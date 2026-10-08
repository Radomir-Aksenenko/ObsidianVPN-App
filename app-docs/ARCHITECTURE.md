# Obsidian VPN: unified Flutter client

One Flutter (Dart) codebase for Windows, macOS, Linux, Android and iOS. It replaces
`desktop/` (Tauri) and `ios/` (SwiftUI). Old clients stay in the repo until the new one
reaches parity. Feature reference: `app-docs/desktop-inventory.md`, `app-docs/ios-inventory.md`.
Design: `app-docs/DESIGN.md`.

Native code exists only where the OS forces it (VPN APIs). Everything else is Dart.

## Toolchain notes (Windows dev box)

- Flutter 3.44 at `C:\src\flutter`. Before any `flutter` command in Git Bash, strip scrcpy from
  PATH or flutter crashes on a broken adb symlink:
  `export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v scrcpy | paste -sd:)`
- All builds (every platform, including Windows) run in GitHub Actions only. Locally run only
  `flutter analyze` and `flutter test`. Never install SDKs or write caches to drive C: set
  `GOCACHE=E:\PC-Storage\Temp\Radomir\claude\E--Projects-tets-vpn\1cce9ccf-d8ac-4c9b-b0c0-180f6142fd64\scratchpad\gocache`
  before any Go command.
- Go core: submodule `core/` (source repo `E:\Projects\tets_vpn`, module name `obsidian`).

## Layout

```
app/                                  Flutter project, package name obsidian_vpn
  pubspec.yaml
  assets/fonts/Manrope.ttf, JetBrainsMono.ttf   (copied from desktop/src/fonts)
  lib/
    main.dart                         bootstrap, error zone, window setup on desktop
    app.dart                          MaterialApp, theme, router, AppScope
    l10n/app_ru.arb, app_en.arb       all UI strings (Russian is primary)
    theme/tokens.dart                 colors, radii, spacing, durations (from DESIGN.md)
    theme/theme.dart                  ThemeData light + dark
    core/
      models/profile.dart             ServerProfile, VpsAccess, IssuedKey
      models/split_tunnel.dart        SplitMode, SplitTunnelConfig, rule parser, presets
      models/settings.dart            AppSettings
      codec/obsidian_key.dart         parse obsidian:// vpn:// OBSDN-, encode both, ClientConfig
      codec/client_config.dart        ClientConfig model + toJson (Go ClientConfig field names)
      storage/store.dart              JSON file in app support dir + flutter_secure_storage
      net/ping.dart                   TCP connect ping
    vpn/
      vpn_backend.dart                abstract VpnBackend + VpnStatus + TrafficStats
      vpn_controller.dart             ChangeNotifier state machine used by UI
      desktop_backend.dart            Windows/Linux/macOS: spawns obsidian-client
      desktop_log_parser.dart         stdout lines -> stage/status (pure, unit tested)
      channel_backend.dart            Android + iOS: MethodChannel/EventChannel
      elevation.dart                  Windows UAC relaunch, pkexec, osascript
    vps/
      ssh_session.dart                dartssh2 wrapper (password or key)
      deployer.dart                   deploy / update / version check / sni / reset
      keyserver.dart                  key issue (OBSDN encode with token, days, devices)
      server_assets.dart              where obsidian-server-linux + keyserver.py come from
    ui/
      shell.dart                      adaptive scaffold: bottom bar (narrow) / rail (wide)
      home/                           connect dial, status, stats, server chip, split row
      servers/                        list, add key sheet, qr scan, server detail
      vps/                            deploy wizard, manage server, issue key, issued key
      split/                          split tunnel editor
      settings/                       settings, logs, about
      widgets/                        shared primitives (tiles, sheets, buttons, toasts)
  android/app/src/main/kotlin/com/obsidian/vpn/
      MainActivity.kt                 MethodChannel "obsidian/vpn", EventChannel "obsidian/vpn/events"
      ObsidianVpnService.kt           VpnService, calls gomobile StartTunnelWithConfig(fd)
  android/app/libs/obsidian.aar       built in CI by gomobile (not committed)
  ios/Runner/VpnChannel.swift         NETunnelProviderManager bridge
  ios/PacketTunnel/                   NEPacketTunnelProvider, ported from ios/PacketTunnel
  ios/Frameworks/Obsidian.xcframework built in CI (not committed)
  windows/runner, linux/, macos/      standard runners; desktop bundles obsidian-client binary
```

## Dependencies (pubspec)

dartssh2, cryptography (X25519), flutter_secure_storage, path_provider, mobile_scanner,
qr_flutter, window_manager, tray_manager, file_picker, provider is NOT used: state is plain
`ChangeNotifier` + `ListenableBuilder` + a small `AppScope` InheritedWidget.
zlib and base32: `dart:io` ZLibCodec, base32 implemented in `codec/` (RFC 4648, no padding).
Add nothing else without a reason in the PR description.

## The single contract: ClientConfig JSON

The Go type `obsidian.ClientConfig` (`core/obsidian/uri.go`, `core/obsidian/protocol.go`) is
the source of truth. Dart builds the same JSON for every platform:

- Desktop: write `<appSupport>/runtime/<profileId>.json`, run
  `obsidian-client --config <path> --debug`.
- Android: `Mobile.startTunnelWithConfig(json, fd, mtu, protector, status, stats)`.
- iOS: `MobileStartPacketTunnelWithConfig(json, 1280, ...)` (new Go func, see below).

