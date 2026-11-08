import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/core/models/profile.dart';
import 'package:obsidian_vpn/core/models/split_tunnel.dart';
import 'package:obsidian_vpn/core/storage/store.dart';

ServerProfile _profile(String name) => ServerProfile(
  id: 'id-$name',
  name: name,
  countryCode: 'DE',
  host: '203.0.113.10',
  port: 8443,
  serverPublicKey: 'ab' * 32,
  source: ProfileSource.key,
  createdAt: DateTime.utc(2026, 1, 2),
  split: SplitTunnelConfig(),
);

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('obsidian_reinstall_'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('servers come back from the secret-store mirror when the directory is wiped', () async {
    final secrets = MemorySecretStore();
    final first = Directory('${temp.path}/a')..createSync();
    final store = await AppStore.open(dir: first.path, secrets: secrets);
    for (var i = 0; i < 12; i++) {
      await store.putProfile(_profile('Сервер-$i'));
    }
    await store.secrets.write(SecretKeys.profile('id-Сервер-0', SecretKeys.rawKey), 'KEY');

    // A reinstall: new empty directory, same keychain.
    final second = Directory('${temp.path}/b')..createSync();
    final reopened = await AppStore.open(dir: second.path, secrets: secrets);
    expect(reopened.profiles.map((p) => p.name), [for (var i = 0; i < 12; i++) 'Сервер-$i']);
    expect(reopened.deviceId, store.deviceId);
    expect(await reopened.secrets.read(SecretKeys.profile('id-Сервер-0', SecretKeys.rawKey)), 'KEY');
    expect(File('${second.path}/state.json').existsSync(), isTrue);
  });

  test('a shrinking state drops stale mirror chunks', () async {
    final secrets = MemorySecretStore();
    final store = await AppStore.open(dir: temp.path, secrets: secrets);
    for (var i = 0; i < 12; i++) {
      await store.putProfile(_profile('s$i'));
    }
    for (var i = 0; i < 12; i++) {
      await store.removeProfile('id-s$i');
    }
    final count = int.parse(secrets.values['state.mirror.count']!);
    expect(secrets.values.keys.where((k) => k.startsWith('state.mirror.') && k != 'state.mirror.count').length, count);
  });

  test('FileSecretStore persists, and copies legacy secrets on first read', () async {
    final legacy = MemorySecretStore();
    await legacy.write('old', 'value');
    final store = FileSecretStore(dir: temp.path, legacy: legacy);
    expect(await store.read('old'), 'value');
    await store.write('new', 'x');

    final again = FileSecretStore(dir: temp.path);
    expect(await again.read('old'), 'value');
    expect(await again.read('new'), 'x');
    await again.deletePrefix('ne');
    expect(await FileSecretStore(dir: temp.path).read('new'), isNull);
  });
}
