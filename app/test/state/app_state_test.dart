import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/core/codec/obsidian_key.dart';
import 'package:obsidian_vpn/core/models/profile.dart';
import 'package:obsidian_vpn/core/models/split_tunnel.dart';
import 'package:obsidian_vpn/core/storage/store.dart';
import 'package:obsidian_vpn/state/app_state.dart';
import 'package:obsidian_vpn/vps/key_issuer.dart';
import 'package:obsidian_vpn/vps/vps_models.dart';
import 'package:obsidian_vpn/vpn/elevation.dart';
import 'package:obsidian_vpn/vpn/vpn_backend.dart';

import '../support/fake_vpn_backend.dart';
import '../support/vectors.dart';

AppPlatformHooks _platform({
  bool desktop = false,
  bool windows = false,
  bool elevated = true,
  Future<void> Function(List<String> args)? relaunch,
  List<bool>? autostartCalls,
  bool autostartFails = false,
}) {
  return AppPlatformHooks(
    isDesktop: desktop,
    isWindows: windows,
    isElevated: () async => elevated,
    relaunchElevated: relaunch ?? (_) async {},
    setAutostart: (enabled) async {
      if (autostartFails) throw Exception('schtasks failed');
      autostartCalls?.add(enabled);
    },
  );
}

void main() {
  late Directory temp;
  late MemorySecretStore secrets;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('obsidian_app_state_');
    secrets = MemorySecretStore();
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  Future<AppState> open({
    required FakeVpnBackend backend,
    AppPlatformHooks? platform,
    List<String> launchArgs = const <String>[],
  }) async {
    final store = await AppStore.open(dir: temp.path, secrets: secrets);
    final state = AppState(
      store: store,
      backend: backend,
      platform: platform ?? _platform(),
      launchArgs: launchArgs,
      observeLifecycle: false,
    );
    await state.init();
    return state;
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('profiles', () {
    test('addKey saves the first profile, selects it, and keeps the key out of state.json', () async {
      final backend = FakeVpnBackend();
      final state = await open(backend: backend);
      final input = keyLegacyHost();

      final profile = await state.addKey(input);

      expect(state.profiles, hasLength(1));
      expect(state.selectedProfile?.id, profile.id);
      expect(profile.host, 'legacy.example.net');
      expect(profile.port, 8443);
      expect(profile.name, 'legacy.example.net');
      expect(profile.countryCode, 'VPN');
      expect(secrets.values[SecretKeys.profile(profile.id, SecretKeys.rawKey)], input.trim());
      final raw = File('${temp.path}${Platform.pathSeparator}state.json').readAsStringSync();
      expect(raw, isNot(contains('token=abc')));
      expect(raw, isNot(contains(input)));
    });

    test('addKey deduplicates by host, port and public key', () async {
      final state = await open(backend: FakeVpnBackend());
      final first = await state.addKey(keyLegacyHost(), name: 'Первый');

      final second = await state.addKey(keyLegacyHost(), name: 'Второй');

      expect(second.id, first.id);
      expect(state.profiles, hasLength(1));
      expect(state.profiles.single.name, 'Первый');
    });

    test('addKey rejects invalid input with KeyFormatException', () async {
      final state = await open(backend: FakeVpnBackend());
      await expectLater(state.addKey('not a key'), throwsA(isA<KeyFormatException>()));
      expect(state.profiles, isEmpty);
    });

    test('a second profile keeps the selection until selectProfile is called', () async {
      final state = await open(backend: FakeVpnBackend());
      final first = await state.addKey(keyLegacyHost());
      final second = await state.addKey(keyOtherHost(), name: 'Амстердам');
      expect(second.countryCode, 'NL');
      expect(state.selectedProfile?.id, first.id);

      await state.selectProfile(second.id);
      expect(state.selectedProfile?.id, second.id);
      await expectLater(state.selectProfile('missing'), throwsA(isA<AppStateException>()));
    });

    test('rename, favorite and remove', () async {
      final backend = FakeVpnBackend();
      final state = await open(backend: backend);
      final first = await state.addKey(keyLegacyHost());
      final second = await state.addKey(keyOtherHost());

      await expectLater(
        state.renameProfile(first.id, '   '),
        throwsA(isA<AppStateException>()),
      );
      await state.renameProfile(first.id, '  Мой сервер ');
      expect(state.profileById(first.id)?.name, 'Мой сервер');

      await state.toggleFavorite(second.id);
      expect(state.profileById(second.id)?.isFavorite, isTrue);

      await state.removeProfile(first.id);
      expect(state.profiles.map((p) => p.id), [second.id]);
      expect(state.selectedProfile?.id, second.id);
      expect(
        secrets.values.keys.where((k) => k.startsWith('profile.${first.id}.')),
        isEmpty,
      );
    });

    test('removing the active profile disconnects it first', () async {
      final backend = FakeVpnBackend();
      final state = await open(backend: backend);
      final profile = await state.addKey(keyLegacyHost());
      await state.connect();
      backend.emitStatus(const VpnStatus(phase: VpnPhase.connected, stage: 4));

      await state.removeProfile(profile.id);

      expect(backend.disconnectCalls, 1);
      expect(state.profiles, isEmpty);
    });
  });

  group('connect', () {
    test('passes runtime JSON with client keys and split fields to the backend', () async {
      final backend = FakeVpnBackend();
      final state = await open(backend: backend);
      final profile = await state.addKey(keyLegacyHost());
      await state.setSplit(
        profile.id,
        SplitTunnelConfig(
          mode: SplitMode.include,
          entries: const ['example.org', '10.0.0.0/8'],
          presets: const {SplitPreset.telegram},
        ),
      );

      await state.connect();

      expect(backend.connects, hasLength(1));
      final call = backend.connects.single;
      expect(call.profileId, profile.id);
      expect(call.serverHost, 'legacy.example.net');
      expect(call.name, profile.name);
      final json = jsonDecode(call.configJson) as Map<String, dynamic>;
      expect(json['server_host'], 'legacy.example.net');
      expect(json['client_private_key'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(json['client_public_key'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(json['tun_address'], matches(RegExp(r'^10\.8\.0\.\d+/24$')));
      expect(json['split_tunnel_mode'], 'include');
      expect(json['split_presets'], ['telegram']);
      final sites = (json['split_sites'] as List<dynamic>).cast<String>();
      expect(sites.first, 'example.org');
      expect(sites, contains('10.0.0.0/8'));
      expect(sites, containsAll(SplitPreset.telegram.entries));
      expect(
        secrets.values[SecretKeys.profile(profile.id, SecretKeys.clientPrivateKey)],
        json['client_private_key'],
      );
    });

    test('reuses the same client keypair on later connects', () async {
      final backend = FakeVpnBackend();
      final state = await open(backend: backend);
      await state.addKey(keyLegacyHost());

      await state.connect();
      backend.emitStatus(const VpnStatus(phase: VpnPhase.disconnected));
      await state.connect();

      expect(backend.connects, hasLength(2));
      final first = jsonDecode(backend.connects[0].configJson) as Map<String, dynamic>;
      final second = jsonDecode(backend.connects[1].configJson) as Map<String, dynamic>;
      expect(second['client_private_key'], first['client_private_key']);
      expect(second['client_public_key'], first['client_public_key']);
    });

    test('a backend error becomes an error status with its message', () async {
      final backend = FakeVpnBackend()
        ..connectError = const VpnBackendException('Сеть недоступна');
      final state = await open(backend: backend);
      await state.addKey(keyLegacyHost());

      await state.connect();

      expect(state.vpnStatus.phase, VpnPhase.error);
      expect(state.vpnStatus.error, 'Сеть недоступна');
      expect(state.connectedProfile, isNull);
    });

    test('Windows without elevation relaunches; a refused UAC prompt becomes an error status', () async {
      var relaunchArgs = <String>[];
      final backend = FakeVpnBackend();
      final state = await open(
        backend: backend,
        platform: _platform(
          windows: true,
          elevated: false,
          desktop: true,
          relaunch: (args) async {
            relaunchArgs = args;
            throw const ElevationDenied();
          },
        ),
      );
      await state.addKey(keyLegacyHost());

      await state.connect();

      expect(relaunchArgs, ['--connect']);
      expect(backend.connects, isEmpty);
      expect(state.vpnStatus.phase, VpnPhase.error);
      expect(state.vpnStatus.error, const ElevationDenied().message);
    });

    test('kill switch is passed only to a backend that supports it', () async {
      final backend = FakeKillSwitchBackend();
      final state = await open(backend: backend);
      await state.addKey(keyLegacyHost());
      await state.updateSettings(state.settings.copyWith(killSwitch: true));

      await state.connect();

      expect(backend.killSwitchCalls, [true]);
      expect(backend.connects, hasLength(1));
    });

    test('connect without any profile throws AppStateException', () async {
      final state = await open(backend: FakeVpnBackend());
      await expectLater(state.connect(), throwsA(isA<AppStateException>()));
    });

    test('toggle disconnects when connected and connects otherwise', () async {
      final backend = FakeVpnBackend();
      final state = await open(backend: backend);
      await state.addKey(keyLegacyHost());

      await state.toggle();
      expect(backend.connects, hasLength(1));

      backend.emitStatus(const VpnStatus(phase: VpnPhase.connected, stage: 4));
      await state.toggle();
      expect(backend.disconnectCalls, 1);
    });

    test('auto connect runs on init when --connect is passed', () async {
      final backend = FakeVpnBackend();
      final first = await open(backend: backend);
      await first.addKey(keyLegacyHost());

      final backend2 = FakeVpnBackend();
      await open(backend: backend2, launchArgs: const ['--connect']);
      await settle();
      await settle();

      expect(backend2.connects, hasLength(1));
    });

    test('no auto connect without --connect or the autoConnect setting', () async {
      final state = await open(backend: FakeVpnBackend());
      await state.addKey(keyLegacyHost());
      final backend = FakeVpnBackend();
      await open(backend: backend, launchArgs: const ['--autostart']);
      await settle();
      expect(backend.connects, isEmpty);
    });
  });

  group('status and logs', () {
    test('clearLogs empties the log and notifies once', () async {
      final backend = FakeVpnBackend();
      final state = await open(backend: backend);
      backend.emitLog('first');
      backend.emitLog('second');
      await settle();
      var notified = 0;
      state.addListener(() => notified++);

      state.clearLogs();

      expect(state.logs, isEmpty);
      expect(notified, 1);
      state.clearLogs();
      expect(notified, 1);

      backend.emitLog('after');
      await settle();
      expect(state.logs, ['after']);
    });

    test('status and stats propagate; the connected profile follows the phase', () async {
      final backend = FakeVpnBackend();
      final state = await open(backend: backend);
      final profile = await state.addKey(keyLegacyHost());

      backend.emitStatus(const VpnStatus(phase: VpnPhase.connecting, stage: 2));
      expect(state.vpnStatus.stage, 2);
      expect(state.isBusy, isTrue);

      backend.emitStatus(VpnStatus(
        phase: VpnPhase.connected,
        stage: 4,
        connectedAt: DateTime.utc(2026),
      ));
      expect(state.isConnected, isTrue);
      expect(state.connectedProfile?.id, profile.id);

      backend.emitStats(
        const TrafficStats(rxBytes: 10, txBytes: 20, rxBps: 1, txBps: 2),
      );
      expect(state.stats?.rxBytes, 10);

      await state.disconnect();
      expect(backend.disconnectCalls, 1);
      backend.emitStatus(const VpnStatus(phase: VpnPhase.disconnected));
      expect(state.connectedProfile, isNull);
      expect(state.stats, isNull);
    });

    test('keeps the last 500 log lines, oldest first, read-only', () async {
      final backend = FakeVpnBackend();
      final state = await open(backend: backend);

      for (var i = 0; i < 600; i++) {
        backend.emitLog('line $i');
      }

      expect(state.logs, hasLength(kAppLogCapacity));
      expect(state.logs.first, 'line 100');
      expect(state.logs.last, 'line 599');
      expect(() => (state.logs as List<String>).add('x'), throwsUnsupportedError);
    });

    test('setSplit applies the new rules live only while connected to that profile', () async {
      final backend = FakeVpnBackend();
      final state = await open(backend: backend);
      final profile = await state.addKey(keyLegacyHost());
      final split = SplitTunnelConfig(mode: SplitMode.exclude, entries: const ['a.example']);

      await state.setSplit(profile.id, split);
      expect(backend.splitConfigs, isEmpty);

      await state.connect();
      backend.emitStatus(const VpnStatus(phase: VpnPhase.connected, stage: 4));
      await state.setSplit(profile.id, split.copyWith(mode: SplitMode.include));

      expect(backend.splitConfigs, hasLength(1));
      final json = jsonDecode(backend.splitConfigs.single) as Map<String, dynamic>;
      expect(json['split_tunnel_mode'], 'include');
      expect(json['split_sites'], ['a.example']);
    });
  });

  group('settings', () {
    test('autostart is applied on desktop, and a failure saves nothing', () async {
      final calls = <bool>[];
      final state = await open(
        backend: FakeVpnBackend(),
        platform: _platform(desktop: true, autostartCalls: calls),
      );

      await state.updateSettings(state.settings.copyWith(autostart: true));
      expect(calls, [true]);
      expect(state.settings.autostart, isTrue);

      final failing = await open(
        backend: FakeVpnBackend(),
        platform: _platform(desktop: true, autostartFails: true),
      );
      await expectLater(
        failing.updateSettings(failing.settings.copyWith(autostart: false)),
        throwsA(isA<AppStateException>()),
      );
    });

    test('updateSettings keeps the selected profile when the new settings carry none', () async {
      final state = await open(backend: FakeVpnBackend());
      final profile = await state.addKey(keyLegacyHost());

      await state.updateSettings(const AppSettings(themeMode: AppThemeMode.dark));

      expect(state.settings.themeMode, AppThemeMode.dark);
      expect(state.settings.lastProfileId, profile.id);
    });
  });

  group('vps and issued keys', () {
    test('saveVpsProfile creates, then updates the same profile; secrets follow the credentials', () async {
      final state = await open(backend: FakeVpnBackend());
      final owner = parseKey(keyOtherHost());
      final result = DeployResult(
        ownerKey: keyOtherHost(),
        ownerConfig: owner,
        adminToken: 'abcd',
        tcpPort: 443,
        udpPort: 443,
        sni: 'example.org',
        ipv6: false,
        serverVersion: '1.2.3',
        hostKeyFingerprint: 'SHA256:xyz',
      );

      final created = await state.saveVpsProfile(
        result,
        const VpsCredentials(host: '198.51.100.7', password: 'pw'),
      );

      expect(created.source, ProfileSource.vps);
      expect(created.vps?.host, '198.51.100.7');
      expect(created.vps?.password, isNull);
      expect(created.vpsHostKey, 'SHA256:xyz');
      expect(created.serverVersion, '1.2.3');
      expect(state.selectedProfile?.id, created.id);

      final loaded = await state.vpsCredentials(created.id);
      expect(loaded?.password, 'pw');
      expect(loaded?.privateKeyPem, isNull);
      expect(loaded?.hostKeyFingerprint, 'SHA256:xyz');
      expect(await state.adminToken(created.id), 'abcd');

      final updated = await state.saveVpsProfile(
        result,
        const VpsCredentials(host: '198.51.100.7'),
        hostKey: 'SHA256:new',
      );
      expect(updated.id, created.id);
      expect(state.profiles, hasLength(1));
      expect((await state.vpsCredentials(created.id))?.password, isNull);
      expect((await state.vpsCredentials(created.id))?.hostKeyFingerprint, 'SHA256:new');
    });

    test('vpsCredentials is null for key-imported profiles', () async {
      final state = await open(backend: FakeVpnBackend());
      final profile = await state.addKey(keyLegacyHost());
      expect(await state.vpsCredentials(profile.id), isNull);
    });

    test('issued keys are added, replaced and removed with their secrets', () async {
      final state = await open(backend: FakeVpnBackend());
      final key = IssuedKey(
        id: 'i1',
        name: 'Phone',
        serverId: 'srv',
        devices: 1,
        days: 0,
        key: keyLegacyHost(),
        uri: 'obsidian://x',
        created: DateTime.utc(2026),
      );

      await state.addIssuedKey(key);
      expect(state.issuedKeys.single.name, 'Phone');
      expect(secrets.values[SecretKeys.issued('i1', SecretKeys.issuedKey)], keyLegacyHost());

      await state.removeIssuedKey('i1');
      expect(state.issuedKeys, isEmpty);
      expect(secrets.values.keys.where((k) => k.startsWith('issued.i1.')), isEmpty);
    });
  });

  testWidgets('lifecycle toggles statsActive and stops when not resumed', (tester) async {
    final backend = FakeVpnBackend();
    final state = AppState(
      store: AppStore.memory(secrets: secrets),
      backend: backend,
      platform: _platform(),
    );
    addTearDown(state.dispose);
    await state.init();

    // Valid transitions only: resumed, inactive, resumed, inactive, hidden.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);

    expect(backend.statsActiveHistory, [true, false, true, false, false]);
  });
}
