/// R-110 — „Abendgrenze" (M8 Sleep Gate).
///
/// Die Nacht ist reizarm genug fuer Hyperfokus und bietet zugleich die
/// staerkste Neuheit. Daraus entsteht eine sich selbst verstaerkende
/// Kaskade: Schlafdefizit senkt die Exekutivfunktion, das erhoeht
/// Kompensationsaufwand und Reizbedarf, was den Abendkonsum steigert [D8].
/// Der Ausstiegsanker bricht den Kreis an seiner schwaechsten Stelle.
///
/// **Was dieser Test festhaelt.** Das Fenster reichte bis 23:15, die
/// Ruhezeit beginnt um 23:00 (rules/core/limits.yaml). Die letzten fuenfzehn
/// Minuten waren stumm: Die Bedingung traf zu, die Regel sprach nicht, weil
/// nur `enforce` die Ruhezeit brechen darf. Seit dem 06.08.2026 endet das
/// Fenster um 22:59 — gekuerzt statt verbindlich gemacht, weil eine
/// verbindliche Abendgrenze der eigenen Begruendung widerspraeche („wer um
/// halb elf angeschrien wird, schaltet die App stumm"). Die Ruhezeit *ist*
/// der Wind-down; diese Regel gehoert davor.
///
/// Der Test prueft deshalb beides: dass das Fenster dort endet, wo die
/// Ruhezeit beginnt, und dass jede Minute darin auch am Geraet ankommt.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Der Bedingungsbaum aus rules/core/s2-live.yaml, Wort fuer Wort.
Condition r110() => Condition.fromMap({
      'all': [
        {
          'time_between': ['22:30', '22:59'],
        },
        {
          'not': {
            'active_slot': {'eq': 'focus'},
          },
        },
      ],
    });

EvalContext contextAt(
  int hour,
  int minute, {
  String slot = 'none',
}) =>
    StateEvalContext(
      state: stateOf(),
      clock: FakeClock(DateTime(2026, 8, 3, hour, minute)),
      runtime: RuntimeContext(activeSlot: slot),
    );

Rule r110Rule() => ruleOf(
      id: 'R-110',
      when: r110(),
      priority: 60,
      cooldown:
          const Cooldown(minInterval: Duration(minutes: 720), maxPerDay: 1),
    );

void main() {
  group('R-110 haelt sein Fenster', () {
    test('22:29 noch nicht', () {
      expect(r110().eval(contextAt(22, 29)), isFalse);
    });

    test('22:30 schon', () {
      expect(r110().eval(contextAt(22, 30)), isTrue);
    });

    test('22:59 noch — die letzte Minute vor der Ruhezeit', () {
      expect(r110().eval(contextAt(22, 59)), isTrue);
    });

    test('23:00 nicht mehr — ab hier ist die Ruhezeit der Wind-down', () {
      expect(r110().eval(contextAt(23, 0)), isFalse);
      expect(r110().eval(contextAt(23, 15)), isFalse);
    });

    test('am Nachmittag nicht', () {
      expect(r110().eval(contextAt(15, 0)), isFalse);
    });
  });

  group('R-110 unterbricht keinen laufenden Fokus', () {
    test('waehrend eines Fokusblocks still', () {
      // Absicht der Regel: leise sein. „Wer um halb elf angeschrien wird,
      // schaltet die App stumm" — und eine stummgeschaltete App ist eine
      // geloeschte App mit Extraschritten (R2).
      expect(r110().eval(contextAt(22, 45, slot: 'focus')), isFalse);
    });

    test('waehrend eines Reiz-Slots dagegen schon', () {
      expect(r110().eval(contextAt(22, 45, slot: 'sensation')), isTrue);
    });

    test('ohne laufenden Slot schon', () {
      expect(r110().eval(contextAt(22, 45)), isTrue);
    });
  });

  group('Kein Teil des Fensters faellt der Ruhezeit zum Opfer', () {
    test('jede Minute des Fensters kommt auch am Geraet an', () {
      // Der eigentliche Punkt der Kuerzung: Was in der YAML steht, muss
      // sprechen koennen. Ein Fenster, dessen Rand von den Grenzen daneben
      // zurueckgenommen wird, ist eine Zusage, die niemand einloest (G2).
      for (var minute = 30; minute <= 59; minute++) {
        final at = DateTime(2026, 8, 3, 22, minute);
        expect(
          fireOnce(r110Rule(), ctx: contextAt(22, minute), nowLocal: at).fired,
          isTrue,
          reason: 'Um 22:$minute muss die Abendgrenze durchkommen',
        );
      }
    });

    test('nach 23:00 ist die Bedingung selbst falsch, nicht nur unterdrueckt',
        () {
      // Vorher reichte das Fenster bis 23:15 und die Bedingung traf dort
      // zu — verworfen wurde sie erst von der Ruhezeit, mit
      // SkipReason.quietHours. Der Unterschied ist nicht kosmetisch: Eine
      // Regel, die zutrifft und unterdrueckt wird, taucht im Systeminspektor
      // als unterdrueckt auf und sieht nach einem Konflikt aus, den es nie
      // gab.
      for (final at in [
        DateTime(2026, 8, 3, 23, 0),
        DateTime(2026, 8, 3, 23, 15),
      ]) {
        expect(r110().eval(contextAt(at.hour, at.minute)), isFalse);
        final outcome =
            fireOnce(r110Rule(), ctx: contextAt(at.hour, at.minute), nowLocal: at);
        expect(outcome.fired, isFalse);
        expect(outcome.reason, SkipReason.conditionFalse);
      }
    });
  });
}
