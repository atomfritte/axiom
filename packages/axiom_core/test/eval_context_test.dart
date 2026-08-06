/// Der Auswertungskontext — die Stelle, an der aus einem Variablennamen ein
/// Wert wird.
///
/// Dazu gab es bisher keine eigene Datei. Dabei entscheidet genau hier, ob
/// eine Regel ueberhaupt auswertbar ist: Loest ein Name nicht auf, bricht die
/// Auswertung ab (Fail-Fast), und loest er auf den falschen Wert auf, feuert
/// die Regel zur falschen Zeit — beides ohne Fehlermeldung im zweiten Fall.
///
/// Zweiter Zweck: Der Wortschatz (`RuleVocabulary`) und dieser Kontext sind
/// zwei Listen derselben Sache. Der Kommentar im Wortschatz sagt zu, dass sie
/// dieselbe ist. Diese Datei haelt das fest, statt es zu hoffen.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

StateEvalContext _ctx({
  StateVector? state,
  DateTime? now,
  RuntimeContext runtime = const RuntimeContext(),
}) =>
    StateEvalContext(
      state: state ?? stateOf(),
      clock: FakeClock(now ?? testNoon),
      runtime: runtime,
    );

void main() {
  group('Wortschatz und Auswerter sind dieselbe Liste', () {
    final ctx = _ctx();

    test('jede angebotene Zahl loest auf', () {
      for (final variable in RuleVocabulary.numerics) {
        expect(ctx.numeric(variable.id), isNotNull,
            reason: '${variable.id} steht im Editor, die Engine kennt sie '
                'nicht — die Regel wuerde beim Auswerten abbrechen');
      }
    });

    test('jede angebotene Auswahlvariable loest auf', () {
      // Diese Richtung fehlte bisher ganz. Eine im Editor angebotene
      // symbolische Variable ohne Anschluss im Kontext waere eine Regel, die
      // sich anlegen laesst und beim ersten Auswerten wirft.
      for (final variable in RuleVocabulary.symbolics) {
        expect(ctx.symbolic(variable.id), isNotNull,
            reason: '${variable.id} steht im Editor, die Engine kennt sie '
                'nicht');
      }
    });

    test('die Engine kennt keine Variable, die der Editor nicht anbietet', () {
      // Die Gegenrichtung. Sie laesst sich nicht aufzaehlen — ein `switch`
      // hat keine Schluesselliste —, deshalb steht sie hier als
      // Namensliste. Faellt der Test um, ist entweder eine Variable
      // dazugekommen, die im Editor fehlt, oder eine ist verschwunden.
      const bekannt = {
        'capacity',
        'focus_debt',
        'sensation_need',
        'load_index',
        'regulation',
        'sleep_debt',
        'meta_minutes_today',
        'inbox_count',
        'inbox_oldest_hours',
        'hours_to_deadline',
        'deadline_slack_hours',
      };
      expect(
        RuleVocabulary.numerics.map((v) => v.id).toSet(),
        bekannt,
      );
      for (final name in bekannt) {
        expect(ctx.numeric(name), isNotNull, reason: name);
      }
      expect(
        RuleVocabulary.symbolics.map((v) => v.id).toSet(),
        {'load_level', 'active_slot', 'place', 'weekday'},
      );
    });

    test('die angebotenen Werte einer Auswahlvariablen kommen auch vor', () {
      // `load_level` wird als L0..L3 geliefert; der Editor bietet genau das
      // an. Waere die Schreibweise verschieden, traefe kein `eq` je zu.
      final werte = RuleVocabulary.symbolic('load_level')!.values.keys.toSet();
      final geliefert = <String>{
        for (final loadIndex in [10, 60, 75, 90])
          _ctx(state: stateOf(loadIndex: loadIndex)).symbolic('load_level')!,
      };
      expect(geliefert, werte);
    });

    test('die angebotenen Wochentage kommen auch vor', () {
      final werte = RuleVocabulary.symbolic('weekday')!.values.keys.toSet();
      final geliefert = <String>{
        for (var tag = 3; tag <= 9; tag++)
          _ctx(now: DateTime(2026, 8, tag)).symbolic('weekday')!,
      };
      expect(geliefert, werte);
    });

    test('ein unbekannter Name loest nicht auf — Fail-Fast statt still false',
        () {
      expect(ctx.numeric('gibt_es_nicht'), isNull);
      expect(ctx.symbolic('gibt_es_nicht'), isNull);
    });
  });

  group('Wochentag', () {
    test('der 3. August 2026 ist ein Montag und heisst mon', () {
      const namen = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
      for (var i = 0; i < 7; i++) {
        expect(
          _ctx(now: DateTime(2026, 8, 3 + i)).symbolic('weekday'),
          namen[i],
          reason: '3. August + $i Tage',
        );
      }
    });

    test('der Wochentag kommt aus der Ortszeit, nicht aus UTC', () {
      // Regeln denken in Ortszeit. Waere hier `nowUtc` angezapft, wechselte
      // eine Wochenend-Regel je nach Zeitzone am falschen Abend.
      final clock = FakeClock(DateTime(2026, 8, 9, 23, 30)); // Sonntag
      final ctx = StateEvalContext(state: stateOf(), clock: clock);
      expect(ctx.symbolic('weekday'), 'sun');
      expect(ctx.localNow, clock.nowLocal());
    });
  });

  group('Ort — ein Wert statt null', () {
    test('ohne gesetzten Ort steht „none", nicht nichts', () {
      // Eine unaufloesbare Variable bricht die Auswertung ab. „Gerade kein
      // Ort" ist aber der Normalfall, kein Fehler [D2].
      expect(_ctx().symbolic('place'), kNoPlace);
    });

    test('nur Leerzeichen zaehlen wie kein Ort', () {
      expect(
        _ctx(runtime: const RuntimeContext(place: '   ')).symbolic('place'),
        kNoPlace,
      );
    });

    test('Randleerzeichen werden abgeschnitten', () {
      expect(
        _ctx(runtime: const RuntimeContext(place: '  Büro ')).symbolic('place'),
        'Büro',
      );
    });

    test('eine Regel auf den Ort vergleicht ohne Ruecksicht auf die '
        'Schreibweise', () {
      final c = Condition.fromMap({
        'place': {'eq': 'baumarkt'}
      });
      expect(
        c.eval(_ctx(runtime: const RuntimeContext(place: 'Baumarkt'))),
        isTrue,
      );
      expect(c.eval(_ctx()), isFalse);
    });
  });

  group('Voreinstellungen des Laufzeitkontexts', () {
    test('ohne Frist unterschreitet keine Fristregel ihre Schwelle', () {
      // `kNoDeadlineHours` ist so gross gewaehlt, dass keine sinnvolle Regel
      // sie unterschreitet. Waere hier 0 oder null, feuerte jede Fristregel
      // genau dann, wenn es gar keine Frist gibt.
      expect(_ctx().numeric('hours_to_deadline'), kNoDeadlineHours);
      expect(
        Condition.fromMap({
          'hours_to_deadline': {'lte': 168}
        }).eval(_ctx()),
        isFalse,
      );
      expect(
        Condition.fromMap({
          'deadline_slack_hours': {'lt': 0}
        }).eval(_ctx()),
        isFalse,
      );
    });

    test('ein leerer Eingang hat kein Alter, nicht ein unendliches', () {
      // Die Umkehrung der Fristlogik, und mit Absicht: Mit einer grossen
      // Zahl feuerte jede Regel der Form `gte: 72`, wenn der Eingang **leer**
      // ist — genau dann, wenn es nichts zu tun gibt.
      expect(_ctx().numeric('inbox_oldest_hours'), 0);
      expect(
        Condition.fromMap({
          'inbox_oldest_hours': {'gte': 72}
        }).eval(_ctx()),
        isFalse,
      );
    });

    test('ohne Angabe laeuft nichts und nichts wurde heute gezaehlt', () {
      final ctx = _ctx();
      expect(ctx.symbolic('active_slot'), 'none');
      expect(ctx.numeric('meta_minutes_today'), 0);
      expect(ctx.numeric('inbox_count'), 0);
      expect(ctx.countToday('checkin'), 0);
      expect(ctx.minutesSince('checkin'), isNull);
    });

    test('der Laufzeitkontext liegt vor dem Zustandsvektor', () {
      // `meta_minutes_today` misst die App, nicht den Nutzer — sie darf
      // nicht im Vektor landen und muss trotzdem als Bedingung taugen (G4).
      final ctx = _ctx(runtime: const RuntimeContext(metaMinutesToday: 14));
      expect(ctx.numeric('meta_minutes_today'), 14);
      expect(
        Condition.fromMap({
          'meta_minutes_today': {'gte': 12}
        }).eval(ctx),
        isTrue,
      );
    });
  });

  group('Konfidenz wird durchgereicht, nicht neu erfunden', () {
    test('ohne Eintrag gilt volle Konfidenz', () {
      expect(_ctx().confidenceOf('capacity'), 1.0);
    });

    test('ein Eintrag im Vektor kommt unveraendert an', () {
      final ctx = _ctx(
        state: stateOf(confidence: const {'capacity': 0.35}),
      );
      expect(ctx.confidenceOf('capacity'), 0.35);
      expect(ctx.confidenceOf('regulation'), 1.0);
    });
  });

  test('Determinismus: derselbe Kontext antwortet zweimal gleich', () {
    final ctx = _ctx(
      state: stateOf(capacity: 55),
      runtime: const RuntimeContext(
        activeSlot: 'focus',
        place: 'Büro',
        minutesSinceByEvent: {'checkin': 40},
        countTodayByEvent: {'body_prompt': 2},
      ),
    );
    for (final name in ['capacity', 'meta_minutes_today', 'hours_to_deadline']) {
      expect(ctx.numeric(name), ctx.numeric(name), reason: name);
    }
    for (final name in ['load_level', 'active_slot', 'place', 'weekday']) {
      expect(ctx.symbolic(name), ctx.symbolic(name), reason: name);
    }
    expect(ctx.minutesSince('checkin'), 40);
    expect(ctx.countToday('body_prompt'), 2);
  });
}
