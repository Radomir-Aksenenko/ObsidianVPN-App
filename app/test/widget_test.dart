import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/app.dart';
import 'package:obsidian_vpn/core/storage/store.dart';
import 'package:obsidian_vpn/state/app_state.dart';

import 'support/fake_vpn_backend.dart';

const _navLabels = ['Главная', 'Серверы', 'Доступ', 'Настройки'];

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final state = AppState(
    store: AppStore.memory(secrets: MemorySecretStore()),
    backend: FakeVpnBackend(),
    observeLifecycle: false,
  );
  await tester.pumpWidget(ObsidianApp(state: state, locale: const Locale('ru')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('wide layout shows the four nav labels in the left rail', (tester) async {
    await _pumpAt(tester, const Size(1000, 800));

    final nav = find.byKey(const ValueKey('shell-nav'));
    expect(nav, findsOneWidget);
    for (final label in _navLabels) {
      expect(find.descendant(of: nav, matching: find.text(label)), findsOneWidget);
    }
  });

  testWidgets('narrow layout shows the four nav labels in the bottom bar', (tester) async {
    await _pumpAt(tester, const Size(400, 800));

    final nav = find.byKey(const ValueKey('shell-nav'));
    expect(nav, findsOneWidget);
    for (final label in _navLabels) {
      expect(find.descendant(of: nav, matching: find.text(label)), findsOneWidget);
    }
  });
}
