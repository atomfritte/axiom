/// Theme-Aufbau und Zugriff auf die Palette.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Macht die Palette ueber den Widget-Baum verfuegbar.
@immutable
final class AxiomTheme extends ThemeExtension<AxiomTheme> {
  final AxiomPalette palette;
  const AxiomTheme(this.palette);

  static AxiomPalette of(BuildContext context) =>
      Theme.of(context).extension<AxiomTheme>()?.palette ?? AxiomPalette.dark;

  @override
  AxiomTheme copyWith({AxiomPalette? palette}) =>
      AxiomTheme(palette ?? this.palette);

  @override
  AxiomTheme lerp(ThemeExtension<AxiomTheme>? other, double t) =>
      t < 0.5 ? this : (other as AxiomTheme? ?? this);
}

/// Kurzform: `context.axiom.signal`
extension AxiomThemeContext on BuildContext {
  AxiomPalette get axiom => AxiomTheme.of(this);
}

ThemeData buildAxiomTheme({required Brightness brightness}) {
  final p = brightness == Brightness.dark
      ? AxiomPalette.dark
      : AxiomPalette.light;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.signal,
    onPrimary: brightness == Brightness.dark
        ? const Color(0xFF14100A)
        : const Color(0xFFFFFFFF),
    secondary: p.info,
    onSecondary: p.ink,
    error: p.caution, // bewusst Kupfer statt Rot
    onError: p.ink,
    surface: p.panel,
    onSurface: p.ink,
    surfaceContainerHighest: p.panelRaised,
    outline: p.rule,
    outlineVariant: p.rule,
  );

  TextStyle sans(double size, FontWeight weight,
          {double? height, double? spacing, Color? color}) =>
      TextStyle(
        fontFamily: Fonts.sans,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: spacing,
        color: color ?? p.ink,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.base,
    canvasColor: p.base,
    fontFamily: Fonts.sans,
    splashFactory: InkSparkle.splashFactory,
    extensions: [AxiomTheme(p)],

    // Typskala. Die grossen Grade sind LEICHT gesetzt (w300): Ein genervter
    // Nutzer soll gelesen, nicht angeschrien werden.
    textTheme: TextTheme(
      displayLarge: sans(40, FontWeight.w300, height: 1.1, spacing: -0.8),
      displayMedium: sans(32, FontWeight.w300, height: 1.15, spacing: -0.5),
      headlineLarge: sans(26, FontWeight.w400, height: 1.2, spacing: -0.3),
      headlineMedium: sans(21, FontWeight.w500, height: 1.25),
      titleLarge: sans(17, FontWeight.w500, height: 1.3),
      titleMedium: sans(15, FontWeight.w500, height: 1.35),
      bodyLarge: sans(16, FontWeight.w400, height: 1.5, color: p.ink),
      bodyMedium: sans(14, FontWeight.w400, height: 1.5, color: p.inkDim),
      bodySmall: sans(12.5, FontWeight.w400, height: 1.45, color: p.inkDim),
      labelLarge: sans(14, FontWeight.w500, spacing: 0.2),
      labelMedium: sans(12, FontWeight.w500, spacing: 0.4),
      labelSmall: TextStyle(
        fontFamily: Fonts.mono,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.8,
        color: p.inkFaint,
      ),
    ),

    dividerTheme: DividerThemeData(color: p.rule, thickness: 1, space: 1),

    appBarTheme: AppBarTheme(
      backgroundColor: p.base,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: sans(17, FontWeight.w500),
      iconTheme: IconThemeData(color: p.inkDim, size: 22),
    ),

    cardTheme: CardThemeData(
      color: p.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.panel),
        side: BorderSide(color: p.rule),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.signal,
        foregroundColor: scheme.onPrimary,
        minimumSize: const Size.fromHeight(52),
        padding: const EdgeInsets.symmetric(horizontal: Space.xl),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        textStyle: sans(16, FontWeight.w500),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        minimumSize: const Size.fromHeight(48),
        side: BorderSide(color: p.rule),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        textStyle: sans(15, FontWeight.w400),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.inkDim,
        textStyle: sans(14, FontWeight.w400),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.panel,
      hintStyle: sans(16, FontWeight.w400, color: p.inkFaint),
      contentPadding: const EdgeInsets.all(Space.lg),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.control),
        borderSide: BorderSide(color: p.rule),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.control),
        borderSide: BorderSide(color: p.rule),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.control),
        borderSide: BorderSide(color: p.signal, width: 1.5),
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.panelRaised,
      contentTextStyle: sans(14, FontWeight.w400),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.control),
        side: BorderSide(color: p.rule),
      ),
    ),

    sliderTheme: SliderThemeData(
      activeTrackColor: p.signal,
      inactiveTrackColor: p.rule,
      thumbColor: p.signal,
      overlayColor: p.signal.withValues(alpha: 0.12),
      trackHeight: 3,
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.panel,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.signal.withValues(alpha: 0.16),
      elevation: 0,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => sans(11.5, FontWeight.w500,
            color: states.contains(WidgetState.selected) ? p.ink : p.inkDim),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected) ? p.signal : p.inkDim,
        ),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: p.panelRaised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.panel),
        side: BorderSide(color: p.rule),
      ),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.panel,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.panel)),
      ),
    ),
  );
}

/// Monospace-Stil fuer Messwerte, IDs und Skalen.
TextStyle monoStyle(
  BuildContext context, {
  double size = 13,
  FontWeight weight = FontWeight.w400,
  Color? color,
  double spacing = 0.2,
}) =>
    TextStyle(
      fontFamily: Fonts.mono,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: spacing,
      color: color ?? AxiomTheme.of(context).inkDim,
    );
