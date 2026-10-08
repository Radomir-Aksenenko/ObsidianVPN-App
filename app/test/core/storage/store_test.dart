import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/core/models/profile.dart';
import 'package:obsidian_vpn/core/models/split_tunnel.dart';
import 'package:obsidian_vpn/core/storage/store.dart';

import '../../support/vectors.dart';

/// Secret store whose writes always fail, to check that import keeps going.
final class _BrokenSecrets implements SecretStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {
    throw Exception('secret store is locked');
  }

  @override
  Future<void> delete(String key) async {}

  @override
  Future<void> deletePrefix(String prefix) async {}
}

const String _deviceId = '11111111-2222-4333-8444-555555555555';

void _writeLegacy(Directory legacy, String rawKey, String vpsKeyPath) {
  legacy.createSync(recursive: true);
  File('${legacy.path}${Platform.pathSeparator}device_id.txt')
      .writeAsStringSync('$_deviceId\n');
  File('${legacy.path}${Platform.pathSeparator}settings.json').writeAsStringSync(
    jsonEncode({
      'autostart': true,
      'minimize_to_tray': false,
      'kill_switch': true,
      'last_profile_id': 'old-key-1',
    }),
  );
  final servers = [
    {
      'id': 'old-key-1',
      'name': 'Helsinki',
      'config': {
        'server_host': 'legacy.example.net',
        'server_port': '8443',
        'server_public_key':
            '3f8a1c9e0b7d4f2a6e5c8b1d9f0a2c4e6b8d1f3a5c7e9b0d2f4a6c8e1b3d5f7a',
        'client_private_key': 'aa' * 32,
        'client_public_key': 'bb' * 32,
        'split_tunnel_mode': 'exclude',
        'split_sites': ['ya.ru'],
        'split_presets': ['ru'],
      },
      'raw_key': rawKey,
      'source': 'key',
      'flag': 'FI',
    },
    {
      'id': 'old-vps-1',
      'name': 'Lab VPS',
      'config': {
        'server_host': '203.0.113.50',
        'server_port': '8443',
        'server_public_key':
            '3f8a1c9e0b7d4f2a6e5c8b1d9f0a2c4e6b8d1f3a5c7e9b0d2f4a6c8e1b3d5f7a',
      },
      'raw_key': '',
      'source': 'vps',
      'ssh_host': '203.0.113.50',
      'ssh_port': 22,
      'ssh_user': 'root',
      'ssh_auth': 'password',
      'ssh_password_secret': 'pa55 word',
      'ssh_key_path': vpsKeyPath,
      'keyserver_admin_token': 'tok123',
      'server_version': '1.2.3',
      'needs_update': true,
    },
  ];
  File('${legacy.path}${Platform.pathSeparator}servers.json')
      .writeAsStringSync(jsonEncode(servers));
  File('${legacy.path}${Platform.pathSeparator}issued.json').writeAsStringSync(
    jsonEncode([
      {
        'id': 'iss-1',
        'name': 'Phone',
        'server_id': 'srv-1',
        'server_code': 'DE-FRA-01',
        'devices': 2,
        'days': 30,
        'key': rawKey,
        'created': '2026-05-01T10:00:00Z',
      },
    ]),
  );
}

