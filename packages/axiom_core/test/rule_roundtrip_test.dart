/// Bedingungen muessen den Weg zurueck finden.
///
/// Der Editor schreibt Regeln in die Datenbank und exportiert sie als YAML —
/// beides geht ueber [Condition.toMap]. Waere die Umkehrung unvollstaendig,
/// waere jede im Editor bearbeitete Regel ein Einbahnweg aus dem
/// versionierten Regelwerk heraus: bearbeitbar, aber nicht mehr in `rules/`
/// zurueckzubringen.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

void main() {
  group('fromMap(toMap()) ergibt dieselbe Bedingung', () {
    final cases = <String, Map<String, Object?>>{
      'numerisch': {
        'capacity': {'gte': 30}
      },
      'symbolisch': {
        'load_level': {'eq': 'L3'}
      },
      'Uhrzeit': {
        'time_between': ['22:00', '05:00']
      },
      'seit Ereignis': {
        'minutes_since': {'event': 'focus_start', 'gte': 90}
      },
      'Anzahl heute': {
        'count_today': {'event': 'checkin', 'lt': 3}
      },
      'verschachtelt': {
        'all': [
          {
            'capacity': {'lt': 40}
          },
          {
            'any': [
              {
                'load_level': {'eq': 'L2'}
              },
              {
                'not': {
                  'active_slot': {'eq': 'focus'}
                }
              },
            ]
          },
        ]
      },
    };

    cases.forEach((name, map) {
      test(name, () {
        final parsed = Condition.fromMap(map);
        final again = Condition.fromMap(parsed.toMap());
        expect(again.toMap(), parsed.toMap());
        expect(again.toString(), parsed.toString());
        expect(again.referencedVariables, parsed.referencedVariables);
      });
    });

    test('die Form bleibt exakt erhalten, nicht nur die Bedeutung', () {
      // Sonst waere ein Export nicht mehr mit dem Original vergleichbar,
      // und ein Diff im Regelwerk zeigte Aenderungen, die keine sind.
      final map = {
        'minutes_since': {'event': 'body_prompt', 'gte': 100}
      };
      expect(Condition.fromMap(map).toMap(), map);
    });
  });

  group('Wortschatz deckt ab, was die Engine kennt', () {
    test('jede numerische Variable ist auswertbar', () {
      // Geprueft wird gegen den Auswertungskontext, nicht gegen den
      // Zustandsvektor allein: Nicht jede Variable misst den Nutzer.
      // `meta_minutes_today` misst die App selbst (G4) und kommt aus dem
      // Laufzeitkontext — im Zustandsvektor waere sie fehl am Platz.
      final ctx = StateEvalContext(
        state: StateVector(
          at: DateTime.utc(2026),
          capacity: 50,
          focusDebt: 10,
          sensationNeed: 40,
          loadIndex: 20,
          regulation: 60,
          sleepDebt: 15,
        ),
        clock: FakeClock(DateTime.utc(2026)),
        runtime: const RuntimeContext(),
      );
      for (final variable in RuleVocabulary.numerics) {
        expect(ctx.numeric(variable.id), isNotNull,
            reason: '${variable.id} steht im Editor, aber die Engine '
                'kennt sie nicht');
      }
    });

    test('jede angebotene Aktion ist ein bekannter Aktionstyp', () {
      for (final action in RuleVocabulary.actions) {
        expect(ActionType.parse(action.type.token), action.type);
      }
    });

    test('jedes angebotene Ereignis ist ein bekannter Event-Typ', () {
      final known = EventType.values.map((e) => _snake(e.name)).toSet();
      for (final event in RuleVocabulary.events) {
        expect(known, contains(event.id),
            reason: '${event.id} steht im Editor, existiert aber nicht');
      }
    });
  });
}

String _snake(String camel) => camel
    .replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m.group(0)!.toLowerCase()}');
