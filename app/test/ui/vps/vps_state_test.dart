import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/core/codec/client_config.dart';
import 'package:obsidian_vpn/core/codec/obsidian_key.dart';
import 'package:obsidian_vpn/vps/key_issuer.dart';
import 'package:obsidian_vpn/vps/vps_models.dart';

import '../../support/fake_vpn_backend.dart';
import '../support.dart';
import 'vps_test_support.dart';

void main() {
  test(
    'updateVpsProfile replaces creds, host key, version and owner key',
    () async {
      final state = await buildState(FakeVpnBackend());
      final saved = await state.saveVpsProfile(
        sampleDeployResult(),
        const VpsCredentials(host: '203.0.113.10', password: 'old-pass'),
      );
      final id = saved.id;

      final newOwner = ClientConfig(
        serverHost: '203.0.113.10',
        serverPort: '8443',
        serverPublicKey: 'EF' * 32,
        realitySni: 'www.apple.com',
      );
      final newKey = encodeObsdn(newOwner);

      final updated = await state.updateVpsProfile(
        id,
        creds: const VpsCredentials(
          host: '203.0.113.10',
          port: 2222,
          user: 'admin',
          password: 'new-pass',
        ),
        hostKey: 'SHA256:pinned',
        serverVersion: '0.2.0',
        needsUpdate: false,
        ownerKey: newKey,
        ownerConfig: parseKey(newKey),
        adminToken: 'tok-2',
      );

      expect(updated.vps?.port, 2222);
      expect(updated.vps?.user, 'admin');
      expect(updated.vpsHostKey, 'SHA256:pinned');
      expect(updated.serverVersion, '0.2.0');
      expect(updated.needsUpdate, isFalse);
      expect(updated.port, 8443);
      expect(updated.serverPublicKey, 'ef' * 32);

      final creds = await state.vpsCredentials(id);
      expect(creds?.password, 'new-pass');
      expect(creds?.hostKeyFingerprint, 'SHA256:pinned');
      expect(await state.ownerKey(id), newKey);
      expect(await state.adminToken(id), 'tok-2');
    },
  );

  test('updateVpsProfile without creds keeps stored secrets', () async {
    final state = await buildState(FakeVpnBackend());
    final saved = await state.saveVpsProfile(
      sampleDeployResult(),
      const VpsCredentials(host: '203.0.113.10', password: 'keep-me'),
    );

    await state.updateVpsProfile(saved.id, needsUpdate: true);

    expect((await state.vpsCredentials(saved.id))?.password, 'keep-me');
    expect(state.profileById(saved.id)?.needsUpdate, isTrue);
  });

  test('applyVpsReset drops the keys issued from that server only', () async {
    final state = await buildState(FakeVpnBackend());
    final server = await state.saveVpsProfile(
      sampleDeployResult(),
      const VpsCredentials(host: '203.0.113.10'),
    );
    final other = await state.saveVpsProfile(
      sampleDeployResult(host: '203.0.113.20'),
      const VpsCredentials(host: '203.0.113.20'),
    );
    await state.addIssuedKey(_issued('k-a', server.id));
    await state.addIssuedKey(_issued('k-b', server.id));
    await state.addIssuedKey(_issued('k-other', other.id));

    final owner = issueKey(serverConfig: _server(), name: 'Owner', devices: 3);
    final removed = await state.applyVpsReset(
      server.id,
      ResetResult(
        serverPublicKey: 'ef' * 32,
        realityAuthKey: 'ff' * 32,
        realitySni: 'www.apple.com',
        ownerKey: owner.key,
        ownerConfig: parseKey(owner.key),
      ),
      hostKey: 'SHA256:reset',
    );

    expect(removed, 2);
    expect(state.issuedKeys.map((k) => k.id), ['k-other']);
    expect(await state.ownerKey(server.id), owner.key);
    expect(state.profileById(server.id)?.vpsHostKey, 'SHA256:reset');
  });

  test(
    'applyVpsUpdate on a new TCP port rebuilds the owner key on that port',
    () async {
      final state = await buildState(FakeVpnBackend());
      final saved = await state.saveVpsProfile(
        sampleDeployResult(),
        const VpsCredentials(host: '203.0.113.10', password: 'pass'),
      );

      final changed = await state.applyVpsUpdate(
        saved.id,
        const UpdateResult(
          tcpPort: 8443,
          udpPort: 8444,
          realityEnabled: true,
          realityAuthKey: 'cd',
          sni: 'www.microsoft.com',
          ipv6: false,
        ),
        serverVersion: '0.2.0',
        hostKey: 'SHA256:updated',
      );

      expect(changed, isTrue);
      final profile = state.profileById(saved.id)!;
      expect(profile.port, 8443);
      expect(profile.serverVersion, '0.2.0');
      expect(profile.needsUpdate, isFalse);
      expect(profile.vpsHostKey, 'SHA256:updated');
      final rebuilt = parseKey((await state.ownerKey(saved.id))!);
      expect(rebuilt.serverPort, '8443');
      expect(rebuilt.udpPort, '8444');
      expect(rebuilt.serverPublicKey, saved.serverPublicKey);
      expect(rebuilt.realitySni, 'www.microsoft.com');
    },
  );

  test('applyVpsUpdate on the same port keeps the owner key', () async {
    final state = await buildState(FakeVpnBackend());
    final saved = await state.saveVpsProfile(
      sampleDeployResult(),
      const VpsCredentials(host: '203.0.113.10'),
    );
    final before = await state.ownerKey(saved.id);

    final changed = await state.applyVpsUpdate(
      saved.id,
      const UpdateResult(
        tcpPort: 443,
        udpPort: 443,
        realityEnabled: true,
        realityAuthKey: 'cd',
        sni: 'www.microsoft.com',
        ipv6: false,
      ),
      serverVersion: '0.2.0',
    );

    expect(changed, isFalse);
    expect(await state.ownerKey(saved.id), before);
    expect(state.profileById(saved.id)?.serverVersion, '0.2.0');
  });
}

IssuedKey _issued(String id, String serverId) {
  return IssuedKey(
    id: id,
    name: 'Key $id',
    serverId: serverId,
    devices: 1,
    days: 30,
    key: 'OBSDN-$id',
    uri: 'obsidian://$id',
    created: DateTime.utc(2026, 9, 1),
  );
}

ClientConfig _server() {
  return ClientConfig(
    serverHost: '203.0.113.10',
    serverPort: '443',
    serverPublicKey: 'ab' * 32,
    realityEnabled: true,
    realityAuthKey: 'cd' * 32,
    realitySni: 'www.microsoft.com',
    sni: 'www.microsoft.com',
  );
}
