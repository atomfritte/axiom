/// R-130 — „Seit einem Tag ist keine Entscheidung beantwortet".
///
/// Die Rueckmeldung unter einer Entscheidung ist die einzige Stelle, an der
/// das Regelwerk erfaehrt, ob es richtig lag: Der exponentielle Backoff
/// haengt an abgelehnten Entscheidungen, und das Wochenreview sieht sonst
/// nur Feuerraten. Was nicht sichtbar zurueckkommt, existiert nicht [D9].
///
/// **Warum die Regel heute anders heisst.** Sie hiess „Termine eintragen"
/// und ihre Begruendung handelte von gepflegten Zeitankern — gemessen hat
/// die Bedingung davon nie etwas. Sie liest vier Dinge: Uhrzeit, Wochentag,
/// ob heute etwas erfasst wurde, und wie lange keine Entscheidung mehr
/// beantwortet wurde. Keine dieser Variablen kennt Anker, und im
/// Regelwortschatz gibt es dafuer auch keine — Anker liegen in einer eigenen
/// Tabelle, nicht im Ereignisstrom. Von den zwei moeglichen Aufloesungen war
/// nur eine ohne neue Variable erreichbar: den Text an die Bedingung
/// bringen. Der Test unten haelt fest, dass die Bedingung seither das misst,
/// was ueber ihr steht.
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
          'weekday': {'ne': 'sun'},
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

  group('R-130 nimmt beide freien Tage aus', () {
    test('Montag: ja', () {
      expect(r130().eval(contextOn(3)), isTrue);
    });

    test('Freitag: ja', () {
      expect(r130().eval(contextOn(7)), isTrue);
    });

    test('Samstag: nein', () {
      expect(r130().eval(contextOn(8)), isFalse);
    });

    test('Sonntag: nein', () {
      // Vorher stand in der Bedingung nur `ne: sat`, und nirgends stand, ob
      // der Sonntag mitgemeint war. Das Fenster 08:00–09:30 ist ein
      // Werktagsmorgen; an einem freien Morgen um acht ist eine offene
      // Rueckmeldung kein Befund.
      expect(r130().eval(contextOn(9)), isFalse);
    });
  });

  group('Was die Bedingung misst', () {
    test('ohne Erfassung heute schweigt sie', () {
      // Gemeldet wird nur bei jemandem, der das System heute schon benutzt
      // hat. Eine fehlende Rueckmeldung bei jemandem, der gar nicht da war,
      // ist kein Befund, sondern ein freier Tag.
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

    test('sie misst genau das, was ueber ihr steht', () {
      // Der Kern der Korrektur in einer Zeile: Der Titel spricht von einer
      // ausbleibenden Rueckmeldung, und `event:decision_feedback` ist die
      // Variable, die das traegt. Solange diese Menge so aussieht, decken
      // sich Text und Bedingung.
      expect(
        r130().referencedVariables,
        {'time_between', 'weekday', 'event:capture', 'event:decision_feedback'},
      );
    });

    test('der Regelwortschatz hat weiterhin keine Zahl fuer Anker', () {
      // Die urspruengliche Absicht („es sind keine Anker gepflegt") ist
      // damit nicht erledigt, sondern offen: Sie laesst sich gar nicht
      // formulieren. Waechter — sobald jemand eine solche Zahl ergaenzt,
      // faellt dieser Test um, und dann gehoert die Absicht als eigene
      // Regel mit eigener ID zurueck.
      final anchorish = [
        for (final v in RuleVocabulary.numerics) v.id,
        for (final v in RuleVocabulary.symbolics) v.id,
        for (final e in RuleVocabulary.events) e.id,
      ].where((id) => id.contains('anchor') || id.contains('appointment'));
      expect(anchorish, isEmpty,
          reason: 'Es gibt jetzt eine Ankervariable — R-130 hat sie nicht '
              'gebraucht, aber die Regel, die sie ersetzen sollte, schon');
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
