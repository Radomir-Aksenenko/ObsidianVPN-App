import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian_vpn/app.dart';
import 'package:obsidian_vpn/core/models/profile.dart';
import 'package:obsidian_vpn/core/models/split_tunnel.dart';
import 'package:obsidian_vpn/core/storage/store.dart';
import 'package:obsidian_vpn/state/app_state.dart';
import 'package:obsidian_vpn/theme/theme.dart';

import '../support/fake_vpn_backend.dart';

/// A profile that never touches the network (host does not resolve, no pings run).
ServerProfile fakeProfile({
  String id = '11111111-1111-4111-8111-111111111111',
  String name = 'Frankfurt',
  String country = 'DE',
  String host = 'fra.example.net',
  int port = 443,
  SplitTunnelConfig? split,
}) {
  return ServerProfile(
    id: id,
    name: name,
    countryCode: country,
    host: host,
    port: port,
    serverPublicKey: 'ab' * 32,
    source: ProfileSource.key,
    createdAt: DateTime.utc(2026, 1, 1),
    split: split ?? SplitTunnelConfig(),
  );
}

/// An [AppState] over an in-memory store and a [FakeVpnBackend].
Future<AppState> buildState(
  FakeVpnBackend backend, {
  List<ServerProfile> profiles = const <ServerProfile>[],
  String? key,
}) async {
  final store = AppStore.memory(secrets: MemorySecretStore());
  for (final p in profiles) {
    await store.putProfile(p);
  }
  final state = AppState(
    store: store,
    backend: backend,
    observeLifecycle: false,
    // Never the system hooks: on Windows they would try to relaunch elevated.
    platform: AppPlatformHooks(
      isDesktop: false,
      isWindows: false,
      isElevated: () async => true,
      relaunchElevated: (_) async {},
      setAutostart: (_) async {},
    ),
  );
  await state.init();
  if (key != null) await state.addKey(key);
  addTearDown(state.dispose);
  return state;
}

/// Pumps the full app (Shell + Home) at [size] logical pixels.
Future<void> pumpApp(
  WidgetTester tester,
  AppState state, {
  Size size = const Size(390, 844),
  double ratio = 1,
}) async {
  tester.view.physicalSize = size * ratio;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ObsidianApp(state: state, locale: const Locale('ru')),
  );
  await tester.pump();
}

/// Pumps only [child] inside the themed app chrome.
Future<void> pumpThemed(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}
