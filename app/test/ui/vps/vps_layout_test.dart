import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/ui/vps/access_screen.dart';
import 'package:obsidian_vpn/ui/vps/deploy_wizard_screen.dart';
import 'package:obsidian_vpn/ui/vps/issue_key_sheet.dart';
import 'package:obsidian_vpn/ui/vps/issued_key_screen.dart';
import 'package:obsidian_vpn/ui/vps/server_manage_screen.dart';
import 'package:obsidian_vpn/ui/widgets/widgets.dart';
import 'package:obsidian_vpn/state/app_state.dart';
import 'package:obsidian_vpn/vps/key_issuer.dart';
import 'package:obsidian_vpn/vps/vps_models.dart';

import '../../support/fake_vpn_backend.dart';
import '../support.dart';
import 'vps_test_support.dart';

const String _longHost = 'very-long-subdomain.of-some-extremely-long-hostname.example-company.net';
const String _longName = 'Очень длинное имя ключа для проверки переполнения строки в списке';

/// Pumps [child] at 360 px wide with text scale 1.3 and expects no layout exception.
Future<void> _pumpNarrow(
  WidgetTester tester,
  AppState state,
  Widget child, {
  double height = 800,
}) async {
  await pumpVps(
    tester,
    state,
    MediaQuery(
      data: MediaQueryData(
        size: Size(360, height),
        textScaler: const TextScaler.linear(1.3),
      ),
      child: child,
    ),
    size: Size(360, height),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('manage screen with a long host fits 360 px at text scale 1.3', (tester) async {
    final state = await buildState(FakeVpnBackend());
    final saved = await state.saveVpsProfile(
      sampleDeployResult(host: _longHost),
      const VpsCredentials(host: _longHost, user: 'administrator-with-long-name', password: 'pw'),
    );
    await _pumpNarrow(tester, state, ServerManageScreen(profileId: saved.id), height: 1600);
    expect(tester.takeException(), isNull);
  });

  testWidgets('access screen with long names fits 360 px at text scale 1.3', (tester) async {
    final state = await buildState(FakeVpnBackend());
    final saved = await state.saveVpsProfile(
      sampleDeployResult(host: _longHost),
      const VpsCredentials(host: _longHost, password: 'pw'),
    );
    final owner = await state.ownerKey(saved.id);
    expect(owner, isNotNull);
    await state.addIssuedKey(
      IssuedKey(
        id: 'k1',
        name: _longName,
        serverId: saved.id,
        devices: 3,
        days: 30,
        key: 'OBSDN-x',
        uri: 'obsidian://x',
        created: DateTime.now().toUtc(),
      ),
    );
    await _pumpNarrow(tester, state, const Scaffold(body: AccessScreen()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('issued key screen with a long name fits 360 px at text scale 1.3', (tester) async {
    final state = await buildState(FakeVpnBackend());
    final saved = await state.saveVpsProfile(
      sampleDeployResult(host: _longHost),
      const VpsCredentials(host: _longHost, password: 'pw'),
    );
    final issued = IssuedKey(
      id: 'k1',
      name: _longName,
      serverId: saved.id,
      devices: 3,
      days: 30,
      key: 'OBSDN-${'x' * 300}',
      uri: 'obsidian://abc@host:443#label',
      created: DateTime.now().toUtc(),
    );
    await _pumpNarrow(tester, state, IssuedKeyScreen(issued: issued), height: 1600);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deploy form fits 360 px at text scale 1.3', (tester) async {
    final state = await buildState(FakeVpnBackend());
    await _pumpNarrow(tester, state, DeployWizardScreen(deployer: FakeDeployer()), height: 1600);
    expect(tester.takeException(), isNull);
  });

  testWidgets('issue key sheet caps the key name length', (tester) async {
    final state = await buildState(FakeVpnBackend());
    await state.saveVpsProfile(
      sampleDeployResult(),
      const VpsCredentials(host: '203.0.113.10', password: 'pw'),
    );
    await pumpVps(
      tester,
      state,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showIssueKeySheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'я' * 200);
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text.length, kMaxKeyNameLength);
  });

  testWidgets('a tall sheet scrolls and stays above the keyboard instead of overflowing', (
    tester,
  ) async {
    final state = await buildState(FakeVpnBackend());
    await pumpVps(
      tester,
      state,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAdaptiveSheet<void>(
              context,
              (_) => const ObsSheet(
                title: 'Tall',
                child: Column(
                  children: [SizedBox(height: 900, child: Text('content')), TextField()],
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
      size: const Size(360, 600),
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The last field is reachable by scrolling.
    await tester.scrollUntilVisible(find.byType(TextField), 200, scrollable: find.byType(Scrollable).last);
    final bottom = tester.getBottomLeft(find.byType(TextField)).dy;
    expect(bottom, lessThanOrEqualTo(600 - 280));
  });
}
