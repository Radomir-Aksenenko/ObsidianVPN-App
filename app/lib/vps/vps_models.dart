import 'package:obsidian_vpn/core/codec/client_config.dart';

/// Default REALITY mask (SNI) used when the user does not pick one.
const String kDefaultSni = 'www.microsoft.com';

/// SSH login to a VPS. Immutable.
///
/// Secrets (password, private key PEM, passphrase) must be kept only in
/// flutter_secure_storage. [toJson] includes them, so never write its output to
/// a plain file. [toString] never prints secrets.
class VpsCredentials {
  const VpsCredentials({
    required this.host,
    this.port = 22,
    this.user = 'root',
    this.password,
    this.privateKeyPem,
    this.passphrase,
    this.hostKeyFingerprint,
  });

  factory VpsCredentials.fromJson(Map<String, dynamic> json) {
    return VpsCredentials(
      host: _str(json['host']),
      port: _int(json['port'], 22),
      user: _str(json['user'], 'root'),
      password: _strOrNull(json['password']),
      privateKeyPem: _strOrNull(json['privateKeyPem']),
      passphrase: _strOrNull(json['passphrase']),
      hostKeyFingerprint: _strOrNull(json['hostKeyFingerprint']),
    );
  }

  final String host;
  final int port;
  final String user;
  final String? password;
  final String? privateKeyPem;
  final String? passphrase;

  /// OpenSSH-style SHA256 fingerprint ("SHA256:...") pinned on first use.
  /// Null means the server has not been seen yet.
  final String? hostKeyFingerprint;

  /// True when key auth should be used (a non-empty PEM is present).
  bool get usesKey => (privateKeyPem ?? '').trim().isNotEmpty;

  VpsCredentials copyWith({
    String? host,
    int? port,
    String? user,
    String? password,
    String? privateKeyPem,
    String? passphrase,
    String? hostKeyFingerprint,
  }) {
    return VpsCredentials(
      host: host ?? this.host,
      port: port ?? this.port,
      user: user ?? this.user,
      password: password ?? this.password,
      privateKeyPem: privateKeyPem ?? this.privateKeyPem,
      passphrase: passphrase ?? this.passphrase,
      hostKeyFingerprint: hostKeyFingerprint ?? this.hostKeyFingerprint,
    );
  }

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'user': user,
        if (password != null) 'password': password,
        if (privateKeyPem != null) 'privateKeyPem': privateKeyPem,
        if (passphrase != null) 'passphrase': passphrase,
        if (hostKeyFingerprint != null) 'hostKeyFingerprint': hostKeyFingerprint,
      };

  @override
  String toString() => 'VpsCredentials($user@$host:$port)';
}

/// Input of a fresh deploy.
class DeployRequest {
  const DeployRequest({required this.creds, this.sni = kDefaultSni});

  final VpsCredentials creds;
  final String sni;
}

/// Outcome of a successful deploy. Contains secrets (owner key, admin token).
class DeployResult {
  const DeployResult({
    required this.ownerKey,
    required this.ownerConfig,
    required this.adminToken,
    required this.tcpPort,
    required this.udpPort,
    required this.sni,
    required this.ipv6,
    required this.serverVersion,
    required this.hostKeyFingerprint,
  });

  /// OBSDN key for the owner device (3 devices, no expiry).
  final String ownerKey;
  final ClientConfig ownerConfig;

  /// Keyserver admin token (24 random bytes, hex).
  final String adminToken;
  final int tcpPort;
  final int udpPort;
  final String sni;
  final bool ipv6;

  /// Version of the core that was installed.
  final String serverVersion;

  /// SHA256 fingerprint of the server host key. Store it for later connections.
  final String hostKeyFingerprint;
}

/// Outcome of an in-place core update.
class UpdateResult {
  const UpdateResult({
    required this.tcpPort,
    required this.udpPort,
    required this.realityEnabled,
    required this.realityAuthKey,
    required this.sni,
    required this.ipv6,
  });

  final int tcpPort;
  final int udpPort;
  final bool realityEnabled;
  final String realityAuthKey;
  final String sni;
  final bool ipv6;
}

/// Outcome of a server reset. The owner key is rebuilt for the new keys.
class ResetResult {
  const ResetResult({
    required this.serverPublicKey,
    required this.realityAuthKey,
    required this.realitySni,
    required this.ownerKey,
    required this.ownerConfig,
  });

  final String serverPublicKey;
  final String realityAuthKey;
  final String realitySni;
  final String ownerKey;
  final ClientConfig ownerConfig;
}

/// Installed-core status from [VpsDeployer.checkVersion].
class VpsStatus {
  const VpsStatus({
    required this.installed,
    required this.upToDate,
    required this.version,
  });

  final bool installed;
  final bool upToDate;
  final String version;
}

/// Events emitted by every long VPS operation. A stream ends with exactly one
/// [DeployFinished] on success, or with an error ([VpsException]) on failure.
sealed class DeployEvent {
  const DeployEvent();
}

/// Progress 0..100 with a Russian step label.
final class DeployProgress extends DeployEvent {
  const DeployProgress(this.percent, this.stepRu);

  final int percent;
  final String stepRu;
}

/// One line of the remote log. Never contains passwords, keys or tokens.
final class DeployLog extends DeployEvent {
  const DeployLog(this.line);

  final String line;
}

/// Final value of the operation.
final class DeployFinished<T> extends DeployEvent {
  const DeployFinished(this.value);

  final T value;
}

/// Shortcut: waits for the stream and returns the value of its [DeployFinished].
extension DeployStreamResult on Stream<DeployEvent> {
  Future<T> resultOf<T>() async {
    var found = false;
    late T value;
    await for (final event in this) {
      if (event is DeployFinished<T>) {
        value = event.value;
        found = true;
      }
    }
    if (!found) {
      throw const VpsException('Операция завершилась без результата.');
    }
    return value;
  }
}

/// Error with a message ready to show to the user (Russian).
class VpsException implements Exception {
  const VpsException(this.messageRu);

  final String messageRu;

  @override
  String toString() => messageRu;
}

/// The server host key differs from the pinned fingerprint. Connection aborted.
class HostKeyChangedException extends VpsException {
  HostKeyChangedException({required this.expected, required this.actual})
      : super(
          'Отпечаток ключа сервера изменился. Ожидался $expected, получен $actual. '
          'Возможна подмена сервера, подключение прервано.',
        );

  final String expected;
  final String actual;
}

String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;

String? _strOrNull(Object? v) => v is String && v.isNotEmpty ? v : null;

int _int(Object? v, int fallback) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}
