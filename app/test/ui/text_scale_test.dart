import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_vpn_backend.dart';
import 'support.dart';

void main() {
  testWidgets('every tab fits 360x640 at text scale 1.3 with very long server names', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final state = await buildState(
      FakeVpnBackend(),
      profiles: [
        fakeProfile(
          name: 'Очень длинное название сервера которое точно не поместится в одну строку',
          host: 'a-very-long-hostname-for-overflow-checks.subdomain.example-company.net',
        ),
      ],
    );
    await pumpApp(tester, state, size: const Size(360, 640));
    expect(tester.takeException(), isNull);
    for (final tab in ['Серверы', 'Доступ', 'Настройки', 'Главная']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }
  });
}
