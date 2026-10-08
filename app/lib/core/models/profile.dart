import 'dart:math';

import 'package:obsidian_vpn/core/models/split_tunnel.dart';
import 'package:obsidian_vpn/vps/vps_models.dart';

/// Country code shown when the profile name matches no keyword.
const String kFallbackCountryCode = 'VPN';

/// Where a server profile came from.
enum ProfileSource {
  /// Imported from an obsidian://, vpn:// or OBSDN- key.
  key('key'),

  /// Deployed by this app to a VPS over SSH.
  vps('vps');

  const ProfileSource(this.wire);

  /// Value stored in state.json.
  final String wire;

  /// Parses [raw]. Unknown or missing values fall back to [ProfileSource.key].
  static ProfileSource fromWire(Object? raw) {
    for (final source in values) {
      if (source.wire == raw) return source;
    }
    return ProfileSource.key;
  }
}

/// A saved VPN server. Holds metadata only: secrets (raw key, client keypair,
/// SSH password, admin token) live in the secret store, keyed by [id].
final class ServerProfile {
  ServerProfile({
    required this.id,
    required this.name,
    required this.countryCode,
    required this.host,
    required this.port,
    required this.serverPublicKey,
    required this.source,
    required this.createdAt,
    required this.split,
    this.isFavorite = false,
    this.vps,
    this.vpsHostKey,
    this.serverVersion,
    this.needsUpdate = false,
  });

  /// Random UUID v4. Also the suffix of every secret key of this profile.
  final String id;

  /// Display name chosen by the user, or taken from the key label or host.
  final String name;

  /// Two-letter ISO code guessed from the name, or [kFallbackCountryCode].
  final String countryCode;

  /// Server host name or IP, as written in the key.
  final String host;

  /// Server TCP port.
  final int port;

  /// Server X25519 public key, lower-case hex. Public, so it is not a secret.
  /// Used with [host] and [port] to detect duplicate keys.
  final String serverPublicKey;

  /// Origin of the profile.
  final ProfileSource source;

  /// When the profile was first saved, in UTC.
  final DateTime createdAt;

  /// Split tunnel rules for this profile.
  final SplitTunnelConfig split;

  /// Pinned to the top of the list by the UI.
  final bool isFavorite;

  /// SSH access to the VPS. Only [VpsCredentials.host], port and user are set;
  /// password, private key and passphrase are never kept here.
  /// Null for key-imported profiles.
  final VpsCredentials? vps;

  /// SHA256 fingerprint of the VPS host key, pinned on first use.
  final String? vpsHostKey;

  /// Core version installed on the VPS, when known.
  final String? serverVersion;

  /// True when the VPS runs an older core than this app bundles.
  final bool needsUpdate;

  /// Returns a copy with the given fields replaced. The nullable fields
  /// [vps], [vpsHostKey] and [serverVersion] keep their value when omitted.
  ServerProfile copyWith({
    String? name,
    String? countryCode,
    bool? isFavorite,
    SplitTunnelConfig? split,
    VpsCredentials? vps,
    String? vpsHostKey,
    String? serverVersion,
    bool? needsUpdate,
  }) {
    return ServerProfile(
      id: id,
      name: name ?? this.name,
      countryCode: countryCode ?? this.countryCode,
      host: host,
      port: port,
      serverPublicKey: serverPublicKey,
      source: source,
      createdAt: createdAt,
      split: split ?? this.split,
      isFavorite: isFavorite ?? this.isFavorite,
      vps: vps ?? this.vps,
      vpsHostKey: vpsHostKey ?? this.vpsHostKey,
      serverVersion: serverVersion ?? this.serverVersion,
      needsUpdate: needsUpdate ?? this.needsUpdate,
    );
  }

