/// R-090 — „Erhaltungsmodus (L3)".
///
/// Die eingreifendste Regel des Systems: 72 Stunden nur Pflicht und
/// Erholung. Ein hochkompensiertes System bemerkt seinen eigenen Absturz
/// zuletzt, weil es nach aussen bis kurz vor dem Bruch fehlerfrei laeuft
/// [D1]. L3 ist der externe Notaus, den der Nutzer im ruhigen Zustand selbst
/// autorisiert hat — und ein Erfolg des Systems, kein Scheitern des Nutzers.
///
/// Die Bedingung hat zwei unabhaengige Zweige, und der zweite ist der
/// wichtigere: `load_index` ist ein Sieben-Tage-Mittel und braucht Tage, um
/// 85 zu erreichen. Eine akute Nacht plus leere Kapazitaet kommt frueher.
/// Beide Zweige einzeln zu pruefen ist der ganze Punkt dieses Tests — ein
/// `any` verdeckt einen toten Zweig vollstaendig.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Der Bedingungsbaum aus rules/core/s3-regulation.yaml, Wort fuer Wort.
Condition r090() => Condition.fromMap({
      'any': [
        {
          'load_level': {'eq': 'L3'},
        },
        {
          'all': [
            {
              'sleep_debt': {'gte': 70},
            },
            {
              'capacity': {'lt': 25},
            },
          ],
        },
      ],
    });

EvalContext contextWith({
  int loadIndex = 20,
  int sleepDebt = 10,
  int capacity = 60,
  int hour = 14,
}) =>
    StateEvalContext(
      state: stateOf(
        loadIndex: loadIndex,
        sleepDebt: sleepDebt,
        capacity: capacity,
      ),
      clock: FakeClock(DateTime(2026, 8, 3, hour)),
      runtime: const RuntimeContext(),
    );

void main() {
  group('Zweig 1 — die Laststufe', () {
    test('84 ergibt L2, nicht L3', () {
      expect(stateOf(loadIndex: 84).loadLevel, LoadLevel.l2);
      expect(r090().eval(contextWith(loadIndex: 84)), isFalse);
    });

    test('85 ergibt L3 — Anlass', () {
      expect(stateOf(loadIndex: 85).loadLevel, LoadLevel.l3);
      expect(r090().eval(contextWith(loadIndex: 85)), isTrue);
    });

    test('L0 im Normalbetrieb loest nichts aus', () {
      expect(r090().eval(contextWith()), isFalse);
    });

    test('der Vergleich laeuft ueber den Namen der Stufe, nicht die Zahl', () {
      // load_level ist symbolisch. Stuende in der YAML „l3" statt „L3",
      // muss die Auswertung trotzdem stimmen — SymbolicCompare vergleicht
      // ohne Ruecksicht auf Gross- und Kleinschreibung. Sonst haengt eine
      // Notaus-Regel an einer Schreibweise.
      final lower = Condition.fromMap({
        'load_level': {'eq': 'l3'},
      });
      expect(lower.eval(contextWith(loadIndex: 90)), isTrue);
    });
  });

  group('Zweig 2 — akut, bevor das Wochenmittel nachzieht', () {
    test('Schlafschuld 70 und Kapazitaet 24 — Anlass', () {
      expect(
        r090().eval(contextWith(sleepDebt: 70, capacity: 24)),
        isTrue,
        reason: 'Der Zweig existiert genau fuer den Fall, in dem der '
            'Sieben-Tage-Mittelwert noch nicht nachgezogen hat',
      );
    });

    test('Schlafschuld 69 — noch nicht', () {
      expect(r090().eval(contextWith(sleepDebt: 69, capacity: 24)), isFalse);
    });

    test('Kapazitaet 25 — noch nicht', () {
      expect(r090().eval(contextWith(sleepDebt: 90, capacity: 25)), isFalse);
    });

    test('hohe Schlafschuld allein reicht nicht', () {
      // Eine kurze Nacht ist kein Notaus. Sonst spraeche die schwerste
      // Regel des Systems nach jedem verpassten Schlaf — und wer L3 einmal
      // als uebertrieben erlebt hat, glaubt ihm beim naechsten Mal nicht.
      expect(r090().eval(contextWith(sleepDebt: 95)), isFalse);
    });

    test('niedrige Kapazitaet allein reicht auch nicht', () {
      expect(r090().eval(contextWith(capacity: 10)), isFalse);
    });

    test('beide Zweige zugleich bleibt ein Anlass', () {
      expect(
        r090().eval(contextWith(loadIndex: 90, sleepDebt: 80, capacity: 10)),
        isTrue,
      );
    });
  });

  group('R-090 ist verbindlich und deshalb von Grenzen ausgenommen', () {
    Rule rule() => ruleOf(
          id: 'R-090',
          when: r090(),
          action: ActionType.restrictMode,
          priority: 100,
          severity: Severity.enforce,
          cooldown:
              const Cooldown(minInterval: Duration(minutes: 1440), maxPerDay: 1),
        );

    test('spricht auch in der Ruhezeit', () {
      // Wer um vier Uhr morgens wach ist und L3 erreicht hat, ist genau der
      // Fall. Ein Notaus, der bis zum Morgen wartet, ist keiner.
      final now = DateTime(2026, 8, 3, 4);
      expect(
        fireOnce(rule(), ctx: contextWith(loadIndex: 90, hour: 4), nowLocal: now)
            .fired,
        isTrue,
      );
    });

    test('spricht auch bei erschoepftem Tagesbudget', () {
      final now = DateTime(2026, 8, 3, 14);
      expect(
        fireOnce(
          rule(),
          ctx: contextWith(loadIndex: 90),
          nowLocal: now,
          history: FakeHistory(total: 12),
        ).fired,
        isTrue,
      );
    });

    test('aber nur einmal am Tag', () {
      // Die Einschraenkung laeuft 72 Stunden. Sie taeglich neu anzukuendigen
      // waere Wiederholung; sie stuendlich anzukuendigen waere Strafe (R7).
      final now = DateTime(2026, 8, 3, 14);
      final outcome = fireOnce(
        rule(),
        ctx: contextWith(loadIndex: 90),
        nowLocal: now,
        history: FakeHistory(today: {'R-090': 1}),
      );
      expect(outcome.fired, isFalse);
      expect(outcome.reason, SkipReason.dailyLimitReached);
    });

    test('sie schlaegt jede andere Regel', () {
      // severity DESC, dann priority DESC. R-090 traegt beides am
      // hoechsten; wenn sie spricht, spricht sonst niemand (G1).
      final now = DateTime(2026, 8, 3, 14);
      final result = const RuleEngine().evaluate(
        rules: [
          rule(),
          ruleOf(id: 'R-020', priority: 80),
          ruleOf(id: 'R-051', priority: 85, severity: Severity.intervene),
        ],
        ctx: contextWith(loadIndex: 90),
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
      expect(resolved.winner?.ruleId, 'R-090');
    });
  });
}
