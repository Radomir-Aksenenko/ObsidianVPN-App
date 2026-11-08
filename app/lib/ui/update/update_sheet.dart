import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Durations;

import '../../app_version.dart';
import '../../core/update/update_checker.dart';
import '../../core/update/windows_updater.dart';
import '../../desktop/desktop_shell.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../widgets/widgets.dart';

/// Opens the update sheet for [release] over the current route.
///
/// The main button opens the installer for this platform in the browser, or
/// the release page when there is none. "Пропустить эту версию" saves the
/// version in settings, so the startup prompt stays quiet for it. A critical
/// release has no such button.
Future<void> showUpdateSheet(BuildContext context, AppRelease release) {
  final state = AppState.of(context);
  final asset = pickAssetForPlatform(
    release,
    Platform.operatingSystem,
    androidAbi: currentAndroidAbi(),
  );
  // Windows with a setup.exe: download, install silently and restart in place.
  final inApp = Platform.isWindows &&
      asset != null &&
      asset.name.toLowerCase().endsWith('-setup.exe') &&
      isTrustedDownloadUrl(asset.url);
  final install = ValueNotifier<UpdateInstallProgress>(
    const UpdateInstallProgress.idle(),
  );

  Future<void> runInstall() async {
    if (asset == null || install.value.busy) return;
    install.value = const UpdateInstallProgress.downloading(0);
    try {
      final file = await downloadInstaller(
        asset,
        onProgress: (f) => install.value = UpdateInstallProgress.downloading(f),
      );
      install.value = const UpdateInstallProgress.installing();
      await launchSilentInstaller(file);
      // The installer closes the app too, but leaving cleanly disconnects the VPN.
      await quitApp();
    } on Object catch (e) {
      debugPrint('update failed: $e');
      install.value = const UpdateInstallProgress.failed();
    }
  }

  return showAdaptiveSheet<void>(context, (sheetContext) {
    return UpdateSheet(
      release: release,
      currentVersion: kAppVersion,
      hasDownload: asset != null,
      inAppInstall: inApp,
      install: install,
      onInstall: runInstall,
      onDownload: () async {
        Navigator.of(sheetContext).pop();
        final opened = await openInBrowser(asset?.url ?? release.htmlUrl);
        if (!context.mounted) return;
        final l10n = AppLocalizations.of(context);
        showObsToast(
          context,
          !opened
              ? l10n.updateOpenFailed
              : asset != null
              ? l10n.updateDownloadStarted
              : l10n.updatePageOpened,
        );
      },
      onLater: () => Navigator.of(sheetContext).pop(),
      onSkip: () {
        Navigator.of(sheetContext).pop();
        state.updateSettings(
          state.settings.copyWith(skippedUpdateVersion: release.version),
        );
      },
      onOpenReleasePage: () => openInBrowser(release.htmlUrl),
    );
  });
}

/// Body of the update sheet: the new version, the installed one, the release
/// notes (hidden when empty) and the actions. The buttons only call back.
class UpdateSheet extends StatelessWidget {
  const UpdateSheet({
    super.key,
    required this.release,
    required this.currentVersion,
    this.hasDownload = true,
    required this.onDownload,
    this.inAppInstall = false,
    this.install,
    this.onInstall,
    required this.onLater,
    required this.onSkip,
    required this.onOpenReleasePage,
  });

  /// The release on offer.
  final AppRelease release;

  /// Version of the running app.
  final String currentVersion;

  /// Whether the primary action downloads a file rather than opening a page.
  final bool hasDownload;

  /// Primary action.
  final VoidCallback onDownload;

  /// Whether the primary action downloads and installs the update inside the app.
  final bool inAppInstall;

  /// Progress of the in-app install. Only read when [inAppInstall] is set.
  final ValueListenable<UpdateInstallProgress>? install;

  /// Starts the in-app install. Only used when [inAppInstall] is set.
  final VoidCallback? onInstall;

