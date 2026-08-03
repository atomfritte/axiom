import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

void main() {
  const log = SignalLog();
  final now = DateTime(2026, 8, 10, 18);

  SignalIncident incidentOf({
    String id = 'i1',
    int intensity = 4,
    TriggerClass trigger = TriggerClass.criticism,
    Duration ago = const Duration(hours: 20),
  }) =>
      SignalIncident(
        id: id,
        at: now.subtract(ago),
        intensity: intensity,
        triggerClass: trigger,
      );

  group('Nachbetrachtung kommt spaeter, nicht sofort [D10]', () {
    test('frischer Vorfall wird nicht zur Analyse angeboten', () {
      // Im Spike ist niemand analysefaehig — der Versuch verlaengert das
      // Ereignis, statt es abzuschliessen.
      final due = log.awaitingPostMortem(
        incidents: [incidentOf(ago: const Duration(hours: 2))],
        reviewedIds: const {},
        now: now,
      );
      expect(due, isEmpty);
    });

    test('nach der Wartezeit wird er angeboten', () {
      final due = log.awaitingPostMortem(
        incidents: [incidentOf(ago: const Duration(hours: 20))],
        reviewedIds: const {},
        now: now,
      );
      expect(due, hasLength(1));
    });

    test('sehr alte Vorfaelle werden nicht mehr aufgewaermt', () {
      final due = log.awaitingPostMortem(
        incidents: [incidentOf(ago: const Duration(days: 9))],
        reviewedIds: const {},
        now: now,
      );
      expect(due, isEmpty);
    });

    test('bereits betrachtete Vorfaelle verschwinden', () {
      final due = log.awaitingPostMortem(
        incidents: [incidentOf()],
        reviewedIds: const {'i1'},
        now: now,
      );
      expect(due, isEmpty);
    });

    test('der staerkste kommt zuerst', () {
      final due = log.awaitingPostMortem(
        incidents: [
          incidentOf(id: 'schwach', intensity: 2),
          incidentOf(id: 'stark', intensity: 5),
        ],
        reviewedIds: const {},
        now: now,
      );
      expect(due.first.id, 'stark');
    });
  });

  group('Belastung klingt ab', () {
    test('frischer Vorfall belastet mehr als ein alter', () {
      final frisch = log.pressure(
        incidents: [incidentOf(ago: const Duration(hours: 2))],
        now: now,
      );
      final alt = log.pressure(
        incidents: [incidentOf(ago: const Duration(hours: 60))],
        now: now,
      );
      expect(frisch, greaterThan(alt));
    });

    test('nach 72 Stunden zaehlt er nicht mehr', () {
      expect(
        log.pressure(
          incidents: [incidentOf(ago: const Duration(hours: 80))],
          now: now,
        ),
        0,
      );
    });

    test('mehrere Vorfaelle summieren sich, gedeckelt bei 100', () {
      final many = List.generate(
        20,
        (i) => incidentOf(id: 'i$i', intensity: 5, ago: const Duration(hours: 1)),
      );
      expect(log.pressure(incidents: many, now: now), 100);
    });

    test('ohne Vorfaelle keine Belastung', () {
      expect(log.pressure(incidents: const [], now: now), 0);
    });
  });

  group('Muster', () {
    test('haeufigste Ausloeserklasse steht vorn', () {
      final counts = log.patterns([
        incidentOf(id: 'a', trigger: TriggerClass.rejection),
        incidentOf(id: 'b', trigger: TriggerClass.rejection),
        incidentOf(id: 'c', trigger: TriggerClass.rejection),
        incidentOf(id: 'd', trigger: TriggerClass.overload),
      ]);
      expect(counts.keys.first, TriggerClass.rejection);
      expect(counts[TriggerClass.rejection], 3);
    });

    test('jede Klasse hat Bezeichnung und Erlaeuterung', () {
      for (final t in TriggerClass.values) {
        expect(t.label, isNotEmpty);
        expect(t.description, isNotEmpty);
      }
    });
  });

  group('Rueckblick-Differenz — die nuetzlichste Zahl des Moduls', () {
    PostMortem review(String id, int hindsight) => PostMortem(
          incidentId: id,
          at: now,
          rootCause: 'geklaert',
          intensityInHindsight: hindsight,
        );

    test('zeigt, um wie viel niedriger es im Rueckblick ausfaellt', () {
      final delta = log.hindsightDelta(
        incidents: [
          incidentOf(id: 'a', intensity: 5),
          incidentOf(id: 'b', intensity: 4),
          incidentOf(id: 'c', intensity: 5),
        ],
        reviews: [review('a', 3), review('b', 2), review('c', 3)],
      );
      expect(delta, closeTo(2.0, 0.01));
    });

    test('unter drei Faellen keine Zahl — sonst waere sie Zufall', () {
      final delta = log.hindsightDelta(
        incidents: [incidentOf(id: 'a', intensity: 5)],
        reviews: [review('a', 2)],
      );
      expect(delta, isNull);
    });

    test('Nachbetrachtungen ohne Rueckblickwert zaehlen nicht mit', () {
      final delta = log.hindsightDelta(
        incidents: [incidentOf(id: 'a', intensity: 5)],
        reviews: [
          PostMortem(incidentId: 'a', at: now, rootCause: 'x'),
        ],
      );
      expect(delta, isNull);
    });
  });

  test('Nachbetrachtung gilt erst mit benannter Ursache als vollstaendig', () {
    expect(
      PostMortem(incidentId: 'a', at: now, rootCause: 'Kritik in der Sitzung')
          .isComplete,
      isTrue,
    );
    expect(PostMortem(incidentId: 'a', at: now).isComplete, isFalse);
    expect(
      PostMortem(incidentId: 'a', at: now, rootCause: '   ').isComplete,
      isFalse,
    );
  });
}
