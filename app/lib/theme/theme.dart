import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'tokens.dart';

export 'tokens.dart';

/// Builds the Obsidian theme for one brightness. Ember is the primary colour.
ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final c = isDark ? ObsidianColors.dark : ObsidianColors.light;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.ember,
    onPrimary: c.onEmber,
    primaryContainer: c.emberSoft,
    onPrimaryContainer: c.ember,
    secondary: c.textDim,
    onSecondary: c.bg,
    secondaryContainer: c.surfaceHi,
    onSecondaryContainer: c.text,
    tertiary: c.ok,
    onTertiary: c.bg,
    error: c.danger,
    onError: c.bg,
    errorContainer: c.surfaceHi,
    onErrorContainer: c.danger,
    surface: c.bg,
    onSurface: c.text,
    onSurfaceVariant: c.textDim,
    surfaceContainerLowest: c.bg,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.surfaceHi,
    surfaceContainerHighest: c.surfaceHi,
    outline: c.line,
    outlineVariant: c.line,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: isDark ? ObsidianColors.light.bg : ObsidianColors.dark.bg,
    onInverseSurface: isDark ? ObsidianColors.light.text : ObsidianColors.dark.text,
    inversePrimary: c.ember,
    surfaceTint: Colors.transparent,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Manrope',
    textTheme: _textTheme(c),
    iconTheme: IconThemeData(color: c.textDim, size: 22),
    scaffoldBackgroundColor: c.bg,
    dividerColor: c.line,
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    hoverColor: c.surfaceHi,
    highlightColor: Colors.transparent,
    splashFactory: InkRipple.splashFactory,
    splashColor: c.text.withValues(alpha: 0.08),
    extensions: <ThemeExtension<dynamic>>[c],
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      modalBackgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sheet)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.surfaceHi,
      contentTextStyle: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: c.text,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.button)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.onEmber : c.textDim,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.ember : c.surfaceHi,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.transparent : c.line,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceHi,
      hintStyle: TextStyle(color: c.textFaint),
      labelStyle: TextStyle(color: c.textDim),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: _inputBorder(BorderSide.none),
      enabledBorder: _inputBorder(BorderSide.none),
      disabledBorder: _inputBorder(BorderSide.none),
      focusedBorder: _inputBorder(BorderSide(color: c.ember)),
      errorBorder: _inputBorder(BorderSide(color: c.danger)),
      focusedErrorBorder: _inputBorder(BorderSide(color: c.danger)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        elevation: const WidgetStatePropertyAll(0),
        minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? c.surfaceHi : c.ember,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? c.textFaint : c.onEmber,
        ),
        overlayColor: WidgetStatePropertyAll(c.onEmber.withValues(alpha: 0.08)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.button)),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontFamily: 'Manrope', fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(c.text),
        overlayColor: WidgetStatePropertyAll(c.text.withValues(alpha: 0.08)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.input)),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontFamily: 'Manrope', fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    ),
  );
}

OutlineInputBorder _inputBorder(BorderSide side) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(Radii.input),
    borderSide: side,
  );
}

/// Manrope type scale from DESIGN.md. Slots not listed keep Material 2021 defaults.
TextTheme _textTheme(ObsidianColors c) {
  final base = Typography.material2021().englishLike.apply(
        fontFamily: 'Manrope',
        bodyColor: c.text,
        displayColor: c.text,
      );

  TextStyle manrope(
    double size,
    FontWeight weight, {
    double? height,
    double? letterSpacing,
    Color? color,
    List<FontVariation>? variations,
  }) {
    return TextStyle(
      fontFamily: 'Manrope',
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      color: color ?? c.text,
      fontVariations: variations,
    );
  }

  return base.copyWith(
    // display: mono 34/600 for throughput values and the session timer.
    displayLarge: obsidianMono(c, size: 34, weight: FontWeight.w600, letterSpacing: -0.5),
    // title: 22/700 for screen titles.
    headlineSmall: manrope(22, FontWeight.w700, letterSpacing: -0.4),
    // heading: 17/650 for section heads and sheet titles.
    titleLarge: manrope(17, FontWeight.w600, variations: [FontVariation.weight(650)]),
    // body: 15/500, line height 1.4.
    bodyLarge: manrope(15, FontWeight.w500, height: 1.4),
    // label: 13/600 for buttons and small row titles.
    labelLarge: manrope(13, FontWeight.w600),
    // caption: 12/500, textDim, for hints.
    bodySmall: manrope(12, FontWeight.w500, color: c.textDim),
  );
}

/// Mono text for hosts, keys, logs and numbers. Uses tabular figures.
TextStyle obsidianMono(
  ObsidianColors c, {
  double size = 13,
  FontWeight weight = FontWeight.w500,
  double? letterSpacing,
  Color? color,
}) {
  return TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: size,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    color: color ?? c.text,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// Shortcut access to Obsidian tokens and styles: `context.obs.colors`, `context.obs.mono`.
extension ObsidianContext on BuildContext {
  ObsidianStyles get obs => ObsidianStyles(this);
}

class ObsidianStyles {
  const ObsidianStyles(this._context);

  final BuildContext _context;

  ObsidianColors get colors =>
      Theme.of(_context).extension<ObsidianColors>() ?? ObsidianColors.dark;

  /// Mono 13/500 (hosts, keys, log lines).
  TextStyle get mono => obsidianMono(colors);

  /// Mono 34/600 (throughput values, session timer).
  TextStyle get display => obsidianMono(
        colors,
        size: 34,
        weight: FontWeight.w600,
        letterSpacing: -0.5,
      );
}
