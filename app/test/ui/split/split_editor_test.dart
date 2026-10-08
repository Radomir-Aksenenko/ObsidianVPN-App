import 'package:flutter/material.dart' hide Durations;
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/core/models/split_tunnel.dart';
import 'package:obsidian_vpn/platform_info.dart';
import 'package:obsidian_vpn/ui/widgets/widgets.dart';

import '../../support/fake_vpn_backend.dart';
import '../support.dart';

const _profileId = '11111111-1111-4111-8111-111111111111';

/// Opens the split editor for the only server through the Servers tab.
Future<void> _openEditor(WidgetTester tester) async {
  await tester.tap(find.text('Серверы'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Действия'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Раздельный туннель'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => debugPlatformOverride = TargetPlatform.android);
  tearDown(() => debugPlatformOverride = null);

  testWidgets('shows an issue for "*.ru" and saves the valid rules', (
    tester,
  ) async {
    final state = await buildState(FakeVpnBackend(), profiles: [fakeProfile()]);
    await pumpApp(tester, state);
    await _openEditor(tester);

    await tester.tap(find.text('Только список'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '*.ru\nexample.com');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Не распознано'), findsOneWidget);
    expect(find.text('*.ru'), findsOneWidget);
    expect(find.text('Принято правил: 1'), findsOneWidget);
    expect(find.text('Список пуст: через VPN сейчас ничего не идет.'), findsNothing);

    await tester.tap(find.widgetWithText(ObsButton, 'Сохранить'));
    await tester.pumpAndSettle();

    final saved = state.profileById(_profileId)!.split;
    expect(saved.mode, SplitMode.include);
    expect(saved.entries, ['example.com']);
    expect(find.textContaining('Пропущено строк: 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('include mode with nothing effective warns', (tester) async {
    final state = await buildState(FakeVpnBackend(), profiles: [fakeProfile()]);
    await pumpApp(tester, state);
    await _openEditor(tester);

    await tester.tap(find.text('Только список'));
    await tester.pump();

    expect(
      find.text('Список пуст: через VPN сейчас ничего не идет.'),
      findsOneWidget,
    );
  });

  testWidgets('leaving with unsaved changes asks first; Discard leaves', (
    tester,
  ) async {
    final state = await buildState(FakeVpnBackend(), profiles: [fakeProfile()]);
    await pumpApp(tester, state);
    await _openEditor(tester);

    await tester.enterText(find.byType(TextField), 'example.org');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();

    expect(find.text('Сохранить изменения?'), findsOneWidget);
    await tester.tap(find.widgetWithText(ObsButton, 'Остаться'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ObsButton, 'Не сохранять'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(state.profileById(_profileId)!.split.entries, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

