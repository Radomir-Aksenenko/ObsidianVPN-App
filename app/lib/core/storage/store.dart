import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:obsidian_vpn/core/codec/client_config.dart';
import 'package:obsidian_vpn/core/codec/obsidian_key.dart';
import 'package:obsidian_vpn/core/models/profile.dart';
import 'package:obsidian_vpn/core/models/split_tunnel.dart';
import 'package:obsidian_vpn/vps/key_issuer.dart';
import 'package:obsidian_vpn/vps/vps_models.dart';

/// Schema version written to state.json. A file with a larger version is
/// treated as unreadable and moved aside.
const int kStateSchemaVersion = 1;

/// File name of the JSON state inside the app support directory.
const String kStateFileName = 'state.json';

/// Key-value store for secrets (raw keys, client private keys, SSH passwords,
/// admin tokens). Values never go to state.json.
abstract interface class SecretStore {
  /// Returns the value stored under [key], or null when absent.
  Future<String?> read(String key);

  /// Stores [value] under [key], replacing any previous value.
  Future<void> write(String key, String value);

  /// Removes [key]. Does nothing when absent.
  Future<void> delete(String key);

  /// Removes every key that starts with [prefix].
  Future<void> deletePrefix(String prefix);
}

/// [SecretStore] backed by the OS keychain or keystore (flutter_secure_storage).
final class SecureSecretStore implements SecretStore {
  /// Creates a store. Pass [storage] to use a custom FlutterSecureStorage.
  SecureSecretStore({FlutterSecureStorage? storage})
    : _storage = storage ?? FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deletePrefix(String prefix) async {
    final all = await _storage.readAll();
    for (final key in all.keys) {
      if (key.startsWith(prefix)) await _storage.delete(key: key);
    }
  }
}

/// In-memory [SecretStore] for tests and previews. Nothing is persisted.
final class MemorySecretStore implements SecretStore {
  final Map<String, String> _values = <String, String>{};

  /// Read-only copy of the stored entries.
  Map<String, String> get values => UnmodifiableMapView(_values);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> deletePrefix(String prefix) async {
    _values.removeWhere((key, _) => key.startsWith(prefix));
  }
}

/// Names of secret keys. Profile secrets are stored as `profile.<id>.<field>`,
/// issued key secrets as `issued.<id>.<field>`.
abstract final class SecretKeys {
  /// Field: the key or URI imported by the user (for a VPS, the owner key).
  static const String rawKey = 'rawKey';

  /// Field: X25519 client private key, 64 lower-case hex characters.
  static const String clientPrivateKey = 'clientPrivateKey';

  /// Field: X25519 client public key, 64 lower-case hex characters.
  static const String clientPublicKey = 'clientPublicKey';

  /// Field: SSH password of the VPS.
  static const String vpsPassword = 'vpsPassword';

  /// Field: SSH private key of the VPS (PEM).
  static const String vpsPrivateKeyPem = 'vpsPrivateKeyPem';

  /// Field: passphrase of the SSH private key.
  static const String vpsPassphrase = 'vpsPassphrase';

  /// Field: keyserver admin token.
  static const String adminToken = 'adminToken';

  /// Issued key field: the OBSDN key.
  static const String issuedKey = 'key';

  /// Issued key field: the obsidian:// URI.
  static const String issuedUri = 'uri';

  /// Full secret key for a profile field.
  static String profile(String id, String field) => 'profile.$id.$field';

  /// Prefix shared by every secret of a profile.
  static String profilePrefix(String id) => 'profile.$id.';

  /// Full secret key for an issued key field.
  static String issued(String id, String field) => 'issued.$id.$field';

  /// Prefix shared by both secrets of an issued key.
  static String issuedPrefix(String id) => 'issued.$id.';
}

/// Persistent app state: profiles, issued keys, settings and the device id.
///
/// Metadata is written atomically to `<dir>/state.json` (temporary file, then
/// rename). Secrets go to [secrets]. A file that cannot be parsed is renamed
/// to `state.json.bad` and the store starts empty.
final class AppStore {
  AppStore._({
    required this.secrets,
    required String? dir,
    required this.deviceId,
    required List<ServerProfile> profiles,
    required List<IssuedKey> issued,
    required AppSettings settings,
    required List<String> notices,
  }) : // The named parameters keep their public names, so the fields are set here.
       // ignore: prefer_initializing_formals
       _dir = dir,
       // ignore: prefer_initializing_formals
       _profiles = profiles,
       // ignore: prefer_initializing_formals
       _issued = issued,
       // ignore: prefer_initializing_formals
       _settings = settings,
       // ignore: prefer_initializing_formals
       _notices = notices;

