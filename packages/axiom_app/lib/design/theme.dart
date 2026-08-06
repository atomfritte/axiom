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

  /// Optische Laufweitenkorrektur fuer grosse Grade.
  ///
  /// Eine Schrift ist fuer Lesegroesse ausgeglichen. Ab etwa 20 px stehen
  /// dieselben Abstaende zu weit, die Zeile faellt auseinander. Die Faustzahl
  /// −0,028 × Groesse zieht sie wieder zusammen; sie ist der Grund, warum
  /// eine 42-px-Zeile in w600 kompakt wirkt statt breit.
  double optical(double size) => -0.028 * size;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.base,
    canvasColor: p.base,
    fontFamily: Fonts.sans,
    splashFactory: InkSparkle.splashFactory,
    extensions: [AxiomTheme(p)],

    // Typskala.
    //
    // Hier stand: „Die grossen Grade sind LEICHT gesetzt (w300): Ein
    // genervter Nutzer soll gelesen, nicht angeschrien werden." Die Absicht
    // war richtig, das Mittel falsch. w300 in 42 px sieht auf einem
    // Rechnerbildschirm elegant aus und auf einem Telefon duenn und blass —
    // vor allem auf dunklem Grund, wo helle Haarlinien optisch weiter
    // ausduennen. Was leise wirken sollte, wirkte kraftlos.
    //
    // Ersatz: **w600 mit optischer Laufweitenkorrektur** ([optical]). Ein
    // grosser Grad wird dadurch kompakt statt laut — Ruhe kommt aus
    // Enge und Groesse, nicht aus Duenne. Fliesstext bleibt w400.
    //
    // Durchgehend angehoben gegenueber der ersten Fassung. Die alten Grade
    // (Fliesstext 12,5 · Beschriftung 11) sahen als Screenshot praezise aus
    // und waren auf dem Geraet zu klein — und eine Zeile, die man
    // zusammenkneifen muss, wird uebersprungen. Wer es kompakter will,
    // stellt es unter System -> Anzeige zurueck.
    textTheme: TextTheme(
      displayLarge:
          sans(42, FontWeight.w600, height: 1.06, spacing: optical(42)),
      displayMedium:
          sans(34, FontWeight.w600, height: 1.1, spacing: optical(34)),
      headlineLarge:
          sans(27, FontWeight.w600, height: 1.18, spacing: optical(27)),
      headlineMedium:
          sans(22, FontWeight.w600, height: 1.25, spacing: optical(22)),
      titleLarge: sans(18.5, FontWeight.w600, height: 1.3, spacing: -0.3),
      titleMedium: sans(16.5, FontWeight.w500, height: 1.35, spacing: -0.15),
      bodyLarge: sans(17, FontWeight.w400, height: 1.5, color: p.ink),
      bodyMedium: sans(15.5, FontWeight.w400, height: 1.5, color: p.inkDim),
      bodySmall: sans(14, FontWeight.w400, height: 1.5, color: p.inkDim),
      labelLarge: sans(15, FontWeight.w500, spacing: 0.2),
      labelMedium: sans(13.5, FontWeight.w500, spacing: 0.4),

      // **Die Abschnittsmarke.** Hier stand Monospace in 12,5 px mit
      // `letterSpacing: 0.8` — und weil fast jede Marke am Aufrufort noch
      // `.toUpperCase()` bekam, las man ueberall gesperrte Versalien:
      // AKTIVIERUNGSENERGIE, KAPAZITAET, JETZT, ZUSTAND. Gesperrte Versalien
      // sind messbar langsamer zu lesen (die Wortform faellt weg, es bleibt
      // Buchstabe fuer Buchstabe) und tragen den Ton eines Beipackzettels.
      //
      // Jetzt: normale Schreibweise, Hausschrift, 13,5 px, w600, leicht
      // gesperrt. `SectionLabel` und `sectionStyle` setzen das durch;
      // `typography_test.dart` haelt fest, dass keine Versalienmarke
      // zurueckkommt.
      labelSmall: sans(13.5, FontWeight.w600, height: 1.3,
          spacing: 0.5, color: p.inkFaint),
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

    // Rahmen raus, Schatten rein. Ein Haarlinienrahmen um jede Flaeche
    // zeichnet ein Gitter ueber den Schirm; ein Schatten sagt dasselbe
    // (hier hoert die Flaeche auf) und sagt zusaetzlich, was oben liegt.
    cardTheme: CardThemeData(
      color: p.panel,
      surfaceTintColor: Colors.transparent,
      shadowColor: p.shade,
      elevation: p.isDark ? 0 : 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.panel),
        side: p.isDark ? BorderSide(color: p.rim) : BorderSide.none,
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

/// Monospace — **fuer die Regel-ID und fuer woertlich Abzutippendes.**
///
/// Hier stand „Monospace-Stil fuer Messwerte, IDs und Skalen", und die Folge
/// war messbar: 117 Aufrufe im Quelltext gegen sieben `RuleStamp`. Jede Zahl,
/// jede Uhrzeit, jede Beschriftung lief in Schreibmaschine — eine Oberflaeche
/// im Ton eines Terminalprotokolls, obwohl Mono nur eine einzige Eigenschaft
/// beitrug: gleich breite Ziffern.
///
/// **Wofuer es noch gedacht ist.** Zwei Faelle, und beide sind keine
/// Messwerte:
///
///  1. Die **Regel-ID** in `RuleStamp` (`R-050`). Sie ist damit das einzige
///     technisch gesetzte Element eines Schirms und deshalb sofort zu finden.
///     Genau das will G2: Die Regel soll auffallen, nicht mitlaufen.
///  2. **Woertlicher Text**, den jemand abtippt, kopiert oder Zeichen fuer
///     Zeichen vergleicht: Shell-Befehle, Dateipfade, YAML-Ausschnitte,
///     Fehlerausgaben. Dort traegt die feste Laufweite echte Information.
///
/// **Wofuer nicht.** Zahlen, Zeiten, Prozente, Skalen, Beschriftungen,
/// Plaketten, Herleitungen. Alles davon ist ein Messwert und gehoert in
/// [readingStyle] — Hausschrift mit Tabellenziffern, die genauso sauber
/// untereinander stehen.
///
/// `typography_test.dart` deckelt die Fundstellen je Datei; die Zahl darf
/// sinken und nicht steigen.
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

/// **Die Messwertrolle.** Hausschrift mit Tabellenziffern.
///
/// Jede Zahl der Oberflaeche laeuft hier durch: Kapazitaet, Uhrzeiten,
/// Minuten, Terme einer Herleitung, Zaehler in einer Abschnittsmarke.
/// `FontFeature.tabularFigures` gibt jeder Ziffer dieselbe Vorbreite —
/// 61 steht damit unter 88, ohne dass die Zeile nach Schreibmaschine
/// aussieht. Das war der einzige sachliche Grund fuer [monoStyle], und er
/// ist damit erledigt.
///
/// Die Farbe ist bewusst **nicht** vorbelegt mit einer Rollenfarbe je
/// Messwert: Wer hier nichts uebergibt, bekommt [AxiomPalette.ink]. Eine
/// Messung, die eine Farbe braucht, bekommt [AxiomPalette.signal] — und zwar
/// jede dieselbe. Drei Messwerte in drei Farben lesen sich als drei Urteile
/// (R7).
TextStyle readingStyle(
  BuildContext context, {
  double size = 15,
  FontWeight weight = FontWeight.w600,
  Color? color,
  double? spacing,
  double? height,
}) {
  final resolved = size < kMinReadableSize ? kMinReadableSize : size;
  return TextStyle(
    fontFamily: Fonts.sans,
    fontSize: resolved,
    fontWeight: weight,
    // Grosse Grade brauchen dieselbe optische Korrektur wie die Typskala,
    // sonst faellt eine 42er-Zahl auseinander.
    letterSpacing: spacing ?? (resolved >= 20 ? -0.028 * resolved : 0),
    height: height,
    fontFeatures: kTabularFigures,
    color: color ?? AxiomTheme.of(context).ink,
  );
}

/// **Die Abschnittsmarke.** Normale Schreibweise, keine gesperrten Versalien.
///
/// Dieselbe Rolle wie `textTheme.labelSmall`, nur direkt greifbar — der
/// Baustein dazu ist `SectionLabel`. Wer eine Marke von Hand setzt, nimmt
/// das hier und schreibt „Nicht in Reichweite", nicht
/// „NICHT IN REICHWEITE".
TextStyle sectionStyle(BuildContext context, {Color? color}) {
  final style = Theme.of(context).textTheme.labelSmall!;
  return color == null ? style : style.copyWith(color: color);
}
