import 'package:flutter/material.dart' hide Durations;

import '../../theme/theme.dart';

/// One choice of an [ObsSegmented].
class ObsSegment<T> {
  const ObsSegment({required this.value, required this.label});

  final T value;
  final String label;
}

/// Two or three mutually exclusive options on a surfaceHi track. The selected
/// option sits on `bg` with a hairline; the change animates in 220 ms.
class ObsSegmented<T> extends StatelessWidget {
  const ObsSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  }) : assert(
         options.length >= 2 && options.length <= 3,
         'ObsSegmented takes 2 or 3 options',
       );

  final List<ObsSegment<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    final noMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration = noMotion ? Duration.zero : Durations.stateChange;
    final label = Theme.of(context).textTheme.labelLarge!;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surfaceHi,
        borderRadius: BorderRadius.circular(Radii.input + 3),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: option.value == value,
                label: option.label,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(option.value),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: AnimatedContainer(
                      duration: duration,
                      curve: Durations.curve,
                      height: 38,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: Space.s8),
                      decoration: BoxDecoration(
                        color: option.value == value
                            ? c.bg
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(Radii.input),
                        border: Border.all(
                          color: option.value == value
                              ? c.line
                              : Colors.transparent,
                        ),
                      ),
                      child: AnimatedDefaultTextStyle(
                        duration: duration,
                        style: label.copyWith(
                          color: option.value == value ? c.text : c.textDim,
                        ),
                        child: Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
