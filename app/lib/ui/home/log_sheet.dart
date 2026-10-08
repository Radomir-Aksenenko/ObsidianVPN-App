import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/theme.dart';
import '../widgets/widgets.dart';

/// Lines shown in the log sheet.
const int kLogSheetLines = 500;

/// Opens the log sheet. It shows the last [kLogSheetLines] lines of [logs] and
/// updates while it is open.
Future<void> showLogSheet(
  BuildContext context,
  ValueListenable<List<String>> logs,
) {
  return showAdaptiveSheet<void>(context, (_) => _LogSheet(logs: logs));
}

class _LogSheet extends StatefulWidget {
  const _LogSheet({required this.logs});

  final ValueListenable<List<String>> logs;

  @override
  State<_LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends State<_LogSheet> {
  bool _copied = false;

  Future<void> _copy(List<String> lines) async {
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: widget.logs,
      builder: (context, all, _) {
        final lines = all.length > kLogSheetLines
            ? all.sublist(all.length - kLogSheetLines)
            : all;
        return _buildSheet(context, lines);
      },
    );
  }

  Widget _buildSheet(BuildContext context, List<String> lines) {
    final l10n = AppLocalizations.of(context);
    final c = context.obs.colors;
    final height = MediaQuery.sizeOf(context).height;

    return ObsSheet(
      title: l10n.logsTitle,
      action: lines.isEmpty
          ? null
          : TextButton.icon(
              onPressed: () => _copy(lines),
              icon: Icon(
                _copied ? Icons.check_rounded : Icons.copy_rounded,
                size: 16,
                color: _copied ? c.ok : c.textDim,
              ),
              label: Text(_copied ? l10n.logsCopied : l10n.logsCopyAll),
            ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height * 0.6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(Radii.input),
            border: Border.all(color: c.line),
          ),
          child: lines.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(Space.s16),
                  child: Text(
                    l10n.logsEmpty,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : SelectionArea(
                  child: ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(Space.s12),
                    itemCount: lines.length,
                    itemBuilder: (_, i) => Text(
                      lines[lines.length - 1 - i],
                      style: obsidianMono(
                        c,
                        size: 12,
                        color: c.textDim,
                      ).copyWith(height: 1.5),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
