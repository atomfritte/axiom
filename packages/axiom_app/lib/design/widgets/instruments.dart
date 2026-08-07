/// Instrumente — die Bausteine der Zustandsanzeige.
///
/// Jeder Messwert zeigt auf Wunsch seine Herleitung. Ein Score ohne
/// sichtbaren Rechenweg ist fuer dieses Nutzerprofil Willkuer (G2).
library;

import 'package:axiom_core/axiom_core.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../tokens.dart';
import '../../i18n/i18n.dart';

/// Kommazahl in der eingestellten Sprache.
///
/// „67.5" ist im Deutschen keine Zahl, sondern ein Tippfehler. In einer
/// Herleitung, die beweisen soll, dass die Summe stimmt, faellt genau das
/// auf — und wer einmal stolpert, rechnet nicht weiter nach.
String _decimal(BuildContext context, double value, {int digits = 1}) {
  final text = value.toStringAsFixed(digits);
  return context.language == AppLanguage.de ? text.replaceAll('.', ',') : text;
}

/// Eine Messwertzeile: Name, Balken, Zahl — aufklappbar zur Herleitung.
///
/// **Jeder Messwert wird in [AxiomPalette.signal] gezeichnet.** Vorher waehlte
/// die aufrufende Seite eine Farbe je Messwert: Kapazitaet bernstein,
/// Kompensationslast gruen (ueber `forLoadLevel`), Reizbedarf kupfern,
/// Fokuslast blau. Untereinander gelesen — und genau so stehen sie auf dem
/// Zustandsschirm — las sich das als drei bis sechs verschiedene *Urteile*
/// ueber denselben Menschen. Gruen sagt „gut", Kupfer sagt „Achtung"; beides
/// sind Noten, und Noten sind hier verboten (R7: Zustandswerte sind
/// Messwerte).
///
/// Unterschieden wird ab jetzt ueber Beschriftung und Position. Farbe
/// unterscheidet nur noch *Messung* von *Zustand* — und ein Zustand (eine
/// Laststufe, ein Regime) faerbt sich weiterhin ueber
/// [AxiomPalette.forLoadLevel], nur eben nicht mehr hier.
final class InstrumentBar extends StatefulWidget {
  final String label;

  /// 0..100.
  final int value;

  /// **Wird nicht mehr ausgewertet.**
  ///
  /// Der Parameter steht nur noch da, damit die Schirme, die ihn heute
  /// uebergeben, weiter uebersetzen; er faerbt nichts. Wer ihn an einer
  /// Aufrufstelle findet, streicht ihn — das ist dann eine Zeile weniger und
  /// keine Verhaltensaenderung. Danach kann auch dieses Feld weg.
  final Color? color;

  /// Kurze Einordnung ohne Bewertung ("ausgeruht", "hohe Last").
  final String? reading;

  /// Terme der Formel. Leer = nicht aufklappbar.
  final List<Term> breakdown;

  /// 0..1. Unter 0.4 feuern Regeln nicht — das wird sichtbar gemacht.
  final double confidence;

  const InstrumentBar({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.reading,
    this.breakdown = const [],
    this.confidence = 1.0,
  });

  @override
  State<InstrumentBar> createState() => _InstrumentBarState();
}

