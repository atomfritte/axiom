/// R-052 — „Nachtbestellung abfangen".
///
/// Nachts sind Regulationsreserve und Impulskontrolle am niedrigsten,
/// waehrend Verfuegbarkeit und Novelty am hoechsten sind. Eine Bestellung um
/// 01:00 wird um 09:00 fast nie noch gewollt [D5].
///
/// **Befund, den dieser Test festhaelt.** Genau der Fall, den die
/// Begruendung nennt — 01:00 —, kann nicht eintreten. Die Bedingung trifft
/// zu, aber die Ruhezeit (23:00–06:30, rules/core/limits.yaml) laesst nur
/// `severity: enforce` durch, und R-052 steht auf `intervene`. Vom Fenster
/// 22:00–05:00 bleiben in der Praxis 22:00–22:59 uebrig; sechs der sieben
/// Stunden sind stumm.
///
/// Der Test haelt beide Haelften getrennt fest: was die Bedingung sagt, und
/// was am Geraet daraus wird. Wer die Regel repariert — hoehere Severity
/// oder ein anderes Fenster —, sieht hier, welche Zusage er dabei anfasst.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Der Bedingungsbaum aus rules/core/s3-regulation.yaml, Wort fuer Wort.
Condition r052() => Condition.fromMap({
      'all': [
        {
          'time_between': ['22:00', '05:00'],
        },
        {
          'regulation': {'lt': 50},
        },
      ],
    });

EvalContext contextAt(
  int hour, {
  int minute = 0,
  int regulation = 30,
}) =>
    StateEvalContext(
      state: stateOf(regulation: regulation),
      clock: FakeClock(DateTime(2026, 8, 3, hour, minute)),
      runtime: const RuntimeContext(),
    );

Rule r052Rule() => ruleOf(
      id: 'R-052',
      when: r052(),
      action: ActionType.startCooldown,
      priority: 90,
      severity: Severity.intervene,
      cooldown:
          const Cooldown(minInterval: Duration(minutes: 240), maxPerDay: 2),
    );

void main() {
  group('R-052 spannt ein Fenster ueber Mitternacht', () {
    test('21:59 noch nicht', () {
      expect(r052().eval(contextAt(21, minute: 59)), isFalse);
    });

    test('22:00 schon', () {
      expect(r052().eval(contextAt(22)), isTrue);
    });

    test('Mitternacht liegt mitten drin', () {
      // Die haeufigste Bruchstelle bei Zeitfenstern: Ist die untere Grenze
      // groesser als die obere, muss die Bedingung ODER rechnen, nicht UND.
      // Rechnete sie UND, waere dieses Fenster leer und die Regel tot.
      expect(r052().eval(contextAt(0)), isTrue);
      expect(r052().eval(contextAt(1)), isTrue);
    });

    test('05:00 noch', () {
      expect(r052().eval(contextAt(5)), isTrue);
    });

    test('05:01 nicht mehr', () {
      expect(r052().eval(contextAt(5, minute: 1)), isFalse);
    });

    test('mittags nicht', () {
      expect(r052().eval(contextAt(12)), isFalse);
    });
  });

  group('R-052 verlangt zusaetzlich eine niedrige Reserve', () {
    test('49 — Anlass', () {
      expect(r052().eval(contextAt(1, regulation: 49)), isTrue);
    });

    test('50 — kein Anlass', () {
      expect(r052().eval(contextAt(1, regulation: 50)), isFalse);
    });

    test('volle Reserve nachts — kein Anlass', () {
      // Nachts allein ist kein Befund. Sonst spraeche die Regel jede Nacht,
      // in der jemand einfach spaet wach ist — und wuerde weggewischt (R2).
      expect(r052().eval(contextAt(1, regulation: 80)), isFalse);
    });
  });

  group('Was am Geraet davon uebrig bleibt', () {
    test('22:00 bis 22:59 spricht sie', () {
      for (final at in [
        DateTime(2026, 8, 3, 22),
        DateTime(2026, 8, 3, 22, 59),
      ]) {
        expect(
          fireOnce(r052Rule(), ctx: contextAt(at.hour, minute: at.minute), nowLocal: at)
              .fired,
          isTrue,
          reason: 'Vor Beginn der Ruhezeit ist der Weg frei',
        );
      }
    });

    test('ab 23:00 haelt die Ruhezeit sie zurueck — auch um 01:00', () {
      // Der Fall aus der Begruendung der Regel selbst. Er tritt nie ein.
      for (final hour in [23, 0, 1, 4, 5]) {
        final at = DateTime(2026, 8, hour >= 23 ? 3 : 4, hour);
        expect(r052().eval(contextAt(hour)), isTrue,
            reason: 'Die Bedingung trifft um $hour:00 zu');
        final outcome =
            fireOnce(r052Rule(), ctx: contextAt(hour), nowLocal: at);
        expect(outcome.fired, isFalse);
        expect(
          outcome.reason,
          SkipReason.quietHours,
          reason: 'Um $hour:00 bleibt die Regel stumm, obwohl ihre '
              'Bedingung zutrifft — nur enforce darf die Ruhezeit brechen',
        );
      }
    });

    test('mit verbindlicher Severity waere das Fenster vollstaendig', () {
      // Der Gegenbeweis, damit der Befund oben nicht als Eigenschaft der
      // Uhrzeit missverstanden wird: Es liegt allein an der Severity.
      // Ob R-052 sie bekommen soll, ist eine Entscheidung des Nutzers —
      // enforce gibt es nur fuer Regeln, die er im ruhigen Zustand selbst
      // autorisiert hat.
      final at = DateTime(2026, 8, 4, 1);
      final asEnforce = ruleOf(
        id: 'R-052',
        when: r052(),
        action: ActionType.startCooldown,
        priority: 90,
        severity: Severity.enforce,
        cooldown:
            const Cooldown(minInterval: Duration(minutes: 240), maxPerDay: 2),
      );
      expect(fireOnce(asEnforce, ctx: contextAt(1), nowLocal: at).fired, isTrue);
    });
  });
}
