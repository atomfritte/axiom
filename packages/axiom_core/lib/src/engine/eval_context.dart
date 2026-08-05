/// Standard-EvalContext: verbindet StateVector, Clock und Event-Statistiken.
library;

import '../domain/condition.dart';
import '../domain/state_vector.dart';
import '../ports/ports.dart';

/// Kontextinformationen, die nicht im StateVector stehen.
final class RuntimeContext {
  /// Laufender Slot: 'focus' | 'sensation' | 'none'.
  final String activeSlot;

  /// Minuten seit dem letzten Event je Typ (snake_case Typname).
  final Map<String, int> minutesSinceByEvent;

  /// Anzahl Events je Typ seit lokalem Tagesbeginn.
  final Map<String, int> countTodayByEvent;

  /// Heute in AXIOM verbrachte Minuten, ohne Erfassung.
  ///
  /// Gehört hierher und nicht in den Zustandsvektor: Das ist kein
  /// abgeleiteter Zustand des Nutzers, sondern eine Beobachtung über die
  /// App selbst. G4 braucht sie trotzdem als Bedingung — ohne sie kann
  /// keine Regel formulieren, dass das Budget aufgebraucht ist, und die
  /// Selbstbegrenzung bliebe eine Absichtserklärung.
  final int metaMinutesToday;

  const RuntimeContext({
    this.activeSlot = 'none',
    this.minutesSinceByEvent = const {},
    this.countTodayByEvent = const {},
    this.metaMinutesToday = 0,
  });
}

final class StateEvalContext implements EvalContext {
  final StateVector state;
  final Clock clock;
  final RuntimeContext runtime;

  const StateEvalContext({
    required this.state,
    required this.clock,
    this.runtime = const RuntimeContext(),
  });

  @override
  num? numeric(String variable) => variable == 'meta_minutes_today'
      ? runtime.metaMinutesToday
      : state.numeric(variable);

  @override
  String? symbolic(String variable) => switch (variable) {
        'load_level' => state.loadLevel.name.toUpperCase(),
        'active_slot' => runtime.activeSlot,
        'weekday' => _weekdayName(clock.nowLocal().weekday),
        _ => null,
      };

  @override
  DateTime get localNow => clock.nowLocal();

  @override
  int? minutesSince(String eventType) => runtime.minutesSinceByEvent[eventType];

  @override
  int countToday(String eventType) => runtime.countTodayByEvent[eventType] ?? 0;

  @override
  double confidenceOf(String variable) => state.confidenceOf(variable);

  static String _weekdayName(int weekday) => const [
        'mon',
        'tue',
        'wed',
        'thu',
        'fri',
        'sat',
        'sun',
      ][weekday - 1];
}
