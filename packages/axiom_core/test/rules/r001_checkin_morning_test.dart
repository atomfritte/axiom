/// R-001 — „Check-in Morgen".
///
/// Die Regel, die alle anderen traegt: Ohne Messpunkte ist der
/// Zustandsvektor blind, und jede spaetere Regel raet [D1]. Geprueft wird
/// deshalb nicht, dass sie irgendwann feuert, sondern wo genau ihre Kanten
/// liegen. Ein um zwei Minuten verschobenes Fenster faellt sonst niemandem
/// auf — eine ausgebliebene Aufforderung sieht aus wie ein ruhiger Morgen.
///
/// Der Bedingungsbaum wird hier so aufgebaut, wie der YAML-Parser ihn
/// aufbaut (`Condition.fromMap`), und gegen echte Zustaende ausgewertet.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Der Bedingungsbaum aus rules/core/s1-baseline.yaml, Wort fuer Wort.
Condition r001() => Condition.fromMap({
      'all': [
        {
          'time_between': ['08:45', '09:30'],
        },
        {
          'count_today': {'event': 'checkin', 'lt': 1},
        },
      ],
    });

EvalContext contextAt(
  int hour,
  int minute, {
  int checkinsToday = 0,
}) =>
    StateEvalContext(
      state: stateOf(),
      clock: FakeClock(DateTime(2026, 8, 3, hour, minute)),
      runtime: RuntimeContext(
        countTodayByEvent: {'checkin': checkinsToday},
      ),
    );

void main() {
  group('R-001 fragt in einem Fenster, nicht zu einem Zeitpunkt', () {
    test('eine Minute vor dem Fenster noch nicht', () {
      expect(r001().eval(contextAt(8, 44)), isFalse);
    });

    test('ab 08:45 genau', () {
      // time_between ist an beiden Enden einschliessend. Steht hier lt
      // statt lte, verschiebt sich der Start um eine Minute — unsichtbar.
      expect(r001().eval(contextAt(8, 45)), isTrue);
    });

    test('09:30 gehoert noch dazu', () {
      expect(r001().eval(contextAt(9, 30)), isTrue);
    });

    test('eine Minute danach nicht mehr', () {
      expect(r001().eval(contextAt(9, 31)), isFalse);
    });

    test('um Mitternacht schweigt sie', () {
      // Das Fenster laeuft nicht ueber den Tageswechsel. Waeren die beiden
      // Zeiten vertauscht, waere aus dem Vormittagsfenster ein
      // Nachtfenster geworden — dieselbe Zeile, umgekehrte Bedeutung.
      expect(r001().eval(contextAt(0, 0)), isFalse);
    });
  });

  group('R-001 zaehlt Check-ins, nicht Slots', () {
    test('ohne Check-in heute fragt sie', () {
      expect(r001().eval(contextAt(9, 0)), isTrue);
    });

    test('nach dem ersten Check-in ist sie still', () {
      expect(
        r001().eval(contextAt(9, 0, checkinsToday: 1)),
        isFalse,
        reason: 'Wer schon erfasst hat, wird nicht ein zweites Mal gefragt',
      );
    });

    test('fehlender Zaehler heisst null, nicht unbekannt', () {
      // countToday liefert 0 fuer einen Ereignistyp, der heute nie
      // vorkam. Waere das null oder ein Fehler, schwiege die Regel
      // ausgerechnet am ersten Tag nach der Installation.
      final ctx = StateEvalContext(
        state: stateOf(),
        clock: FakeClock(DateTime(2026, 8, 3, 9)),
        runtime: const RuntimeContext(),
      );
      expect(r001().eval(ctx), isTrue);
    });
  });

  group('R-001 kommt auch durch die Systemgrenzen', () {
    Rule rule() => ruleOf(
          id: 'R-001',
          when: r001(),
          action: ActionType.promptCheckin,
          priority: 70,
          cooldown: const Cooldown(minInterval: Duration(minutes: 60), maxPerDay: 1),
        );

    test('das Fenster liegt vollstaendig ausserhalb der Ruhezeit', () {
      // Die Ruhezeit endet um 06:30. Ruecke jemand das Fenster nach vorn,
      // wuerde die Regel stumm ausfallen, ohne dass ihre Bedingung sich
      // aendert — die Sorte Fehler, die nur eine Auswertung gegen die
      // echten Grenzen findet.
      final now = DateTime(2026, 8, 3, 8, 45);
      expect(fireOnce(rule(), ctx: contextAt(8, 45), nowLocal: now).fired, isTrue);
    });

    test('einmal am Tag, nicht bei jedem Blick auf die App', () {
      final now = DateTime(2026, 8, 3, 9);
      final outcome = fireOnce(
        rule(),
        ctx: contextAt(9, 0),
        nowLocal: now,
        history: FakeHistory(today: {'R-001': 1}),
      );
      expect(outcome.fired, isFalse);
      expect(outcome.reason, SkipReason.dailyLimitReached);
    });
  });
}
