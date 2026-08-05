/// R-140 — „Die Frist ist näher als der Anlauf".
///
/// Geprueft wird das Verhalten der Bedingung, nicht ihre Schreibweise: Der
/// Baum wird hier genauso aufgebaut, wie der YAML-Parser ihn aufbaut
/// (`Condition.fromMap`), und dann gegen echte Zustaende ausgewertet. Faellt
/// dieser Test um, feuert die Regel auf dem Geraet anders als gedacht.
///
/// Dass die Werte auch tatsaechlich aus dem Bestand kommen, prueft
/// `tightestDeadline` weiter unten — die Regel ist nur so gut wie die Zahl,
/// die sie liest.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Der Bedingungsbaum aus rules/core/s3-regulation.yaml, Wort fuer Wort.
Condition r140() => Condition.fromMap({
      'all': [
        {
          'deadline_slack_hours': {'lte': 0},
        },
        {
          'hours_to_deadline': {'gt': 0},
        },
      ],
    });

EvalContext contextWith({
  required num hoursToDeadline,
  required num slack,
}) =>
    StateEvalContext(
      state: stateOf(),
      clock: FakeClock(DateTime.utc(2026, 8, 3, 10)),
      runtime: RuntimeContext(
        hoursToDeadline: hoursToDeadline,
        deadlineSlackHours: slack,
      ),
    );

Task taskOf({
  required int ae,
  DateTime? decayAt,
  Duration? estimate,
  TaskState state = TaskState.ready,
}) =>
    Task(
      id: 'T$ae${decayAt?.hour ?? 0}',
      title: 'Steuerunterlagen',
      activationEnergy: ae,
      salience: 5,
      stakes: 8,
      decayAt: decayAt,
      estimate: estimate,
      state: state,
    );

void main() {
  final now = DateTime(2026, 8, 3, 10);

  group('R-140 feuert genau dann, wenn die Zeit rechnerisch nicht reicht', () {
    test('Frist in sechs Stunden, Anlauf zwei — kein Anlass', () {
      expect(
        r140().eval(contextWith(hoursToDeadline: 6, slack: 4)),
        isFalse,
        reason: 'Vier Stunden Rest sind kein Druck, sondern Zeit',
      );
    });

    test('Anlauf laenger als die verbleibende Zeit — Anlass', () {
      expect(
        r140().eval(contextWith(hoursToDeadline: 2, slack: -0.5)),
        isTrue,
      );
    });

    test('genau aufgehend zaehlt schon dazu', () {
      // lte, nicht lt: Wenn der Anlauf die Zeit exakt aufbraucht, ist der
      // Moment zum Anfangen jetzt — nicht gleich.
      expect(r140().eval(contextWith(hoursToDeadline: 2, slack: 0)), isTrue);
    });

    test('eine abgelaufene Frist meldet sich nicht mehr', () {
      // Sonst meldete sich die Regel bis zum Aufraeumen taeglich — und eine
      // Regel, die einen Zustand wiederholt, wird weggewischt (R2).
      expect(
        r140().eval(contextWith(hoursToDeadline: -3, slack: -5)),
        isFalse,
      );
    });

    test('ohne Frist im Bestand schweigt sie', () {
      // Der Ersatzwert muss so gross sein, dass keine Regel ihn
      // unterschreitet. Waere er null, wuerde die Bedingung werfen; waere er
      // 0, feuerte die Regel bei leerem Bestand dauernd.
      expect(
        r140().eval(contextWith(
          hoursToDeadline: kNoDeadlineHours,
          slack: kNoDeadlineHours,
        )),
        isFalse,
      );
    });
  });

  group('Die Zahlen dahinter', () {
    test('Anlauf ist Kaltstart plus Bearbeitung', () {
      // ae 6 x 15 min = 90 min, dazu 30 min Vorgabe.
      expect(taskRunway(taskOf(ae: 6)), const Duration(minutes: 120));
      // Mit eigener Schaetzung statt der Vorgabe.
      expect(
        taskRunway(taskOf(ae: 2, estimate: const Duration(hours: 3))),
        const Duration(minutes: 210),
      );
    });

    test('es gewinnt der knappste Vorlauf, nicht die naechste Frist', () {
      // Die frühere Frist hat reichlich Luft, die spätere praktisch keine.
      final soonButSmall = taskOf(
        ae: 1,
        decayAt: now.add(const Duration(hours: 4)),
      );
      final laterButHeavy = taskOf(
        ae: 10,
        decayAt: now.add(const Duration(hours: 3, minutes: 10)),
        estimate: const Duration(hours: 2),
      );

      final tightest = tightestDeadline([soonButSmall, laterButHeavy], now);
      expect(tightest?.task.activationEnergy, 10);
      expect(tightest!.untilDue - tightest.runway, lessThan(Duration.zero));
    });

    test('erledigte und verworfene Aufgaben zaehlen nicht mehr', () {
      final done = taskOf(
        ae: 9,
        decayAt: now.add(const Duration(hours: 1)),
        state: TaskState.done,
      );
      expect(tightestDeadline([done], now), isNull);
    });

    test('ohne Frist gibt es nichts zu messen', () {
      expect(tightestDeadline([taskOf(ae: 9)], now), isNull);
    });

    test('Stunden werden auf eine Nachkommastelle gerundet', () {
      // Sonst steht im Regelinspektor "5.983333333333333", und das liest
      // niemand.
      expect(hoursOf(const Duration(minutes: 359)), 6.0);
      expect(hoursOf(const Duration(minutes: 90)), 1.5);
    });
  });
}
