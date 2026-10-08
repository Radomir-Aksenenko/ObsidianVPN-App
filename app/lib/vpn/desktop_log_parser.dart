import 'vpn_backend.dart';

/// Stage markers of the Go client's log, lowercase. Port of the table in
/// app-docs/desktop-inventory.md, "VPN run (desktop)".
const _stageMarkers = <int, List<String>>{
  1: ['connecting to', 'handshake'],
  2: ['wintun session started', 'creating adapter', 'session started'],
  3: ['tun address set', 'set dns', 'tun mtu'],
  4: ['clean all stale', 'bypass route', 'dual-stack ipv6', 'routes restored'],
};

const _readyMarker = ': ready';
const _sessionEndedMarker = 'session ended:';
const _reconnectingMarker = 'reconnecting in';

/// Turns the Go client's log lines into [VpnStatus] updates, one line at a time.
///
/// Pure: no I/O and no timers. The clock is injected so `connectedAt` is testable.
class DesktopLogParser {
  DesktopLogParser({
    required this._clock,
    VpnStatus initial = const VpnStatus(phase: VpnPhase.connecting),
  }) : _status = initial;

  final DateTime Function() _clock;
  VpnStatus _status;

  VpnStatus get status => _status;

  /// Replaces the current state, e.g. when the backend starts a new connect.
  void reset(VpnStatus next) => _status = next;

  /// Returns the state after [line]. Lines received while disconnecting,
  /// disconnected or in error never change the state.
  VpnStatus feed(String line) {
    final lower = line.toLowerCase();
    final phase = _status.phase;
    if (phase == VpnPhase.disconnecting ||
        phase == VpnPhase.disconnected ||
        phase == VpnPhase.error) {
      return _status;
    }

    if (lower.contains(_readyMarker)) {
      if (phase == VpnPhase.connected) return _status;
      _status = _status.copyWith(
        phase: VpnPhase.connected,
        stage: 4,
        clearError: true,
        connectedAt: _clock(),
      );
      return _status;
    }

    if (lower.contains(_sessionEndedMarker)) {
      final next = lower.contains(_reconnectingMarker)
          ? VpnPhase.reconnecting
          : VpnPhase.connecting;
      _status = _status.copyWith(phase: next, stage: 0, clearConnectedAt: true);
      return _status;
    }

    if (lower.contains(_reconnectingMarker)) {
      _status = _status.copyWith(
        phase: VpnPhase.reconnecting,
        clearConnectedAt: true,
      );
      return _status;
    }

    // Once connected, stage lines are debug noise: the tunnel stays connected
    // until a "session ended:" line arrives.
    if (phase == VpnPhase.connected) return _status;

    final stage = stageFor(lower);
    if (stage == null || stage <= _status.stage) return _status;
    _status = _status.copyWith(stage: stage);
    return _status;
  }

  /// Handshake stage named by [line], or null. When a line matches several
  /// stages the highest one wins. Expects lowercase input or mixed case.
  static int? stageFor(String line) {
    final lower = line.toLowerCase();
    for (final stage in [4, 3, 2, 1]) {
      if (_stageMarkers[stage]!.any(lower.contains)) return stage;
    }
    return null;
  }
}

/// Russian message for a client that exited, from its last output lines.
/// Port of `humanize_client_log` in desktop/src-tauri/src/vpn.rs.
String humanizeExit(List<String> lastLines) {
  final lower = lastLines.join('\n').toLowerCase();
  final last = lastLines
      .lastWhere((l) => l.trim().isNotEmpty, orElse: () => '')
      .trim();

  // pkexec on Linux: the password dialog was dismissed or authorization failed.
  if (lower.contains('error executing command as another user') ||
      lower.contains('request dismissed') ||
      lower.contains('not authorized')) {
    return 'Нужны права администратора для запуска клиента. Подтвердите запрос пароля.';
  }
  if (lower.contains('access is denied') || lower.contains('administrator')) {
    return 'Для работы Wintun требуются права Администратора.';
  }
  if (last.contains('failed to open TUN')) {
    return 'Не удалось создать виртуальный адаптер TUN. Запустите приложение от имени Администратора.';
  }
  if (lower.contains('connectex') ||
      lower.contains('did not properly respond')) {
    return 'Сервер не отвечает на TCP-порт 443. Проверьте статус VPS.';
  }
  if (lower.contains('i/o timeout') ||
      lower.contains('did not return a recognizable response')) {
    return 'Таймаут подключения: сервер не завершил рукопожатие REALITY.';
  }
  return last.isEmpty ? 'Процесс клиента неожиданно завершился' : last;
}
