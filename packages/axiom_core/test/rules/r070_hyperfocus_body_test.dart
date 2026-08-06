/// R-070 — „Hyperfokus ohne Koerperkontakt".
///
/// Im Hyperfokus werden Durst, Hunger und Bewegungsbedarf systematisch
/// uebersehen, und der koerperliche Zustand ist der groesste einzelne
/// Modulator der Exekutivfunktion [D7].
///
/// Die erste Zeile der Bedingung ist die eigentliche Arbeit. `minutes_since`
/// gilt bei einem nie eingetretenen Ereignis als „unendlich lange her" —
/// richtig fuer *„seit X nichts getrunken"*, falsch fuer *„laeuft seit X"*.
/// Ohne `active_slot: focus` feuerte die Regel auf einem frisch
/// installierten Geraet dauernd, weil noch nie ein Fokus begonnen hat. Genau
/// dieser Fall steht unten als erster Test.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Der Bedingungsbaum aus rules/core/s3-regulation.yaml, Wort fuer Wort.
Condition r070() => Condition.fromMap({
      'all': [
        {
          'active_slot': {'eq': 'focus'},
        },
        {
          'minutes_since': {'event': 'focus_start', 'gte': 90},
        },
        {
          'minutes_since': {'event': 'body_prompt', 'gte': 90},
        },
        {
          'time_between': ['07:00', '22:00'],
        },
      ],
    });

EvalContext contextWith({
  String slot = 'focus',
  int? sinceFocusStart = 120,
  int? sinceBodyPrompt,
  int hour = 14,
  int minute = 0,
}) =>
    StateEvalContext(
      state: stateOf(),
      clock: FakeClock(DateTime(2026, 8, 3, hour, minute)),
      runtime: RuntimeContext(
        activeSlot: slot,
        minutesSinceByEvent: {
          'focus_start': ?sinceFocusStart,
          'body_prompt': ?sinceBodyPrompt,
        },
      ),
    );

void main() {
  group('R-070 setzt einen laufenden Fokus voraus', () {
    test('frisches Geraet, nie ein Fokus, nichts laeuft — still', () {
      // Der Fehler, gegen den die erste Zeile geschrieben ist: Beide
      // minutes_since-Bedingungen treffen hier zu, weil noch nie etwas
      // passiert ist. Ohne active_slot spraeche die Regel ab dem ersten
      // Vormittag nach der Installation, ohne dass je ein Fokus lief.
      final ctx = StateEvalContext(
        state: stateOf(),
        clock: FakeClock(DateTime(2026, 8, 3, 14)),
        runtime: const RuntimeContext(),
      );
      expect(r070().eval(ctx), isFalse);
    });

    test('ein alter Fokus, der laengst beendet ist — still', () {
      expect(
        r070().eval(contextWith(slot: 'none', sinceFocusStart: 600)),
        isFalse,
      );
    });

    test('ein laufender Reiz-Slot ist kein Fokus', () {
      expect(r070().eval(contextWith(slot: 'sensation')), isFalse);
    });

    test('laufender Fokus seit zwei Stunden — Anlass', () {
      expect(r070().eval(contextWith()), isTrue);
    });
  });

  group('R-070 wartet neunzig Minuten, nicht laenger und nicht kuerzer', () {
    test('89 Minuten Fokus — noch nicht', () {
      expect(r070().eval(contextWith(sinceFocusStart: 89)), isFalse);
    });

    test('90 Minuten Fokus — genau ab hier', () {
      expect(r070().eval(contextWith(sinceFocusStart: 90)), isTrue);
    });

    test('vor 89 Minuten quittiert — sie schweigt', () {
      expect(
        r070().eval(contextWith(sinceBodyPrompt: 89)),
        isFalse,
        reason: 'Wer gerade getrunken hat, wird nicht erinnert',
      );
    });

    test('vor 90 Minuten quittiert — sie meldet sich', () {
      expect(r070().eval(contextWith(sinceBodyPrompt: 90)), isTrue);
    });

    test('heute noch gar nicht quittiert — sie meldet sich', () {
      // Hier ist „nie" richtig als „unendlich lange her" zu lesen: Wer noch
      // nie getrunken hat, hat erst recht lange nicht getrunken.
      expect(r070().eval(contextWith(sinceBodyPrompt: null)), isTrue);
    });
  });

  group('R-070 kennt Tagesraender', () {
    test('06:59 nicht', () {
      expect(r070().eval(contextWith(hour: 6, minute: 59)), isFalse);
    });

    test('07:00 schon', () {
      expect(r070().eval(contextWith(hour: 7)), isTrue);
    });

    test('22:00 noch', () {
      expect(r070().eval(contextWith(hour: 22)), isTrue);
    });

    test('22:01 nicht mehr', () {
      expect(r070().eval(contextWith(hour: 22, minute: 1)), isFalse);
    });

    test('ein Nachtfokus bleibt unbehelligt', () {
      // Absicht: Nach 22:00 uebernimmt das Sleep Gate (R-110). Zwei Regeln,
      // die gleichzeitig in dieselbe Nacht sprechen, waeren Rauschen.
      expect(r070().eval(contextWith(hour: 2)), isFalse);
    });
  });

  test('R-070 kommt tagsueber durch die Systemgrenzen', () {
    final rule = ruleOf(
      id: 'R-070',
      when: r070(),
      priority: 55,
      cooldown:
          const Cooldown(minInterval: Duration(minutes: 120), maxPerDay: 3),
    );
    final now = DateTime(2026, 8, 3, 14);
    expect(fireOnce(rule, ctx: contextWith(), nowLocal: now).fired, isTrue);
  });
}
