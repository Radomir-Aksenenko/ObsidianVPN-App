import 'package:flutter/material.dart' hide Durations;

import '../../theme/theme.dart';

/// Visual weight of an [ObsButton].
enum ObsButtonKind {
  /// Ember fill, dark text. One per screen or sheet.
  primary,

  /// surfaceHi fill, normal text.
  secondary,

  /// surfaceHi fill, danger text.
  destructive,
}

/// Button: height 48, radius 12, press scale 0.97, [loading] spinner (taps ignored).
/// Full width by default; set [expand] false for an inline button.
class ObsButton extends StatefulWidget {
  const ObsButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = ObsButtonKind.primary,
    this.loading = false,
    this.expand = true,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final ObsButtonKind kind;
  final bool loading;
  final bool expand;
  final IconData? icon;

  @override
  State<ObsButton> createState() => _ObsButtonState();
}

class _ObsButtonState extends State<ObsButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  void _setPressed(bool v) {
    if (_pressed != v && mounted) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    final disabled = widget.onPressed == null;
    final (Color bg, Color fg) = disabled
        ? (c.surfaceHi, c.textFaint)
        : switch (widget.kind) {
            ObsButtonKind.primary => (c.ember, c.onEmber),
            ObsButtonKind.secondary => (c.surfaceHi, c.text),
            ObsButtonKind.destructive => (c.surfaceHi, c.danger),
          };
    final noMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final labelStyle = Theme.of(
      context,
    ).textTheme.labelLarge!.copyWith(fontSize: 14, color: fg);

    final child = widget.loading
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 18, color: fg),
                const SizedBox(width: Space.s8),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  style: labelStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      excludeSemantics: true,
      child: AnimatedScale(
        scale: _pressed && _enabled ? 0.97 : 1,
        duration: noMotion ? Duration.zero : Durations.press,
        curve: Durations.curve,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(Radii.button),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _enabled ? widget.onPressed : null,
            onHighlightChanged: _setPressed,
            mouseCursor: _enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            splashColor: fg.withValues(alpha: 0.08),
            highlightColor: Colors.transparent,
            hoverColor: fg.withValues(alpha: 0.06),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: 48,
                minWidth: widget.expand ? double.infinity : 64,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.s20),
                child: Center(
                  widthFactor: widget.expand ? null : 1,
                  heightFactor: 1,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
