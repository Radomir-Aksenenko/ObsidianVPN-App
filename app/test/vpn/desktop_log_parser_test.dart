import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/vpn/desktop_log_parser.dart';
import 'package:obsidian_vpn/vpn/vpn_backend.dart';

void main() {
  final clockTime = DateTime.utc(2026, 9, 4, 19);
  late DesktopLogParser parser;

  setUp(() {
    parser = DesktopLogParser(clock: () => clockTime);
  });

  VpnStatus connecting() => const VpnStatus(phase: VpnPhase.connecting);

  group('ready marker', () {
    test('": ready" connects, sets stage 4 and connectedAt from the clock', () {
      final s = parser.feed('2026/09/04 19:00:00 session 1234abcd: ready');
      expect(s.phase, VpnPhase.connected);
      expect(s.stage, 4);
      expect(s.connectedAt, clockTime);
      expect(s.error, isNull);
    });

    test('ready while already connected keeps connectedAt', () {
      var now = DateTime.utc(2026, 1, 1);
      final p = DesktopLogParser(clock: () => now);
      p.feed('session a: ready');
      now = DateTime.utc(2026, 1, 2);
      final s = p.feed('session b: ready');
      expect(s.connectedAt, DateTime.utc(2026, 1, 1));
    });

    test('ready clears a previous error', () {
      parser.reset(const VpnStatus(phase: VpnPhase.reconnecting, error: 'old'));
      final s = parser.feed('session x: ready');
      expect(s.phase, VpnPhase.connected);
      expect(s.error, isNull);
    });

    test('ready is matched case-insensitively', () {
      expect(parser.feed('SESSION X: READY').phase, VpnPhase.connected);
    });
  });

  group('session ended marker', () {
    test('after ready without reconnect text goes back to connecting', () {
      parser.feed('session a: ready');
      final s = parser.feed('2026/09/04 19:02:00 session ended: EOF');
      expect(s.phase, VpnPhase.connecting);
      expect(s.stage, 0);
      expect(s.connectedAt, isNull);
    });

    test('with "reconnecting in" goes to reconnecting', () {
      parser.feed('session a: ready');
      final s = parser.feed(
        '2026/09/04 19:02:00 session ended: connection reset - reconnecting in 3s',
      );
      expect(s.phase, VpnPhase.reconnecting);
      expect(s.connectedAt, isNull);
    });
  });

  group('reconnecting in marker', () {
    test('alone maps to reconnecting and clears connectedAt', () {
      parser.feed('session a: ready');
      final s = parser.feed('reconnecting in 3s');
      expect(s.phase, VpnPhase.reconnecting);
      expect(s.connectedAt, isNull);
    });
  });

  group('stage table', () {
    test('"connecting to" is stage 1', () {
      final s = parser.feed('[attempt 1] connecting to 203.0.113.5:443');
      expect(s.phase, VpnPhase.connecting);
      expect(s.stage, 1);
    });

    test('"handshake" is stage 1', () {
      expect(parser.feed('handshake: waiting for ServerHello').stage, 1);
    });

    test('"wintun session started" is stage 2', () {
      expect(parser.feed('wintun session started').stage, 2);
    });

    test('"creating adapter" is stage 2', () {
      expect(parser.feed('creating adapter wintun').stage, 2);
    });

    test('"session started" is stage 2', () {
      expect(parser.feed('tun session started').stage, 2);
    });

    test('"tun address set" is stage 3', () {
      expect(parser.feed('tun address set to 10.8.0.5/24').stage, 3);
    });

    test('"set dns" is stage 3', () {
      expect(parser.feed('set dns 10.8.0.1').stage, 3);
    });

    test('"tun mtu" is stage 3', () {
      expect(parser.feed('tun mtu 1420').stage, 3);
    });

    test('"clean all stale" is stage 4', () {
      expect(parser.feed('clean all stale routes').stage, 4);
    });

    test('"bypass route" is stage 4', () {
      expect(parser.feed('bypass route: 203.0.113.5 -> 192.168.1.1').stage, 4);
    });

    test('"dual-stack ipv6" is stage 4', () {
      expect(parser.feed('dual-stack ipv6 disabled').stage, 4);
    });

    test('"routes restored" is stage 4', () {
      expect(parser.feed('routes restored').stage, 4);
    });

    test('the stage never goes backwards inside one attempt', () {
      parser.feed('bypass route: x');
      expect(parser.feed('connecting to host').stage, 4);
      expect(parser.feed('tun mtu 1420').stage, 4);
    });

    test('a new attempt after "session ended:" restarts from stage 1', () {
      parser.feed('bypass route: x');
      parser.feed('session ended: EOF - reconnecting in 3s');
      final s = parser.feed('[attempt 2] connecting to host');
      expect(s.stage, 1);
      expect(s.phase, VpnPhase.reconnecting);
    });

    test('stage lines keep the phase connecting', () {
      final s = parser.feed('wintun session started');
      expect(s.phase, VpnPhase.connecting);
    });

    test(
      'stageFor returns the highest stage on a line that matches several',
      () {
        expect(DesktopLogParser.stageFor('connecting to x; bypass route y'), 4);
        expect(DesktopLogParser.stageFor('nothing here'), isNull);
        expect(DesktopLogParser.stageFor('TUN MTU 1420'), 3);
      },
    );
  });

  group('unknown and ignored lines', () {
    test('an unknown line leaves the status unchanged', () {
      final before = parser.feed('[attempt 1] connecting to host');
      expect(parser.feed('some random debug text'), before);
    });

    test('once connected, stage lines are ignored', () {
      parser.feed('session a: ready');
      final s = parser.feed('handshake: sending junk train');
      expect(s.phase, VpnPhase.connected);
      expect(s.stage, 4);
    });

    test('once connected, unknown traffic lines keep the tunnel connected', () {
      parser.feed('session a: ready');
      expect(
        parser.feed('DEBUG: packet traffic flowing').phase,
        VpnPhase.connected,
      );
    });

    test('lines received while disconnecting are ignored, including ready', () {
      parser.reset(const VpnStatus(phase: VpnPhase.disconnecting));
      expect(parser.feed('session a: ready').phase, VpnPhase.disconnecting);
      expect(parser.feed('connecting to host').phase, VpnPhase.disconnecting);
    });

    test('lines received while disconnected are ignored', () {
      parser.reset(const VpnStatus());
      expect(parser.feed('session a: ready'), const VpnStatus());
    });

    test('lines received in error are ignored', () {
      parser.reset(const VpnStatus(phase: VpnPhase.error, error: 'boom'));
      final s = parser.feed('session a: ready');
      expect(s.phase, VpnPhase.error);
      expect(s.error, 'boom');
    });
  });

  test('a full reconnect cycle works end to end', () {
    var now = DateTime.utc(2026, 1, 1, 10);
    final p = DesktopLogParser(clock: () => now, initial: connecting());

    p.feed('[attempt 1] connecting to host:443');
    p.feed('wintun session started');
    p.feed('tun address set');
    p.feed('bypass route: host');
    expect(p.feed('session a: ready').phase, VpnPhase.connected);

    now = DateTime.utc(2026, 1, 1, 11);
    final dropped = p.feed('session a: EOF - reconnecting in 3s');
    expect(dropped.phase, VpnPhase.reconnecting);
    expect(dropped.connectedAt, isNull);

    p.feed('[attempt 2] connecting to host:443');
    expect(p.status.phase, VpnPhase.reconnecting);

    final back = p.feed('session b: ready');
    expect(back.phase, VpnPhase.connected);
    expect(back.connectedAt, DateTime.utc(2026, 1, 1, 11));
  });

  group('humanizeExit', () {
    test('access denied asks for administrator rights', () {
      expect(
        humanizeExit(['wintun: Access is denied.']),
        'Для работы Wintun требуются права Администратора.',
      );
    });

    test('"administrator" in the output asks for administrator rights', () {
      expect(
        humanizeExit(['please run as Administrator']),
        'Для работы Wintun требуются права Администратора.',
      );
    });

    test('"failed to open TUN" on the last line names the TUN adapter', () {
      expect(
        humanizeExit(['something', 'failed to open TUN device']),
        'Не удалось создать виртуальный адаптер TUN. Запустите приложение от имени Администратора.',
      );
    });

    test('connectex means TCP 443 does not answer', () {
      expect(
        humanizeExit(['dial tcp: connectex: refused']),
        'Сервер не отвечает на TCP-порт 443. Проверьте статус VPS.',
      );
    });

    test('"did not properly respond" means TCP 443 does not answer', () {
      expect(
        humanizeExit([
          'a connected host did not properly respond after a period',
        ]),
        'Сервер не отвечает на TCP-порт 443. Проверьте статус VPS.',
      );
    });

    test('i/o timeout means the REALITY handshake timed out', () {
      expect(
        humanizeExit(['read: i/o timeout']),
        'Таймаут подключения: сервер не завершил рукопожатие REALITY.',
      );
    });

    test('"did not return a recognizable response" means REALITY timeout', () {
      expect(
        humanizeExit(['server did not return a recognizable response']),
        'Таймаут подключения: сервер не завершил рукопожатие REALITY.',
      );
    });

    test('unknown output returns the last non-empty line', () {
      expect(humanizeExit(['first', 'second', '   ', '']), 'second');
    });

    test('empty output gives the generic message', () {
      expect(humanizeExit([]), 'Процесс клиента неожиданно завершился');
      expect(humanizeExit(['  ', '']), 'Процесс клиента неожиданно завершился');
    });

    test('Russian messages contain no em or en dash', () {
      final messages = [
        humanizeExit(['access is denied']),
        humanizeExit(['failed to open TUN']),
        humanizeExit(['connectex']),
        humanizeExit(['i/o timeout']),
        humanizeExit([]),
      ];
      for (final m in messages) {
        expect(m.contains('—'), isFalse, reason: m);
        expect(m.contains('–'), isFalse, reason: m);
      }
    });
  });
}
