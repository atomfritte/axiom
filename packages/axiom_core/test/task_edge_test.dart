/// Aufgaben an den Raendern.
///
/// Der vorhandene Test prueft Score und Startbarkeit im Groben. Hier stehen
/// die Kanten: die Startbarkeit auf den Punkt der Kapazitaet, der
/// Verfallsdruck an seinen beiden Enden, der Fristdruck (`taskRunway`,
/// `tightestDeadline`) mit und ohne Frist, und die Frage, was „offen"
/// eigentlich heisst — sie haengt an genau einer Stelle und wird von drei
/// Mechaniken gelesen.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

final DateTime _noon = DateTime(2026, 8, 3, 12);

Task _task(
  String id, {
  int ae = 2,
  int salience = 5,
  int stakes = 5,
  DateTime? decayAt,
  Duration? estimate,
  TaskState state = TaskState.ready,
  String? place,
}) =>
    Task(
      id: id,
      title: 'Aufgabe $id',
      activationEnergy: ae,
      salience: salience,
      stakes: stakes,
      decayAt: decayAt,
      estimate: estimate,
      state: state,
      place: place,
    );

void main() {
  group('Startbarkeit — die Kapazitaet auf den Punkt', () {
    test('Aktivierungsenergie 5 braucht Kapazitaet 50, nicht 49', () {
      final task = _task('a', ae: 5);
      expect(task.isStartable(49), isFalse);
      expect(task.isStartable(50), isTrue);
    });

    test('bei Kapazitaet 0 ist nichts startbar', () {
      // Auch nicht die billigste Aufgabe: Aktivierungsenergie faengt bei 1
      // an, es gibt keine kostenlose Handlung.
      expect(_task('a', ae: 1).isStartable(0), isFalse);
      expect(_task('a', ae: 1).isStartable(10), isTrue);
    });

    test('bei voller Kapazitaet ist auch das Schwerste startbar', () {
      expect(_task('a', ae: 10).isStartable(100), isTrue);
      expect(_task('a', ae: 10).isStartable(99), isFalse);
    });

    test('nur ready ist startbar — kein anderer Zustand', () {
      for (final state in TaskState.values) {
        expect(
          _task('a', ae: 1, state: state).isStartable(100),
          state == TaskState.ready,
          reason: state.name,
        );
      }
    });

    test('der Ort unterdrueckt nur, wenn tatsaechlich einer gesetzt ist', () {
      final imBaumarkt = _task('a', ae: 1, place: 'Baumarkt');
      expect(imBaumarkt.isStartable(100), isTrue);
      expect(imBaumarkt.isStartable(100, atPlace: ''), isTrue);
      expect(imBaumarkt.isStartable(100, atPlace: '   '), isTrue);
      expect(imBaumarkt.isStartable(100, atPlace: 'baumarkt '), isTrue);
      expect(imBaumarkt.isStartable(100, atPlace: 'Büro'), isFalse);
    });
  });

  group('Verfallsdruck an beiden Enden [D12]', () {
    double score(Duration? bisFrist) => taskScore(
        _task('a', ae: 1, salience: 5, stakes: 5,
            decayAt: bisFrist == null ? null : _noon.add(bisFrist)),
        _noon);

    test('ueberfaellig erreicht den Hoechstwert und bleibt dort', () {
      final geradeVorbei = score(const Duration(minutes: -1));
      final langeVorbei = score(const Duration(days: -30));
      expect(geradeVorbei, langeVorbei);
    });

    test('genau zur Frist gilt bereits ueberfaellig', () {
      expect(score(Duration.zero), score(const Duration(hours: -1)));
    });

    test('jenseits einer Woche gibt es kaum noch Zug', () {
      final knappUnterWoche = score(const Duration(hours: 167));
      final genauWoche = score(const Duration(hours: 168));
      final weitDanach = score(const Duration(days: 300));
      expect(genauWoche, weitDanach);
      expect(knappUnterWoche, greaterThanOrEqualTo(genauWoche));
    });

    test('ohne Frist liegt der Druck zwischen den Enden, nicht bei null', () {
      // Ohne Termin soll eine Aufgabe nicht verschwinden — nur weniger
      // ziehen als eine mit naher Frist.
      final ohne = score(null);
      expect(ohne, greaterThan(0));
      expect(ohne, lessThan(score(const Duration(hours: 2))));
    });

    test('der Druck faellt monoton, je weiter die Frist weg ist', () {
      var vorher = double.infinity;
      for (final stunden in [0, 1, 12, 48, 100, 167, 168, 1000]) {
        final jetzt = score(Duration(hours: stunden));
        expect(jetzt, lessThanOrEqualTo(vorher), reason: '$stunden h');
        vorher = jetzt;
      }
    });
  });

  group('Anlauf und Rest — die Rechnung, die sonst im Kopf laeuft [D4]', () {
    test('der Kaltstart steht vorn und wiegt schwer', () {
      expect(taskRunway(_task('a', ae: 1)),
          kStartCostPerEnergy + kDefaultTaskWork);
      expect(taskRunway(_task('a', ae: 4)),
          kStartCostPerEnergy * 4 + kDefaultTaskWork);
    });

    test('ohne Schaetzung wird mit der Voreinstellung gerechnet', () {
      expect(
        taskRunway(_task('a', ae: 2)) -
            taskRunway(_task('a', ae: 2, estimate: const Duration(hours: 2))),
        kDefaultTaskWork - const Duration(hours: 2),
      );
    });

    test('verglichen wird der Rest, nicht die naechste Frist', () {
      // Eine Frist in vier Stunden mit zwanzig Minuten Anlauf draengt
      // weniger als eine in acht Stunden mit sechs Stunden Anlauf.
      final locker = _task('locker',
          ae: 1, decayAt: _noon.add(const Duration(hours: 4)));
      final knapp = _task('knapp',
          ae: 10,
          estimate: const Duration(hours: 4),
          decayAt: _noon.add(const Duration(hours: 8)));

      final best = tightestDeadline([locker, knapp], _noon)!;
      expect(best.task.id, 'knapp');
      // Die spaetere Frist gewinnt, obwohl sie spaeter liegt — verglichen
      // wird, was nach dem Anlauf uebrig bleibt.
      expect(best.untilDue, greaterThan(const Duration(hours: 4)));
      expect(best.untilDue - best.runway,
          lessThan(const Duration(hours: 4) - const Duration(minutes: 45)));
    });

    test('ist der Anlauf laenger als die Frist, wird der Rest negativ', () {
      // Der Moment, in dem Anfangen noch gereicht haette, ist dann vorbei —
      // die Zahl, die sonst systematisch zu optimistisch geschaetzt wird.
      final zuSpaet = _task('zuspaet',
          ae: 10,
          estimate: const Duration(hours: 4),
          decayAt: _noon.add(const Duration(hours: 2)));
      final best = tightestDeadline([zuSpaet], _noon)!;
      expect((best.untilDue - best.runway).isNegative, isTrue);
    });

    test('ohne Frist gibt es keinen Kandidaten', () {
      expect(tightestDeadline([_task('a'), _task('b')], _noon), isNull);
    });

    test('aus einer leeren Liste kommt nichts', () {
      expect(tightestDeadline(const [], _noon), isNull);
    });

    test('nur was laufen kann, draengt', () {
      // Erledigtes, Verworfenes, Zerlegtes und Notizen im Eingang haben
      // keine Frist, die etwas bedeutet.
      final tasks = [
        for (final state in TaskState.values)
          _task(state.name,
              state: state, decayAt: _noon.add(const Duration(hours: 1))),
      ];
      final ids = <String>{};
      for (final task in tasks) {
        final best = tightestDeadline([task], _noon);
        if (best != null) ids.add(best.task.id);
      }
      expect(ids, {'ready', 'active'});
    });

    test('Stunden werden auf eine Stelle gerundet — sonst liest es niemand',
        () {
      expect(hoursOf(const Duration(minutes: 359)), 6.0);
      expect(hoursOf(const Duration(minutes: 90)), 1.5);
      expect(hoursOf(const Duration(minutes: 5)), 0.1);
      expect(hoursOf(const Duration(minutes: -90)), -1.5);
      expect(hoursOf(Duration.zero), 0.0);
    });

    test('„keine Frist" ist eine Zahl, kein null', () {
      // Eine Bedingung, deren Variable nicht aufloest, bricht die
      // Auswertung ab. Deshalb eine Zahl, die keine Regel unterschreitet.
      expect(kNoDeadlineHours, greaterThan(hoursOf(const Duration(days: 365))));
    });
  });

  group('Hebel', () {
    test('ohne aufgehaltene Aufgaben veraendert er nichts', () {
      expect(taskLeverage(0), 1.0);
      expect(taskLeverage(-1), 1.0);
    });

    test('jede Verdopplung kostet denselben Zuschlag', () {
      final schritte = [
        taskLeverage(1) - taskLeverage(0),
        taskLeverage(3) - taskLeverage(1),
        taskLeverage(7) - taskLeverage(3),
        taskLeverage(15) - taskLeverage(7),
      ];
      for (final schritt in schritte) {
        expect(schritt, closeTo(kLeverageWeight, 0.001));
      }
    });

    test('er steht im Zaehler, nicht im Nenner', () {
      // Eine Aufgabe wird nicht leichter anzufangen, nur weil etwas an ihr
      // haengt [D2]. Der Faktor muss deshalb den Wert heben, nicht die
      // Kosten senken.
      final billig = taskScore(_task('a', ae: 1), _noon);
      final teuer = taskScore(_task('b', ae: 5), _noon, unblocks: 15);
      expect(teuer, lessThan(billig));
    });
  });

  group('Zerlegungsbedarf', () {
    test('greift genau unter 72 Stunden bis zur Frist', () {
      Task mit(Duration bisFrist) => _task('a',
          ae: 9, stakes: 9, decayAt: _noon.add(bisFrist));
      expect(needsAtomizing(mit(const Duration(hours: 72)), 50, _noon), isFalse);
      expect(
        needsAtomizing(mit(const Duration(hours: 71, minutes: 59)), 50, _noon),
        isTrue,
      );
    });

    test('greift genau ab Konsequenz 8', () {
      Task mit(int stakes) => _task('a',
          ae: 9, stakes: stakes, decayAt: _noon.add(const Duration(hours: 5)));
      expect(needsAtomizing(mit(7), 50, _noon), isFalse);
      expect(needsAtomizing(mit(8), 50, _noon), isTrue);
    });

    test('der Ort spielt keine Rolle — geplant wird ueberall', () {
      final imBaumarkt = _task('a',
          ae: 9,
          stakes: 9,
          place: 'Baumarkt',
          decayAt: _noon.add(const Duration(hours: 5)));
      expect(needsAtomizing(imBaumarkt, 50, _noon), isTrue);
    });
  });

  group('„Offen" heisst an einer Stelle dasselbe', () {
    test('Eingang, bereit, laufend und zerlegt sind offen', () {
      for (final state in [
        TaskState.inbox,
        TaskState.ready,
        TaskState.active,
        TaskState.blocked,
      ]) {
        expect(isTaskOpen(_task('a', state: state)), isTrue,
            reason: state.name);
      }
    });

    test('erledigt und verworfen sind es nicht', () {
      expect(isTaskOpen(_task('a', state: TaskState.done)), isFalse);
      expect(isTaskOpen(_task('a', state: TaskState.dropped)), isFalse);
    });

    test('jeder Zustand ist beantwortet — auch ein neuer', () {
      // Die Antwort kommt aus einem `switch` ohne `default`. Faellt hier ein
      // neuer Zustand durch, meldet es der Compiler; dieser Test haelt die
      // Vollstaendigkeit zusaetzlich fest.
      for (final state in TaskState.values) {
        expect(() => isTaskOpen(_task('a', state: state)), returnsNormally,
            reason: state.name);
      }
    });
  });

  group('Wertebereiche', () {
    test('Aktivierungsenergie, Zug und Konsequenz liegen in 1..10', () {
      expect(() => _task('a', ae: 0), throwsA(isA<AssertionError>()));
      expect(() => _task('a', ae: 11), throwsA(isA<AssertionError>()));
      expect(() => _task('a', salience: 0), throwsA(isA<AssertionError>()));
      expect(() => _task('a', stakes: 11), throwsA(isA<AssertionError>()));
    });

    test('copyWith behaelt die Kennung und alles Uebrige', () {
      final vorher = _task('a',
          ae: 3,
          decayAt: _noon,
          estimate: const Duration(minutes: 45),
          place: 'Büro');
      final nachher = vorher.copyWith(state: TaskState.active);
      expect(nachher.id, 'a');
      expect(nachher.state, TaskState.active);
      expect(nachher.activationEnergy, 3);
      expect(nachher.decayAt, _noon);
      expect(nachher.estimate, const Duration(minutes: 45));
      expect(nachher.place, 'Büro');
    });
  });

  test('Determinismus: gleicher Bestand, gleicher Score', () {
    final task = _task('a',
        ae: 3, salience: 4, stakes: 6, decayAt: _noon.add(const Duration(hours: 6)));
    expect(taskScore(task, _noon, unblocks: 3),
        taskScore(task, _noon, unblocks: 3));
  });
}
