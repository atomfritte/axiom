/// Blocker-Beziehungen: A blockiert B. Genau eine Beziehungsart.
///
/// Geprueft wird Wirkung, nicht Implementierung: Was wartet, was ist wieder
/// startbar, was wird abgelehnt — nicht, welche Methode dabei laeuft.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

final _noon = DateTime(2026, 8, 3, 12);

Task taskOf(
  String id, {
  int ae = 3,
  int salience = 5,
  int stakes = 5,
  TaskState state = TaskState.ready,
}) =>
    Task(
      id: id,
      title: 'Aufgabe $id',
      activationEnergy: ae,
      salience: salience,
      stakes: stakes,
      state: state,
    );

TaskLink link(String blocker, String blocked) =>
    TaskLink(blockerId: blocker, blockedId: blocked);

void main() {
  group('Warten wird gerechnet, nicht gespeichert', () {
    test('eine Aufgabe mit offenem Blocker wartet', () {
      final graph = TaskLinkGraph.from(
        tasks: [taskOf('a'), taskOf('b')],
        links: [link('a', 'b')],
      );

      expect(graph.isWaiting('b'), isTrue);
      expect(graph.blockersOf('b'), ['a']);
      // Der Blocker selbst wartet auf nichts.
      expect(graph.isWaiting('a'), isFalse);
      expect(graph.blockedBy('a'), ['b']);
    });

    test('ein erledigter Blocker haelt nichts mehr auf', () {
      final graph = TaskLinkGraph.from(
        tasks: [taskOf('a', state: TaskState.done), taskOf('b')],
        links: [link('a', 'b')],
      );

      expect(graph.isWaiting('b'), isFalse);
      expect(graph.blockersOf('b'), isEmpty);
    });

    test('ein verworfener Blocker ebenso', () {
      final graph = TaskLinkGraph.from(
        tasks: [taskOf('a', state: TaskState.dropped), taskOf('b')],
        links: [link('a', 'b')],
      );
      expect(graph.isWaiting('b'), isFalse);
    });

    test('der letzte erledigte Blocker gibt die Aufgabe frei', () {
      final tasks = [taskOf('a'), taskOf('b'), taskOf('c')];
      final links = [link('a', 'c'), link('b', 'c')];

      expect(TaskLinkGraph.from(tasks: tasks, links: links).isWaiting('c'),
          isTrue);

      // Erst einer fertig — sie wartet weiter.
      final einer = [
        taskOf('a', state: TaskState.done),
        taskOf('b'),
        taskOf('c'),
      ];
      expect(TaskLinkGraph.from(tasks: einer, links: links).isWaiting('c'),
          isTrue);

      // Beide fertig — sie ist frei, ohne dass irgendwo etwas nachgezogen
      // werden musste. Genau dafuer ist „wartet" kein Zustand.
      final beide = [
        taskOf('a', state: TaskState.done),
        taskOf('b', state: TaskState.done),
        taskOf('c'),
      ];
      expect(TaskLinkGraph.from(tasks: beide, links: links).isWaiting('c'),
          isFalse);
    });

    test('eine zerlegte Aufgabe blockiert weiter — sie ist nicht erledigt', () {
      // Die Namensfalle: `blocked` heisst zerlegt. Eine zerlegte Aufgabe ist
      // offen und haelt deshalb auf, was an ihr haengt.
      final graph = TaskLinkGraph.from(
        tasks: [taskOf('a', state: TaskState.blocked), taskOf('b')],
        links: [link('a', 'b')],
      );
      expect(graph.isWaiting('b'), isTrue);
    });

    test('eine Kante ins Leere haelt niemanden auf', () {
      // Eine Aufgabe wegen eines Verweises auf etwas Verschwundenes fuer
      // immer warten zu lassen waere der schlimmere Fehler [D9].
      final graph = TaskLinkGraph.from(
        tasks: [taskOf('b')],
        links: [link('weg', 'b')],
      );
      expect(graph.isWaiting('b'), isFalse);
    });
  });

  group('Hebel — transitiv gemessen, nicht geraten', () {
    test('zaehlt die ganze Kette, nicht nur die direkt Blockierten', () {
      // a -> b -> c -> d
      final graph = TaskLinkGraph.from(
        tasks: [taskOf('a'), taskOf('b'), taskOf('c'), taskOf('d')],
        links: [link('a', 'b'), link('b', 'c'), link('c', 'd')],
      );

      expect(graph.unblocks('a'), 3);
      expect(graph.unblocks('b'), 2);
      expect(graph.unblocks('d'), 0);
    });

    test('zaehlt eine Aufgabe einmal, auch wenn zwei Wege zu ihr fuehren', () {
      // a -> b -> d,  a -> c -> d
      final graph = TaskLinkGraph.from(
        tasks: [taskOf('a'), taskOf('b'), taskOf('c'), taskOf('d')],
        links: [
          link('a', 'b'),
          link('a', 'c'),
          link('b', 'd'),
          link('c', 'd'),
        ],
      );
      expect(graph.unblocks('a'), 3);
    });

    test('erledigte Aufgaben zaehlen nicht mit', () {
      final graph = TaskLinkGraph.from(
        tasks: [taskOf('a'), taskOf('b', state: TaskState.done), taskOf('c')],
        links: [link('a', 'b'), link('a', 'c')],
      );
      expect(graph.unblocks('a'), 1);
    });

    test('drei Blockierte machen eine Aufgabe nicht dreimal so wichtig', () {
      // Der eigentliche Punkt der Formelwahl: Hebel ja, Explosion nein.
      expect(taskLeverage(0), 1.0);
      expect(taskLeverage(1), closeTo(1.35, 0.01));
      expect(taskLeverage(3), closeTo(1.70, 0.01));
      expect(taskLeverage(7), closeTo(2.05, 0.01));

      final ohne = taskScore(taskOf('a', ae: 1, salience: 3, stakes: 3), _noon);
      final mit = taskScore(taskOf('a', ae: 1, salience: 3, stakes: 3), _noon,
          unblocks: 3);
      expect(mit, greaterThan(ohne));
      expect(mit, lessThan(ohne * 2));
    });

    test('ein Blocker zieht an einer gleich teuren Aufgabe vorbei', () {
      final blocker =
          taskOf('frei', ae: 1, salience: 3, stakes: 3); // haelt drei auf
      final andere = taskOf('sonst', ae: 1, salience: 5, stakes: 5);

      expect(taskScore(blocker, _noon), lessThan(taskScore(andere, _noon)));
      expect(
        taskScore(blocker, _noon, unblocks: 3),
        greaterThan(taskScore(andere, _noon)),
      );
    });

    test('der Hebel senkt nicht die Kosten des Starts', () {
      // Eine Aufgabe wird nicht leichter anzufangen, nur weil etwas an ihr
      // haengt. Die teure bleibt hinter der billigen, solange der Hebel
      // gleich ist [D2].
      final teuer = taskOf('teuer', ae: 9);
      final billig = taskOf('billig', ae: 1);
      expect(
        taskScore(teuer, _noon, unblocks: 3),
        lessThan(taskScore(billig, _noon, unblocks: 3)),
      );
    });
  });

  group('Zyklen sind ein Fehler, kein Sonderfall', () {
    test('ein Kreis ueber drei Ecken wird abgelehnt', () {
      // a blockiert b blockiert c — und c soll a blockieren.
      final existing = [link('a', 'b'), link('b', 'c')];

      expect(
        () => ensureAcyclic(
            existing: existing, blockerId: 'c', blockedId: 'a'),
        throwsA(isA<TaskLinkCycleError>()),
      );

      try {
        ensureAcyclic(existing: existing, blockerId: 'c', blockedId: 'a');
        fail('Der Kreis wurde nicht erkannt');
      } on TaskLinkCycleError catch (e) {
        // Der Weg zeigt, wo er sich schliesst — sonst ist die Meldung
        // richtig und nutzlos.
        expect(e.path, ['c', 'a', 'b', 'c']);
      }
    });

    test('auch der kurze Kreis ueber zwei Ecken', () {
      expect(
        () => ensureAcyclic(
            existing: [link('a', 'b')], blockerId: 'b', blockedId: 'a'),
        throwsA(isA<TaskLinkCycleError>()),
      );
    });

    test('eine Aufgabe kann sich nicht selbst blockieren', () {
      try {
        ensureAcyclic(existing: const [], blockerId: 'a', blockedId: 'a');
        fail('Selbstblockade wurde nicht erkannt');
      } on TaskLinkCycleError catch (e) {
        expect(e.path, ['a', 'a']);
      }
    });

    test('eine Beziehung ohne Kreis geht durch', () {
      // Rauten sind erlaubt: a haelt b und c auf, beide halten d auf. Das ist
      // kein Kreis, nur ein Geflecht — und es laehmt nichts.
      ensureAcyclic(
        existing: [link('a', 'b'), link('a', 'c'), link('b', 'd')],
        blockerId: 'c',
        blockedId: 'd',
      );
    });

    test('die Pruefung ist rein: gleiche Eingabe, gleiche Ausgabe', () {
      // Bei mehreren moeglichen Wegen darf nicht mal der eine, mal der
      // andere gemeldet werden — eine wechselnde Fehlermeldung ist keine.
      final existing = [
        link('a', 'b'),
        link('a', 'c'),
        link('b', 'z'),
        link('c', 'z'),
      ];
      final paths = <List<String>>[];
      for (var i = 0; i < 5; i++) {
        try {
          ensureAcyclic(
              existing: existing, blockerId: 'z', blockedId: 'a');
          fail('Der Kreis wurde nicht erkannt');
        } on TaskLinkCycleError catch (e) {
          paths.add(e.path);
        }
      }
      expect(paths.every((p) => p.join() == paths.first.join()), isTrue);
      // Der kuerzeste Kreis, nicht irgendeiner.
      expect(paths.first, ['z', 'a', 'b', 'z']);
    });
  });
}
