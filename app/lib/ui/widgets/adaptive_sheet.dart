import 'package:flutter/material.dart' hide Durations;

import '../../l10n/app_localizations.dart';
import '../../theme/theme.dart';

/// Width from which sheets become centered dialogs.
const double kAdaptiveSheetBreakpoint = 720;

/// Max width of the centered dialog variant.
const double kAdaptiveSheetMaxWidth = 480;

/// Bottom sheet on narrow windows, centered dialog (max 480) on wide ones. Radius 24.
/// Put an [ObsSheet] (or any widget) in [builder].
Future<T?> showAdaptiveSheet<T>(BuildContext context, WidgetBuilder builder) {
  final wide = MediaQuery.sizeOf(context).width >= kAdaptiveSheetBreakpoint;
  final noMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  if (wide) {
    return showDialog<T>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(Space.s24),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.sheet),
          side: BorderSide(color: ctx.obs.colors.line),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kAdaptiveSheetMaxWidth),
          child: builder(ctx),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    barrierColor: Colors.black54,
    elevation: 0,
    sheetAnimationStyle: AnimationStyle(
      duration: noMotion ? Duration.zero : Durations.sheet,
      reverseDuration: noMotion ? Duration.zero : Durations.stateChange,
      curve: Durations.curve,
    ),
    builder: builder,
  );
}

/// Standard sheet body: drag handle (narrow only), [title] in heading style, an
/// optional [action] on the right (a close button on wide layouts), then [child].
class ObsSheet extends StatelessWidget {
  const ObsSheet({super.key, this.title, this.action, required this.child});

  final String? title;
  final Widget? action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    final wide = MediaQuery.sizeOf(context).width >= kAdaptiveSheetBreakpoint;
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.s20,
          Space.s12,
          Space.s20,
          Space.s20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!wide)
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: Space.s12),
                  decoration: BoxDecoration(
                    color: c.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              )
            else
              const SizedBox(height: Space.s8),
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.s12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title!,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    action ??
                        (wide
                            ? IconButton(
                                tooltip: l10n.sheetClose,
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                                icon: const Icon(Icons.close_rounded, size: 20),
                              )
                            : const SizedBox.shrink()),
                  ],
                ),
              ),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}
