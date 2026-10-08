import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../desktop/desktop_shell.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/theme.dart';

const double _titleBarHeight = 40;
const double _captionButtonWidth = 46;

/// Custom 40 px title area for Windows and Linux (the native frame is hidden).
class DesktopTitleBar extends StatelessWidget {
  const DesktopTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    final l10n = AppLocalizations.of(context);

    return SizedBox(
      height: _titleBarHeight,
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Padding(
                padding: const EdgeInsets.only(left: Space.s16),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    l10n.appTitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ),
          ),
          _CaptionButton(
            icon: Icons.remove_rounded,
            tooltip: l10n.windowMinimize,
            hoverColor: c.surfaceHi,
            onPressed: windowManager.minimize,
          ),
          _CaptionButton(
            icon: Icons.close_rounded,
            tooltip: l10n.windowClose,
            hoverColor: c.danger,
            onPressed: closeMainWindow,
          ),
        ],
      ),
    );
  }
}

class _CaptionButton extends StatelessWidget {
  const _CaptionButton({
    required this.icon,
    required this.tooltip,
    required this.hoverColor,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color hoverColor;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: _captionButtonWidth,
        height: _titleBarHeight,
        child: InkWell(
          onTap: () => onPressed(),
          hoverColor: hoverColor,
          mouseCursor: SystemMouseCursors.click,
          child: Icon(icon, size: 18, color: c.textDim),
        ),
      ),
    );
  }
}
