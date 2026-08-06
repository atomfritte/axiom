/// Der Bedingungsbaum an den Raendern.
///
/// `condition.dart` ist die schmalste Stelle des ganzen Systems: Jede Regel
/// laeuft hier durch, und ein Fehler kostet nicht eine falsche Anzeige,
/// sondern eine Regel, die es faktisch nicht gibt. Der vorhandene Test
/// prueft die Mitte jeder Form; hier stehen die Kanten — jeder Operator an
/// seiner Schwelle, Mitternacht, jede Ablehnung des Parsers, und die Frage,
/// was ein nie eingetretenes Ereignis fuer jeden einzelnen Operator bedeutet.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

EvalContext _ctx({
  StateVector? state,
  DateTime? now,
  RuntimeContext runtime = const RuntimeContext(),
}) =>
    StateEvalContext(
      state: state ?? stateOf(),
      clock: FakeClock(now ?? testNoon),
      runtime: runtime,
    );

/// Wertet `capacity <op> 30` bei gegebener Kapazitaet aus.
bool _cmp(String op, int capacity) => Condition.fromMap({
      'capacity': {op: 30}
    }).eval(_ctx(state: stateOf(capacity: capacity)));

void main() {
  group('Jeder Operator an seiner Schwelle', () {
    test('gte trennt bei genau dem Wert', () {
      expect(_cmp('gte', 29), isFalse);
      expect(_cmp('gte', 30), isTrue);
      expect(_cmp('gte', 31), isTrue);
    });

    test('gt schliesst den Wert selbst aus', () {
      expect(_cmp('gt', 30), isFalse);
      expect(_cmp('gt', 31), isTrue);
    });

    test('lte schliesst den Wert selbst ein', () {
      expect(_cmp('lte', 30), isTrue);
      expect(_cmp('lte', 31), isFalse);
    });

    test('lt schliesst den Wert selbst aus', () {
      expect(_cmp('lt', 30), isFalse);
      expect(_cmp('lt', 29), isTrue);
    });

    test('eq und ne sind komplementaer', () {
      for (final capacity in [29, 30, 31]) {
        expect(_cmp('eq', capacity), isNot(_cmp('ne', capacity)),
            reason: 'bei $capacity');
      }
      expect(_cmp('eq', 30), isTrue);
    });

    test('ganze Zahl gegen Kommazahl wird korrekt verglichen', () {
      // Der Editor kann 29.5 schreiben; die Zustandswerte sind ganzzahlig.
      final c = Condition.fromMap({
        'capacity': {'gte': 29.5}
      });
      expect(c.eval(_ctx(state: stateOf(capacity: 29))), isFalse);
      expect(c.eval(_ctx(state: stateOf(capacity: 30))), isTrue);
    });

    test('an den Enden der Skala', () {
      expect(
        Condition.fromMap({
          'capacity': {'gte': 0}
        }).eval(_ctx(state: stateOf(capacity: 0))),
        isTrue,
      );
      expect(
        Condition.fromMap({
          'capacity': {'lte': 100}
        }).eval(_ctx(state: stateOf(capacity: 100))),
        isTrue,
      );
    });
  });

  group('time_between — Mitternacht und die Minute davor', () {
    bool at(Condition c, int hour, int minute) =>
        c.eval(_ctx(now: DateTime(2026, 8, 3, hour, minute)));

    test('das normale Intervall schliesst beide Enden ein', () {
      final c = Condition.fromMap({
        'time_between': ['07:00', '21:00']
      });
      expect(at(c, 6, 59), isFalse);
      expect(at(c, 7, 0), isTrue);
      expect(at(c, 21, 0), isTrue);
      expect(at(c, 21, 1), isFalse);
    });

    test('ueber Mitternacht schliesst ebenfalls beide Enden ein [D8]', () {
      final c = Condition.fromMap({
        'time_between': ['22:00', '05:00']
      });
      expect(at(c, 21, 59), isFalse);
      expect(at(c, 22, 0), isTrue);
      expect(at(c, 23, 59), isTrue);
      expect(at(c, 0, 0), isTrue);
      expect(at(c, 5, 0), isTrue);
      expect(at(c, 5, 1), isFalse);
    });

    test('ein Intervall mit gleichem Anfang und Ende meint genau diese Minute',
        () {
      final c = Condition.fromMap({
        'time_between': ['12:00', '12:00']
      });
      expect(at(c, 11, 59), isFalse);
      expect(at(c, 12, 0), isTrue);
      expect(at(c, 12, 1), isFalse);
    });

    test('Sekunden zaehlen nicht mit', () {
      // Sonst haenge eine Regel an der Sekunde, in der der Auswertungslauf
      // zufaellig stattfindet.
      final c = Condition.fromMap({
        'time_between': ['12:00', '12:00']
      });
      expect(c.eval(_ctx(now: DateTime(2026, 8, 3, 12, 0, 59))), isTrue);
    });

    test('00:00 bis 23:59 deckt den ganzen Tag ab', () {
      final c = Condition.fromMap({
        'time_between': ['00:00', '23:59']
      });
      for (final hour in [0, 6, 12, 18, 23]) {
        expect(at(c, hour, 30), isTrue, reason: 'Stunde $hour');
      }
    });

    test('das Datum spielt keine Rolle, nur die Uhrzeit', () {
      final c = Condition.fromMap({
        'time_between': ['22:00', '05:00']
      });
      expect(c.eval(_ctx(now: DateTime(2026, 12, 31, 23, 30))), isTrue);
      expect(c.eval(_ctx(now: DateTime(2027, 1, 1, 2, 30))), isTrue);
    });

    test('die Uhrzeit findet den Weg zurueck ins YAML', () {
      final map = {
        'time_between': ['07:05', '21:00']
      };
      expect(Condition.fromMap(map).toMap(), map);
    });
  });

  group('Ein nie eingetretenes Ereignis — je Operator', () {
    // „Noch nie" heisst „unendlich lange her". Das ist richtig fuer
    // „seit X nichts getrunken" und falsch fuer „laeuft seit X" — deshalb
    // steht hier jeder Operator einzeln.
    bool never(String op) => Condition.fromMap({
          'minutes_since': {'event': 'nie_passiert', op: 90}
        }).eval(_ctx());

    test('gte und gt treffen zu', () {
      expect(never('gte'), isTrue);
      expect(never('gt'), isTrue);
    });

    test('ne trifft zu', () {
      expect(never('ne'), isTrue);
    });

    test('lt, lte und eq treffen nicht zu', () {
      expect(never('lt'), isFalse);
      expect(never('lte'), isFalse);
      expect(never('eq'), isFalse);
    });

    test('gerade eingetreten heisst null Minuten, nicht „nie"', () {
      final c = Condition.fromMap({
        'minutes_since': {'event': 'checkin', 'lt': 5}
      });
      expect(
        c.eval(_ctx(
            runtime: const RuntimeContext(minutesSinceByEvent: {'checkin': 0}))),
        isTrue,
      );
    });
  });

  group('count_today', () {
    test('ein unbekanntes Ereignis zaehlt null, es wirft nicht', () {
      // Anders als bei einer Variablen: „heute noch nicht passiert" ist
      // eine Antwort, kein Fehler.
      expect(
        Condition.fromMap({
          'count_today': {'event': 'nie_passiert', 'lt': 3}
        }).eval(_ctx()),
        isTrue,
      );
      expect(
        Condition.fromMap({
          'count_today': {'event': 'nie_passiert', 'gte': 1}
        }).eval(_ctx()),
        isFalse,
      );
    });

    test('zaehlt genau an der Grenze', () {
      final c = Condition.fromMap({
        'count_today': {'event': 'body_prompt', 'lt': 3}
      });
      for (final entry in {2: true, 3: false, 4: false}.entries) {
        expect(
          c.eval(_ctx(
              runtime: RuntimeContext(
                  countTodayByEvent: {'body_prompt': entry.key}))),
          entry.value,
          reason: '${entry.key} mal',
        );
      }
    });
  });

  group('Verschachtelung', () {
    test('not(not(x)) ist x', () {
      final x = Condition.fromMap({
        'capacity': {'gte': 30}
      });
      final doppelt = Condition.fromMap({
        'not': {
          'not': {
            'capacity': {'gte': 30}
          }
        }
      });
      for (final capacity in [20, 30, 40]) {
        final ctx = _ctx(state: stateOf(capacity: capacity));
        expect(doppelt.eval(ctx), x.eval(ctx), reason: 'bei $capacity');
      }
    });

    test('all in any in not — drei Ebenen tief', () {
      final c = Condition.fromMap({
        'not': {
          'any': [
            {
              'all': [
                {
                  'capacity': {'lt': 30}
                },
                {
                  'load_level': {'eq': 'L3'}
                },
              ]
            },
            {
              'regulation': {'lt': 20}
            },
          ]
        }
      });
      // Weder beide Bedingungen des `all` noch das `any`-Geschwister.
      expect(c.eval(_ctx(state: stateOf(capacity: 60, regulation: 80))), isTrue);
      // Das `any` greift ueber die Regulationsreserve.
      expect(c.eval(_ctx(state: stateOf(capacity: 60, regulation: 10))), isFalse);
      // Das `all` greift.
      expect(
        c.eval(_ctx(state: stateOf(capacity: 20, loadIndex: 90))),
        isFalse,
      );
    });

    test('ein einzelnes Kind in all und any ist erlaubt', () {
      expect(
        Condition.fromMap({
          'all': [
            {
              'capacity': {'gte': 0}
            }
          ]
        }).eval(_ctx()),
        isTrue,
      );
      expect(
        Condition.fromMap({
          'any': [
            {
              'capacity': {'gte': 999}
            }
          ]
        }).eval(_ctx()),
        isFalse,
      );
    });

    test('referencedVariables sammelt ueber alle Ebenen', () {
      final c = Condition.fromMap({
        'not': {
          'any': [
            {
              'all': [
                {
                  'capacity': {'lt': 30}
                },
                {
                  'time_between': ['22:00', '05:00']
                },
              ]
            },
            {
              'count_today': {'event': 'checkin', 'gte': 3}
            },
          ]
        }
      });
      expect(
        c.referencedVariables,
        {'capacity', 'time_between', 'event:checkin'},
      );
    });
  });

  group('Fail-Fast — was der Parser ablehnt', () {
    void rejects(String name, Object? map) {
      test(name, () {
        expect(
          () => Condition.fromMap(map as Map<Object?, Object?>),
          throwsA(isA<ConditionError>()),
        );
      });
    }

    rejects('ein leerer Knoten', <Object?, Object?>{});
    rejects('not mit einer Liste', {
      'not': [
        {
          'capacity': {'gte': 1}
        }
      ]
    });
    rejects('all, das keine Liste ist', {
      'all': {
        'capacity': {'gte': 1}
      }
    });
    rejects('any ohne Inhalt', {'any': <Object?>[]});
    rejects('minutes_since ohne event', {
      'minutes_since': {'gte': 90}
    });
    rejects('minutes_since mit zwei Operatoren', {
      'minutes_since': {'event': 'checkin', 'gte': 90, 'lt': 200}
    });
    rejects('minutes_since ohne Operator', {
      'minutes_since': {'event': 'checkin'}
    });
    rejects('minutes_since mit Text als Wert', {
      'minutes_since': {'event': 'checkin', 'gte': 'viel'}
    });
    rejects('count_today, das keine Map ist', {'count_today': 3});
    rejects('time_between mit einem Wert', {
      'time_between': ['07:00']
    });
    rejects('time_between mit drei Werten', {
      'time_between': ['07:00', '12:00', '21:00']
    });
    rejects('time_between ohne Doppelpunkt', {
      'time_between': ['0700', '21:00']
    });
    rejects('eine Stunde jenseits von 23', {
      'time_between': ['24:00', '05:00']
    });
    rejects('eine Minute jenseits von 59', {
      'time_between': ['07:60', '21:00']
    });
    rejects('eine negative Uhrzeit', {
      'time_between': ['-1:00', '21:00']
    });
    rejects('eine Variable ohne Operator-Map', {'capacity': 30});
    rejects('eine Variable mit zwei Operatoren', {
      'capacity': {'gte': 30, 'lte': 60}
    });
    rejects('ein Vergleichswert, der weder Zahl noch Text ist', {
      'capacity': {'gte': true}
    });
    rejects('ein symbolischer Vergleich mit lt', {
      'load_level': {'lt': 'L3'}
    });

    test('ein Knoten mit zwei Schluesseln nennt beide in der Meldung', () {
      // Eine Meldung ohne Ort ist hier so gut wie keine — die Regel steht in
      // einer YAML-Datei mit dreissig Zeilen.
      try {
        Condition.fromMap({
          'capacity': {'gte': 10},
          'regulation': {'gte': 10},
        });
        fail('nicht abgelehnt');
      } on ConditionError catch (e) {
        expect(e.message, contains('capacity'));
        expect(e.message, contains('regulation'));
      }
    });

    test('eine unbekannte Variable wirft mit ihrem Namen', () {
      try {
        Condition.fromMap({
          'kapazitaet': {'gte': 30}
        }).eval(_ctx());
        fail('nicht abgelehnt');
      } on ConditionError catch (e) {
        expect(e.message, contains('kapazitaet'));
      }
    });

    test('eine unbekannte symbolische Variable wirft ebenfalls', () {
      expect(
        () => Condition.fromMap({
          'stimmung': {'eq': 'gut'}
        }).eval(_ctx()),
        throwsA(isA<ConditionError>()),
      );
    });
  });

  group('Warum der Validator vor dem Laden prueft, nicht die Engine', () {
    test('all bricht beim ersten falschen Kind ab — der Fehler dahinter '
        'bleibt stumm', () {
      // `every` haelt an, sobald ein Kind falsch ist. Eine vertippte
      // Variable an zweiter Stelle wirft dann nie, solange die erste
      // Bedingung nicht zutrifft: Die Regel feuert einfach nie, und niemand
      // erfaehrt warum. Genau deshalb prueft `validate_rules.dart` die
      // Variablennamen statisch beim Laden — hier ist der Beleg, dass die
      // Laufzeit das nicht auffangen kann.
      final c = Condition.fromMap({
        'all': [
          {
            'capacity': {'gte': 999}
          },
          {
            'gibt_es_nicht': {'gte': 1}
          },
        ]
      });
      expect(c.eval(_ctx()), isFalse);

      // Dieselbe Bedingung wirft, sobald das erste Kind zutrifft.
      final andersherum = Condition.fromMap({
        'all': [
          {
            'capacity': {'gte': 0}
          },
          {
            'gibt_es_nicht': {'gte': 1}
          },
        ]
      });
      expect(() => andersherum.eval(_ctx()), throwsA(isA<ConditionError>()));

      // Statisch ist sie in beiden Faellen auffindbar.
      expect(c.referencedVariables, contains('gibt_es_nicht'));
    });

    test('any bricht beim ersten zutreffenden Kind ab', () {
      final c = Condition.fromMap({
        'any': [
          {
            'capacity': {'gte': 0}
          },
          {
            'gibt_es_nicht': {'gte': 1}
          },
        ]
      });
      expect(c.eval(_ctx()), isTrue);
    });
  });

  group('Symbolische Vergleiche', () {
    test('Gross- und Kleinschreibung trennt nicht', () {
      for (final geschrieben in ['L3', 'l3', 'L3']) {
        expect(
          Condition.fromMap({
            'load_level': {'eq': geschrieben}
          }).eval(_ctx(state: stateOf(loadIndex: 90))),
          isTrue,
          reason: geschrieben,
        );
      }
    });

    test('ne ist die genaue Umkehrung von eq', () {
      for (final loadIndex in [10, 60, 75, 90]) {
        final ctx = _ctx(state: stateOf(loadIndex: loadIndex));
        final gleich = Condition.fromMap({
          'load_level': {'eq': 'L3'}
        }).eval(ctx);
        final ungleich = Condition.fromMap({
          'load_level': {'ne': 'L3'}
        }).eval(ctx);
        expect(gleich, isNot(ungleich), reason: 'bei $loadIndex');
      }
    });

    test('ein unbekannter Wert ist schlicht ungleich, kein Fehler', () {
      // Der Wert steht in der Regel, die Variable loest auf — hier ist
      // „trifft nicht zu" die richtige Antwort.
      expect(
        Condition.fromMap({
          'load_level': {'eq': 'L9'}
        }).eval(_ctx()),
        isFalse,
      );
    });
  });

  test('Determinismus: zweimal ausgewertet, zweimal dasselbe', () {
    final c = Condition.fromMap({
      'all': [
        {
          'capacity': {'gte': 30}
        },
        {
          'time_between': ['07:00', '21:00']
        },
        {
          'minutes_since': {'event': 'checkin', 'gte': 60}
        },
      ]
    });
    final ctx = _ctx(
      state: stateOf(capacity: 55),
      runtime: const RuntimeContext(minutesSinceByEvent: {'checkin': 90}),
    );
    expect(c.eval(ctx), c.eval(ctx));
    expect(c.eval(ctx), isTrue);
  });
}
