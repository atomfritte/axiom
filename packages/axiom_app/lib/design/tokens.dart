/// Design-Tokens.
///
/// Gestaltungsleitbild: **Instrument, nicht Produktivitaets-App.** Jede Zahl
/// ist ein Messwert, kein Urteil; jede Ausgabe nennt ihre Regel. Was das
/// heisst, steht in den zwei Entscheidungen unten — nicht in einer bestimmten
/// Palette.
///
/// Zwei Entscheidungen, die aus dem Nutzerprofil folgen und nicht verhandelbar
/// sind:
///
///  1. **Kein Rot.** Rot heisst Fehler heisst Schuld. Bei Rejection
///     Sensitivity (D10) ist das die teuerste Farbe im Spektrum. Warnungen
///     sind Kupfer. Selbst der Erhaltungsmodus (L3) ist kein Alarm — er ist
///     ein Erfolg des Systems.
///
///  2. **Abends darf nichts leuchten.** Ein grelles Interface um 23 Uhr
///     arbeitet gegen das Sleep Gate (D8). Dafuer gibt es [AxiomScheme.muted]
///     und den dunklen Modus.
///
/// **Was hier gestanden hat und nicht mehr gilt:** „Warmes Anthrazit statt
/// Reinschwarz, Bernstein statt Neon" stand jahrelang als nicht verhandelbare
/// Entscheidung da — also als Gesetz, obwohl es eine Geschmacksfrage war. Die
/// Voreinstellung ist seit dem 07.08.2026 [AxiomScheme.workbench]: weisse
/// Flaechen, blaues Signal, Luft. Bernstein auf Anthrazit gibt es weiterhin
/// als [AxiomScheme.instrument], einen Tipp entfernt. Ein Leitbild, das eine
/// Palette vorschreibt, verwechselt das Mittel mit dem Zweck; die zwei
/// Punkte oben gelten in jeder Fassung, und darauf kommt es an.
library;

import 'package:flutter/material.dart';

