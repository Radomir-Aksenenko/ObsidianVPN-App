import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/models/profile.dart';
import '../l10n/app_localizations.dart';
import '../platform_info.dart';
import '../state/app_state.dart';
import '../vpn/vpn_backend.dart';

/// How long quitting waits for the tunnel to go down before the window closes anyway.
const Duration kQuitDisconnectTimeout = Duration(seconds: 3);

/// Window close and tray behaviour for Windows, Linux and macOS.
///
/// [attach] runs once [AppState] is ready. From then on closing the window hides it to
/// the tray when [AppSettings.minimizeToTray] is set, and quits otherwise. The tray icon
/// shows the window on left click and offers Open, Connect or Disconnect, and Quit.
class DesktopShell with WindowListener, TrayListener {
  DesktopShell._(this._state);

  static DesktopShell? _instance;

  final AppState _state;
  bool _quitting = false;
  String? _menuSignature;

  /// Installs the tray icon and the close hook. Safe to call once per process;
  /// does nothing off desktop. Errors are swallowed: a failed tray must not block the app.
  static Future<void> attach(AppState state) async {
    if (!isDesktop || _instance != null) return;
    final shell = DesktopShell._(state);
    _instance = shell;
    try {
      await shell._start();
    } on Object catch (_) {
      // Without the tray the window still works: closing it quits, as before.
    }
  }

  Future<void> _start() async {
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
    trayManager.addListener(this);
    await trayManager.setIcon(_iconAsset);
    await trayManager.setToolTip(_l10n().appTitle);
    _state.addListener(_onStateChanged);
    await _refreshMenu();
  }

  /// Asset path relative to the bundle's flutter_assets folder.
  static String get _iconAsset =>
      isWindows ? 'assets/tray/obsidian.ico' : 'assets/tray/obsidian_64.png';

  AppLocalizations _l10n() => lookupAppLocalizations(_locale());

  Locale _locale() {
    return switch (_state.settings.locale) {
      AppLocalePref.en => const Locale('en'),
      AppLocalePref.ru => const Locale('ru'),
      AppLocalePref.system =>
        WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'en'
            ? const Locale('en')
            : const Locale('ru'),
    };
  }

  void _onStateChanged() {
    unawaited(_refreshMenu());
  }

  /// Rebuilds the tray menu only when its text or enabled state changes.
  Future<void> _refreshMenu() async {
    if (_quitting) return;
    final l10n = _l10n();
    final phase = _state.vpnStatus.phase;
    final connectAction =
        phase == VpnPhase.disconnected || phase == VpnPhase.error;
    final toggleLabel = connectAction ? l10n.trayConnect : l10n.trayDisconnect;
    final toggleDisabled = phase == VpnPhase.disconnecting;
    final signature = '${l10n.localeName}|$toggleLabel|$toggleDisabled';
    if (signature == _menuSignature) return;
    _menuSignature = signature;

    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: _keyOpen, label: l10n.trayOpen),
          MenuItem.separator(),
          MenuItem(
            key: _keyToggle,
            label: toggleLabel,
            disabled: toggleDisabled,
          ),
          MenuItem.separator(),
          MenuItem(key: _keyQuit, label: l10n.trayQuit),
        ],
      ),
    );
  }

  static const String _keyOpen = 'open';
  static const String _keyToggle = 'toggle';
  static const String _keyQuit = 'quit';

  @override
  void onTrayIconMouseDown() {
    unawaited(_showWindow());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _keyOpen:
        unawaited(_showWindow());
      case _keyToggle:
        unawaited(_toggleFromTray());
      case _keyQuit:
        unawaited(quit());
    }
  }

  Future<void> _toggleFromTray() async {
    try {
      await _state.toggle();
    } on AppStateException {
      // No server selected: the window shows the reason, so bring it up.
      await _showWindow();
    }
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  /// Native close button, Alt+F4 and the custom title bar all end up here.
  @override
  void onWindowClose() {
    unawaited(_handleClose());
  }

  Future<void> _handleClose() async {
    if (_quitting) return;
    if (_state.settings.minimizeToTray) {
      await windowManager.hide();
      return;
    }
    await quit();
  }

  /// Disconnects (at most [kQuitDisconnectTimeout]), removes the tray icon and closes
  /// the window for good.
  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    try {
      await _state.disconnect().timeout(kQuitDisconnectTimeout);
    } on Object catch (_) {
      // Timed out or failed. The process exit tears the tunnel down.
    }
    try {
      await trayManager.destroy();
    } on Object catch (_) {}
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }
}

/// Close action for the custom title bar. Same rules as the native close button.
Future<void> closeMainWindow() async {
  final shell = DesktopShell._instance;
  if (shell == null) {
    await windowManager.close();
    return;
  }
  await shell._handleClose();
}
