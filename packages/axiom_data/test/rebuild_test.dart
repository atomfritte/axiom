/// Der Wiederaufbau der Projektionen — die Stelle, an der ein Vault-Import
/// den Aufgabenbestand verlieren konnte.
///
/// Die Tests hier halten drei Zusagen fest, die vorher keine waren:
/// ein Ereignis ohne Anlage kippt den Aufbau nicht, ein Abbruch lässt die
/// alte Projektion stehen, und die Anlagezeit kommt aus dem Ereignis.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
import 'package:test/test.dart';

void main() {
  late FakeClock clock;
  late SqliteEventStore store;

  setUp(() {
    clock = FakeClock(DateTime(2026, 6, 24, 10));
    store = SqliteEventStore.inMemory(clock: clock);
  });
  tearDown(() => store.close());

  Event evt(EventType type, Map<String, Object?> payload) => Event(
        id: newUlid(clock.nowUtc()),
        at: clock.nowUtc(),
        type: type,
        source: EventSource.user,
        payload: payload,
      );

  Future<void> create(String id, {String title = 'Aufgabe', int ae = 5}) async {
    await store.append(evt(EventType.taskCreated, {
      'task_id': id,
      'title': title,
      'ae': ae,
      'salience': 5,
      'stakes': 5,
      'state': 'ready',
    }));
    await store.upsertTask(Task(
      id: id,
      title: title,
      activationEnergy: ae,
      salience: 5,
      stakes: 5,
      state: TaskState.ready,
    ));
  }

  group('Ein Ereignis ohne Anlage', () {
    test('nimmt nicht den ganzen Bestand mit', () async {
      // Der Fall aus der Zeit vor Commit aefafc3: Teilschritte standen nur
      // in der Projektion, der Strom kannte nur ihre IDs im `task_split`.
      // Wird so ein Schritt spaeter abgehakt, liegt ein `task_completed`
      // ohne `task_created` im Strom.
      await create('p1', title: 'Steuer', ae: 8);
      await store.upsertTask(const Task(
        id: 'c1',
        title: 'Ordner holen',
        activationEnergy: 2,
        salience: 5,
        stakes: 5,
        parentId: 'p1',
        state: TaskState.ready,
      ));
      await store.append(evt(EventType.taskSplit, {
        'parent_id': 'p1',
        'child_ids': ['c1'],
      }));
      await store.append(evt(EventType.taskCompleted, {'task_id': 'c1'}));

      await store.rebuildProjections();

      final tasks = await store.tasks();
      expect(tasks.map((t) => t.id), ['p1'],
          reason: 'Der Waise faellt weg — der uebrige Bestand bleibt');
      expect(tasks.single.state, TaskState.blocked);
    });

    test('gilt auch für ein Aufgeben ohne Anlage', () async {
      // Dieselbe Zeile stand ein zweites Mal bei `task_abandoned`.
      await create('p1');
      await store.append(evt(EventType.taskAbandoned, {
        'task_id': 'nie-angelegt',
        'reason': 'released',
      }));

      await store.rebuildProjections();
      expect((await store.tasks()).map((t) => t.id), ['p1']);
    });
  });

  group('Ein Abbruch im Wiederaufbau', () {
    test('lässt die vorhandene Projektion stehen', () async {
      // Ohne Transaktion war die Reihenfolge toedlich: erst `DELETE FROM
      // tasks`, dann der Aufbau. Warf der Aufbau, blieb die Projektion leer
      // — und weil der Import einen Wiederaufbau nur bei neuen Ereignissen
      // ausloest, kam sie nie wieder.
      await create('gut', title: 'Bleibt bestehen');
      await store.append(evt(EventType.taskCreated, {
        'task_id': 'kaputt',
        'title': 'Unlesbares Verfallsdatum',
        'decay_at': 'kein-datum',
        'state': 'ready',
      }));

      await expectLater(store.rebuildProjections(), throwsA(isA<Object>()));

      expect((await store.tasks()).map((t) => t.id), ['gut'],
          reason: 'Ein gescheiterter Wiederaufbau darf nichts loeschen');
    });
  });

  group('Anlagezeit', () {
    test('kommt aus dem Ereignis, nicht aus der Uhr', () async {
      // Sonst gilt nach jedem Import jede Aufgabe als „gerade angelegt":
      // Der Atomizer sieht nichts mehr liegen (`stale` kann nicht mehr
      // entstehen) und schlaegt eine andere Aufgabe zum Zerlegen vor.
      await create('alt', title: 'Liegt seit Wochen');
      clock.advance(const Duration(days: 40));
      await create('neu', title: 'Von heute');

      clock.advance(const Duration(days: 1));
      await store.rebuildProjections();

      final times = await store.taskCreationTimes();
      expect(times['alt'], DateTime(2026, 6, 24, 10));
      expect(times['neu'], DateTime(2026, 8, 3, 10));
    });

    test('hält die Reihenfolge „neueste zuerst"', () async {
      await create('a');
      clock.advance(const Duration(days: 1));
      await create('b');
      clock.advance(const Duration(days: 1));
      await create('c');

      expect((await store.tasks()).map((t) => t.id), ['c', 'b', 'a']);
      clock.advance(const Duration(days: 30));
      await store.rebuildProjections();
      expect((await store.tasks()).map((t) => t.id), ['c', 'b', 'a'],
          reason: 'Nach dem Wiederaufbau stand die Liste andersherum');
    });

    test('eine neu angelegte Aufgabe bekommt weiterhin die Uhrzeit', () async {
      await store.upsertTask(const Task(
        id: 'frisch',
        title: 'Gerade eben',
        activationEnergy: 3,
        salience: 5,
        stakes: 5,
        state: TaskState.inbox,
      ));
      expect((await store.taskCreationTimes())['frisch'],
          DateTime(2026, 6, 24, 10));
    });
  });

  group('Import auf ein Gerät mit eigenem Bestand', () {
    test('das Zielgerät behält seine Aufgaben', () async {
      // Der teuerste Ablauf: Ein altes Geraet exportiert, das neue spielt
      // ein — und verlor dabei seinen eigenen Bestand, weil der
      // Wiederaufbau nach dem DELETE warf.
      await create('p1', title: 'Steuer', ae: 8);
      await store.upsertTask(const Task(
        id: 'c1',
        title: 'Nur in der Projektion',
        activationEnergy: 2,
        salience: 5,
        stakes: 5,
        state: TaskState.ready,
      ));
      await store.append(evt(EventType.taskCompleted, {'task_id': 'c1'}));

      final blob = await Vault(store: store, clock: clock, kdfRounds: 200)
          .export(passphrase: 'ein-langes-kennwort');

      final target = SqliteEventStore.inMemory(clock: clock);
      await target.append(evt(EventType.taskCreated, {
        'task_id': 'eigene',
        'title': 'Vom Zielgerät',
        'state': 'ready',
      }));
      await target.upsertTask(const Task(
        id: 'eigene',
        title: 'Vom Zielgerät',
        activationEnergy: 5,
        salience: 5,
        stakes: 5,
        state: TaskState.ready,
      ));

      final result = await Vault(store: target, clock: clock, kdfRounds: 200)
          .import(data: blob, passphrase: 'ein-langes-kennwort');

      expect(result.imported, greaterThan(0));
      expect((await target.tasks()).map((t) => t.id).toSet(),
          {'eigene', 'p1'});
      target.close();
    });
  });
}
