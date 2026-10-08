import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'base32.dart';
import 'client_config.dart';

/// Thrown when a key or link cannot be parsed. [messageRu] is shown to the user.
class KeyFormatException implements Exception {
  const KeyFormatException(this.messageRu);

  final String messageRu;

  @override
  String toString() => messageRu;
}

/// Protocol version written by Go (`obsidian.ProtocolVersion`).
const int kProtocolVersion = 2;

/// Largest MTU accepted for the tunnel (Go ParseURI caps at 1420).
const int kMaxMtu = 1420;

const String kDefaultPort = '8443';
const String kDefaultRealitySni = 'www.microsoft.com';
const String kDefaultTunAddress = '10.8.0.2/24';
const String kServerDns = '10.8.0.1';
const String kPublicDns = '1.1.1.1';

const List<String> kDefaultSignatures = [
  '<b 0xc00000000108><rc 8><b 0x08><rc 8><b 0x0044b000000001><r 1170>',
  '<r 2><b 0x010000010000000000010377777706676f6f676c6503636f6d00000100010000291000000000000000>',
];

/// Defaults from Go `DefaultClientConfig()`.
ClientConfig goDefaultClientConfig() => const ClientConfig(
      protocolVersion: kProtocolVersion,
      tunAddress: kDefaultTunAddress,
      dns: kPublicDns,
      mtu: kMaxMtu,
      profile: 'fast-secure',
      jitter: 'off',
      junkCount: 7,
      junkMin: 50,
      junkMax: 1000,
      noiseMinSec: 10,
      noiseMaxSec: 40,
      keepaliveSec: 20,
      enableUdpData: true,
      signatures: kDefaultSignatures,
    );

const _badUri = 'Не удалось разобрать ссылку. Проверьте, что она скопирована целиком.';
const _badPort = 'Некорректный порт в ссылке.';
const _unsupported =
    'Неподдерживаемый формат. Используйте ссылку obsidian:// или vpn:// либо ключ OBSDN-.';

/// Parses an `obsidian://`, `vpn://`, `vpn://obsidian/` link or an `OBSDN-` key.
///
/// Mirrors Go `obsidian.DecodeKey` / `ParseURI`, including the legacy query
/// aliases (pk, pbk, sid, fp, sig and others). Throws [KeyFormatException].
ClientConfig parseKey(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw const KeyFormatException('Ключ пустой. Вставьте ключ или ссылку.');
  }
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('obsidian://') || lower.startsWith('vpn://')) {
    // Line breaks from copy-paste are dropped; spaces inside a label are kept.
    return _parseUri(trimmed.replaceAll(RegExp(r'[\r\n\t]'), ''));
  }
  if (trimmed.contains('://')) {
    throw const KeyFormatException(_unsupported);
  }
  return _decodeObsdn(trimmed);
}

