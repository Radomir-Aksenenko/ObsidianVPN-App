import 'dart:async';

import 'package:flutter/material.dart';
import 'package:obsidian_vpn/core/models/profile.dart';
import 'package:obsidian_vpn/core/storage/store.dart';
import 'package:obsidian_vpn/desktop/desktop_shell.dart';
import 'package:obsidian_vpn/state/app_state.dart';

import 'l10n/app_localizations.dart';
import 'theme/theme.dart';
import 'ui/shell.dart';

/// Background shown while [AppState] loads. Matches the desktop window colour.
const Color _bootBackground = Color(0xFF0B0C0E);

/// Creates and starts [AppState] before the app is built. Shows a plain
/// background box until it is ready. Storage failures fall back to an
/// in-memory state so the app still starts.
class ObsidianBootstrap extends StatefulWidget {
  /// Creates the bootstrap. [launchArgs] are the process arguments.
  const ObsidianBootstrap({super.key, this.launchArgs = const <String>[]});

  /// Process arguments passed to [AppState.create] (`--connect`, `--autostart`).
  final List<String> launchArgs;

  @override
  State<ObsidianBootstrap> createState() => _ObsidianBootstrapState();
}

class _ObsidianBootstrapState extends State<ObsidianBootstrap> {
  late final Future<AppState> _ready = _boot();

  Future<AppState> _boot() async {
    final state = await _create();
    await state.init();
    // Tray icon and close behaviour. Desktop only, and never blocks the first frame.
    unawaited(DesktopShell.attach(state));
    return state;
  }

  Future<AppState> _create() async {
    try {
      return await AppState.create(launchArgs: widget.launchArgs);
    } on Object catch (_) {
      return AppState(store: AppStore.memory(), launchArgs: widget.launchArgs);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppState>(
      future: _ready,
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state == null) return const ColoredBox(color: _bootBackground);
        return ObsidianApp(state: state);
      },
    );
  }
}

/// Root of the app. Provides [AppState] through [AppScope] and applies the
/// theme and language from settings.
class ObsidianApp extends StatelessWidget {
  /// Creates the app around [state].
  const ObsidianApp({super.key, required this.state, this.locale});

  /// Shared application state.
  final AppState state;

  /// Forces a locale (used by tests). When null, the language comes from
  /// settings, and the device language decides when settings say "system".
  final Locale? locale;

  static final ThemeData _lightTheme = buildTheme(Brightness.light);
  static final ThemeData _darkTheme = buildTheme(Brightness.dark);

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final forced = locale ?? _localeOf(state.settings.locale);
          return MaterialApp(
            onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
            debugShowCheckedModeBanner: false,
            theme: _lightTheme,
            darkTheme: _darkTheme,
            themeMode: _themeModeOf(state.settings.themeMode),
            locale: forced,
            localeResolutionCallback: forced == null ? _resolveLocale : null,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Shell(),
          );
        },
      ),
    );
  }

  static Locale _resolveLocale(Locale? locale, Iterable<Locale> supported) {
    final language = locale?.languageCode ?? 'ru';
    return language == 'en' ? const Locale('en') : const Locale('ru');
  }

  static ThemeMode _themeModeOf(AppThemeMode mode) {
    return switch (mode) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.dark => ThemeMode.dark,
      AppThemeMode.light => ThemeMode.light,
    };
  }

  static Locale? _localeOf(AppLocalePref pref) {
    return switch (pref) {
      AppLocalePref.system => null,
      AppLocalePref.ru => const Locale('ru'),
      AppLocalePref.en => const Locale('en'),
    };
  }
}
