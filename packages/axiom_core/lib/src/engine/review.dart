/// Review-Kadenz — M11.
///
/// Format ist bewusst ein Ops-Review, kein Tagebuch: Metriken, Abweichungen,
/// Regeländerungen. Dasselbe Vorgehen, das dieses Profil beruflich
/// akzeptiert. Ein „Gefühlstagebuch" wird nicht geführt, ein Wochenbericht
/// schon — identischer Inhalt, anderes Framing, und das Framing entscheidet
/// über die Adhärenz. [D10, D12]
///
/// Der harte Zeitdeckel ist Teil des Konzepts, keine Bequemlichkeit: Ein
/// Review ohne Grenze wird zur Meta-Work-Fläche (D3).
library;

import 'package:meta/meta.dart';

import '../domain/phrase.dart';

enum ReviewScope {
  day(Duration(minutes: 2), 'Tag'),
  week(Duration(minutes: 15), 'Woche'),
  month(Duration(minutes: 30), 'Monat'),
  quarter(Duration(minutes: 60), 'Quartal');

  const ReviewScope(this.timeCap, this.label);

  /// Erzwungene Obergrenze. Danach schließt der Review.
  final Duration timeCap;
  final String label;

  /// Nur im Wochen-Review dürfen Regeln geändert werden (M12).
  bool get allowsRuleChanges => this == week || this == month || this == quarter;

  /// Module aktivieren geht nur monatlich oder seltener.
  bool get allowsModuleChanges => this == month || this == quarter;
}

/// Eine Kennzahl mit Richtung und Konsequenz.
@immutable
final class Metric {
  final String id;
  final String label;

  /// Der Zahlenwert als Quelltext mit Platzhaltern.
  ///
  /// Getrennt gehalten, weil sonst nicht uebersetzbar: Aus „57 %  (12
  /// gesamt)" liessen sich die Zahlen nur mit Raten zurueckgewinnen.
  final Phrase valueSource;

  /// Wo die Zahl herkommt. Ohne das ist sie nicht überprüfbar (G2).
  final String derivation;

  /// Bewegung gegenüber dem Vorzeitraum. Null, wenn es keinen gibt.
  ///
  /// Beschreibt die **Richtung der Zahl**, nicht ihre Bewertung. Ob eine
  /// steigende Zahl gut oder schlecht ist, hängt von der Kennzahl ab —
  /// bei „Messpunkte erfasst" ist mehr besser, bei „Kompensationslast"
  /// weniger. Ein Pfeil, der beides bedeuten soll, verwirrt mehr als er
  /// erklärt.
  final MetricTrend? trend;

  /// Braucht diese Zahl Aufmerksamkeit? Trägt die Bewertung, getrennt von
  /// der Richtung.
  final bool needsAttention;

  /// Was zu tun ist, wenn die Zahl aus dem Rahmen fällt.
  final String? consequence;

  const Metric({
    required this.id,
    required this.label,
    required Phrase value,
    required this.derivation,
    this.trend,
    this.needsAttention = false,
    this.consequence,
  }) : valueSource = value;

  /// Der fertige deutsche Wert.
  String get value => valueSource.text;
}

/// Richtung der Zahl gegenüber dem Vorzeitraum — ohne Wertung.
enum MetricTrend { up, flat, down }

/// Rohwerte für die Kennzahlen. Aggregation passiert in `axiom_data`.
@immutable
final class ReviewInputs {
  /// Anteil erledigter Check-ins im Zeitraum, 0..1.
  final double checkinRate;

  /// `load_index` im Mittel, und im Vorzeitraum.
  final int loadIndex;
  final int? loadIndexBefore;

  /// Minuten in AXIOM, die aufs Budget zählen.
  final int metaMinutes;

  /// Grob geschätzte Zeit, die das System erspart hat.
  /// Bewusst grob: Eine Scheingenauigkeit wäre hier schlimmer als eine
  /// ehrliche Schätzung.
  final int savedMinutesEstimate;

