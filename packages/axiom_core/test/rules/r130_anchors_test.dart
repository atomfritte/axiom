/// R-130 — „Termine eintragen" (M3 Time Anchor).
///
/// Puenktlichkeit ist bei diesem Profil erfolgreich kompensiert — und genau
/// das ist teuer: Puffer, staendiges Nachrechnen, Dauerspannung vor jedem
/// Termin [D4]. Eingetragene Anker verlagern diese Rechnung vom Kopf ins
/// System.
///
/// **Befund, den dieser Test festhaelt.** Die Bedingung misst etwas anderes
/// als der Titel sagt. Sie liest vier Dinge — Uhrzeit, Wochentag, ob heute
/// schon etwas erfasst wurde und wann zuletzt eine Entscheidung beantwortet
/// wurde — und keines davon hat mit Ankern zu tun. Ob welche gepflegt
/// werden, prueft sie nicht; im Regelwortschatz gibt es dafuer auch keine
/// Variable. Was sie tatsaechlich beschreibt, ist „jemand benutzt das System
/// noch, antwortet aber seit einem Tag nicht mehr auf Entscheidungen".
///
/// Zwei Dinge daempfen das: Die Regel steht auf `log_only` (SHADOW) und
/// `severity: info`, spricht also gar nicht, sondern wird nur protokolliert
/// — und genau dafuer ist die Schattenzeit da. Wer sie live stellt, sollte
/// vorher wissen, was sie zaehlt. Deshalb steht es hier.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Der Bedingungsbaum aus rules/core/s2-live.yaml, Wort fuer Wort.
Condition r130() => Condition.fromMap({
      'all': [
        {
          'time_between': ['08:00', '09:30'],
        },
        {
          'weekday': {'ne': 'sat'},
        },
        {
          'count_today': {'event': 'capture', 'gte': 1},
        },
        {
          'minutes_since': {'event': 'decision_feedback', 'gte': 1440},
        },
      ],
    });

/// 2026-08-03 ist ein Montag, 08-08 ein Samstag, 08-09 ein Sonntag.
EvalContext contextOn(
  int day, {
  int hour = 8,
  int minute = 30,
  int capturesToday = 1,
  int? sinceFeedback,
}) =>
    StateEvalContext(
      state: stateOf(),
      clock: FakeClock(DateTime(2026, 8, day, hour, minute)),
      runtime: RuntimeContext(
        countTodayByEvent: {'capture': capturesToday},
        minutesSinceByEvent: {'decision_feedback': ?sinceFeedback},
      ),
    );

void main() {
  group('R-130 haelt sein Fenster', () {
    test('07:59 noch nicht', () {
      expect(r130().eval(contextOn(3, hour: 7, minute: 59)), isFalse);
    });

    test('08:00 schon', () {
      expect(r130().eval(contextOn(3, hour: 8, minute: 0)), isTrue);
    });

    test('09:30 noch', () {
      expect(r130().eval(contextOn(3, hour: 9, minute: 30)), isTrue);
    });

    test('09:31 nicht mehr', () {
      expect(r130().eval(contextOn(3, hour: 9, minute: 31)), isFalse);
    });
  });

  group('R-130 nimmt den Samstag aus — und nur ihn', () {
    test('Montag: ja', () {
      expect(r130().eval(contextOn(3)), isTrue);
    });

    test('Freitag: ja', () {
      expect(r130().eval(contextOn(7)), isTrue);
    });

    test('Samstag: nein', () {
      expect(r130().eval(contextOn(8)), isFalse);
    });

    test('Sonntag: ja', () {
      // Festgehalten, nicht behoben: Die Zeile nimmt nur den Samstag aus.
      // Ob der Sonntag mitgemeint war, steht nirgends — die Begruendung
      // erwaehnt das Wochenende gar nicht. Solange die Regel im Schatten
      // laeuft, ist das folgenlos; wer sie live stellt, entscheidet hier.
      expect(r130().eval(contextOn(9)), isTrue);
    });
  });

  group('Was die Bedingung wirklich misst', () {
    test('ohne Erfassung heute schweigt sie', () {
      // Die Regel meldet sich nur bei jemandem, der das System heute schon
      // benutzt hat. Mit Ankern hat das nichts zu tun — es ist ein
      // Lebenszeichen, kein Befund ueber Termine.
      expect(r130().eval(contextOn(3, capturesToday: 0)), isFalse);
    });

    test('mit einer Erfassung heute meldet sie sich', () {
      expect(r130().eval(contextOn(3, capturesToday: 1)), isTrue);
    });

    test('Rueckmeldung vor 1439 Minuten — noch nicht', () {
      expect(r130().eval(contextOn(3, sinceFeedback: 1439)), isFalse);
    });

    test('Rueckmeldung vor 1440 Minuten — genau ab hier', () {
      expect(r130().eval(contextOn(3, sinceFeedback: 1440)), isTrue);
    });

    test('nie eine Rueckmeldung gegeben zaehlt als „lange her"', () {
      // Richtig gelesen: „seit X nichts beantwortet". Wer noch nie
      // geantwortet hat, hat erst recht lange nicht geantwortet. Auf einem
      // frisch eingerichteten Geraet trifft die Bedingung damit am ersten
      // Morgen zu, an dem etwas erfasst wurde.
      expect(r130().eval(contextOn(3, sinceFeedback: null)), isTrue);
    });

    test('keine der Variablen bezieht sich auf Anker', () {
      // Der Kern des Befunds in einer Zeile. Faellt dieser Test um, weil
      // jemand eine Ankervariable ergaenzt hat, ist der Befund behoben —
      // und der Test die Stelle, an der man das mitbekommt.
      expect(
        r130().referencedVariables,
        {'time_between', 'weekday', 'event:capture', 'event:decision_feedback'},
      );
    });
  });

  test('R-130 laeuft im Schatten und erzeugt keine Ausgabe', () {
    // log_only umgeht alle Grenzen, weil es nichts ausspielt, sondern nur
    // protokolliert. Deshalb steht in `fired` ein Eintrag, im aufgeloesten
    // Ergebnis aber kein Gewinner (G1: es gibt keine Handlung zu zeigen).
    final rule = ruleOf(
      id: 'R-130',
      when: r130(),
      action: ActionType.logOnly,
      priority: 30,
      severity: Severity.info,
      cooldown: const Cooldown(
        minInterval: Duration(minutes: 1440),
        maxPerDay: 1,
        exponentialBackoff: true,
      ),
    );
    expect(rule.isShadow, isTrue);

    final now = DateTime(2026, 8, 3, 8, 30);
    final result = const RuleEngine().evaluate(
      rules: [rule],
      ctx: contextOn(3),
      history: FakeHistory(total: 12),
      nowLocal: now,
    );
    expect(result.fired.map((f) => f.rule.id), ['R-130']);

    final resolved = const DecisionResolver().resolve(
      fired: result.fired,
      at: now,
      stateSnapshotId: 'snapshot',
      explain: (r) => r.rationale,
      nextId: () => 'decision-1',
    );
    expect(resolved.winner, isNull);
    expect(resolved.suppressed, isEmpty);
  });
}
