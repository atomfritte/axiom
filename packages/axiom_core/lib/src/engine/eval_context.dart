/// Standard-EvalContext: verbindet StateVector, Clock und Event-Statistiken.
library;

import '../domain/condition.dart';
import '../domain/state_vector.dart';
import '../domain/task.dart';
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

  /// Der gerade gesetzte Ort, oder null.
  ///
  /// Gehört wie [metaMinutesToday] hierher und nicht in den Zustandsvektor:
  /// Das ist keine abgeleitete Größe über den Nutzer, sondern eine Angabe
  /// über die Umgebung — gesetzt vom Nutzer selbst oder von einer
  /// Geräteroutine. [D2]
  final String? place;

  /// Wie viele Erfassungen noch unbeantwortet im Eingang liegen.
  ///
  /// Gehört wie [metaMinutesToday] hierher: Eine Notiz ist kein Zustand des
  /// Nutzers, sondern ein Posten in der App.
  final int inboxCount;

  /// Alter der ältesten unbeantworteten Erfassung, in Stunden.
  ///
  /// Die wichtigere der beiden Zahlen. Zehn Notizen von heute Vormittag sind
  /// harmlos — eine von vor drei Wochen ist der Beleg dafür, dass der Eingang
  /// nicht mehr angesehen wird. Genau davor soll eine Regel warnen können,
  /// und zwar bevor der Bestand unüberschaubar wird. [D9]
  ///
  /// Ohne Notiz **0**, nicht [kNoDeadlineHours] — und das ist der Punkt.
  ///
  /// Bei Fristen heißt „keine" unendlich weit weg, also eine große Zahl.
  /// Hier kehrt sich das um: „keine Notiz" heißt kein Alter, also null. Mit
  /// der großen Zahl hätte jede Regel der Form `gte: 72` gefeuert, wenn der
  /// Eingang **leer** ist — genau dann, wenn es nichts zu tun gibt. Der
  /// Test zu R-150 hält das fest.
  final num inboxOldestHours;

  /// Stunden bis zur Frist der am knappsten dastehenden offenen Aufgabe.
  ///
  /// Ohne Frist [kNoDeadlineHours] — nie null, sonst wirft die Bedingung.
  final num hoursToDeadline;

  /// Was von der Zeit bis zu dieser Frist übrig bleibt, wenn man den Anlauf
  /// abzieht (`taskRunway`). Wird sie negativ, ist der Moment, in dem
  /// Anfangen noch gereicht hätte, bereits vorbei. [D4]
  final num deadlineSlackHours;

  const RuntimeContext({
    this.activeSlot = 'none',
    this.minutesSinceByEvent = const {},
    this.countTodayByEvent = const {},
    this.metaMinutesToday = 0,
    this.inboxCount = 0,
    this.inboxOldestHours = 0,
    this.place,
    this.hoursToDeadline = kNoDeadlineHours,
    this.deadlineSlackHours = kNoDeadlineHours,
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
  num? numeric(String variable) => switch (variable) {
        'meta_minutes_today' => runtime.metaMinutesToday,
        'inbox_count' => runtime.inboxCount,
        'inbox_oldest_hours' => runtime.inboxOldestHours,
        'hours_to_deadline' => runtime.hoursToDeadline,
        'deadline_slack_hours' => runtime.deadlineSlackHours,
        _ => state.numeric(variable),
      };

  @override
  String? symbolic(String variable) => switch (variable) {
        'load_level' => state.loadLevel.name.toUpperCase(),
        'active_slot' => runtime.activeSlot,
        'weekday' => _weekdayName(clock.nowLocal().weekday),
        // Ohne gesetzten Ort ein Wert statt null: Eine unaufloesbare Variable
        // bricht die Auswertung ab (Fail-Fast), und „gerade kein Ort" ist
        // kein Fehler, sondern der Normalfall.
        'place' => _placeOrNone(runtime.place),
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

  static String _placeOrNone(String? place) {
    final trimmed = place?.trim();
    return trimmed == null || trimmed.isEmpty ? kNoPlace : trimmed;
  }

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
