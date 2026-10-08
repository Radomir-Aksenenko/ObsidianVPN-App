import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/core/net/ping.dart';

void main() {
  test('tcpPing returns a time for a listening port and null for a closed one', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;

    final open = await tcpPing('127.0.0.1', port);
    await server.close();
    final closed = await tcpPing(
      '127.0.0.1',
      port,
      timeout: const Duration(milliseconds: 500),
    );

    expect(open, isNotNull);
    expect(open, greaterThanOrEqualTo(0));
    expect(closed, isNull);
  });
}
