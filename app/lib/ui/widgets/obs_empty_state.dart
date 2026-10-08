import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'obs_button.dart';

/// One sentence and one primary action, left aligned, no illustration.
class ObsEmptyState extends StatelessWidget {
  const ObsEmptyState({
    super.key,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge!.copyWith(color: c.textDim),
        ),
        if (actionLabel != null) ...[
          const SizedBox(height: Space.s16),
          ObsButton(label: actionLabel!, onPressed: onAction, expand: false),
        ],
      ],
    );
  }
}
