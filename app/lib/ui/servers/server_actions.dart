import 'package:flutter/material.dart' hide Durations;

import '../../core/models/profile.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../split/split_editor_screen.dart';
import '../widgets/widgets.dart';

enum _ServerAction { rename, favorite, split, delete }

/// Per-server actions sheet. The chosen action runs after the sheet closes.
Future<void> showServerActions(BuildContext context, ServerProfile profile) async {
  final action = await showAdaptiveSheet<_ServerAction>(context, (sheetContext) {
    final l10n = AppLocalizations.of(sheetContext);
    void pick(_ServerAction value) => Navigator.of(sheetContext).pop(value);
    return ObsSheet(
      title: profile.name,
      child: ObsGroup(
        children: [
          ObsRow(
            title: l10n.serversActionRename,
            onTap: () => pick(_ServerAction.rename),
          ),
          ObsRow(
            title: profile.isFavorite
                ? l10n.serversActionFavoriteRemove
                : l10n.serversActionFavoriteAdd,
            onTap: () => pick(_ServerAction.favorite),
          ),
          ObsRow(
            title: l10n.serversActionSplit,
            onTap: () => pick(_ServerAction.split),
          ),
          ObsRow(
            title: l10n.serversActionDelete,
            destructive: true,
            onTap: () => pick(_ServerAction.delete),
          ),
        ],
      ),
    );
  });
  if (action == null || !context.mounted) return;

  switch (action) {
    case _ServerAction.rename:
      await _rename(context, profile);
    case _ServerAction.favorite:
      await _toggleFavorite(context, profile);
    case _ServerAction.split:
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => SplitEditorScreen(profileId: profile.id),
        ),
      );
    case _ServerAction.delete:
      await _delete(context, profile);
  }
}

Future<void> _rename(BuildContext context, ServerProfile profile) async {
  final name = await showAdaptiveSheet<String>(
    context,
    (_) => _RenameSheet(initialName: profile.name),
  );
  if (name == null || !context.mounted) return;
  final l10n = AppLocalizations.of(context);
  await AppState.of(context).renameProfile(profile.id, name);
  if (!context.mounted) return;
  showObsToast(context, l10n.serversRenamed, kind: ObsToastKind.success);
}

Future<void> _toggleFavorite(BuildContext context, ServerProfile profile) async {
  final l10n = AppLocalizations.of(context);
  await AppState.of(context).toggleFavorite(profile.id);
  if (!context.mounted) return;
  showObsToast(
    context,
    profile.isFavorite
        ? l10n.serversFavoriteRemoved
        : l10n.serversFavoriteAdded,
    kind: ObsToastKind.success,
  );
}

Future<void> _delete(BuildContext context, ServerProfile profile) async {
  final l10n = AppLocalizations.of(context);
  final state = AppState.of(context);
  final blocked = state.connectedProfile?.id == profile.id ||
      (state.isBusy && state.selectedProfile?.id == profile.id);
  if (blocked) {
    showObsToast(context, l10n.serversDeleteBlocked, kind: ObsToastKind.error);
    return;
  }

  final confirmed = await showAdaptiveSheet<bool>(context, (sheetContext) {
    final l10n = AppLocalizations.of(sheetContext);
    final c = sheetContext.obs.colors;
    return ObsSheet(
      title: l10n.serversDeleteTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.serversDeleteBody,
            style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                  color: c.textDim,
                ),
          ),
          const SizedBox(height: Space.s16),
          ObsButton(
            label: l10n.serversDeleteConfirm,
            kind: ObsButtonKind.destructive,
            onPressed: () => Navigator.of(sheetContext).pop(true),
          ),
          const SizedBox(height: Space.s8),
          ObsButton(
            label: l10n.serversCancel,
            kind: ObsButtonKind.secondary,
            onPressed: () => Navigator.of(sheetContext).pop(false),
          ),
        ],
      ),
    );
  });
  if (confirmed != true || !context.mounted) return;

  await state.removeProfile(profile.id);
  if (!context.mounted) return;
  showObsToast(context, l10n.serversDeleted, kind: ObsToastKind.success);
}

/// Rename sheet. Pops with the trimmed name; empty names are not accepted.
class _RenameSheet extends StatefulWidget {
  const _RenameSheet({required this.initialName});

  final String initialName;

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _trimmed => _controller.text.trim();

  void _submit() {
    if (_trimmed.isEmpty) return;
    Navigator.of(context).pop(_trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ObsSheet(
      title: l10n.serversRenameTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ObsTextField(
            controller: _controller,
            label: l10n.serversNameLabel,
            hint: l10n.serversNameHint,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: Space.s16),
          ObsButton(
            label: l10n.serversSave,
            onPressed: _trimmed.isEmpty ? null : _submit,
          ),
        ],
      ),
    );
  }
}
