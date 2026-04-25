import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import '../config/config.dart';
import '../config/environment.dart';

/// Status of the local IPFS node lifecycle.
enum IpfsNodeStatus { stopped, starting, running, stopping }

/// Manages a local Kubo (go-ipfs) daemon on macOS via the KuboHelper XPC
/// service bundled inside the app.
///
/// All process management (init, configure, spawn, stop) is delegated to the
/// XPC service through the "groots/kubo" MethodChannel. This file only
/// handles:
///   • resolving the repo path and reading the swarm key asset
///   • polling the Kubo HTTP API for readiness after start
///   • building stream / cover-art URLs for the player
///
/// Ports used (chosen to avoid collision with the Docker dev stack):
///   API     → 127.0.0.1:5101
///   Gateway → 127.0.0.1:8180
///   Swarm   → 0.0.0.0:4101
class IpfsLocalNode extends GetxService {
  static const _apiPort = 5101;
  static const _channel = MethodChannel('groots/kubo');

  int get _gatewayPort => Environment().config.localGatewayPort;

  final RxBool isRunning = false.obs;
  final Rx<IpfsNodeStatus> status = IpfsNodeStatus.stopped.obs;

  Timer? _pollTimer;

  String get _apiUrl => 'http://127.0.0.1:$_apiPort';
  String get _gatewayUrl => 'http://127.0.0.1:$_gatewayPort';

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    if (!Platform.isMacOS) return;
    // Allow native side (dock menu) to trigger start/stop on the Dart service.
    _channel.setMethodCallHandler(_handleNativeCall);
    // Poll daemon reachability every 5 s to keep [isRunning] in sync even if
    // the process is started/stopped outside of this service (e.g. dock menu).
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) async {
        // Only probe when not in the middle of a transition.
        if (status.value == IpfsNodeStatus.starting ||
            status.value == IpfsNodeStatus.stopping) {
          return;
        }
        final reachable = await _isApiReachable();
        if (reachable != isRunning.value) {
          isRunning.value = reachable;
          status.value =
              reachable ? IpfsNodeStatus.running : IpfsNodeStatus.stopped;
          _log(reachable ? 'node detected as running' : 'node detected as stopped');
        }
      },
    );
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Start the local Kubo daemon. Idempotent — safe to call if already running.
  /// No-op on non-macOS platforms (XPC helper is macOS-only).
  Future<void> start() async {
    if (!Platform.isMacOS) return;
    if (isRunning.value || status.value == IpfsNodeStatus.starting) return;

    status.value = IpfsNodeStatus.starting;

    final repoPath = await _resolveRepoPath();
    final swarmKey = await rootBundle.loadString('assets/swarm.key');

    _log('starting via XPC (repo → $repoPath)');

    final result = await _channel.invokeMapMethod<String, dynamic>(
      'start',
      {
        'repo_path': repoPath,
        'swarm_key': swarmKey,
        'gateway_port': _gatewayPort,
      },
    );

    if (result?['success'] != true) {
      _log('XPC start failed: ${result?['error']}');
      status.value = IpfsNodeStatus.stopped;
      return;
    }

    await _waitUntilReady();
    isRunning.value = true;
    status.value = IpfsNodeStatus.running;
    _log('local node ready — gateway $_gatewayUrl');

    // Connect to the central cluster node regardless of how start() was triggered
    // (launch callback, dock menu, or status indicator tap).
    await connectToCentralNode();
  }

  /// Gracefully stop the daemon.
  Future<void> stop() async {
    if (!Platform.isMacOS) return;
    if (!isRunning.value || status.value == IpfsNodeStatus.stopping) return;
    status.value = IpfsNodeStatus.stopping;
    await _channel.invokeMethod<void>('stop');
    isRunning.value = false;
    status.value = IpfsNodeStatus.stopped;
    _log('daemon stopped');
  }

  /// Returns a streaming URL for [cid].
  String streamUrl(String cid, String mimeType) {
    if (isRunning.value) {
      final ext = BaseConfig.extForMime(mimeType);
      return '$_gatewayUrl/ipfs/$cid?filename=track$ext';
    }
    return Environment().config.ipfsStreamUrl(cid, mimeType);
  }

  /// Returns a cover-art URL for [cid].
  String coverUrl(String cid) {
    if (isRunning.value) return '$_gatewayUrl/ipfs/$cid';
    return 'http://${Environment().config.ipfsGatewayHost}/ipfs/$cid';
  }

  /// Register the app as a macOS Login Item so the IPFS daemon starts at boot.
  /// Returns null on success, or an error message on failure.
  /// Unsupported on non-macOS platforms.
  Future<String?> installAsLoginItem() async {
    if (!Platform.isMacOS) return 'Login Items are only supported on macOS.';
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('registerLoginItem');
      return result?['error'] as String?;
    } on PlatformException catch (e) {
      return e.message;
    }
  }

  /// Remove the app from macOS Login Items.
  /// Unsupported on non-macOS platforms.
  Future<String?> uninstallLoginItem() async {
    if (!Platform.isMacOS) return 'Login Items are only supported on macOS.';
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('unregisterLoginItem');
      return result?['error'] as String?;
    } on PlatformException catch (e) {
      return e.message;
    }
  }

  /// Pin a CID on the local node so it survives the central node going offline.
  Future<void> pinAdd(String cid) async {
    if (!isRunning.value) return;
    final client = HttpClient();
    try {
      final req = await client.postUrl(
        Uri.parse('$_apiUrl/api/v0/pin/add?arg=$cid&recursive=true'),
      );
      final res = await req.close();
      await res.drain<void>();
      if (res.statusCode != 200) {
        _log('pinAdd failed for $cid — status ${res.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  /// Manually connect to another peer (e.g. the central Docker node).
  Future<void> connectToPeer(String multiaddr) async {
    if (!isRunning.value) return;
    final client = HttpClient();
    try {
      final req = await client.postUrl(
        Uri.parse(
          '$_apiUrl/api/v0/swarm/connect?arg=${Uri.encodeComponent(multiaddr)}',
        ),
      );
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      _log('swarm connect → $multiaddr  result: $body');
    } finally {
      client.close();
    }
  }

  /// Fetch the central node's peer ID from the API and connect to it.
  Future<void> connectToCentralNode() async {
    final swarmHost = Environment().config.ipfsSwarmHost;
    if (swarmHost == null) {
      _log('connectToCentralNode: no swarm host configured, skipping');
      return;
    }

    if (!isRunning.value) {
      _log('connectToCentralNode: local node not running, skipping');
      return;
    }

    final apiBase = Environment().config.apiBaseUrl;
    _log('connectToCentralNode: fetching peer ID from $apiBase/ipfs/peer-id');
    final client = HttpClient();
    try {
      final req = await client
          .getUrl(Uri.parse('$apiBase/ipfs/peer-id'))
          .timeout(const Duration(seconds: 5));
      req.headers.set('Accept', 'application/json');
      final res = await req.close();
      if (res.statusCode != 200) {
        _log('connectToCentralNode: peer-id request failed (${res.statusCode})');
        return;
      }
      final body = await res.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final peerId = data['peer_id'] as String?;
      if (peerId == null || peerId.isEmpty) {
        _log('connectToCentralNode: empty peer_id in response');
        return;
      }
      final isIp = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(swarmHost);
      final proto = isIp ? 'ip4' : 'dns4';
      final swarmPort = Environment().config.ipfsSwarmPort;
      await connectToPeer('/$proto/$swarmHost/tcp/$swarmPort/p2p/$peerId');
    } on TimeoutException {
      _log('connectToCentralNode: timed out fetching peer ID');
    } catch (e) {
      _log('connectToCentralNode: $e');
    } finally {
      client.close();
    }
  }

  @override
  Future<void> onClose() async {
    _pollTimer?.cancel();
    await stop();
    super.onClose();
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Handles method calls initiated from the native side (e.g. dock menu).
  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'startFromNative':
        await start();
      case 'stopFromNative':
        await stop();
      default:
        throw PlatformException(
          code: 'NOT_IMPLEMENTED',
          message: 'Unknown native call: ${call.method}',
        );
    }
  }

  Future<String> _resolveRepoPath() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/ipfs-node');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  Future<bool> _isApiReachable() async {
    final client = HttpClient();
    try {
      final req = await client
          .postUrl(Uri.parse('$_apiUrl/api/v0/id'))
          .timeout(const Duration(seconds: 2));
      final res = await req.close();
      await res.drain<void>();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  Future<void> _waitUntilReady({
    Duration timeout = const Duration(seconds: 30),
    Duration interval = const Duration(milliseconds: 500),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _isApiReachable()) return;
      await Future<void>.delayed(interval);
    }
    _log('WARNING: daemon did not become ready within ${timeout.inSeconds}s');
  }

  void _log(String msg) => debugPrint('[IpfsLocalNode] $msg');
}
