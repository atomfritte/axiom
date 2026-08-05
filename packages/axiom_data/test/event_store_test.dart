import 'dart:io';

import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  _schemaGuard();
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

    test('der Ort ueberlebt einen Wiederaufbau', () async {
      // Ohne `place` im Ereignis kaeme die Aufgabe ortsungebunden zurueck —
      // und wuerde ueberall vorgeschlagen. Ein Wiederaufbau, der den Zustand
      // veraendert, ist die teuerste Art von Fehler in einem System, dessen
      // Projektionen aus dem Ereignisstrom entstehen.
      await store.append(evt(EventType.taskCreated, payload: {
        'task_id': 't3',
        'title': 'Dichtungsring kaufen',
        'ae': 3,
        'salience': 4,
        'stakes': 6,
        'state': 'ready',
        'place': 'Baumarkt',
      }));

      await store.rebuildProjections();
      final rebuilt = (await store.tasks()).single;
      expect(rebuilt.place, 'Baumarkt');
      expect(rebuilt.isStartable(100, atPlace: 'Büro'), isFalse);
      expect(rebuilt.isStartable(100), isTrue,
          reason: 'Ohne gesetzten Ort wird nichts unterdrueckt');
    });

    test('der Ort ueberlebt auch einen Zustandswechsel in der Projektion',
        () async {
      await store.upsertTask(const Task(
        id: 't4',
        title: 'Regal aufbauen',
        activationEnergy: 4,
        salience: 5,
        stakes: 5,
        place: 'Zuhause',
        state: TaskState.ready,
      ));
      final loaded = (await store.tasks()).single;
      await store.upsertTask(loaded.copyWith(state: TaskState.active));
      expect((await store.tasks()).single.place, 'Zuhause');
    });

    test('eine Zerlegung überlebt den Wiederaufbau', () async {
      // Der teuerste Datenverlust, den es hier gab: Teilschritte standen
      // nur in der Projektion, nie im Ereignisstrom. Ein Wiederaufbau —
      // auch der nach einem Vault-Import — hat sie ersatzlos verworfen.
      // Zerlegen ist der haeufigste Weg, wie eine Aufgabe in Reichweite
      // kommt; sie danach nicht mehr zu finden ist das Gegenteil davon.
      await store.append(evt(EventType.taskCreated, payload: {
        'task_id': 'p1',
        'title': 'Steuer',
        'ae': 8,
        'state': 'ready',
      }));
      for (final (id, title) in [('c1', 'Ordner holen'), ('c2', 'Sortieren')]) {
        await store.append(evt(EventType.taskCreated, payload: {
          'task_id': id,
          'title': title,
          'ae': 2,
          'state': 'ready',
          'parent_id': 'p1',
        }));
      }
      await store.append(evt(EventType.taskSplit, payload: {
        'parent_id': 'p1',
        'child_ids': ['c1', 'c2'],
      }));

      await store.rebuildProjections();
      final tasks = await store.tasks();

      expect(tasks.map((t) => t.id).toSet(), {'p1', 'c1', 'c2'});
      // Der Eltern-Bezug muss mitkommen, sonst stehen die Schritte als
      // lose Aufgaben da und die Elternaufgabe wirkt grundlos unerledigt.
      expect(tasks.firstWhere((t) => t.id == 'c1').parentId, 'p1');
      // Und die zerlegte Aufgabe darf nicht wieder als startbar erscheinen.
      expect(tasks.firstWhere((t) => t.id == 'p1').state, TaskState.blocked);
    });

    test('zurückgelegt ist nicht verworfen', () async {
      // `taskAbandoned` traegt den Grund. Wer eine Aufgabe zuruecklegt
      // oder durch eine andere verdraengt, hat sie nicht weggeworfen —
      // sie beim Wiederaufbau als verworfen zu fuehren loescht sie
      // faktisch, und zwar stumm.
      await store.append(evt(EventType.taskCreated, payload: {
        'task_id': 'r1',
        'title': 'Angefangen',
        'ae': 3,
        'state': 'ready',
      }));
      await store.append(evt(EventType.taskStarted, payload: {'task_id': 'r1'}));
      await store.append(evt(EventType.taskAbandoned,
          payload: {'task_id': 'r1', 'reason': 'released'}));

      await store.rebuildProjections();
      final task = (await store.tasks()).firstWhere((t) => t.id == 'r1');
      expect(task.state, TaskState.ready);
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

void _schemaGuard() {
  group('Schema-Grenze', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('axiom_schema'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('eine Datei aus einer neueren Fassung wird abgelehnt', () {
      // Weiterlaufen hiesse, gegen ein unbekanntes Schema zu rechnen. Das
      // Ergebnis waere still falsch — und das ist teurer als ein Abbruch.
      final path = '${dir.path}/axiom.db';
      sqlite3.open(path)
        ..execute('PRAGMA user_version = ${kSchemaVersion + 1};')
        ..dispose();

      expect(
        () => SqliteEventStore.open(path, clock: FakeClock(DateTime(2026))),
        throwsA(isA<StateError>()),
      );
    });

    test('jede Schemaversion hat ihren eigenen Migrationsblock', () {
      // Der Fehler, den das verhindert: `rule_overrides` stand im
      // `current < 5`-Zweig, waehrend kSchemaVersion schon auf 6 stand.
      // Eine Bestandsdatenbank auf Stand 5 lief daran vorbei, bekam die
      // Tabelle nie und wurde danach als Stand 6 markiert. Auf einem frisch
      // installierten Geraet war davon nichts zu merken.
      final source = File('lib/src/sqlite_event_store.dart').readAsStringSync();
      final blocks = RegExp(r'if \(current < (\d+)\)')
          .allMatches(source)
          .map((m) => int.parse(m.group(1)!))
          .toSet();
      expect(blocks, {for (var v = 1; v <= kSchemaVersion; v++) v},
          reason: 'Für jede Version von 1 bis $kSchemaVersion muss es genau '
              'einen Migrationsblock geben');
    });

    test('eine Bestandsdatenbank bekommt neue Tabellen nachgereicht',
        () async {
      // Der Fall, der auf dem Geraet passiert und im Test sonst nie: Die
      // Datei existiert schon, mit einer aelteren Schemaversion.
      final path = '${dir.path}/alt.db';
      final clock = FakeClock(DateTime(2026));
      SqliteEventStore.open(path, clock: clock).close();
      sqlite3.open(path)
        ..execute('DROP TABLE IF EXISTS rule_overrides;')
        ..execute('PRAGMA user_version = 5;')
        ..dispose();

      final store = SqliteEventStore.open(path, clock: clock);
      final db = sqlite3.open(path);
      final tables = db
          .select("SELECT name FROM sqlite_master WHERE type='table';")
          .map((r) => r['name'])
          .toList();
      db.dispose();
      expect(tables, contains('rule_overrides'),
          reason: 'Sonst bricht der Regeleditor auf genau den Geräten, auf '
              'denen AXIOM schon lief');
      store.close();
    });

    test('eine Bestandsdatenbank bekommt die Ortsspalte nachgereicht',
        () async {
      // Derselbe Fall eine Version weiter: Wer AXIOM schon benutzt, hat
      // `tasks` ohne `place`. Ohne Nachreichen bricht jedes Speichern einer
      // Aufgabe — und zwar erst auf dem Geraet.
      final path = '${dir.path}/ohne_ort.db';
      final clock = FakeClock(DateTime(2026));
      SqliteEventStore.open(path, clock: clock).close();
      sqlite3.open(path)
        ..execute('ALTER TABLE tasks DROP COLUMN place;')
        ..execute('PRAGMA user_version = 6;')
        ..dispose();

      final store = SqliteEventStore.open(path, clock: clock);
      await store.upsertTask(const Task(
        id: 'alt',
        title: 'Aus einer aelteren Fassung',
        activationEnergy: 3,
        salience: 5,
        stakes: 5,
        place: 'Büro',
        state: TaskState.ready,
      ));
      expect((await store.tasks()).single.place, 'Büro');
      store.close();
    });

    test('eine Datei derselben Fassung bleibt unveraendert', () async {
      final path = '${dir.path}/axiom.db';
      final clock = FakeClock(DateTime(2026));
      SqliteEventStore.open(path, clock: clock).close();
      // Zweites Oeffnen darf nichts erneut anlegen und nichts werfen.
      final again = SqliteEventStore.open(path, clock: clock);
      expect(await again.eventCount(), 0);
      again.close();
    });
  });
}
