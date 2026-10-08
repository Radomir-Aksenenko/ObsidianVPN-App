/// Client connection settings. Mirrors Go `obsidian.ClientConfig`
/// (core/obsidian/uri.go): JSON names and omitempty behaviour follow the Go
/// struct tags. `clientPublicKey` is an app-only field (JSON `client_public_key`)
/// that the desktop app also stores; Go ignores it.
class ClientConfig {
  const ClientConfig({
    this.protocolVersion = 0,
    this.serverHost = '',
    this.serverPort = '',
    this.serverPublicKey = '',
    this.clientPrivateKey = '',
    this.clientPublicKey = '',
    this.noTls = false,
    this.realityEnabled = false,
    this.realityAuthKey = '',
    this.realitySni = '',
    this.fingerprint = '',
    this.sni = '',
    this.sniPool = const [],
    this.verifyTls = false,
    this.tunInterface = '',
    this.tunAddress = '',
    this.dns = '',
    this.mtu = 0,
    this.noiseMinSec = 0,
    this.noiseMaxSec = 0,
    this.keepaliveSec = 0,
    this.jitter = '',
    this.profile = '',
    this.junkCount = 0,
    this.junkMin = 0,
    this.junkMax = 0,
    this.signatures = const [],
    this.h1Min = 0,
    this.h1Max = 0,
    this.h4Min = 0,
    this.h4Max = 0,
    this.routeIps = const [],
    this.splitTunnelMode = '',
    this.splitSites = const [],
    this.splitApps = const [],
    this.splitProcesses = const [],
    this.udpPort = '',
    this.enableUdpData = false,
    this.portPool = const [],
    this.portHopIntervalSec = 0,
    this.maxTrailer = 0,
    this.useBucketPadding = false,
    this.bucketMtu = 0,
    this.enableIpv6 = false,
    this.keyserver = '',
    this.token = '',
    this.expires = '',
    this.maxDevices = 0,
    this.label = '',
  });

  /// Decodes the JSON produced by Go `json.Marshal(ClientConfig)`. Missing
  /// fields take Go zero values, the same as `json.Unmarshal` into a zero struct.
  factory ClientConfig.fromJson(Map<String, dynamic> json) {
    return ClientConfig(
      protocolVersion: _int(json['protocol_version']),
      serverHost: _str(json['server_host']),
      serverPort: _str(json['server_port']),
      serverPublicKey: _str(json['server_public_key']),
      clientPrivateKey: _str(json['client_private_key']),
      clientPublicKey: _str(json['client_public_key']),
      noTls: _bool(json['no_tls']),
      realityEnabled: _bool(json['reality_enabled']),
      realityAuthKey: _str(json['reality_auth_key']),
      realitySni: _str(json['reality_sni']),
      fingerprint: _str(json['fingerprint']),
      sni: _str(json['sni']),
      sniPool: _strList(json['sni_pool']),
      verifyTls: _bool(json['verify_tls']),
      tunInterface: _str(json['tun_interface']),
      tunAddress: _str(json['tun_address']),
      dns: _str(json['dns']),
      mtu: _int(json['mtu']),
      noiseMinSec: _double(json['noise_min_sec']),
      noiseMaxSec: _double(json['noise_max_sec']),
      keepaliveSec: _double(json['keepalive_sec']),
      jitter: _str(json['jitter']),
      profile: _str(json['profile']),
      junkCount: _int(json['junk_count']),
      junkMin: _int(json['junk_min']),
      junkMax: _int(json['junk_max']),
      signatures: _strList(json['signatures']),
      h1Min: _int(json['h1_min']),
      h1Max: _int(json['h1_max']),
      h4Min: _int(json['h4_min']),
      h4Max: _int(json['h4_max']),
      routeIps: _strList(json['route_ips']),
      splitTunnelMode: _str(json['split_tunnel_mode']),
      splitSites: _strList(json['split_sites']),
      splitApps: _strList(json['split_apps']),
      splitProcesses: _strList(json['split_processes']),
      udpPort: _str(json['udp_port']),
      enableUdpData: _bool(json['enable_udp_data']),
      portPool: _intList(json['port_pool']),
      portHopIntervalSec: _int(json['port_hop_interval_sec']),
      maxTrailer: _int(json['max_trailer']),
      useBucketPadding: _bool(json['use_bucket_padding']),
      bucketMtu: _int(json['bucket_mtu']),
      enableIpv6: _bool(json['enable_ipv6']),
      keyserver: _str(json['_keyserver']),
      token: _str(json['_token']),
      expires: _str(json['_expires']),
      maxDevices: _int(json['_max_devices']),
      label: _str(json['_label']),
    );
  }

