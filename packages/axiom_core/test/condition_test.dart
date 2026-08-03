import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

EvalContext ctxWith({
  StateVector? state,
  DateTime? now,
  RuntimeContext runtime = const RuntimeContext(),
}) =>
    StateEvalContext(
      state: state ?? stateOf(),
      clock: FakeClock(now ?? testNoon),
      runtime: runtime,
    );

void main() {
  group('Parser', () {
    test('numerischer Vergleich', () {
      final c = Condition.fromMap({
        'capacity': {'gte': 30}
      });
      expect(c, isA<NumericCompare>());
      expect(c.eval(ctxWith(state: stateOf(capacity: 60))), isTrue);
      expect(c.eval(ctxWith(state: stateOf(capacity: 20))), isFalse);
    });

    test('all / any / not verschachtelt', () {
      final c = Condition.fromMap({
        'all': [
          {
            'sensation_need': {'gte': 70}
          },
          {
            'capacity': {'gte': 30}
          },
          {
            'not': {
              'active_slot': {'eq': 'sensation'}
            }
          },
        ]
      });

      // Trifft zu: hoher Reizbedarf, genug Kapazitaet, kein laufender Slot.
      expect(
        c.eval(ctxWith(state: stateOf(sensationNeed: 80, capacity: 50))),
        isTrue,
      );

      // Laeuft bereits ein Reiz-Slot -> Regel darf nicht feuern.
      expect(
        c.eval(ctxWith(
          state: stateOf(sensationNeed: 80, capacity: 50),
          runtime: const RuntimeContext(activeSlot: 'sensation'),
        )),
        isFalse,
      );

      // Leerer Tank -> kein Sport-Vorschlag.
      expect(
        c.eval(ctxWith(state: stateOf(sensationNeed: 80, capacity: 10))),
        isFalse,
      );
    });

    test('symbolischer Vergleich load_level', () {
      final c = Condition.fromMap({
        'load_level': {'eq': 'L3'}
      });
      expect(c.eval(ctxWith(state: stateOf(loadIndex: 90))), isTrue);
      expect(c.eval(ctxWith(state: stateOf(loadIndex: 60))), isFalse);
    });

    test('minutes_since', () {
      final c = Condition.fromMap({
        'minutes_since': {'event': 'focus_start', 'gte': 90}
      });
      expect(
        c.eval(ctxWith(
          runtime: const RuntimeContext(
            minutesSinceByEvent: {'focus_start': 120},
          ),
        )),
        isTrue,
      );
      expect(
        c.eval(ctxWith(
          runtime: const RuntimeContext(
            minutesSinceByEvent: {'focus_start': 30},
          ),
        )),
        isFalse,
      );
    });

    test('minutes_since ohne bisheriges Event gilt als unendlich lange her', () {
      final c = Condition.fromMap({
        'minutes_since': {'event': 'body_prompt', 'gte': 90}
      });
      expect(c.eval(ctxWith()), isTrue);
    });

    test('„laeuft seit X" braucht zusaetzlich active_slot', () {
      // Haeufige Fehlerquelle: minutes_since allein trifft auch zu, wenn
      // ueberhaupt nichts laeuft. Eine Regel, die einen laufenden Fokus
      // meint, muss das mitpruefen.
      final naiv = Condition.fromMap({
        'minutes_since': {'event': 'focus_start', 'gte': 90}
      });
      expect(naiv.eval(ctxWith()), isTrue,
          reason: 'ohne je gestarteten Fokus trifft die Bedingung zu');

      final korrekt = Condition.fromMap({
        'all': [
          {
            'active_slot': {'eq': 'focus'}
          },
          {
            'minutes_since': {'event': 'focus_start', 'gte': 90}
          },
        ]
      });
      expect(korrekt.eval(ctxWith()), isFalse);
      expect(
        korrekt.eval(ctxWith(
          runtime: const RuntimeContext(
            activeSlot: 'focus',
            minutesSinceByEvent: {'focus_start': 120},
          ),
        )),
        isTrue,
      );
    });

    test('count_today', () {
      final c = Condition.fromMap({
        'count_today': {'event': 'body_prompt', 'lt': 3}
      });
      expect(
        c.eval(ctxWith(
          runtime: const RuntimeContext(countTodayByEvent: {'body_prompt': 2}),
        )),
        isTrue,
      );
      expect(
        c.eval(ctxWith(
          runtime: const RuntimeContext(countTodayByEvent: {'body_prompt': 5}),
        )),
        isFalse,
      );
    });
  });

  group('time_between', () {
    test('normales Intervall', () {
      final c = Condition.fromMap({
        'time_between': ['07:00', '21:00']
      });
      expect(c.eval(ctxWith(now: DateTime(2026, 8, 3, 12))), isTrue);
      expect(c.eval(ctxWith(now: DateTime(2026, 8, 3, 6, 30))), isFalse);
      expect(c.eval(ctxWith(now: DateTime(2026, 8, 3, 22))), isFalse);
    });

    test('ueber Mitternacht — Nacht-Kaskade [D8]', () {
      final c = Condition.fromMap({
        'time_between': ['22:00', '05:00']
      });
      expect(c.eval(ctxWith(now: DateTime(2026, 8, 3, 23, 30))), isTrue);
      expect(c.eval(ctxWith(now: DateTime(2026, 8, 3, 2))), isTrue);
      expect(c.eval(ctxWith(now: DateTime(2026, 8, 3, 12))), isFalse);
    });
  });

  group('Fail-Fast', () {
    test('unbekannte Variable wirft, statt still false zu liefern', () {
      final c = Condition.fromMap({
        'gibt_es_nicht': {'gte': 10}
      });
      expect(() => c.eval(ctxWith()), throwsA(isA<ConditionError>()));
    });

    test('Knoten mit mehreren Schluesseln wird abgelehnt', () {
      expect(
        () => Condition.fromMap({
          'capacity': {'gte': 10},
          'regulation': {'gte': 10},
        }),
        throwsA(isA<ConditionError>()),
      );
    });

    test('unbekannter Operator wird abgelehnt', () {
      expect(
        () => Condition.fromMap({
          'capacity': {'ungefaehr': 10}
        }),
        throwsA(isA<ConditionError>()),
      );
    });

    test('leere all-Liste wird abgelehnt', () {
      expect(
        () => Condition.fromMap({'all': <Object?>[]}),
        throwsA(isA<ConditionError>()),
      );
    });

    test('symbolischer Vergleich erlaubt nur eq/ne', () {
      expect(
        () => Condition.fromMap({
          'load_level': {'gte': 'L3'}
        }),
        throwsA(isA<ConditionError>()),
      );
    });

    test('ungueltige Uhrzeit wird abgelehnt', () {
      expect(
        () => Condition.fromMap({
          'time_between': ['25:00', '05:00']
        }),
        throwsA(isA<ConditionError>()),
      );
    });
  });

  test('referencedVariables sammelt rekursiv — Basis des Validators', () {
    final c = Condition.fromMap({
      'all': [
        {
          'capacity': {'gte': 30}
        },
        {
          'not': {
            'load_index': {'gte': 80}
          }
        },
        {
          'minutes_since': {'event': 'focus_start', 'gte': 90}
        },
      ]
    });
    expect(
      c.referencedVariables,
      containsAll(<String>['capacity', 'load_index', 'event:focus_start']),
    );
  });
}
