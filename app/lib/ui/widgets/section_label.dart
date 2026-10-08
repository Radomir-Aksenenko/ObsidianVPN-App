import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Caption above a group: textDim, sentence case, 8 px gap to the group below.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: Space.s4, bottom: Space.s8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: context.obs.colors.textDim,
        ),
      ),
    );
  }
}
