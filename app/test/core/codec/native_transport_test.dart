import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/core/codec/client_config.dart';
import 'package:obsidian_vpn/core/codec/obsidian_key.dart';
import 'package:obsidian_vpn/vps/key_issuer.dart';

void main() {
  test('native REALITY survives JSON, copy and both share formats', () {
    final cfg = ClientConfig(
      serverHost: '127.0.0.1',
      serverPort: '443',
      serverPublicKey: List.filled(64, '1').join(),
      transport: 'native-reality',
      realityPublicKey: List.filled(64, '2').join(),
      realityShortId: '1234567890abcdef',
      realitySni: 'example.com',
      enableUdpData: true,
    );
    final guest = issueKey(serverConfig: cfg, name: 'native guest');
    for (final decoded in [
      ClientConfig.fromJson(cfg.toJson()),
      cfg.copyWith(label: 'copy'),
      parseKey(encodeObsdn(cfg)),
      parseKey(encodeUri(cfg)),
      parseKey(guest.key),
      parseKey(guest.uri),
    ]) {
      expect(decoded.transport, 'native-reality');
      expect(decoded.realityPublicKey, cfg.realityPublicKey);
      expect(decoded.realityShortId, cfg.realityShortId);
      expect(decoded.realitySni, cfg.realitySni);
      expect(decoded.allowDirectUdp, isFalse);
    }
  });
}