  /// Secret storage used for every secret of this store.
  final SecretStore secrets;

  /// Stable random id of this installation, created once.
  final String deviceId;

  final String? _dir;
  final List<ServerProfile> _profiles;
  final List<IssuedKey> _issued;
  final List<String> _notices;
  AppSettings _settings;
  Future<void> _writeChain = Future<void>.value();

  /// Store with no file on disk, for tests and previews.
  factory AppStore.memory({SecretStore? secrets}) {
    return AppStore._(
      secrets: secrets ?? MemorySecretStore(),
      dir: null,
      deviceId: generateUuidV4(),
      profiles: <ServerProfile>[],
      issued: <IssuedKey>[],
      settings: const AppSettings(),
      notices: <String>[],
    );
  }

  /// Opens the store in [dir], creating the directory when needed.
  ///
  /// When `state.json` is absent and [legacyDir] is set, the old desktop app
  /// data (servers.json, issued.json, settings.json, device_id.txt) is imported
  /// once. Old files are never deleted. A corrupted state.json is renamed to
  /// `state.json.bad` and the store starts empty, without importing.
  static Future<AppStore> open({
    required String dir,
    required SecretStore secrets,
    String? legacyDir,
  }) async {
    await Directory(dir).create(recursive: true);
    final file = File(_join(dir, kStateFileName));

    if (await file.exists()) {
      final parsed = _parseStateFile(await file.readAsString());
      if (parsed != null) {
        final loaded = await _loadState(parsed, secrets);
        final store = AppStore._(
          secrets: secrets,
          dir: dir,
          deviceId: parsed.deviceId ?? generateUuidV4(),
          profiles: loaded.profiles,
          issued: loaded.issued,
          settings: parsed.settings,
          notices: loaded.notices,
        );
        if (parsed.deviceId == null) await store._persist();
        return store;
      }
      await _moveAside(file);
      final store = AppStore._(
        secrets: secrets,
        dir: dir,
        deviceId: generateUuidV4(),
        profiles: <ServerProfile>[],
        issued: <IssuedKey>[],
        settings: const AppSettings(),
        notices: <String>[
          'Файл состояния повреждён, сохранён как $kStateFileName.bad',
        ],
      );
      await store._persist();
      return store;
    }

    final legacy = legacyDir == null
        ? null
        : await _importLegacy(legacyDir, secrets);
    final store = AppStore._(
      secrets: secrets,
      dir: dir,
      deviceId: legacy?.deviceId ?? generateUuidV4(),
      profiles: legacy?.profiles ?? <ServerProfile>[],
      issued: legacy?.issued ?? <IssuedKey>[],
      settings: legacy?.settings ?? const AppSettings(),
      notices: legacy?.notices ?? <String>[],
    );
    await store._persist();
    return store;
  }

  /// Profiles in insertion order. Read-only view.
  List<ServerProfile> get profiles => UnmodifiableListView(_profiles);

  /// Issued keys in insertion order. Read-only view.
  List<IssuedKey> get issuedKeys => UnmodifiableListView(_issued);

  /// Current settings.
  AppSettings get settings => _settings;

  /// Notices from loading or migration, for the log screen. Read-only view.
  List<String> get notices => UnmodifiableListView(_notices);

  /// Adds [profile], or replaces the profile with the same id. Persists.
  Future<void> putProfile(ServerProfile profile) {
    final index = _profiles.indexWhere((p) => p.id == profile.id);
    if (index >= 0) {
      _profiles[index] = profile;
    } else {
      _profiles.add(profile);
    }
    return _persist();
  }

  /// Removes the profile and all of its secrets. Persists.
  Future<void> removeProfile(String id) async {
    _profiles.removeWhere((p) => p.id == id);
    await secrets.deletePrefix(SecretKeys.profilePrefix(id));
    await _persist();
  }

  /// Replaces the settings. Persists.
  Future<void> setSettings(AppSettings settings) {
    _settings = settings;
    return _persist();
  }

  /// Adds [key], or replaces the issued key with the same id. The OBSDN key and
  /// URI go to the secret store, the rest to state.json. Persists.
  Future<void> putIssued(IssuedKey key) async {
    await secrets.write(SecretKeys.issued(key.id, SecretKeys.issuedKey), key.key);
    await secrets.write(SecretKeys.issued(key.id, SecretKeys.issuedUri), key.uri);
    final index = _issued.indexWhere((k) => k.id == key.id);
    if (index >= 0) {
      _issued[index] = key;
    } else {
      _issued.add(key);
    }
    await _persist();
  }

