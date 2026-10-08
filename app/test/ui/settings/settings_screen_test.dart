import 'package:flutter/material.dart' hide Durations;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/core/models/profile.dart';
import 'package:obsidian_vpn/platform_info.dart';
import 'package:obsidian_vpn/ui/settings/settings_screen.dart';

import '../../support/fake_vpn_backend.dart';
import '../support.dart';

const String _killSwitchTitle = 'Блокировать трафик без VPN';
const String _iosCaption = 'Применяется при следующем подключении.';
const String _androidCaption =
    'Откроется системный раздел VPN. Включи «Постоянная VPN» и «Блокировать соединения без VPN» для Obsidian.';
const MethodChannel _vpnChannel = MethodChannel('obsidian/vpn');

/// Opens the Settings tab from the bottom bar (or the rail on wide screens).
Future<void> openSettingsTab(WidgetTester tester) async {
  await tester.tap(find.text('Настройки').first);
  await tester.pump(const Duration(milliseconds: 400));
}

/// Scrolls the settings list until [text] is built, then returns its finder.
Future<Finder> scrollTo(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.dragUntilVisible(
    finder,
    find.byType(ListView).last,
    const Offset(0, -150),
  );
  // Centre it, clear of the bottom bar, so a tap lands on the row.
  await Scrollable.ensureVisible(
    tester.element(finder),
    alignment: 0.5,
    duration: Duration.zero,
  );
  await tester.pump();
  return finder;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugPlatformOverride = null;
  });

  group('rows per platform', () {
    testWidgets('Windows: desktop section, no kill switch, no haptics', (
      tester,
    ) async {
      debugPlatformOverride = TargetPlatform.windows;
      final state = await buildState(
        FakeVpnBackend(),
        profiles: [fakeProfile()],
      );
      await pumpApp(tester, state);
      await openSettingsTab(tester);

      expect(find.text('Компьютер'), findsOneWidget);
      expect(find.text('Запускать вместе с системой'), findsOneWidget);
      expect(find.text('Сворачивать в трей при закрытии'), findsOneWidget);
      expect(find.text(_killSwitchTitle), findsNothing);
      expect(find.text('Тактильный отклик'), findsNothing);
      expect(find.text('Подключаться при запуске'), findsOneWidget);
      expect(find.text('Тема'), findsOneWidget);
      expect(find.text('Язык'), findsOneWidget);
      expect(find.text('ID устройства'), findsOneWidget);
      expect(
        await scrollTo(tester, 'Протокол Obsidian v2, REALITY и UDP'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('iOS: kill switch switch with the next-connection caption', (
      tester,
    ) async {
      debugPlatformOverride = TargetPlatform.iOS;
      final state = await buildState(
        FakeVpnBackend(),
        profiles: [fakeProfile()],
      );
      await pumpApp(tester, state);
      await openSettingsTab(tester);

      expect(find.text(_killSwitchTitle), findsOneWidget);
      expect(find.text(_iosCaption), findsOneWidget);
      expect(find.text('Тактильный отклик'), findsOneWidget);
      expect(find.text('Компьютер'), findsNothing);
      expect(find.text('Запускать вместе с системой'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text(_killSwitchTitle));
      await tester.pump();
      expect(state.settings.killSwitch, isTrue);
    });

    testWidgets('Android: kill switch row opens the system VPN settings', (
      tester,
    ) async {
      debugPlatformOverride = TargetPlatform.android;
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_vpnChannel, (call) async {
            calls.add(call.method);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_vpnChannel, null),
      );

      final state = await buildState(
        FakeVpnBackend(),
        profiles: [fakeProfile()],
      );
      await pumpApp(tester, state);
      await openSettingsTab(tester);

      expect(find.text(_androidCaption), findsOneWidget);
      expect(find.text(_iosCaption), findsNothing);
      expect(find.text('Компьютер'), findsNothing);

      await tester.tap(find.text(_killSwitchTitle));
      await tester.pump();
      expect(calls, ['openSystemVpnSettings']);
      // The Android row is a link, not a switch: the stored setting stays off.
      expect(state.settings.killSwitch, isFalse);
    });
  });

  testWidgets('theme change updates the stored settings', (tester) async {
    final state = await buildState(FakeVpnBackend(), profiles: [fakeProfile()]);
    await pumpApp(tester, state);
    await openSettingsTab(tester);

    expect(state.settings.themeMode, AppThemeMode.system);
    await tester.tap(find.text('Тёмная'));
    await tester.pump();

    expect(state.settings.themeMode, AppThemeMode.dark);
  });

  testWidgets('device id: tap copies the full id and shows a toast', (
    tester,
  ) async {
    final copied = <String?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(
              (call.arguments as Map<Object?, Object?>)['text'] as String?,
            );
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final state = await buildState(FakeVpnBackend(), profiles: [fakeProfile()]);
    await pumpApp(tester, state);
    await openSettingsTab(tester);

    await tester.tap(await scrollTo(tester, groupDeviceId(state.deviceId)));
    await tester.pump();

    expect(copied, [state.deviceId]);
    expect(find.text('ID устройства скопирован'), findsOneWidget);
  });

  test('groupDeviceId takes 12 hex digits in groups of four', () {
    expect(
      groupDeviceId('a1b2c3d4-e5f6-4789-8abc-def012345678'),
      'A1B2-C3D4-E5F6',
    );
    expect(groupDeviceId('abc'), 'ABC');
    expect(groupDeviceId(''), '');
  });

  testWidgets('connection log opens, shows lines, and clears', (tester) async {
    debugPlatformOverride = TargetPlatform.iOS;
    final backend = FakeVpnBackend();
    final state = await buildState(backend, profiles: [fakeProfile()]);
    // Tall view: every row is on screen, so the tap needs no scrolling.
    await pumpApp(tester, state, size: const Size(390, 1400));
    backend.emitLog('Подключение: Frankfurt');
    await tester.pump();
    await openSettingsTab(tester);

    expect(state.logs, ['Подключение: Frankfurt']);
    await tester.tap(find.text('Журнал подключения'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Очистить'), findsOneWidget);
    expect(find.byType(SelectableText), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (w) => w is SelectableText && w.data == 'Подключение: Frankfurt',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Очистить'));
    await tester.pump();

    expect(state.logs, isEmpty);
    expect(find.text('Записей пока нет'), findsOneWidget);
  });
}
