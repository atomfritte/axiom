/// R-003 — „Check-in Abend + Kompensationsaufwand".
///
/// Der wichtigste Messpunkt: Kompensationsaufwand und Erholungsqualitaet
/// sind die beiden Signale, die ein hochkompensiertes System vor dem Bruch
/// warnen koennen [D1]. Faellt dieses Fenster aus, faellt der Load Monitor
/// mit aus — und zwar lautlos, weil eine nicht gestellte Frage keine
/// Fehlermeldung erzeugt.
///
/// Der Abend ist zugleich die Stelle, an der es eng wird: R-120
/// („Tagesabschluss", 21:00–22:15) liegt teilweise im selben Fenster, und
/// der Stundendeckel laesst nur zwei Meldungen zu. Die Konfliktaufloesung
/// steht deshalb hier mit im Test.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Der Bedingungsbaum aus rules/core/s1-baseline.yaml, Wort fuer Wort.
Condition r003() => Condition.fromMap({
      'all': [
        {
          'time_between': ['20:45', '21:45'],
        },
        {
          'count_today': {'event': 'checkin', 'lt': 3},
        },
      ],
    });

EvalContext contextAt(
  int hour,
  int minute, {
  int checkinsToday = 2,
}) =>
    StateEvalContext(
      state: stateOf(),
      clock: FakeClock(DateTime(2026, 8, 3, hour, minute)),
      runtime: RuntimeContext(
        countTodayByEvent: {'checkin': checkinsToday},
      ),
    );

void main() {
  group('R-003 haelt sein Fenster', () {
    test('20:44 noch nicht', () {
      expect(r003().eval(contextAt(20, 44)), isFalse);
    });

    test('20:45 schon', () {
      expect(r003().eval(contextAt(20, 45)), isTrue);
    });

    test('21:45 noch', () {
      expect(r003().eval(contextAt(21, 45)), isTrue);
    });

    test('21:46 nicht mehr', () {
      expect(r003().eval(contextAt(21, 46)), isFalse);
    });
  });

  group('R-003 zaehlt bis drei', () {
    test('zwei Check-ins bisher — sie fragt', () {
      expect(r003().eval(contextAt(21, 0, checkinsToday: 2)), isTrue);
    });

    test('drei Check-ins bisher — sie ist still', () {
      expect(r003().eval(contextAt(21, 0, checkinsToday: 3)), isFalse);
    });

    test('ein verpasster Tag verhindert den Abend nicht', () {
      // Weder Morgen noch Mittag erfasst. Der Abend ist der wertvollste
      // Messpunkt — er darf nicht daran haengen, dass die anderen liefen.
      expect(r003().eval(contextAt(21, 0, checkinsToday: 0)), isTrue);
    });
  });

  group('R-003 und die Systemgrenzen', () {
    Rule rule() => ruleOf(
          id: 'R-003',
          when: r003(),
          action: ActionType.promptCheckin,
          priority: 75,
          cooldown: const Cooldown(minInterval: Duration(minutes: 60), maxPerDay: 1),
        );

    test('das Fenster endet vor der Ruhezeit', () {
      // Ruhezeit ab 23:00. Waere das Fenster nach hinten verschoben,
      // fiele der wichtigste Messpunkt des Tages stumm aus.
      final now = DateTime(2026, 8, 3, 21, 45);
      expect(fireOnce(rule(), ctx: contextAt(21, 45), nowLocal: now).fired, isTrue);
    });

    test('der Stundendeckel kann ihn verdraengen', () {
      // Zwei andere Regeln haben in der letzten Stunde gesprochen. Das ist
      // kein Fehler, sondern die Burst-Bremse (R2) — steht hier, damit
      // sichtbar bleibt, dass auch der wichtigste Messpunkt ihr
      // unterliegt.
      final now = DateTime(2026, 8, 3, 21, 0);
      final result = const RuleEngine().evaluate(
        rules: [
          rule(),
          ruleOf(id: 'R-120'),
          ruleOf(id: 'R-110'),
        ],
        ctx: contextAt(21, 0),
        history: FakeHistory(last: {
          'R-120': now.subtract(const Duration(minutes: 10)),
          'R-110': now.subtract(const Duration(minutes: 20)),
        }),
        nowLocal: now,
      );
      expect(
        result.skipped
            .where((s) => s.rule.id == 'R-003')
            .map((s) => s.reason),
        [SkipReason.hourlyLimitReached],
      );
    });
  });
}
