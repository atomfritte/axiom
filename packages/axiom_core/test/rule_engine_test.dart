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

    test('Stundengrenze bremst, sobald sie erreicht ist', () {
      // Vorher wurde maxNotificationsPerHour nur geparst und angezeigt, nie
      // geprueft — eine Grenze, die im Systeminspektor steht und nicht
      // greift, ist schlimmer als keine (G2).
      final result = run(
        [
          ruleOf(id: 'R-001'),
          ruleOf(id: 'R-002'),
          ruleOf(id: 'R-003'),
        ],
        history: FakeHistory(
          last: {
            'R-001': testNoon.subtract(const Duration(minutes: 10)),
            'R-002': testNoon.subtract(const Duration(minutes: 40)),
          },
        ),
      );
      expect(result.fired, isEmpty);
      expect(
        result.skipped.map((s) => s.reason).toSet(),
        {SkipReason.hourlyLimitReached},
      );
    });

    test('was laenger als eine Stunde her ist, bremst nicht mehr', () {
      final result = run(
        [
          ruleOf(id: 'R-001'),
          ruleOf(id: 'R-002'),
          ruleOf(id: 'R-003'),
        ],
        history: FakeHistory(
          last: {
            'R-001': testNoon.subtract(const Duration(minutes: 61)),
            'R-002': testNoon.subtract(const Duration(minutes: 90)),
          },
        ),
      );
      expect(result.fired, hasLength(3));
    });

    test('ein Zeitstempel aus der Zukunft bremst nicht dauerhaft', () {
      // Nach einer Zeitumstellung oder einer von Hand gestellten Uhr kann eine
      // gespeicherte Entscheidung in der Zukunft liegen. Wuerde sie
      // mitgezaehlt, bliebe die Stundengrenze erreicht, bis die Uhr aufgeholt
      // hat — im schlimmsten Fall tagelang stumm.
      final result = run(
        [
          ruleOf(id: 'R-001'),
          ruleOf(id: 'R-002'),
          ruleOf(id: 'R-003'),
        ],
        history: FakeHistory(
          last: {
            'R-001': testNoon.add(const Duration(days: 2)),
            'R-002': testNoon.add(const Duration(minutes: 5)),
          },
        ),
      );
      // R-001 und R-002 haelt ihr eigener Cooldown zurueck — das ist so, seit
      // es Cooldowns gibt. Hier zaehlt nur, dass R-003 nicht zusaetzlich von
      // der Stundengrenze erwischt wird.
      expect(result.fired.map((f) => f.rule.id), ['R-003']);
      expect(
        result.skipped.map((s) => s.reason),
        isNot(contains(SkipReason.hourlyLimitReached)),
      );
    });

    test('Stundengrenze: nur enforce darf durchbrechen', () {
      final result = run(
        [
          ruleOf(id: 'R-001'),
          ruleOf(id: 'R-002'),
          ruleOf(id: 'R-003', severity: Severity.enforce),
        ],
        history: FakeHistory(
          last: {
            'R-001': testNoon.subtract(const Duration(minutes: 10)),
            'R-002': testNoon.subtract(const Duration(minutes: 40)),
          },
        ),
      );
      expect(result.fired.map((f) => f.rule.id), ['R-003']);
    });

    test('log_only laeuft auch an der Stundengrenze weiter', () {
      // Schattenregeln erzeugen keine Ausgabe. Wuerde die Bremse sie
      // erwischen, fehlten in der Kalibrierphase genau die Treffer, wegen
      // derer sie mitlaufen.
      final result = run(
        [
          ruleOf(id: 'R-001'),
          ruleOf(id: 'R-002'),
          ruleOf(id: 'R-900', action: ActionType.logOnly),
        ],
        history: FakeHistory(
          last: {
            'R-001': testNoon.subtract(const Duration(minutes: 10)),
            'R-002': testNoon.subtract(const Duration(minutes: 40)),
          },
        ),
      );
      expect(result.fired.map((f) => f.rule.id), ['R-900']);
    });

    test('die wirksame Zahl ist die angezeigte aus limits.yaml', () {
      // Der Systeminspektor zeigt limits.maxNotificationsPerHour als
      // geltende Grenze. Also muss genau dieser Wert entscheiden.
      final history = FakeHistory(
        last: {'R-001': testNoon.subtract(const Duration(minutes: 10))},
      );
      final withOne = run(
        [ruleOf(id: 'R-001'), ruleOf(id: 'R-002')],
        history: history,
        limits: const GlobalLimits(maxNotificationsPerHour: 1),
      );
      final withThree = run(
        [ruleOf(id: 'R-001'), ruleOf(id: 'R-002')],
        history: history,
        limits: const GlobalLimits(maxNotificationsPerHour: 3),
      );
      expect(withOne.fired, isEmpty);
      expect(withThree.fired, hasLength(2));
    });

    test('verdraengte Regeln ruecken nicht unbegrenzt nach', () {
      // Der Burst aus dem Befund, Schritt fuer Schritt nachgefahren: vier
      // gleichzeitig zutreffende Regeln, alle fuenf Minuten eine neue
      // Auswertung. Weil nur die ausgespielte Entscheidung ein lastFired
      // bekommt und die verdraengten als `suppressed` gespeichert werden,
      // stand vorher bei jedem Aufruf die naechste Regel bereit: vier
      // verschiedene Aufforderungen in zwanzig Minuten.
      const cooldownByRule = <String, Duration>{
        'R-052': Duration(hours: 4),
        'R-020': Duration(hours: 6),
        'R-080': Duration(hours: 12),
        'R-110': Duration(hours: 12),
      };
      final rules = [
        for (final e in cooldownByRule.entries)
          ruleOf(
            id: e.key,
            severity: e.key == 'R-052' ? Severity.intervene : Severity.nudge,
            cooldown: Cooldown(minInterval: e.value),
          ),
      ];

      final last = <String, DateTime>{};
      final history = FakeHistory(last: last);
      const resolver = DecisionResolver();
      final emitted = <String>[];

      var now = DateTime(2026, 8, 3, 22, 30); // vor Beginn der Ruhezeit
      for (var i = 0; i < 4; i++) {
        final resolved = resolver.resolve(
          fired: run(rules, now: now, history: history).fired,
          at: now,
          stateSnapshotId: 'snapshot',
          explain: (rule) => rule.rationale,
          nextId: () => 'decision-$i',
        );
        final winner = resolved.winner;
        if (winner != null) {
          emitted.add(winner.ruleId);
          // Genau das tut der Speicher: Nur die ausgespielte Entscheidung
          // setzt lastFired, die verdraengten nicht.
          last[winner.ruleId] = now;
        }
        now = now.add(const Duration(minutes: 5));
      }

      expect(emitted, ['R-052', 'R-020']);
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
