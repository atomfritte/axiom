/// R-100 — „Vormittags: trinken und aufstehen".
///
/// Reiner Zeittrigger. Bei diesem Profil der zuverlaessigste
/// Interventionstyp, weil Puenktlichkeit auch gegenueber der App gilt [D4].
/// Durst und Bewegungsbedarf werden systematisch zu spaet bemerkt, im
/// Hyperfokus gar nicht [D7].
///
/// Der Zaehler ist die interessante Stelle: Gezaehlt werden **quittierte**
/// Koerpersignale, nicht ausgespielte Aufforderungen. Wer heute schon
/// zweimal getrunken und das eingetragen hat, wird nicht erinnert — wer
/// zweimal erinnert wurde und nichts getan hat, dagegen schon.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Der Bedingungsbaum aus rules/core/s2-live.yaml, Wort fuer Wort.
Condition r100() => Condition.fromMap({
      'all': [
        {
          'time_between': ['10:30', '11:15'],
        },
        {
          'count_today': {'event': 'body_prompt', 'lt': 2},
        },
      ],
    });

EvalContext contextAt(
  int hour,
  int minute, {
  int bodyPromptsToday = 0,
}) =>
    StateEvalContext(
      state: stateOf(),
      clock: FakeClock(DateTime(2026, 8, 3, hour, minute)),
      runtime: RuntimeContext(
        countTodayByEvent: {'body_prompt': bodyPromptsToday},
      ),
    );

void main() {
  group('R-100 haelt sein Fenster', () {
    test('10:29 noch nicht', () {
      expect(r100().eval(contextAt(10, 29)), isFalse);
    });

    test('10:30 schon', () {
      expect(r100().eval(contextAt(10, 30)), isTrue);
    });

    test('11:15 noch', () {
      expect(r100().eval(contextAt(11, 15)), isTrue);
    });

    test('11:16 nicht mehr', () {
      expect(r100().eval(contextAt(11, 16)), isFalse);
    });

    test('am fruehen Morgen nicht', () {
      expect(r100().eval(contextAt(7, 0)), isFalse);
    });

    test('am Nachmittag nicht — dafuer gibt es R-101', () {
      expect(r100().eval(contextAt(15, 30)), isFalse);
    });
  });

  group('R-100 zaehlt quittierte Signale', () {
    test('noch keins heute — sie meldet sich', () {
      expect(r100().eval(contextAt(10, 45)), isTrue);
    });

    test('eins heute — sie meldet sich noch', () {
      expect(r100().eval(contextAt(10, 45, bodyPromptsToday: 1)), isTrue);
    });

    test('zwei heute — sie ist still', () {
      expect(
        r100().eval(contextAt(10, 45, bodyPromptsToday: 2)),
        isFalse,
        reason: 'Wer den Vormittag ueber zweimal getrunken hat, braucht '
            'keine dritte Erinnerung',
      );
    });

    test('fehlender Zaehler heisst null', () {
      final ctx = StateEvalContext(
        state: stateOf(),
        clock: FakeClock(DateTime(2026, 8, 3, 10, 45)),
        runtime: const RuntimeContext(),
      );
      expect(r100().eval(ctx), isTrue);
    });
  });

  test('R-100 kommt durch die Systemgrenzen', () {
    final rule = ruleOf(
      id: 'R-100',
      when: r100(),
      priority: 40,
      cooldown:
          const Cooldown(minInterval: Duration(minutes: 120), maxPerDay: 1),
    );
    final now = DateTime(2026, 8, 3, 10, 45);
    expect(fireOnce(rule, ctx: contextAt(10, 45), nowLocal: now).fired, isTrue);
  });

  test('R-100 verliert gegen jede wichtigere Regel im selben Moment', () {
    // priority 40 ist der niedrigste Wert im ganzen Regelwerk, und das ist
    // Absicht: „trinken" darf nie einen Termin oder einen Notaus verdraengen
    // (G1 — genau eine Handlung).
    final now = DateTime(2026, 8, 3, 10, 45);
    final result = const RuleEngine().evaluate(
      rules: [
        ruleOf(id: 'R-100', when: r100(), priority: 40),
        ruleOf(id: 'R-020', priority: 80),
      ],
      ctx: contextAt(10, 45),
      history: FakeHistory(),
      nowLocal: now,
    );
    final resolved = const DecisionResolver().resolve(
      fired: result.fired,
      at: now,
      stateSnapshotId: 'snapshot',
      explain: (r) => r.rationale,
      nextId: () => 'decision-1',
    );
    expect(resolved.winner?.ruleId, 'R-020');
    expect(resolved.suppressed.map((d) => d.ruleId), ['R-100']);
  });
}
