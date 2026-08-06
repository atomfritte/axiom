/// R-051 — „Impulsdurchbruch wahrscheinlich — Risikokanaele sichern".
///
/// Sehr hoher Reizbedarf bei gleichzeitig niedriger Regulationsreserve ist
/// der Zustand, in dem ein Impuls durchkommt [D5]. Der Interceptor wird
/// vorsorglich scharf gestellt — kein Verbot, nur Latenz (G3).
///
/// Die Regel ist der Zwilling von R-050: Ab 85 Reizbedarf treffen beide
/// Bedingungen zu, wenn die Kapazitaet reicht. Dass dann genau eine Ausgabe
/// entsteht und welche, ist Teil dessen, was diese Regel haelt (G1) — und
/// steht deshalb hier mit im Test.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Der Bedingungsbaum aus rules/core/s3-regulation.yaml, Wort fuer Wort.
Condition r051() => Condition.fromMap({
      'all': [
        {
          'sensation_need': {'gte': 85},
        },
        {
          'regulation': {'lt': 50},
        },
      ],
    });

/// Der Bedingungsbaum von R-050 — nur fuer die Konfliktaufloesung unten.
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
  int sensationNeed = 90,
  int regulation = 30,
  int capacity = 60,
  int hour = 19,
}) =>
    StateEvalContext(
      state: stateOf(
        sensationNeed: sensationNeed,
        regulation: regulation,
        capacity: capacity,
      ),
      clock: FakeClock(DateTime(2026, 8, 3, hour)),
      runtime: const RuntimeContext(),
    );

void main() {
  group('R-051 verlangt beides gleichzeitig', () {
    test('84 Reizbedarf — noch nicht', () {
      expect(r051().eval(contextWith(sensationNeed: 84)), isFalse);
    });

    test('85 Reizbedarf — genau ab hier', () {
      expect(r051().eval(contextWith(sensationNeed: 85)), isTrue);
    });

    test('49 Regulationsreserve — Anlass', () {
      expect(r051().eval(contextWith(regulation: 49)), isTrue);
    });

    test('50 Regulationsreserve — kein Anlass', () {
      // lt, nicht lte. Bei genau der Haelfte gilt die Reserve als
      // ausreichend; der Interceptor bleibt ungespannt.
      expect(r051().eval(contextWith(regulation: 50)), isFalse);
    });

    test('hoher Bedarf allein reicht nicht', () {
      // Ohne die zweite Zeile waere die Regel ein Dauerzustand fuer ein
      // Profil mit hohem Reizbedarf — und ein dauerhaft scharfer
      // Interceptor ist ein abgeschalteter Interceptor.
      expect(
        r051().eval(contextWith(sensationNeed: 95, regulation: 80)),
        isFalse,
      );
    });

    test('niedrige Reserve allein reicht auch nicht', () {
      expect(
        r051().eval(contextWith(sensationNeed: 40, regulation: 20)),
        isFalse,
      );
    });

    test('der neutrale Zustand loest nichts aus', () {
      final ctx = StateEvalContext(
        state: stateOf(),
        clock: FakeClock(DateTime(2026, 8, 3, 19)),
        runtime: const RuntimeContext(),
      );
      expect(r051().eval(ctx), isFalse);
    });
  });

  group('R-051 traegt kein Zeitfenster — das hat Folgen', () {
    Rule rule() => ruleOf(
          id: 'R-051',
          when: r051(),
          action: ActionType.startCooldown,
          priority: 85,
          severity: Severity.intervene,
          cooldown: const Cooldown(
            minInterval: Duration(minutes: 180),
            maxPerDay: 2,
            exponentialBackoff: true,
          ),
        );

    test('am Abend spricht sie', () {
      final now = DateTime(2026, 8, 3, 19);
      expect(fireOnce(rule(), ctx: contextWith(), nowLocal: now).fired, isTrue);
    });

    test('nachts haelt sie allein die Ruhezeit zurueck', () {
      // Die Bedingung trifft um drei Uhr genauso zu wie um sieben Uhr
      // abends — nur die Ruhezeit unterscheidet die beiden Faelle. Das ist
      // hier vermutlich richtig (R-052 deckt die Nacht ab), aber es ist
      // eine Eigenschaft der Systemgrenzen, nicht der Regel. Wer die
      // Ruhezeit verschiebt, verschiebt R-051 mit.
      final night = DateTime(2026, 8, 3, 3);
      expect(r051().eval(contextWith(hour: 3)), isTrue);
      final outcome =
          fireOnce(rule(), ctx: contextWith(hour: 3), nowLocal: night);
      expect(outcome.fired, isFalse);
      expect(outcome.reason, SkipReason.quietHours);
    });
  });

  test('bei hohem Bedarf und leerer Reserve gewinnt das Sichern', () {
    // Ab 85 Reizbedarf treffen R-050 und R-051 gemeinsam zu. Gezeigt wird
    // genau eine Handlung (G1), und es muss die eingreifendere sein: Erst
    // den Kanal sichern, dann einen Slot vorschlagen. Die umgekehrte
    // Reihenfolge waere ein Vorschlag, waehrend der Impuls schon laeuft.
    final now = DateTime(2026, 8, 3, 19);
    final ctx = contextWith(sensationNeed: 90, regulation: 30, capacity: 60);
    final result = const RuleEngine().evaluate(
      rules: [
        ruleOf(
          id: 'R-050',
          when: r050(),
          action: ActionType.suggestSlot,
          priority: 60,
        ),
        ruleOf(
          id: 'R-051',
          when: r051(),
          action: ActionType.startCooldown,
          priority: 85,
          severity: Severity.intervene,
        ),
      ],
      ctx: ctx,
      history: FakeHistory(),
      nowLocal: now,
    );

    final resolved = const DecisionResolver().resolve(
      fired: result.fired,
      at: now,
      stateSnapshotId: 'snapshot',
      explain: (rule) => rule.rationale,
      nextId: () => 'decision-1',
    );

    expect(result.fired.map((f) => f.rule.id), ['R-050', 'R-051']);
    expect(resolved.winner?.ruleId, 'R-051');
    expect(resolved.suppressed.map((d) => d.ruleId), ['R-050']);
  });
}
