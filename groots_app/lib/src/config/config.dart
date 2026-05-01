abstract class BaseConfig {
  String get apiHost;
  String get appName;
  String get ipfsGatewayHost;

  /// IP/hostname of the central IPFS swarm port.
  /// Used by the Mac local node to explicitly connect to the Docker peer.
  /// Returns null in production — no local daemon in prod.
  String? get ipfsSwarmHost => null;

  /// TCP port of the central IPFS swarm endpoint.
  /// Dev uses 4001 (direct Docker); prod uses 4002 (nginx stream proxy).
  int get ipfsSwarmPort => 4001;

  /// Local Kubo gateway port (used by the macOS embedded node).
  /// Dev = 8180, Prod = 8280 — kept separate so both flavours can coexist on the same machine.
  int get localGatewayPort => 8180;

  String get apiBaseUrl => 'http://$apiHost/api';

  /// Appending ?filename=track.ext forces Kubo to set the correct
  /// Content-Type header, which AVFoundation requires to decode the stream.
  String ipfsStreamUrl(String cid, String mimeType) {
    final ext = BaseConfig.extForMime(mimeType);
    return 'http://$ipfsGatewayHost/ipfs/$cid?filename=track$ext';
  }

  static String extForMime(String mime) => switch (mime) {
    'audio/mpeg' => '.mp3',
    'audio/flac' => '.flac',
    'audio/aac' => '.aac',
    'audio/ogg' => '.ogg',
    'audio/wav' => '.wav',
    'audio/mp4' => '.m4a',
    'audio/opus' => '.opus',
    _ => '.mp3',
  };
}

class DevConfig extends BaseConfig {
  @override
  String get apiHost => '192.168.0.190:8001';

  @override
  String get appName => 'Groots Dev';

  @override
  String get ipfsGatewayHost => '192.168.0.190:8080';

  @override
  // Same machine as the API — Docker exposes swarm on port 4001.
  String get ipfsSwarmHost => '192.168.0.190';
}

class ProdConfig extends BaseConfig {
  @override
  String get apiHost => 'api.groots.rce-studio.com';

  @override
  int get localGatewayPort => 8280;

  @override
  String get appName => 'Groots';

  @override
  String get ipfsGatewayHost => 'gateway.groots.rce-studio.com';

  @override
  String? get ipfsSwarmHost => 'swarm.groots.rce-studio.com';

  @override
  int get ipfsSwarmPort => 4002;

  @override
  String get apiBaseUrl => 'https://$apiHost/api';

  @override
  String ipfsStreamUrl(String cid, String mimeType) {
    final ext = BaseConfig.extForMime(mimeType);
    return 'https://$ipfsGatewayHost/ipfs/$cid?filename=track$ext';
  }
}
