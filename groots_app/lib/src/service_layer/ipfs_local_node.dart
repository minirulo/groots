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

/// Manages a local Kubo (go-ipfs) daemon.
///
/// On macOS, process management is delegated to the KuboHelper XPC service
/// via the "groots/kubo" MethodChannel.
///
/// On Linux, the Kubo binary is spawned directly as a child process. The
/// binary is resolved from (in order):
///   1. Alongside the app executable (bundled).
///   2. System PATH (`ipfs`).
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
  Process? _daemonProcess;

  String get _apiUrl => 'http://127.0.0.1:$_apiPort';
  String get _gatewayUrl => 'http://127.0.0.1:$_gatewayPort';

  static bool get _supported => Platform.isMacOS || Platform.isLinux;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    if (!_supported) return;
    if (Platform.isMacOS) {
      _channel.setMethodCallHandler(_handleNativeCall);
    }
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (status.value == IpfsNodeStatus.starting ||
          status.value == IpfsNodeStatus.stopping) {
        return;
      }
      final reachable = await _isApiReachable();
      if (reachable != isRunning.value) {
        isRunning.value = reachable;
        status.value = reachable
            ? IpfsNodeStatus.running
            : IpfsNodeStatus.stopped;
        _log(
          reachable ? 'node detected as running' : 'node detected as stopped',
        );
      }
    });
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Start the local Kubo daemon. Idempotent — safe to call if already running.
  Future<void> start() async {
    if (!_supported) return;
    if (isRunning.value || status.value == IpfsNodeStatus.starting) return;

    status.value = IpfsNodeStatus.starting;

    if (Platform.isLinux) {
      await _startLinux();
    } else {
      await _startMacOS();
    }
  }

  /// Gracefully stop the daemon.
  Future<void> stop() async {
    if (!_supported) return;
    if (!isRunning.value || status.value == IpfsNodeStatus.stopping) return;
    status.value = IpfsNodeStatus.stopping;
    if (Platform.isLinux) {
      await _stopLinux();
    } else {
      await _stopMacOS();
    }
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
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'registerLoginItem',
      );
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
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'unregisterLoginItem',
      );
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
        _log(
          'connectToCentralNode: peer-id request failed (${res.statusCode})',
        );
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

  // ── macOS (XPC) ───────────────────────────────────────────────────────────

  Future<void> _startMacOS() async {
    final repoPath = await _resolveRepoPath();
    final swarmKey = await rootBundle.loadString('assets/swarm.key');

    _log('starting via XPC (repo → $repoPath)');

    final result = await _channel.invokeMapMethod<String, dynamic>('start', {
      'repo_path': repoPath,
      'swarm_key': swarmKey,
      'gateway_port': _gatewayPort,
    });

    if (result?['success'] != true) {
      _log('XPC start failed: ${result?['error']}');
      status.value = IpfsNodeStatus.stopped;
      return;
    }

    await _waitUntilReady();
    isRunning.value = true;
    status.value = IpfsNodeStatus.running;
    _log('local node ready — gateway $_gatewayUrl');
    await connectToCentralNode();
  }

  Future<void> _stopMacOS() async {
    await _channel.invokeMethod<void>('stop');
    isRunning.value = false;
    status.value = IpfsNodeStatus.stopped;
    _log('daemon stopped');
  }

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

  // ── Linux (subprocess) ────────────────────────────────────────────────────

  Future<void> _startLinux() async {
    final ipfsBin = await _resolveIpfsBinary();
    if (ipfsBin == null) {
      _log('ipfs binary not found — place kubo binary at linux/bin/ipfs');
      status.value = IpfsNodeStatus.stopped;
      return;
    }

    final repoPath = await _resolveRepoPath();
    final env = {'IPFS_PATH': repoPath};

    // Shut down any daemon left over from a previous session (hot restart,
    // crash) that still holds the port. Using the API is cleaner than kill.
    if (await _isApiReachable()) {
      _log('stale daemon detected on port $_apiPort — sending shutdown');
      final client = HttpClient();
      try {
        final req = await client.postUrl(Uri.parse('$_apiUrl/api/v0/shutdown'));
        final res = await req.close();
        await res.drain<void>();
      } catch (_) {
      } finally {
        client.close();
      }
      // Wait for the port to be released before proceeding.
      const maxWait = Duration(seconds: 10);
      final deadline = DateTime.now().add(maxWait);
      while (DateTime.now().isBefore(deadline) && await _isApiReachable()) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }

    // Remove stale lock left by a previous crash so the daemon can start.
    final lockFile = File('$repoPath/repo.lock');
    if (lockFile.existsSync()) {
      _log('removing stale repo.lock');
      lockFile.deleteSync();
    }

    // First-run: initialize repo, write swarm key, set ports.
    if (!File('$repoPath/config').existsSync()) {
      _log('initializing repo at $repoPath');
      await Process.run(ipfsBin, [
        'init',
        '--profile=server',
      ], environment: env);

      final swarmKey = await rootBundle.loadString('assets/swarm.key');
      File('$repoPath/swarm.key').writeAsStringSync(swarmKey);

      // Private network — remove all public bootstrap peers.
      await Process.run(ipfsBin, [
        'bootstrap',
        'rm',
        '--all',
      ], environment: env);

      // Custom ports to avoid collisions with the Docker dev stack.
      await Process.run(ipfsBin, [
        'config',
        'Addresses.API',
        '/ip4/127.0.0.1/tcp/$_apiPort',
      ], environment: env);
      await Process.run(ipfsBin, [
        'config',
        'Addresses.Gateway',
        '/ip4/127.0.0.1/tcp/$_gatewayPort',
      ], environment: env);
      await Process.run(ipfsBin, [
        'config',
        '--json',
        'Addresses.Swarm',
        '["/ip4/0.0.0.0/tcp/4101","/ip6/::/tcp/4101"]',
      ], environment: env);
    }

    // Applied every launch — idempotent. Kubo 0.34+ defaults are incompatible
    // with swarm.key private networks: AutoTLS connection-gates peers without
    // ACME certs (blocks the Docker node), Websocket conflicts with PNET,
    // and Routing.Type=auto falls back to dht anyway but logs errors.
    // AddrFilters: --profile=server blocks all RFC-1918 ranges including
    // 10.0.0.0/8, which covers the Docker node at 10.10.10.x.
    // Kubo 0.34+ / migration-introduced defaults incompatible with private networks.
    // All applied every launch so existing repos are fixed without re-init.
    await Process.run(ipfsBin, [
      'config',
      '--json',
      'AutoTLS.Enabled',
      'false',
    ], environment: env);
    await Process.run(ipfsBin, [
      'config',
      '--json',
      'AutoConf.Enabled',
      'false',
    ], environment: env);
    // Repo migration to v18 writes 'auto' placeholders that require AutoConf.
    // For a private swarm none of these are needed.
    await Process.run(ipfsBin, [
      'config',
      '--json',
      'Bootstrap',
      '[]',
    ], environment: env);
    await Process.run(ipfsBin, [
      'config',
      '--json',
      'Routing.DelegatedRouters',
      '[]',
    ], environment: env);
    await Process.run(ipfsBin, [
      'config',
      '--json',
      'Ipns.DelegatedPublishers',
      '[]',
    ], environment: env);
    await Process.run(ipfsBin, [
      'config',
      '--json',
      'DNS.Resolvers',
      '{}',
    ], environment: env);
    await Process.run(ipfsBin, [
      'config',
      '--json',
      'Swarm.Transports.Network.Websocket',
      'false',
    ], environment: env);
    await Process.run(ipfsBin, [
      'config',
      'Routing.Type',
      'dht',
    ], environment: env);
    await Process.run(ipfsBin, [
      'config',
      '--json',
      'Swarm.AddrFilters',
      '[]',
    ], environment: env);

    _log('starting daemon (repo → $repoPath, bin → $ipfsBin)');
    _daemonProcess = await Process.start(ipfsBin, [
      'daemon',
      '--enable-gc',
      '--migrate',
    ], environment: env);

    _daemonProcess!.stdout
        .transform(utf8.decoder)
        .listen((s) => _log('kubo: ${s.trim()}'));
    _daemonProcess!.stderr
        .transform(utf8.decoder)
        .listen((s) => _log('kubo err: ${s.trim()}'));

    bool processExited = false;
    _daemonProcess!.exitCode.then((code) {
      processExited = true;
      if (status.value != IpfsNodeStatus.stopping) {
        _log('daemon exited unexpectedly (code $code)');
        isRunning.value = false;
        status.value = IpfsNodeStatus.stopped;
      }
    });

    await _waitUntilReady(shouldAbort: () => processExited);

    if (processExited) return; // daemon died during startup, already logged

    isRunning.value = true;
    status.value = IpfsNodeStatus.running;
    _log('local node ready — gateway $_gatewayUrl');
    await connectToCentralNode();
  }

  Future<void> _stopLinux() async {
    _daemonProcess?.kill(ProcessSignal.sigterm);
    await _daemonProcess?.exitCode;
    _daemonProcess = null;
    isRunning.value = false;
    status.value = IpfsNodeStatus.stopped;
    _log('daemon stopped');
  }

  /// Resolves the Kubo binary path: bundled next to the executable, then PATH.
  Future<String?> _resolveIpfsBinary() async {
    final execDir = File(Platform.resolvedExecutable).parent.path;
    final bundled = File('$execDir/ipfs');
    if (bundled.existsSync()) return bundled.path;

    final result = await Process.run('which', ['ipfs']);
    if (result.exitCode == 0) {
      final path = (result.stdout as String).trim();
      if (path.isNotEmpty) return path;
    }

    return null;
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

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
    bool Function()? shouldAbort,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (shouldAbort != null && shouldAbort()) return;
      if (await _isApiReachable()) {
        if (shouldAbort != null && shouldAbort()) return;
        return;
      }
      await Future<void>.delayed(interval);
    }
    _log('WARNING: daemon did not become ready within ${timeout.inSeconds}s');
  }

  void _log(String msg) => debugPrint('[IpfsLocalNode] $msg');
}
