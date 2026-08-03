import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
import 'package:test/test.dart';

void main() {
  late FakeClock clock;
  late SqliteEventStore store;

  setUp(() {
    clock = FakeClock(DateTime(2026, 8, 3, 10));
    store = SqliteEventStore.inMemory(clock: clock);
  });

  tearDown(() => store.close());

  Event evt(EventType type, {Map<String, Object?> payload = const {}}) => Event(
        id: newUlid(clock.nowUtc()),
        at: clock.nowUtc(),
        type: type,
        source: EventSource.user,
        payload: payload,
      );

  group('Append-only', () {
    test('speichert und liest Events zurueck', () async {
      await store.append(evt(EventType.capture, payload: {'text': 'Test'}));
      final all = await store.query();
      expect(all, hasLength(1));
      expect(all.single.payload['text'], 'Test');
      expect(all.single.type, EventType.capture);
    });

    test('erhaelt die zeitliche Reihenfolge', () async {
      for (var i = 0; i < 5; i++) {
        await store.append(evt(EventType.capture, payload: {'n': i}));
        clock.advance(const Duration(minutes: 1));
      }
      final all = await store.query();
      expect(all.map((e) => e.payload['n']), [0, 1, 2, 3, 4]);
    });

    test('filtert nach Typ und Zeitfenster', () async {
      await store.append(evt(EventType.capture));
      clock.advance(const Duration(hours: 2));
      await store.append(evt(EventType.checkin, payload: {'energy': 4}));

      expect(await store.query(types: {EventType.checkin}), hasLength(1));
      expect(
        await store.query(from: clock.nowUtc().subtract(const Duration(hours: 1))),
        hasLength(1),
      );
    });

    test('last() liefert das juengste Event des Typs', () async {
      await store.append(evt(EventType.checkin, payload: {'energy': 1}));
      clock.advance(const Duration(hours: 3));
      await store.append(evt(EventType.checkin, payload: {'energy': 5}));

      final last = await store.last(EventType.checkin);
      expect(last!.payload['energy'], 5);
    });

    test('doppelte ID wird abgelehnt', () async {
      final e = evt(EventType.capture);
      await store.append(e);
      expect(() => store.append(e), throwsA(anything));
    });
  });

  group('Reihenfolge', () {
    test('Events derselben Millisekunde behalten die Einfuegereihenfolge', () async {
      // Der FakeClock steht still: alle Events haben denselben Zeitstempel.
      // Ohne monotone Sequenz entschiede der Zufallsanteil der ULID die
      // Sortierung — und der Rebuild koennte task_completed vor
      // task_created einsortieren.
      for (var i = 0; i < 60; i++) {
        await store.append(evt(EventType.capture, payload: {'n': i}));
      }
      final all = await store.query();
      expect(all.map((e) => e.payload['n']), List.generate(60, (i) => i));
    });

    test('last() liefert das zuletzt eingefuegte, nicht das zufaellig groesste',
        () async {
      for (var i = 0; i < 30; i++) {
        await store.append(evt(EventType.checkin, payload: {'n': i}));
      }
      final last = await store.last(EventType.checkin);
      expect(last!.payload['n'], 29);
    });
  });

  group('Rebuild — Projektionen sind verwerfbar', () {
    test('Tasks werden identisch aus events wiederhergestellt', () async {
      await store.append(evt(EventType.taskCreated, payload: {
        'task_id': 't1',
        'title': 'Steuerunterlagen sortieren',
        'ae': 7,
        'salience': 2,
        'stakes': 9,
        'state': 'ready',
      }));
      await store.append(evt(EventType.taskCreated, payload: {
        'task_id': 't2',
        'title': 'Rueckruf Werkstatt',
        'ae': 2,
        'salience': 3,
        'stakes': 5,
        'state': 'ready',
      }));
      await store.append(evt(EventType.taskCompleted, payload: {
        'task_id': 't2',
        'duration_min': 4,
      }));

      await store.rebuildProjections();
      final afterFirst = await store.tasks();

      // Projektionen wegwerfen und erneut aufbauen.
      await store.rebuildProjections();
      final afterSecond = await store.tasks();

      expect(afterFirst.map((t) => t.id).toSet(), {'t1', 't2'});
      expect(
        afterFirst.firstWhere((t) => t.id == 't2').state,
        TaskState.done,
      );
      expect(
        afterSecond.map((t) => '${t.id}:${t.state.name}:${t.activationEnergy}'),
        afterFirst.map((t) => '${t.id}:${t.state.name}:${t.activationEnergy}'),
      );
    });
  });

  group('Meta-Guard (M12)', () {
    test('summiert nur budgetrelevante Nutzung', () async {
      await store.logUsage('system', const Duration(minutes: 5));
      await store.logUsage('capture', const Duration(minutes: 3),
          countsToBudget: false);
      await store.logUsage('state', const Duration(minutes: 2));

      final used = await store.usageToday(clock.nowLocal());
      expect(used, const Duration(minutes: 7));
    });

    test('Nutzung von gestern zaehlt nicht mehr', () async {
      await store.logUsage('system', const Duration(minutes: 10));
      clock.advance(const Duration(days: 1));
      expect(await store.usageToday(clock.nowLocal()), Duration.zero);
    });
  });

  group('DecisionHistory', () {
    Decision decision(String ruleId, {DecisionResponse? response}) => Decision(
          id: newUlid(clock.nowUtc()),
          at: clock.nowUtc(),
          ruleId: ruleId,
          action: const Action(ActionType.notify),
          explanation: 'weil',
          stateSnapshotId: 's1',
          response: response,
        );

    test('zaehlt heutige Feuerungen je Regel', () async {
      await store.saveDecision(decision('R-050'));
      clock.advance(const Duration(hours: 1));
      await store.saveDecision(decision('R-050'));
      await store.saveDecision(decision('R-070'));

      final history = store.historyAt(clock.nowLocal());
      expect(history.firedToday('R-050'), 2);
      expect(history.firedToday('R-070'), 1);
      expect(history.totalInterventionsToday(), 3);
    });

    test('zaehlt Ablehnungen in Folge und setzt bei Befolgung zurueck',
        () async {
      await store.saveDecision(
          decision('R-050', response: DecisionResponse.rejected));
      clock.advance(const Duration(hours: 1));
      await store.saveDecision(
          decision('R-050', response: DecisionResponse.rejected));

      expect(store.historyAt(clock.nowLocal()).consecutiveRejections('R-050'), 2);

      clock.advance(const Duration(hours: 1));
      await store.saveDecision(
          decision('R-050', response: DecisionResponse.followed));
      expect(store.historyAt(clock.nowLocal()).consecutiveRejections('R-050'), 0);
    });

    test('unterdrueckte Entscheidungen zaehlen nicht als Feuerung', () async {
      await store.saveDecision(Decision(
        id: newUlid(clock.nowUtc()),
        at: clock.nowUtc(),
        ruleId: 'R-099',
        action: const Action(ActionType.notify),
        explanation: 'verdraengt',
        stateSnapshotId: 's1',
        suppressed: true,
      ));
      expect(store.historyAt(clock.nowLocal()).firedToday('R-099'), 0);
    });

    test('ruleStats berechnet die Befolgungsquote', () async {
      await store.saveDecision(
          decision('R-050', response: DecisionResponse.followed));
      clock.advance(const Duration(minutes: 1));
      await store.saveDecision(
          decision('R-050', response: DecisionResponse.rejected));

      final stats = await store.ruleStats(
        since: clock.nowUtc().subtract(const Duration(days: 1)),
      );
      final r50 = stats.firstWhere((s) => s.ruleId == 'R-050');
      expect(r50.fires, 2);
      expect(r50.followRate, closeTo(0.5, 0.001));
    });
  });

  group('Settings', () {
    test('schreibt und liest', () {
      expect(store.setting('onboarding_done'), isNull);
      store.setSetting('onboarding_done', 'true');
      expect(store.setting('onboarding_done'), 'true');
      store.setSetting('onboarding_done', 'false');
      expect(store.setting('onboarding_done'), 'false');
    });
  });

  group('ULID', () {
    test('ist zeitlich sortierbar', () {
      final a = newUlid(DateTime.utc(2026, 8, 3, 10));
      final b = newUlid(DateTime.utc(2026, 8, 3, 11));
      expect(a.compareTo(b), lessThan(0));
      expect(a.length, 26);
    });

    test('kollidiert nicht bei gleichem Zeitstempel', () {
      final at = DateTime.utc(2026, 8, 3, 10);
      final ids = List.generate(500, (_) => newUlid(at)).toSet();
      expect(ids, hasLength(500));
    });
  });
}
