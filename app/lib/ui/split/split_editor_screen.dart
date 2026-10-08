import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart' hide Durations;

import '../../core/models/split_tunnel.dart';
import '../../l10n/app_localizations.dart';
import '../../platform_info.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../widgets/desktop_title_bar.dart';
import '../widgets/widgets.dart';

enum _LeaveChoice { save, discard, stay }

/// Split tunnel rules for one server. Changes are saved with [AppState.setSplit].
/// Leaving with unsaved changes asks first.
class SplitEditorScreen extends StatefulWidget {
  const SplitEditorScreen({super.key, required this.profileId});

  final String profileId;

  @override
  State<SplitEditorScreen> createState() => _SplitEditorScreenState();
}

class _SplitEditorScreenState extends State<SplitEditorScreen> {
  final TextEditingController _entries = TextEditingController();
  Timer? _debounce;
  bool _loaded = false;
  bool _missing = false;
  bool _allowPop = false;

  SplitMode _mode = SplitMode.off;
  Set<SplitPreset> _presets = <SplitPreset>{};
  List<SplitRule> _rules = const <SplitRule>[];
  List<SplitIssue> _issues = const <SplitIssue>[];

  // Last saved draft. The draft is dirty when it differs from this.
  SplitMode _savedMode = SplitMode.off;
  Set<SplitPreset> _savedPresets = <SplitPreset>{};
  String _savedText = '';

