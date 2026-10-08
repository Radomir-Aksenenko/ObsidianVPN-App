import 'package:flutter/material.dart' hide Durations;
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/ui/home/connect_dial.dart';
import 'package:obsidian_vpn/vpn/vpn_backend.dart';

import '../support/fake_vpn_backend.dart';
import 'support.dart';

void main() {
  for (final size in const [Size(390, 844), Size(420, 760)]) {
    testWidgets(
      'the dial keeps its position in ${size.width.toInt()}x${size.height.toInt()} '
      'when connecting and when the traffic row appears',
      (tester) async {
        final backend = FakeVpnBackend();
        final state = await buildState(backend, profiles: [fakeProfile()]);
        await pumpApp(tester, state, size: size);

        final disconnected = tester.getTopLeft(find.byType(ConnectDial));

        backend.emitStatus(
          VpnStatus(
            phase: VpnPhase.connected,
            stage: 4,
            connectedAt: DateTime.now().subtract(const Duration(seconds: 5)),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(tester.getTopLeft(find.byType(ConnectDial)), disconnected);

        backend.emitStats(
          const TrafficStats(rxBytes: 1000, txBytes: 500, rxBps: 10, txBps: 5),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(tester.getTopLeft(find.byType(ConnectDial)), disconnected);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
