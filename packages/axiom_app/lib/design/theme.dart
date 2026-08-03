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

ThemeData buildAxiomTheme({
  required Brightness brightness,
  AxiomScheme scheme_ = AxiomScheme.instrument,
}) {
  final p = scheme_.palette(brightness);

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
    // Durchgehend angehoben gegenueber der ersten Fassung. Die alten Grade
    // (Fliesstext 12,5 · Beschriftung 11) sahen als Screenshot praezise aus
    // und waren auf dem Geraet zu klein — und eine Zeile, die man
    // zusammenkneifen muss, wird uebersprungen. Wer es kompakter will,
    // stellt es unter System -> Anzeige zurueck.
    textTheme: TextTheme(
      displayLarge: sans(42, FontWeight.w300, height: 1.1, spacing: -0.8),
      displayMedium: sans(34, FontWeight.w300, height: 1.15, spacing: -0.5),
      headlineLarge: sans(27, FontWeight.w400, height: 1.2, spacing: -0.3),
      headlineMedium: sans(22, FontWeight.w500, height: 1.25),
      titleLarge: sans(18.5, FontWeight.w500, height: 1.3),
      titleMedium: sans(16.5, FontWeight.w500, height: 1.35),
      bodyLarge: sans(17, FontWeight.w400, height: 1.5, color: p.ink),
      bodyMedium: sans(15.5, FontWeight.w400, height: 1.5, color: p.inkDim),
      bodySmall: sans(14, FontWeight.w400, height: 1.5, color: p.inkDim),
      labelLarge: sans(15, FontWeight.w500, spacing: 0.2),
      labelMedium: sans(13.5, FontWeight.w500, spacing: 0.4),
      labelSmall: TextStyle(
        fontFamily: Fonts.mono,
        fontSize: 12.5,
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
      titleTextStyle: sans(19, FontWeight.w500),
      iconTheme: IconThemeData(color: p.inkDim, size: 24),
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
        textStyle: sans(17, FontWeight.w500),
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
        textStyle: sans(16, FontWeight.w400),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.inkDim,
        textStyle: sans(15.5, FontWeight.w400),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.panel,
      hintStyle: sans(17, FontWeight.w400, color: p.inkFaint),
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
      contentTextStyle: sans(15.5, FontWeight.w400),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.control),
        side: BorderSide(color: p.rule),
      ),
    ),

    // Schalter waren bisher ungestylt.
    //
    // Material 3 nimmt dann `outline` fuer den Knopf und
    // `surfaceContainerHighest` fuer die Bahn — in dieser Palette sind das
    // die Hairline-Farbe und ein dunkles Panel. Ergebnis: ein
    // anthrazitfarbener Knopf auf anthrazitfarbenem Grund, der aussieht wie
    // ein deaktiviertes Bedienelement und den man deshalb gar nicht erst
    // antippt. Ein Schalter muss aus zwei Metern erkennbar an oder aus sein.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return p.inkFaint;
        return states.contains(WidgetState.selected)
            ? scheme.onPrimary
            : p.inkDim;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return p.panel;
        return states.contains(WidgetState.selected) ? p.signal : p.base;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? p.signal : p.inkFaint),
      trackOutlineWidth: const WidgetStatePropertyAll(1.5),
    ),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? p.signal : Colors.transparent),
      checkColor: WidgetStatePropertyAll(scheme.onPrimary),
      side: BorderSide(color: p.inkFaint, width: 1.5),
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
      height: 70,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => sans(13, FontWeight.w500,
            color: states.contains(WidgetState.selected) ? p.ink : p.inkDim),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
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

/// Kleinste Schriftgroesse, die noch als Text gilt.
///
/// Darunter wird nichts mehr gelesen, es wird erkannt — und was nur erkannt
/// wird, traegt keine Information. Der Wert ist eine Untergrenze, kein
/// Vorschlag: `monoStyle` hebt jede kleinere Angabe darauf an.
const double kMinReadableSize = 12.5;

/// Monospace-Stil fuer Messwerte, IDs und Skalen.
TextStyle monoStyle(
  BuildContext context, {
  double size = 14,
  FontWeight weight = FontWeight.w400,
  Color? color,
  double spacing = 0.2,
}) =>
    TextStyle(
      fontFamily: Fonts.mono,
      fontSize: size < kMinReadableSize ? kMinReadableSize : size,
      fontWeight: weight,
      letterSpacing: spacing,
      color: color ?? AxiomTheme.of(context).inkDim,
    );
