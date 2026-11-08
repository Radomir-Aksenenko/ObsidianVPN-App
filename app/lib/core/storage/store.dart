import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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

/// File name of [FileSecretStore] inside the app support directory.
const String kSecretsFileName = 'secrets.json';

/// Secret-store keys of the state.json mirror: `state.mirror.count` holds the
/// number of chunks, `state.mirror.<n>` the chunks. The mirror lets the app
/// rebuild its servers after a reinstall wiped the app directory but left the
/// keychain (iOS) or the credential store (desktop) alone.
const String _mirrorCount = 'state.mirror.count';
const String _mirrorChunk = 'state.mirror.';

/// Chunk size in characters. Windows Credential Manager caps a value at 2560 bytes.
const int _mirrorChunkSize = 800;

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

/// [SecretStore] that keeps secrets in a JSON file inside the app directory.
///
/// Android Keystore keys die with an uninstall, so Keystore-encrypted secrets
/// cannot come back from Auto Backup. A plain file in the app-private directory
/// can: it is included in the Android backup rules and restored on reinstall.
/// Secrets in [legacy] (the old Keystore store) are copied over on first read.
final class FileSecretStore implements SecretStore {
  /// Creates a store that writes `secrets.json` into [dir].
  FileSecretStore({required String dir, this._legacy})
    : _path = _join(dir, kSecretsFileName);

  final String _path;
  final SecretStore? _legacy;
  Map<String, String>? _cache;
  Future<void> _chain = Future<void>.value();

  Future<Map<String, String>> _load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final map = <String, String>{};
    final file = File(_path);
    try {
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          decoded.forEach((k, v) {
            if (k is String && v is String) map[k] = v;
          });
        }
      }
    } on Object {
      // An unreadable file is treated as empty; the legacy store may still help.
    }
    return _cache = map;
  }

  Future<void> _save(Map<String, String> map) {
    final body = jsonEncode(map);
    final next = _chain.then((_) async {
      final temp = File('$_path.tmp');
      await temp.writeAsString(body, flush: true);
      await temp.rename(_path);
    });
    _chain = next.catchError((Object _) {});
    return next;
  }

  @override
  Future<String?> read(String key) async {
    final map = await _load();
    final value = map[key];
    if (value != null) return value;
    final legacy = _legacy;
    if (legacy == null) return null;
    final old = await legacy.read(key);
    if (old != null) {
      map[key] = old;
      await _save(map);
    }
    return old;
  }

  @override
  Future<void> write(String key, String value) async {
    final map = await _load();
    map[key] = value;
    await _save(map);
  }

  @override
  Future<void> delete(String key) async {
    final map = await _load();
    if (map.remove(key) != null) await _save(map);
    await _legacy?.delete(key);
  }

  @override
  Future<void> deletePrefix(String prefix) async {
    final map = await _load();
    final before = map.length;
    map.removeWhere((key, _) => key.startsWith(prefix));
    if (map.length != before) await _save(map);
    await _legacy?.deletePrefix(prefix);
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

    final exists = await file.exists();
    var parsed = exists ? _parseStateFile(await _readStateText(file)) : null;
    var restored = false;
    if (parsed == null) {
      // state.json is gone or unreadable. A reinstall may have wiped the app
      // directory while the secret store survived, so try the mirror first.
      final mirror = await _readMirror(secrets);
      parsed = mirror == null ? null : _parseStateFile(mirror);
      restored = parsed != null;
    }

    if (exists || restored) {
      if (parsed != null) {
        final loaded = await _loadState(parsed, secrets);
        final store = AppStore._(
          secrets: secrets,
          dir: dir,
          deviceId: parsed.deviceId ?? generateUuidV4(),
          profiles: loaded.profiles,
          issued: loaded.issued,
          settings: parsed.settings,
          notices: List<String>.of(loaded.notices),
        );
        if (restored) {
          store._notices.add('Серверы и ключи восстановлены после переустановки');
        }
        // Always rewrite: it also refreshes the secret-store mirror for installs
        // that predate it.
        await store._persist();
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
    final next = _writeChain.then((_) async {
      await _writeAtomic(dir, body);
      await _writeMirror(secrets, body);
    });
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

/// Copies the state.json text into [secrets] in chunks and drops stale chunks.
/// Failures are ignored: the mirror is a safety net, state.json stays the source.
Future<void> _writeMirror(SecretStore secrets, String body) async {
  try {
    final chunks = <String>[
      for (var i = 0; i < body.length; i += _mirrorChunkSize)
        body.substring(i, min(i + _mirrorChunkSize, body.length)),
    ];
    final oldCount = int.tryParse(await secrets.read(_mirrorCount) ?? '') ?? 0;
    for (var i = 0; i < chunks.length; i++) {
      await secrets.write('$_mirrorChunk$i', chunks[i]);
    }
    await secrets.write(_mirrorCount, '${chunks.length}');
    for (var i = chunks.length; i < oldCount; i++) {
      await secrets.delete('$_mirrorChunk$i');
    }
  } on Object {
    // Keep going without a mirror.
  }
}

/// Reads the mirror back. Returns null when it is absent or incomplete.
Future<String?> _readMirror(SecretStore secrets) async {
  try {
    final count = int.tryParse(await secrets.read(_mirrorCount) ?? '') ?? 0;
    if (count <= 0) return null;
    final buffer = StringBuffer();
    for (var i = 0; i < count; i++) {
      final chunk = await secrets.read('$_mirrorChunk$i');
      if (chunk == null) return null;
      buffer.write(chunk);
    }
    return buffer.toString();
  } on Object {
    return null;
  }
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

/// Reads state.json. Returns an empty string when the bytes are not valid UTF-8
/// or the file cannot be read, so the caller treats it as corrupted and moves it
/// aside instead of failing to start.
Future<String> _readStateText(File file) async {
  try {
    return await file.readAsString();
  } on FormatException {
    return '';
  } on FileSystemException {
    return '';
  }
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
    } on Object {
      // FormatException for a bad id/host/port, TypeError for a mangled field.
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
  // On Windows the rename can fail for a moment when an antivirus scanner or the
  // indexer holds the target open, so it is retried before giving up.
  for (var attempt = 0;; attempt++) {
    try {
      await temp.rename(target.path);
      return;
    } on FileSystemException {
      if (attempt >= 4) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 40 * (attempt + 1)));
    }
  }
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
