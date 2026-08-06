/// R-050 — „Reizbedarf proaktiv decken".
///
/// Ungedeckter Reizbedarf sucht sich den schnellsten Kanal, und der ist
/// meist der teuerste [D5]. Die Regel deckt denselben physiologischen Bedarf
/// zu kalkulierbaren Kosten — kanalisieren, nicht unterdruecken (G3).
///
/// Vier Bedingungen, und drei davon sind Bremsen: Ohne die
/// Kapazitaetsschwelle schluege sie im leeren Tank Sport vor, ohne den
/// Slot-Ausschluss mitten im laufenden Reiz-Slot, ohne das Zeitfenster
/// nachts. Genau diese drei sind deshalb einzeln geprueft.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Der Bedingungsbaum aus rules/core/s3-regulation.yaml, Wort fuer Wort.
Condition r050() => Condition.fromMap({
      'all': [
        {
          'sensation_need': {'gte': 70},
        },
        {
          'capacity': {'gte': 30},
        },
        {
          'not': {
            'active_slot': {'eq': 'sensation'},
          },
        },
        {
          'time_between': ['07:00', '21:00'],
        },
      ],
    });

EvalContext contextWith({
  int sensationNeed = 80,
  int capacity = 60,
  String slot = 'none',
  int hour = 14,
  int minute = 0,
}) =>
    StateEvalContext(
      state: stateOf(sensationNeed: sensationNeed, capacity: capacity),
      clock: FakeClock(DateTime(2026, 8, 3, hour, minute)),
      runtime: RuntimeContext(activeSlot: slot),
    );

void main() {
  group('R-050 misst den Bedarf an einer Kante', () {
    test('69 — noch kein Anlass', () {
      expect(r050().eval(contextWith(sensationNeed: 69)), isFalse);
    });

    test('70 — Anlass', () {
      expect(r050().eval(contextWith(sensationNeed: 70)), isTrue);
    });

    test('Voreinstellung des Zustands (40) loest nichts aus', () {
      // Sonst schluege das System bei jedem Blick einen Reiz-Slot vor und
      // waere selbst die Reizquelle.
      expect(r050().eval(contextWith(sensationNeed: 40)), isFalse);
    });
  });

  group('R-050 schlaegt nichts vor, was gerade nicht geht', () {
    test('29 Kapazitaet — kein Sport-Vorschlag', () {
      expect(
        r050().eval(contextWith(capacity: 29)),
        isFalse,
        reason: 'Ein Vorschlag, der die letzte Reserve kostet, wird '
            'abgelehnt und macht den naechsten unglaubwuerdig',
      );
    });

    test('30 Kapazitaet — gerade noch', () {
      expect(r050().eval(contextWith(capacity: 30)), isTrue);
    });
  });

  group('R-050 verdoppelt nichts, was schon laeuft', () {
    test('waehrend eines Reiz-Slots still', () {
      expect(r050().eval(contextWith(slot: 'sensation')), isFalse);
    });

    test('waehrend eines Fokusblocks dagegen nicht still', () {
      // Dokumentierte Kante: Der Ausschluss gilt nur dem Reiz-Slot. Wer
      // auch den Fokus schuetzen will, braucht dafuer den Focus Governor
      // (M4) — nicht eine zweite Zeile in dieser Regel.
      expect(r050().eval(contextWith(slot: 'focus')), isTrue);
    });

    test('ohne laufenden Slot ist der Weg frei', () {
      expect(r050().eval(contextWith()), isTrue);
    });
  });

  group('R-050 kennt Tagesraender', () {
    test('06:59 noch nicht', () {
      expect(r050().eval(contextWith(hour: 6, minute: 59)), isFalse);
    });

    test('07:00 schon', () {
      expect(r050().eval(contextWith(hour: 7)), isTrue);
    });

    test('21:00 noch', () {
      expect(r050().eval(contextWith(hour: 21)), isTrue);
    });

    test('21:01 nicht mehr', () {
      // Ein Hochreiz-Slot am spaeten Abend arbeitet direkt gegen das Sleep
      // Gate [D8] — die Nacht ist ohnehin die reizstaerkste Zeit.
      expect(r050().eval(contextWith(hour: 21, minute: 1)), isFalse);
    });

    test('um drei Uhr nachts nicht', () {
      expect(r050().eval(contextWith(hour: 3)), isFalse);
    });
  });

  test('R-050 kommt tagsueber durch die Systemgrenzen', () {
    final rule = ruleOf(
      id: 'R-050',
      when: r050(),
      action: ActionType.suggestSlot,
      priority: 60,
      cooldown: const Cooldown(
        minInterval: Duration(minutes: 240),
        maxPerDay: 2,
        exponentialBackoff: true,
      ),
    );
    final now = DateTime(2026, 8, 3, 14);
    expect(fireOnce(rule, ctx: contextWith(), nowLocal: now).fired, isTrue);
  });
}