  /// Removes the issued key and its secrets. Persists.
  Future<void> removeIssued(String id) async {
    _issued.removeWhere((k) => k.id == id);
    await secrets.deletePrefix(SecretKeys.issuedPrefix(id));
    await _persist();
  }

  /// Writes state.json. Writes are queued, so they never interleave.
  Future<void> _persist() {
    final dir = _dir;
    if (dir == null) return Future<void>.value();
    final body = const JsonEncoder.withIndent('  ').convert(_toJson());
    final next = _writeChain.then((_) => _writeAtomic(dir, body));
    _writeChain = next.catchError((Object _) {});
    return next;
  }

  Map<String, dynamic> _toJson() => <String, dynamic>{
    'schema': kStateSchemaVersion,
    'device_id': deviceId,
    'settings': _settings.toJson(),
    'profiles': <Map<String, dynamic>>[for (final p in _profiles) p.toJson()],
    'issued_keys': <Map<String, dynamic>>[
      for (final k in _issued) _issuedMetaJson(k),
    ],
  };
}

/// Metadata read from state.json, before secrets are attached.
final class _StateFile {
  const _StateFile({
    required this.deviceId,
    required this.settings,
    required this.profiles,
    required this.issued,
  });

  /// Null when the file has no device id (it is then generated and saved).
  final String? deviceId;
  final AppSettings settings;
  final List<Map<String, dynamic>> profiles;
  final List<Map<String, dynamic>> issued;
}

/// Result of loading state or importing legacy data.
final class _Loaded {
  const _Loaded({
    this.deviceId,
    this.settings = const AppSettings(),
    this.profiles = const <ServerProfile>[],
    this.issued = const <IssuedKey>[],
    this.notices = const <String>[],
  });

  final String? deviceId;
  final AppSettings settings;
  final List<ServerProfile> profiles;
  final List<IssuedKey> issued;
  final List<String> notices;
}

/// Parses state.json text. Returns null when the JSON is invalid, is not an
/// object, or has a schema version this build does not know.
_StateFile? _parseStateFile(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  final schema = decoded['schema'];
  if (schema is! int || schema > kStateSchemaVersion) return null;
  final settings = decoded['settings'];
  return _StateFile(
    deviceId: _nonEmpty(decoded['device_id']),
    settings: settings is Map<String, dynamic>
        ? AppSettings.fromJson(settings)
        : const AppSettings(),
    profiles: _mapList(decoded['profiles']),
    issued: _mapList(decoded['issued_keys']),
  );
}

/// Builds profiles and issued keys from state.json metadata and the secret store.
/// Entries that cannot be read are skipped and reported in the notices.
Future<_Loaded> _loadState(_StateFile parsed, SecretStore secrets) async {
  var skipped = 0;
  final profiles = <ServerProfile>[];
  for (final json in parsed.profiles) {
    try {
      profiles.add(ServerProfile.fromJson(json));
    } on FormatException {
      skipped++;
    }
  }
  final issued = <IssuedKey>[];
  for (final json in parsed.issued) {
    final id = _nonEmpty(json['id']);
    final key = id == null
        ? null
        : await _readOrNull(secrets, SecretKeys.issued(id, SecretKeys.issuedKey));
    if (id == null || key == null) {
      skipped++;
      continue;
    }
    final uri =
        await _readOrNull(secrets, SecretKeys.issued(id, SecretKeys.issuedUri)) ?? '';
    issued.add(_issuedFromMeta(id, json, key: key, uri: uri));
  }
  return _Loaded(
    deviceId: parsed.deviceId,
    settings: parsed.settings,
    profiles: profiles,
    issued: issued,
    notices: skipped == 0
        ? const <String>[]
        : <String>['Пропущено записей при загрузке: $skipped'],
  );
}