  final int protocolVersion;
  final String serverHost;
  final String serverPort;
  final String serverPublicKey;
  final String clientPrivateKey;
  final String clientPublicKey;
  final bool noTls;
  final bool realityEnabled;
  final String realityAuthKey;
  final String realitySni;
  final String fingerprint;
  final String sni;
  final List<String> sniPool;
  final bool verifyTls;
  final String tunInterface;
  final String tunAddress;
  final String dns;
  final int mtu;
  final double noiseMinSec;
  final double noiseMaxSec;
  final double keepaliveSec;
  final String jitter;
  final String profile;
  final int junkCount;
  final int junkMin;
  final int junkMax;
  final List<String> signatures;
  final int h1Min;
  final int h1Max;
  final int h4Min;
  final int h4Max;
  final List<String> routeIps;
  final String splitTunnelMode;
  final List<String> splitSites;
  final List<String> splitApps;
  final List<String> splitProcesses;
  final String udpPort;
  final bool enableUdpData;
  final List<int> portPool;
  final int portHopIntervalSec;
  final int maxTrailer;
  final bool useBucketPadding;
  final int bucketMtu;
  final bool enableIpv6;

  /// Key server URL (JSON `_keyserver`).
  final String keyserver;

  /// Subscription token (JSON `_token`).
  final String token;

  /// Expiry, as stored in the key (JSON `_expires`).
  final String expires;

  /// Device limit (JSON `_max_devices`).
  final int maxDevices;

  /// Human-readable label (JSON `_label`).
  final String label;

  /// Encodes like Go `json.Marshal`: fields tagged omitempty are dropped when
  /// they hold their zero value. The four untagged fields are always written.
  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'protocol_version': protocolVersion,
      'server_host': serverHost,
      'server_port': serverPort,
      'server_public_key': serverPublicKey,
    };
    _putStr(m, 'client_private_key', clientPrivateKey);
    _putBool(m, 'no_tls', noTls);
    _putBool(m, 'reality_enabled', realityEnabled);
    _putStr(m, 'reality_auth_key', realityAuthKey);
    _putStr(m, 'reality_sni', realitySni);
    _putStr(m, 'fingerprint', fingerprint);
    _putStr(m, 'sni', sni);
    _putList(m, 'sni_pool', sniPool);
    _putBool(m, 'verify_tls', verifyTls);
    _putStr(m, 'tun_interface', tunInterface);
    _putStr(m, 'tun_address', tunAddress);
    _putStr(m, 'dns', dns);
    _putInt(m, 'mtu', mtu);
    _putDouble(m, 'noise_min_sec', noiseMinSec);
    _putDouble(m, 'noise_max_sec', noiseMaxSec);
    _putDouble(m, 'keepalive_sec', keepaliveSec);
    _putStr(m, 'jitter', jitter);
    _putStr(m, 'profile', profile);
    _putInt(m, 'junk_count', junkCount);
    _putInt(m, 'junk_min', junkMin);
    _putInt(m, 'junk_max', junkMax);
    _putList(m, 'signatures', signatures);
    _putInt(m, 'h1_min', h1Min);
    _putInt(m, 'h1_max', h1Max);
    _putInt(m, 'h4_min', h4Min);
    _putInt(m, 'h4_max', h4Max);
    _putList(m, 'route_ips', routeIps);
    _putStr(m, 'split_tunnel_mode', splitTunnelMode);
    _putList(m, 'split_sites', splitSites);
    _putList(m, 'split_apps', splitApps);
    _putList(m, 'split_processes', splitProcesses);
    _putStr(m, 'udp_port', udpPort);
    _putBool(m, 'enable_udp_data', enableUdpData);
    _putList(m, 'port_pool', portPool);
    _putInt(m, 'port_hop_interval_sec', portHopIntervalSec);
    _putInt(m, 'max_trailer', maxTrailer);
    _putBool(m, 'use_bucket_padding', useBucketPadding);
    _putInt(m, 'bucket_mtu', bucketMtu);
    _putBool(m, 'enable_ipv6', enableIpv6);
    _putStr(m, '_keyserver', keyserver);
    _putStr(m, '_token', token);
    _putStr(m, '_expires', expires);
    _putInt(m, '_max_devices', maxDevices);
    _putStr(m, '_label', label);
    _putStr(m, 'client_public_key', clientPublicKey);
    return m;
  }

  ClientConfig copyWith({
    int? protocolVersion,
    String? serverHost,
    String? serverPort,
    String? serverPublicKey,
    String? clientPrivateKey,
    String? clientPublicKey,
    bool? noTls,
    bool? realityEnabled,
    String? realityAuthKey,
    String? realitySni,
    String? fingerprint,
    String? sni,
    List<String>? sniPool,
    bool? verifyTls,
    String? tunInterface,
    String? tunAddress,
    String? dns,
    int? mtu,
    double? noiseMinSec,
    double? noiseMaxSec,
    double? keepaliveSec,
    String? jitter,
    String? profile,
    int? junkCount,
    int? junkMin,
    int? junkMax,
    List<String>? signatures,
    int? h1Min,
    int? h1Max,
    int? h4Min,
    int? h4Max,
    List<String>? routeIps,
    String? splitTunnelMode,
    List<String>? splitSites,
    List<String>? splitApps,
    List<String>? splitProcesses,
    String? udpPort,
    bool? enableUdpData,
    List<int>? portPool,
    int? portHopIntervalSec,
    int? maxTrailer,
    bool? useBucketPadding,
    int? bucketMtu,
    bool? enableIpv6,
    String? keyserver,
    String? token,
    String? expires,
    int? maxDevices,
    String? label,
  }) {
    return ClientConfig(
      protocolVersion: protocolVersion ?? this.protocolVersion,
      serverHost: serverHost ?? this.serverHost,
      serverPort: serverPort ?? this.serverPort,
      serverPublicKey: serverPublicKey ?? this.serverPublicKey,
      clientPrivateKey: clientPrivateKey ?? this.clientPrivateKey,
      clientPublicKey: clientPublicKey ?? this.clientPublicKey,
      noTls: noTls ?? this.noTls,
      realityEnabled: realityEnabled ?? this.realityEnabled,
      realityAuthKey: realityAuthKey ?? this.realityAuthKey,
      realitySni: realitySni ?? this.realitySni,
      fingerprint: fingerprint ?? this.fingerprint,
      sni: sni ?? this.sni,
      sniPool: sniPool ?? this.sniPool,
      verifyTls: verifyTls ?? this.verifyTls,
      tunInterface: tunInterface ?? this.tunInterface,
      tunAddress: tunAddress ?? this.tunAddress,
      dns: dns ?? this.dns,
      mtu: mtu ?? this.mtu,
      noiseMinSec: noiseMinSec ?? this.noiseMinSec,
      noiseMaxSec: noiseMaxSec ?? this.noiseMaxSec,
      keepaliveSec: keepaliveSec ?? this.keepaliveSec,
      jitter: jitter ?? this.jitter,
      profile: profile ?? this.profile,
      junkCount: junkCount ?? this.junkCount,
      junkMin: junkMin ?? this.junkMin,
      junkMax: junkMax ?? this.junkMax,
      signatures: signatures ?? this.signatures,
      h1Min: h1Min ?? this.h1Min,
      h1Max: h1Max ?? this.h1Max,
      h4Min: h4Min ?? this.h4Min,
      h4Max: h4Max ?? this.h4Max,
      routeIps: routeIps ?? this.routeIps,
      splitTunnelMode: splitTunnelMode ?? this.splitTunnelMode,
      splitSites: splitSites ?? this.splitSites,
      splitApps: splitApps ?? this.splitApps,
      splitProcesses: splitProcesses ?? this.splitProcesses,
      udpPort: udpPort ?? this.udpPort,
      enableUdpData: enableUdpData ?? this.enableUdpData,
      portPool: portPool ?? this.portPool,
      portHopIntervalSec: portHopIntervalSec ?? this.portHopIntervalSec,
      maxTrailer: maxTrailer ?? this.maxTrailer,
      useBucketPadding: useBucketPadding ?? this.useBucketPadding,
      bucketMtu: bucketMtu ?? this.bucketMtu,
      enableIpv6: enableIpv6 ?? this.enableIpv6,
      keyserver: keyserver ?? this.keyserver,
      token: token ?? this.token,
      expires: expires ?? this.expires,
      maxDevices: maxDevices ?? this.maxDevices,
      label: label ?? this.label,
    );
  }
}

