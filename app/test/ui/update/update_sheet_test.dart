import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/app_version.dart';
import 'package:obsidian_vpn/core/update/update_checker.dart';
import 'package:obsidian_vpn/l10n/app_localizations.dart';
import 'package:obsidian_vpn/state/app_state.dart';
import 'package:obsidian_vpn/theme/theme.dart';
import 'package:obsidian_vpn/ui/update/update_sheet.dart';

import '../../support/fake_vpn_backend.dart';
import '../support.dart';

const AppRelease _release = AppRelease(
  version: '2.1.0',
  tagName: 'v2.1.0',
  htmlUrl: 'https://github.com/example/app/releases/tag/v2.1.0',
  notes: 'Быстрее переподключение',
  publishedAt: null,
  assets: [],
);

/// A host page with one button that opens the update sheet for [release].
Future<void> _pumpHost(
  WidgetTester tester,
  AppState state, {
  AppRelease release = _release,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    AppScope(
      state: state,
      child: MaterialApp(
        locale: const Locale('ru'),
        theme: buildTheme(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showUpdateSheet(context, release),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'the sheet shows the new version, the installed one and the notes',
    (tester) async {
      final state = await buildState(FakeVpnBackend());
      await _pumpHost(tester, state);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Вышла версия 2.1.0'), findsOneWidget);
      expect(find.text('Сейчас установлена $kAppVersion'), findsOneWidget);
      expect(find.text('Что изменилось'), findsOneWidget);
      expect(find.text('Быстрее переподключение'), findsOneWidget);
      expect(find.text('Скачать'), findsOneWidget);
      expect(find.text('Позже'), findsOneWidget);
    },
  );

  testWidgets('the notes block is hidden when the release has none', (
    tester,
  ) async {
    final state = await buildState(FakeVpnBackend());
    await _pumpHost(
      tester,
      state,
      release: const AppRelease(
        version: '2.1.0',
        tagName: 'v2.1.0',
        htmlUrl: 'https://github.com/example/app/releases/tag/v2.1.0',
        notes: '   ',
        publishedAt: null,
        assets: [],
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Вышла версия 2.1.0'), findsOneWidget);
    expect(find.text('Что изменилось'), findsNothing);
  });

  testWidgets(
    '"Пропустить эту версию" stores the version and closes the sheet',
    (tester) async {
      final state = await buildState(FakeVpnBackend());
      await _pumpHost(tester, state);
      expect(state.settings.skippedUpdateVersion, isNull);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Пропустить эту версию'));
      await tester.pumpAndSettle();

      expect(state.settings.skippedUpdateVersion, '2.1.0');
      expect(find.text('Вышла версия 2.1.0'), findsNothing);
    },
  );
}