void main() {
  late Directory temp;
  late String dir;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('obsidian_store_');
    dir = '${temp.path}${Platform.pathSeparator}app';
  });
  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  test('creates state.json, keeps the device id across reopen, leaves no temp file', () async {
    final first = await AppStore.open(dir: dir, secrets: MemorySecretStore());
    expect(uuid.hasMatch(first.deviceId), isTrue);
    expect(File('$dir${Platform.pathSeparator}state.json').existsSync(), isTrue);
    expect(File('$dir${Platform.pathSeparator}state.json.tmp').existsSync(), isFalse);

    final second = await AppStore.open(dir: dir, secrets: MemorySecretStore());
    expect(second.deviceId, first.deviceId);
  });

  test('profiles and settings survive reopen; no secret reaches state.json', () async {
    final secrets = MemorySecretStore();
    final store = await AppStore.open(dir: dir, secrets: secrets);
    final profile = ServerProfile(
      id: generateUuidV4(),
      name: 'Франкфурт',
      countryCode: 'DE',
      host: '203.0.113.10',
      port: 8443,
      serverPublicKey: 'ab' * 32,
      source: ProfileSource.key,
      createdAt: DateTime.utc(2026, 1, 2),
      split: SplitTunnelConfig(
        mode: SplitMode.exclude,
        entries: const ['example.com'],
        presets: const {SplitPreset.telegram},
      ),
      isFavorite: true,
    );
    await store.putProfile(profile);
    await secrets.write(
      SecretKeys.profile(profile.id, SecretKeys.rawKey),
      'obsidian://SECRETKEY@203.0.113.10:8443',
    );
    await store.setSettings(
      AppSettings(killSwitch: true, lastProfileId: profile.id, themeMode: AppThemeMode.dark),
    );

    final reopened = await AppStore.open(dir: dir, secrets: secrets);
    final loaded = reopened.profiles.single;
    expect(loaded.name, 'Франкфурт');
    expect(loaded.isFavorite, isTrue);
    expect(loaded.split.mode, SplitMode.exclude);
    expect(loaded.split.presets, {SplitPreset.telegram});
    expect(reopened.settings.killSwitch, isTrue);
    expect(reopened.settings.themeMode, AppThemeMode.dark);
    expect(reopened.settings.lastProfileId, profile.id);

    final raw = File('$dir${Platform.pathSeparator}state.json').readAsStringSync();
    expect(raw, isNot(contains('SECRETKEY')));
  });

  test('a corrupted state.json is moved to state.json.bad and the store starts empty', () async {
    Directory(dir).createSync(recursive: true);
    final garbage = '{not json at all';
    File('$dir${Platform.pathSeparator}state.json').writeAsStringSync(garbage);
    final legacy = Directory('${temp.path}${Platform.pathSeparator}legacy');
    _writeLegacy(legacy, parseVectorInput('obsidian_legacy_aliases_no_port'), '');

    final store = await AppStore.open(
      dir: dir,
      secrets: MemorySecretStore(),
      legacyDir: legacy.path,
    );

    expect(store.profiles, isEmpty);
    expect(store.notices.single, contains('state.json.bad'));
    expect(
      File('$dir${Platform.pathSeparator}state.json.bad').readAsStringSync(),
      garbage,
    );
    final fresh = jsonDecode(
      File('$dir${Platform.pathSeparator}state.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(fresh['schema'], kStateSchemaVersion);
    expect(fresh['device_id'], store.deviceId);
  });

  test('a state file from a newer schema is treated as unreadable', () async {
    Directory(dir).createSync(recursive: true);
    File('$dir${Platform.pathSeparator}state.json')
        .writeAsStringSync(jsonEncode({'schema': kStateSchemaVersion + 1}));

    final store = await AppStore.open(dir: dir, secrets: MemorySecretStore());

    expect(store.profiles, isEmpty);
    expect(
      File('$dir${Platform.pathSeparator}state.json.bad').existsSync(),
      isTrue,
    );
  });

  test('legacy desktop data is imported once and the old files are kept', () async {
    final legacy = Directory('${temp.path}${Platform.pathSeparator}legacy');
    final keyPath = '${legacy.path}${Platform.pathSeparator}id_ed25519';
    _writeLegacy(legacy, parseVectorInput('obsidian_legacy_aliases_no_port'), keyPath);
    File(keyPath).writeAsStringSync('-----BEGIN OPENSSH PRIVATE KEY-----\nAAA\n');
    final secrets = MemorySecretStore();

    final store = await AppStore.open(
      dir: dir,
      secrets: secrets,
      legacyDir: legacy.path,
    );

    expect(store.deviceId, _deviceId);
    expect(store.profiles, hasLength(2));
    final key = store.profiles.first;
    expect(key.name, 'Helsinki');
    expect(key.countryCode, 'FI');
    expect(key.host, 'legacy.example.net');
    expect(key.port, 8443);
    expect(key.split.mode, SplitMode.exclude);
    expect(key.split.entries, ['ya.ru']);
    expect(key.split.presets, {SplitPreset.ru});
    expect(secrets.values[SecretKeys.profile(key.id, SecretKeys.rawKey)],
        parseVectorInput('obsidian_legacy_aliases_no_port'));
    expect(secrets.values[SecretKeys.profile(key.id, SecretKeys.clientPrivateKey)], 'aa' * 32);
    expect(secrets.values[SecretKeys.profile(key.id, SecretKeys.clientPublicKey)], 'bb' * 32);

    final vps = store.profiles.last;
    expect(vps.source, ProfileSource.vps);
    expect(vps.vps?.host, '203.0.113.50');
    expect(vps.vps?.user, 'root');
    expect(vps.countryCode, 'VPN');
    expect(vps.serverVersion, '1.2.3');
    expect(vps.needsUpdate, isTrue);
    expect(secrets.values[SecretKeys.profile(vps.id, SecretKeys.vpsPassword)], 'pa55 word');
    expect(secrets.values[SecretKeys.profile(vps.id, SecretKeys.adminToken)], 'tok123');
    expect(
      secrets.values[SecretKeys.profile(vps.id, SecretKeys.vpsPrivateKeyPem)],
      contains('OPENSSH'),
    );

    expect(store.settings.autostart, isTrue);
    expect(store.settings.minimizeToTray, isFalse);
    expect(store.settings.killSwitch, isTrue);
    expect(store.settings.lastProfileId, 'old-key-1');

    final issued = store.issuedKeys.single;
    expect(issued.name, 'Phone');
    expect(issued.devices, 2);
    expect(issued.uri, startsWith('obsidian://'));
    expect(secrets.values[SecretKeys.issued('iss-1', SecretKeys.issuedKey)],
        parseVectorInput('obsidian_legacy_aliases_no_port'));

    expect(File('${legacy.path}${Platform.pathSeparator}servers.json').existsSync(), isTrue);
    expect(File('${legacy.path}${Platform.pathSeparator}issued.json').existsSync(), isTrue);
    expect(File('${legacy.path}${Platform.pathSeparator}device_id.txt').existsSync(), isTrue);

    // A second start with the same legacy folder must not import again.
    final again = await AppStore.open(
      dir: dir,
      secrets: secrets,
      legacyDir: legacy.path,
    );
    expect(again.profiles, hasLength(2));
    expect(again.issuedKeys, hasLength(1));
    expect(again.deviceId, _deviceId);
  });

  test('migration keeps going when the secret store refuses writes', () async {
    final legacy = Directory('${temp.path}${Platform.pathSeparator}legacy');
    _writeLegacy(
      legacy,
      parseVectorInput('obsidian_legacy_aliases_no_port'),
      '${legacy.path}${Platform.pathSeparator}missing_key',
    );

    final store = await AppStore.open(
      dir: dir,
      secrets: _BrokenSecrets(),
      legacyDir: legacy.path,
    );

    expect(store.profiles, hasLength(2));
    expect(store.notices, isNotEmpty);
  });

  test('a state.json with invalid UTF-8 is moved aside instead of crashing', () async {
    Directory(dir).createSync(recursive: true);
    File('$dir${Platform.pathSeparator}state.json')
        .writeAsBytesSync(<int>[0x7b, 0x22, 0xff, 0xfe, 0xc3, 0x28, 0x7d]);

    final store = await AppStore.open(dir: dir, secrets: MemorySecretStore());

    expect(store.profiles, isEmpty);
    expect(store.notices, isNotEmpty);
    expect(File('$dir${Platform.pathSeparator}state.json.bad').existsSync(), isTrue);
  });

  test('a profile with mangled field types is skipped, the rest still loads', () async {
    final good = {
      'id': 'good-1',
      'name': 'Good',
      'host': 'good.example.net',
      'port': 443,
      'server_public_key': 'ab' * 32,
    };
    final bad = {
      'id': 'bad-1',
      'host': 'bad.example.net',
      'port': 443,
      'vps': {'host': 'x', 'port': 22, 'user': 'root'},
      'split': 'not-a-map',
      'created_at': 12,
    };
    final mangled = {'id': 'bad-2', 'host': 'h', 'port': 443, 'vps': 5, 'is_favorite': 'yes'};
    Directory(dir).createSync(recursive: true);
    File('$dir${Platform.pathSeparator}state.json').writeAsStringSync(
      jsonEncode({
        'schema': 1,
        'device_id': _deviceId,
        'settings': {},
        'profiles': [good, bad, mangled],
        'issued_keys': [],
      }),
    );

    final store = await AppStore.open(dir: dir, secrets: MemorySecretStore());

    expect(store.profiles.map((p) => p.id), contains('good-1'));
  });
}
