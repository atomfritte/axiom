/// Test-Fakes. In-Memory, deterministisch, ohne I/O.
library;

import 'package:axiom_core/axiom_core.dart';

/// Steuerbare Entscheidungs-Historie fuer Cooldown-Tests.
final class FakeHistory implements DecisionHistory {
  final Map<String, DateTime> last;
  final Map<String, int> today;
  final Map<String, int> rejections;
  final int total;

  FakeHistory({
    this.last = const {},
    this.today = const {},
    this.rejections = const {},
    this.total = 0,
  });

  @override
  DateTime? lastFired(String ruleId) => last[ruleId];

  @override
  int firedToday(String ruleId) => today[ruleId] ?? 0;

  @override
  int consecutiveRejections(String ruleId) => rejections[ruleId] ?? 0;

  @override
  int totalInterventionsToday() => total;
}

/// Neutraler Zustand — bewusst mittig, damit Tests gezielt eine Dimension
/// verschieben koennen.
StateVector stateOf({
  int capacity = 60,
  int focusDebt = 0,
  int sensationNeed = 40,
  int loadIndex = 20,
  int regulation = 80,
  int sleepDebt = 10,
  Map<String, double> confidence = const {},
}) =>
    StateVector(
      at: DateTime.utc(2026, 8, 3, 10),
      capacity: capacity,
      focusDebt: focusDebt,
      sensationNeed: sensationNeed,
      loadIndex: loadIndex,
      regulation: regulation,
      sleepDebt: sleepDebt,
      confidence: confidence,
    );

Rule ruleOf({
  required String id,
  Condition? when,
  ActionType action = ActionType.notify,
  int priority = 50,
  Severity severity = Severity.nudge,
  Cooldown? cooldown,
  bool enabled = true,
}) =>
    Rule(
      id: id,
      title: 'Testregel $id',
      rationale: 'Testbegruendung',
      when: when ?? const NumericCompare('capacity', CompareOp.gte, 0),
      then: Action(action),
      priority: priority,
      severity: severity,
      cooldown: cooldown ?? const Cooldown(minInterval: Duration.zero),
      enabled: enabled,
    );

/// Werktag, 10:00 Ortszeit — ausserhalb der Ruhezeiten.
DateTime get testNoon => DateTime(2026, 8, 3, 10);
