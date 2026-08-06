/// R-110 — „Abendgrenze" (M8 Sleep Gate).
///
/// Die Nacht ist reizarm genug fuer Hyperfokus und bietet zugleich die
/// staerkste Neuheit. Daraus entsteht eine sich selbst verstaerkende
/// Kaskade: Schlafdefizit senkt die Exekutivfunktion, das erhoeht
/// Kompensationsaufwand und Reizbedarf, was den Abendkonsum steigert [D8].
/// Der Ausstiegsanker bricht den Kreis an seiner schwaechsten Stelle.
///
/// **Befund, den dieser Test festhaelt.** Das Fenster in der YAML reicht bis
/// 23:15, die Ruhezeit beginnt um 23:00 (rules/core/limits.yaml). Die
/// letzten fuenfzehn Minuten sind stumm: Die Bedingung trifft zu, die Regel
/// spricht nicht, weil nur `enforce` die Ruhezeit brechen darf. Das ist
/// weniger schwer als bei R-052 — der Kern des Fensters bleibt erreichbar —,
/// aber es ist dieselbe Sorte Luecke: eine Zusage in der Regeldatei, die die
/// Grenzen daneben zuruecknehmen.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Der Bedingungsbaum aus rules/core/s2-live.yaml, Wort fuer Wort.
Condition r110() => Condition.fromMap({
      'all': [
        {
          'time_between': ['22:30', '23:15'],
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

    test('23:15 noch', () {
      expect(r110().eval(contextAt(23, 15)), isTrue);
    });

    test('23:16 nicht mehr', () {
      expect(r110().eval(contextAt(23, 16)), isFalse);
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

  group('Was am Geraet davon uebrig bleibt', () {
    test('bis 22:59 spricht sie', () {
      for (final at in [
        DateTime(2026, 8, 3, 22, 30),
        DateTime(2026, 8, 3, 22, 59),
      ]) {
        expect(
          fireOnce(r110Rule(), ctx: contextAt(at.hour, at.minute), nowLocal: at)
              .fired,
          isTrue,
        );
      }
    });

    test('ab 23:00 nicht mehr, obwohl das Fenster bis 23:15 reicht', () {
      for (final at in [
        DateTime(2026, 8, 3, 23, 0),
        DateTime(2026, 8, 3, 23, 15),
      ]) {
        expect(r110().eval(contextAt(at.hour, at.minute)), isTrue,
            reason: 'Die Bedingung trifft zu');
        final outcome =
            fireOnce(r110Rule(), ctx: contextAt(at.hour, at.minute), nowLocal: at);
        expect(outcome.fired, isFalse);
        expect(
          outcome.reason,
          SkipReason.quietHours,
          reason: 'Die letzten fuenfzehn Minuten des Fensters sind stumm',
        );
      }
    });
  });
}
