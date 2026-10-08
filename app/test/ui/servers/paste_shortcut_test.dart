import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/platform_info.dart';
import 'package:obsidian_vpn/ui/widgets/widgets.dart';

import '../../support/fake_vpn_backend.dart';
import '../support.dart';

void _mockClipboard(WidgetTester tester, String text) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.getData') return <String, dynamic>{'text': text};
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
}

Future<void> _ctrlV(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => debugPlatformOverride = TargetPlatform.windows);
  tearDown(() => debugPlatformOverride = null);

  testWidgets('Ctrl+V on the Servers tab opens the add sheet with the clipboard text', (tester) async {
    _mockClipboard(tester, 'not-a-key');
    final state = await buildState(FakeVpnBackend(), profiles: [fakeProfile()]);
    await pumpApp(tester, state);
    await tester.tap(find.text('Серверы'));
    await tester.pumpAndSettle();

    await _ctrlV(tester);

    expect(find.byType(ObsSheet), findsOneWidget);
  });

  testWidgets('Ctrl+V on another tab does not open the add sheet', (tester) async {
    _mockClipboard(tester, 'not-a-key');
    final state = await buildState(FakeVpnBackend(), profiles: [fakeProfile()]);
    await pumpApp(tester, state);

    await _ctrlV(tester);

    expect(find.byType(ObsSheet), findsNothing);
  });
}
