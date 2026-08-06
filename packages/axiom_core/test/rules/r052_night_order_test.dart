/// R-052 — „Nachtbestellung abfangen".
///
/// Nachts sind Regulationsreserve und Impulskontrolle am niedrigsten,
/// waehrend Verfuegbarkeit und Novelty am hoechsten sind. Eine Bestellung um
/// 01:00 wird um 09:00 fast nie noch gewollt [D5].
///
/// **Was dieser Test festhaelt.** Die Regel stand auf `severity: intervene`
/// und war damit sechs von sieben Stunden tot: Die Ruhezeit (23:00–06:30,
/// rules/core/limits.yaml) laesst nur `enforce` durch, vom Fenster
/// 22:00–05:00 blieb 22:00–22:59 uebrig. Genau der Fall, den die Begruendung
/// als Zweck nennt — 01:00 —, konnte nicht eintreten.
///
/// Seit dem 06.08.2026 steht sie auf `enforce`. Der Test prueft beide
/// Haelften getrennt: was die Bedingung sagt, und was am Geraet daraus wird.
/// Faellt die zweite Haelfte um, weil jemand die Severity gesenkt hat, ist
/// die Regel wieder auf ihre eine Stunde geschrumpft — ohne dass sich am
/// Fenster in der YAML etwas geaendert haette.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Der Bedingungsbaum aus rules/core/s3-regulation.yaml, Wort fuer Wort.
Condition r052() => Condition.fromMap({
      'all': [
        {
          'time_between': ['22:00', '05:00'],
        },
        {
          'regulation': {'lt': 50},
        },
      ],
    });

EvalContext contextAt(
  int hour, {
  int minute = 0,
  int regulation = 30,
}) =>
    StateEvalContext(
      state: stateOf(regulation: regulation),
      clock: FakeClock(DateTime(2026, 8, 3, hour, minute)),
      runtime: const RuntimeContext(),
    );

/// Die Regel, wie sie in rules/core/s3-regulation.yaml steht.
Rule r052Rule({Severity severity = Severity.enforce}) => ruleOf(
      id: 'R-052',
      when: r052(),
      action: ActionType.startCooldown,
      priority: 90,
      severity: severity,
      cooldown:
          const Cooldown(minInterval: Duration(minutes: 240), maxPerDay: 2),
    );

void main() {
  group('R-052 spannt ein Fenster ueber Mitternacht', () {
    test('21:59 noch nicht', () {
      expect(r052().eval(contextAt(21, minute: 59)), isFalse);
    });

    test('22:00 schon', () {
      expect(r052().eval(contextAt(22)), isTrue);
    });

    test('Mitternacht liegt mitten drin', () {
      // Die haeufigste Bruchstelle bei Zeitfenstern: Ist die untere Grenze
      // groesser als die obere, muss die Bedingung ODER rechnen, nicht UND.
      // Rechnete sie UND, waere dieses Fenster leer und die Regel tot.
      expect(r052().eval(contextAt(0)), isTrue);
      expect(r052().eval(contextAt(1)), isTrue);
    });

    test('05:00 noch', () {
      expect(r052().eval(contextAt(5)), isTrue);
    });

    test('05:01 nicht mehr', () {
      expect(r052().eval(contextAt(5, minute: 1)), isFalse);
    });

    test('mittags nicht', () {
      expect(r052().eval(contextAt(12)), isFalse);
    });
  });

  group('R-052 verlangt zusaetzlich eine niedrige Reserve', () {
    test('49 — Anlass', () {
      expect(r052().eval(contextAt(1, regulation: 49)), isTrue);
    });

    test('50 — kein Anlass', () {
      expect(r052().eval(contextAt(1, regulation: 50)), isFalse);
    });

    test('volle Reserve nachts — kein Anlass', () {
      // Nachts allein ist kein Befund. Sonst spraeche die Regel jede Nacht,
      // in der jemand einfach spaet wach ist — und wuerde weggewischt (R2).
      expect(r052().eval(contextAt(1, regulation: 80)), isFalse);
    });
  });

  group('Was am Geraet davon uebrig bleibt', () {
    /// Der Zeitpunkt zur vollen Stunde — nach Mitternacht am Folgetag,
    /// damit die Nacht zusammenhaengend bleibt.
    DateTime nightAt(int hour) => DateTime(2026, 8, hour >= 22 ? 3 : 4, hour);

    test('vor der Ruhezeit spricht sie', () {
      for (final at in [
        DateTime(2026, 8, 3, 22),
        DateTime(2026, 8, 3, 22, 59),
      ]) {
        expect(
          fireOnce(r052Rule(), ctx: contextAt(at.hour, minute: at.minute), nowLocal: at)
              .fired,
          isTrue,
        );
      }
    });

    test('das ganze Fenster traegt — auch um 01:00', () {
      // Der Fall aus der Begruendung der Regel selbst. Bis zum 06.08.2026
      // konnte er nicht eintreten: `intervene` wurde von der Ruhezeit
      // (23:00–06:30) verworfen, und uebrig blieb die eine Stunde davor.
      for (final hour in [23, 0, 1, 4, 5]) {
        expect(r052().eval(contextAt(hour)), isTrue,
            reason: 'Die Bedingung trifft um $hour:00 zu');
        expect(
          fireOnce(r052Rule(), ctx: contextAt(hour), nowLocal: nightAt(hour))
              .fired,
          isTrue,
          reason: 'Um $hour:00 muss aus dem zutreffenden Anlass auch eine '
              'Wartezeit werden — sonst hat die Regel ihre Nacht nicht',
        );
      }
    });

    test('mit gesenkter Severity schrumpft sie auf eine Stunde zurueck', () {
      // Der Gegenbeweis, damit die Zusage oben nicht als Eigenschaft der
      // Uhrzeit missverstanden wird: Sie haengt allein an der Severity. Wer
      // hierauf zurueckfaellt, hat zwischen 23:00 und 05:00 eine stumme
      // Regel, deren Fenster unveraendert dasteht.
      for (final hour in [23, 1, 5]) {
        final outcome = fireOnce(
          r052Rule(severity: Severity.intervene),
          ctx: contextAt(hour),
          nowLocal: nightAt(hour),
        );
        expect(outcome.fired, isFalse);
        expect(outcome.reason, SkipReason.quietHours);
      }
    });

    test('verbindlich heisst nicht unbegrenzt', () {
      // `enforce` umgeht Ruhezeit, Tages- und Stundendeckel. Was bleibt,
      // ist der eigene Cooldown der Regel — zweimal je Nacht. Das ist die
      // Grenze, die hier wirklich zaehlt (R2).
      final outcome = fireOnce(
        r052Rule(),
        ctx: contextAt(1),
        nowLocal: nightAt(1),
        history: FakeHistory(today: const {'R-052': 2}, total: 12),
      );
      expect(outcome.fired, isFalse);
      expect(outcome.reason, SkipReason.dailyLimitReached);
    });
  });
}
