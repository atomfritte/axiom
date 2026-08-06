import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
import 'package:test/test.dart';

void main() {
  late FakeClock clock;
  late SqliteEventStore store;
  late ReviewAggregator aggregator;

  setUp(() {
    clock = FakeClock(DateTime(2026, 8, 10, 20));
    store = SqliteEventStore.inMemory(clock: clock);
    aggregator = ReviewAggregator(store: store, clock: clock);
  });
  tearDown(() => store.close());

  Future<void> record(
    EventType type, {
    Map<String, Object?> payload = const {},
    Duration ago = Duration.zero,
  }) async {
    final at = clock.nowUtc().subtract(ago);
    await store.append(Event(
      id: newUlid(at),
      at: at,
      type: type,
      source: EventSource.user,
      payload: payload,
    ));
  }

  group('Zählungen', () {
    test('erfasst Notizen, Aufgaben und Erledigungen', () async {
      await record(EventType.capture, payload: {'text': 'a'});
      await record(EventType.capture, payload: {'text': 'b'});
      await record(EventType.taskCreated, payload: {'task_id': 't1'});
      await record(EventType.taskCompleted, payload: {'task_id': 't1'});

      final input = await aggregator.collect(ReviewScope.week);
      expect(input.captures, 2);
      expect(input.tasksCreated, 1);
      expect(input.tasksCompleted, 1);
    });

    test('ignoriert Ereignisse außerhalb des Zeitraums', () async {
      await record(EventType.capture, ago: const Duration(days: 20));
      await record(EventType.capture, ago: const Duration(days: 2));

      expect((await aggregator.collect(ReviewScope.week)).captures, 1);
      expect((await aggregator.collect(ReviewScope.month)).captures, 2);
    });
  });

  group('Erfassungsquote', () {
    test('rechnet gegen drei Check-ins pro Tag', () async {
      // 7 Tage × 3 = 21 erwartet, 21 geliefert.
      for (var i = 0; i < 21; i++) {
        await record(EventType.checkin,
            payload: {'energy': 3}, ago: Duration(hours: i * 6));
      }
      final input = await aggregator.collect(ReviewScope.week);
      expect(input.checkinRate, greaterThan(0.9));
    });

    test('bleibt bei 1.0 gedeckelt', () async {
      for (var i = 0; i < 40; i++) {
        await record(EventType.checkin, payload: {'energy': 3});
      }
      expect((await aggregator.collect(ReviewScope.week)).checkinRate, 1.0);
    });

    test('halbe Erfassung ergibt etwa die Hälfte', () async {
      for (var i = 0; i < 10; i++) {
        await record(EventType.checkin,
            payload: {'energy': 3}, ago: Duration(hours: i * 12));
      }
      final rate = (await aggregator.collect(ReviewScope.week)).checkinRate;
      expect(rate, inInclusiveRange(0.4, 0.6));
    });
  });

  group('Reiz-Slots', () {
    test('trennt geplant und ungeplant', () async {
      await record(EventType.sensationSlot,
          payload: {'planned': true, 'channel': 'sport'});
      await record(EventType.sensationSlot,
          payload: {'planned': true, 'channel': 'kaelte'});
      await record(EventType.sensationSlot,
          payload: {'planned': false, 'channel': 'scrollen'});

      final input = await aggregator.collect(ReviewScope.week);
      expect(input.plannedSlots, 2);
      expect(input.unplannedSlots, 1);
    });
  });

  group('Impulse', () {
    /// Ein vollständiger Abfang: ein Ereignis beim Start, eines beim Auflösen.
    /// Genau so schreibt es AxiomRuntime.
    Future<void> intercept(String outcome, {Duration ago = Duration.zero}) async {
      await record(EventType.impulseIntercepted,
          payload: {'outcome': 'pending', 'trigger_id': 't1'}, ago: ago);
      await record(EventType.impulseIntercepted,
          payload: {'outcome': outcome, 'trigger_id': 't1'}, ago: ago);
    }

    test('zählt abgefangen und trotzdem ausgeführt', () async {
      await intercept('aborted', ago: const Duration(hours: 3));
      await intercept('aborted', ago: const Duration(hours: 2));
      await intercept('proceeded', ago: const Duration(hours: 1));

      final input = await aggregator.collect(ReviewScope.week);
      expect(input.impulsesIntercepted, 3);
      expect(input.impulsesProceeded, 1);
    });

    test('ein Abfang ist einer, nicht zwei', () async {
      // Zwei Abfänge, beide durchgezogen: 0 von 2 gehalten. Vorher wurden
      // Start- und Auflösungsereignis getrennt gezählt — „2 von 4 gehalten".
      await intercept('proceeded', ago: const Duration(hours: 2));
      await intercept('proceeded', ago: const Duration(hours: 1));

      final input = await aggregator.collect(ReviewScope.week);
      expect(input.impulsesIntercepted, 2);
      expect(input.impulsesProceeded, 2);
    });

    test('ein laufender Abfang gilt nicht als gehalten', () async {
      // Nur das Start-Ereignis, der Cooldown läuft noch. Vorher stand hier
      // „1 von 1 gehalten", bevor überhaupt etwas entschieden war.
      await record(EventType.impulseIntercepted,
          payload: {'outcome': 'pending', 'trigger_id': 't1'});

      final input = await aggregator.collect(ReviewScope.week);
      expect(input.impulsesIntercepted, 0);
      expect(input.impulsesProceeded, 0);
    });
  });

  group('Regelurteile', () {
    Future<void> decision(
      String ruleId, {
      DecisionResponse? response,
      bool suppressed = false,
      Duration ago = Duration.zero,
      ActionType action = ActionType.notify,
    }) async {
      final at = clock.nowUtc().subtract(ago);
      await store.saveDecision(Decision(
        id: newUlid(at),
        at: at,
        ruleId: ruleId,
        action: Action(action),
        explanation: 'weil',
        stateSnapshotId: 's1',
        suppressed: suppressed,
        response: response,
      ));
    }

    test('überwiegend abgelehnte Regel gilt als schwach', () async {
      for (var i = 0; i < 4; i++) {
        await decision('R-050',
            response: DecisionResponse.rejected, ago: Duration(hours: i));
      }
      await decision('R-050',
          response: DecisionResponse.followed, ago: const Duration(hours: 5));

      final input = await aggregator.collect(ReviewScope.week);
      expect(input.weakRules, contains('R-050'));
    });

    test('vereinzelte Ablehnung reicht nicht für ein Urteil', () async {
      await decision('R-050', response: DecisionResponse.rejected);
      final input = await aggregator.collect(ReviewScope.week);
      expect(input.weakRules, isEmpty);
    });

    test('nie gefeuerte Regeln werden erkannt', () async {
      await decision('R-001', response: DecisionResponse.followed);

      final input = await aggregator.collect(
        ReviewScope.week,
        knownRuleIds: ['R-001', 'R-070', 'R-080'],
      );
      // R-001 war aktiv, die anderen beiden nicht.
      expect(input.silentRules, ['R-070', 'R-080']);
    });

    test('ohne bekannte Regeln keine falschen Stummeldungen', () async {
      final input = await aggregator.collect(ReviewScope.week);
      expect(input.silentRules, isEmpty);
    });

    test('dauerhaft verdrängte Regeln zeigen einen Konflikt', () async {
      for (var i = 0; i < 8; i++) {
        await decision('R-090', suppressed: true, ago: Duration(hours: i));
      }
      final input = await aggregator.collect(ReviewScope.week);
      expect(input.suppressedRules, contains('R-090'));
    });

    test('eine Schattenregel ist kein Konflikt', () async {
      // Eine neue Regel läuft ihre sieben Tage als log_only. Jeder Tag legt
      // eine Zeile mit suppressed = 1 an — dieselbe Spalte, die auch „hat die
      // Konfliktauflösung verloren" bedeutet. Vorher meldete der Review
      // deshalb für jede neue Regel einen Konflikt, den es nie gab.
      for (var i = 0; i < 7; i++) {
        await decision('R-140',
            suppressed: true,
            action: ActionType.logOnly,
            ago: Duration(days: i));
      }
      final input = await aggregator.collect(ReviewScope.week);
      expect(input.suppressedRules, isEmpty);
    });

    test('Schattenzeit verdeckt keinen echten Konflikt', () async {
      // Dieselbe Regel läuft erst im Schatten und wird danach live von einer
      // höherrangigen verdrängt. Der Konflikt muss sichtbar bleiben.
      for (var i = 0; i < 3; i++) {
        await decision('R-140',
            suppressed: true,
            action: ActionType.logOnly,
            ago: Duration(days: 4 + i));
      }
      for (var i = 0; i < 5; i++) {
        await decision('R-140', suppressed: true, ago: Duration(hours: i));
      }
      final input = await aggregator.collect(ReviewScope.week);
      expect(input.suppressedRules, contains('R-140'));
    });
  });

  group('Ersparnisschätzung', () {
    test('zählt die Schritte vergangener Zeitanker', () async {
      // Vorher stand im Summanden `EventType.decisionEmitted` — ein
      // Ereignistyp, den niemand schreibt. Der Anteil, den der Kommentar den
      // Zeitankern zuschreibt, war konstant null; K6 wurde damit systematisch
      // zu schlecht und kann den Rückbau laufender Module auslösen.
      final before = (await aggregator.collect(ReviewScope.week))
          .savedMinutesEstimate;

      await store.upsertAnchor(Anchor(
        id: 'a1',
        title: 'Zahnarzt',
        arriveBy: clock.nowLocal().subtract(const Duration(days: 2)),
        travel: const Duration(minutes: 20),
      ));

      final after = (await aggregator.collect(ReviewScope.week))
          .savedMinutesEstimate;
      expect(after, greaterThan(before));
    });

    test('Anker außerhalb des Zeitraums zählen nicht', () async {
      await store.upsertAnchor(Anchor(
        id: 'a2',
        title: 'Elternabend',
        arriveBy: clock.nowLocal().subtract(const Duration(days: 20)),
        travel: const Duration(minutes: 20),
      ));
      await store.upsertAnchor(Anchor(
        id: 'a3',
        title: 'Termin morgen',
        arriveBy: clock.nowLocal().add(const Duration(days: 1)),
        travel: const Duration(minutes: 20),
      ));

      expect(
        (await aggregator.collect(ReviewScope.week)).savedMinutesEstimate,
        0,
      );
    });
  });

  group('Vergleich mit dem Vorzeitraum', () {
    test('ohne Vorgeschichte kein erfundener Vergleichswert', () async {
      await record(EventType.checkin, payload: {'compensation': 3});
      final input = await aggregator.collect(ReviewScope.week);
      expect(input.loadIndexBefore, isNull);
    });

    test('mit Vorgeschichte wird verglichen', () async {
      await record(EventType.checkin,
          payload: {'compensation': 5}, ago: const Duration(days: 10));
      await record(EventType.checkin, payload: {'compensation': 2});

      final input = await aggregator.collect(ReviewScope.week);
      expect(input.loadIndexBefore, isNotNull);
      expect(input.loadIndex, lessThan(input.loadIndexBefore!));
    });
  });

  group('Zusammenspiel mit der ReviewEngine', () {
    test('erzeugt vollständige Kennzahlen aus echten Ereignissen', () async {
      await record(EventType.capture, payload: {'text': 'a'});
      await record(EventType.checkin, payload: {'compensation': 2});
      await store.logUsage('system', const Duration(minutes: 6));

      final metrics = const ReviewEngine()
          .metrics(await aggregator.collect(ReviewScope.week));

      expect(metrics, hasLength(6));
      for (final m in metrics) {
        expect(m.value, isNotEmpty, reason: m.id);
        expect(m.derivation, isNotEmpty, reason: m.id);
      }
    });
  });
}
