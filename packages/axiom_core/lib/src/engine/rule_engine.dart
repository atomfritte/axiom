/// Rule Engine — wertet das gesamte Regelwerk gegen einen Zustand aus.
///
///   evaluate(state, ruleset) -> decision
///
/// Reine Funktion. Kein Zufall, keine Uhrzeitabfrage, kein I/O. Gleicher
/// Zustand plus gleiches Regelwerk ergibt immer dieselbe Entscheidung
/// (ADR-0003).
library;

import 'package:meta/meta.dart';

import '../domain/condition.dart';
import '../domain/decision.dart';
import '../domain/rule.dart';
import '../ports/ports.dart';

/// Warum eine Regel nicht gefeuert hat. Fuer Diagnose und Wochenreview —
/// eine Regel, die nie feuert, soll auffallen, nicht verschwinden.
enum SkipReason {
  disabled,
  conditionFalse,
  cooldownActive,
  dailyLimitReached,
  globalLimitReached,
  hourlyLimitReached,
  quietHours,
  lowConfidence,
}

@immutable
final class FiredRule {
  final Rule rule;
  const FiredRule(this.rule);
}

@immutable
final class SkippedRule {
  final Rule rule;
  final SkipReason reason;
  const SkippedRule(this.rule, this.reason);
}

@immutable
final class EvaluationResult {
  final List<FiredRule> fired;
  final List<SkippedRule> skipped;
  const EvaluationResult(this.fired, this.skipped);
}

/// Systemweite Obergrenzen aus `rules/core/limits.yaml`.
///
/// Ohne globales Limit summieren sich einzeln vernuenftige Regeln zu einer
/// Benachrichtigungsflut — der haeufigste Grund, warum ADHS-Apps nach drei
/// Wochen stummgeschaltet werden. Und eine stummgeschaltete App ist eine
/// geloeschte App mit Extraschritten. (R2)
@immutable
final class GlobalLimits {
  final int maxInterventionsPerDay;

  /// Burst-Bremse innerhalb des Tagesbudgets: Auch wenn von 12 Interventionen
  /// erst drei verbraucht sind, sollen nicht vier davon in zwanzig Minuten
  /// liegen. Der Cooldown einer Regel sieht das nicht — er kennt nur sich
  /// selbst; gedeckelt wird hier das Durchrotieren *verschiedener* Regeln. (R2)
  final int maxNotificationsPerHour;

  final int quietFromMinutes;
  final int quietToMinutes;

  /// Regeln unterhalb dieser Konfidenz feuern nicht: lieber schweigen als
  /// raten. (R8)
  final double minConfidence;

  const GlobalLimits({
    this.maxInterventionsPerDay = 12,
    this.maxNotificationsPerHour = 2,
    this.quietFromMinutes = 23 * 60,
    this.quietToMinutes = 6 * 60 + 30,
    this.minConfidence = 0.4,
  });

  bool isQuietHour(DateTime local) {
    final m = local.hour * 60 + local.minute;
    return quietFromMinutes <= quietToMinutes
        ? m >= quietFromMinutes && m <= quietToMinutes
        : m >= quietFromMinutes || m <= quietToMinutes;
  }
}

final class RuleEngine {
  final GlobalLimits limits;
  const RuleEngine({this.limits = const GlobalLimits()});

  /// Wertet alle Regeln aus. Trifft KEINE Auswahl — das macht der
  /// [DecisionResolver].
  EvaluationResult evaluate({
    required List<Rule> rules,
    required EvalContext ctx,
    required DecisionHistory history,
    required DateTime nowLocal,
  }) {
    final fired = <FiredRule>[];
    final skipped = <SkippedRule>[];

    final globalExhausted =
        history.totalInterventionsToday() >= limits.maxInterventionsPerDay;

    // Einmal vor der Schleife, nicht je Regel: Die Historie aendert sich
    // waehrend einer Auswertung nicht, und ein Wert, der von der
    // Bearbeitungsreihenfolge abhinge, waere nicht mehr deterministisch
    // (ADR-0003).
    final hourlyExhausted =
        _firedWithinLastHour(rules, history, nowLocal) >=
            limits.maxNotificationsPerHour;

    // Deterministische Reihenfolge unabhaengig von der Ladereihenfolge.
    final ordered = [...rules]..sort((a, b) => a.id.compareTo(b.id));

    for (final rule in ordered) {
      if (!rule.enabled) {
        skipped.add(SkippedRule(rule, SkipReason.disabled));
        continue;
      }

      if (!rule.when.eval(ctx)) {
        skipped.add(SkippedRule(rule, SkipReason.conditionFalse));
        continue;
      }

      // SHADOW-Regeln umgehen alle Limits: Sie erzeugen keine Ausgabe,
      // sondern nur einen Log-Eintrag zur Kalibrierung.
      if (rule.isShadow) {
        fired.add(FiredRule(rule));
        continue;
      }

      final skip = _limitCheck(
        rule,
        ctx,
        history,
        nowLocal,
        globalExhausted: globalExhausted,
        hourlyExhausted: hourlyExhausted,
      );
      if (skip != null) {
        skipped.add(SkippedRule(rule, skip));
        continue;
      }

      fired.add(FiredRule(rule));
    }

    return EvaluationResult(fired, skipped);
  }