  /// Erfasste Notizen und daraus entstandene Aufgaben.
  final int captures;
  final int tasksCreated;
  final int tasksCompleted;

  /// Geplante gegen ungeplante Reiz-Slots.
  final int plannedSlots;
  final int unplannedSlots;

  /// Abgefangene Impulse, die trotzdem ausgeführt wurden.
  final int impulsesIntercepted;
  final int impulsesProceeded;

  /// Regeln, deren Befolgungsquote unter 40 % liegt.
  final List<String> weakRules;

  /// Regeln, die im Zeitraum kein einziges Mal gefeuert haben.
  final List<String> silentRules;

  /// Regeln, die regelmäßig von höherrangigen verdrängt werden.
  final List<String> suppressedRules;

  const ReviewInputs({
    this.checkinRate = 0,
    this.loadIndex = 0,
    this.loadIndexBefore,
    this.metaMinutes = 0,
    this.savedMinutesEstimate = 0,
    this.captures = 0,
    this.tasksCreated = 0,
    this.tasksCompleted = 0,
    this.plannedSlots = 0,
    this.unplannedSlots = 0,
    this.impulsesIntercepted = 0,
    this.impulsesProceeded = 0,
    this.weakRules = const [],
    this.silentRules = const [],
    this.suppressedRules = const [],
  });
}

/// Berechnet die Kennzahlen K1–K6 aus docs/06-METRIKEN.md.
final class ReviewEngine {
  const ReviewEngine();

  List<Metric> metrics(ReviewInputs input) => [
        _checkins(input),
        _load(input),
        _capture(input),
        _sensation(input),
        _impulse(input),
        _metaWork(input),
      ];

  Metric _checkins(ReviewInputs i) => Metric(
        id: 'checkins',
        label: 'Messpunkte erfasst',
        value: Phrase('{0} %', [(i.checkinRate * 100).round()]),
        derivation: 'Erledigte Check-ins geteilt durch geplante.',
        needsAttention: i.checkinRate < 0.8,
        consequence: i.checkinRate < 0.8
            ? 'Unter 80 %: Der Zustandsvektor wird ungenau, und Regeln '
                'feuern auf veralteten Werten. Bevor etwas dazukommt, muss '
                'die Erfassung leichter werden.'
            : null,
      );

  Metric _load(ReviewInputs i) {
    final before = i.loadIndexBefore;
    final delta = before == null ? null : i.loadIndex - before;
    return Metric(
      id: 'load',
      label: 'Kompensationslast',
      value: delta == null
          ? Phrase('{0}', [i.loadIndex])
          : Phrase('{0}  ({1}{2})',
              [i.loadIndex, delta >= 0 ? '+' : '', delta]),
      derivation: 'Gleitender Mittelwert aus Schlafschuld, Erholungsqualität, '
          'Kompensationsaufwand, Reizbarkeit und Rückzug.',
      trend: delta == null
          ? null
          : delta < -3
              ? MetricTrend.down
              : delta > 3
                  ? MetricTrend.up
                  : MetricTrend.flat,
      needsAttention: i.loadIndex >= 55,
      consequence: i.loadIndex >= 70
          ? 'Ab 70 nichts Neues zusätzlich aufnehmen. Bestehendes eher '
              'abgeben als erweitern.'
          : null,
    );
  }

  Metric _capture(ReviewInputs i) => Metric(
        id: 'capture',
        label: 'Erfasst und einsortiert',
        value: Phrase('{0} erfasst · {1} übernommen · {2} erledigt',
            [i.captures, i.tasksCreated, i.tasksCompleted]),
        derivation: 'Gezählte Ereignisse im Zeitraum.',
        needsAttention: i.captures > 0 && i.tasksCreated == 0,
        consequence: i.captures > 0 && i.tasksCreated == 0
            ? 'Nichts einsortiert. Der Eingang läuft voll, und ein voller '
                'Eingang wird irgendwann gar nicht mehr geöffnet.'
            : null,
      );

