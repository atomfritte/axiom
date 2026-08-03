import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Task taskOf({
  String id = 't1',
  int ae = 5,
  int salience = 5,
  int stakes = 5,
  DateTime? decayAt,
  TaskState state = TaskState.ready,
}) =>
    Task(
      id: id,
      title: 'Aufgabe $id',
      activationEnergy: ae,
      salience: salience,
      stakes: stakes,
      decayAt: decayAt,
      state: state,
    );

void main() {
  group('Startbarkeit — Aktivierungsenergie statt Prioritaet [D2]', () {
    test('sichtbar nur, wenn AE unter der Kapazitaet liegt', () {
      final hard = taskOf(ae: 8);
      expect(hard.isStartable(90), isTrue);
      expect(hard.isStartable(40), isFalse);
    });

    test('nicht startbar, solange die Aufgabe nicht ready ist', () {
      expect(taskOf(ae: 1, state: TaskState.inbox).isStartable(100), isFalse);
      expect(taskOf(ae: 1, state: TaskState.blocked).isStartable(100), isFalse);
    });
  });

  group('Score', () {
    test('niedrige Aktivierungsenergie gewinnt bei sonst gleichen Werten', () {
      final easy = taskOf(id: 'easy', ae: 2);
      final hard = taskOf(id: 'hard', ae: 9);
      expect(taskScore(easy, testNoon), greaterThan(taskScore(hard, testNoon)));
    });

    test('naher Verfall erhoeht den Score', () {
      final soon = taskOf(
        id: 'soon',
        decayAt: testNoon.add(const Duration(hours: 2)),
      );
      final later = taskOf(
        id: 'later',
        decayAt: testNoon.add(const Duration(days: 30)),
      );
      expect(taskScore(soon, testNoon), greaterThan(taskScore(later, testNoon)));
    });

    test('ueberfaellige Aufgabe erreicht maximalen Verfallsdruck', () {
      final overdue = taskOf(
        id: 'overdue',
        decayAt: testNoon.subtract(const Duration(days: 1)),
      );
      final noDeadline = taskOf(id: 'none');
      expect(
        taskScore(overdue, testNoon),
        greaterThan(taskScore(noDeadline, testNoon)),
      );
    });

    test('jenseits einer Woche kaum Zug — Belohnungsdiskontierung [D12]', () {
      final farOut = taskOf(
        id: 'far',
        decayAt: testNoon.add(const Duration(days: 200)),
      );
      final noDeadline = taskOf(id: 'none');
      expect(
        (taskScore(farOut, testNoon) - taskScore(noDeadline, testNoon)).abs(),
        lessThan(0.3),
      );
    });
  });

  group('Atomizer — wichtig + unstartbar wird zerlegt, nicht angemahnt [D2]',
      () {
    test('greift bei hohen Stakes, naher Frist und zu hoher AE', () {
      final task = taskOf(
        ae: 9,
        stakes: 9,
        decayAt: testNoon.add(const Duration(hours: 24)),
      );
      expect(task.isStartable(40), isFalse);
      expect(needsAtomizing(task, 40, testNoon), isTrue);
    });

    test('greift nicht, wenn die Aufgabe ohnehin startbar ist', () {
      final task = taskOf(
        ae: 3,
        stakes: 9,
        decayAt: testNoon.add(const Duration(hours: 24)),
      );
      expect(needsAtomizing(task, 80, testNoon), isFalse);
    });

    test('greift nicht ohne nahe Frist', () {
      final task = taskOf(
        ae: 9,
        stakes: 9,
        decayAt: testNoon.add(const Duration(days: 30)),
      );
      expect(needsAtomizing(task, 40, testNoon), isFalse);
    });

    test('greift nicht bei niedrigen Stakes', () {
      final task = taskOf(
        ae: 9,
        stakes: 3,
        decayAt: testNoon.add(const Duration(hours: 24)),
      );
      expect(needsAtomizing(task, 40, testNoon), isFalse);
    });
  });

  test('unzulaessige Wertebereiche werden abgelehnt', () {
    expect(() => taskOf(ae: 0), throwsA(isA<AssertionError>()));
    expect(() => taskOf(ae: 11), throwsA(isA<AssertionError>()));
    expect(() => taskOf(stakes: 0), throwsA(isA<AssertionError>()));
  });
}