ClientConfig _parseUri(String raw) {
  final lower = raw.toLowerCase();
  final String rest;
  if (lower.startsWith('vpn://obsidian/')) {
    rest = raw.substring('vpn://obsidian/'.length);
  } else if (lower.startsWith('vpn://')) {
    rest = raw.substring('vpn://'.length);
  } else {
    rest = raw.substring('obsidian://'.length);
  }

  final hashAt = rest.indexOf('#');
  final beforeFragment = hashAt >= 0 ? rest.substring(0, hashAt) : rest;
  final fragmentRaw = hashAt >= 0 ? rest.substring(hashAt + 1) : '';
  final queryAt = beforeFragment.indexOf('?');
  final pathAndAuthority =
      queryAt >= 0 ? beforeFragment.substring(0, queryAt) : beforeFragment;
  final queryRaw = queryAt >= 0 ? beforeFragment.substring(queryAt + 1) : '';
  final slashAt = pathAndAuthority.indexOf('/');
  final authority =
      slashAt >= 0 ? pathAndAuthority.substring(0, slashAt) : pathAndAuthority;

  final atAt = authority.lastIndexOf('@');
  final userinfoRaw = atAt >= 0 ? authority.substring(0, atAt) : '';
  final hostPort = atAt >= 0 ? authority.substring(atAt + 1) : authority;

  final (host, port) = _splitHostPort(hostPort);
  if (host.isEmpty) {
    throw const KeyFormatException('В ссылке не указан адрес сервера.');
  }
  final serverPort = port.isEmpty ? kDefaultPort : port;

  var serverPublicKey = '';
  if (userinfoRaw.isNotEmpty) {
    final userinfo = _percentDecodeOrThrow(userinfoRaw, plusIsSpace: false);
    final username = userinfo.split(':').first;
    if (username.isNotEmpty) serverPublicKey = username.toLowerCase();
  }

  String label = '';
  if (fragmentRaw.isNotEmpty) {
    final fragment = _percentDecodeOrThrow(fragmentRaw, plusIsSpace: false);
    label = _queryUnescapeOrNull(fragment) ?? fragment;
  }

  final q = _parseQuery(queryRaw);
  String first(String key) {
    final values = q[key];
    return values == null || values.isEmpty ? '' : values.first;
  }

  final defaults = goDefaultClientConfig();

  final pk = first('pk');
  if (pk.isNotEmpty) {
    serverPublicKey = pk.toLowerCase();
  } else if (first('pbk').isNotEmpty) {
    serverPublicKey = first('pbk').toLowerCase();
  } else if (first('server_public_key').isNotEmpty) {
    serverPublicKey = first('server_public_key').toLowerCase();
  }
  if (serverPublicKey.isEmpty) {
    throw const KeyFormatException(
        'В ссылке нет публичного ключа сервера. Скопируйте ссылку заново.');
  }

  var udpPort = first('udp_port');
  if (udpPort.isEmpty) udpPort = first('udp');
  if (udpPort.isEmpty) udpPort = serverPort;

  var enableUdpData = defaults.enableUdpData;
  if (first('udp_data').isNotEmpty) {
    enableUdpData = _parseBool(first('udp_data'), true);
  } else if (first('eu').isNotEmpty) {
    enableUdpData = _parseBool(first('eu'), true);
  }

  var enableIpv6 = defaults.enableIpv6;
  if (first('ipv6').isNotEmpty) {
    enableIpv6 = _parseBool(first('ipv6'), false);
  } else if (first('v6').isNotEmpty) {
    enableIpv6 = _parseBool(first('v6'), false);
  }

  var noTls = defaults.noTls;
  if (first('no_tls').isNotEmpty) {
    noTls = _parseBool(first('no_tls'), false);
  } else if (first('nt').isNotEmpty) {
    noTls = _parseBool(first('nt'), false);
  }

  var realityEnabled = false;
  var realitySni = '';
  var sni = '';
  var realityAuthKey = '';
  var fingerprint = '';
  final security = first('security').toLowerCase();
  if (security == 'reality' ||
      _parseBool(first('reality'), false) ||
      _parseBool(first('re'), false) ||
      first('sni').isNotEmpty ||
      first('auth_key').isNotEmpty) {
    realityEnabled = true;
    var s = first('sni');
    if (s.isEmpty) s = first('rs');
    if (s.isEmpty) s = first('reality_sni');
    if (s.isEmpty) s = kDefaultRealitySni;
    realitySni = s;
    sni = s;

    var authKey = first('auth_key');
    if (authKey.isEmpty) authKey = first('rk');
    if (authKey.isEmpty) authKey = first('sid');
    if (authKey.isEmpty) authKey = first('reality_auth_key');
    realityAuthKey = authKey;

    var fp = first('fp');
    if (fp.isEmpty) fp = first('fingerprint');
    if (fp.isEmpty) fp = 'chrome';
    fingerprint = fp;
  }

  var profile = defaults.profile;
  if (first('profile').isNotEmpty) profile = first('profile');
  var jitter = defaults.jitter;
  if (first('jitter').isNotEmpty) jitter = first('jitter');

  var mtu = defaults.mtu;
  final mtuValue = int.tryParse(first('mtu'));
  if (mtuValue != null && mtuValue > 0) {
    mtu = mtuValue > kMaxMtu ? kMaxMtu : mtuValue;
  }

  var dns = defaults.dns;
  if (first('dns').isNotEmpty) {
    dns = first('dns');
  } else if (first('d').isNotEmpty) {
    dns = first('d');
  }

  var tunAddress = defaults.tunAddress;
  if (first('tun').isNotEmpty) {
    tunAddress = first('tun');
  } else if (first('tun_address').isNotEmpty) {
    tunAddress = first('tun_address');
  }

  var junkCount = defaults.junkCount;
  var junkMin = defaults.junkMin;
  var junkMax = defaults.junkMax;
  final j = int.tryParse(first('junk'));
  if (j != null) junkCount = j;
  final jmin = int.tryParse(first('junk_min'));
  if (jmin != null) junkMin = jmin;
  final jmax = int.tryParse(first('junk_max'));
  if (jmax != null) junkMax = jmax;

  var noiseMin = defaults.noiseMinSec;
  var noiseMax = defaults.noiseMaxSec;
  var keepalive = defaults.keepaliveSec;
  final nmin = double.tryParse(first('noise_min'));
  if (nmin != null) noiseMin = nmin;
  final nmax = double.tryParse(first('noise_max'));
  if (nmax != null) noiseMax = nmax;
  final ka = double.tryParse(first('keepalive'));
  if (ka != null) keepalive = ka;

  var signatures = defaults.signatures;
  final sigs = q['sig'];
  if (sigs != null && sigs.isNotEmpty) signatures = sigs;

  var keyserver = '';
  if (first('keyserver').isNotEmpty) {
    keyserver = first('keyserver');
  } else if (first('ks').isNotEmpty) {
    keyserver = first('ks');
  }

  var token = '';
  if (first('token').isNotEmpty) {
    token = first('token');
  } else if (first('t').isNotEmpty) {
    token = first('t');
  }

  var expires = '';
  if (first('expires').isNotEmpty) {
    expires = first('expires');
  } else if (first('e').isNotEmpty) {
    expires = first('e');
  }

  var maxDevices = 0;
  final maxDevRaw = first('max_devices').isNotEmpty
      ? first('max_devices')
      : first('m');
  if (maxDevRaw.isNotEmpty) {
    final parsed = _parseUint32(maxDevRaw);
    if (parsed != null) maxDevices = parsed;
  }

  var clientPrivateKey = '';
  if (first('client_key').isNotEmpty) {
    clientPrivateKey = first('client_key').toLowerCase();
  }

  return defaults.copyWith(
    serverHost: host,
    serverPort: serverPort,
    serverPublicKey: serverPublicKey,
    clientPrivateKey: clientPrivateKey,
    udpPort: udpPort,
    enableUdpData: enableUdpData,
    enableIpv6: enableIpv6,
    noTls: noTls,
    realityEnabled: realityEnabled,
    realitySni: realitySni,
    sni: sni,
    realityAuthKey: realityAuthKey,
    fingerprint: fingerprint,
    profile: profile,
    jitter: jitter,
    mtu: mtu,
    dns: dns,
    tunAddress: tunAddress,
    junkCount: junkCount,
    junkMin: junkMin,
    junkMax: junkMax,
    noiseMinSec: noiseMin,
    noiseMaxSec: noiseMax,
    keepaliveSec: keepalive,
    signatures: signatures,
    keyserver: keyserver,
    token: token,
    expires: expires,
    maxDevices: maxDevices,
    label: label,
  );
}

