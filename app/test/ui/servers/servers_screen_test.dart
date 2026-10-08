import 'package:flutter/material.dart' hide Durations;
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/platform_info.dart';
import 'package:obsidian_vpn/ui/widgets/widgets.dart';

import '../../support/fake_vpn_backend.dart';
import '../../support/vectors.dart';
import '../support.dart';

const _frankfurtId = '11111111-1111-4111-8111-111111111111';
const _amsterdamId = '22222222-2222-4222-8222-222222222222';

Future<void> _openServers(WidgetTester tester) async {
  await tester.tap(find.text('Серверы'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => debugPlatformOverride = TargetPlatform.android);
  tearDown(() => debugPlatformOverride = null);

  testWidgets('list renders profiles, favorites group first', (tester) async {
    final favorite = fakeProfile(
      id: _amsterdamId,
      name: 'Amsterdam',
      country: 'NL',
      host: 'ams.example.net',
    ).copyWith(isFavorite: true);
    final state = await buildState(
      FakeVpnBackend(),
      profiles: [fakeProfile(), favorite],
    );
    await pumpApp(tester, state);
    await _openServers(tester);

    expect(find.text('Избранное'), findsOneWidget);
    expect(find.text('Все серверы'), findsOneWidget);
    expect(find.text('Amsterdam'), findsOneWidget);
    expect(find.text('ams.example.net'), findsOneWidget);
    expect(find.text('Frankfurt'), findsOneWidget);
    expect(find.text('fra.example.net'), findsOneWidget);
    expect(find.text('Добавить ключ'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Favorites render above the rest.
    final favoritesY = tester.getTopLeft(find.text('Избранное')).dy;
    final allY = tester.getTopLeft(find.text('Все серверы')).dy;
    expect(favoritesY, lessThan(allY));
  });

  testWidgets('tapping a row selects that server', (tester) async {
    final state = await buildState(
      FakeVpnBackend(),
      profiles: [
        fakeProfile(),
        fakeProfile(id: _amsterdamId, name: 'Amsterdam', host: 'ams.example.net'),
      ],
    );
    await pumpApp(tester, state);
    await _openServers(tester);

    expect(state.selectedProfile?.id, _frankfurtId);
    await tester.tap(find.text('Amsterdam'));
    await tester.pumpAndSettle();
    expect(state.selectedProfile?.id, _amsterdamId);
  });

  testWidgets('empty list shows the empty state with the add action', (
    tester,
  ) async {
    final state = await buildState(FakeVpnBackend());
    await pumpApp(tester, state);
    await _openServers(tester);

    expect(
      find.text('Добавь первый сервер: вставь ключ доступа.'),
      findsOneWidget,
    );
    expect(find.text('Добавить ключ'), findsOneWidget);
  });

  testWidgets('add sheet: garbage keeps Add disabled, valid key saves and selects', (
    tester,
  ) async {
    final state = await buildState(
      FakeVpnBackend(),
      profiles: [fakeProfile()],
    );
    await pumpApp(tester, state);
    await _openServers(tester);

    await tester.tap(find.widgetWithText(ObsButton, 'Добавить ключ'));
    await tester.pumpAndSettle();

    final keyField = find.byType(TextField).first;
    await tester.enterText(keyField, 'не ключ вовсе');
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester.widget<ObsButton>(find.widgetWithText(ObsButton, 'Добавить')).onPressed,
      isNull,
    );

    await tester.enterText(keyField, keyOtherHost());
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Распознано: host.example:8443'), findsOneWidget);
    expect(
      tester.widget<ObsButton>(find.widgetWithText(ObsButton, 'Добавить')).onPressed,
      isNotNull,
    );

    await tester.tap(find.widgetWithText(ObsButton, 'Добавить'));
    await tester.pumpAndSettle();

    expect(state.profiles, hasLength(2));
    expect(state.selectedProfile?.host, 'host.example');
    expect(find.text('Сервер добавлен'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('more action opens the split editor for that server', (
    tester,
  ) async {
    final state = await buildState(
      FakeVpnBackend(),
      profiles: [fakeProfile()],
    );
    await pumpApp(tester, state);
    await _openServers(tester);

    await tester.tap(find.byTooltip('Действия'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Раздельный туннель'));
    await tester.pumpAndSettle();

    expect(find.text('Только список'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
