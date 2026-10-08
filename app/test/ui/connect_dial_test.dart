import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/ui/home/connect_dial.dart';
import 'package:obsidian_vpn/vpn/vpn_backend.dart';

import 'support.dart';

Widget _dial(VpnStatus status, {VoidCallback? onPressed}) => ConnectDial(
  status: status,
  onPressed: onPressed ?? () {},
  semanticLabel: 'Подключить',
);

void main() {
  group('litSegments', () {
    test('connected lights all 4 segments whatever the stage', () {
      for (final stage in [0, 1, 2, 3, 4]) {
        expect(
          litSegments(VpnStatus(phase: VpnPhase.connected, stage: stage)),
          4,
          reason: 'stage $stage',
        );
      }
    });

    test('disconnected and disconnecting light no segments', () {
      for (final stage in [0, 2, 4]) {
        expect(
          litSegments(VpnStatus(phase: VpnPhase.disconnected, stage: stage)),
          0,
        );
        expect(
          litSegments(VpnStatus(phase: VpnPhase.disconnecting, stage: stage)),
          0,
        );
      }
    });

    test('connecting and reconnecting follow the stage', () {
      for (final phase in [VpnPhase.connecting, VpnPhase.reconnecting]) {
        for (var stage = 0; stage <= 4; stage++) {
          expect(litSegments(VpnStatus(phase: phase, stage: stage)), stage);
        }
      }
    });

    test('error lights the segments before the failed one', () {
      expect(
        litSegments(
          const VpnStatus(phase: VpnPhase.error, stage: 2, error: 'x'),
        ),
        2,
      );
      expect(
        litSegments(
          const VpnStatus(phase: VpnPhase.error, stage: 4, error: 'x'),
        ),
        3,
      );
    });
  });

  group('ConnectDial', () {
    testWidgets('connected with stage 2 paints 4 lit segments', (tester) async {
      await pumpThemed(
        tester,
        _dial(const VpnStatus(phase: VpnPhase.connected, stage: 2)),
      );
      await tester.pumpAndSettle();
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byWidgetPredicate(
                      (w) => w is CustomPaint && w.painter is DialPainter,
                    ),
                  )
                  .painter!
              as DialPainter;
      expect(painter.fill.value, 4);
    });

    testWidgets('disconnected with stage 4 paints no lit segments', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        _dial(const VpnStatus(phase: VpnPhase.disconnected, stage: 4)),
      );
      await tester.pumpAndSettle();
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byWidgetPredicate(
                      (w) => w is CustomPaint && w.painter is DialPainter,
                    ),
                  )
                  .painter!
              as DialPainter;
      expect(painter.fill.value, 0);
    });

    for (final status in <VpnStatus>[
      const VpnStatus(),
      const VpnStatus(phase: VpnPhase.connecting, stage: 2),
      const VpnStatus(phase: VpnPhase.reconnecting, stage: 1),
      VpnStatus(
        phase: VpnPhase.connected,
        stage: 4,
        connectedAt: DateTime(2026),
      ),
      const VpnStatus(phase: VpnPhase.disconnecting),
      const VpnStatus(phase: VpnPhase.error, stage: 2, error: 'x'),
      const VpnStatus(phase: VpnPhase.error, stage: 4, error: 'x'),
    ]) {
      testWidgets(
        'paints ${status.phase} stage ${status.stage} without exceptions',
        (tester) async {
          await pumpThemed(tester, _dial(status));
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
          expect(find.byType(CustomPaint), findsWidgets);
        },
      );
    }

    testWidgets('sweep loops only while connecting', (tester) async {
      await pumpThemed(
        tester,
        _dial(const VpnStatus(phase: VpnPhase.connecting, stage: 1)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.binding.hasScheduledFrame, isTrue);

      await pumpThemed(tester, _dial(const VpnStatus()));
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('connected and disconnected are static after settling', (
      tester,
    ) async {
      await pumpThemed(tester, _dial(const VpnStatus()));
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);

      await pumpThemed(
        tester,
        _dial(
          VpnStatus(
            phase: VpnPhase.connected,
            stage: 4,
            connectedAt: DateTime(2026),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('connecting to connected stops the sweep', (tester) async {
      await pumpThemed(
        tester,
        _dial(const VpnStatus(phase: VpnPhase.connecting, stage: 3)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await pumpThemed(
        tester,
        _dial(
          VpnStatus(
            phase: VpnPhase.connected,
            stage: 4,
            connectedAt: DateTime(2026),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('disableAnimations keeps the sweep off', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: _dial(
                  const VpnStatus(phase: VpnPhase.connecting, stage: 2),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('tap calls onPressed and exposes a button semantic', (
      tester,
    ) async {
      var taps = 0;
      await pumpThemed(
        tester,
        _dial(const VpnStatus(), onPressed: () => taps++),
      );
      await tester.tap(find.byType(ConnectDial));
      await tester.pump();
      expect(taps, 1);
      expect(
        tester.getSemantics(find.byType(ConnectDial)),
        matchesSemantics(
          label: 'Подключить',
          isButton: true,
          hasTapAction: true,
        ),
      );
    });
  });
}
