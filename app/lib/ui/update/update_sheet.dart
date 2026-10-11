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
/// "Скачать" opens the installer for this platform in the browser (or the
/// release page when there is none). "Пропустить эту версию" saves the version
/// in settings, so the startup prompt stays quiet for it.
Future<void> showUpdateSheet(BuildContext context, AppRelease release) {
  final state = AppState.of(context);
  return showAdaptiveSheet<void>(context, (sheetContext) {
    return UpdateSheet(
      release: release,
      currentVersion: kAppVersion,
      onDownload: () {
        Navigator.of(sheetContext).pop();
        final url =
            pickAssetForPlatform(release, Platform.operatingSystem)?.url ??
            release.htmlUrl;
        openInBrowser(url);
        showObsToast(
          context,
          AppLocalizations.of(context).updateDownloadStarted,
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
    required this.onDownload,
    required this.onLater,
    required this.onSkip,
    required this.onOpenReleasePage,
  });

  /// The release on offer.
  final AppRelease release;

  /// Version of the running app.
  final String currentVersion;

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

    return ObsSheet(
      title: l10n.updateSheetTitle(release.version),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.updateSheetCurrent(currentVersion),
            style: theme.bodyMedium!.copyWith(color: c.textDim),
          ),
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
          ObsButton(label: l10n.updateDownload, onPressed: onDownload),
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
