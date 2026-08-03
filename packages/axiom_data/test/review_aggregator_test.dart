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
    test('zählt abgefangen und trotzdem ausgeführt', () async {
      await record(EventType.impulseIntercepted,
          payload: {'outcome': 'aborted'});
      await record(EventType.impulseIntercepted,
          payload: {'outcome': 'aborted'});
      await record(EventType.impulseIntercepted,
          payload: {'outcome': 'proceeded'});

      final input = await aggregator.collect(ReviewScope.week);
      expect(input.impulsesIntercepted, 3);
      expect(input.impulsesProceeded, 1);
    });
  });

  group('Regelurteile', () {
    Future<void> decision(
      String ruleId, {
      DecisionResponse? response,
      bool suppressed = false,
      Duration ago = Duration.zero,
    }) async {
      final at = clock.nowUtc().subtract(ago);
      await store.saveDecision(Decision(
        id: newUlid(at),
        at: at,
        ruleId: ruleId,
        action: const Action(ActionType.notify),
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
