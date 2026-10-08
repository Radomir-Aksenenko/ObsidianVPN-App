import 'package:flutter/material.dart';

/// Colour tokens from app-docs/DESIGN.md. Dark is the default; light follows the system.
@immutable
class ObsidianColors extends ThemeExtension<ObsidianColors> {
  const ObsidianColors({
    required this.bg,
    required this.surface,
    required this.surfaceHi,
    required this.line,
    required this.text,
    required this.textDim,
    required this.textFaint,
    required this.ember,
    required this.emberSoft,
    required this.onEmber,
    required this.ok,
    required this.warn,
    required this.danger,
  });

  /// Dark glass: the default theme.
  static const dark = ObsidianColors(
    bg: Color(0xFF0B0C0E),
    surface: Color(0xFF131518),
    surfaceHi: Color(0xFF1A1D21),
    line: Color(0xFF26292E),
    text: Color(0xFFEDEEF0),
    textDim: Color(0xFF8B9099),
    textFaint: Color(0xFF5A5F68),
    ember: Color(0xFFFF6A2B),
    emberSoft: Color(0x24FF6A2B), // ember at 14%
    onEmber: Color(0xFF0B0C0E),
    ok: Color(0xFF46C78A),
    warn: Color(0xFFF5B83D),
    danger: Color(0xFFE5484D),
  );

  static const light = ObsidianColors(
    bg: Color(0xFFF4F3F0),
    surface: Color(0xFFFFFFFF),
    surfaceHi: Color(0xFFECEAE6),
    line: Color(0xFFDEDBD5),
    text: Color(0xFF141517),
    textDim: Color(0xFF5E6269),
    textFaint: Color(0xFF9A9DA3),
    ember: Color(0xFFE5531A),
    emberSoft: Color(0x1FE5531A), // ember at 12%
    onEmber: Color(0xFF0B0C0E),
    ok: Color(0xFF1F9D61),
    warn: Color(0xFFB7791F),
    danger: Color(0xFFCD2B31),
  );

  final Color bg;
  final Color surface;
  final Color surfaceHi;
  final Color line;
  final Color text;
  final Color textDim;
  final Color textFaint;
  final Color ember;
  final Color emberSoft;

  /// Text and icons drawn on top of ember fills (primary buttons).
  final Color onEmber;
  final Color ok;
  final Color warn;
  final Color danger;

  @override
  ObsidianColors copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceHi,
    Color? line,
    Color? text,
    Color? textDim,
    Color? textFaint,
    Color? ember,
    Color? emberSoft,
    Color? onEmber,
    Color? ok,
    Color? warn,
    Color? danger,
  }) {
    return ObsidianColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceHi: surfaceHi ?? this.surfaceHi,
      line: line ?? this.line,
      text: text ?? this.text,
      textDim: textDim ?? this.textDim,
      textFaint: textFaint ?? this.textFaint,
      ember: ember ?? this.ember,
      emberSoft: emberSoft ?? this.emberSoft,
      onEmber: onEmber ?? this.onEmber,
      ok: ok ?? this.ok,
      warn: warn ?? this.warn,
      danger: danger ?? this.danger,
    );
  }

  @override
  ObsidianColors lerp(ThemeExtension<ObsidianColors>? other, double t) {
    if (other is! ObsidianColors) return this;
    return ObsidianColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHi: Color.lerp(surfaceHi, other.surfaceHi, t)!,
      line: Color.lerp(line, other.line, t)!,
      text: Color.lerp(text, other.text, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      ember: Color.lerp(ember, other.ember, t)!,
      emberSoft: Color.lerp(emberSoft, other.emberSoft, t)!,
      onEmber: Color.lerp(onEmber, other.onEmber, t)!,
      ok: Color.lerp(ok, other.ok, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

/// 4 pt grid. Screen gutter is 20 on narrow layouts and 24 on wide ones.
class Space {
  const Space._();

  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s48 = 48;

  static const double gutterNarrow = s20;
  static const double gutterWide = s24;
}

/// Corner radii. The dial is a circle and does not use these.
class Radii {
  const Radii._();

  static const double input = 10;
  static const double chip = 10;
  static const double button = 12;
  static const double row = 16;
  static const double group = 16;
  static const double sheet = 24;
}

/// Motion timings. Animations run only on state change. Respect MediaQuery.disableAnimations.
class Durations {
  const Durations._();

  static const Duration press = Duration(milliseconds: 120);
  static const Duration stateChange = Duration(milliseconds: 220);
  static const Duration sheet = Duration(milliseconds: 320);
  static const Curve curve = Curves.easeOutCubic;
}
