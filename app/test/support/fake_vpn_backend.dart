import 'dart:async';

import 'package:obsidian_vpn/state/app_state.dart';
import 'package:obsidian_vpn/vpn/vpn_backend.dart';

/// One call to [FakeVpnBackend.connect], as received.
class ConnectCall {
  const ConnectCall({
    required this.profileId,
    required this.name,
    required this.serverHost,
    required this.configJson,
  });

  final String profileId;
  final String name;
  final String serverHost;
  final String configJson;
}

/// Scripted [VpnBackend]. The test pushes status, stats and log events and
/// inspects the recorded calls.
class FakeVpnBackend implements VpnBackend {
  FakeVpnBackend({this.permissionGranted = true});

  /// Value returned by [ensurePermission].
  final bool permissionGranted;

  /// Error thrown by the next and later [connect] calls, when set.
  Object? connectError;

  /// Every successful [connect] call, in order.
  final List<ConnectCall> connects = <ConnectCall>[];

  /// Config JSON passed to [applySplit], in order.
  final List<String> splitConfigs = <String>[];

  /// Number of [disconnect] calls.
  int disconnectCalls = 0;

  /// Every value assigned to [statsActive], in order.
  final List<bool> statsActiveHistory = <bool>[];

  final StreamController<VpnStatus> _status =
      StreamController<VpnStatus>.broadcast(sync: true);
  final StreamController<TrafficStats> _stats =
      StreamController<TrafficStats>.broadcast(sync: true);
  final StreamController<String> _logs =
      StreamController<String>.broadcast(sync: true);

  /// Pushes a status event to the state.
  void emitStatus(VpnStatus status) => _status.add(status);

  /// Pushes a traffic sample to the state.
  void emitStats(TrafficStats stats) => _stats.add(stats);

  /// Pushes one log line to the state.
  void emitLog(String line) => _logs.add(line);

  @override
  Stream<VpnStatus> get status => _status.stream;

  @override
  Stream<TrafficStats> get stats => _stats.stream;

  @override
  Stream<String> get logs => _logs.stream;

  @override
  Future<bool> ensurePermission() async => permissionGranted;

  @override
  Future<void> connect({
    required String profileId,
    required String name,
    required String serverHost,
    required String configJson,
  }) async {
    final error = connectError;
    if (error != null) throw error;
    connects.add(
      ConnectCall(
        profileId: profileId,
        name: name,
        serverHost: serverHost,
        configJson: configJson,
      ),
    );
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
  }

  @override
  Future<void> applySplit(String configJson) async {
    splitConfigs.add(configJson);
  }

  @override
  set statsActive(bool v) {
    statsActiveHistory.add(v);
  }

  @override
  Future<void> dispose() async {
    await _status.close();
    await _stats.close();
    await _logs.close();
  }
}

/// [FakeVpnBackend] that also supports the kill switch capability.
class FakeKillSwitchBackend extends FakeVpnBackend implements KillSwitchCapable {
  /// Values passed to [setKillSwitch], in order.
  final List<bool> killSwitchCalls = <bool>[];

  @override
  Future<void> setKillSwitch(bool enabled) async {
    killSwitchCalls.add(enabled);
  }
}

/// Waits for pending microtasks and zero-delay timers.
Future<void> settle() => Future<void>.delayed(Duration.zero);
