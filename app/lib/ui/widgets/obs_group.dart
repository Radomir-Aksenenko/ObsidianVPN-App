import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'section_label.dart';

/// Grouped rows on `surface`: radius 16, 1 px border, hairline separators between
/// children, optional [label] above. Fill it with [ObsRow]s or any widgets.
class ObsGroup extends StatelessWidget {
  const ObsGroup({super.key, required this.children, this.label});

  final List<Widget> children;

  /// Section label drawn 8 px above the group.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) items.add(Divider(height: 1, thickness: 1, color: c.line));
      items.add(children[i]);
    }
    final group = Material(
      color: c.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.group),
        side: BorderSide(color: c.line),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: items),
    );
    if (label == null) return group;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [SectionLabel(label!), group],
    );
  }
}
