/// R-101 — „Nachmittags: Pause fuer Augen und Beine".
///
/// Das Nachmittagstief trifft mit ohnehin sinkender Kapazitaet zusammen
/// [D7]. Kurz aufstehen und den Blick vom Bildschirm nehmen ist die
/// billigste verfuegbare Gegenmassnahme.
///
/// Der Zaehler steht bei vier, nicht bei zwei wie in R-100 — die Schwelle
/// ist kumulativ ueber den Tag gedacht: zwei am Vormittag, zwei bis zum
/// Nachmittag. Wer den Vormittag ausgelassen hat, bekommt hier trotzdem
/// seine Erinnerung, und wer schon vier Signale quittiert hat, keine. Genau
/// dieser Unterschied ist unten festgehalten; eine vertauschte Zahl faellt
/// sonst niemandem auf.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Der Bedingungsbaum aus rules/core/s2-live.yaml, Wort fuer Wort.
Condition r101() => Condition.fromMap({
      'all': [
        {
          'time_between': ['15:00', '15:45'],
        },
        {
          'count_today': {'event': 'body_prompt', 'lt': 4},
        },
      ],
    });

EvalContext contextAt(
  int hour,
  int minute, {
  int bodyPromptsToday = 1,
}) =>
    StateEvalContext(
      state: stateOf(),
      clock: FakeClock(DateTime(2026, 8, 3, hour, minute)),
      runtime: RuntimeContext(
        countTodayByEvent: {'body_prompt': bodyPromptsToday},
      ),
    );

void main() {
  group('R-101 haelt sein Fenster', () {
    test('14:59 noch nicht', () {
      expect(r101().eval(contextAt(14, 59)), isFalse);
    });

    test('15:00 schon', () {
      expect(r101().eval(contextAt(15, 0)), isTrue);
    });

    test('15:45 noch', () {
      expect(r101().eval(contextAt(15, 45)), isTrue);
    });

    test('15:46 nicht mehr', () {
      expect(r101().eval(contextAt(15, 46)), isFalse);
    });

    test('das Vormittagsfenster gehoert R-100', () {
      // Die beiden Fenster duerfen sich nicht beruehren, sonst spraechen
      // zwei Regeln denselben Satz aus verschiedenen Anlaessen (G2).
      expect(r101().eval(contextAt(10, 45)), isFalse);
    });
  });

  group('R-101 zaehlt ueber den ganzen Tag', () {
    test('drei quittierte Signale — sie meldet sich noch', () {
      expect(r101().eval(contextAt(15, 20, bodyPromptsToday: 3)), isTrue);
    });

    test('vier quittierte Signale — sie ist still', () {
      expect(r101().eval(contextAt(15, 20, bodyPromptsToday: 4)), isFalse);
    });

    test('ein ausgelassener Vormittag verhindert den Nachmittag nicht', () {
      // Der Zaehler ist eine Obergrenze, keine Voraussetzung. Kommentarlos
      // uebernehmen, was war — kein Nachtragen, kein Hinweis darauf.
      expect(r101().eval(contextAt(15, 20, bodyPromptsToday: 0)), isTrue);
    });
  });

  test('R-101 kommt durch die Systemgrenzen', () {
    final rule = ruleOf(
      id: 'R-101',
      when: r101(),
      priority: 40,
      cooldown:
          const Cooldown(minInterval: Duration(minutes: 120), maxPerDay: 1),
    );
    final now = DateTime(2026, 8, 3, 15, 20);
    expect(fireOnce(rule, ctx: contextAt(15, 20), nowLocal: now).fired, isTrue);
  });

  test('R-101 spricht hoechstens einmal am Nachmittag', () {
    // Das Fenster ist 45 Minuten breit, die App wertet mehrfach darin aus.
    // Ohne max_per_day waere daraus eine Serie geworden (R2).
    final rule = ruleOf(
      id: 'R-101',
      when: r101(),
      priority: 40,
      cooldown:
          const Cooldown(minInterval: Duration(minutes: 120), maxPerDay: 1),
    );
    final now = DateTime(2026, 8, 3, 15, 40);
    final outcome = fireOnce(
      rule,
      ctx: contextAt(15, 40),
      nowLocal: now,
      history: FakeHistory(today: {'R-101': 1}),
    );
    expect(outcome.fired, isFalse);
    expect(outcome.reason, SkipReason.dailyLimitReached);
  });
}
