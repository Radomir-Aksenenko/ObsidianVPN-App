import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// One row of an [ObsGroup]: [leading], [title], [subtitle], [trailing]. Min height
/// 56. With [onTap] it gets hover and pressed states (surfaceHi) and a click cursor.
/// [selected] tints the row with emberSoft. [destructive] paints the title in danger.
class ObsRow extends StatelessWidget {
  const ObsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleMono = false,
    this.leading,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.destructive = false,
    this.semanticLabel,
  });

  final String title;
  final String? subtitle;

  /// Set the subtitle in JetBrains Mono (hosts, keys).
  final bool subtitleMono;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final bool destructive;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    final theme = Theme.of(context).textTheme;
    final titleStyle = theme.bodyLarge!.copyWith(
      fontSize: 15,
      height: 1.25,
      color: destructive ? c.danger : c.text,
    );
    final subStyle = subtitleMono
        ? obsidianMono(c, size: 12, color: c.textDim)
        : theme.bodySmall!.copyWith(color: c.textDim);

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s16,
          vertical: Space.s8,
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: Space.s12),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: titleStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: subStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: Space.s12),
              trailing!,
            ],
          ],
        ),
      ),
    );

    final tinted = selected
        ? ColoredBox(color: c.emberSoft, child: content)
        : content;
    if (onTap == null) return tinted;

    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          mouseCursor: SystemMouseCursors.click,
          hoverColor: c.surfaceHi,
          highlightColor: c.surfaceHi,
          splashColor: c.text.withValues(alpha: 0.08),
          child: tinted,
        ),
      ),
    );
  }
}
