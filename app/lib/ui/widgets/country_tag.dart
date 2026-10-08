import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Two-letter country code in a square mono box (32 px by default).
class CountryTag extends StatelessWidget {
  const CountryTag(this.code, {super.key, this.size = 32});

  final String code;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.obs.colors;
    final text = code.trim().isEmpty ? '??' : code.trim().toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surfaceHi,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          maxLines: 1,
          style: obsidianMono(
            c,
            size: 12,
            weight: FontWeight.w600,
            color: c.textDim,
          ),
        ),
      ),
    );
  }
}
