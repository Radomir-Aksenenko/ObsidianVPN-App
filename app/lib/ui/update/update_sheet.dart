import 'dart:io' show Platform;

import 'package:flutter/material.dart' hide Durations;

import '../../app_version.dart';
import '../../core/update/update_checker.dart';
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
  return showAdaptiveSheet<void>(context, (sheetContext) {
    return UpdateSheet(
      release: release,
      currentVersion: kAppVersion,
      hasDownload: asset != null,
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