Persisted per profile: `client_private_key` / `client_public_key` (X25519, generated once in
Dart, stored in secure storage). Key server registration needs the stable public key.

Go additions needed in `core/pkg/mobile/mobile.go` (edit in `E:\Projects\tets_vpn`, then bump
submodule): `StartPacketTunnelWithConfig(configJSON string, mtu int, protector, status, stats)`.

## VpnBackend (Dart)

```dart
enum VpnPhase { disconnected, connecting, connected, reconnecting, disconnecting, error }

class VpnStatus {
  final VpnPhase phase;
  final int stage;          // 0..4, handshake progress shown on the dial
  final String? error;      // human readable, Russian
  final DateTime? connectedAt;
}

class TrafficStats { final int rxBytes, txBytes, rxBps, txBps; }

abstract class VpnBackend {
  Stream<VpnStatus> get status;
  Stream<TrafficStats> get stats;      // only emits while statsActive == true
  Stream<String> get logs;             // ring buffer of last 500 lines lives in controller
  Future<bool> ensurePermission();     // Android VpnService.prepare, iOS manager save, desktop elevation
  Future<void> connect({required String profileId, required String name,
                        required String serverHost, required String configJson});
  Future<void> disconnect();
  Future<void> applySplit(String configJson);   // live where possible, else reconnect
  set statsActive(bool v);             // false when app is backgrounded: saves battery
}
```

Desktop stage mapping: port the table in `desktop-inventory.md` section 4 into
`desktop_log_parser.dart`, with unit tests per line pattern. "reconnecting in" maps to
`reconnecting`. Stop = close child stdin, wait 1.5 s, kill. Run the Windows network cleanup
from the same section on startup and after disconnect.

Desktop privileges:
- Windows: if not elevated, relaunch self via `powershell Start-Process -Verb RunAs
  -ArgumentList '--connect'` and exit (same as old app). Autostart via `schtasks /RL HIGHEST`.
- Linux: run the client through `pkexec`. macOS: `osascript -e 'do shell script "..." with
  administrator privileges'`. Kill via the same mechanism.

Backend calls never take Dart model types. Split tunnel settings travel inside the config JSON
(`split_tunnel_mode`, `split_sites`, plus `split_presets` for display), so backends only see:

```dart
Future<void> connect({required String profileId, required String name,
                      required String serverHost, required String configJson});
Future<void> applySplit(String configJson);
```

## Native channel protocol (Android and iOS, identical)

MethodChannel `obsidian/vpn`:

| Method | Args | Result |
|---|---|---|
| `prepare` | none | bool: VPN permission granted / profile installed |
| `connect` | `{profileId, name, serverHost, configJson}` | null, throws PlatformException(code, message) |
| `disconnect` | none | null |
| `applySplit` | `{configJson}` | null |
| `setStatsActive` | `{active: bool}` | null |
| `currentStatus` | none | status map (same shape as event) |

EventChannel `obsidian/vpn/events` emits maps:
- `{type: "status", phase: "disconnected|connecting|connected|reconnecting|disconnecting|error", stage: 0..4, error: String?, connectedAtMs: int?}`
- `{type: "stats", rx: int, tx: int, rxBps: int, txBps: int}` (max 1 Hz, only while stats active)
- `{type: "log", line: String}`

Android stage mapping from Go StatusListener: 1 starting, 3 TUN ready / Go connecting,
4 connected (stage 2 unused on Android). iOS: NEVPNStatus connecting 1..3 by provider messages, connected 4.

## Bundled binaries (`app/assets/bin/`, gitignored, produced by `scripts/build-core-assets.sh`)

- `obsidian-client-windows-amd64.exe`, `wintun.dll`, `obsidian-client-linux-amd64`,
  `obsidian-client-darwin-universal` (desktop only; extracted to `<appSupport>/runtime/`,
  re-extracted when sha256 differs, chmod +x on unix).
- `obsidian-server-linux-amd64`, `obsidian-server-linux-arm64`, `keyserver.py`
  (all platforms, used by VPS deploy; arch picked from `uname -m` on the VPS).
- The script builds from `core/` with `CGO_ENABLED=0 go build -trimpath -ldflags "-s -w"`
  and copies `desktop/src-tauri/resources/keyserver.py`. CI runs it before `flutter build`.

## Battery and performance rules

- No animation runs while the app is idle or connected. Animations only play on state change.
- Stats and ping timers stop when `AppLifecycleState` is not `resumed` or window is hidden.
- Stats UI updates at most 1 Hz. Ping every 30 s, only on visible screens.
- No polling in native code. Android stats come from the Go StatsListener callback,
  throttled to 1 Hz, and are dropped when no Dart listener is attached.
- Lists use `ListView.builder`. Images: none except icons. Use `const` widgets.

## Secrets

Config URIs, OBSDN keys, client private keys, SSH passwords, SSH keys and keyserver admin
tokens go to `flutter_secure_storage` only. The JSON file holds non-secret metadata and
references secrets by profile id. Logs never print keys or tokens.

## Quality gates (every task)

1. `flutter analyze` returns no issues.
2. `flutter test` passes. Pure logic (codec, split parser, log parser, store migration) has tests.
3. No TODO stubs left in delivered code. If something cannot be done, say so in the report.
4. UI strings come from ARB files, Russian first. No em dash or en dash characters in strings.
