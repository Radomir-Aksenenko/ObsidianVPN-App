import 'package:obsidian_vpn/core/codec/client_config.dart';
import 'package:obsidian_vpn/core/codec/obsidian_key.dart';
import 'package:obsidian_vpn/vps/key_issuer.dart';

/// Rebuilds the owner key after a server change (SNI, IPv6 or reset).
///
/// [server] is the parsed owner key. Its server keys stay as they are, and only the
/// given settings change. The result has no expiry and 3 devices, like the deployer's
/// owner key. Keys issued earlier still carry the old settings.
({String key, ClientConfig config}) rebuildOwnerKey(
  ClientConfig server, {
  String? sni,
  bool? ipv6,
}) {
  var config = server;
  if (sni != null) {
    config = config.copyWith(realitySni: sni, sni: sni);
  }
  if (ipv6 != null) {
    config = config.copyWith(enableIpv6: ipv6);
  }
  final issued = issueKey(serverConfig: config, name: 'Owner', days: 0, devices: 3);
  return (key: issued.key, config: parseKey(issued.key));
}
