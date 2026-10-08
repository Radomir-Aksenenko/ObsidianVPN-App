import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/core/codec/client_config.dart';
import 'package:obsidian_vpn/core/codec/obsidian_key.dart';
import 'package:obsidian_vpn/vps/vps_models.dart';

import '../../support/fake_vpn_backend.dart';
import '../support.dart';
import 'vps_test_support.dart';

void main() {
  test('updateVpsProfile replaces creds, host key, version and owner key', () async {
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
      creds: const VpsCredentials(host: '203.0.113.10', port: 2222, user: 'admin', password: 'new-pass'),
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
  });

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
}
