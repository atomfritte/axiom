/// Design-Tokens.
///
/// Gestaltungsleitbild: **Instrumententafel**, nicht Produktivitaets-App.
/// Die Welt eines Systemizers sind Messgeraete, Frontplatten, Skalen und
/// Telemetrie — keine bunten Karten mit Konfetti.
///
/// Zwei Entscheidungen, die aus dem Nutzerprofil folgen und nicht verhandelbar
/// sind:
///
///  1. **Kein Rot.** Rot heisst Fehler heisst Schuld. Bei Rejection
///     Sensitivity (D10) ist das die teuerste Farbe im Spektrum. Warnungen
///     sind Kupfer, Grenzwerte sind Bernstein. Selbst der Erhaltungsmodus
///     (L3) ist kein Alarm — er ist ein Erfolg des Systems.
///
///  2. **Warmes Anthrazit statt Reinschwarz, Bernstein statt Neon.**
///     Die Palette ist einem Phosphor-Instrument nachempfunden: gedaempft,
///     augenschonend, abends nicht wachhaltend (D8). Ein grelles Interface
///     um 23 Uhr arbeitet gegen das Sleep Gate.
library;

import 'package:flutter/material.dart';

/// Semantische Farbrollen. Jede Rolle hat eine dunkle und eine helle Fassung.
///
/// **Kontrast ist hier eine Zusage, keine Absicht.** Jede Rolle, die als Text
/// erscheint — [ink], [inkDim], [inkFaint], [signal], [calm], [caution],
/// [info] —, erreicht auf [base], [panel] und [panelRaised] mindestens
/// 4,5:1 (WCAG 2.x AA fuer Fliesstext). Das ist keine Formalie: Die kleinste
/// Schriftgroesse der App liegt bei 12,5 px, damit greift keine
/// Large-Text-Ausnahme, und was nicht gelesen wird, existiert fuer dieses
/// Profil nicht [D9].
///
/// Nachgerechnet wird das von `test/contrast_test.dart` — fuer alle vier
/// Schemata in beiden Helligkeiten. Vorher prueften die Tests genau eine der
/// acht Paletten, und dabei war der Tertiaertext der Werkbank bei 2,96:1
/// gelandet: unterhalb sogar der 3:1-Grenze, die fuer reine Grafik gilt.
@immutable
final class AxiomPalette {
  /// Seitenhintergrund.
  final Color base;

  /// Flaeche einer Karte — die "Frontplatte".
  final Color panel;

  /// Erhoehte Flaeche (Dialog, aktive Karte).
  final Color panelRaised;

  /// Hairlines, Skalenstriche, Rahmen.
  final Color rule;

  /// Primaertext.
  final Color ink;

  /// Sekundaertext, Beschriftungen.
  final Color inkDim;

  /// Tertiaer — Skalenzahlen, Fussnoten.
  final Color inkFaint;

  /// Signalfarbe. Das Jetzt, das Primaere, die Kapazitaetslinie.
  final Color signal;

  /// Gedrueckter/aktiver Zustand der Signalfarbe.
  final Color signalDeep;

  /// Im Normalbereich, ruhig, erledigt.
  final Color calm;

  /// Aufmerksamkeit — nie Alarm, nie Schuld.
  final Color caution;

  /// Struktur, Metadaten, Information.
  final Color info;

  const AxiomPalette({
    required this.base,
    required this.panel,
    required this.panelRaised,
    required this.rule,
    required this.ink,
    required this.inkDim,
    required this.inkFaint,
    required this.signal,
    required this.signalDeep,
    required this.calm,
    required this.caution,
    required this.info,
  });

  /// Dunkel — der Standard. Nachts nutzbar, ohne wachzuhalten.
  static const dark = AxiomPalette(
    base: Color(0xFF0E1113),
    panel: Color(0xFF171B1E),
    panelRaised: Color(0xFF1F2529),
    rule: Color(0xFF2A3237),
    ink: Color(0xFFECEAE4),
    // Tertiaertext lag bei etwa 4,0:1 — an der Grenze und bei Muedigkeit
    // darunter. Skalenzahlen und Fussnoten muessen ablesbar sein, sonst
    // sind sie Dekoration.
    inkDim: Color(0xFF9BA4AB),
    // #7A848B lag auf `panelRaised` (Dialog, SnackBar) bei 4,06:1 und
    // Kupfer #C4653A bei 3,89:1 — beides unter AA. Beide sind minimal
    // aufgehellt, der Farbton bleibt.
    inkFaint: Color(0xFF838D93),
    signal: Color(0xFFE8A33D),
    signalDeep: Color(0xFFB8761F),
    calm: Color(0xFF7FA88A),
    caution: Color(0xFFCB754E),
    info: Color(0xFF6E90A4),
  );