class _InstrumentBarState extends State<InstrumentBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final expandable = widget.breakdown.isNotEmpty;
    final stale = widget.confidence < 0.4;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      button: expandable,
      label: context.t('{0}: {1} von 100{2}{3}', [widget.label, widget.value, widget.reading == null ? "" : ", ${widget.reading}", stale ? context.t(', Daten veraltet') : ""]),
      child: InkWell(
        onTap: expandable
            ? () {
                HapticFeedback.selectionClick();
                setState(() => _expanded = !_expanded);
              }
            : null,
        borderRadius: BorderRadius.circular(Radii.control),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(widget.label,
                        style: Theme.of(context).textTheme.labelSmall),
                  ),
                  if (stale)
                    Padding(
                      padding: const EdgeInsets.only(right: Space.sm),
                      // „DATEN ALT" war neun Zeichen in gesperrten Versalien
                      // — die Ausnahme gilt nur bis sieben.
                      child: Text(context.t('Daten alt'),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: p.inkFaint)),
                    ),
                  Text(
                    '${widget.value}',
                    style: readingStyle(context,
                        size: 17,
                        color: stale ? p.inkFaint : p.signal),
                  ),
                  if (expandable)
                    Padding(
                      padding: const EdgeInsets.only(left: Space.xs),
                      child: AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: reduceMotion ? Duration.zero : Motion.quick,
                        child: Icon(Icons.keyboard_arrow_down,
                            size: 16, color: p.inkFaint),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Space.sm),
              _Bar(
                value: widget.value,
                color: stale ? p.inkFaint : p.signal,
                track: p.rule,
              ),
              if (widget.reading != null) ...[
                const SizedBox(height: Space.xs + 2),
                Text(widget.reading!,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              // AnimatedSize statt AnimatedCrossFade: Letzteres haelt beide
              // Kinder dauerhaft im Baum — die eingeklappte Herleitung waere
              // fuer Screenreader und Suchen weiterhin vorhanden.
              AnimatedSize(
                duration: reduceMotion ? Duration.zero : Motion.quick,
                curve: Motion.instrument,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? _Breakdown(
                        terms: widget.breakdown,
                        value: widget.value,
                        confidence: widget.confidence,
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _Bar extends StatelessWidget {
  final int value;
  final Color color;
  final Color track;
  const _Bar({required this.value, required this.color, required this.track});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          // Runde Enden statt geschnittener: Der Balken ist eine Marke auf
          // einer Skala, kein Fortschrittsbalken mit Ziellinie.
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: track,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: value / 100, end: value / 100),
            duration: reduceMotion ? Duration.zero : Motion.settle,
            curve: Motion.instrument,
            builder: (context, t, _) => Container(
              height: 4,
              width: constraints.maxWidth * t,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Die Herleitungstafel: jeder Term mit seinem Beitrag — **und die Summe.**
///
/// **Warum die drei Zeilen unten keine Kosmetik sind.** G2 verlangt, dass
/// kein Score ohne sichtbare Formel dasteht. Hier standen die Terme, und
/// darunter stand nichts. Wer nachrechnete, kam auf eine andere Zahl als die
/// oben angezeigte — bei Konfidenz 0,50 summierten sich sichtbare 67,5 zu
/// einer angezeigten 60. Eine Formel, die etwas anderes rechnet, als sie
/// zeigt, erklaert nichts; sie beschaedigt das Vertrauen in alles andere,
/// was das System behauptet.
///
/// Der Kern liefert die fehlende Groesse inzwischen als eigenen Term
/// („Duenne Datenlage", `state_deriver.dart`). Was noch fehlte, war der
/// Abschluss: **Summe · Rundung und Grenze · Angezeigt.** Damit ist die
/// Rechnung Zeile fuer Zeile nachvollziehbar, ohne dass man wissen muss,
/// was `clamp100` ist.
///
/// **Warum die Beitraege nicht mehr gruen und kupfern sind.** Ein negativer
/// Term ist kein schlechter Term. „Schlafschuld −18" ist eine Messung, keine
/// Ruege; in Kupfer gesetzt liest sie sich als Vorwurf (R7, D10). Das
/// Vorzeichen steht ohnehin da — es braucht keine Farbe, die es noch einmal
/// bewertet. Farbe traegt hier nur die eine Zeile, um die es geht: die
/// angezeigte Zahl.
final class _Breakdown extends StatelessWidget {
  final List<Term> terms;

  /// Der Wert, der oben steht. Das Ziel der Rechnung.
  final int value;

  /// 0..1.
  final double confidence;

  const _Breakdown({
    required this.terms,
    required this.value,
    required this.confidence,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final sum = terms.fold(0.0, (a, t) => a + t.contribution);
    // Der Rest zwischen Termsumme und angezeigtem Wert. Er entsteht durch
    // Runden und durch die Begrenzung auf 0..100 — und er wird ausgewiesen,
    // auch wenn er null ist. Gerade die Null ist die Aussage: Es fehlt
    // nichts.
    final rest = value - sum;

    Widget row(String label, String amount,
            {Color? color, FontWeight weight = FontWeight.w500}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(label,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: color ?? p.inkDim)),
              ),
              const SizedBox(width: Space.md),
              Text(amount,
                  style: readingStyle(context,
                      size: 14, weight: weight, color: color ?? p.inkDim)),
            ],
          ),
        );

    String signed(double v) =>
        '${v >= 0 ? "+" : "−"}${_decimal(context, v.abs())}';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: Space.md),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: p.well,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(context.t('So wird gerechnet'),
                    style: Theme.of(context).textTheme.labelSmall),
              ),
              if (confidence < 1.0)
                Text(
                  context.t('Konfidenz {0}',
                      [_decimal(context, confidence, digits: 2)]),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          for (final term in terms)
            row(term.label, signed(term.contribution)),
          const SizedBox(height: Space.sm),
          Container(height: 1, color: p.rule),
          const SizedBox(height: Space.sm),
          row(context.t('Summe der Terme'), _decimal(context, sum)),
          row(context.t('Rundung und Grenze 0 bis 100'), signed(rest)),
          row(context.t('Angezeigt'), '$value',
              color: p.signal, weight: FontWeight.w600),
        ],
      ),
    );
  }
}

