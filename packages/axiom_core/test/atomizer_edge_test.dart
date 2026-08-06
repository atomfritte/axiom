/// Atomizer an den Raendern.
///
/// Der Atomizer erfindet nichts — er entscheidet, **was** zum Zerlegen
/// angeboten wird und **wie klein** der erste Schritt sein soll. Beides sind
/// Zahlen mit Schwellen, und beide Schwellen entscheiden darueber, ob eine
/// Aufgabe liegen bleibt. Hier stehen die Kanten der Gruende, die
/// Zielenergie an ihren beiden Enden und die Zerlegung mit ungewoehnlichen
/// Eingaben.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

final DateTime _noon = DateTime(2026, 8, 3, 12);
const Atomizer _atomizer = Atomizer();

Task _task(
  String id, {
  int ae = 2,
  int salience = 5,
  int stakes = 5,
  DateTime? decayAt,
  TaskState state = TaskState.ready,
  String? parentId,
}) =>
    Task(
      id: id,
      title: 'Aufgabe $id',
      activationEnergy: ae,
      salience: salience,
      stakes: stakes,
      decayAt: decayAt,
      state: state,
      parentId: parentId,
    );

AtomizeReason _reason(Task task, {int capacity = 60, DateTime? created}) =>
    _atomizer
        .candidateFor(
            task: task, capacity: capacity, now: _noon, createdAt: created)
        .reason;