  /// Hell — fuer Tageslicht draussen. Dieselbe Instrumenten-Logik,
  /// Bernstein wird abgedunkelt, damit er auf Weiss noch traegt.
  static const light = AxiomPalette(
    base: Color(0xFFF2F1ED),
    panel: Color(0xFFFFFFFF),
    panelRaised: Color(0xFFFAF9F6),
    rule: Color(0xFFCFCCC4),
    ink: Color(0xFF15181B),
    // Angehoben gegenueber der ersten Fassung: #5C666D/#8F979D lagen bei
    // etwa 4,5:1 und 3,0:1. Der zweite Wert war auf einem hellen
    // Hintergrund schlicht nicht mehr zuverlaessig lesbar.
    inkDim: Color(0xFF4A545B),
    // Zweiter Nachzug: #6E767C lag auf `base` bei 4,09:1, Bernstein #9A6510
    // bei 4,38:1. Beides sah als Screenshot in Ordnung aus und war es nicht.
    inkFaint: Color(0xFF676E74),
    signal: Color(0xFF966210),
    signalDeep: Color(0xFF7A4E08),
    calm: Color(0xFF3F6B4F),
    caution: Color(0xFF9C4522),
    info: Color(0xFF3E6072),
  );

  /// Hochkontrast — dieselbe Instrumenten-Logik, aufgedreht.
  ///
  /// Nicht "haesslicher, dafuer lesbar": Die Farbrollen bleiben, nur der
  /// Abstand zwischen Papier und Text waechst. Sekundaertext liegt hier
  /// ueber 7:1, Tertiaertext ueber 5:1 — auch bei Sonne auf dem Display
  /// und auch, wenn die Augen muede sind.
  static const darkContrast = AxiomPalette(
    base: Color(0xFF0A0C0E),
    panel: Color(0xFF15191C),
    panelRaised: Color(0xFF1E2428),
    rule: Color(0xFF3D474D),
    ink: Color(0xFFF5F3EE),
    inkDim: Color(0xFFC2C9CE),
    inkFaint: Color(0xFF9BA5AC),
    signal: Color(0xFFFFBB55),
    signalDeep: Color(0xFFD08A28),
    calm: Color(0xFF9CC7A6),
    caution: Color(0xFFE08356),
    info: Color(0xFF8FB3C7),
  );

  static const lightContrast = AxiomPalette(
    base: Color(0xFFFAFAF8),
    panel: Color(0xFFFFFFFF),
    panelRaised: Color(0xFFF2F1ED),
    rule: Color(0xFFB4B0A7),
    ink: Color(0xFF0D1012),
    inkDim: Color(0xFF3B4248),
    inkFaint: Color(0xFF5C666D),
    signal: Color(0xFF7A4E08),
    signalDeep: Color(0xFF5C3A05),
    calm: Color(0xFF2E5239),
    caution: Color(0xFF7C3316),
    info: Color(0xFF2B4757),
  );

  /// Gedaempft — fuer den Abend.
  ///
  /// Ein grelles Interface um 23 Uhr arbeitet gegen das Sleep Gate (D8).
  /// Diese Fassung nimmt Leuchtdichte und Blauanteil zurueck; Kontraste
  /// bleiben ueber der Lesbarkeitsgrenze, aber nichts leuchtet mehr.
  static const darkMuted = AxiomPalette(
    base: Color(0xFF12100D),
    panel: Color(0xFF1A1714),
    panelRaised: Color(0xFF221E1A),
    rule: Color(0xFF332C26),
    ink: Color(0xFFE0D8CC),
    inkDim: Color(0xFFA3988A),
    // Lag mit 4,04/3,79/3,52:1 auf allen drei Flaechen unter AA — die
    // gedaempfte Fassung darf leiser sein, nicht unlesbar.
    inkFaint: Color(0xFF918575),
    signal: Color(0xFFD79A55),
    signalDeep: Color(0xFFA87433),
    calm: Color(0xFF8FA98C),
    caution: Color(0xFFBE7A55),
    info: Color(0xFF8B9AA0),
  );

