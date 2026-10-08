import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/vpn/channel_backend.dart';
import 'package:obsidian_vpn/vpn/vpn_backend.dart';

const MethodChannel _method = MethodChannel('obsidian/vpn');
const EventChannel _events = EventChannel('obsidian/vpn/events');

/// Lets queued platform messages (channel listen, fake events) reach their listeners.
Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall call) respond;
  MockStreamHandlerEventSink? sink;
  late List<ChannelVpnBackend> backends;

  setUp(() {
    calls = <MethodCall>[];
    respond = (MethodCall _) async => null;
    sink = null;
    backends = <ChannelVpnBackend>[];

    messenger.setMockMethodCallHandler(_method, (MethodCall call) async {
      calls.add(call);
      return respond(call);
    });
    messenger.setMockStreamHandler(
      _events,
      MockStreamHandler.inline(
        onListen: (Object? arguments, MockStreamHandlerEventSink events) {
          sink = events;
        },
        onCancel: (Object? arguments) {
          sink = null;
        },
      ),
    );
  });

  tearDown(() async {
    for (final backend in backends) {
      await backend.dispose();
    }
    messenger.setMockMethodCallHandler(_method, null);
    messenger.setMockStreamHandler(_events, null);
  });

  Future<ChannelVpnBackend> createBackend() async {
    final backend = ChannelVpnBackend();
    backends.add(backend);
    await _settle();
    return backend;
  }

  void emit(Map<String, Object?> event) {
    sink!.success(event);
  }

  Iterable<MethodCall> callsTo(String method) =>
      calls.where((MethodCall call) => call.method == method);

  group('commands', () {
    test('connect sends profile, name, server and config', () async {
      final backend = await createBackend();

      await backend.connect(
        profileId: 'p1',
        name: 'Home',
        serverHost: 'vpn.example.com',
        configJson: '{"server_host":"vpn.example.com"}',
      );

      expect(callsTo('connect').single.arguments, {
        'profileId': 'p1',
        'name': 'Home',
        'serverHost': 'vpn.example.com',
        'configJson': '{"server_host":"vpn.example.com"}',
        'killSwitch': false,
      });
    });

    test('connect sends the kill switch set before it', () async {
      final backend = await createBackend();

      await backend.setKillSwitch(true);
      await backend.connect(
        profileId: 'p1',
        name: 'Home',
        serverHost: 'vpn.example.com',
        configJson: '{}',
      );

      expect(callsTo('connect').single.arguments, {
        'profileId': 'p1',
        'name': 'Home',
        'serverHost': 'vpn.example.com',
        'configJson': '{}',
        'killSwitch': true,
      });
    });

    test('openSystemVpnSettings calls the native method', () async {
      await openSystemVpnSettings(channel: _method);

      expect(callsTo('openSystemVpnSettings'), hasLength(1));
    });

    test(
      'openSystemVpnSettings maps a native failure to a Russian message',
      () async {
        respond = (MethodCall _) async {
          throw PlatformException(code: 'settings_unavailable');
        };

        await expectLater(
          openSystemVpnSettings(channel: _method),
          throwsA(
            isA<VpnBackendException>().having(
              (VpnBackendException e) => e.message,
              'message',
              startsWith('Не удалось открыть настройки VPN'),
            ),
          ),
        );
      },
    );

    test(
      'disconnect and applySplit reach the channel with their arguments',
      () async {
        final backend = await createBackend();

        await backend.applySplit('{"split_tunnel_mode":"exclude"}');
        await backend.disconnect();

        expect(callsTo('applySplit').single.arguments, {
          'configJson': '{"split_tunnel_mode":"exclude"}',
        });
        expect(callsTo('disconnect'), hasLength(1));
      },
    );

    test('ensurePermission returns the native answer', () async {
      final backend = await createBackend();

      respond = (MethodCall _) async => true;
      expect(await backend.ensurePermission(), isTrue);

      respond = (MethodCall _) async => null;
      expect(await backend.ensurePermission(), isFalse);
    });

    test(
      'a native error becomes a VpnBackendException with a Russian message',
      () async {
        final backend = await createBackend();
        respond = (MethodCall _) async {
          throw PlatformException(
            code: 'not_prepared',
            message: 'VPN consent has not been granted',
          );
        };

        await expectLater(
          backend.connect(
            profileId: 'p1',
            name: 'Home',
            serverHost: 'vpn.example.com',
            configJson: '{}',
          ),
          throwsA(
            isA<VpnBackendException>().having(
              (VpnBackendException e) => e.message,
              'message',
              contains('Нет разрешения на VPN'),
            ),
          ),
        );
      },
    );

    test(
      'an unknown native error code falls back to the operation message',
      () async {
        final backend = await createBackend();
        respond = (MethodCall _) async {
          throw PlatformException(code: 'weird', message: 'boom');
        };

        await expectLater(
          backend.disconnect(),
          throwsA(
            isA<VpnBackendException>().having(
              (VpnBackendException e) => e.message,
              'message',
              'Не удалось отключить VPN.',
            ),
          ),
        );
      },
    );

    test(
      'a channel without a native handler is reported as an unavailable VPN',
      () async {
        // No mock is registered for these names, so the platform side answers with
        // MissingPluginException, the same as a build without the native layer.
        final backend = ChannelVpnBackend(
          methodChannel: const MethodChannel('obsidian/vpn-without-handler'),
          eventChannel: const EventChannel(
            'obsidian/vpn-without-handler/events',
          ),
        );
        backends.add(backend);

        await expectLater(
          backend.ensurePermission(),
          throwsA(
            isA<VpnBackendException>().having(
              (VpnBackendException e) => e.message,
              'message',
              contains('недоступен'),
            ),
          ),
        );
      },
    );

    test('currentStatus parses the native map', () async {
      final backend = await createBackend();
      respond = (MethodCall call) async {
        if (call.method == 'currentStatus') {
          return <String, Object?>{
            'type': 'status',
            'phase': 'reconnecting',
            'stage': 3,
            'error': null,
            'connectedAtMs': null,
          };
        }
        return null;
      };

      final status = await backend.currentStatus();

      expect(status.phase, VpnPhase.reconnecting);
      expect(status.stage, 3);
      expect(status.connectedAt, isNull);
    });
  });

  group('statsActive', () {
    test('sends the flag only when it changes', () async {
      final backend = await createBackend();

      backend.statsActive = true;
      backend.statsActive = true;
      backend.statsActive = false;
      await _settle();

      final flags = callsTo(
        'setStatsActive',
      ).map((MethodCall call) => call.arguments).toList();
      expect(flags, <Object?>[
        {'active': true},
        {'active': false},
      ]);
    });

    test('stats events are dropped while statsActive is false', () async {
      final backend = await createBackend();
      final received = <TrafficStats>[];
      final subscription = backend.stats.listen(received.add);

      emit(<String, Object?>{
        'type': 'stats',
        'rx': 1,
        'tx': 2,
        'rxBps': 3,
        'txBps': 4,
      });
      await _settle();
      expect(received, isEmpty);

      backend.statsActive = true;
      await _settle();
      emit(<String, Object?>{
        'type': 'stats',
        'rx': 10,
        'tx': 20,
        'rxBps': 30,
        'txBps': 40,
      });
      await _settle();

      expect(received, <TrafficStats>[
        const TrafficStats(rxBytes: 10, txBytes: 20, rxBps: 30, txBps: 40),
      ]);
      await subscription.cancel();
    });
  });

  group('events', () {
    test('a connected status carries the stage and connectedAt', () async {
      final backend = await createBackend();
      final next = backend.status.first;

      emit(<String, Object?>{
        'type': 'status',
        'phase': 'connected',
        'stage': 4,
        'error': null,
        'connectedAtMs': 1700000000000,
      });
      await _settle();

      final status = await next;
      expect(status.phase, VpnPhase.connected);
      expect(status.stage, 4);
      expect(status.error, isNull);
      expect(
        status.connectedAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
    });

    test(
      'an error status keeps the Go detail inside a Russian message',
      () async {
        final backend = await createBackend();
        final next = backend.status.first;

        emit(<String, Object?>{
          'type': 'status',
          'phase': 'error',
          'stage': 0,
          'error': 'init session: handshake refused',
          'connectedAtMs': null,
        });
        await _settle();

        final status = await next;
        expect(status.phase, VpnPhase.error);
        expect(status.error, 'Ошибка VPN: init session: handshake refused');
      },
    );

    test('unknown phases and out-of-range stages are handled', () async {
      final backend = await createBackend();
      final received = <VpnStatus>[];
      final subscription = backend.status.listen(received.add);

      emit(<String, Object?>{'type': 'status', 'phase': 'bogus', 'stage': 1});
      emit(<String, Object?>{
        'type': 'status',
        'phase': 'connecting',
        'stage': 9,
      });
      await _settle();

      expect(received, hasLength(1));
      expect(received.single.phase, VpnPhase.connecting);
      expect(received.single.stage, 4);
      await subscription.cancel();
    });

    test('log events arrive on the logs stream', () async {
      final backend = await createBackend();
      final next = backend.logs.first;

      emit(<String, Object?>{
        'type': 'log',
        'line': 'Connecting to vpn.example.com',
      });
      await _settle();

      expect(await next, 'Connecting to vpn.example.com');
    });

    test('dispose closes the streams', () async {
      final backend = await createBackend();
      final done = backend.status.toList();

      await backend.dispose();
      backends.clear();

      expect(await done, isEmpty);
    });
  });

  group('review fixes', () {
    test('a status that arrived before anyone listened is replayed', () async {
      final backend = await createBackend();
      emit(<String, Object?>{
        'type': 'status',
        'phase': 'connected',
        'stage': 4,
        'connectedAtMs': 1000,
      });
      await _settle();

      final first = await backend.status.first;

      expect(first.phase, VpnPhase.connected);
    });

    test('a non-finite number in an event does not escape as an uncaught error', () async {
      final backend = await createBackend();
      await backend.setKillSwitch(false);
      backend.statsActive = true;
      await _settle();
      final stats = <TrafficStats>[];
      final sub = backend.stats.listen(stats.add);
      final logs = backend.logs.first;

      emit(<String, Object?>{'type': 'stats', 'rx': double.nan, 'tx': double.infinity, 'rxBps': 1, 'txBps': 2});
      emit(<String, Object?>{'type': 'status', 'phase': 'connected', 'stage': double.nan});
      emit(<String, Object?>{'type': 'log', 'line': 'still alive'});
      await _settle();

      expect(await logs, 'still alive');
      expect(stats.single.rxBytes, 0);
      await sub.cancel();
    });
  });
}