(String, String) _splitHostPort(String hostPort) {
  if (hostPort.startsWith('[')) {
    final close = hostPort.indexOf(']');
    if (close < 0) throw const KeyFormatException(_badUri);
    final host = hostPort.substring(1, close);
    final rest = hostPort.substring(close + 1);
    if (rest.isEmpty) return (host, '');
    if (!rest.startsWith(':')) throw const KeyFormatException(_badPort);
    return (host, _validPort(rest.substring(1)));
  }
  final colon = hostPort.lastIndexOf(':');
  if (colon < 0) return (hostPort, '');
  final host = hostPort.substring(0, colon);
  if (host.contains(':')) throw const KeyFormatException(_badPort);
  return (host, _validPort(hostPort.substring(colon + 1)));
}

String _validPort(String port) {
  if (port.isEmpty) return port;
  if (!RegExp(r'^[0-9]+$').hasMatch(port)) throw const KeyFormatException(_badPort);
  _requirePortInRange(port);
  return port;
}

/// A TCP/UDP port must be 1..65535. Longer digit strings are rejected without
/// parsing them into an int.
void _requirePortInRange(String port) {
  final value = port.length > 5 ? null : int.tryParse(port);
  if (value == null || value < 1 || value > 65535) {
    throw const KeyFormatException(_badPort);
  }
}