  static const lightMuted = AxiomPalette(
    base: Color(0xFFF4F0E7),
    panel: Color(0xFFFBF8F1),
    panelRaised: Color(0xFFFFFDF8),
    rule: Color(0xFFD5CDBE),
    ink: Color(0xFF221E19),
    inkDim: Color(0xFF57503F),
    // 4,18:1 auf `base`, 4,48:1 auf `panel` — knapp daneben ist auch daneben.
    inkFaint: Color(0xFF746C5E),
    signal: Color(0xFF8A5A16),
    signalDeep: Color(0xFF6B450F),
    calm: Color(0xFF44634A),
    caution: Color(0xFF8C4A26),
    info: Color(0xFF3F5A66),
  );

  // ── Werkbank ──────────────────────────────────────────────────────────
  //
  // Die drei Schemata darueber sind Varianten desselben Bernsteins: ein
  // Messgeraet im Halbdunkel, entworfen fuer ein Telefon in der Hand, nachts,
  // einhaendig. Auf einem 27-Zoll-Monitor in einem hellen Raum kippt genau
  // das — die warme Toenung liegt dann als Braunschleier ueber der ganzen
  // Flaeche, und Bernstein auf Anthrazit hat bei Tageslicht zu wenig
  // Trennschaerfe fuer eine Tabelle mit dreissig Zeilen.
  //
  // Werkbank ist die Antwort darauf: weisse Flaechen, ein blaues Signal,
  // Luft. Es ist derselbe Grund, aus dem es `contrast` und `muted` gibt —
  // eine Umgebung, in der das Vorgabeschema nicht funktioniert.
  //
  // **Was nicht uebernommen wird:** Farbe als Note. Gruen-gut/rot-schlecht
  // ist der Kern des Vorbilds und faellt hier unter R7 — ein Zustandswert
  // ist ein Messwert. `calm` und `caution` behalten deshalb ihre Rollen aus
  // dem Kopfkommentar: ruhig und Aufmerksamkeit, nie Lob und nie Vorwurf.

  static const lightWorkbench = AxiomPalette(
    base: Color(0xFFF5F6FA),
    panel: Color(0xFFFFFFFF),
    panelRaised: Color(0xFFF0F2F8),
    rule: Color(0xFFDDE1EC),
    ink: Color(0xFF20232C),
    inkDim: Color(0xFF565E72),
    // Der schlechteste Wert der ganzen Palette: #868DA1 lag bei 3,07/3,31/
    // 2,96:1. Der letzte Wert unterschreitet sogar die 3:1-Grenze, die fuer
    // reine Grafik gilt — und er traf jede `SectionLabel` und jeden
    // Hinweistext im Erfassungsblatt. #868DA1 ist praktisch derselbe Ton,
    // der bei der hellen Standardpalette (siehe oben) schon einmal als
    // unlesbar verworfen wurde.
    inkFaint: Color(0xFF666E83),
    signal: Color(0xFF0F62D6),
    signalDeep: Color(0xFF0A48A0),
    calm: Color(0xFF157D4E),
    // Kupfer, nicht Rot. Das Vorbild benutzt hier #E2445C — und genau das
    // ist die eine Farbe, die dieses Projekt nicht fuehrt (Kopfkommentar,
    // Punkt 1). Aufmerksamkeit ja, Vorwurf nein.
    caution: Color(0xFFA9500F),
    info: Color(0xFF6A3FBF),
  );

  static const darkWorkbench = AxiomPalette(
    base: Color(0xFF12141B),
    panel: Color(0xFF1A1D26),
    panelRaised: Color(0xFF232733),
    rule: Color(0xFF313648),
    ink: Color(0xFFECEEF5),
    inkDim: Color(0xFFA0A7BB),
    // 4,33:1 auf `panel`, 3,84:1 auf `panelRaised`.
    inkFaint: Color(0xFF878EA1),
    signal: Color(0xFF5A9BFF),
    signalDeep: Color(0xFF3570D4),
    calm: Color(0xFF3FC98D),
    caution: Color(0xFFE08C4A),
    info: Color(0xFFA98BFF),
  );

  /// Farbe fuer eine Load-Stufe. Bewusst ohne Rot — siehe Kopfkommentar.
  Color forLoadLevel(int level) => switch (level) {
        0 => calm,
        1 => info,
        2 => signal,
        _ => caution,
      };
}

