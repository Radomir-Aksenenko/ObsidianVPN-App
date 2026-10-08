import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/theme.dart';

/// Ping with a 6 px status dot: ok below 80 ms, warn below 160, danger above.
/// A null [ms] (no answer) shows the caption "нет ответа" and a faint dot.
class PingBadge extends StatelessWidget {
  const PingBadge(this.ms, {super.key});

  final int? ms;

  /// Dot colour for a measured [ms].
  static Color dotColor(ObsidianColors c, int ms) {
    if (ms < 80) return c.ok;
    if (ms < 160) return c.warn;
    return c.danger;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    final l10n = AppLocalizations.of(context);
    final value = ms;
    final dot = Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: value == null ? c.textFaint : dotColor(c, value),
        shape: BoxShape.circle,
      ),
    );
    final text = value == null
        ? Text(l10n.pingNoReply, style: Theme.of(context).textTheme.bodySmall)
        : Text(
            l10n.pingMs(value),
            style: obsidianMono(c, size: 12, color: c.text),
          );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(width: Space.s8),
        text,
      ],
    );
  }
}
