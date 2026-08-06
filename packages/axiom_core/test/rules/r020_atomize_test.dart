/// R-020 — „Wichtig, aber nicht startbar — zerlegen statt anmahnen".
///
/// Der uebliche Fehlermodus: Eine wichtige Aufgabe liegt seit Wochen oben
/// und erzeugt bei jedem Blick Schuld, ohne je zu starten. Schuld senkt die
/// Regulationsreserve und macht den Start noch unwahrscheinlicher [D2].
/// Statt anzumahnen wird zerlegt.
///
/// Die Bedingung besteht aus zwei Zeilen, und die zweite ist die wichtigere:
/// Ohne `not active_slot == focus` waere die Regel eine Unterbrechung
/// mitten in der Vertiefung — dem wertvollsten Zustand, den dieses Profil
/// hat [D6].
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Der Bedingungsbaum aus rules/core/s3-regulation.yaml, Wort fuer Wort.
Condition r020() => Condition.fromMap({
      'all': [
        {
          'capacity': {'lt': 50},
        },
        {
          'not': {
            'active_slot': {'eq': 'focus'},
          },
        },
      ],
    });

EvalContext contextWith({
  required int capacity,
  String slot = 'none',
  int hour = 14,
}) =>
    StateEvalContext(
      state: stateOf(capacity: capacity),
      clock: FakeClock(DateTime(2026, 8, 3, hour)),
      runtime: RuntimeContext(activeSlot: slot),
    );

void main() {
  group('R-020 greift unterhalb der halben Kapazitaet', () {
    test('49 — Anlass', () {
      expect(r020().eval(contextWith(capacity: 49)), isTrue);
    });

    test('50 — kein Anlass', () {
      // lt, nicht lte: Bei genau der Haelfte gilt der Bestand als
      // erreichbar. Eine Verschiebung um einen Punkt aendert nichts am
      // Bildschirm und alles daran, wie oft die Regel spricht.
      expect(r020().eval(contextWith(capacity: 50)), isFalse);
    });

    test('leerer Tank — erst recht', () {
      expect(r020().eval(contextWith(capacity: 0)), isTrue);
    });

    test('voller Tank — still', () {
      expect(r020().eval(contextWith(capacity: 100)), isFalse);
    });
  });

  group('R-020 unterbricht keine laufende Vertiefung', () {
    test('waehrend eines Fokusblocks still', () {
      expect(
        r020().eval(contextWith(capacity: 20, slot: 'focus')),
        isFalse,
        reason: 'Eine falsch getimte Unterbrechung zerstoert den '
            'wertvollsten Zustand, den dieses Profil hat [D6]',
      );
    });

    test('waehrend eines Reiz-Slots dagegen schon', () {
      // Der Ausschluss gilt nur dem Fokus. Ein laufender Reiz-Slot ist
      // kein Zustand, den ein Zerlegungsvorschlag beschaedigt.
      expect(r020().eval(contextWith(capacity: 20, slot: 'sensation')), isTrue);
    });

    test('ohne laufenden Slot schon', () {
      expect(r020().eval(contextWith(capacity: 20)), isTrue);
    });
  });

  group('Was die Bedingung nicht prueft', () {
    test('sie fragt nicht, ob es ueberhaupt etwas zu zerlegen gibt', () {
      // Befund, festgehalten statt behoben: Der Titel spricht von einer
      // wichtigen Aufgabe, die nicht startbar ist — die Bedingung liest
      // dazu nichts. Sie trifft auch auf einem leeren Bestand zu, denn der
      // Bedingungsbaum kennt keine Aufgaben.
      //
      // Sichtbar wird das erst in der Oberflaeche: Ohne Zerlegungs-
      // kandidaten faellt now_screen.dart auf die allgemeine
      // Entscheidungskarte zurueck und zeigt „Regel R-020 …" ohne etwas,
      // das man zerlegen koennte — formal korrekt, praktisch wertlos (G1).
      //
      // Im Regelwortschatz gibt es heute keine Zahl fuer „etwas Wichtiges
      // liegt ausser Reichweite". Der Test haelt die Luecke fest, damit sie
      // beim naechsten Blick nicht wieder neu entdeckt werden muss.
      expect(r020().eval(contextWith(capacity: 30)), isTrue);
      expect(
        r020().referencedVariables,
        {'capacity', 'active_slot'},
        reason: 'Keine Variable des Baums bezieht sich auf den Bestand',
      );
    });
  });

  group('R-020 und die Systemgrenzen', () {
    Rule rule() => ruleOf(
          id: 'R-020',
          when: r020(),
          action: ActionType.forceAtomize,
          priority: 80,
          cooldown: const Cooldown(
            minInterval: Duration(minutes: 360),
            maxPerDay: 2,
            exponentialBackoff: true,
          ),
        );

    test('kein Zeitfenster — die Ruhezeit ist die einzige Grenze', () {
      // Die Regel traegt keine Uhrzeit. Nachts haelt sie allein die
      // Ruhezeit zurueck, und das soll sichtbar bleiben: Verschoebe jemand
      // die Ruhezeit, spraeche R-020 um drei Uhr morgens.
      final night = DateTime(2026, 8, 3, 3);
      final outcome =
          fireOnce(rule(), ctx: contextWith(capacity: 20, hour: 3), nowLocal: night);
      expect(outcome.fired, isFalse);
      expect(outcome.reason, SkipReason.quietHours);

      final day = DateTime(2026, 8, 3, 14);
      expect(fireOnce(rule(), ctx: contextWith(capacity: 20), nowLocal: day).fired,
          isTrue);
    });

    test('wiederholtes Ablehnen verdoppelt den Abstand', () {
      // backoff: exponential in der YAML. Eine Regel, die nervt, korrigiert
      // sich selbst, statt weggewischt zu werden (R2).
      final cooldown = rule().cooldown;
      expect(cooldown.effectiveInterval(0), const Duration(minutes: 360));
      expect(cooldown.effectiveInterval(1), const Duration(minutes: 720));
      expect(
        cooldown.effectiveInterval(9),
        const Duration(minutes: 360 * 8),
        reason: 'Gedeckelt bei 8x, damit die Regel nicht lautlos '
            'verschwindet, sondern im Rueckblick als Streichkandidat '
            'auftaucht',
      );
    });
  });
}
