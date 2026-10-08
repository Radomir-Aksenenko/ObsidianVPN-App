/// Android backend over the native channel protocol (app-docs/ARCHITECTURE.md, "Native channel
/// protocol"). MethodChannel `obsidian/vpn` for commands, EventChannel `obsidian/vpn/events` for
/// status, stats and log events. iOS uses the same names once its bridge exists.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import 'vpn_backend.dart';

const String vpnMethodChannelName = 'obsidian/vpn';
const String vpnEventChannelName = 'obsidian/vpn/events';

class ChannelVpnBackend implements VpnBackend {
  ChannelVpnBackend({MethodChannel? methodChannel, EventChannel? eventChannel})
    : _method = methodChannel ?? const MethodChannel(vpnMethodChannelName),
      _events = eventChannel ?? const EventChannel(vpnEventChannelName) {
    _eventSubscription = _events.receiveBroadcastStream().listen(
      _onEvent,
      onError: _onStreamError,
    );
  }

  final MethodChannel _method;
  final EventChannel _events;

  final StreamController<VpnStatus> _statusController =
      StreamController<VpnStatus>.broadcast();
  final StreamController<TrafficStats> _statsController =
      StreamController<TrafficStats>.broadcast();
  final StreamController<String> _logController = StreamController<String>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;
  bool _statsActive = false;

  @override
  Stream<VpnStatus> get status => _statusController.stream;

  @override
  Stream<TrafficStats> get stats => _statsController.stream;

  @override
  Stream<String> get logs => _logController.stream;

  @override
  Future<bool> ensurePermission() async {
    final granted = await _invoke<bool>(
      'prepare',
      fallback: 'Не удалось запросить разрешение на VPN.',
    );
    return granted ?? false;
  }

  @override
  Future<void> connect({
    required String profileId,
    required String name,
    required String serverHost,
    required String configJson,
  }) async {
    await _invoke<void>(
      'connect',
      fallback: 'Не удалось подключиться к VPN.',
      arguments: {
        'profileId': profileId,
        'name': name,
        'serverHost': serverHost,
        'configJson': configJson,
      },
    );
  }

  @override
  Future<void> disconnect() async {
    await _invoke<void>('disconnect', fallback: 'Не удалось отключить VPN.');
  }

  @override
  Future<void> applySplit(String configJson) async {
    await _invoke<void>(
      'applySplit',
      fallback: 'Не удалось применить раздельный туннель.',
      arguments: {'configJson': configJson},
    );
  }

  /// Reads the native status once, for the first paint before any event arrives.
  Future<VpnStatus> currentStatus() async {
    final raw = await _invoke<Map<Object?, Object?>>(
      'currentStatus',
      fallback: 'Не удалось получить состояние VPN.',
    );
    return (raw == null ? null : _parseStatus(raw)) ?? const VpnStatus();
  }

  @override
  set statsActive(bool v) {
    if (v == _statsActive) return;
    _statsActive = v;
    // A setter cannot await. A failure is written to the log stream instead of being lost.
    unawaited(
      _invoke<void>(
        'setStatsActive',
        fallback: 'Не удалось переключить сбор статистики.',
        arguments: {'active': v},
      ).then<void>(
        (_) {},
        onError: (Object error) {
          _logController.add('setStatsActive: $error');
        },
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _statusController.close();
    await _statsController.close();
    await _logController.close();
  }

  // ---- events ----

  void _onEvent(Object? event) {
    if (event is! Map<Object?, Object?>) return;
    final type = event['type'];
    if (type == 'status') {
      final status = _parseStatus(event);
      if (status != null) _statusController.add(status);
    } else if (type == 'stats') {
      // Native may still send a sample that was in flight when statsActive went false.
      if (_statsActive) _statsController.add(_parseStats(event));
    } else if (type == 'log') {
      final line = event['line'];
      if (line is String) _logController.add(line);
    }
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    _logController.add('Канал VPN: $error');
  }

  VpnStatus? _parseStatus(Map<Object?, Object?> event) {
    final phase = _phaseFrom(event['phase']);
    // An unknown phase is a protocol mismatch. Dropping it is safer than guessing a state.
    if (phase == null) return null;

    final rawStage = _asInt(event['stage']) ?? 0;
    final stage = rawStage < 0 ? 0 : (rawStage > 4 ? 4 : rawStage);

    final error = event['error'];
    final connectedAtMs = _asInt(event['connectedAtMs']);
    return VpnStatus(
      phase: phase,
      stage: stage,
      error: error is String && error.isNotEmpty ? _russianError(error) : null,
      connectedAt: connectedAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(connectedAtMs),
    );
  }

  TrafficStats _parseStats(Map<Object?, Object?> event) => TrafficStats(
    rxBytes: _asInt(event['rx']) ?? 0,
    txBytes: _asInt(event['tx']) ?? 0,
    rxBps: _asInt(event['rxBps']) ?? 0,
    txBps: _asInt(event['txBps']) ?? 0,
  );

  VpnPhase? _phaseFrom(Object? raw) {
    for (final phase in VpnPhase.values) {
      if (phase.name == raw) return phase;
    }
    return null;
  }

  int? _asInt(Object? value) => switch (value) {
    int v => v,
    num v => v.toInt(),
    _ => null,
  };

  /// The Go core reports English details. The UI contract (VpnStatus.error) is Russian.
  String _russianError(String detail) => 'Ошибка VPN: $detail';

  // ---- method calls ----

  Future<T?> _invoke<T>(
    String method, {
    required String fallback,
    Map<String, Object?>? arguments,
  }) async {
    try {
      return await _method.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw VpnBackendException(_russianMessage(e.code, fallback));
    } on MissingPluginException {
      throw const VpnBackendException('VPN недоступен: нативный канал не подключен.');
    }
  }

  /// Maps the native error codes from MainActivity to user-facing Russian text.
  static String _russianMessage(String code, String fallback) => switch (code) {
    'not_prepared' => 'Нет разрешения на VPN. Подтвердите его и попробуйте снова.',
    'bad_args' => 'Некорректные данные подключения.',
    'busy' => 'Запрос разрешения уже открыт.',
    'service_error' =>
      'Не удалось запустить VPN-сервис. Откройте приложение и попробуйте снова.',
    _ => fallback,
  };
}