void main() {
  group('Der Grund wird in fester Rangfolge bestimmt', () {
    test('dringend und unerreichbar schlaegt alles andere', () {
      final task = _task('a',
          ae: 9, stakes: 9, decayAt: _noon.add(const Duration(hours: 5)));
      expect(
        _reason(task, created: _noon.subtract(const Duration(days: 100))),
        AtomizeReason.urgentButUnreachable,
      );
    });

    test('lange liegend schlaegt „von sich aus schwer"', () {
      final task = _task('a', ae: 9);
      expect(
        _reason(task, created: _noon.subtract(const Duration(days: 11))),
        AtomizeReason.stale,
      );
      expect(_reason(task), AtomizeReason.inherentlyHeavy);
    });

    test('„lange liegend" beginnt genau nach zehn Tagen', () {
      final task = _task('a', ae: 1);
      expect(
        _reason(task, created: _noon.subtract(kStaleAfter)),
        isNot(AtomizeReason.stale),
      );
      expect(
        _reason(task,
            created: _noon.subtract(kStaleAfter + const Duration(minutes: 1))),
        AtomizeReason.stale,
      );
    });

    test('„von sich aus schwer" beginnt genau bei Energie 8', () {
      expect(_reason(_task('a', ae: 7), capacity: 100),
          isNot(AtomizeReason.inherentlyHeavy));
      expect(_reason(_task('a', ae: 8), capacity: 100),
          AtomizeReason.inherentlyHeavy);
    });

    test('„ausser Reichweite" beginnt genau ueber der Kapazitaet', () {
      // Gemessen wird Energie gegen Kapazitaet, nicht `isStartable` — sonst
      // zaehlte der Zustand mit hinein.
      expect(_reason(_task('a', ae: 5), capacity: 50), AtomizeReason.chosen);
      expect(
          _reason(_task('a', ae: 6), capacity: 50), AtomizeReason.outOfReach);
    });

    test('ohne jeden Grund bleibt „vom Nutzer gewaehlt"', () {
      // Zerlegen ist nie verboten (G3).
      expect(_reason(_task('a', ae: 1), capacity: 100), AtomizeReason.chosen);
    });

    test('jeder Grund hat einen eigenen Text ohne Vorwurf', () {
      final texte = <String>{};
      for (final reason in AtomizeReason.values) {
        final text = AtomizeCandidate(
                task: _task('a'), reason: reason, targetEnergy: 2)
            .explanation;
        expect(text, isNotEmpty, reason: reason.name);
        expect(text, isNot(contains('!')), reason: reason.name);
        for (final wort in ['versäumt', 'endlich', 'schon wieder', 'faul']) {
          expect(text.toLowerCase(), isNot(contains(wort)),
              reason: reason.name);
        }
        texte.add(text);
      }
      expect(texte, hasLength(AtomizeReason.values.length));
    });
  });

  group('Wer von sich aus angeboten wird — und wer nicht', () {
    List<String> ids(List<Task> tasks, {int capacity = 60}) => _atomizer
        .candidates(
            tasks: tasks, capacity: capacity, now: _noon, createdAt: const {})
        .map((c) => c.task.id)
        .toList();

    test('nur bereite Aufgaben, kein anderer Zustand', () {
      final tasks = [
        for (final state in TaskState.values) _task(state.name, ae: 9, state: state),
      ];
      expect(ids(tasks), ['ready']);
    });

    test('eine Aufgabe mit offenen Schritten steht nicht neben ihren Teilen',
        () {
      final tasks = [
        _task('klammer', ae: 9),
        _task('schritt', ae: 1, parentId: 'klammer'),
      ];
      expect(ids(tasks), isNot(contains('klammer')));
    });

    test('erledigte Schritte halten die Klammer nicht mehr zurueck', () {
      final tasks = [
        _task('klammer', ae: 9),
        _task('schritt', ae: 1, parentId: 'klammer', state: TaskState.done),
      ];
      expect(ids(tasks), contains('klammer'));
    });

    test('eine startbare Aufgabe wird nicht von sich aus angeboten', () {
      expect(ids([_task('a', ae: 2)], capacity: 100), isEmpty);
    });

    test('auf Zuruf laesst sich trotzdem alles zerlegen', () {
      // Der Unterschied zwischen „soll das zerlegt werden?" und „der Nutzer
      // will zerlegen — womit faengt er an?".
      for (final state in TaskState.values) {
        expect(
          () => _atomizer.candidateFor(
              task: _task('a', state: state), capacity: 100, now: _noon),
          returnsNormally,
          reason: state.name,
        );
      }
    });

    test('aus einem leeren Bestand kommt kein Vorschlag', () {
      expect(ids(const []), isEmpty);
    });
  });

  group('Zielenergie', () {
    test('liegt deutlich unter der Kapazitaet, nicht knapp darunter', () {
      // Ein Schritt, der gerade so passt, passt morgen nicht mehr.
      final ziel = _atomizer
          .candidateFor(task: _task('a', ae: 9), capacity: 50, now: _noon)
          .targetEnergy;
      expect(ziel, lessThan(5));
      expect(ziel, 3);
    });

    test('bleibt auch bei voller Kapazitaet klein', () {
      expect(
        _atomizer
            .candidateFor(task: _task('a', ae: 9), capacity: 100, now: _noon)
            .targetEnergy,
        4,
      );
    });

    test('faellt nie unter eins — null waere kein Schritt', () {
      for (final capacity in [0, 1, 10, 16]) {
        final ziel = _atomizer
            .candidateFor(task: _task('a', ae: 9), capacity: capacity, now: _noon)
            .targetEnergy;
        expect(ziel, greaterThanOrEqualTo(1), reason: 'Kapazitaet $capacity');
        expect(ziel, lessThanOrEqualTo(4), reason: 'Kapazitaet $capacity');
      }
    });

    test('waechst monoton mit der Kapazitaet', () {
      var vorher = 0;
      for (var capacity = 0; capacity <= 100; capacity += 5) {
        final ziel = _atomizer
            .candidateFor(task: _task('a', ae: 9), capacity: capacity, now: _noon)
            .targetEnergy;
        expect(ziel, greaterThanOrEqualTo(vorher), reason: 'bei $capacity');
        vorher = ziel;
      }
    });
  });

  group('Zerlegen', () {
    var counter = 0;
    String nextId() => 'k${counter++}';

    setUp(() => counter = 0);

    test('der erste Schritt erbt Frist und Zug, die spaeteren nicht', () {
      final parent = _task('p',
          ae: 9,
          salience: 7,
          stakes: 9,
          decayAt: _noon.add(const Duration(days: 2)));
      final kinder = _atomizer.split(
        parent: parent,
        steps: [
          (title: 'Ordner holen', energy: 1),
          (title: 'Belege sortieren', energy: 3),
        ],
        nextId: nextId,
      );

      expect(kinder.first.decayAt, parent.decayAt);
      expect(kinder.last.decayAt, isNull);
      expect(kinder.first.salience, parent.salience);
      expect(kinder.last.salience, parent.salience - 1);
      expect(kinder.first.stakes, parent.stakes - 1);
      expect(kinder.last.stakes, parent.stakes - 3);
    });

    test('alle Kinder sind sofort bereit, nicht im Eingang', () {
      // Ein Teilschritt, der erst noch einsortiert werden muss, hat den
      // Kaltstart nur verschoben.
      final kinder = _atomizer.split(
        parent: _task('p', ae: 9),
        steps: [(title: 'a', energy: 1), (title: 'b', energy: 2)],
        nextId: nextId,
      );
      for (final kind in kinder) {
        expect(kind.state, TaskState.ready);
        expect(kind.parentId, 'p');
      }
      expect(kinder.map((k) => k.id), ['k0', 'k1']);
    });

    test('eine Energie unter eins wird geklemmt, nicht abgelehnt', () {
      // Aufrufer leiten sie ab („eins unter dem Ganzen"), und bei einer
      // Aufgabe mit Energie 1 kommt dabei 0 heraus. Ein Abbruch verwuerfe
      // den gerade eingetippten Schritt — der teuerste Moment, um etwas zu
      // verlieren [D2].
      final kinder = _atomizer.split(
        parent: _task('p', ae: 1),
        steps: [(title: 'a', energy: 0), (title: 'b', energy: -5)],
        nextId: nextId,
      );
      expect(kinder.map((k) => k.activationEnergy), [1, 1]);
    });

    test('eine Energie ueber zehn ebenso', () {
      final kinder = _atomizer.split(
        parent: _task('p', ae: 9),
        steps: [(title: 'a', energy: 99)],
        nextId: nextId,
      );
      expect(kinder.single.activationEnergy, 10);
    });

    test('die gedaempften Werte fallen nie unter eins', () {
      final kinder = _atomizer.split(
        parent: _task('p', ae: 5, salience: 1, stakes: 1),
        steps: [(title: 'a', energy: 1), (title: 'b', energy: 1)],
        nextId: nextId,
      );
      for (final kind in kinder) {
        expect(kind.salience, greaterThanOrEqualTo(1));
        expect(kind.stakes, greaterThanOrEqualTo(1));
      }
    });

    test('ohne Schritte kommen keine Kinder heraus', () {
      expect(
        _atomizer.split(parent: _task('p'), steps: const [], nextId: nextId),
        isEmpty,
      );
    });

    test('ein einzelner Schritt ist erlaubt — er erbt alles vom Ersten', () {
      final kind = _atomizer.split(
        parent: _task('p', ae: 9, decayAt: _noon),
        steps: [(title: 'a', energy: 1)],
        nextId: nextId,
      ).single;
      expect(kind.decayAt, _noon);
    });
  });

  group('Gelungene Zerlegung', () {
    test('mindestens ein Schritt muss in Reichweite liegen', () {
      final gross = [
        _task('a', ae: 8, state: TaskState.ready),
        _task('b', ae: 9, state: TaskState.ready),
      ];
      expect(_atomizer.isSufficient(gross, 50), isFalse);
      expect(
        _atomizer.isSufficient([...gross, _task('c', ae: 2)], 50),
        isTrue,
      );
    });

    test('ohne Kinder ist nichts gelungen', () {
      // Sonst gaebe eine abgebrochene Zerlegung „passt schon" zurueck.
      expect(_atomizer.isSufficient(const [], 100), isFalse);
    });
  });

  group('Formenkatalog', () {
    test('jede Form ist koerperlich und ueberpruefbar beschrieben', () {
      for (final shape in StepShape.values) {
        expect(shape.label, isNotEmpty, reason: shape.name);
        expect(shape.examples, isNotEmpty, reason: shape.name);
        expect(shape.examples, contains(','),
            reason: '${shape.name} soll mehrere Beispiele nennen');
      }
    });

    test('die Formen sind untereinander verschieden', () {
      expect(StepShape.values.map((s) => s.label).toSet(),
          hasLength(StepShape.values.length));
    });
  });

  test('Determinismus: gleicher Bestand, gleiche Kandidaten', () {
    final tasks = [_task('a', ae: 9), _task('b', ae: 8, stakes: 9)];
    List<String> lauf() => _atomizer
        .candidates(
            tasks: tasks, capacity: 60, now: _noon, createdAt: const {})
        .map((c) => '${c.task.id}:${c.reason.name}:${c.targetEnergy}')
        .toList();
    expect(lauf(), lauf());
  });
}
