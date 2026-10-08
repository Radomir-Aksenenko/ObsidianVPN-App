import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart' hide Durations;
import 'package:flutter/services.dart';

import '../../core/models/profile.dart';
import '../../l10n/app_localizations.dart';
import '../../platform_info.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../vpn/channel_backend.dart';
import '../../vpn/vpn_backend.dart';
import '../widgets/widgets.dart';
import 'logs_screen.dart';

/// App version shown in About. Override at build time with `--dart-define=APP_VERSION=...`.
const String _appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '2.0.0',
);

/// Device id as shown to the user: the first 12 hex digits in groups of four
/// (`A1B2-C3D4-E5F6`). The full id is what gets copied.
@visibleForTesting
String groupDeviceId(String id) {
  final hex = id.replaceAll(RegExp('[^0-9a-fA-F]'), '').toUpperCase();
  final head = hex.length > 12 ? hex.substring(0, 12) : hex;
  final groups = <String>[];
  for (var i = 0; i < head.length; i += 4) {
    groups.add(head.substring(i, i + 4 > head.length ? head.length : i + 4));
  }
  return groups.join('-');
}

/// Settings tab: connection, interface, desktop behaviour, diagnostics and about.
/// Rows that do not apply to the running platform are not built at all.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppState.of(context);
    final settings = state.settings;
    final l10n = AppLocalizations.of(context);
    final c = context.obs.colors;

    Future<void> save(AppSettings next) => _save(context, next);

    return TabPage(
      title: l10n.navSettings,
      children: [
        ObsGroup(
          label: l10n.settingsSectionConnection,
          children: [
            _SwitchRow(
              title: l10n.settingsAutoConnect,
              value: settings.autoConnect,
              onChanged: (v) => save(settings.copyWith(autoConnect: v)),
            ),
            if (isIOS)
              _SwitchRow(
                title: l10n.settingsKillSwitch,
                subtitle: l10n.settingsKillSwitchIosCaption,
                value: settings.killSwitch,
                onChanged: (v) => save(settings.copyWith(killSwitch: v)),
              ),
            if (isAndroid)
              ObsRow(
                title: l10n.settingsKillSwitch,
                subtitle: l10n.settingsKillSwitchAndroidCaption,
                trailing: Icon(
                  Icons.open_in_new_rounded,
                  size: 20,
                  color: c.textFaint,
                ),
                onTap: () => _openVpnSettings(context),
              ),
          ],
        ),
        ObsGroup(
          label: l10n.settingsSectionInterface,
          children: [
            _SegmentRow<AppThemeMode>(
              title: l10n.settingsTheme,
              value: settings.themeMode,
              options: [
                ObsSegment(
                  value: AppThemeMode.system,
                  label: l10n.settingsThemeSystem,
                ),
                ObsSegment(
                  value: AppThemeMode.dark,
                  label: l10n.settingsThemeDark,
                ),
                ObsSegment(
                  value: AppThemeMode.light,
                  label: l10n.settingsThemeLight,
                ),
              ],
              onChanged: (v) => save(settings.copyWith(themeMode: v)),
            ),
            _SegmentRow<AppLocalePref>(
              title: l10n.settingsLanguage,
              value: settings.locale,
              options: [
                ObsSegment(
                  value: AppLocalePref.system,
                  label: l10n.settingsLocaleSystem,
                ),
                ObsSegment(
                  value: AppLocalePref.ru,
                  label: l10n.settingsLocaleRu,
                ),
                ObsSegment(
                  value: AppLocalePref.en,
                  label: l10n.settingsLocaleEn,
                ),
              ],
              onChanged: (v) => save(settings.copyWith(locale: v)),
            ),
            if (isMobile)
              _SwitchRow(
                title: l10n.settingsHaptics,
                value: settings.haptics,
                onChanged: (v) => save(settings.copyWith(haptics: v)),
              ),
          ],
        ),
        if (isDesktop)
          ObsGroup(
            label: l10n.settingsSectionDesktop,
            children: [
              _SwitchRow(
                title: l10n.settingsAutostart,
                value: settings.autostart,
                onChanged: (v) => save(settings.copyWith(autostart: v)),
              ),
              _SwitchRow(
                title: l10n.settingsMinimizeToTray,
                subtitle: l10n.settingsMinimizeToTrayCaption,
                value: settings.minimizeToTray,
                onChanged: (v) => save(settings.copyWith(minimizeToTray: v)),
              ),
            ],
          ),
        ObsGroup(
          label: l10n.settingsSectionDiagnostics,
          children: [
            ObsRow(
              title: l10n.settingsConnectionLog,
              trailing: Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: c.textFaint,
              ),
              onTap: () => Navigator.of(
                context,
              ).push<void>(_pageRoute(const LogsScreen())),
            ),
            ObsRow(
              title: l10n.settingsDeviceId,
              subtitle: groupDeviceId(state.deviceId),
              subtitleMono: true,
              trailing: Icon(
                Icons.content_copy_rounded,
                size: 18,
                color: c.textFaint,
              ),
              onTap: () => _copyDeviceId(context, state.deviceId),
            ),
          ],
        ),
        ObsGroup(
          label: l10n.settingsSectionAbout,
          children: [
            ObsRow(
              title: l10n.settingsVersion,
              trailing: Text(
                _appVersion,
                style: context.obs.mono.copyWith(color: c.textDim),
              ),
            ),
            _InfoRow(l10n.settingsProtocol),
          ],
        ),
      ],
    );
  }

  /// Saves [next]. A refused save (autostart on desktop) shows the reason as a toast.
  static Future<void> _save(BuildContext context, AppSettings next) async {
    final state = AppState.of(context);
    try {
      await state.updateSettings(next);
    } on AppStateException catch (e) {
      if (context.mounted) {
        showObsToast(context, e.messageRu, kind: ObsToastKind.error);
      }
    }
  }

  static Future<void> _openVpnSettings(BuildContext context) async {
    try {
      await openSystemVpnSettings();
    } on VpnBackendException catch (e) {
      if (context.mounted) {
        showObsToast(context, e.message, kind: ObsToastKind.error);
      }
    }
  }

  static Future<void> _copyDeviceId(BuildContext context, String id) async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: id));
    if (context.mounted) {
      showObsToast(
        context,
        l10n.settingsDeviceIdCopied,
        kind: ObsToastKind.success,
      );
    }
  }

  /// Cupertino transitions on Apple platforms, Material everywhere else.
  static Route<void> _pageRoute(Widget page) {
    if (isIOS || isMacOS) {
      return CupertinoPageRoute<void>(builder: (_) => page);
    }
    return MaterialPageRoute<void>(builder: (_) => page);
  }
}

/// A row with a switch on the trailing side. Tapping the row toggles it too.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    final theme = Theme.of(context).textTheme;
    // Own layout instead of ObsRow: long titles wrap here rather than ellipsize.
    return InkWell(
      onTap: () => onChanged(!value),
      mouseCursor: SystemMouseCursors.click,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s16,
          vertical: Space.s12,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: theme.bodyLarge),
                  if (subtitle != null) ...[
                    const SizedBox(height: Space.s4),
                    Text(
                      subtitle!,
                      style: theme.bodySmall!.copyWith(color: c.textDim),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: Space.s12),
            ObsSwitch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// A non-interactive text row that wraps instead of ellipsizing.
class _InfoRow extends StatelessWidget {
  const _InfoRow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s16,
        vertical: Space.s16,
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
    );
  }
}

/// A title above a full-width segmented control, inside a group.
class _SegmentRow<T> extends StatelessWidget {
  const _SegmentRow({
    required this.title,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final List<ObsSegment<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.s16,
        Space.s12,
        Space.s16,
        Space.s16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: Space.s8),
          ObsSegmented<T>(options: options, value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
