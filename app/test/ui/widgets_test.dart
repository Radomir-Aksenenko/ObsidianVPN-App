import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/l10n/app_localizations.dart';
import 'package:obsidian_vpn/theme/theme.dart';
import 'package:obsidian_vpn/ui/home/traffic_format.dart';
import 'package:obsidian_vpn/ui/widgets/widgets.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.dark),
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
}

void main() {
  test('PingBadge thresholds are 80 and 160 ms', () {
    const c = ObsidianColors.dark;
    expect(PingBadge.dotColor(c, 79), c.ok);
    expect(PingBadge.dotColor(c, 80), c.warn);
    expect(PingBadge.dotColor(c, 159), c.warn);
    expect(PingBadge.dotColor(c, 160), c.danger);
  });

  testWidgets('PingBadge shows ms or "нет ответа", never a dash', (
    tester,
  ) async {
    await _pump(
      tester,
      const Column(children: [PingBadge(42), PingBadge(null)]),
    );
    expect(find.text('42 мс'), findsOneWidget);
    expect(find.text('нет ответа'), findsOneWidget);
  });

  testWidgets('ObsButton ignores taps while loading and when disabled', (
    tester,
  ) async {
    var taps = 0;
    await _pump(
      tester,
      ObsButton(label: 'Go', onPressed: () => taps++, loading: true),
    );
    await tester.tap(find.byType(ObsButton));
    await tester.pump();
    expect(taps, 0);

    await _pump(tester, ObsButton(label: 'Go', onPressed: () => taps++));
    await tester.tap(find.text('Go'));
    await tester.pump();
    expect(taps, 1);
    expect(tester.getSize(find.byType(ObsButton)).height, 48);
  });

  testWidgets('ObsRow is at least 56 high and taps', (tester) async {
    var taps = 0;
    await _pump(
      tester,
      ObsGroup(
        label: 'Сервер',
        children: [
          ObsRow(title: 'A', onTap: () => taps++),
          const ObsRow(title: 'B'),
        ],
      ),
    );
    expect(
      tester.getSize(find.widgetWithText(ObsRow, 'A')).height,
      greaterThanOrEqualTo(56),
    );
    await tester.tap(find.text('A'));
    expect(taps, 1);
    expect(find.text('Сервер'), findsOneWidget);
  });

  testWidgets('ObsSegmented reports the tapped value', (tester) async {
    String? picked;
    await _pump(
      tester,
      ObsSegmented<String>(
        options: const [
          ObsSegment(value: 'a', label: 'Первый'),
          ObsSegment(value: 'b', label: 'Второй'),
        ],
        value: 'a',
        onChanged: (v) => picked = v,
      ),
    );
    await tester.tap(find.text('Второй'));
    expect(picked, 'b');
  });

  testWidgets('ObsEmptyState runs its action', (tester) async {
    var ran = false;
    await _pump(
      tester,
      ObsEmptyState(
        text: 'Пусто',
        actionLabel: 'Добавить',
        onAction: () => ran = true,
      ),
    );
    await tester.tap(find.text('Добавить'));
    expect(ran, isTrue);
  });

  testWidgets('showAdaptiveSheet is a dialog on wide windows', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late BuildContext ctx;
    await _pump(
      tester,
      Builder(
        builder: (c) {
          ctx = c;
          return const SizedBox();
        },
      ),
    );
    showAdaptiveSheet<void>(
      ctx,
      (_) => const ObsSheet(title: 'T', child: Text('body')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('body'), findsOneWidget);
  });

  testWidgets('showObsToast shows one line of text', (tester) async {
    late BuildContext ctx;
    await _pump(
      tester,
      Builder(
        builder: (c) {
          ctx = c;
          return const SizedBox();
        },
      ),
    );
    showObsToast(ctx, 'Готово');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Готово'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Готово'), findsNothing);
  });

  group('formatters', () {
    late AppLocalizations l10n;
    setUp(
      () async =>
          l10n = await AppLocalizations.delegate.load(const Locale('ru')),
    );

    test('rate picks Кбит/с, Мбит/с, Гбит/с with one decimal', () {
      expect(formatRate(1000, l10n).value, '8.0');
      expect(formatRate(1000, l10n).unit, 'Кбит/с');
      expect(formatRate(1550000, l10n).value, '12.4');
      expect(formatRate(1550000, l10n).unit, 'Мбит/с');
      expect(formatRate(200000000, l10n).unit, 'Гбит/с');
    });

    test('bytes and session', () {
      expect(formatBytes(512, l10n), '512 Б');
      expect(formatBytes(1536, l10n), '1.5 КБ');
      expect(
        formatSession(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '01:02:03',
      );
    });
  });
}
