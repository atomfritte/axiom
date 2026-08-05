import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

void main() {
  const atomizer = Atomizer();
  final now = DateTime(2026, 8, 3, 10);

  Task taskOf({
    String id = 't1',
    int ae = 8,
    int stakes = 9,
    int salience = 5,
    DateTime? decayAt,
    String? parentId,
    TaskState state = TaskState.ready,
  }) =>
      Task(
        id: id,
        title: 'Steuerunterlagen sortieren',
        activationEnergy: ae,
        salience: salience,
        stakes: stakes,
        decayAt: decayAt,
        parentId: parentId,
        state: state,
      );

  group('Kandidaten finden [D2]', () {
    test('wichtig, bald fällig, außer Reichweite', () {
      final task = taskOf(decayAt: now.add(const Duration(hours: 24)));
      final found = atomizer.candidates(
        tasks: [task],
        capacity: 40,
        now: now,
        createdAt: {'t1': now},
      );
      expect(found, hasLength(1));
      expect(found.single.reason, AtomizeReason.urgentButUnreachable);
    });

    test('lange unangetastet — der klassische Schuld-Erzeuger', () {
      final found = atomizer.candidates(
        tasks: [taskOf(ae: 6, stakes: 4)],
        capacity: 40,
        now: now,
        createdAt: {'t1': now.subtract(const Duration(days: 20))},
      );
      expect(found.single.reason, AtomizeReason.stale);
    });

    test('grundsätzlich schwerer Einstieg', () {
      final found = atomizer.candidates(
        tasks: [taskOf(ae: 9, stakes: 3)],
        capacity: 40,
        now: now,
        createdAt: {'t1': now},
      );
      expect(found.single.reason, AtomizeReason.inherentlyHeavy);
    });

    test('startbare Aufgaben werden nicht angeboten', () {
      final found = atomizer.candidates(
        tasks: [taskOf(ae: 2)],
        capacity: 80,
        now: now,
        createdAt: {'t1': now},
      );
      expect(found, isEmpty);
    });

    test('bereits zerlegte Aufgaben werden nicht erneut angeboten', () {
      final parent = taskOf(id: 'p1', ae: 9);
      final child = taskOf(id: 'c1', ae: 2, parentId: 'p1');
      final found = atomizer.candidates(
        tasks: [parent, child],
        capacity: 40,
        now: now,
        createdAt: {'p1': now, 'c1': now},
      );
      expect(found.map((c) => c.task.id), isNot(contains('p1')));
    });

    test('ein zu groß geratener Teilschritt wird selbst angeboten', () {
      // Der Kern von D2: Ist der erste Schritt immer noch zu groß,
      // passiert nichts — es sei denn, er laesst sich weiter zerlegen.
      final parent = taskOf(id: 'p1', ae: 9, state: TaskState.blocked);
      final step = taskOf(id: 'c1', ae: 5, stakes: 3, parentId: 'p1');
      final found = atomizer.candidates(
        tasks: [parent, step],
        capacity: 30,
        now: now,
        createdAt: {'p1': now, 'c1': now},
      );
      expect(found.map((c) => c.task.id), contains('c1'));
    });

    test('außer Reichweite genügt als Grund — ohne Frist, ohne Alter', () {
      final found = atomizer.candidates(
        tasks: [taskOf(ae: 5, stakes: 3, salience: 3)],
        capacity: 30,
        now: now,
        createdAt: {'t1': now},
      );
      expect(found.single.reason, AtomizeReason.outOfReach);
    });

    test('erledigte Teilschritte halten die Klammer nicht mehr zurück', () {
      // Sonst gilt eine Aufgabe für immer als „schon zerlegt", auch wenn
      // von der Zerlegung nichts mehr offen ist.
      final parent = taskOf(id: 'p1', ae: 9);
      final done = taskOf(id: 'c1', ae: 2, parentId: 'p1', state: TaskState.done);
      final found = atomizer.candidates(
        tasks: [parent, done],
        capacity: 40,
        now: now,
        createdAt: {'p1': now, 'c1': now},
      );
      expect(found.map((c) => c.task.id), contains('p1'));
    });

    test('nur ready — nicht erledigte oder verworfene', () {
      for (final state in [TaskState.done, TaskState.dropped, TaskState.inbox]) {
        final found = atomizer.candidates(
          tasks: [taskOf(ae: 9, state: state)],
          capacity: 30,
          now: now,
          createdAt: {'t1': now},
        );
        expect(found, isEmpty, reason: state.name);
      }
    });

    test('dringende Fälle kommen zuerst', () {
      final urgent = taskOf(
        id: 'urgent',
        decayAt: now.add(const Duration(hours: 12)),
      );
      final heavy = taskOf(id: 'heavy', ae: 9, stakes: 3);
      final found = atomizer.candidates(
        tasks: [heavy, urgent],
        capacity: 40,
        now: now,
        createdAt: {'urgent': now, 'heavy': now},
      );
      expect(found.first.task.id, 'urgent');
    });
  });

  group('Zerlegen auf Zuruf — jede Ebene, ohne Bedingung [D2]', () {
    test('auch ein blockiertes Elternteil lässt sich weiter zerlegen', () {
      final candidate = atomizer.candidateFor(
        task: taskOf(state: TaskState.blocked),
        capacity: 40,
        now: now,
      );
      expect(candidate.task.id, 't1');
      expect(candidate.targetEnergy, greaterThanOrEqualTo(1));
    });

    test('auch eine startbare Aufgabe — der Nutzer entscheidet', () {
      final candidate = atomizer.candidateFor(
        task: taskOf(ae: 2, stakes: 3),
        capacity: 80,
        now: now,
      );
      expect(candidate.reason, AtomizeReason.chosen);
    });

    test('eine laufende Aufgabe gilt nicht als außer Reichweite', () {
      // `isStartable` zieht den Zustand mit hinein; die Begruendung darf
      // das nicht, sonst steht bei einer laufenden Aufgabe „liegt ueber
      // der Kapazitaet".
      final candidate = atomizer.candidateFor(
        task: taskOf(ae: 2, stakes: 3, state: TaskState.active),
        capacity: 80,
        now: now,
      );
      expect(candidate.reason, AtomizeReason.chosen);
    });
  });

  group('Zielenergie', () {
    test('liegt deutlich unter der Kapazität, nicht knapp darunter', () {
      // Ein Schritt, der gerade so passt, passt morgen nicht mehr.
      final found = atomizer.candidates(
        tasks: [taskOf(ae: 9)],
        capacity: 60,
        now: now,
        createdAt: {'t1': now},
      );
      expect(found.single.targetEnergy, lessThan(6));
      expect(found.single.targetEnergy, greaterThanOrEqualTo(1));
    });

    test('bleibt auch bei sehr hoher Kapazität klein', () {
      // Bei Kapazität 95 ist AE 10 knapp außer Reichweite — sonst wäre die
      // Aufgabe startbar und gar kein Kandidat.
      final found = atomizer.candidates(
        tasks: [taskOf(ae: 10)],
        capacity: 95,
        now: now,
        createdAt: {'t1': now},
      );
      expect(found.single.targetEnergy, lessThanOrEqualTo(4));
    });

    test('bei voller Kapazität ist auch das Schwerste startbar', () {
      final found = atomizer.candidates(
        tasks: [taskOf(ae: 10)],
        capacity: 100,
        now: now,
        createdAt: {'t1': now},
      );
      expect(found, isEmpty);
    });
  });

  group('Zerlegen', () {
    test('erzeugt Kinder mit Elternbezug', () {
      var counter = 0;
      final parent = taskOf(ae: 9, stakes: 9, salience: 6);
      final children = atomizer.split(
        parent: parent,
        steps: [
          (title: 'Ordner auf den Tisch legen', energy: 1),
          (title: 'Belege nach Monat sortieren', energy: 4),
        ],
        nextId: () => 'c${counter++}',
      );

      expect(children, hasLength(2));
      expect(children.every((c) => c.parentId == parent.id), isTrue);
      expect(children.first.activationEnergy, 1);
    });

    test('nur der erste Schritt erbt die Frist', () {
      final deadline = now.add(const Duration(days: 2));
      var counter = 0;
      final children = atomizer.split(
        parent: taskOf(decayAt: deadline),
        steps: [
          (title: 'erster', energy: 1),
          (title: 'zweiter', energy: 3),
        ],
        nextId: () => 'c${counter++}',
      );
      expect(children[0].decayAt, deadline);
      expect(children[1].decayAt, isNull);
    });

    test('Teilschritte tragen nicht die volle Konsequenz des Ganzen', () {
      var counter = 0;
      final parent = taskOf(stakes: 9);
      final children = atomizer.split(
        parent: parent,
        steps: [
          (title: 'erster', energy: 1),
          (title: 'zweiter', energy: 3),
        ],
        nextId: () => 'c${counter++}',
      );
      // Sonst erzeugt jeder Teilschritt denselben Druck wie das Ganze.
      expect(children[0].stakes, lessThan(parent.stakes));
      expect(children[1].stakes, lessThan(children[0].stakes));
    });

    test('eine Aufgabe mit Energie 1 lässt sich zerlegen', () {
      // Der Rest wird als „eine Stufe leichter" abgeleitet, und bei 1 kam
      // dabei 0 heraus — ausserhalb des Wertebereichs von Task.
      var counter = 0;
      final children = atomizer.split(
        parent: taskOf(ae: 1),
        steps: [
          (title: 'erster Handgriff', energy: 1),
          (title: 'der Rest', energy: 0),
        ],
        nextId: () => 'c${counter++}',
      );
      expect(children.last.activationEnergy, 1);
    });

    test('Kinder sind sofort startbar, nicht im Eingang', () {
      var counter = 0;
      final children = atomizer.split(
        parent: taskOf(),
        steps: [(title: 'erster', energy: 1)],
        nextId: () => 'c${counter++}',
      );
      expect(children.single.state, TaskState.ready);
    });
  });

  group('Gelungene Zerlegung', () {
    test('mindestens ein Schritt muss in Reichweite liegen', () {
      var counter = 0;
      final good = atomizer.split(
        parent: taskOf(),
        steps: [(title: 'klein', energy: 2), (title: 'groß', energy: 8)],
        nextId: () => 'c${counter++}',
      );
      expect(atomizer.isSufficient(good, 40), isTrue);
    });

    test('zu grobe Zerlegung wird erkannt', () {
      var counter = 0;
      final bad = atomizer.split(
        parent: taskOf(),
        steps: [(title: 'immer noch groß', energy: 7)],
        nextId: () => 'c${counter++}',
      );
      expect(atomizer.isSufficient(bad, 40), isFalse);
    });
  });

  group('Formenkatalog', () {
    test('jede Form hat Bezeichnung und konkrete Beispiele', () {
      for (final shape in StepShape.values) {
        expect(shape.label, isNotEmpty);
        expect(shape.examples, isNotEmpty);
      }
    });

    test('Begründungen benennen den Zustand ohne Vorwurf', () {
      for (final reason in AtomizeReason.values) {
        final text = AtomizeCandidate(
          task: taskOf(),
          reason: reason,
          targetEnergy: 2,
        ).explanation;
        expect(text, isNotEmpty);
        for (final blame in ['versagt', 'endlich', 'schon wieder', 'faul']) {
          expect(text.toLowerCase(), isNot(contains(blame)));
        }
      }
    });
  });
}