Map<String, List<String>> _parseQuery(String raw) {
  final out = <String, List<String>>{};
  for (final part in raw.split('&')) {
    if (part.isEmpty) continue;
    final eq = part.indexOf('=');
    final keyRaw = eq >= 0 ? part.substring(0, eq) : part;
    final valueRaw = eq >= 0 ? part.substring(eq + 1) : '';
    if (keyRaw.contains(';')) continue;
    final key = _queryUnescapeOrNull(keyRaw);
    final value = _queryUnescapeOrNull(valueRaw);
    if (key == null || value == null) continue;
    out.putIfAbsent(key, () => <String>[]).add(value);
  }
  return out;
}

bool _parseBool(String s, bool defaultValue) {
  switch (s.trim().toLowerCase()) {
    case '1':
    case 'true':
    case 'yes':
    case 'on':
      return true;
    case '0':
    case 'false':
    case 'no':
    case 'off':
      return false;
    default:
      return defaultValue;
  }
}

int? _parseUint32(String s) {
  if (!RegExp(r'^[0-9]+$').hasMatch(s)) return null;
  final v = BigInt.parse(s);
  if (v > BigInt.from(0xFFFFFFFF)) return null;
  return v.toInt();
}

int _hexValue(int c) {
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
  if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
  return -1;
}

/// Percent-decodes [s] like Go url.Unescape. A '+' becomes a space only when
/// [plusIsSpace] is set (query component). Throws [FormatException] on a bad escape.
String _percentDecode(String s, {required bool plusIsSpace}) {
  final units = utf8.encode(s);
  final bytes = <int>[];
  for (var i = 0; i < units.length; i++) {
    final b = units[i];
    if (b == 0x25) {
      if (i + 2 >= units.length) throw const FormatException('bad escape');
      final hi = _hexValue(units[i + 1]);
      final lo = _hexValue(units[i + 2]);
      if (hi < 0 || lo < 0) throw const FormatException('bad escape');
      bytes.add(hi * 16 + lo);
      i += 2;
    } else if (plusIsSpace && b == 0x2b) {
      bytes.add(0x20);
    } else {
      bytes.add(b);
    }
  }
  return utf8.decode(bytes, allowMalformed: true);
}

String _percentDecodeOrThrow(String s, {required bool plusIsSpace}) {
  try {
    return _percentDecode(s, plusIsSpace: plusIsSpace);
  } on FormatException {
    throw const KeyFormatException(_badUri);
  }
}

String? _queryUnescapeOrNull(String s) {
  try {
    return _percentDecode(s, plusIsSpace: true);
  } on FormatException {
    return null;
  }
}