  /// JSON for state.json. Contains no secrets.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'country_code': countryCode,
    'host': host,
    'port': port,
    'server_public_key': serverPublicKey,
    'source': source.wire,
    'created_at': createdAt.toUtc().toIso8601String(),
    'is_favorite': isFavorite,
    'split': split.toJson(),
    if (vps != null)
      'vps': <String, dynamic>{
        'host': vps!.host,
        'port': vps!.port,
        'user': vps!.user,
      },
    if (vpsHostKey != null) 'vps_host_key': vpsHostKey,
    if (serverVersion != null) 'server_version': serverVersion,
    'needs_update': needsUpdate,
  };

  /// Reads a profile written by [toJson]. Throws [FormatException] when the
  /// id, host or port is missing or invalid.
  factory ServerProfile.fromJson(Map<String, dynamic> json) {
    final id = _string(json['id']);
    final host = _string(json['host']);
    final port = _int(json['port']);
    if (id.isEmpty || host.isEmpty || port == null || port < 1 || port > 65535) {
      throw const FormatException('profile: id, host or port is invalid');
    }
    final vpsJson = json['vps'];
    VpsCredentials? vps;
    if (vpsJson is Map) {
      vps = VpsCredentials(
        host: _string(vpsJson['host']),
        port: _int(vpsJson['port']) ?? 22,
        user: _string(vpsJson['user'], 'root'),
      );
    }
    final splitJson = json['split'];
    final createdAt = DateTime.tryParse(_string(json['created_at']));
    return ServerProfile(
      id: id,
      name: _string(json['name'], host),
      countryCode: _string(json['country_code'], kFallbackCountryCode),
      host: host,
      port: port,
      serverPublicKey: _string(json['server_public_key']).toLowerCase(),
      source: ProfileSource.fromWire(json['source']),
      createdAt: createdAt?.toUtc() ?? DateTime.now().toUtc(),
      split: splitJson is Map
          ? SplitTunnelConfig.fromJson(Map<String, dynamic>.from(splitJson))
          : SplitTunnelConfig(),
      isFavorite: json['is_favorite'] == true,
      vps: vps,
      vpsHostKey: _nonEmptyOrNull(json['vps_host_key']),
      serverVersion: _nonEmptyOrNull(json['server_version']),
      needsUpdate: json['needs_update'] == true,
    );
  }
}

/// Guesses the country code from a profile name using a keyword table.
///
/// Matching is case-insensitive. Latin keywords shorter than four letters
/// (for example "uk" or "usa") must match a whole word, so that "ukraine"
/// does not count as the United Kingdom. Returns [kFallbackCountryCode] when
/// nothing matches.
String guessCountryCode(String name) {
  final lower = name.toLowerCase();
  for (final (needles, code) in _countryTable) {
    for (final needle in needles) {
      if (_matchesKeyword(lower, needle)) return code;
    }
  }
  return kFallbackCountryCode;
}

bool _matchesKeyword(String lowerName, String needle) {
  final isShortLatin = needle.length < 4 && RegExp(r'^[a-z ]+$').hasMatch(needle);
  if (!isShortLatin) return lowerName.contains(needle);
  final pattern = RegExp('(^|[^a-z0-9])${RegExp.escape(needle)}(\$|[^a-z0-9])');
  return pattern.hasMatch(lowerName);
}

/// The 13 countries of the iOS table,
/// merged with the desktop tags (Frankfurt, Amsterdam, London, Paris, Warsaw,
/// Helsinki, Moscow).
const List<(List<String>, String)> _countryTable = <(List<String>, String)>[
  (['helsinki', 'finland', 'хельсинки', 'финлянд', 'suomi'], 'FI'),
  (['amsterdam', 'netherlands', 'nether', 'амстердам', 'нидерланд', 'голланди'], 'NL'),
  (['frankfurt', 'germany', 'франкфурт', 'германи', 'deutschland'], 'DE'),
  (['stockholm', 'sweden', 'стокгольм', 'швец'], 'SE'),
  (['warsaw', 'poland', 'варшав', 'польш'], 'PL'),
  (['london', 'uk', 'лондон', 'великобритан', 'united kingdom'], 'GB'),
  (['paris', 'france', 'париж', 'франци'], 'FR'),
  (['tokyo', 'japan', 'токио', 'япони'], 'JP'),
  (['singapore', 'сингапур'], 'SG'),
  (['usa', 'united states', 'сша', 'нью-йорк', 'new york', 'los angeles', 'лос-анджелес'], 'US'),
  (['russia', 'москв', 'росси', 'moscow', 'spb', 'питер', 'санкт-петербург'], 'RU'),
  (['turkey', 'турци', 'стамбул', 'istanbul'], 'TR'),
  (['kazakhstan', 'казахстан', 'алматы', 'астана'], 'KZ'),
];

/// Interface language choice in settings.
enum AppLocalePref {
  /// Follow the device language. Russian unless the device is English.
  system('system'),

