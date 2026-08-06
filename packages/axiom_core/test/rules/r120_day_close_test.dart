/// R-120 — „Tagesabschluss" (M11 Review Cadence).
///
/// Zwei Minuten, zwei Fragen. Ohne taeglichen Abschluss verschwinden Ziele
/// lautlos — jenseits von etwa zwei Wochen sind sie motivational praktisch
/// unsichtbar [D12]. Der Zeitdeckel ist Teil der Regel: Ein Review ohne
/// Grenze wird selbst zur Ausweichbeschaeftigung (D3).
///
/// Das Fenster ueberlappt mit R-003 („Check-in Abend", 20:45–21:45). Das ist
/// gewollt — zwei verschiedene Anlaesse —, aber es heisst, dass R-120 in
/// dieser Dreiviertelstunde regelmaessig den kuerzeren zieht: gleiche
/// Severity, niedrigere Prioritaet. Steht unten als Test, damit die
/// Reihenfolge eine Entscheidung bleibt und kein Zufall wird.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Der Bedingungsbaum aus rules/core/s2-live.yaml, Wort fuer Wort.
Condition r120() => Condition.fromMap({
      'all': [
        {
          'time_between': ['21:00', '22:15'],
        },
        {
          'count_today': {'event': 'review_completed', 'lt': 1},
        },
      ],
    });

EvalContext contextAt(
  int hour,
  int minute, {
  int reviewsToday = 0,
}) =>
    StateEvalContext(
      state: stateOf(),
      clock: FakeClock(DateTime(2026, 8, 3, hour, minute)),
      runtime: RuntimeContext(
        countTodayByEvent: {'review_completed': reviewsToday},
      ),
    );

void main() {
  group('R-120 haelt sein Fenster', () {
    test('20:59 noch nicht', () {
      expect(r120().eval(contextAt(20, 59)), isFalse);
    });

    test('21:00 schon', () {
      expect(r120().eval(contextAt(21, 0)), isTrue);
    });

    test('22:15 noch', () {
      expect(r120().eval(contextAt(22, 15)), isTrue);
    });

    test('22:16 nicht mehr', () {
      // Danach uebernimmt die Abendgrenze (R-110, ab 22:30). Ein Review,
      // das erst um halb zwoelf beginnt, arbeitet gegen das Sleep Gate.
      expect(r120().eval(contextAt(22, 16)), isFalse);
    });

    test('am Nachmittag nicht', () {
      expect(r120().eval(contextAt(16, 0)), isFalse);
    });
  });

  group('R-120 fragt genau einmal am Tag', () {
    test('noch kein Rueckblick — sie meldet sich', () {
      expect(r120().eval(contextAt(21, 30)), isTrue);
    });

    test('Rueckblick erledigt — sie ist still', () {
      expect(
        r120().eval(contextAt(21, 30, reviewsToday: 1)),
        isFalse,
        reason: 'Kommentarlos uebernehmen, dass es schon passiert ist',
      );
    });

    test('fehlender Zaehler heisst null', () {
      final ctx = StateEvalContext(
        state: stateOf(),
        clock: FakeClock(DateTime(2026, 8, 3, 21, 30)),
        runtime: const RuntimeContext(),
      );
      expect(r120().eval(ctx), isTrue);
    });
  });

  group('R-120 und die Systemgrenzen', () {
    Rule rule() => ruleOf(
          id: 'R-120',
          when: r120(),
          priority: 65,
          cooldown:
              const Cooldown(minInterval: Duration(minutes: 240), maxPerDay: 1),
        );

    test('das Fenster endet vor der Ruhezeit', () {
      final now = DateTime(2026, 8, 3, 22, 15);
      expect(fireOnce(rule(), ctx: contextAt(22, 15), nowLocal: now).fired, isTrue);
    });

    test('im Ueberlappungsfenster gewinnt der Abend-Check-in', () {
      // Beide nudge, R-003 hat 75 gegen 65. Das ist die richtige
      // Reihenfolge: Der Messpunkt liefert die Daten, auf denen der
      // Rueckblick beruht. Umgekehrt saehe man den Tag ohne seine Zahlen an.
      final now = DateTime(2026, 8, 3, 21, 30);
      final result = const RuleEngine().evaluate(
        rules: [
          rule(),
          ruleOf(id: 'R-003', priority: 75),
        ],
        ctx: contextAt(21, 30),
        history: FakeHistory(),
        nowLocal: now,
      );
      final resolved = const DecisionResolver().resolve(
        fired: result.fired,
        at: now,
        stateSnapshotId: 'snapshot',
        explain: (r) => r.rationale,
        nextId: () => 'decision-1',
      );
      expect(resolved.winner?.ruleId, 'R-003');
      expect(resolved.suppressed.map((d) => d.ruleId), ['R-120']);
    });

    test('nach 21:45 hat R-120 das Feld fuer sich', () {
      // Die Ueberlappung endet mit dem Check-in-Fenster. Deshalb ist R-120
      // keine dauerhaft verdraengte Regel, sondern eine mit spaeterem
      // Anlauf — ein Unterschied, den man nur sieht, wenn man beide
      // Fensterenden kennt.
      final now = DateTime(2026, 8, 3, 22, 0);
      final result = const RuleEngine().evaluate(
        rules: [
          rule(),
          ruleOf(
            id: 'R-003',
            when: Condition.fromMap({
              'all': [
                {
                  'time_between': ['20:45', '21:45'],
                },
                {
                  'count_today': {'event': 'checkin', 'lt': 3},
                },
              ],
            }),
            priority: 75,
          ),
        ],
        ctx: contextAt(22, 0),
        history: FakeHistory(),
        nowLocal: now,
      );
      expect(result.fired.map((f) => f.rule.id), ['R-120']);
    });
  });
}
