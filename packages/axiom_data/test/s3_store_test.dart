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

    test('eine spätere Sitzung ohne Notiz verdeckt die letzte Notiz nicht',
        () async {
      // Sonst wäre der Wiedereinstieg genau dann weg, wenn eine kurze
      // Sitzung dazwischenkam — und das ist der Normalfall [D11].
      await store.startFocus(sessionOf());
      clock.advance(const Duration(minutes: 30));
      await store.endFocus('f1',
          at: clock.nowLocal(), breadcrumb: 'Bei Anlage KAP, Zeile 7');

      clock.advance(const Duration(hours: 1));
      await store.startFocus(sessionOf(id: 'f2'));
      clock.advance(const Duration(minutes: 10));
      await store.endFocus('f2', at: clock.nowLocal());

      expect(await store.lastBreadcrumb(), 'Bei Anlage KAP, Zeile 7');
    });

    test('von zwei offenen Sitzungen gilt die zuletzt begonnene', () async {
      // Passiert, wenn die App weggeräumt wurde, bevor sie beendet werden
      // konnte. Zwei laufende Sitzungen wären zwei gleichzeitige Antworten
      // auf „was gerade läuft" — es gibt genau eine (G1).
      await store.startFocus(sessionOf(id: 'alt'));
      clock.advance(const Duration(hours: 2));
      await store.startFocus(sessionOf(id: 'neu', anchor: null));

      expect((await store.activeFocus())!.id, 'neu');
    });

    test('eine unbekannte Kennung zu beenden ist folgenlos', () async {
      await store.startFocus(sessionOf());
      await store.endFocus('gibt-es-nicht', at: clock.nowLocal());

      expect((await store.activeFocus())!.id, 'f1');
    });

    test('die Art des Ausstiegs wird festgehalten', () async {
      // Geplant beendet oder abgebrochen ist der Unterschied zwischen einer
      // gehaltenen und einer gerissenen Sitzung. Die Spalte wird heute von
      // keiner Auswertung gelesen — geschrieben wird sie trotzdem, und sie
      // wandert im Export mit.
      await store.startFocus(sessionOf());
      clock.advance(const Duration(minutes: 12));
      await store.endFocus('f1', at: clock.nowLocal(), exitKind: 'aborted');

      expect(
        store.rawDatabase
            .select('SELECT exit_kind FROM focus_sessions WHERE id = ?', ['f1'])
            .single['exit_kind'],
        'aborted',
      );
    });

    test('eine Sitzung über Mitternacht zählt am Folgetag nicht mehr mit',
        () async {
      // Gezählt wird nach *Beginn* der Sitzung, nicht nach Überschneidung
      // mit dem Tag. Wer um 23:30 anfängt und um 01:00 aufhört, bekommt für
      // keinen der beiden Tage die vollen Minuten gutgeschrieben.
      //
      // Dieser Test hält den heutigen Stand fest, keinen Vorsatz: Wer die
      // Zählung auf Überschneidung umstellt, ändert ihn mit.
      clock.set(DateTime(2026, 8, 2, 23, 30));
      await store.startFocus(sessionOf());
      clock.advance(const Duration(minutes: 90));
      await store.endFocus('f1', at: clock.nowLocal());

      expect(await store.focusMinutesToday(DateTime(2026, 8, 3, 10)), 0);
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

    test('die Reihenfolge folgt der Sortierung, bei Gleichstand der Stärke',
        () async {
      await store.upsertChannel(
        const SensationChannel(
            id: 'ruhig', label: 'Spazieren', intensity: 1, typical: Duration(minutes: 20)),
        order: 1,
      );
      await store.upsertChannel(
        const SensationChannel(
            id: 'laut', label: 'Konzert', intensity: 5, typical: Duration(minutes: 120)),
        order: 0,
      );
      await store.upsertChannel(
        const SensationChannel(
            id: 'mittel', label: 'Sauna', intensity: 3, typical: Duration(minutes: 60)),
        order: 0,
      );

      expect((await store.channels()).map((c) => c.id),
          ['laut', 'mittel', 'ruhig']);
    });

    test('ein bearbeiteter Kanal behält seinen Platz', () async {
      // Sonst würde jede Textkorrektur die Liste umsortieren — und die
      // Reihenfolge ist genau das, worauf man sich beim Auswählen verlässt.
      await store.seedChannelsIfEmpty();
      final letzter = (await store.channels()).last;
      await store.upsertChannel(
        SensationChannel(
          id: letzter.id,
          label: 'Anders benannt',
          intensity: letzter.intensity,
          typical: letzter.typical,
          hasCost: letzter.hasCost,
        ),
      );

      final danach = await store.channels();
      expect(danach.last.id, letzter.id);
      expect(danach.last.label, 'Anders benannt');
    });

    test('einen Kanal zu löschen löscht keine vergangenen Slots', () async {
      // Der Reiz-Haushalt rechnet aus dem Strom. Einen Kanal zu entfernen
      // heißt „den brauche ich nicht mehr", nicht „das war nie".
      await store.upsertChannel(const SensationChannel(
        id: 'moto',
        label: 'Motorrad',
        intensity: 5,
        typical: Duration(minutes: 90),
      ));
      await store.append(Event(
        id: newUlid(clock.nowUtc()),
        at: clock.nowUtc(),
        type: EventType.sensationSlot,
        source: EventSource.user,
        payload: const {'channel': 'moto', 'label': 'Motorrad', 'intensity': 5},
      ));

      await store.deleteChannel('moto');

      expect(await store.channels(), isEmpty);
      final slots = await store.slotsSince(DateTime(2026, 8));
      expect(slots.single.channelId, 'moto');
    });

    test('ein Slot ohne Angaben bekommt lesbare Ersatzwerte', () async {
      // Ein Ereignis aus einer älteren Fassung oder aus einem fremden
      // Export darf den Haushalt nicht kippen — und es soll auch nicht
      // stumm verschwinden.
      await store.append(Event(
        id: newUlid(clock.nowUtc()),
        at: clock.nowUtc(),
        type: EventType.sensationSlot,
        source: EventSource.user,
        payload: const {},
      ));

      final slot = (await store.slotsSince(DateTime(2026, 8))).single;
      expect(slot.channelId, 'unknown');
      expect(slot.channelLabel, 'Slot');
      expect(slot.intensity, 3);
      expect(slot.duration, const Duration(minutes: 30));
      expect(slot.planned, isFalse);
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

    test('ein archivierter Trigger kommt durch Speichern nicht zurück',
        () async {
      // Archivieren ist die einzige Richtung: `upsertTrigger` fasst die
      // Spalte `archived` bewusst nicht an. Ein Trigger, den man abgelegt
      // hat, taucht also nicht wieder auf, weil man seinen Text bearbeitet.
      await store.upsertTrigger(triggerOf());
      await store.archiveTrigger('purchase');
      await store.upsertTrigger(const InterceptTrigger(
        id: 'purchase',
        label: 'Anschaffung über 500 €',
        cooldown: Duration(minutes: 30),
        checklist: ['Kannte ich das vor heute?'],
      ));

      expect(await store.triggers(), isEmpty);
    });

    test('Trigger stehen nach Bezeichnung sortiert', () async {
      for (final label in ['Zocken', 'Anschaffung', 'Motorrad']) {
        await store.upsertTrigger(InterceptTrigger(
          id: label.toLowerCase(),
          label: label,
          cooldown: const Duration(minutes: 15),
          checklist: const ['Brauche ich das morgen noch?'],
        ));
      }
      expect((await store.triggers()).map((t) => t.label),
          ['Anschaffung', 'Motorrad', 'Zocken']);
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

    test('ein Abfang bleibt offen, bis eine Antwort da ist — auch lange nach '
        'Ablauf der Sperre', () async {
      // Die Sperre läuft ab, die *Entscheidung* nicht. Was den Abfang
      // schließt, ist die Antwort, nicht die Uhr — sonst verschwände die
      // Frage von selbst und der Impuls hätte gewonnen, ohne dass jemand
      // ihn angesehen hat [D6].
      const interceptor = Interceptor();
      await store.saveRun(interceptor.start(
        trigger: triggerOf(),
        now: clock.nowLocal(),
        id: 'r1',
      ));

      clock.advance(const Duration(days: 21));
      expect((await store.activeRun(clock.nowLocal()))!.id, 'r1');
    });

    test('runsSince schneidet am Rand ein, nicht aus', () async {
      const interceptor = Interceptor();
      final grenze = DateTime(2026, 8, 3, 12);
      clock.set(grenze.subtract(const Duration(milliseconds: 1)));
      await store.saveRun(interceptor.start(
          trigger: triggerOf(), now: clock.nowLocal(), id: 'davor'));
      clock.set(grenze);
      await store.saveRun(interceptor.start(
          trigger: triggerOf(), now: clock.nowLocal(), id: 'genau'));

      expect((await store.runsSince(grenze)).map((r) => r.id), ['genau']);
    });

    test('eine offene Entscheidung verwässert die Haltequote nicht', () async {
      // `started` zählt alle, `holdRate` nur die entschiedenen. Ein Abfang,
      // der noch offen ist, ist kein „trotzdem gemacht".
      const interceptor = Interceptor();
      await store.saveRun(interceptor.start(
          trigger: triggerOf(), now: clock.nowLocal(), id: 'offen'));
      final entschieden = interceptor.start(
          trigger: triggerOf(), now: clock.nowLocal(), id: 'zu');
      await store.saveRun(InterceptRun(
        id: entschieden.id,
        triggerId: entschieden.triggerId,
        triggerLabel: entschieden.triggerLabel,
        startedAt: entschieden.startedAt,
        releasesAt: entschieden.releasesAt,
        outcome: InterceptOutcome.aborted,
      ));

      final stats = (await store.interceptStats(since: DateTime(2026, 8))).single;
      expect(stats.started, 2);
      expect(stats.decided, 1);
      expect(stats.holdRate, 1.0);
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

    test('eine unbekannte Stufe fällt auf L0 zurück, statt zu werfen',
        () async {
      // Kommt aus einem Export einer neueren Fassung. Ein Erhaltungsmodus,
      // den man wegen eines unbekannten Namens nicht mehr verlassen kann,
      // wäre schlimmer als die Rückkehr in den Normalbetrieb.
      store.rawDatabase.execute(
        'INSERT INTO load_state (id, level, since) VALUES (1, ?, ?)',
        ['l9', clock.nowLocal().millisecondsSinceEpoch],
      );
      expect(store.loadState()!.level, LoadLevel.l0);
    });
  });
}