/// Decodes a legacy OBSDN key: OBSDN-XXXX-XXXX-... (base32 of zlib of compact JSON).
ClientConfig _decodeObsdn(String input) {
  var clean = input.replaceAll(RegExp(r'\s+'), '').toUpperCase();
  if (clean.startsWith('OBSDN-')) clean = clean.substring(6);
  clean = clean.replaceAll('-', '');
  if (clean.isEmpty) {
    throw const KeyFormatException('Ключ пустой. Вставьте ключ или ссылку.');
  }

  final Uint8List compressed;
  try {
    compressed = base32Decode(clean);
  } on FormatException {
    throw const KeyFormatException(
        'Ключ OBSDN обрезан или содержит недопустимые символы. Скопируйте его заново.');
  }

  final Object? decoded;
  try {
    final raw = ZLibDecoder().convert(compressed);
    // Dart's ZLibDecoder accepts a truncated stream; Go's zlib reader does not.
    // Verify the Adler-32 trailer, which must be present and match the output.
    final n = compressed.length;
    if (n < 6 || _adler32(raw) != _readUint32BE(compressed, n - 4)) {
      throw const FormatException('zlib checksum mismatch');
    }
    decoded = jsonDecode(utf8.decode(raw));
  } catch (_) {
    throw const KeyFormatException(
        'Ключ OBSDN повреждён: не удалось распаковать данные. Скопируйте его заново.');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const KeyFormatException('Ключ OBSDN повреждён: внутри не объект JSON.');
  }
  final compact = decoded;

  for (final req in const ['h', 'p', 'u', 'k']) {
    if (!compact.containsKey(req)) {
      throw KeyFormatException('В ключе OBSDN нет поля "$req". Скопируйте ключ заново.');
    }
  }

  String text(String key) {
    final v = compact[key];
    if (v is String) return v;
    if (v is num) return _numToString(v);
    throw KeyFormatException('В ключе OBSDN неверное значение поля "$key".');
  }

  bool? flag(String key) => compact[key] is bool ? compact[key] as bool : null;
  String str(String key) => compact[key] is String ? compact[key] as String : '';
  double? number(String key) =>
      compact[key] is num ? (compact[key] as num).toDouble() : null;

  if (text('h').trim().isEmpty) {
    throw const KeyFormatException('В ключе не указан адрес сервера.');
  }
  if (text('k').trim().isEmpty) {
    throw const KeyFormatException('В ключе нет публичного ключа сервера.');
  }
  _requirePortInRange(text('p').trim());

  final defaults = goDefaultClientConfig();
  var c = defaults.copyWith(
    serverHost: text('h'),
    serverPort: text('p'),
    serverPublicKey: text('k'),
    udpPort: text('u'),
    enableUdpData: flag('eu') ?? defaults.enableUdpData,
    enableIpv6: flag('v6') ?? false,
    noTls: flag('nt') ?? false,
  );

  if (str('d').isNotEmpty) c = c.copyWith(dns: str('d'));
  final mtu = number('mtu');
  if (mtu != null && mtu > 0) c = c.copyWith(mtu: mtu.toInt());
  final j = number('j');
  if (j != null) c = c.copyWith(junkCount: j.toInt());
  final ns = number('ns');
  if (ns != null) c = c.copyWith(noiseMinSec: ns);
  final nx = number('nx');
  if (nx != null) c = c.copyWith(noiseMaxSec: nx);
  final ka = number('ka');
  if (ka != null) c = c.copyWith(keepaliveSec: ka);

  final re = flag('re') ?? false;
  final rk = str('rk');
  var rs = str('rs');
  if (re || rk.isNotEmpty || rs.isNotEmpty) {
    if (rs.isEmpty) rs = kDefaultRealitySni;
    c = c.copyWith(
      realityEnabled: true,
      realityAuthKey: rk,
      realitySni: rs,
      sni: rs,
      fingerprint: 'chrome',
    );
  }

  c = c.copyWith(keyserver: str('ks'), token: str('t'), expires: str('e'));
  final m = number('m');
  if (m != null) {
    c = c.copyWith(maxDevices: m.clamp(0, 0xFFFFFFFF).toInt());
  }

  final clientKey = str('c').trim().toLowerCase();
  if (RegExp(r'^[0-9a-f]{64}$').hasMatch(clientKey)) {
    c = c.copyWith(clientPrivateKey: clientKey);
  }
  return c;
}