/// Kleine Plakette mit der Regel-ID. Macht G2 sichtbar: Jede Ausgabe traegt
/// die Regel, die sie erzeugt hat.
final class RuleStamp extends StatelessWidget {
  final String ruleId;
  final VoidCallback? onTap;
  final Color? color;

  const RuleStamp({super.key, required this.ruleId, this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final tint = color ?? p.info;
    return Semantics(
      button: onTap != null,
      label: context.t('Regel {0}{1}', [ruleId, onTap == null ? "" : context.t(', zeigt die Begruendung')]),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.control),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: Space.sm, vertical: Space.xs),
          decoration: BoxDecoration(
            border: Border.all(color: tint.withValues(alpha: 0.45)),
            borderRadius: BorderRadius.circular(Radii.control),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(ruleId,
                  style: monoStyle(context,
                      size: 11, weight: FontWeight.w600, spacing: 0.6,
                      color: tint)),
              if (onTap != null) ...[
                const SizedBox(width: Space.xs),
                Icon(Icons.info_outline, size: 12, color: tint),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// **Die Zaehlplakette** — eine Zahl an der Zeile statt im Beitext.
///
/// Warum es sie gibt: Der Beitext einer Menuezeile wird ueberflogen.
/// „Eingang — Nichts zu sortieren." und „Eingang — 2 Notizen warten auf
/// Sortieren" unterscheiden sich fuer das Auge um zwei Woerter in der
/// kleineren zweiten Zeile; wer die nicht liest, erfaehrt nie, dass da etwas
/// liegt. Eine Zahl in einer Flaeche wird dagegen **gesehen, bevor gelesen
/// wird** — und was nicht ins Auge springt, existiert nicht [D9]. Der
/// Beitext bleibt und erklaert die Zahl; er traegt sie nur nicht mehr
/// allein.
///
/// **Sie zaehlt, sie mahnt nicht.** Kein Rot, keine Alarmfarbe, kein Wachsen
/// ins Bedrohliche, keine zweite Fassung fuer „zu viel": „3" heisst drei,
/// nicht „im Rueckstand" (R7, D10). Form und Farbe sind bei 1 dieselben wie
/// bei 12.
///
/// **Die Zahl ist bernstein, die Flaeche nicht.** Bernstein ist die Farbe
/// jedes Messwerts (die Zahl ist einer) — aber auf dem Hauptschirm zugleich
/// die der einen Handlung (G1). Eine **deckend** bernsteinfarbene Plakette
/// saehe neben dem Anfangen-Knopf aus wie ein zweites Angebot und machte aus
/// einer Handlung wieder eine Auswahl. Deshalb traegt die Ziffer den Farbton
/// und die Flaeche darunter keinen: sie ist [AxiomPalette.panel], also
/// dieselbe Stufe, die `_Tag` auf einer Karte in die andere Richtung nimmt
/// (dort Mulde auf Karte, hier Karte in der Mulde). Eine Toenung derselben
/// Farbe war die erste Fassung und sah im Dunkeln aus wie ein Fleck.
///
/// **Und die Ziffer steht deshalb auf einer Flaeche, nicht auf ihrer eigenen
/// Toenung.** Das ist der Unterschied zur Stufenplakette (`L0`–`L3`), und er
/// ist nachgerechnet: Derselbe Farbton vorn und hinten ist die einzige
/// Stelle dieser App, an der der Textkontrast unter AA faellt (`kBadgeFloor`
/// in `contrast_test.dart` haelt den Rueckstand fest). `signal` auf `panel`
/// ist dagegen eine der Kombinationen, die dieselbe Datei in allen acht
/// Fassungen ueber 4,5:1 prueft — ein neuer Ort desselben alten Musters
/// waere ein neuer Rueckstand gewesen.
///
/// **Null bekommt keine Plakette.** „0" ist eine Zahl, die nichts sagt und
/// trotzdem Platz und Aufmerksamkeit nimmt. Das steht hier und nicht am
/// Aufrufort: Eine Regel, die jeder Aufrufer selbst befolgen muss, wird
/// irgendwo nicht befolgt.
final class CountBadge extends StatelessWidget {
  final int count;

  const CountBadge(this.count, {super.key});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final p = context.axiom;
    return Container(
      // Mindestbreite, Zahl zentriert: Sonst ist die Plakette bei „1" ein
      // Kreis und bei „12" ein Riegel, und untereinander gelesen sieht die
      // groessere Zahl nach mehr Nachdruck aus. Die Form soll nichts ueber
      // die Menge sagen.
      //
      // Sie skaliert mit der Schrift, weil sie ein typografisches Mass ist:
      // Bleibt sie fest, waechst bei angehobener Schrift nur die Hoehe, und
      // aus der Plakette wird eine hochkant stehende Ellipse.
      constraints: BoxConstraints(
          minWidth: MediaQuery.textScalerOf(context).scale(26)),
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: readingStyle(context, size: 13.5, color: p.signal),
      ),
    );
  }
}

/// Eine Karte — eine Flaeche, die **ueber** dem Grund liegt.
///
/// Hier stand ein Haarlinienrahmen um jede Flaeche („Frontplatte"). Das ist
/// konsequent zum Bild der Instrumententafel und hat eine Nebenwirkung, die
/// sich erst auf zwoelf Schirmen zeigt: Zehn gerahmte Kaesten untereinander
/// sind ein Gitter, und ein Gitter hat keine Ordnung — alles ist gleich weit
/// weg.
///
/// Jetzt traegt der Schatten die Aussage. [reachable] hebt die eine Karte
/// heraus, die jetzt gemeint ist (G1); alle anderen liegen ruhig auf dem
/// Grund. Im Dunkeln uebernimmt das Kantenlicht ([AxiomPalette.rim]), weil
/// ein Schatten auf fast schwarzem Grund nichts sagt.
final class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  /// Zeichnet doch einen Rahmen, in dieser Farbe. Fuer die wenigen Faelle,
  /// in denen eine Karte einen *Zustand* meldet (geeicht, vollstaendig) —
  /// nicht fuer Messwerte.
  final Color? accent;

  /// Griffhoehe: die Karte, die jetzt in die Hand geht.
  final bool reachable;

  final VoidCallback? onTap;

  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.xl),
    this.accent,
    this.reachable = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final radius = BorderRadius.circular(Radii.panel);
    final content = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        // Im Dunkeln ist Griffhoehe eine Helligkeitsstufe, im Hellen nicht:
        // `panel` ist dort bereits Weiss, und `panelRaised` liegt *darunter*.
        // Die erhobene Karte sah damit im Hellen matter aus als eine
        // gewoehnliche — genau verkehrt herum. Im Hellen traegt allein der
        // Schatten, und das reicht: Er ist dort ohnehin das staerkere Mittel.
        color: reachable && p.isDark ? p.panelRaised : p.panel,
        borderRadius: radius,
        boxShadow: reachable ? Shadows.reachable(p) : Shadows.resting(p),
        border: accent != null
            ? Border.all(color: accent!)
            : (p.isDark ? Border.all(color: p.rim) : null),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: content,
    );
  }
}

