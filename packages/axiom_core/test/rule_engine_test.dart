import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

EvaluationResult run(
  List<Rule> rules, {
  StateVector? state,
  DateTime? now,
  DecisionHistory? history,
  GlobalLimits limits = const GlobalLimits(),
  RuntimeContext runtime = const RuntimeContext(),
}) {
  final at = now ?? testNoon;
  return RuleEngine(limits: limits).evaluate(
    rules: rules,
    ctx: StateEvalContext(
      state: state ?? stateOf(),
      clock: FakeClock(at),
      runtime: runtime,
    ),
    history: history ?? FakeHistory(),
    nowLocal: at,
  );
}

void main() {
  group('Grundauswertung', () {
    test('erfuellte Bedingung feuert, unerfuellte nicht', () {
      final result = run([
        ruleOf(id: 'R-001', when: const NumericCompare('capacity', CompareOp.gte, 50)),
        ruleOf(id: 'R-002', when: const NumericCompare('capacity', CompareOp.gte, 90)),
      ], state: stateOf(capacity: 60));

      expect(result.fired.map((f) => f.rule.id), ['R-001']);
      expect(
        result.skipped.single.reason,
        SkipReason.conditionFalse,
      );
    });

    test('deaktivierte Regel feuert nie', () {
      final result = run([ruleOf(id: 'R-001', enabled: false)]);
      expect(result.fired, isEmpty);
      expect(result.skipped.single.reason, SkipReason.disabled);
    });
  });

  group('Cooldown (R2)', () {
    test('blockiert innerhalb des Mindestabstands', () {
      final result = run(
        [
          ruleOf(
            id: 'R-001',
            cooldown: const Cooldown(minInterval: Duration(hours: 3)),
          )
        ],
        history: FakeHistory(
          last: {'R-001': testNoon.subtract(const Duration(minutes: 30))},
        ),
      );
      expect(result.skipped.single.reason, SkipReason.cooldownActive);
    });

    test('laesst nach Ablauf wieder durch', () {
      final result = run(
        [
          ruleOf(
            id: 'R-001',
            cooldown: const Cooldown(minInterval: Duration(hours: 3)),
          )
        ],
        history: FakeHistory(
          last: {'R-001': testNoon.subtract(const Duration(hours: 4))},
        ),
      );
      expect(result.fired, hasLength(1));
    });

    test('Tageslimit greift', () {
      final result = run(
        [
          ruleOf(
            id: 'R-001',
            cooldown: const Cooldown(
              minInterval: Duration.zero,
              maxPerDay: 3,
            ),
          )
        ],
        history: FakeHistory(today: {'R-001': 3}),
      );
      expect(result.skipped.single.reason, SkipReason.dailyLimitReached);
    });

    test('exponentielles Backoff verlaengert nach Ablehnungen', () {
      const cooldown = Cooldown(
        minInterval: Duration(minutes: 60),
        exponentialBackoff: true,
      );
      expect(cooldown.effectiveInterval(0), const Duration(minutes: 60));
      expect(cooldown.effectiveInterval(2), const Duration(minutes: 240));
      // Deckelung bei 8x, damit die Regel nicht faktisch verschwindet,
      // ohne im Review als Streichkandidat aufzutauchen.
      expect(cooldown.effectiveInterval(9), const Duration(minutes: 480));
    });

    test('Backoff blockt eine wiederholt abgelehnte Regel', () {
      final result = run(
        [
          ruleOf(
            id: 'R-001',
            cooldown: const Cooldown(
              minInterval: Duration(minutes: 60),
              exponentialBackoff: true,
            ),
          )
        ],
        history: FakeHistory(
          last: {'R-001': testNoon.subtract(const Duration(minutes: 90))},
          rejections: {'R-001': 3},
        ),
      );
      expect(result.skipped.single.reason, SkipReason.cooldownActive);
    });
  });

  group('Globale Grenzen (R2)', () {
    test('Tagesobergrenze stoppt nudge, nicht enforce', () {
      final result = run(
        [
          ruleOf(id: 'R-001', severity: Severity.nudge),
          ruleOf(id: 'R-002', severity: Severity.enforce),
        ],
        history: FakeHistory(total: 12),
      );
      expect(result.fired.map((f) => f.rule.id), ['R-002']);
      expect(
        result.skipped.single.reason,
        SkipReason.globalLimitReached,
      );
    });

    test('Ruhezeiten: nur enforce darf durchbrechen', () {
      final night = DateTime(2026, 8, 4, 2);
      final result = run(
        [
          ruleOf(id: 'R-001', severity: Severity.intervene),
          ruleOf(id: 'R-002', severity: Severity.enforce),
        ],
        now: night,
      );
      expect(result.fired.map((f) => f.rule.id), ['R-002']);
      expect(result.skipped.single.reason, SkipReason.quietHours);
    });
  });

  group('SHADOW-Modus', () {
    test('log_only feuert unabhaengig von allen Limits', () {
      final result = run(
        [ruleOf(id: 'R-900', action: ActionType.logOnly)],
        now: DateTime(2026, 8, 4, 3), // Ruhezeit
        history: FakeHistory(total: 99), // Tageslimit weit ueberschritten
      );
      expect(result.fired, hasLength(1));
      expect(result.fired.single.rule.isShadow, isTrue);
    });
  });

  group('Konfidenz (R8)', () {
    test('veraltete Daten unterdruecken die Regel — lieber schweigen als raten',
        () {
      final result = run(
        [
          ruleOf(
            id: 'R-001',
            when: const NumericCompare('capacity', CompareOp.gte, 10),
          )
        ],
        state: stateOf(capacity: 60, confidence: {'capacity': 0.2}),
      );
      expect(result.skipped.single.reason, SkipReason.lowConfidence);
    });

    test('ausreichende Konfidenz laesst durch', () {
      final result = run(
        [
          ruleOf(
            id: 'R-001',
            when: const NumericCompare('capacity', CompareOp.gte, 10),
          )
        ],
        state: stateOf(capacity: 60, confidence: {'capacity': 0.9}),
      );
      expect(result.fired, hasLength(1));
    });
  });

  test('Auswertung ist unabhaengig von der Ladereihenfolge', () {
    final rules = [
      ruleOf(id: 'R-003'),
      ruleOf(id: 'R-001'),
      ruleOf(id: 'R-002'),
    ];
    final a = run(rules).fired.map((f) => f.rule.id).toList();
    final b = run(rules.reversed.toList()).fired.map((f) => f.rule.id).toList();
    expect(a, b);
    expect(a, ['R-001', 'R-002', 'R-003']);
  });
}
