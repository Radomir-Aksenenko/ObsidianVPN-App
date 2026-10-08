import 'package:flutter/material.dart' hide Durations;

import '../../theme/theme.dart';

/// Scaffold of a bottom-bar tab: a title, scrolling sections, and an optional fixed
/// [footer] (primary actions). Sections are separated by 24 px. The horizontal gutter
/// (20 narrow, 24 wide) comes from the shell, so this widget adds none.
class TabPage extends StatelessWidget {
  const TabPage({
    super.key,
    required this.title,
    required this.children,
    this.footer,
  });

  final String title;
  final List<Widget> children;

  /// Pinned under the scrolling sections, 12 px above it.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) sections.add(const SizedBox(height: Space.s24));
      sections.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Space.s24, bottom: Space.s16),
          child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: Space.s16),
            children: sections,
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.s12, bottom: Space.s16),
            child: footer,
          ),
      ],
    );
  }
}