/// Semantische Farbrollen. Jede Rolle hat eine dunkle und eine helle Fassung.
///
/// **Kontrast ist hier eine Zusage, keine Absicht.** Jede Rolle, die als Text
/// erscheint — [ink], [inkDim], [inkFaint], [signal], [calm], [caution],
/// [info] —, erreicht auf [base], [panel], [panelRaised] **und [well]**
/// mindestens 4,5:1 (WCAG 2.x AA fuer Fliesstext). Das ist keine Formalie:
/// Die kleinste Schriftgroesse der App liegt bei 12,5 px, damit greift keine
/// Large-Text-Ausnahme, und was nicht gelesen wird, existiert fuer dieses
/// Profil nicht [D9].
///
/// [well] ist dabei der teuerste der vier Gruende: Unter der
/// Reichweitenkante liegt eine vertiefte Flaeche, und dort steht Text, der
/// **nicht** ausgegraut wird. Ausgegraut hiesse „unwichtig"; gemeint ist
/// „heute nicht erreichbar". Der Unterschied ist der ganze Punkt der
/// Signatur — also muss die Mulde denselben Massstab halten wie jede andere
/// Flaeche.
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

  /// Ob diese Fassung dunkel ist.
  ///
  /// Nicht Kosmetik, sondern Physik: Erhebung entsteht im Hellen durch
  /// Schatten, im Dunkeln durch Helligkeitsstufe und Kantenlicht. Ein
  /// Schatten auf fast schwarzem Grund ist unsichtbar, ein Kantenlicht auf
  /// Weiss auch. [shade], [rim] und [Shadows] lesen dieses Feld.
  final bool isDark;

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
    required this.isDark,
  });

  /// Die Mulde — die Flaeche **unter** der Reichweitenkante.
  ///
  /// Bewusst gerechnet statt getippt. Acht weitere Farbwerte waeren acht
  /// weitere Stellen, an denen die Weboberflaeche des Expertenmodus
  /// auseinanderdriftet (`expert_server_test` vergleicht beide Dateien) —
  /// und eine Vertiefung ist ohnehin keine eigene Farbe, sondern derselbe
  /// Grund mit weniger Licht darauf.
  ///
  /// Schwarz mit wenig Deckkraft ueber dem Grund ist dabei nicht irgendeine
  /// Rechnung, sondern **die** richtige: Sie multipliziert jeden Kanal mit
  /// demselben Faktor und laesst das Farbverhaeltnis unangetastet. Die Mulde
  /// ist damit dieselbe Flaeche mit weniger Licht darauf — genau das, was
  /// eine Vertiefung ist. Ein Grauton daruebergelegt haette die warme
  /// Toenung herausgezogen, und die Mulde saehe aus wie eine fremde Karte.
  ///
  /// Ein erster Versuch toente im Hellen mit [rule]. Das war ungleichmaessig:
  /// Die Werkbank hat eine sehr helle Haarlinie, ihre Mulde wurde kaum
  /// sichtbar, waehrend die Standardfassung eine deutliche Stufe bekam. Eine
  /// Signatur, die in einem Schema verschwindet, ist keine.
  ///
  /// Die Tiefe ist knapp bemessen (4 % im Hellen, 45 % im Dunkeln) und das
  /// hat einen nachgerechneten Grund: Jede weitere Stufe kostet Textkontrast,
  /// und unter der Kante wird nichts ausgegraut. Wer sie vertieft, rechnet
  /// `contrast_test.dart` neu — und wird dort aufgehalten.
  Color get well => Color.alphaBlend(
        const Color(0xFF000000).withValues(alpha: isDark ? 0.45 : 0.04),
        base,
      );

  /// Schattenton. Nie Reinschwarz im Hellen: Ein Schatten ist Licht, das
  /// fehlt, kein Russ — und ein neutralgrauer Schatten unter einer warmen
  /// Karte sieht schmutzig aus.
  Color get shade => isDark ? const Color(0xFF000000) : ink;

  /// Kantenlicht auf erhobenen Flaechen. Im Hellen unsichtbar (dort
  /// arbeitet der Schatten), im Dunkeln die eigentliche Kante.
  Color get rim => isDark
      ? const Color(0xFFFFFFFF).withValues(alpha: 0.06)
      : const Color(0x00000000);

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
    isDark: true,
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
    //
    // Dritter Nachzug, diesmal aus der Reichweitenkante: #676E74 kam auf
    // `base` auf 4,58:1 und Bernstein #966210 auf 4,59:1 — beide hatten
    // rechnerisch keinen Millimeter Luft. Auf der Mulde (`well`) landeten
    // sie damit bei 4,14 bzw. 4,15:1. Da unten steht der Satz „Zerlegen
    // macht sie erreichbar" und die einzige farbige Handlung des Schirms
    // („zerlegen ›"); beides muss lesbar sein, sonst ist die Tiefzone eine
    // Sackgasse statt eines Wegs. Zwei Nuancen dunkler, Farbton unveraendert.
    inkFaint: Color(0xFF62686E),
    signal: Color(0xFF8E5D0F),
    signalDeep: Color(0xFF7A4E08),
    calm: Color(0xFF3F6B4F),
    caution: Color(0xFF9C4522),
    info: Color(0xFF3E6072),
    isDark: false,
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
    isDark: true,
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
    isDark: false,
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
    isDark: true,
  );

  static const lightMuted = AxiomPalette(
    base: Color(0xFFF4F0E7),
    panel: Color(0xFFFBF8F1),
    panelRaised: Color(0xFFFFFDF8),
    rule: Color(0xFFD5CDBE),
    ink: Color(0xFF221E19),
    inkDim: Color(0xFF57503F),
    // 4,18:1 auf `base`, 4,48:1 auf `panel` — knapp daneben ist auch daneben.
    // Danach 4,56:1 und damit ohne Reserve fuer die Mulde (4,17:1); zwei
    // Nuancen dunkler, siehe die helle Standardfassung.
    inkFaint: Color(0xFF6E6659),
    signal: Color(0xFF8A5A16),
    signalDeep: Color(0xFF6B450F),
    calm: Color(0xFF44634A),
    caution: Color(0xFF8C4A26),
    info: Color(0xFF3F5A66),
    isDark: false,
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
    // Und noch einmal zwei Nuancen fuer die Mulde: 4,72:1 auf `base` liess
    // 4,44:1 auf `well` uebrig.
    inkFaint: Color(0xFF626A7F),
    signal: Color(0xFF0F62D6),
    signalDeep: Color(0xFF0A48A0),
    // 4,77:1 auf `base`, 4,36:1 auf `well` — eine Nuance dunkler.
    calm: Color(0xFF14794C),
    // Kupfer, nicht Rot. Das Vorbild benutzt hier #E2445C — und genau das
    // ist die eine Farbe, die dieses Projekt nicht fuehrt (Kopfkommentar,
    // Punkt 1). Aufmerksamkeit ja, Vorwurf nein.
    caution: Color(0xFFA9500F),
    info: Color(0xFF6A3FBF),
    isDark: false,
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
    isDark: true,
  );

  /// Farbe fuer eine Load-**Stufe**. Bewusst ohne Rot — siehe Kopfkommentar.
  ///
  /// **Was diese Funktion faerben darf und was nicht.** Sie faerbt einen
  /// *Zustand*: L0 bis L3 sind vier benannte Regime, in denen sich das
  /// System unterschiedlich verhaelt. Ein Regime hat eine Rolle, so wie ein
  /// Schalter „an" oder „aus" ist.
  ///
  /// Sie faerbt **keinen Messwert**. Kompensationslast, Kapazitaet,
  /// Reizbedarf sind Zahlen auf derselben Skala, und drei Zahlen
  /// untereinander in drei Farben lesen sich als drei verschiedene *Urteile*
  /// — genau das verbietet R7. Messwerte tragen deshalb ausnahmslos
  /// [signal]; unterschieden wird ueber Beschriftung und Position, nicht
  /// ueber Farbe. `InstrumentBar` setzt das durch, `typography_test.dart`
  /// haelt es fest.
  Color forLoadLevel(int level) => switch (level) {
        0 => calm,
        1 => info,
        2 => signal,
        _ => caution,
      };
}

