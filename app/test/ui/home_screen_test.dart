import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/ui/home/session_timer.dart';
import 'package:obsidian_vpn/vpn/vpn_backend.dart';

import '../support/fake_vpn_backend.dart';
import '../support/vectors.dart';
import 'support.dart';

void main() {
  testWidgets('with no profiles Home shows the empty state and Servers action', (
    tester,
  ) async {
    final backend = FakeVpnBackend();
    final state = await buildState(backend);
    await pumpApp(tester, state);

    expect(
      find.text('Добавь первый сервер: вставь ключ доступа.'),
      findsOneWidget,
    );
    expect(find.text('ОТКЛЮЧЕНО'), findsOneWidget);
    expect(find.text('Подключить'), findsOneWidget);

    await tester.tap(find.text('Добавить сервер'));
    await tester.pump();
    // The shell switched to the Servers tab; Home is no longer the visible tab.
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the selected server and the split summary', (
    tester,
  ) async {
    final state = await buildState(FakeVpnBackend(), profiles: [fakeProfile()]);
    await pumpApp(tester, state);

    expect(find.text('Frankfurt'), findsOneWidget);
    expect(find.text('fra.example.net'), findsOneWidget);
    expect(find.text('DE'), findsOneWidget);
    expect(find.text('Раздельный туннель'), findsOneWidget);
    expect(find.text('Выключен'), findsOneWidget);
    expect(find.text('Загрузка'), findsNothing);
  });

  testWidgets('connected: timer and traffic row; timer stops when leaving', (
    tester,
  ) async {
    final backend = FakeVpnBackend();
    final state = await buildState(backend, profiles: [fakeProfile()]);
    await pumpApp(tester, state);

    backend.emitStatus(
      VpnStatus(
        phase: VpnPhase.connected,
        stage: 4,
        connectedAt: DateTime.now().subtract(
          const Duration(minutes: 12, seconds: 34),
        ),
      ),
    );
    backend.emitStats(
      const TrafficStats(
        rxBytes: 150 * 1024 * 1024,
        txBytes: 2048,
        rxBps: 1550000,
        txBps: 40000,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('ЗАЩИЩЕНО'), findsOneWidget);
    expect(find.text('Отключить'), findsOneWidget);
    expect(find.textContaining('00:12:3'), findsOneWidget);
    expect(find.text('Загрузка'), findsOneWidget);
    expect(find.text('Отдача'), findsOneWidget);
    expect(find.text('12.4'), findsOneWidget);
    expect(find.text('Мбит/с'), findsOneWidget);
    expect(find.text('Всего 150.0 МБ'), findsOneWidget);

    final timer = tester.state(find.byType(SessionTimer)) as dynamic;
    expect(timer.isTicking, isTrue);

    backend.emitStatus(const VpnStatus());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SessionTimer), findsNothing);
    expect(find.text('Загрузка'), findsNothing);
  });

  testWidgets('connected without stats (desktop) shows no traffic numbers', (
    tester,
  ) async {
    final backend = FakeVpnBackend();
    final state = await buildState(backend, profiles: [fakeProfile()]);
    await pumpApp(tester, state);

    backend.emitStatus(
      VpnStatus(
        phase: VpnPhase.connected,
        stage: 4,
        connectedAt: DateTime.now(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(SessionTimer), findsOneWidget);
    expect(find.text('Загрузка'), findsNothing);
  });

  testWidgets('error shows the message and opens the log sheet', (
    tester,
  ) async {
    final backend = FakeVpnBackend();
    final state = await buildState(backend, profiles: [fakeProfile()]);
    await pumpApp(tester, state);

    backend.emitLog('line one');
    backend.emitStatus(
      const VpnStatus(
        phase: VpnPhase.error,
        stage: 2,
        error: 'Сервер не отвечает на порту 443.',
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('ОШИБКА'), findsOneWidget);
    expect(find.text('Сервер не отвечает на порту 443.'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Журнал'));
    await tester.pumpAndSettle();
    expect(find.text('Скопировать всё'), findsOneWidget);
    expect(find.textContaining('line one'), findsOneWidget);
  });

  testWidgets('connecting shows the stage in the status word', (tester) async {
    final backend = FakeVpnBackend();
    final state = await buildState(backend, profiles: [fakeProfile()]);
    await pumpApp(tester, state);

    backend.emitStatus(const VpnStatus(phase: VpnPhase.connecting, stage: 2));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ПОДКЛЮЧЕНИЕ 2/4'), findsOneWidget);
    expect(find.text('Отмена'), findsOneWidget);
  });

  testWidgets('Space toggles the connection when Home has focus', (
    tester,
  ) async {
    final backend = FakeVpnBackend();
    final state = await buildState(backend, key: keyLegacyHost());
    await pumpApp(tester, state);
    await tester.pump();

    // Focus the Home root (autofocus only fires on desktop hosts).
    final focus = Focus.of(tester.element(find.text('Подключить')));
    focus.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(backend.connects, isNotEmpty);
  });

  testWidgets('picker lists profiles and selects one', (tester) async {
    final backend = FakeVpnBackend();
    final state = await buildState(
      backend,
      profiles: [
        fakeProfile(),
        fakeProfile(
          id: '22222222-2222-4222-8222-222222222222',
          name: 'Helsinki',
          country: 'FI',
          host: 'hel.example.net',
        ),
      ],
    );
    await pumpApp(tester, state);

    await tester.tap(find.text('Frankfurt'));
    await tester.pumpAndSettle();
    expect(find.text('Helsinki'), findsOneWidget);

    await tester.tap(find.text('Helsinki'));
    await tester.pumpAndSettle();
    expect(state.selectedProfile?.name, 'Helsinki');
  });

  testWidgets('layout survives 360x640 and a short window', (tester) async {
    final state = await buildState(FakeVpnBackend(), profiles: [fakeProfile()]);
    await pumpApp(tester, state, size: const Size(360, 640));
    expect(tester.takeException(), isNull);

    await pumpApp(tester, state, size: const Size(900, 560));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