String _numToString(num n) {
  if (n is int) return n.toString();
  if (n == n.truncateToDouble() && n.abs() < 1e15) return n.toInt().toString();
  return n.toString();
}

/// Go-style JSON number: integral values have no fraction (Go writes float64 10 as `10`).
Object _jsonNumber(double d) {
  if (d == d.truncateToDouble() && d.abs() < 1e15) return d.toInt();
  return d;
}

Map<String, Object> _compactMap(ClientConfig c) {
  final udp = c.udpPort.isEmpty ? c.serverPort : c.udpPort;
  final mtu = c.mtu <= 0 || c.mtu > kMaxMtu ? kMaxMtu : c.mtu;
  final dns = c.dns.isEmpty || c.dns == kPublicDns || c.dns == kServerDns
      ? kServerDns
      : c.dns;
  final m = <String, Object>{
    'h': c.serverHost,
    'p': c.serverPort,
    'u': udp,
    'k': c.serverPublicKey,
    'j': c.junkCount,
    'ns': _jsonNumber(c.noiseMinSec),
    'nx': _jsonNumber(c.noiseMaxSec),
    'ka': _jsonNumber(c.keepaliveSec),
    'd': dns,
    'mtu': mtu,
    'pv': c.protocolVersion == 0 ? kProtocolVersion : c.protocolVersion,
    'eu': c.enableUdpData,
    'v6': c.enableIpv6,
  };
  if (c.noTls) m['nt'] = true;
  if (c.realityEnabled) {
    m['re'] = true;
    if (c.realityAuthKey.isNotEmpty) m['rk'] = c.realityAuthKey;
    if (c.realitySni.isNotEmpty) m['rs'] = c.realitySni;
  }
  if (c.keyserver.isNotEmpty) m['ks'] = c.keyserver;
  if (c.token.isNotEmpty) m['t'] = c.token;
  if (c.expires.isNotEmpty) m['e'] = c.expires;
  if (c.maxDevices > 0) m['m'] = c.maxDevices;
  return m;
}

/// Canonical compact JSON (sorted keys) that [encodeObsdn] compresses.
/// Exposed for tests; matches the compact payload of desktop keys.rs encode_key.
String obsdnCompactJson(ClientConfig c) {
  final m = _compactMap(c);
  final keys = m.keys.toList()..sort();
  return jsonEncode({for (final k in keys) k: m[k]!});
}

/// Encodes [c] as a legacy `OBSDN-XXXX-...` key. Follows desktop keys.rs encode_key:
/// base32 (no padding) of zlib level 9 of compact JSON, grouped by 4 with '-'.
/// The key carries no client private key and no label; `d` is 10.8.0.1 for
/// the default DNS, as in the desktop app.
String encodeObsdn(ClientConfig c) {
  final compressed = ZLibCodec(level: 9)
      .encode(utf8.encode(obsdnCompactJson(c)));
  final b32 = base32Encode(compressed);
  final groups = <String>[];
  for (var i = 0; i < b32.length; i += 4) {
    groups.add(b32.substring(i, i + 4 > b32.length ? b32.length : i + 4));
  }
  return 'OBSDN-${groups.join('-')}';
}

enum _Escape { query, fragment, userinfo }

const _fragmentReserved = r"$&+,/:;=?@!()*";
const _userinfoReserved = r"$&+,;=";