  Metric _sensation(ReviewInputs i) {
    final total = i.plannedSlots + i.unplannedSlots;
    final share = total == 0 ? null : i.plannedSlots / total;
    return Metric(
      id: 'sensation',
      label: 'Reizbedarf geplant gedeckt',
      value: share == null
          ? const Phrase('keine Daten')
          : Phrase('{0} %  ({1} gesamt)',
              [(share * 100).round(), total]),
      derivation: 'Geplante Slots geteilt durch alle Slots.',
      needsAttention: share != null && share < 0.7,
      consequence: share != null && share < 0.7
          ? 'Unter 70 %: Der Bedarf deckt sich überwiegend ungeplant — und '
              'ungeplant heißt meist über den schnellsten, nicht den besten '
              'Kanal.'
          : null,
    );
  }

  Metric _impulse(ReviewInputs i) => Metric(
        id: 'impulse',
        label: 'Impulse abgefangen',
        value: i.impulsesIntercepted == 0
            ? const Phrase('keine')
            : Phrase('{0} von {1} gehalten', [
                i.impulsesIntercepted - i.impulsesProceeded,
                i.impulsesIntercepted,
              ]),
        derivation: 'Cooldowns, die abgelaufen sind, ohne dass die Handlung '
            'ausgeführt wurde.',
        consequence: null,
      );

  /// K6 — das Abbruchkriterium des gesamten Projekts.
  Metric _metaWork(ReviewInputs i) {
    final ratio = i.savedMinutesEstimate == 0
        ? null
        : i.metaMinutes / i.savedMinutesEstimate;
    return Metric(
      id: 'meta',
      label: 'Zeit im System gegen Zeit gespart',
      value: ratio == null
          ? Phrase('{0} min im System', [i.metaMinutes])
          : Phrase('{0} min : {1} min ({2})', [
              i.metaMinutes,
              i.savedMinutesEstimate,
              ratio.toStringAsFixed(2),
            ]),
      derivation: 'Erfasste Nutzungszeit gegen deine eigene Schätzung.',
      needsAttention: ratio != null && ratio > 1.0,
      consequence: ratio != null && ratio > 1.0
          ? 'Über 1,0: AXIOM kostet mehr Zeit, als es einbringt. Dann wird '
              'zurückgebaut, nicht optimiert — Module abschalten, Regeln '
              'streichen.'
          : null,
    );
  }

  /// Regeln, über die im Wochen-Review entschieden werden sollte.
  ///
  /// Ohne diesen Punkt wächst das Regelwerk monoton, und ein monoton
  /// wachsendes Regelwerk ist die Meta-Work-Falle in Reinform.
  List<RuleVerdict> ruleVerdicts(ReviewInputs i) => [
        for (final id in i.weakRules)
          RuleVerdict(
            ruleId: id,
            verdict: RuleAction.retire,
            reason: 'Wird überwiegend abgelehnt. Eine Regel, die nervt, '
                'entwertet auch die anderen.',
          ),
        for (final id in i.silentRules)
          RuleVerdict(
            ruleId: id,
            verdict: RuleAction.widen,
            reason: 'Hat nie gefeuert. Entweder ist die Bedingung zu eng '
                'oder die Regel überflüssig.',
          ),
        for (final id in i.suppressedRules)
          RuleVerdict(
            ruleId: id,
            verdict: RuleAction.resolveConflict,
            reason: 'Wird regelmäßig von höherrangigen Regeln verdrängt — '
                'ein Konflikt, den man sonst nie bemerkt.',
          ),
      ];
}

enum RuleAction { retire, widen, resolveConflict }

@immutable
final class RuleVerdict {
  final String ruleId;
  final RuleAction verdict;
  final String reason;

  const RuleVerdict({
    required this.ruleId,
    required this.verdict,
    required this.reason,
  });
}
