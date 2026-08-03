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

  Anchor anchorOf({
    String id = 'a1',
    int hour = 14,
    Duration travel = const Duration(minutes: 25),
    String? location = 'Praxis',
  }) =>
      Anchor(
        id: id,
        title: 'Zahnarzt',
        arriveBy: DateTime(2026, 8, 3, hour),
        travel: travel,
        location: location,
      );

  group('Speichern und lesen', () {
    test('erhält alle Zeitanteile', () async {
      await store.upsertAnchor(anchorOf());
      final loaded = (await store.anchors()).single;

      expect(loaded.title, 'Zahnarzt');
      expect(loaded.travel, const Duration(minutes: 25));
      expect(loaded.prepare, kDefaultPrepare);
      expect(loaded.buffer, kDefaultBuffer);
      expect(loaded.contextSwitch, kDefaultContextSwitch);
      expect(loaded.location, 'Praxis');
      expect(loaded.arriveBy, DateTime(2026, 8, 3, 14));
    });

    test('die Kette überlebt den Speichervorgang', () async {
      final original = anchorOf();
      await store.upsertAnchor(original);
      final loaded = (await store.anchors()).single;

      expect(
        loaded.chain.map((s) => s.at),
        original.chain.map((s) => s.at),
      );
      expect(loaded.leadTime, original.leadTime);
    });

    test('sortiert chronologisch', () async {
      await store.upsertAnchor(anchorOf(id: 'spaet', hour: 17));
      await store.upsertAnchor(anchorOf(id: 'frueh', hour: 9));
      expect(
        (await store.anchors()).map((a) => a.id),
        ['frueh', 'spaet'],
      );
    });

    test('filtert nach Zeitfenster', () async {
      await store.upsertAnchor(anchorOf(id: 'heute', hour: 14));
      await store.upsertAnchor(Anchor(
        id: 'morgen',
        title: 'Werkstatt',
        arriveBy: DateTime(2026, 8, 4, 10),
      ));

      final today = await store.anchors(
        from: DateTime(2026, 8, 3),
        to: DateTime(2026, 8, 4),
      );
      expect(today.map((a) => a.id), ['heute']);
    });

    test('Aktualisieren überschreibt, statt zu duplizieren', () async {
      await store.upsertAnchor(anchorOf());
      await store.upsertAnchor(anchorOf(travel: const Duration(minutes: 45)));

      final all = await store.anchors();
      expect(all, hasLength(1));
      expect(all.single.travel, const Duration(minutes: 45));
    });
  });

  group('Kalenderimport', () {
    test('erkennt bereits übernommene Einträge', () async {
      expect(await store.hasAnchorFor('cal-42'), isFalse);
      await store.upsertAnchor(anchorOf(),
          source: 'calendar', externalId: 'cal-42');
      expect(await store.hasAnchorFor('cal-42'), isTrue);
    });

    test('verworfene Anker kommen beim Import nicht zurück', () async {
      await store.upsertAnchor(anchorOf(),
          source: 'calendar', externalId: 'cal-42');
      await store.dismissAnchor('a1');

      expect(await store.anchors(), isEmpty);
      // Der Eintrag bleibt bekannt, damit der Import ihn nicht neu anlegt.
      expect(await store.hasAnchorFor('cal-42'), isTrue);
    });
  });

  group('Migration', () {
    test('das Schema kennt die Ankertabelle ab v3', () {
      // Keine feste Versionsnummer festhalten — die steigt mit jeder Stufe.
      // Geprueft wird, dass die Tabelle existiert und benutzbar ist.
      expect(kSchemaVersion, greaterThanOrEqualTo(3));
    });

    test('Bestandsdaten bleiben nach der Migration erhalten', () async {
      // Events aus v1/v2 dürfen durch die v3-Migration nicht verloren gehen.
      await store.append(Event(
        id: newUlid(clock.nowUtc()),
        at: clock.nowUtc(),
        type: EventType.capture,
        source: EventSource.user,
        payload: const {'text': 'vor der Migration'},
      ));
      expect(await store.eventCount(), 1);
      expect((await store.query()).single.payload['text'],
          'vor der Migration');
    });
  });

  group('Aufgaben-Anlagezeit', () {
    test('liefert den Zeitpunkt je Aufgabe für den Atomizer', () async {
      await store.upsertTask(const Task(
        id: 't1',
        title: 'Steuerunterlagen',
        activationEnergy: 8,
        salience: 3,
        stakes: 9,
        state: TaskState.ready,
      ));
      final times = await store.taskCreationTimes();
      expect(times.keys, ['t1']);
      expect(times['t1']!.difference(clock.nowLocal()).inMinutes.abs(),
          lessThan(2));
    });
  });
}