  /// Wie viele Regeln haben in der letzten Stunde tatsaechlich etwas
  /// ausgespielt?
  ///
  /// Gezaehlt wird ueber die Regelliste statt ueber einen eigenen Zaehler,
  /// weil die Historie je Regel genau einen Zeitpunkt fuehrt: `lastFired` ist
  /// der Zeitpunkt der letzten *nicht* unterdrueckten Entscheidung, also genau
  /// dessen, was der Nutzer zu sehen bekam. Verdraengte Verlierer und
  /// Schattenregeln zaehlen damit nicht mit, und das ist richtig so — sie
  /// erscheinen nirgends.
  ///
  /// Bewusste Untergrenze: Eine Regel, die innerhalb derselben Stunde zweimal
  /// gefeuert hat, zaehlt hier einmal. Dagegen wirkt ihr eigener Cooldown; die
  /// Stundengrenze deckelt das, was der Cooldown prinzipiell nicht sehen kann.
  int _firedWithinLastHour(
    List<Rule> rules,
    DecisionHistory history,
    DateTime nowLocal,
  ) {
    const window = Duration(hours: 1);
    var count = 0;
    for (final rule in rules) {
      final last = history.lastFired(rule.id);
      // Nicht `difference().abs()`: Ein in der Zukunft liegender Zeitstempel
      // (Zeitumstellung, manuell gestellte Uhr) darf die Bremse nicht
      // dauerhaft anziehen.
      if (last != null &&
          !last.isAfter(nowLocal) &&
          nowLocal.difference(last) < window) {
        count++;
      }
    }
    return count;
  }

  SkipReason? _limitCheck(
    Rule rule,
    EvalContext ctx,
    DecisionHistory history,
    DateTime nowLocal, {
    required bool globalExhausted,
    required bool hourlyExhausted,
  }) {
    // Konfidenz: bei zu alten Daten wird nicht geraten.
    for (final variable in rule.when.referencedVariables) {
      if (variable.startsWith('event:') || variable == 'time_between') continue;
      if (ctx.confidenceOf(variable) < limits.minConfidence) {
        return SkipReason.lowConfidence;
      }
    }

    // Nur enforce darf Ruhezeiten durchbrechen — und enforce gibt es nur fuer
    // Regeln, die der Nutzer im ruhigen Zustand selbst autorisiert hat.
    if (rule.severity != Severity.enforce && limits.isQuietHour(nowLocal)) {
      return SkipReason.quietHours;
    }

    if (globalExhausted && rule.severity != Severity.enforce) {
      return SkipReason.globalLimitReached;
    }

    // Vorher wurde `maxNotificationsPerHour` nur geparst und im
    // Systeminspektor als geltende Grenze angezeigt, nie geprueft. Folge:
    // Verdraengte Regeln werden mit `suppressed` gespeichert und bekommen
    // deshalb kein `lastFired` — beim naechsten Durchlauf ruecken sie
    // ungebremst nach. Vier verschiedene Aufforderungen in zwanzig Minuten,
    // waehrend der Bildschirm „Meldungen pro Stunde: 2" behauptete. Eine
    // angezeigte Grenze, die nicht greift, ist schlimmer als keine (G2). (R2)
    if (hourlyExhausted && rule.severity != Severity.enforce) {
      return SkipReason.hourlyLimitReached;
    }

    final maxPerDay = rule.cooldown.maxPerDay;
    if (maxPerDay != null && history.firedToday(rule.id) >= maxPerDay) {
      return SkipReason.dailyLimitReached;
    }

    final last = history.lastFired(rule.id);
    if (last != null) {
      final required = rule.cooldown
          .effectiveInterval(history.consecutiveRejections(rule.id));
      if (nowLocal.difference(last) < required) {
        return SkipReason.cooldownActive;
      }
    }

    return null;
  }
}

/// Loest Konflikte auf und liefert GENAU EINE Entscheidung.
///
/// Klassische Apps zeigen eine Liste und delegieren die Auswahl an den
/// Nutzer — genau die Entscheidung, die bei niedriger Kapazitaet am
/// teuersten ist. AXIOM entscheidet und begruendet. (G1)
final class DecisionResolver {
  const DecisionResolver();

  /// Sortierung: (severity DESC, priority DESC, rule_id ASC).
  /// Total, stabil, ohne Zufall.
  ///
  /// Verlierer werden als `suppressed` protokolliert, nicht verworfen —
  /// chronisch unterdrueckte Regeln zeigen Regelkonflikte, die man sonst
  /// nie bemerkt.
  ({Decision? winner, List<Decision> suppressed}) resolve({
    required List<FiredRule> fired,
    required DateTime at,
    required String stateSnapshotId,
    required String Function(Rule rule) explain,
    required String Function() nextId,
  }) {
    final live = fired.where((f) => !f.rule.isShadow).toList()
      ..sort(_byRank);

    if (live.isEmpty) {
      return (winner: null, suppressed: const []);
    }

    Decision build(Rule rule, {required bool suppressed}) => Decision(
          id: nextId(),
          at: at,
          ruleId: rule.id,
          action: rule.then,
          explanation: explain(rule),
          stateSnapshotId: stateSnapshotId,
          suppressed: suppressed,
        );

    return (
      winner: build(live.first.rule, suppressed: false),
      suppressed: live
          .skip(1)
          .map((f) => build(f.rule, suppressed: true))
          .toList(growable: false),
    );
  }

  static int _byRank(FiredRule a, FiredRule b) {
    final bySeverity = b.rule.severity.rank.compareTo(a.rule.severity.rank);
    if (bySeverity != 0) return bySeverity;
    final byPriority = b.rule.priority.compareTo(a.rule.priority);
    if (byPriority != 0) return byPriority;
    return a.rule.id.compareTo(b.rule.id);
  }
}
