import 'package:flutter/material.dart' hide Durations;
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/platform_info.dart';
import 'package:obsidian_vpn/theme/theme.dart';
import 'package:obsidian_vpn/ui/widgets/widgets.dart';
import 'package:obsidian_vpn/vps/key_issuer.dart';

import '../support/fake_vpn_backend.dart';
import 'support.dart';

void main() {
  setUp(() => debugPlatformOverride = TargetPlatform.android);
  tearDown(() => debugPlatformOverride = null);

  testWidgets('the all-servers label sits 24 px under the favorites group', (
    tester,
  ) async {
    final favorite = fakeProfile(
      id: '22222222-2222-4222-8222-222222222222',
      name: 'Amsterdam',
    ).copyWith(isFavorite: true);
    final state = await buildState(
      FakeVpnBackend(),
      profiles: [fakeProfile(), favorite],
    );
    await pumpApp(tester, state);
    await tester.tap(find.text('Серверы'));
    await tester.pumpAndSettle();

    final favoritesGroup = tester.getRect(find.byType(ObsGroup).first);
    final allLabel = tester.getRect(find.text('Все серверы'));
    expect(allLabel.top - favoritesGroup.bottom, closeTo(24, 0.5));
  });

  testWidgets(
    'issued key shows validity in the trailing column, server and devices below',
    (tester) async {
      final state = await buildState(
        FakeVpnBackend(),
        profiles: [fakeProfile()],
      );
      await state.addIssuedKey(
        IssuedKey(
          id: 'k1',
          name: 'Телефон',
          serverId: fakeProfile().id,
          devices: 2,
          days: 30,
          key: 'OBSDN-k1',
          uri: 'obsidian://k1',
          // Twelve hours into a 30 day key: 29 whole days left.
          created: DateTime.now().toUtc().subtract(const Duration(hours: 12)),
        ),
      );
      await pumpApp(tester, state);
      await tester.tap(find.text('Доступ'));
      await tester.pumpAndSettle();

      expect(find.text('Frankfurt · Устройств: 2'), findsOneWidget);
      expect(find.text('29 дн.'), findsOneWidget);
      expect(find.textContaining('Осталось'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'ON switch thumb is light in both themes, never the dark onEmber colour',
    () {
      for (final brightness in Brightness.values) {
        final theme = buildTheme(brightness);
        final c = theme.extension<ObsidianColors>()!;
        final thumbOn = theme.switchTheme.thumbColor!.resolve({
          WidgetState.selected,
        });
        expect(thumbOn, isNot(c.onEmber), reason: brightness.name);
        expect(
          thumbOn,
          obsSwitchThumbOn(c, brightness),
          reason: brightness.name,
        );
      }
      final dark = buildTheme(Brightness.dark);
      expect(
        dark.switchTheme.thumbColor!.resolve({WidgetState.selected}),
        ObsidianColors.dark.text,
      );
    },
  );
}
