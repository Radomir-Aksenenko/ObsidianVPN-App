import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Tone of a toast: the colour of the 6 px dot before the text.
enum ObsToastKind { info, success, error }

/// Bottom toast: surfaceHi, one line, 2.2 s. Replaces a toast that is still showing.
void showObsToast(
  BuildContext context,
  String text, {
  ObsToastKind kind = ObsToastKind.info,
}) {
  final c = context.obs.colors;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final dot = switch (kind) {
    ObsToastKind.info => c.textFaint,
    ObsToastKind.success => c.ok,
    ObsToastKind.error => c.danger,
  };
  final width = (MediaQuery.sizeOf(context).width - Space.s32).clamp(
    200.0,
    420.0,
  );
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 2200),
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.surfaceHi,
        elevation: 0,
        width: width,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s16,
          vertical: Space.s12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.button),
          side: BorderSide(color: c.line),
        ),
        content: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: Space.s12),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge!.copyWith(color: c.text),
              ),
            ),
          ],
        ),
      ),
    );
}
