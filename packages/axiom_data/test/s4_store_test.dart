/// Stufe 4: Nachbetrachtung (M10) und Wirkfenster (M13).
///
/// `s4_store.dart` hatte keine Testdatei — 129 Zeilen Ablage, darunter die
/// einzige Loeschanweisung auf Gesundheitsdaten in diesem Paket. Diese Datei
/// haelt deshalb nicht nur fest, was die Ablage kann, sondern vor allem, was
/// `deleteMedEntry` gerade *nicht* entfernt: Der Strom behaelt die Einnahme.
///
/// Warum das kein Widerspruch zur Append-only-Zusage ist und warum es
/// trotzdem eine Falle bleibt, steht bei der Gruppe „Loeschen".
library;

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

  Future<String> incident({
    int? intensity = 4,
    String triggerClass = 'criticism',
    String? note,
  }) async {
    final id = newUlid(clock.nowUtc());
    await store.append(Event(
      id: id,
      at: clock.nowUtc(),
      type: EventType.signalIncident,
      source: EventSource.user,
      payload: {
        'intensity': ?intensity,
        'trigger_class': triggerClass,
        'note': ?note,
      },
    ));
    return id;
  }

  group('Vorfaelle kommen aus dem Strom, nicht aus einer Tabelle (M10)', () {
    test('Staerke, Klasse und Notiz kommen unveraendert zurueck', () async {
      final id = await incident(intensity: 5, note: 'Meeting');
      final read = (await store.incidentsSince(DateTime(2026, 8))).single;

      expect(read.id, id);
      expect(read.intensity, 5);
      expect(read.triggerClass, TriggerClass.criticism);
      expect(read.note, 'Meeting');
    });

    test('eine unbekannte Auslöserklasse wird „unklar", nicht ein Ladefehler',
        () async {
      // Bewusst nachsichtig, anders als beim Regelwerk: Der Vorfall ist
      // bereits passiert und steht unveraenderlich im Strom. Ihn wegen einer
      // Bezeichnung zu verwerfen hiesse, die Erhebung nachtraeglich zu
      // loeschen — die Klasse ist die weichste Angabe daran.
      await incident(triggerClass: 'gibt_es_nicht');
      final read = (await store.incidentsSince(DateTime(2026, 8))).single;
      expect(read.triggerClass, TriggerClass.unclear);
    });

    test('ein Vorfall ohne Staerke wird als 3 gelesen', () async {
      await incident(intensity: null);
      expect((await store.incidentsSince(DateTime(2026, 8))).single.intensity, 3);
    });

    test('was vor dem Zeitfenster liegt, bleibt draussen', () async {
      await incident();
      clock.advance(const Duration(days: 5));
      final later = await incident();

      final read = await store.incidentsSince(
        clock.nowUtc().subtract(const Duration(days: 1)),
      );
      expect(read.map((i) => i.id), [later]);
    });
  });

  group('Nachbetrachtung (M10)', () {
    PostMortem review(String incidentId, {String? cause, int? hindsight}) =>
        PostMortem(
          incidentId: incidentId,
          at: clock.nowLocal(),
          rootCause: cause,
          countermeasure: 'Vorher rausgehen',
          intensityInHindsight: hindsight,
        );

    test('eine zweite Fassung ersetzt die erste, statt sie zu verdoppeln',
        () async {
      final id = await incident();
      await store.savePostMortem(review(id, cause: 'Zu wenig Schlaf'));
      await store.savePostMortem(review(id, cause: 'Hunger', hindsight: 2));

      final all = await store.postMortems();
      expect(all, hasLength(1));
      expect(all.single.rootCause, 'Hunger');
      expect(all.single.intensityInHindsight, 2);
    });

    test('der Zeitpunkt bleibt der der ersten Fassung', () async {
      // Die Nachbetrachtung entsteht spaeter und wird ergaenzt. Wann sie
      // *begonnen* wurde, ist die Zahl, die im Rueckblick zaehlt — sie bei
      // jeder Ergaenzung nach vorn zu schieben wuerde den Abstand zum
      // Vorfall verschwinden lassen.
      final id = await incident();
      final first = clock.nowLocal();
      await store.savePostMortem(review(id, cause: 'Erste Fassung'));

      clock.advance(const Duration(days: 3));
      await store.savePostMortem(review(id, cause: 'Ergaenzt'));

      expect(
        (await store.postMortems()).single.at.millisecondsSinceEpoch,
        first.millisecondsSinceEpoch,
      );
    });

    test('die juengste Nachbetrachtung steht oben', () async {
      final a = await incident();
      await store.savePostMortem(review(a, cause: 'aelter'));
      clock.advance(const Duration(days: 1));
      final b = await incident();
      await store.savePostMortem(review(b, cause: 'juenger'));

      expect(
        (await store.postMortems()).map((p) => p.rootCause),
        ['juenger', 'aelter'],
      );
    });

    test('nur betrachtete Vorfaelle stehen in reviewedIncidentIds', () async {
      final a = await incident();
      final b = await incident();
      await store.savePostMortem(review(a, cause: 'x'));

      expect(await store.reviewedIncidentIds(), {a});
      expect(await store.reviewedIncidentIds(), isNot(contains(b)));
    });
  });

  group('Das Wirkfenster ist aus, bis es jemand einschaltet (M13)', () {
    test('frisch installiert ist das Modul aus', () {
      // M13 protokolliert Medikation. Ein Modul, das unaufgefordert nach
      // Substanzen fragt, waere die falsche Voreinstellung.
      expect(store.medEnabled, isFalse);
    });

    test('einschalten haelt, ausschalten auch', () {
      store.medEnabled = true;
      expect(store.medEnabled, isTrue);
      store.medEnabled = false;
      expect(store.medEnabled, isFalse);
    });
  });

  group('Einnahmen (M13)', () {
    MedEntry entry({
      String id = 'm1',
      String label = 'Praeparat',
      String? dose = '1 Stueck',
      DateTime? takenAt,
      Duration onset = const Duration(minutes: 45),
      Duration duration = const Duration(hours: 4),
    }) =>
        MedEntry(
          id: id,
          label: label,
          dose: dose,
          takenAt: takenAt ?? clock.nowLocal(),
          onset: onset,
          duration: duration,
        );

    test('Bezeichnung, Dosis und Fenster kommen unveraendert zurueck',
        () async {
      await store.saveMedEntry(entry());
      final read = (await store.medEntriesSince(DateTime(2026, 8))).single;

      expect(read.label, 'Praeparat');
      expect(read.dose, '1 Stueck');
      expect(read.onset, const Duration(minutes: 45));
      expect(read.duration, const Duration(hours: 4));
    });

    test('eine korrigierte Einnahme ersetzt die Zeile, statt eine zweite '
        'anzulegen', () async {
      await store.saveMedEntry(entry(dose: '1 Stueck'));
      await store.saveMedEntry(entry(dose: '2 Stueck'));

      final all = await store.medEntriesSince(DateTime(2026, 8));
      expect(all, hasLength(1));
      expect(all.single.dose, '2 Stueck');
    });

    test('die Vorbelegung nimmt die zuletzt *genommene*, nicht die zuletzt '
        'geschriebene', () async {
      // Nachtraeglich eingetragene Einnahmen sind der Normalfall — wer sie
      // sofort eintraegt, braucht die Vorbelegung nicht. Sortiert wird
      // deshalb nach Einnahmezeit.
      await store.saveMedEntry(entry(
        id: 'heute',
        label: 'Heute',
        takenAt: clock.nowLocal(),
      ));
      await store.saveMedEntry(entry(
        id: 'gestern',
        label: 'Gestern',
        takenAt: clock.nowLocal().subtract(const Duration(days: 1)),
      ));

      expect((await store.lastMedEntry())!.label, 'Heute');
    });

    test('ohne Eintrag gibt es keine Vorbelegung', () async {
      expect(await store.lastMedEntry(), isNull);
    });

    test('das Zeitfenster schliesst am Rand ein, nicht aus', () async {
      final grenze = DateTime(2026, 8, 3, 8);
      await store.saveMedEntry(entry(id: 'genau', takenAt: grenze));
      await store.saveMedEntry(entry(
        id: 'davor',
        takenAt: grenze.subtract(const Duration(milliseconds: 1)),
      ));

      final read = await store.medEntriesSince(grenze);
      expect(read.map((e) => e.id), ['genau']);
    });

    test('ohne Angabe steht kein Wirkfenster da — geraten wird nichts',
        () async {
      // Abgrenzung, verbindlich: M13 protokolliert nur. Eine
      // Voreinstellung fuer Anflutung oder Dauer waere eine Empfehlung
      // durch die Hintertuer, und zwar eine ohne Grundlage.
      await store.saveMedEntry(MedEntry(
        id: 'roh',
        label: 'Praeparat',
        takenAt: clock.nowLocal(),
      ));
      final read = (await store.medEntriesSince(DateTime(2026, 8))).single;
      expect(read.onset, Duration.zero);
      expect(read.duration, Duration.zero);
      expect(read.dose, isNull);
    });
  });

  group('Loeschen — was dabei bleibt', () {
    /// Schreibt eine Einnahme so, wie die App es tut: Tabellenzeile **und**
    /// Ereignis (`runtime.dart`, `logMedEntry`).
    Future<void> takeMedication(String id, String label) async {
      await store.saveMedEntry(MedEntry(
        id: id,
        label: label,
        dose: '10 mg',
        takenAt: clock.nowLocal(),
        onset: const Duration(minutes: 30),
        duration: const Duration(hours: 6),
      ));
      await store.append(Event(
        id: newUlid(clock.nowUtc()),
        at: clock.nowUtc(),
        type: EventType.medIntake,
        source: EventSource.user,
        payload: {
          'substance': label,
          'dose': '10 mg',
          'onset_min': 30,
          'duration_min': 360,
        },
      ));
    }

    test('die geloeschte Einnahme verschwindet aus der Liste', () async {
      await takeMedication('m1', 'Praeparat A');
      await store.deleteMedEntry('m1');

      expect(await store.medEntriesSince(DateTime(2026, 8)), isEmpty);
      expect(await store.lastMedEntry(), isNull);
    });

    test('der Ereignisstrom behaelt die Einnahme — mit Substanz und Dosis',
        () async {
      // Das ist der Kern: Die Zusage „append-only" gilt fuer `events`, und
      // sie gilt hier auch. `deleteMedEntry` faellt die Tabellenzeile, nicht
      // das Ereignis. Wer im Wirkfenster „loeschen" drueckt, entfernt damit
      // die Anzeige, nicht die Erhebung.
      await takeMedication('m1', 'Praeparat A');
      await store.deleteMedEntry('m1');

      final stream = await store.query(types: {EventType.medIntake});
      expect(stream, hasLength(1));
      expect(stream.single.payload['substance'], 'Praeparat A');
      expect(stream.single.payload['dose'], '10 mg');
    });

    test('und der Export traegt sie weiter', () async {
      // Der Export ist der einzige dokumentierte Sicherungsweg und wandert
      // ueber USB und fremde Ordner. Eine geloeschte Einnahme steht darin
      // weiterhin im Klartext-Abschnitt der Ereignisse.
      await takeMedication('m1', 'Praeparat A');
      await store.deleteMedEntry('m1');

      final text =
          await Vault(store: store, clock: clock, kdfRounds: 200)
              .buildPlaintext();
      expect(text, contains('Praeparat A'));
      // Die Tabellenzeile ist weg — nur das Ereignis blieb.
      expect(text, isNot(contains('"table":"med_entries"')));
    });

    test('ein Wiederaufbau der Projektionen holt sie nicht zurueck', () async {
      // `med_entries` ist keine Projektion: `rebuildProjections()` baut
      // ausschliesslich `tasks` und `task_links`. Der `medIntake`-Strom wird
      // dabei nicht ausgewertet — sonst waere jedes Loeschen beim naechsten
      // Import rueckgaengig.
      await takeMedication('m1', 'Praeparat A');
      await store.deleteMedEntry('m1');
      await store.rebuildProjections();

      expect(await store.medEntriesSince(DateTime(2026, 8)), isEmpty);
    });

    test('eine unbekannte Kennung zu loeschen ist folgenlos', () async {
      await takeMedication('m1', 'Praeparat A');
      await store.deleteMedEntry('gibt-es-nicht');

      expect(await store.medEntriesSince(DateTime(2026, 8)), hasLength(1));
    });

    test('geloescht wird genau eine Einnahme, nicht der Rest', () async {
      await takeMedication('m1', 'Praeparat A');
      clock.advance(const Duration(hours: 6));
      await takeMedication('m2', 'Praeparat B');

      await store.deleteMedEntry('m1');
      final rest = await store.medEntriesSince(DateTime(2026, 8));
      expect(rest.map((e) => e.id), ['m2']);
    });
  });
}
