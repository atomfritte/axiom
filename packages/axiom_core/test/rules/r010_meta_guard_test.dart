/// R-010 — „Meta-Work-Budget erschoepft" (M12 Meta-Guard).
///
/// G4 ist laut CLAUDE.md das wichtigste Gesetz dieses Projekts, und R-010
/// ist die einzige Regel, die es ausspricht. Sie hat schon einmal nie
/// gefeuert: Vorher stand in der Bedingung `minutes_since: { event:
/// meta_usage }`, und diesen Ereignistyp schreibt niemand — die Nutzungszeit
/// steht in einer eigenen Tabelle. Die Regel war jahrelang formal in
/// Ordnung und faktisch tot. Genau diese Fehlerart faengt kein Widget-Test:
/// Ein Deckel, der nicht greift, sieht aus wie ein Deckel, den man nie
/// erreicht.
///
/// Der Test prueft deshalb beides: dass die Zahl ueberhaupt ankommt und dass
/// die Schwelle dort liegt, wo die Budgetkarte sie zeigt.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Der Bedingungsbaum aus rules/core/s1-baseline.yaml, Wort fuer Wort.
Condition r010() => Condition.fromMap({
      'meta_minutes_today': {'gte': 12},
    });

EvalContext contextWith({required int metaMinutes, int hour = 14}) =>
    StateEvalContext(
      state: stateOf(),
      clock: FakeClock(DateTime(2026, 8, 3, hour)),
      runtime: RuntimeContext(metaMinutesToday: metaMinutes),
    );

void main() {
  group('R-010 greift genau am Deckel', () {
    test('elf Minuten — noch offen', () {
      expect(r010().eval(contextWith(metaMinutes: 11)), isFalse);
    });

    test('zwoelf Minuten — zu', () {
      // gte, nicht gt: Die Budgetkarte zeigt „12 Minuten", also muss die
      // zwoelfte Minute die letzte sein. Stuende hier gt, waere der
      // angezeigte Deckel um eine Minute falsch — und ein angezeigter
      // Grenzwert, der nicht gilt, ist schlimmer als keiner (G2).
      expect(r010().eval(contextWith(metaMinutes: 12)), isTrue);
    });

    test('darueber erst recht', () {
      expect(r010().eval(contextWith(metaMinutes: 40)), isTrue);
    });

    test('ein frischer Tag beginnt offen', () {
      // Voreinstellung des RuntimeContext, also der Zustand kurz nach
      // Mitternacht: Der Zaehler laeuft tagesweise, nicht bis zum
      // naechsten Rueckblick.
      final ctx = StateEvalContext(
        state: stateOf(),
        clock: FakeClock(DateTime(2026, 8, 3, 0, 5)),
        runtime: const RuntimeContext(),
      );
      expect(r010().eval(ctx), isFalse);
    });
  });

  group('R-010 liest die Nutzungszeit, nicht ein Ereignis', () {
    test('die Variable ist im Wortschatz und wird aufgeloest', () {
      // Der Rueckfall in den frueheren Fehler waere, die Zahl an einen
      // Ereignistyp zu haengen, den niemand schreibt. Dann liefe die
      // Auswertung ins Leere statt in einen Fehler.
      expect(r010().referencedVariables, {'meta_minutes_today'});
      expect(RuleVocabulary.numeric('meta_minutes_today'), isNotNull);
      expect(
        contextWith(metaMinutes: 7).numeric('meta_minutes_today'),
        7,
      );
    });
  });

  group('R-010 ist verbindlich und deshalb von Grenzen ausgenommen', () {
    Rule rule() => ruleOf(
          id: 'R-010',
          when: r010(),
          action: ActionType.lockConfig,
          priority: 95,
          severity: Severity.enforce,
          cooldown:
              const Cooldown(minInterval: Duration(minutes: 1440), maxPerDay: 1),
        );

    test('spricht auch in der Ruhezeit', () {
      // Wer um zwei Uhr nachts im System sitzt, ist genau der Fall, fuer
      // den der Deckel gebaut ist. enforce ist hier kein Uebergriff,
      // sondern der Vertrag mit dem ruhigen Ich.
      final now = DateTime(2026, 8, 3, 2);
      expect(
        fireOnce(rule(), ctx: contextWith(metaMinutes: 20, hour: 2), nowLocal: now)
            .fired,
        isTrue,
      );
    });

    test('spricht auch, wenn das Tagesbudget aller Regeln weg ist', () {
      final now = DateTime(2026, 8, 3, 14);
      expect(
        fireOnce(
          rule(),
          ctx: contextWith(metaMinutes: 20),
          nowLocal: now,
          history: FakeHistory(total: 12),
        ).fired,
        isTrue,
      );
    });

    test('aber nur einmal am Tag', () {
      // Sonst waere aus der Selbstbegrenzung eine Dauerbeschallung
      // geworden — und eine Sperre, die man wegwischt, sperrt nichts (R2).
      final now = DateTime(2026, 8, 3, 14);
      final outcome = fireOnce(
        rule(),
        ctx: contextWith(metaMinutes: 20),
        nowLocal: now,
        history: FakeHistory(today: {'R-010': 1}),
      );
      expect(outcome.fired, isFalse);
      expect(outcome.reason, SkipReason.dailyLimitReached);
    });
  });
}