String _str(Object? v) {
  if (v is String) return v;
  if (v is num) return _numToString(v);
  return '';
}

int _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

double _double(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

bool _bool(Object? v) => v is bool ? v : false;

List<String> _strList(Object? v) {
  if (v is! List) return const [];
  return [for (final e in v) _str(e)];
}

List<int> _intList(Object? v) {
  if (v is! List) return const [];
  return [for (final e in v) _int(e)];
}

/// Integral doubles are written without a fraction, as Go writes float64 10 as `10`.
Object _jsonNum(double d) {
  if (d == d.truncateToDouble() && d.abs() < 1e15) return d.toInt();
  return d;
}

String _numToString(num n) {
  if (n is int) return n.toString();
  if (n == n.truncateToDouble() && n.abs() < 1e15) return n.toInt().toString();
  return n.toString();
}

void _putStr(Map<String, dynamic> m, String key, String value) {
  if (value.isNotEmpty) m[key] = value;
}

void _putBool(Map<String, dynamic> m, String key, bool value) {
  if (value) m[key] = true;
}

void _putInt(Map<String, dynamic> m, String key, int value) {
  if (value != 0) m[key] = value;
}

void _putDouble(Map<String, dynamic> m, String key, double value) {
  if (value != 0) m[key] = _jsonNum(value);
}

void _putList<T>(Map<String, dynamic> m, String key, List<T> value) {
  if (value.isNotEmpty) m[key] = value;
}
