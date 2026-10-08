/// Platform-neutral VPN contract. Implemented by the desktop backend
/// (`desktop_backend.dart`) and by the native channel backend for Android and iOS.
library;

enum VpnPhase {
  disconnected,
  connecting,
  connected,
  reconnecting,
  disconnecting,
  error,
}

class VpnStatus {
  const VpnStatus({
    this.phase = VpnPhase.disconnected,
    this.stage = 0,
    this.error,
    this.connectedAt,
  }) : assert(stage >= 0 && stage <= 4, 'stage must be within 0..4');

  final VpnPhase phase;

  /// Handshake progress shown on the dial, 0..4.
  final int stage;

  /// Human readable (Russian) message, set when [phase] is [VpnPhase.error].
  final String? error;

  final DateTime? connectedAt;

  VpnStatus copyWith({
    VpnPhase? phase,
    int? stage,
    String? error,
    bool clearError = false,
    DateTime? connectedAt,
    bool clearConnectedAt = false,
  }) {
    return VpnStatus(
      phase: phase ?? this.phase,
      stage: stage ?? this.stage,
      error: clearError ? null : (error ?? this.error),
      connectedAt: clearConnectedAt ? null : (connectedAt ?? this.connectedAt),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VpnStatus &&
      other.phase == phase &&
      other.stage == stage &&
      other.error == error &&
      other.connectedAt == connectedAt;

  @override
  int get hashCode => Object.hash(phase, stage, error, connectedAt);

  @override
  String toString() =>
      'VpnStatus(phase: $phase, stage: $stage, error: $error, connectedAt: $connectedAt)';
}

class TrafficStats {
  const TrafficStats({
    required this.rxBytes,
    required this.txBytes,
    required this.rxBps,
    required this.txBps,
  });

  final int rxBytes;
  final int txBytes;
  final int rxBps;
  final int txBps;

  @override
  bool operator ==(Object other) =>
      other is TrafficStats &&
      other.rxBytes == rxBytes &&
      other.txBytes == txBytes &&
      other.rxBps == rxBps &&
      other.txBps == txBps;

  @override
  int get hashCode => Object.hash(rxBytes, txBytes, rxBps, txBps);
}

/// Failure of a backend operation. The message is human readable (Russian).
class VpnBackendException implements Exception {
  const VpnBackendException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class VpnBackend {
  Stream<VpnStatus> get status;

  /// Only emits while [statsActive] is true.
  Stream<TrafficStats> get stats;

  /// Last 500 lines are replayed to a new listener, then live lines follow.
  Stream<String> get logs;

  /// Android VpnService.prepare, iOS manager save, desktop elevation.
  Future<bool> ensurePermission();

  Future<void> connect({
    required String profileId,
    required String name,
    required String serverHost,
    required String configJson,
  });

  Future<void> disconnect();

  /// Live where possible, otherwise reconnects with the new config.
  Future<void> applySplit(String configJson);

  /// False when the app is backgrounded: saves battery.
  set statsActive(bool v);

  Future<void> dispose();
}