/// Imports the old desktop app data from [legacyDir]. Every file is optional.
/// Secrets go to [secrets]; entries whose secrets cannot be written are kept
/// with the missing secret and reported in the notices.
Future<_Loaded> _importLegacy(String legacyDir, SecretStore secrets) async {
  final notices = <String>[];

  final deviceText = await _readLegacyText(legacyDir, 'device_id.txt');
  final settingsJson = await _readLegacyJson(legacyDir, 'settings.json', notices);
  final serversJson = await _readLegacyJson(legacyDir, 'servers.json', notices);
  final issuedJson = await _readLegacyJson(legacyDir, 'issued.json', notices);

  final profiles = <ServerProfile>[];
  if (serversJson is List) {
    for (final item in serversJson) {
      if (item is! Map<String, dynamic>) continue;
      final profile = await _importLegacyProfile(item, secrets, notices);
      if (profile != null) profiles.add(profile);
    }
  }

  final issued = <IssuedKey>[];
  if (issuedJson is List) {
    for (final item in issuedJson) {
      if (item is! Map<String, dynamic>) continue;
      final id = _nonEmpty(item['id']);
      final key = _nonEmpty(item['key']);
      if (id == null || key == null) continue;
      final uri = _uriOf(key);
      final keyOk = await _safeWrite(secrets, SecretKeys.issued(id, SecretKeys.issuedKey), key, notices);
      await _safeWrite(secrets, SecretKeys.issued(id, SecretKeys.issuedUri), uri, notices);
      if (keyOk) issued.add(_issuedFromMeta(id, item, key: key, uri: uri));
    }
  }

  final settings = settingsJson is Map<String, dynamic>
      ? AppSettings.fromJson(settingsJson)
      : const AppSettings();
  if (profiles.isNotEmpty || issued.isNotEmpty) {
    notices.insert(
      0,
      'Импортированы данные старой версии: серверов ${profiles.length}, ключей ${issued.length}',
    );
  }
  return _Loaded(
    deviceId: _nonEmpty(deviceText),
    settings: settings,
    profiles: profiles,
    issued: issued,
    notices: notices,
  );
}

/// Converts one entry of the old servers.json. Returns null when the entry has
/// no usable key or host.
Future<ServerProfile?> _importLegacyProfile(
  Map<String, dynamic> json,
  SecretStore secrets,
  List<String> notices,
) async {
  final config = json['config'] is Map
      ? Map<String, dynamic>.from(json['config'] as Map)
      : <String, dynamic>{};
  final fromConfig = _configOrNull(config);
  var rawKey = _nonEmpty(json['raw_key']) ?? '';
  if (rawKey.isEmpty && fromConfig != null) {
    rawKey = _encodeOrEmpty(fromConfig);
  }
  final base = fromConfig ?? (rawKey.isEmpty ? null : _parseOrNull(rawKey));
  if (base == null || base.serverHost.isEmpty) return null;

  final id = _nonEmpty(json['id']) ?? generateUuidV4();
  final host = base.serverHost;
  final port = int.tryParse(base.serverPort) ?? int.parse(kDefaultPort);
  final name = _nonEmpty(json['name']) ??
      (base.label.isNotEmpty ? base.label : host);
  final source = ProfileSource.fromWire(json['source']);

  if (rawKey.isNotEmpty) {
    await _safeWrite(secrets, SecretKeys.profile(id, SecretKeys.rawKey), rawKey, notices);
  }
  final privateKey = _nonEmpty(config['client_private_key']);
  if (privateKey != null) {
    await _safeWrite(secrets, SecretKeys.profile(id, SecretKeys.clientPrivateKey), privateKey, notices);
  }
  final publicKey = _nonEmpty(config['client_public_key']);
  if (publicKey != null) {
    await _safeWrite(secrets, SecretKeys.profile(id, SecretKeys.clientPublicKey), publicKey, notices);
  }
  final adminToken = _nonEmpty(json['keyserver_admin_token']);
  if (adminToken != null) {
    await _safeWrite(secrets, SecretKeys.profile(id, SecretKeys.adminToken), adminToken, notices);
  }

  VpsCredentials? vps;
  if (source == ProfileSource.vps) {
    vps = VpsCredentials(
      host: _nonEmpty(json['ssh_host']) ?? host,
      port: _intOf(json['ssh_port']) ?? 22,
      user: _nonEmpty(json['ssh_user']) ?? 'root',
    );
    final password = json['ssh_password_secret'];
    if (password is String && password.isNotEmpty) {
      await _safeWrite(secrets, SecretKeys.profile(id, SecretKeys.vpsPassword), password, notices);
    }
    final keyPath = _nonEmpty(json['ssh_key_path']);
    final pem = keyPath == null ? null : await _readFileOrNull(keyPath);
    if (pem != null && pem.trim().isNotEmpty) {
      await _safeWrite(secrets, SecretKeys.profile(id, SecretKeys.vpsPrivateKeyPem), pem, notices);
    }
  }

  final flag = _nonEmpty(json['flag']);
  return ServerProfile(
    id: id,
    name: name,
    countryCode: flag != null && flag.length == 2
        ? flag.toUpperCase()
        : guessCountryCode(name),
    host: host,
    port: port,
    serverPublicKey: base.serverPublicKey.toLowerCase(),
    source: source,
    createdAt: DateTime.now().toUtc(),
    split: SplitTunnelConfig.fromJson(config),
    vps: vps,
    serverVersion: _nonEmpty(json['server_version']),
    needsUpdate: json['needs_update'] == true,
  );
}

