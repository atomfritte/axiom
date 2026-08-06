/// R-002 — „Check-in Mittag".
///
/// Der zweite Messpunkt liefert die Daten fuer das circadiane Profil [D1].
/// Interessant an ihm ist nicht das Fenster, sondern der Zaehler: Die Regel
/// fragt nicht „gab es heute einen Mittags-Check-in", sondern „gab es heute
/// weniger als zwei Check-ins". Wer den Morgen zweimal erfasst hat — etwa
/// nach einer Korrektur —, wird mittags nicht mehr gefragt. Das ist eine
/// Eigenschaft der Regel, keine Nebenwirkung, und deshalb steht sie hier
/// als Test.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Der Bedingungsbaum aus rules/core/s1-baseline.yaml, Wort fuer Wort.
Condition r002() => Condition.fromMap({
      'all': [
        {
          'time_between': ['13:45', '14:30'],
        },
        {
          'count_today': {'event': 'checkin', 'lt': 2},
        },
      ],
    });

EvalContext contextAt(
  int hour,
  int minute, {
  int checkinsToday = 1,
}) =>
    StateEvalContext(
      state: stateOf(),
      clock: FakeClock(DateTime(2026, 8, 3, hour, minute)),
      runtime: RuntimeContext(
        countTodayByEvent: {'checkin': checkinsToday},
      ),
    );

void main() {
  group('R-002 haelt sein Fenster', () {
    test('13:44 noch nicht', () {
      expect(r002().eval(contextAt(13, 44)), isFalse);
    });

    test('13:45 schon', () {
      expect(r002().eval(contextAt(13, 45)), isTrue);
    });

    test('14:30 noch', () {
      expect(r002().eval(contextAt(14, 30)), isTrue);
    });

    test('14:31 nicht mehr', () {
      expect(r002().eval(contextAt(14, 31)), isFalse);
    });

    test('am Vormittag nicht, obwohl der Zaehler passt', () {
      // Sonst waere die Zeit nur Kosmetik und der Tagesverlauf, den die
      // Regel messen soll, waere aus den Daten nicht mehr ablesbar.
      expect(r002().eval(contextAt(9, 0, checkinsToday: 0)), isFalse);
    });
  });

  group('R-002 zaehlt Messpunkte, nicht Tageszeiten', () {
    test('ein Check-in bisher — sie fragt', () {
      expect(r002().eval(contextAt(14, 0, checkinsToday: 1)), isTrue);
    });

    test('zwei Check-ins bisher — sie ist still', () {
      expect(r002().eval(contextAt(14, 0, checkinsToday: 2)), isFalse);
    });

    test('kein Check-in bisher — sie fragt trotzdem', () {
      // Der Morgen ist ausgefallen. Die Regel holt ihn nicht nach und
      // kommentiert ihn auch nicht — sie fragt einfach jetzt.
      expect(r002().eval(contextAt(14, 0, checkinsToday: 0)), isTrue);
    });

    test('zwei Morgen-Check-ins schliessen den Mittag aus', () {
      // Dokumentierte Kante, kein Versehen: Der Zaehler kennt keinen Slot.
      // Zwei Erfassungen vor 13:45 — etwa eine Korrektur — nehmen dem Tag
      // seinen zweiten Messpunkt. Wer das aendern will, muesste den Slot
      // im Ereignis mitzaehlen, nicht die Anzahl.
      expect(r002().eval(contextAt(13, 50, checkinsToday: 2)), isFalse);
    });
  });

  test('R-002 kommt durch die Systemgrenzen', () {
    final rule = ruleOf(
      id: 'R-002',
      when: r002(),
      action: ActionType.promptCheckin,
      priority: 65,
      cooldown: const Cooldown(minInterval: Duration(minutes: 60), maxPerDay: 1),
    );
    final now = DateTime(2026, 8, 3, 14);
    expect(fireOnce(rule, ctx: contextAt(14, 0), nowLocal: now).fired, isTrue);
  });
}