/// Erhebung — die Signatur dieses Entwurfs in zwei Zeilen Code.
///
/// Hoehe kodiert **Entfernung, nicht Bewertung** (R7, D10). Was erhoben ist,
/// geht heute in die Hand; was in der Mulde liegt, ist da und heute nicht
/// erreichbar. Eine Farbe haette an dieser Stelle „gut/schlecht" gesagt.
///
/// Im Hellen entsteht die Stufe aus Schatten, im Dunkeln aus Kantenlicht und
/// Helligkeit — deshalb liest jede Funktion hier [AxiomPalette.isDark].
abstract final class Shadows {
  /// Eine gewoehnliche Karte: liegt auf dem Grund.
  static List<BoxShadow> resting(AxiomPalette p) => p.isDark
      ? [
          BoxShadow(
            color: p.shade.withValues(alpha: 0.38),
            blurRadius: 16,
            offset: const Offset(0, 6),
            spreadRadius: -6,
          ),
        ]
      : [
          BoxShadow(
            color: p.shade.withValues(alpha: 0.045),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: p.shade.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
            spreadRadius: -6,
          ),
        ];

  /// Griffhoehe: die eine Handlung, die jetzt gemeint ist (G1).
  static List<BoxShadow> reachable(AxiomPalette p) => p.isDark
      ? [
          BoxShadow(
            color: p.shade.withValues(alpha: 0.55),
            blurRadius: 34,
            offset: const Offset(0, 16),
            spreadRadius: -12,
          ),
          BoxShadow(
            color: p.shade.withValues(alpha: 0.40),
            blurRadius: 10,
            offset: const Offset(0, 3),
            spreadRadius: -4,
          ),
        ]
      : [
          BoxShadow(
            color: p.shade.withValues(alpha: 0.055),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: p.shade.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 6),
            spreadRadius: -3,
          ),
          BoxShadow(
            color: p.shade.withValues(alpha: 0.09),
            blurRadius: 40,
            offset: const Offset(0, 20),
            spreadRadius: -12,
          ),
        ];
}

/// Die Voreinstellung. An genau einer Stelle, damit sie sich nicht an drei
/// Orten auseinanderentwickelt — `parse`, die Laufzeit und `buildAxiomTheme`
/// hatten sie bisher je einzeln stehen.
const kDefaultScheme = AxiomScheme.workbench;

/// Farbschema — vier, nicht vierzig.
///
/// Einstellungs-Wildwuchs ist bei diesem Profil selbst ein Problem (D3),
/// deshalb hat jede Fassung hier einen Grund und nicht bloss einen Namen:
///
///  * [workbench] ist die **Vorgabe**: weisse Flaechen, blaues Signal, Luft.
///  * [instrument] ist die Gestaltung, gegen die urspruenglich entworfen
///    wurde — Bernstein auf warmem Anthrazit, eine Messgeraetefrontplatte.
///  * [contrast] existiert fuer Lesbarkeit — Sonne, Muedigkeit, kleine
///    Schrift. Ein Text, der nicht gelesen wird, wirkt nicht.
///  * [muted] existiert fuer den Abend. Ein grelles Interface um 23 Uhr
///    arbeitet gegen das Sleep Gate (D8).
///
/// **Warum die Vorgabe gewechselt hat.** [instrument] war drei Jahre lang
/// die Voreinstellung und stand fuer das Leitbild „Instrumententafel, nicht
/// Produktivitaets-App". Der Nutzer hat es als „trist" bezeichnet, und eine
/// Pruefung aller Schirme in allen vier Fassungen gab ihm recht: Dieselbe
/// Gestaltung — dieselbe Typografie, dieselben Abstaende, dieselbe
/// Reichweitenkante — wirkt in [workbench] hell und aufgeraeumt und in
/// [instrument] dunkel und schwer. Es war nie eine Entwurfsfrage, sondern
/// eine Schemafrage.
///
/// [instrument] bleibt vollstaendig erhalten und einen Tipp entfernt. Was
/// hier gewechselt hat, ist die Voreinstellung, nicht die Moeglichkeit.
enum AxiomScheme {
  // Reihenfolge = Reihenfolge in der Auswahl. Die Vorgabe steht vorn.
  workbench('Werkbank'),
  instrument('Instrument'),
  contrast('Kontrast'),
  muted('Gedämpft');

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
        orElse: () => kDefaultScheme,
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

/// Radien.
///
/// Hier stand: „Frontplatten haben kleine Radien — sie sind gefraest, nicht
/// geblasen" (Panel 6, Control 4). Das war konsequent zum Bild der
/// Instrumententafel und hatte eine Folge, die alle zwoelf Juroren
/// unabhaengig genannt haben: Die Oberflaeche wirkte hart und trist. Ein
/// gefraester 6-px-Radius liest sich auf einem Telefon nicht als Praezision,
/// sondern als Kasten.
///
/// Die neuen Werte liegen im Bereich 12–22. Sie sind kein Geschmack, sondern
/// die Voraussetzung fuer die Signatur: Eine Karte, die *schwebt*, braucht
/// eine Kante, die Licht faengt — und ein 6-px-Radius faengt keins.
abstract final class Radii {
  /// Karten und Frontplatten.
  static const double panel = 18;