  bool get _dirty =>
      _mode != _savedMode ||
      !setEquals(_presets, _savedPresets) ||
      _entries.text != _savedText;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final profile = AppState.of(context).profileById(widget.profileId);
    if (profile == null) {
      _missing = true;
      return;
    }
    _mode = profile.split.mode;
    _presets = {...profile.split.presets};
    _savedMode = _mode;
    _savedPresets = {..._presets};
    _entries.text = profile.split.entries.join('\n');
    _savedText = _entries.text;
    _reparse();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _entries.dispose();
    super.dispose();
  }

  void _reparse() {
    final (rules, issues) = SplitRuleParser.parse(_entries.text);
    _rules = rules;
    _issues = issues;
  }

  void _onTextChanged(String _) {
    // The dirty flag and Save button update at once; parsing waits for a pause in typing.
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(_reparse);
    });
  }

  void _togglePreset(SplitPreset preset) {
    setState(() {
      final next = {..._presets};
      if (!next.remove(preset)) next.add(preset);
      _presets = next;
    });
  }

  void _markSaved() {
    setState(() {
      _savedMode = _mode;
      _savedPresets = {..._presets};
      _savedText = _entries.text;
    });
  }

  Future<void> _save() async {
    _debounce?.cancel();
    _reparse();
    final l10n = AppLocalizations.of(context);
    final state = AppState.of(context);
    final skipped = _issues.length;
    final split = SplitTunnelConfig(
      mode: _mode,
      entries: [for (final rule in _rules) rule.canonical],
      presets: _presets,
    );
    try {
      await state.setSplit(widget.profileId, split);
      if (!mounted) return;
      _markSaved();
      showObsToast(
        context,
        skipped == 0 ? l10n.splitSaved : l10n.splitSavedSkipped(skipped),
        kind: ObsToastKind.success,
      );
    } on AppStateException catch (e) {
      // The profile is stored even when the running tunnel could not be updated.
      if (!mounted) return;
      _markSaved();
      showObsToast(context, e.messageRu, kind: ObsToastKind.error);
    }
  }

  Future<void> _leave() async {
    final choice = await showAdaptiveSheet<_LeaveChoice>(context, (sheetContext) {
      final l10n = AppLocalizations.of(sheetContext);
      final c = sheetContext.obs.colors;
      return ObsSheet(
        title: l10n.splitUnsavedTitle,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.splitUnsavedBody,
              style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                    color: c.textDim,
                  ),
            ),
            const SizedBox(height: Space.s16),
            ObsButton(
              label: l10n.splitSave,
              onPressed: () => Navigator.of(sheetContext).pop(_LeaveChoice.save),
            ),
            const SizedBox(height: Space.s8),
            ObsButton(
              label: l10n.splitDiscard,
              kind: ObsButtonKind.destructive,
              onPressed: () =>
                  Navigator.of(sheetContext).pop(_LeaveChoice.discard),
            ),
            const SizedBox(height: Space.s8),
            ObsButton(
              label: l10n.splitKeepEditing,
              kind: ObsButtonKind.secondary,
              onPressed: () => Navigator.of(sheetContext).pop(_LeaveChoice.stay),
            ),
          ],
        ),
      );
    });
    if (!mounted) return;
    if (choice == _LeaveChoice.save) {
      await _save();
      if (!mounted || _dirty) return;
      Navigator.of(context).pop();
    } else if (choice == _LeaveChoice.discard) {
      setState(() => _allowPop = true);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.obs.colors;
    final theme = Theme.of(context);
    final gutter = Space.gutterNarrow;
    final dirty = _dirty;

    final Widget content;
    if (_missing) {
      content = Padding(
        padding: EdgeInsets.all(gutter),
        child: ObsEmptyState(text: l10n.splitMissing),
      );
    } else {
      final state = AppState.of(context);
      final connectedHere =
          state.isConnected && state.connectedProfile?.id == widget.profileId;
      final noEffective =
          _mode == SplitMode.include && _rules.isEmpty && _presets.isEmpty;
      final caption = theme.textTheme.bodySmall?.copyWith(color: c.textDim);

      content = Column(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(gutter, Space.s8, gutter, Space.s24),
                  children: [
                    ObsSegmented<SplitMode>(
                      options: [
                        ObsSegment(value: SplitMode.off, label: l10n.splitModeOff),
                        ObsSegment(
                          value: SplitMode.include,
                          label: l10n.splitModeInclude,
                        ),
                        ObsSegment(
                          value: SplitMode.exclude,
                          label: l10n.splitModeExclude,
                        ),
                      ],
                      value: _mode,
                      onChanged: (mode) => setState(() => _mode = mode),
                    ),
                    const SizedBox(height: Space.s8),
                    if (_mode == SplitMode.off)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.s8),
                        child: Text(l10n.splitOffNote, style: caption),
                      ),
                    if (noEffective) ...[
                      const SizedBox(height: Space.s12),
                      _WarningLine(text: l10n.splitEmptyWarning),
                    ],
                    const SizedBox(height: Space.s24),
                    ObsGroup(
                      label: l10n.splitPresets,
                      children: [
                        for (final preset in SplitPreset.values)
                          ObsRow(
                            title: preset.titleRu,
                            subtitle: l10n.splitPresetCount(preset.entries.length),
                            trailing: Switch.adaptive(
                              value: _presets.contains(preset),
                              onChanged: (_) => _togglePreset(preset),
                            ),
                            onTap: () => _togglePreset(preset),
                          ),
                      ],
                    ),
                    const SizedBox(height: Space.s24),
                    SectionLabel(l10n.splitEntries),
                    const SizedBox(height: Space.s8),
                    ObsTextField(
                      controller: _entries,
                      hint: l10n.splitEntriesHint,
                      mono: true,
                      minLines: 5,
                      maxLines: 10,
                      keyboardType: TextInputType.multiline,
                      onChanged: _onTextChanged,
                    ),
                    const SizedBox(height: Space.s8),
                    Text(
                      l10n.splitAccepted(_rules.length),
                      style: caption,
                    ),
                    if (_issues.isNotEmpty) ...[
                      const SizedBox(height: Space.s16),
                      ObsGroup(
                        label: l10n.splitIssues,
                        children: [
                          for (final issue in _issues)
                            ObsRow(
                              title: issue.input,
                              subtitle: issue.reasonRu,
                              subtitleMono: false,
                              destructive: true,
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: Space.s24),
                    Text(l10n.splitNoteDomains, style: caption),
                    const SizedBox(height: Space.s4),
                    Text(l10n.splitNoteWildcards, style: caption),
                    const SizedBox(height: Space.s4),
                    Text(l10n.splitNoteIdn, style: caption),
                  ],
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: c.bg,
              border: Border(top: BorderSide(color: c.line)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(gutter, Space.s12, gutter, Space.s12),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (connectedHere && dirty) ...[
                          Text(l10n.splitLiveNote, style: caption),
                          const SizedBox(height: Space.s8),
                        ],
                        ObsButton(
                          label: l10n.splitSave,
                          onPressed: dirty ? _save : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return PopScope(
      canPop: _allowPop || !dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (usesCustomTitleBar) const DesktopTitleBar(),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  Space.s8,
                  Space.s8,
                  gutter,
                  Space.s8,
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: l10n.sheetClose,
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: Space.s4),
                    Expanded(
                      child: Text(
                        l10n.splitTitle,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: content),
            ],
          ),
        ),
      ),
    );
  }
}

class _WarningLine extends StatelessWidget {
  const _WarningLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.warning_amber_rounded, size: 18, color: c.warn),
        const SizedBox(width: Space.s8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.warn),
          ),
        ),
      ],
    );
  }
}