IssuedKey _issuedFromMeta(
  String id,
  Map<String, dynamic> json, {
  required String key,
  required String uri,
}) {
  return IssuedKey(
    id: id,
    name: _nonEmpty(json['name']) ?? 'Guest',
    serverId: _nonEmpty(json['server_id']) ?? '',
    devices: _intOf(json['devices']) ?? 0,
    days: _intOf(json['days']) ?? 0,
    key: key,
    uri: uri,
    created: DateTime.tryParse(_nonEmpty(json['created']) ?? '')?.toUtc() ??
        DateTime.now().toUtc(),
  );
}

Map<String, dynamic> _issuedMetaJson(IssuedKey key) => <String, dynamic>{
  'id': key.id,
  'name': key.name,
  'server_id': key.serverId,
  'devices': key.devices,
  'days': key.days,
  'created': key.created.toUtc().toIso8601String(),
};

/// Renames a corrupted state file to `state.json.bad`, replacing an older backup.
Future<void> _moveAside(File file) async {
  final bad = File('${file.path}.bad');
  if (await bad.exists()) await bad.delete();
  await file.rename(bad.path);
}

/// Writes [body] to a temporary file next to state.json, then renames it over the target.
Future<void> _writeAtomic(String dir, String body) async {
  final target = File(_join(dir, kStateFileName));
  final temp = File('${target.path}.tmp');
  await temp.writeAsString(body, flush: true);
  await temp.rename(target.path);
}

Future<String?> _readLegacyText(String dir, String name) async {
  final file = File(_join(dir, name));
  if (!await file.exists()) return null;
  try {
    return await file.readAsString();
  } on FileSystemException {
    return null;
  }
}

Future<Object?> _readLegacyJson(
  String dir,
  String name,
  List<String> notices,
) async {
  final text = await _readLegacyText(dir, name);
  if (text == null) return null;
  try {
    return jsonDecode(text);
  } on FormatException {
    notices.add('Не удалось прочитать $name из старой версии');
    return null;
  }
}

Future<String?> _readFileOrNull(String path) async {
  try {
    return await File(path).readAsString();
  } on FileSystemException {
    return null;
  }
}

Future<String?> _readOrNull(SecretStore secrets, String key) async {
  try {
    return await secrets.read(key);
  } on Object {
    return null;
  }
}

/// Writes a secret. Returns false (and adds a notice) when the secret store fails.
Future<bool> _safeWrite(
  SecretStore secrets,
  String key,
  String value,
  List<String> notices,
) async {
  try {
    await secrets.write(key, value);
    return true;
  } on Object {
    notices.add('Не удалось сохранить секрет в защищённом хранилище');
    return false;
  }
}

ClientConfig? _configOrNull(Map<String, dynamic> config) {
  if (config.isEmpty) return null;
  try {
    return ClientConfig.fromJson(config);
  } on Object {
    return null;
  }
}

ClientConfig? _parseOrNull(String raw) {
  try {
    return parseKey(raw);
  } on KeyFormatException {
    return null;
  }
}

String _encodeOrEmpty(ClientConfig config) {
  try {
    return encodeObsdn(config);
  } on Object {
    return '';
  }
}

String _uriOf(String key) {
  final config = _parseOrNull(key);
  if (config == null) return '';
  try {
    return encodeUri(config);
  } on Object {
    return '';
  }
}

List<Map<String, dynamic>> _mapList(Object? raw) {
  if (raw is! List) return const <Map<String, dynamic>>[];
  return <Map<String, dynamic>>[
    for (final entry in raw)
      if (entry is Map<String, dynamic>) entry,
  ];
}

String _join(String dir, String name) => '$dir${Platform.pathSeparator}$name';

String? _nonEmpty(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty ? null : text;
}

int? _intOf(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}