/// Percent-encodes [s] the way Go url.QueryEscape / EscapedFragment / userinfo do.
String _escape(String s, _Escape mode) {
  const hex = '0123456789ABCDEF';
  final out = StringBuffer();
  for (final c in utf8.encode(s)) {
    final isUnreserved = (c >= 0x30 && c <= 0x39) ||
        (c >= 0x41 && c <= 0x5a) ||
        (c >= 0x61 && c <= 0x7a) ||
        c == 0x2d ||
        c == 0x5f ||
        c == 0x2e ||
        c == 0x7e;
    if (isUnreserved) {
      out.writeCharCode(c);
    } else if (mode == _Escape.query && c == 0x20) {
      out.write('+');
    } else if (mode == _Escape.fragment && _fragmentReserved.codeUnits.contains(c)) {
      out.writeCharCode(c);
    } else if (mode == _Escape.userinfo && _userinfoReserved.codeUnits.contains(c)) {
      out.writeCharCode(c);
    } else {
      out.write('%${hex[c >> 4]}${hex[c & 0x0f]}');
    }
  }
  return out.toString();
}

/// Serializes [c] as `obsidian://<pubkey>@<host>:<port>?...#label`, matching Go
/// EncodeURI. [label] defaults to `c.label` when null or empty.
///
/// Deliberate deviation from Go: an IPv6 host is bracketed once. Go's EncodeURI
/// brackets it and then net.JoinHostPort brackets again (`[[2001:db8::1]]:443`),
/// which its own ParseURI rejects.
String encodeUri(ClientConfig c, {String? label}) {
  final port = c.serverPort.isEmpty ? kDefaultPort : c.serverPort;
  var host = c.serverHost;
  if (host.contains(':') && !host.startsWith('[')) host = '[$host]';
  final udp = c.udpPort.isEmpty ? port : c.udpPort;

  final q = <String, String>{};
  if (udp != port) q['udp_port'] = udp;
  if (!c.enableUdpData) q['udp_data'] = '0';
  if (c.enableIpv6) q['ipv6'] = '1';
  if (c.noTls) q['no_tls'] = '1';
  if (c.realityEnabled) {
    q['security'] = 'reality';
    if (c.realitySni.isNotEmpty) q['sni'] = c.realitySni;
    if (c.realityAuthKey.isNotEmpty) q['auth_key'] = c.realityAuthKey;
    if (c.fingerprint.isNotEmpty && c.fingerprint != 'chrome') {
      q['fp'] = c.fingerprint;
    }
  }
  if (c.profile.isNotEmpty && c.profile != 'fast-secure') q['profile'] = c.profile;
  if (c.mtu != 0 && c.mtu != kMaxMtu) q['mtu'] = c.mtu.toString();
  if (c.dns.isNotEmpty && c.dns != kPublicDns && c.dns != kServerDns) {
    q['dns'] = c.dns;
  }
  if (c.keyserver.isNotEmpty) q['keyserver'] = c.keyserver;
  if (c.token.isNotEmpty) q['token'] = c.token;
  if (c.expires.isNotEmpty) q['expires'] = c.expires;
  if (c.maxDevices > 0) q['max_devices'] = c.maxDevices.toString();
  if (c.clientPrivateKey.isNotEmpty) q['client_key'] = c.clientPrivateKey;

  final keys = q.keys.toList()..sort();
  final query = keys
      .map((k) => '${_escape(k, _Escape.query)}=${_escape(q[k]!, _Escape.query)}')
      .join('&');

  final userinfo = _escape(c.serverPublicKey, _Escape.userinfo);
  final buffer = StringBuffer('obsidian://$userinfo@$host:$port');
  if (query.isNotEmpty) buffer.write('?$query');

  final effectiveLabel = (label == null || label.isEmpty) ? c.label : label;
  if (effectiveLabel.isNotEmpty) {
    buffer.write('#${_escape(effectiveLabel, _Escape.fragment)}');
  }
  return buffer.toString();
}

/// Short "host:port" label for lists; IPv6 hosts are bracketed.
String keyPreview(ClientConfig c) {
  final port = c.serverPort.isEmpty ? kDefaultPort : c.serverPort;
  final host = c.serverHost.contains(':') ? '[${c.serverHost}]' : c.serverHost;
  return '$host:$port';
}

