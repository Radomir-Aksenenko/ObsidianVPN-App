import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// The app's switch. ON: ember track with a light thumb. OFF: surfaceHi track with a
/// textDim thumb. Colours are passed explicitly because on iOS and macOS
/// `Switch.adaptive` ignores the app's SwitchTheme.
class ObsSwitch extends StatelessWidget {
  const ObsSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    final thumbOn = obsSwitchThumbOn(c, Theme.of(context).brightness);
    return Switch.adaptive(
      value: value,
      onChanged: onChanged,
      activeTrackColor: c.ember,
      activeThumbColor: thumbOn,
      inactiveTrackColor: c.surfaceHi,
      inactiveThumbColor: c.textDim,
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.transparent : c.line,
      ),
    );
  }
}
