/// R-111 — „Schlaf eintragen" (M8 Sleep Gate).
///
/// Ohne Schlafdaten fehlt der Kapazitaetsformel ihr staerkster Eingangswert,
/// und der Zustandsvektor raet [D8]. Zwei Uhrzeiten und eine Einschaetzung
/// genuegen.
///
/// Das Fenster beginnt um 07:30 — eine halbe Stunde nach dem Ende der
/// Ruhezeit (06:30). Diese halbe Stunde ist der Grund, warum die Regel
/// ueberhaupt spricht; laege ihr Start davor, waere ihr Anfang stumm, ohne
/// dass die Bedingung sich aendert. Der Test haelt beides fest: das Fenster
/// und dass es tatsaechlich durchkommt.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Der Bedingungsbaum aus rules/core/s2-live.yaml, Wort fuer Wort.
Condition r111() => Condition.fromMap({
      'all': [
        {
          'time_between': ['07:30', '10:00'],
        },
        {
          'count_today': {'event': 'sleep_window', 'lt': 1},
        },
      ],
    });

EvalContext contextAt(
  int hour,
  int minute, {
  int sleepWindowsToday = 0,
}) =>
    StateEvalContext(
      state: stateOf(),
      clock: FakeClock(DateTime(2026, 8, 3, hour, minute)),
      runtime: RuntimeContext(
        countTodayByEvent: {'sleep_window': sleepWindowsToday},
      ),
    );

void main() {
  group('R-111 haelt sein Fenster', () {
    test('07:29 noch nicht', () {
      expect(r111().eval(contextAt(7, 29)), isFalse);
    });

    test('07:30 schon', () {
      expect(r111().eval(contextAt(7, 30)), isTrue);
    });

    test('10:00 noch', () {
      expect(r111().eval(contextAt(10, 0)), isTrue);
    });

    test('10:01 nicht mehr', () {
      // Wer bis zehn Uhr nicht eingetragen hat, traegt heute nicht mehr
      // ein. Eine Erinnerung um vierzehn Uhr bekaeme eine geratene Antwort,
      // und ein geratener Eingangswert ist schlimmer als eine Luecke (R8).
      expect(r111().eval(contextAt(10, 1)), isFalse);
    });

    test('mitten in der Nacht nicht', () {
      expect(r111().eval(contextAt(3, 0)), isFalse);
    });
  });

  group('R-111 fragt genau einmal je Nacht', () {
    test('nichts eingetragen — sie fragt', () {
      expect(r111().eval(contextAt(8, 0)), isTrue);
    });

    test('eine Nacht eingetragen — sie ist still', () {
      expect(
        r111().eval(contextAt(8, 0, sleepWindowsToday: 1)),
        isFalse,
        reason: 'Auch eine aus Health Connect uebernommene Nacht zaehlt — '
            'die Regel unterscheidet die Quelle nicht',
      );
    });

    test('mehrere Eintraege — erst recht still', () {
      expect(r111().eval(contextAt(8, 0, sleepWindowsToday: 3)), isFalse);
    });
  });

  group('R-111 und die Systemgrenzen', () {
    Rule rule() => ruleOf(
          id: 'R-111',
          when: r111(),
          priority: 55,
          cooldown:
              const Cooldown(minInterval: Duration(minutes: 180), maxPerDay: 1),
        );

    test('der Fensteranfang liegt hinter dem Ende der Ruhezeit', () {
      // 07:30 gegen 06:30 — eine Stunde Abstand. Der Test steht hier,
      // damit eine Verschiebung des Fensters nach vorn auffaellt, statt
      // die Regel lautlos verstummen zu lassen.
      final now = DateTime(2026, 8, 3, 7, 30);
      expect(fireOnce(rule(), ctx: contextAt(7, 30), nowLocal: now).fired, isTrue);
    });

    test('sie kollidiert nicht mit dem Morgen-Check-in', () {
      // R-001 fragt zwischen 08:45 und 09:30, R-111 zwischen 07:30 und
      // 10:00 — die Fenster ueberlappen. Der Stundendeckel laesst zwei
      // Meldungen zu, beide kommen also durch; verdraengt wuerde erst eine
      // dritte. Festgehalten, weil ein enger gezogener Deckel genau hier
      // zuerst wehtaete.
      final now = DateTime(2026, 8, 3, 9);
      final result = const RuleEngine().evaluate(
        rules: [
          rule(),
          ruleOf(id: 'R-001', priority: 70),
        ],
        ctx: contextAt(9, 0),
        history: FakeHistory(),
        nowLocal: now,
      );
      expect(result.fired.map((f) => f.rule.id), ['R-001', 'R-111']);
    });
  });
}