/// Derives the client tunnel address 10.8.0.N/24 from [seed]:
/// SHA-256(seed), first 4 bytes as a big-endian uint32 n, N = 2 + n % 253.
String deriveTunAddress(String seed) {
  final digest = const DartSha256().hashSync(utf8.encode(seed)).bytes;
  final n = (digest[0] << 24) | (digest[1] << 16) | (digest[2] << 8) | digest[3];
  final host = 2 + n % 253;
  return '10.8.0.$host/24';
}

/// Applies runtime defaults and derivations from desktop keys.rs and storage.rs:
/// tun address from [profileId] when unset, MTU capped at 1420, DNS 10.8.0.1
/// mapped to 1.1.1.1, Go defaults for zero-valued tunables, and the client keypair.
ClientConfig buildRuntimeConfig(
  ClientConfig c, {
  required String profileId,
  required String clientPrivateKeyHex,
  required String clientPublicKeyHex,
}) {
  final defaults = goDefaultClientConfig();

  final tunAddress =
      c.tunAddress.isEmpty || c.tunAddress == kDefaultTunAddress
          ? deriveTunAddress(profileId)
          : c.tunAddress;

  final mtu = c.mtu <= 0 || c.mtu > kMaxMtu ? kMaxMtu : c.mtu;

  var dns = c.dns.isEmpty ? defaults.dns : c.dns;
  if (dns == kServerDns) dns = kPublicDns;

  final junkUnset = c.junkCount == 0 && c.junkMin == 0 && c.junkMax == 0;
  final noiseUnset = c.noiseMinSec == 0 && c.noiseMaxSec == 0;

  return c.copyWith(
    protocolVersion: c.protocolVersion == 0 ? kProtocolVersion : c.protocolVersion,
    udpPort: c.udpPort.isEmpty ? c.serverPort : c.udpPort,
    tunAddress: tunAddress,
    mtu: mtu,
    dns: dns,
    profile: c.profile.isEmpty ? defaults.profile : c.profile,
    jitter: c.jitter.isEmpty ? defaults.jitter : c.jitter,
    signatures: c.signatures.isEmpty ? defaults.signatures : c.signatures,
    junkCount: junkUnset ? defaults.junkCount : c.junkCount,
    junkMin: junkUnset ? defaults.junkMin : c.junkMin,
    junkMax: junkUnset ? defaults.junkMax : c.junkMax,
    noiseMinSec: noiseUnset ? defaults.noiseMinSec : c.noiseMinSec,
    noiseMaxSec: noiseUnset ? defaults.noiseMaxSec : c.noiseMaxSec,
    keepaliveSec: c.keepaliveSec == 0 ? defaults.keepaliveSec : c.keepaliveSec,
    fingerprint: c.realityEnabled && c.fingerprint.isEmpty
        ? 'chrome'
        : c.fingerprint,
    clientPrivateKey: clientPrivateKeyHex,
    clientPublicKey: clientPublicKeyHex,
  );
}

/// Public key (64 lowercase hex chars) for the X25519 private key [privateHex].
/// Returns null when [privateHex] is not 64 hex characters.
Future<String?> clientPublicKeyFor(String privateHex) async {
  final hex = privateHex.trim().toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hex)) return null;
  final bytes = [
    for (var i = 0; i < 64; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
  ];
  final keyPair = await X25519().newKeyPairFromSeed(bytes);
  return _hex((await keyPair.extractPublicKey()).bytes);
}

/// Generates an X25519 keypair. Returns (privateHex, publicHex), both 64 lowercase hex chars.
Future<(String, String)> generateClientKeypair() async {
  final keyPair = await X25519().newKeyPair();
  final priv = await keyPair.extractPrivateKeyBytes();
  final pub = await keyPair.extractPublicKey();
  return (_hex(priv), _hex(pub.bytes));
}

int _adler32(List<int> data) {
  var a = 1;
  var b = 0;
  for (final byte in data) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  return (b << 16) | a;
}

int _readUint32BE(List<int> data, int offset) =>
    (data[offset] << 24) |
    (data[offset + 1] << 16) |
    (data[offset + 2] << 8) |
    data[offset + 3];

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
