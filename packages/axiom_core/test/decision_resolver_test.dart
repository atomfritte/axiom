import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

({Decision? winner, List<Decision> suppressed}) resolve(List<Rule> rules) {
  var counter = 0;
  return const DecisionResolver().resolve(
    fired: rules.map(FiredRule.new).toList(),
    at: testNoon,
    stateSnapshotId: 'snap-1',
    explain: (r) => r.rationale,
    nextId: () => 'd${counter++}',
  );
}

void main() {
  test('liefert genau EINE Entscheidung — nie eine Liste zur Auswahl (G1)', () {
    final r = resolve([
      ruleOf(id: 'R-001', priority: 10),
      ruleOf(id: 'R-002', priority: 90),
      ruleOf(id: 'R-003', priority: 50),
    ]);
    expect(r.winner, isNotNull);
    expect(r.winner!.ruleId, 'R-002');
    expect(r.suppressed, hasLength(2));
  });

  test('severity schlaegt priority', () {
    final r = resolve([
      ruleOf(id: 'R-001', priority: 99, severity: Severity.nudge),
      ruleOf(id: 'R-002', priority: 1, severity: Severity.enforce),
    ]);
    expect(r.winner!.ruleId, 'R-002');
  });

  test('rule_id als stabiler Tie-Break — kein Zufall', () {
    final r = resolve([
      ruleOf(id: 'R-050', priority: 60, severity: Severity.nudge),
      ruleOf(id: 'R-020', priority: 60, severity: Severity.nudge),
      ruleOf(id: 'R-030', priority: 60, severity: Severity.nudge),
    ]);
    expect(r.winner!.ruleId, 'R-020');
  });

  test('Verlierer werden protokolliert, nicht verworfen', () {
    final r = resolve([
      ruleOf(id: 'R-001', priority: 90),
      ruleOf(id: 'R-002', priority: 10),
    ]);
    expect(r.winner!.suppressed, isFalse);
    expect(r.suppressed.single.ruleId, 'R-002');
    expect(r.suppressed.single.suppressed, isTrue);
  });

  test('SHADOW-Regeln erzeugen nie eine Nutzerausgabe', () {
    final r = resolve([
      ruleOf(id: 'R-900', action: ActionType.logOnly, priority: 99),
      ruleOf(id: 'R-001', priority: 10),
    ]);
    expect(r.winner!.ruleId, 'R-001');
    expect(r.suppressed, isEmpty);
  });

  test('nur SHADOW-Regeln -> keine Entscheidung', () {
    final r = resolve([ruleOf(id: 'R-900', action: ActionType.logOnly)]);
    expect(r.winner, isNull);
  });

  test('Determinismus: gleiche Eingabe, gleiche Ausgabe (ADR-0003)', () {
    final rules = [
      ruleOf(id: 'R-003', priority: 60),
      ruleOf(id: 'R-001', priority: 60),
      ruleOf(id: 'R-002', priority: 80),
    ];
    final a = resolve(rules);
    final b = resolve(rules.reversed.toList());
    expect(a.winner!.ruleId, b.winner!.ruleId);
    expect(
      a.suppressed.map((d) => d.ruleId).toList(),
      b.suppressed.map((d) => d.ruleId).toList(),
    );
  });

  test('jede Entscheidung traegt rule_id und Begruendung (G2)', () {
    final r = resolve([ruleOf(id: 'R-001')]);
    expect(r.winner!.ruleId, isNotEmpty);
    expect(r.winner!.explanation, isNotEmpty);
    expect(r.winner!.stateSnapshotId, 'snap-1');
  });

  test('Regel ohne rationale ist nicht konstruierbar (G2 erzwungen)', () {
    expect(
      () => Rule(
        id: 'R-999',
        title: 'Ohne Begruendung',
        rationale: '   ',
        when: const NumericCompare('capacity', CompareOp.gte, 0),
        then: const Action(ActionType.notify),
        priority: 50,
        severity: Severity.nudge,
        cooldown: const Cooldown(minInterval: Duration.zero),
      ),
      throwsA(isA<ConditionError>()),
    );
  });
}
