import 'dart:async';

import 'package:flutter/material.dart' hide Durations;
import 'package:flutter/services.dart';

import '../../core/codec/obsidian_key.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../widgets/widgets.dart';

/// Opens the add-key sheet. [initialText] prefills the key field (clipboard, QR).
/// Success shows a toast on [context] (the host screen), closes the sheet and selects the server.
Future<void> showAddKeySheet(BuildContext context, {String? initialText}) {
  return showAdaptiveSheet<void>(
    context,
    (_) => _AddKeySheet(hostContext: context, initialText: initialText),
  );
}

class _AddKeySheet extends StatefulWidget {
  const _AddKeySheet({required this.hostContext, this.initialText});

  final BuildContext hostContext;
  final String? initialText;

  @override
  State<_AddKeySheet> createState() => _AddKeySheetState();
}

class _AddKeySheetState extends State<_AddKeySheet> {
  late final TextEditingController _key =
      TextEditingController(text: widget.initialText ?? '');
  final TextEditingController _name = TextEditingController();
  Timer? _debounce;

  /// "host:port" of the recognized key, or null.
  String? _recognized;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _parse(_key.text);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _key.dispose();
    _name.dispose();
    super.dispose();
  }

  /// Parses [text] into [_recognized] or [_error]. Does not call setState.
  void _parse(String text) {
    final trimmed = text.trim();
    _recognized = null;
    _error = null;
    if (trimmed.isEmpty) return;
    try {
      _recognized = keyPreview(parseKey(trimmed));
    } on KeyFormatException catch (e) {
      _error = e.messageRu;
    }
  }

  void _onKeyChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() => _parse(text));
    });
  }

  Future<void> _paste() async {
    final l10n = AppLocalizations.of(context);
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      showObsToast(context, l10n.serversClipboardEmpty);
      return;
    }
    _debounce?.cancel();
    _key.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() => _parse(text));
  }

  Future<void> _submit() async {
    if (_saving || _recognized == null) return;
    final l10n = AppLocalizations.of(context);
    final state = AppState.of(context);
    final navigator = Navigator.of(context);
    final host = widget.hostContext;
    setState(() => _saving = true);
    try {
      final profile = await state.addKey(_key.text, name: _name.text);
      await state.selectProfile(profile.id);
      navigator.pop();
      if (host.mounted) {
        showObsToast(host, l10n.serversAdded, kind: ObsToastKind.success);
      }
    } on KeyFormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _recognized = null;
        _error = e.messageRu;
      });
    } catch (_) {
      // Storage or backend failure: the sheet stays open so the user can retry.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = l10n.serversAddFailed;
      });
    }
  }

  Widget _preview(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.obs.colors;
    if (_error != null) {
      return Text(
        _error!,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.danger),
      );
    }
    if (_recognized != null) {
      return Text(
        l10n.addKeyRecognized(_recognized!),
        style: context.obs.mono.copyWith(color: c.ok),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canSubmit = _recognized != null && !_saving;
    return ObsSheet(
      title: l10n.addKeyTitle,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ObsTextField(
              controller: _key,
              label: l10n.addKeyField,
              hint: l10n.addKeyFieldHint,
              mono: true,
              minLines: 3,
              maxLines: 6,
              autofocus: widget.initialText == null,
              keyboardType: TextInputType.multiline,
              onChanged: _onKeyChanged,
            ),
            const SizedBox(height: Space.s8),
            Row(
              children: [
                Expanded(child: _preview(context)),
                const SizedBox(width: Space.s8),
                ObsButton(
                  label: l10n.addKeyPaste,
                  kind: ObsButtonKind.secondary,
                  expand: false,
                  icon: Icons.content_paste_rounded,
                  onPressed: _paste,
                ),
              ],
            ),
            const SizedBox(height: Space.s16),
            ObsTextField(
              controller: _name,
              label: l10n.addKeyNameField,
              hint: l10n.addKeyNameHint,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: Space.s16),
            ObsButton(
              label: l10n.addKeySubmit,
              loading: _saving,
              onPressed: canSubmit ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }
}