/// Farbschema — drei, nicht dreissig.
///
/// Einstellungs-Wildwuchs ist bei diesem Profil selbst ein Problem (D3),
/// deshalb hat jede Fassung hier einen Grund und nicht bloss einen Namen:
///
///  * [instrument] ist die Gestaltung, gegen die entworfen wurde.
///  * [contrast] existiert fuer Lesbarkeit — Sonne, Muedigkeit, kleine
///    Schrift. Ein Text, der nicht gelesen wird, wirkt nicht.
///  * [muted] existiert fuer den Abend. Ein grelles Interface um 23 Uhr
///    arbeitet gegen das Sleep Gate (D8).
///  * [workbench] existiert fuer den grossen Bildschirm bei Tageslicht. Die
///    drei anderen sind Varianten desselben Bernsteins — auf einem Monitor
///    in einem hellen Raum liegt der als Braunschleier ueber allem, und fuer
///    eine Tabelle mit dreissig Zeilen fehlt ihm die Trennschaerfe.
enum AxiomScheme {
  instrument('Instrument'),
  contrast('Kontrast'),
  muted('Gedämpft'),
  workbench('Werkbank');

  const AxiomScheme(this.label);

  /// Deutscher Quelltext — die Oberflaeche uebersetzt ihn.
  final String label;

  AxiomPalette palette(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return switch (this) {
      AxiomScheme.instrument =>
        dark ? AxiomPalette.dark : AxiomPalette.light,
      AxiomScheme.contrast =>
        dark ? AxiomPalette.darkContrast : AxiomPalette.lightContrast,
      AxiomScheme.muted =>
        dark ? AxiomPalette.darkMuted : AxiomPalette.lightMuted,
      AxiomScheme.workbench =>
        dark ? AxiomPalette.darkWorkbench : AxiomPalette.lightWorkbench,
    };
  }

  static AxiomScheme parse(String? name) => AxiomScheme.values.firstWhere(
        (s) => s.name == name,
        orElse: () => AxiomScheme.instrument,
      );
}

/// Textgroesse in Stufen.
///
/// Kein stufenloser Regler: Ein Regler ist eine Entscheidung mit unendlich
/// vielen Antworten, und genau die kostet hier am meisten (G1). Vier Stufen
/// mit klaren Namen sind in zwei Sekunden erledigt.
enum TextSize {
  compact('Kompakt', 0.9),
  normal('Normal', 1.0),
  large('Groß', 1.18),
  larger('Sehr groß', 1.38);

  const TextSize(this.label, this.scale);

  final String label;
  final double scale;

  static TextSize parse(String? name) => TextSize.values.firstWhere(
        (s) => s.name == name,
        orElse: () => TextSize.normal,
      );
}

/// Abstaende. Vierer-Raster — genug Struktur fuer ein Instrument,
/// nicht so fein, dass es beliebig wird.
abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 48;
}

abstract final class Radii {
  /// Frontplatten haben kleine Radien — sie sind gefraest, nicht geblasen.
  static const double panel = 6;
  static const double control = 4;
  static const double pill = 999;
}

/// Schriftfamilien. Gebuendelt als Assets, nie zur Laufzeit geladen —
/// die App deklariert bewusst keine INTERNET-Berechtigung (ADR-0002).
abstract final class Fonts {
  /// IBM Plex Sans. Entworfen als Hausschrift fuer Ingenieure — humanistisch
  /// genug fuer Fliesstext, technisch genug fuer eine Instrumententafel.
  static const String sans = 'PlexSans';

  /// IBM Plex Mono. Alles, was ein Messwert ist: Zahlen, Regel-IDs,
  /// Skalen, Zeitanker. Mono signalisiert "abgelesen", nicht "gemeint".
  static const String mono = 'PlexMono';
}

/// Dauer von Bewegungen.
///
/// Sparsam dosiert: Die Zielgruppe ist leicht ablenkbar. Bewegung darf
/// Zustandsaenderungen erklaeren, nie unterhalten. Alles respektiert
/// `MediaQuery.disableAnimations`.
abstract final class Motion {
  static const Duration instant = Duration(milliseconds: 90);
  static const Duration quick = Duration(milliseconds: 180);
  static const Duration settle = Duration(milliseconds: 320);

  /// Fuer Werte, die sich einpendeln — wie ein Zeiger, der einschwingt.
  static const Curve instrument = Curves.easeOutCubic;
}
