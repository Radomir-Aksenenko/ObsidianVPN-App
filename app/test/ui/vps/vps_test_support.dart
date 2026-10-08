import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/core/codec/client_config.dart';
import 'package:obsidian_vpn/core/codec/obsidian_key.dart';
import 'package:obsidian_vpn/l10n/app_localizations.dart';
import 'package:obsidian_vpn/state/app_state.dart';
import 'package:obsidian_vpn/theme/theme.dart';
import 'package:obsidian_vpn/vps/deployer.dart';
import 'package:obsidian_vpn/vps/key_issuer.dart';
import 'package:obsidian_vpn/vps/vps_models.dart';

/// Pumps [home] with the app's state scope, theme and Russian localizations.
Future<void> pumpVps(
  WidgetTester tester,
  AppState state,
  Widget home, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    AppScope(
      state: state,
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildTheme(Brightness.dark),
        home: home,
      ),
    ),
  );
  await tester.pump();
}

/// Deployer that replays fixed events instead of talking to SSH.
class FakeDeployer extends VpsDeployer {
  FakeDeployer({this.deployEvents = const <DeployEvent>[]});

  final List<DeployEvent> deployEvents;

  @override
  Stream<DeployEvent> deploy(DeployRequest request) => Stream.fromIterable(deployEvents);
}

/// A deploy result with a real OBSDN owner key for [host].
DeployResult sampleDeployResult({String host = '203.0.113.10', String token = 'tok-test-123'}) {
  final owner = issueKey(
    serverConfig: ClientConfig(
      serverHost: host,
      serverPort: '443',
      serverPublicKey: 'ab' * 32,
      realityEnabled: true,
      realityAuthKey: 'cd' * 32,
      realitySni: 'www.microsoft.com',
      sni: 'www.microsoft.com',
    ),
    name: 'Owner',
    devices: 3,
  );
  return DeployResult(
    ownerKey: owner.key,
    ownerConfig: parseKey(owner.key),
    adminToken: token,
    tcpPort: 443,
    udpPort: 443,
    sni: 'www.microsoft.com',
    ipv6: false,
    serverVersion: '0.1.0',
    hostKeyFingerprint: 'SHA256:test-fingerprint',
  );
}