/// Abschnittsmarke — normale Schreibweise, kein Trennstrich.
///
/// Hier stand `text.toUpperCase()` und dahinter eine Haarlinie ueber die
/// restliche Breite. Beides ging in dieselbe Richtung und beides kostete:
/// Gesperrte Versalien sind langsamer zu lesen, weil die Wortform verloren
/// geht, und ein Strich hinter jeder Ueberschrift zieht ein Lineal ueber
/// den Schirm, das nichts trennt, was der Abstand nicht schon trennte.
///
/// Der Zaehler (`· 3`) steht jetzt als eigenes Stueck rechts neben der
/// Marke statt in ihr — er ist ein Messwert und laeuft mit Tabellenziffern.
final class SectionLabel extends StatelessWidget {
  final String text;

  /// Optionale Zahl rechts. Ein Messwert, kein Zusatz zur Ueberschrift.
  final String? count;

  final Widget? trailing;

  const SectionLabel(this.text, {super.key, this.count, this.trailing});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Row(
        children: [
          // Flexible mit Ellipse: Bei sehr grosser Schrift kuerzt die
          // Ellipse, statt dass die Zeile ueberlaeuft.
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall),
          ),
          if (count != null) ...[
            const SizedBox(width: Space.sm),
            Text(count!,
                style: readingStyle(context, size: 13.5, color: p.inkFaint)),
          ],
          if (trailing != null) ...[
            const Spacer(),
            const SizedBox(width: Space.md),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// **Die Reichweitenkante** — die Signatur dieses Entwurfs.
///
/// Kein Trennstrich, sondern ein Horizont: Darueber liegt, was heute in die
/// Hand geht, darunter, was da ist und heute nicht. Ihre Hoehe ist ein
/// Messwert — die Kapazitaet. Sinkt sie, sinkt mehr vom Tag unter die Kante,
/// ganz ohne einen Satz darueber.
///
/// Warum Tiefe und nicht Farbe: Tiefe kodiert **Entfernung**, Farbe haette
/// „gut/schlecht" gesagt. Was unten liegt, ist nicht schlecht — es ist heute
/// weiter weg (R7, D10). Und sie beantwortet die teuerste Sekunde bei
/// niedriger Kapazitaet — „was kann ich jetzt anfangen" — bevor man liest
/// (G1).
///
/// Gehoert immer zwischen die erhobenen Karten und ein [Well]. Ohne die
/// Mulde darunter ist sie nur eine Zeile.
final class ReachEdge extends StatelessWidget {
  /// 0..100.
  final int capacity;

  const ReachEdge({super.key, required this.capacity});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Semantics(
      label: context.t('Reichweitenkante. Reichweite heute {0}.', [capacity]),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.xl, Space.lg, Space.md),
        child: Row(
          children: [
            Flexible(
              child: Text(context.t('Reichweite heute'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall),
            ),
            const SizedBox(width: Space.sm),
            Text('$capacity',
                style: readingStyle(context, size: 19, color: p.signal)),
            const SizedBox(width: Space.md),
            // Der Strich laeuft nach rechts aus. Er ist die Kante selbst,
            // nicht ihre Umrandung — deshalb ohne festes Ende.
            Expanded(
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(1),
                  gradient: LinearGradient(colors: [
                    p.signal.withValues(alpha: 0.55),
                    p.signal.withValues(alpha: 0.04),
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// **Die Mulde** — die Flaeche unter der Reichweitenkante.
///
/// Flutter kennt keinen Innenschatten. Der hier ist gemalt: ein kurzer
/// Verlauf unter der Oberkante, darueber zwei Haarlinien — aussen faengt
/// die Kante Licht, innen liegt sie im Schatten. An dieser Abfolge erkennt
/// das Auge eine Vertiefung und keine zweite Farbe.
///
/// **Was hier nicht passiert: Ausgrauen.** Der Text in der Mulde behaelt
/// seine Rollen und damit seinen vollen Kontrast — [AxiomPalette.well] ist
/// dafuer eigens knapp bemessen und nachgerechnet. Ausgegraut hiesse
/// „unwichtig"; gemeint ist „heute nicht in Reichweite". Der Unterschied
/// ist der ganze Punkt: Was hier liegt, ist nicht weniger wert, es ist
/// weiter weg.
///
/// Die einzige farbige Handlung, die hier stehen darf, ist der Weg nach
/// oben („zerlegen ›"). Alles andere bleibt Text.
final class Well extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  /// Vollflaechig heisst `BorderRadius.zero` — dann ist die Mulde der Boden
  /// des Schirms und nicht ein weiterer Kasten darauf.
  final BorderRadius radius;

  const Well({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.xl),
    this.radius = const BorderRadius.all(Radius.circular(Radii.well)),
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return ClipRRect(
      borderRadius: radius,
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            color: p.well,
            padding: padding,
            child: child,
          ),
          // Innenschatten: das Licht kommt von oben, also faellt es direkt
          // unter der Kante am wenigsten ein.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 26,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      p.shade.withValues(alpha: p.isDark ? 0.55 : 0.17),
                      p.shade.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Die Schattenlippe innen …
          Positioned(
            top: 1.5,
            left: 0,
            right: 0,
            height: 1.5,
            child: IgnorePointer(
              child: ColoredBox(
                  color: p.shade.withValues(alpha: p.isDark ? 0.7 : 0.14)),
            ),
          ),
          // … und die Lichtlippe aussen.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 1.5,
            child: IgnorePointer(
              child: ColoredBox(
                color: const Color(0xFFFFFFFF)
                    .withValues(alpha: p.isDark ? 0.05 : 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// Ein Ladezustand, der nicht ewig schweigt.
///
/// **Warum das kein Detail ist.** Ein Kreisel ohne Ende ist von einer
/// abgestürzten App nicht zu unterscheiden — man wartet, dann tippt man
/// herum, dann löscht man sie. Genau das ist einmal passiert: Eine
/// Systemschnittstelle antwortete nicht, der Kreisel drehte weiter, und von
/// außen sah es aus, als sei die App kaputt.
///
/// Nach [patience] sagt er deshalb, dass es länger dauert als vorgesehen,
/// und wohin man dann schaut. Ein stiller Ausfall ist schlimmer als ein
/// lauter (R4).
class PatientLoader extends StatefulWidget {
  final Duration patience;
  final String hint;

  const PatientLoader({
    super.key,
    required this.hint,
    this.patience = const Duration(seconds: 8),
  });

  @override
  State<PatientLoader> createState() => _PatientLoaderState();
}

class _PatientLoaderState extends State<PatientLoader> {
  bool _slow = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.patience, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 90,
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: p.rule,
                color: p.signal,
              ),
            ),
            if (_slow) ...[
              const SizedBox(height: Space.xl),
              Text(
                widget.hint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Wie hoch ein Element mit Text sein muss.
///
/// Feste Höhen um Text herum sind die häufigste Ursache für abgeschnittene
/// Zeilen: Bei 1,6-fach ist die Schrift größer, der Kasten nicht. Die App
/// lässt bis 2,4-fach zu — wer die Oberfläche schlecht liest, stellt hoch,
/// und genau dann darf sie nicht kaputtgehen.
///
/// Nur für Kästen mit Text. Punkte, Linien und Farbbalken bleiben, wie sie
/// sind; ein Zeitstrahl, der mit der Schrift wächst, wird zum Balken.
double scaledHeight(BuildContext context, double base) =>
    MediaQuery.textScalerOf(context).scale(base).clamp(base, base * 2.2);

/// Ein Zustand, in dem nichts da ist — und das eine Aussage, kein Fehler.
///
/// **Warum scrollbar.** Der Erklärtext ist hier absichtlich lang: Ein leerer
/// Screen ist die Stelle, an der man erfährt, wozu es ihn gibt. Bei großer
/// Schrift passt er nicht mehr auf ein 640er Display, und eine feste Spalte
/// schneidet ihn dann unten ab — ausgerechnet die Erklärung.
///
/// **Warum ohne Illustration und ohne Aufforderung.** „Leg jetzt deine erste
/// Aufgabe an!" ist eine Handlungsaufforderung ohne Anlass. Hier steht, was
/// der Fall ist, und woher etwas käme.
final class EmptyState extends StatelessWidget {
  /// Kurz, in normaler Schreibweise — der Zustand als Messwert.
  ///
  /// Hier stand „Kurz, in Versalien". Gesperrte Versalien sind langsamer zu
  /// lesen, und der leere Schirm ist ausgerechnet die Stelle, an der jemand
  /// zum ersten Mal liest, wozu es ihn gibt.
  final String label;

  /// Ein Satz, der den Zustand benennt.
  final String headline;

  /// Woher etwas käme. Zwei, drei Sätze.
  final String body;

  /// Optionaler Nachsatz, kleiner gesetzt.
  final String? footnote;

  const EmptyState({
    super.key,
    required this.label,
    required this.headline,
    required this.body,
    this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: Space.md),
        Text(headline, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: Space.md),
        Text(body, style: Theme.of(context).textTheme.bodyMedium),
        if (footnote != null) ...[
          const SizedBox(height: Space.lg),
          Text(footnote!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );

    // Derselbe Baustein steht mal als ganzer Bildschirminhalt da und mal als
    // Eintrag in einer Liste. Als Bildschirminhalt braucht er eine eigene
    // Scrollansicht, sonst laeuft der Erklaertext bei grosser Schrift unten
    // hinaus; in einer Liste waere dieselbe Scrollansicht ein Fehler
    // („unbounded height"). Die Randbedingung sagt, welcher Fall vorliegt:
    // In einer Liste ist die Hoehe unbegrenzt.
    return LayoutBuilder(
      builder: (context, constraints) {
        const padding = EdgeInsets.fromLTRB(
            Space.lg, Space.huge, Space.lg, Space.huge);
        if (!constraints.hasBoundedHeight) {
          return Padding(padding: padding, child: content);
        }
        return SingleChildScrollView(padding: padding, child: content);
      },
    );
  }
}

/// Ein Messwert in groß, mit seiner Einheit daneben.
///
/// Dreimal fast gleich gebaut gewesen — und dreimal mit demselben Fehler:
/// eine `Row` aus zwei unbeschränkten Texten. Bei großer Schrift wird die
/// Zahl so breit, dass die Einheit rechts hinausläuft.
///
/// `Wrap` statt `Row`: Passt beides nebeneinander, steht es nebeneinander;
/// sonst rutscht die Einheit unter die Zahl. Beides ist lesbar, ein
/// abgeschnittener Wert wäre es nicht.
final class BigReading extends StatelessWidget {
  final String value;

  /// Mit führendem Leerzeichen im Quelltext nicht nötig — der Abstand kommt
  /// aus dem Layout.
  final String unit;
  final Color? valueColor;
  final double size;

  const BigReading({
    super.key,
    required this.value,
    required this.unit,
    this.valueColor,
    this.size = 34,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: Space.sm,
      children: [
        // War Monospace in w300. Beides ist weg: Die Ziffern stehen jetzt
        // ueber Tabellenziffern untereinander (der einzige Grund, der je
        // fuer Mono sprach), und w300 in 34 px sah auf einem Telefon nicht
        // ruhig aus, sondern blass.
        Text(
          value,
          style: readingStyle(context,
              size: size, height: 1.06, color: valueColor ?? p.ink),
        ),
        Padding(
          // Die Einheit sitzt auf der Grundlinie der Zahl, nicht auf ihrer
          // Oberkante — `Wrap` kennt keine Grundlinie, also von Hand.
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(unit,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: p.inkFaint)),
        ),
      ],
    );
  }
}

/// Die beiden Enden einer Skala — links das eine, rechts das andere.
///
/// `Row` mit `spaceBetween` sieht richtig aus, bis die Wörter lang werden:
/// Der Zwischenraum kann nicht negativ werden, und dann läuft das rechte
/// Wort hinaus. Mit je einem `Expanded` und Ausrichtung nach außen bleiben
/// die Enden verankert, und lange Beschriftungen brechen um statt zu
/// verschwinden.
final class ScaleEnds extends StatelessWidget {
  final String low;
  final String high;
  const ScaleEnds({super.key, required this.low, required this.high});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: context.axiom.inkFaint);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(low, style: style)),
        const SizedBox(width: Space.md),
        Expanded(
          child: Text(high, textAlign: TextAlign.right, style: style),
        ),
      ],
    );
  }
}
