import 'package:flutter/material.dart' hide Durations;
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../platform_info.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../widgets/desktop_title_bar.dart';
import '../widgets/widgets.dart';

/// Full connection log, opened from Settings. Mono 12, selectable lines, copy and clear.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  /// Distance from the bottom that still counts as "at the bottom".
  static const double _bottomSlack = 24;

  final ScrollController _scroll = ScrollController();
  bool _atBottom = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    _atBottom = position.pixels >= position.maxScrollExtent - _bottomSlack;
  }

  /// Keeps the newest line in view, but only when the reader was already at the bottom.
  /// Content growth does not fire scroll events, so [_atBottom] keeps its last value.
  void _followBottom() {
    if (!mounted || !_atBottom || !_scroll.hasClients) return;
    final target = _scroll.position.maxScrollExtent;
    if (_scroll.position.pixels != target) _scroll.jumpTo(target);
  }

  Future<void> _copyAll(BuildContext context, List<String> lines) async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (context.mounted) {
      showObsToast(context, l10n.logsCopied, kind: ObsToastKind.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppState.of(context);
    // Only this screen rebuilds on new log lines, not the whole app.
    return ValueListenableBuilder<List<String>>(
      valueListenable: state.logsListenable,
      builder: (context, lines, _) => _buildScreen(context, state, lines),
    );
  }

  Widget _buildScreen(BuildContext context, AppState state, List<String> lines) {
    final l10n = AppLocalizations.of(context);
    final c = context.obs.colors;
    final gutter = MediaQuery.sizeOf(context).width >= 720
        ? Space.gutterWide
        : Space.gutterNarrow;

    WidgetsBinding.instance.addPostFrameCallback((_) => _followBottom());

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (usesCustomTitleBar) const DesktopTitleBar(),
            Padding(
              padding: EdgeInsets.fromLTRB(
                gutter - Space.s12,
                Space.s8,
                gutter,
                Space.s16,
              ),
              child: Row(
                children: [
                  if (Navigator.of(context).canPop())
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(Icons.arrow_back_rounded, color: c.textDim),
                    ),
                  Expanded(
                    child: Text(
                      l10n.logsTitle,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(Radii.group),
                    border: Border.all(color: c.line),
                  ),
                  child: lines.isEmpty
                      ? Center(
                          child: Text(
                            l10n.logsEmpty,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.group),
                          child: ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.all(Space.s12),
                            itemCount: lines.length,
                            itemBuilder: (context, index) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: SelectableText(
                                lines[index],
                                style: context.obs.mono.copyWith(
                                  fontSize: 12,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                gutter,
                Space.s12,
                gutter,
                Space.s16,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ObsButton(
                      label: l10n.logsCopyAll,
                      kind: ObsButtonKind.secondary,
                      onPressed: lines.isEmpty
                          ? null
                          : () => _copyAll(context, lines),
                    ),
                  ),
                  const SizedBox(width: Space.s12),
                  Expanded(
                    child: ObsButton(
                      label: l10n.logsClear,
                      kind: ObsButtonKind.secondary,
                      onPressed: lines.isEmpty ? null : state.clearLogs,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
