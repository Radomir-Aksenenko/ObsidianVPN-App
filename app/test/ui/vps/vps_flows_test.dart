import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/ui/vps/deploy_wizard_screen.dart';
import 'package:obsidian_vpn/ui/vps/issue_key_sheet.dart';
import 'package:obsidian_vpn/vps/deployer.dart';
import 'package:obsidian_vpn/vps/vps_models.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../support/fake_vpn_backend.dart';
import '../support.dart';
import 'vps_test_support.dart';

void main() {
  testWidgets('wizard asks for host and password before deploying', (tester) async {
    final state = await buildState(FakeVpnBackend());
    await pumpVps(tester, state, DeployWizardScreen(deployer: FakeDeployer()), size: const Size(390, 1400));

    await tester.tap(find.text('Развернуть'));
    await tester.pump();

    expect(find.text('Укажи IP или домен.'), findsOneWidget);
    expect(find.text('Введи пароль.'), findsOneWidget);
    expect(state.profiles, isEmpty);
  });

  testWidgets('successful deploy saves the server and shows the admin token once',
      (tester) async {
    final state = await buildState(FakeVpnBackend());
    final result = sampleDeployResult();
    final deployer = FakeDeployer(
      deployEvents: <DeployEvent>[
        const DeployProgress(40, 'Установка Docker'),
        const DeployLog('docker: ok'),
        DeployFinished<DeployResult>(result),
      ],
    );
    await pumpVps(tester, state, DeployWizardScreen(deployer: deployer), size: const Size(390, 1400));

    await tester.enterText(find.byType(TextField).at(0), '203.0.113.10');
    await tester.enterText(find.byType(TextField).at(3), 'secret-pass');
    await tester.tap(find.text('Развернуть'));
    await tester.pumpAndSettle();

    expect(find.textContaining('второй раз не покажем'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is SelectableText && w.data == 'tok-test-123'),
      findsOneWidget,
    );
    expect(state.profiles, hasLength(1));
    expect(state.profiles.single.source.name, 'vps');
    expect(state.selectedProfile?.id, state.profiles.single.id);
    expect(await state.adminToken(state.profiles.single.id), 'tok-test-123');
  });

  testWidgets('issue key sheet issues a key and shows it with a QR code', (tester) async {
    final state = await buildState(FakeVpnBackend());
    await state.saveVpsProfile(
      sampleDeployResult(),
      const VpsCredentials(host: '203.0.113.10', password: 'secret-pass'),
    );
    await pumpVps(
      tester,
      state,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showIssueKeySheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Выдать'));
    await tester.tap(find.text('Выдать'));
    await tester.pumpAndSettle();

    expect(state.issuedKeys, hasLength(1));
    expect(state.issuedKeys.single.key, startsWith('OBSDN-'));
    expect(state.issuedKeys.single.days, 30);
    expect(state.issuedKeys.single.devices, 3);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Гость'), findsOneWidget);
  });

  // pumpAndSettle never ends here: the progress bar animates for as long as the deploy runs.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  }

  Future<void> openWizard(WidgetTester tester, VpsDeployer deployer) async {
    final state = await buildState(FakeVpnBackend());
    await pumpVps(
      tester,
      state,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => DeployWizardScreen(deployer: deployer)),
            ),
            child: const Text('open'),
          ),
        ),
      ),
      size: const Size(390, 1400),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '203.0.113.10');
    await tester.enterText(find.byType(TextField).at(3), 'secret-pass');
    await tester.tap(find.text('Развернуть'));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('after a failed deploy back leaves without the interrupt prompt', (tester) async {
    final deployer = FakeDeployer(
      deployStream: () => Stream<DeployEvent>.error(const VpsException('boom')),
    );
    await openWizard(tester, deployer);

    expect(find.text('Операция не выполнена'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('Прервать установку?'), findsNothing);
    expect(find.byType(DeployWizardScreen), findsNothing);
  });

  testWidgets('leaving a running deploy asks first and cancels the stream', (tester) async {
    var cancelled = false;
    late StreamController<DeployEvent> controller;
    controller = StreamController<DeployEvent>(onCancel: () => cancelled = true);
    addTearDown(controller.close);
    await openWizard(tester, FakeDeployer(deployStream: () => controller.stream));

    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(find.text('Прервать установку?'), findsOneWidget);

    await tester.tap(find.text('Продолжить'));
    await settle(tester);
    expect(find.byType(DeployWizardScreen), findsOneWidget);
    expect(cancelled, isFalse);

    await tester.tap(find.byType(BackButton));
    await settle(tester);
    await tester.tap(find.text('Прервать'));
    await settle(tester);
    expect(find.byType(DeployWizardScreen), findsNothing);
    expect(cancelled, isTrue);
  });
}