  /// Closes the sheet without other changes.
  final VoidCallback onLater;

  /// Skips [release] for the startup prompt.
  final VoidCallback onSkip;

  /// Opens the release page on GitHub.
  final VoidCallback onOpenReleasePage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.obs.colors;
    final theme = Theme.of(context).textTheme;
    final notes = release.notes.trim();
    final linkStyle = TextButton.styleFrom(foregroundColor: c.textDim);
    final critical = release.isCriticalFor(currentVersion);

    return ObsSheet(
      title: critical
          ? l10n.updateCriticalTitle(release.version)
          : l10n.updateSheetTitle(release.version),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.updateSheetCurrent(currentVersion),
            style: theme.bodyMedium!.copyWith(color: c.textDim),
          ),
          if (critical) ...[
            const SizedBox(height: Space.s8),
            Text(l10n.updateCriticalBody, style: theme.bodyMedium),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: Space.s16),
            Text(l10n.updateNotesTitle, style: theme.labelLarge),
            const SizedBox(height: Space.s8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Text(notes, style: theme.bodyMedium),
              ),
            ),
          ],
          const SizedBox(height: Space.s20),
          if (inAppInstall && install != null)
            ValueListenableBuilder<UpdateInstallProgress>(
              valueListenable: install!,
              builder: (context, p, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (p.busy) ...[
                    LinearProgressIndicator(value: p.fraction),
                    const SizedBox(height: Space.s8),
                    Text(
                      p.installing ? l10n.updateInstalling : l10n.updateDownloading,
                      style: theme.bodyMedium!.copyWith(color: c.textDim),
                    ),
                  ] else ...[
                    if (p.failed) ...[
                      Text(l10n.updateInstallFailed, style: theme.bodyMedium),
                      const SizedBox(height: Space.s8),
                    ],
                    ObsButton(label: l10n.updateInstall, onPressed: onInstall),
                    const SizedBox(height: Space.s8),
                    ObsButton(
                      label: l10n.updateLater,
                      kind: ObsButtonKind.secondary,
                      onPressed: onLater,
                    ),
                  ],
                ],
              ),
            )
          else ...[
            ObsButton(
              label: hasDownload ? l10n.updateDownload : l10n.updateOpenPage,
              onPressed: onDownload,
            ),
            const SizedBox(height: Space.s8),
            ObsButton(
              label: l10n.updateLater,
              kind: ObsButtonKind.secondary,
              onPressed: onLater,
            ),
          ],
          const SizedBox(height: Space.s4),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              if (!critical)
                TextButton(
                  style: linkStyle,
                  onPressed: onSkip,
                  child: Text(l10n.updateSkip),
                ),
              TextButton(
                style: linkStyle,
                onPressed: onOpenReleasePage,
                child: Text(l10n.updateReleaseNotesLink),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Progress of the in-app install shown by the update sheet.
@immutable
class UpdateInstallProgress {
  /// Nothing started yet.
  const UpdateInstallProgress.idle() : this._(_Phase.idle, null);

  /// Downloading; [fraction] is 0..1.
  const UpdateInstallProgress.downloading(double fraction)
    : this._(_Phase.downloading, fraction);

  /// The installer was started and the app is about to restart.
  const UpdateInstallProgress.installing() : this._(_Phase.installing, null);

  /// Download or start failed; the user can try again.
  const UpdateInstallProgress.failed() : this._(_Phase.failed, null);

  const UpdateInstallProgress._(this._phase, this.fraction);

  final _Phase _phase;

  /// Download fraction in 0..1, or null when not downloading.
  final double? fraction;

  /// Whether a download or install is running.
  bool get busy => _phase == _Phase.downloading || _phase == _Phase.installing;

  /// Whether the installer was started.
  bool get installing => _phase == _Phase.installing;

  /// Whether the last attempt failed.
  bool get failed => _phase == _Phase.failed;
}

enum _Phase { idle, downloading, installing, failed }