  /// Knoepfe, Eingabefelder, kleine Kaesten.
  static const double control = 12;

  /// Die Mulde unter der Reichweitenkante.
  static const double well = 22;

  static const double pill = 999;
}

/// Schriftfamilien. Gebuendelt als Assets, nie zur Laufzeit geladen —
/// die App deklariert bewusst keine INTERNET-Berechtigung (ADR-0002).
abstract final class Fonts {
  /// IBM Plex Sans. Entworfen als Hausschrift fuer Ingenieure — humanistisch
  /// genug fuer Fliesstext, technisch genug fuer eine Instrumententafel.
  ///
  /// Traegt seit dieser Runde auch alle Zahlen: mit
  /// [kTabularFigures] stehen sie genauso sauber untereinander wie in
  /// Monospace, nur ohne den Schreibmaschinenton.
  static const String sans = 'PlexSans';

  /// IBM Plex Mono. **Fuer die Regel-ID und fuer woertlich Abzutippendes** —
  /// nicht mehr fuer Messwerte.
  ///
  /// Hier stand: „Alles, was ein Messwert ist: Zahlen, Regel-IDs, Skalen,
  /// Zeitanker. Mono signalisiert ‚abgelesen', nicht ‚gemeint'." Die Folge
  /// waren 117 Aufrufe von `monoStyle` gegen sieben `RuleStamp` — jede Zahl,
  /// jede Beschriftung, jeder Zeitanker in Schreibmaschine. Das Argument war
  /// die Spaltenausrichtung, und die liefert [kTabularFigures] genauso.
  ///
  /// Uebrig bleiben zwei Faelle, die keine Messwerte sind:
  ///
  ///  1. Die **Regel-ID** (`RuleStamp`). Sie ist damit das einzige technisch
  ///     aussehende Element eines Schirms und deshalb sofort zu finden — G2
  ///     wird dadurch lauter, nicht leiser.
  ///  2. **Woertlicher Text**, den man abtippt oder kopiert: Shell-Befehle,
  ///     Dateipfade, YAML, Fehlerausgaben. Da traegt Monospace echte
  ///     Information (welches Zeichen wo steht), statt Stimmung zu machen.
  ///
  /// `typography_test.dart` deckelt die Zahl der Fundstellen je Datei.
  static const String mono = 'PlexMono';
}

/// Tabellenziffern: gleiche Vorbreite fuer jede Ziffer.
///
/// Der einzige sachliche Grund fuer Monospace war, dass 61 und 88
/// untereinander fluchten. Genau das leistet `tnum` — in der Hausschrift,
/// ohne Schreibmaschinenton. Jeder Messwert der Oberflaeche laeuft damit;
/// `readingStyle` in `theme.dart` setzt es.
///
/// **Ehrlichkeitshalber:** Beim gebuendelten IBM Plex Sans aendert diese
/// Angabe im Moment nichts — die Schrift fuehrt gar keine
/// Proportionalziffern, alle zehn Ziffern sind 600 Einheiten breit
/// (nachgezaehlt in `hmtx`), und ein `tnum`-Merkmal gibt es deshalb auch
/// nicht. Der Eintrag steht trotzdem hier: Er sagt, was zugesagt ist, und
/// haelt die Zusage, sobald jemand die Schrift austauscht. Was hier steht,
/// darf nicht davon abhaengen, welche Datei gerade daneben liegt.
const List<FontFeature> kTabularFigures = [FontFeature.tabularFigures()];

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