  /// Russian.
  ru('ru'),

  /// English.
  en('en');

  const AppLocalePref(this.wire);

  /// Value stored in state.json.
  final String wire;

  /// Parses [raw], falling back to [AppLocalePref.system].
  static AppLocalePref fromWire(Object? raw) {
    for (final value in values) {
      if (value.wire == raw) return value;
    }
    return AppLocalePref.system;
  }
}

/// Theme choice in settings.
enum AppThemeMode {
  /// Follow the OS theme.
  system('system'),

  /// Always dark.
  dark('dark'),

  /// Always light.
  light('light');

  const AppThemeMode(this.wire);

  /// Value stored in state.json.
  final String wire;

  /// Parses [raw], falling back to [AppThemeMode.system].
  static AppThemeMode fromWire(Object? raw) {
    for (final value in values) {
      if (value.wire == raw) return value;
    }
    return AppThemeMode.system;
  }
}

/// Application-wide preferences. Immutable; change with [copyWith].
final class AppSettings {
  const AppSettings({
    this.autostart = false,
    this.minimizeToTray = true,
    this.killSwitch = false,
    this.autoConnect = false,
    this.haptics = true,
    this.lastProfileId,
    this.themeMode = AppThemeMode.system,
    this.locale = AppLocalePref.system,
  });

  /// Start the desktop app at logon (`--autostart`).
  final bool autostart;

  /// Desktop: closing the window hides the app to the tray.
  final bool minimizeToTray;

  /// Block traffic outside the tunnel. Passed to backends that support it.
  final bool killSwitch;

  /// Connect when the app starts.
  final bool autoConnect;

  /// Haptic feedback on mobile.
  final bool haptics;

  /// Id of the selected profile. Owned by `AppState.selectProfile`.
  final String? lastProfileId;

  /// Theme choice.
  final AppThemeMode themeMode;

  /// Language choice.
  final AppLocalePref locale;

  /// Returns a copy with the given fields replaced. Pass [clearLastProfileId]
  /// to set [lastProfileId] to null.
  AppSettings copyWith({
    bool? autostart,
    bool? minimizeToTray,
    bool? killSwitch,
    bool? autoConnect,
    bool? haptics,
    String? lastProfileId,
    bool clearLastProfileId = false,
    AppThemeMode? themeMode,
    AppLocalePref? locale,
  }) {
    return AppSettings(
      autostart: autostart ?? this.autostart,
      minimizeToTray: minimizeToTray ?? this.minimizeToTray,
      killSwitch: killSwitch ?? this.killSwitch,
      autoConnect: autoConnect ?? this.autoConnect,
      haptics: haptics ?? this.haptics,
      lastProfileId: clearLastProfileId ? null : (lastProfileId ?? this.lastProfileId),
      themeMode: themeMode ?? this.themeMode,
      locale: locale ?? this.locale,
    );
  }

  /// JSON for state.json.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'autostart': autostart,
    'minimize_to_tray': minimizeToTray,
    'kill_switch': killSwitch,
    'auto_connect': autoConnect,
    'haptics': haptics,
    if (lastProfileId != null) 'last_profile_id': lastProfileId,
    'theme_mode': themeMode.wire,
    'locale': locale.wire,
  };

  /// Reads settings written by [toJson]. Missing or invalid fields take their defaults.
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final last = _nonEmptyOrNull(json['last_profile_id']);
    return AppSettings(
      autostart: json['autostart'] == true,
      minimizeToTray: json['minimize_to_tray'] is bool ? json['minimize_to_tray'] as bool : true,
      killSwitch: json['kill_switch'] == true,
      autoConnect: json['auto_connect'] == true,
      haptics: json['haptics'] is bool ? json['haptics'] as bool : true,
      lastProfileId: last,
      themeMode: AppThemeMode.fromWire(json['theme_mode']),
      locale: AppLocalePref.fromWire(json['locale']),
    );
  }
}

/// Returns a random RFC 4122 version 4 UUID in lower-case, using [random]
/// (default: `Random.secure()`).
String generateUuidV4({Random? random}) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}'
      '-${hex.substring(16, 20)}-${hex.substring(20)}';
}

String _string(Object? value, [String fallback = '']) =>
    value is String ? value.trim() : fallback;

String? _nonEmptyOrNull(Object? value) {
  final text = _string(value);
  return text.isEmpty ? null : text;
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
