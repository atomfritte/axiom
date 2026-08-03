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

  group('Schema', () {
    test('kennt die Stufe-3-Tabellen ab v4', () {
      // Keine feste Zahl festhalten — die Version steigt mit jeder Stufe.
      expect(kSchemaVersion, greaterThanOrEqualTo(4));
    });

    test('Bestandsdaten überleben die Migration', () async {
      await store.append(Event(
        id: newUlid(clock.nowUtc()),
        at: clock.nowUtc(),
        type: EventType.capture,
        source: EventSource.user,
        payload: const {'text': 'vor v4'},
      ));
      expect((await store.query()).single.payload['text'], 'vor v4');
    });
  });

  group('Fokus (M4)', () {
    FocusSession sessionOf({String id = 'f1', String? anchor = 't1'}) =>
        FocusSession(
          id: id,
          startedAt: clock.nowLocal(),
          anchorTaskId: anchor,
          anchorTitle: anchor == null ? null : 'Steuerunterlagen',
          planned: const Duration(minutes: 50),
        );

    test('laufende Sitzung wird gefunden', () async {
      expect(await store.activeFocus(), isNull);
      await store.startFocus(sessionOf());

      final active = await store.activeFocus();
      expect(active, isNotNull);
      expect(active!.anchorTitle, 'Steuerunterlagen');
      expect(active.planned, const Duration(minutes: 50));
    });

    test('beendete Sitzung gilt nicht mehr als laufend', () async {
      await store.startFocus(sessionOf());
      clock.advance(const Duration(minutes: 40));
      await store.endFocus('f1', at: clock.nowLocal());
      expect(await store.activeFocus(), isNull);
    });

    test('summiert Fokusminuten des Tages', () async {
      await store.startFocus(sessionOf());
      clock.advance(const Duration(minutes: 45));
      await store.endFocus('f1', at: clock.nowLocal());

      await store.startFocus(sessionOf(id: 'f2'));
      clock.advance(const Duration(minutes: 30));
      await store.endFocus('f2', at: clock.nowLocal());

      expect(await store.focusMinutesToday(clock.nowLocal()), 75);
    });

    test('laufende Sitzung zählt bis jetzt mit', () async {
      await store.startFocus(sessionOf());
      clock.advance(const Duration(minutes: 20));
      expect(await store.focusMinutesToday(clock.nowLocal()), 20);
    });

    test('Wiedereinstiegsnotiz überlebt die Sitzung [D11]', () async {
      await store.startFocus(sessionOf());
      clock.advance(const Duration(minutes: 30));
      await store.endFocus('f1',
          at: clock.nowLocal(), breadcrumb: 'Bei Anlage KAP, Zeile 7');

      expect(await store.lastBreadcrumb(), 'Bei Anlage KAP, Zeile 7');
    });
  });

  group('Reizkanäle (M5)', () {
    test('Voreinstellung wird nur einmal angelegt', () async {
      await store.seedChannelsIfEmpty();
      final first = await store.channels();
      expect(first, hasLength(kDefaultChannels.length));

      await store.seedChannelsIfEmpty();
      expect(await store.channels(), hasLength(first.length));
    });

    test('eigene Kanäle lassen sich anlegen und löschen', () async {
      await store.upsertChannel(const SensationChannel(
        id: 'moto',
        label: 'Motorrad',
        intensity: 5,
        typical: Duration(minutes: 90),
        hasCost: true,
      ));
      final channels = await store.channels();
      expect(channels.single.label, 'Motorrad');
      expect(channels.single.hasCost, isTrue);

      await store.deleteChannel('moto');
      expect(await store.channels(), isEmpty);
    });

    test('Slots kommen aus dem Ereignisstrom', () async {
      await store.append(Event(
        id: newUlid(clock.nowUtc()),
        at: clock.nowUtc(),
        type: EventType.sensationSlot,
        source: EventSource.user,
        payload: const {
          'channel': 'sport',
          'label': 'Sport, hart',
          'intensity': 5,
          'duration_min': 45,
          'planned': true,
        },
      ));
      final slots = await store.slotsSince(
        clock.nowUtc().subtract(const Duration(days: 1)),
      );
      expect(slots.single.planned, isTrue);
      expect(slots.single.duration, const Duration(minutes: 45));
    });
  });

  group('Impuls-Trigger (M6)', () {
    InterceptTrigger triggerOf({bool authorized = true}) => InterceptTrigger(
          id: 'purchase',
          label: 'Anschaffung über 200 €',
          cooldown: const Duration(minutes: 15),
          checklist: const ['Kannte ich das vor heute?', 'Sache oder Gefühl?'],
          authorized: authorized,
        );

    test('Trigger mit Checkliste wird gespeichert', () async {
      await store.upsertTrigger(triggerOf());
      final loaded = (await store.triggers()).single;
      expect(loaded.checklist, hasLength(2));
      expect(loaded.authorized, isTrue);
      expect(loaded.isValid, isTrue);
    });

    test('archivierte Trigger verschwinden aus der Liste', () async {
      await store.upsertTrigger(triggerOf());
      await store.archiveTrigger('purchase');
      expect(await store.triggers(), isEmpty);
    });

    test('laufender Abfang wird gefunden', () async {
      const interceptor = Interceptor();
      final run = interceptor.start(
        trigger: triggerOf(),
        now: clock.nowLocal(),
        id: 'r1',
      );
      await store.saveRun(run);

      final active = await store.activeRun(clock.nowLocal());
      expect(active, isNotNull);
      expect(active!.outcome, InterceptOutcome.pending);
    });

    test('Ausgang wird fortgeschrieben, nicht dupliziert', () async {
      const interceptor = Interceptor();
      final run = interceptor.start(
        trigger: triggerOf(),
        now: clock.nowLocal(),
        id: 'r1',
      );
      await store.saveRun(run);
      await store.saveRun(InterceptRun(
        id: run.id,
        triggerId: run.triggerId,
        triggerLabel: run.triggerLabel,
        startedAt: run.startedAt,
        releasesAt: run.releasesAt,
        answers: const [true, true],
        outcome: InterceptOutcome.aborted,
      ));

      final runs = await store.runsSince(
        clock.nowUtc().subtract(const Duration(days: 1)),
      );
      expect(runs, hasLength(1));
      expect(runs.single.outcome, InterceptOutcome.aborted);
      expect(runs.single.answered, 2);
      expect(await store.activeRun(clock.nowLocal()), isNull);
    });

    test('Statistik zählt gehalten und trotzdem gemacht', () async {
      const interceptor = Interceptor();
      for (final (i, outcome) in [
        InterceptOutcome.aborted,
        InterceptOutcome.aborted,
        InterceptOutcome.proceeded,
      ].indexed) {
        final run = interceptor.start(
          trigger: triggerOf(),
          now: clock.nowLocal(),
          id: 'r$i',
        );
        await store.saveRun(InterceptRun(
          id: run.id,
          triggerId: run.triggerId,
          triggerLabel: run.triggerLabel,
          startedAt: run.startedAt,
          releasesAt: run.releasesAt,
          outcome: outcome,
        ));
        clock.advance(const Duration(hours: 1));
      }

      final stats = (await store.interceptStats(
        since: DateTime(2026, 8, 3),
      )).single;
      expect(stats.started, 3);
      expect(stats.aborted, 2);
      expect(stats.holdRate, closeTo(2 / 3, 0.001));
    });
  });

  group('Load-Zustand (M9)', () {
    test('wird persistiert — ein Neustart beendet keinen Erhaltungsmodus',
        () async {
      expect(store.loadState(), isNull);
      store.setLoadState(LoadLevel.l3, clock.nowLocal());

      final state = store.loadState();
      expect(state!.level, LoadLevel.l3);
      expect(state.since.day, clock.nowLocal().day);
    });

    test('Stufenwechsel überschreibt, statt zu sammeln', () async {
      store.setLoadState(LoadLevel.l2, clock.nowLocal());
      clock.advance(const Duration(days: 2));
      store.setLoadState(LoadLevel.l0, clock.nowLocal());

      expect(store.loadState()!.level, LoadLevel.l0);
    });
  });
}
