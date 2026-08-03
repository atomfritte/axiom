/// Der Weg einer bearbeiteten Regel: Objekt → YAML → Objekt.
///
/// Der Editor darf keine Einbahnstrasse sein. Was im Geraet entsteht, muss
/// sich unveraendert nach `rules/` zurueckkopieren lassen — sonst hat das
/// Regelwerk zwei Wahrheiten, und G2 haengt daran, dass es eine gibt.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
import 'package:test/test.dart';

Rule sample({
  String id = 'R-900',
  ActionType action = ActionType.notify,
  bool enabled = true,
}) =>
    Rule(
      id: id,
      title: 'Wenn wenig da ist, nichts Grosses vorschlagen',
      rationale: 'Ein Vorschlag ausserhalb der Reichweite erzeugt Schuld '
          'statt Handlung. Schuld senkt die Regulationsreserve und macht '
          'den Start noch unwahrscheinlicher.',
      deficit: 'D2',
      when: Condition.fromMap({
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
                'minutes_since': {'event': 'checkin', 'gte': 240}
              },
            ]
          },
        ]
      }),
      then: Action(action, const {'text': 'Kleines zuerst.'}),
      priority: 60,
      severity: Severity.nudge,
      cooldown: const Cooldown(
        minInterval: Duration(minutes: 120),
        maxPerDay: 2,
      ),
      enabled: enabled,
      titleTranslations: const {'en': 'Suggest nothing out of reach'},
      rationaleTranslations: const {'en': 'A suggestion out of reach '
          'produces guilt instead of action.'},
    );

Rule reparse(String yaml) {
  final result = YamlRuleSource({'overrides.yaml': yaml}).parse();
  expect(result.issues, isEmpty, reason: result.issues.join('\n'));
  return result.rules.single;
}

void main() {
  group('YAML-Ausgabe laesst sich wieder einlesen', () {
    test('alle Felder ueberleben den Weg', () {
      final original = sample();
      final again = reparse(ruleToYaml(original));

      expect(again.id, original.id);
      expect(again.title, original.title);
      expect(again.rationale, original.rationale);
      expect(again.deficit, original.deficit);
      expect(again.priority, original.priority);
      expect(again.severity, original.severity);
      expect(again.enabled, original.enabled);
      expect(again.then.type, original.then.type);
      expect(again.then.params['text'], 'Kleines zuerst.');
      expect(again.cooldown.minInterval, const Duration(minutes: 120));
      expect(again.cooldown.maxPerDay, 2);
    });

    test('auch der Bedingungsbaum, bis in die Verschachtelung', () {
      final original = sample();
      expect(reparse(ruleToYaml(original)).when.toMap(), original.when.toMap());
    });

    test('auch die Uebersetzungen', () {
      final again = reparse(ruleToYaml(sample()));
      expect(again.titleFor('en'), 'Suggest nothing out of reach');
      expect(again.rationaleFor('en'), contains('guilt instead of action'));
    });

    test('zweimal serialisieren ergibt denselben Text', () {
      // Sonst zeigt ein Diff im Regelwerk Aenderungen, die keine sind.
      final once = ruleToYaml(sample());
      expect(ruleToYaml(reparse(once)), once);
    });
  });

  group('Overlay', () {
    late SqliteEventStore store;
    setUp(() => store = SqliteEventStore.open(':memory:',
        clock: const SystemClock()));
    tearDown(() => store.close());

    test('gleiche ID ersetzt die mitgelieferte Regel', () {
      const shipped = '''
- id: R-900
  title: "Original"
  deficit: D1
  rationale: >
    Der mitgelieferte Text, lang genug fuer den Validator und alle
    weiteren Pruefungen.
  when:
    capacity: { lt: 10 }
  then:
    action: notify
  priority: 10
  severity: info
  cooldown: { minutes: 60 }
''';
      store.saveRuleOverride(
        id: 'R-900',
        yaml: ruleToYaml(sample()),
        overridesShipped: true,
        updatedAt: DateTime(2026, 8, 3),
      );

      final merged = YamlRuleSource({
        'core.yaml': shipped,
        'overrides.yaml': store.overrideDocument(DateTime(2026, 8, 3)),
      }).parse();

      expect(merged.rules, hasLength(1));
      expect(merged.rules.single.priority, 60, reason: 'Overlay gewinnt');
    });

    test('neue ID kommt additiv dazu', () {
      store.saveRuleOverride(
        id: 'R-901',
        yaml: ruleToYaml(sample(id: 'R-901')),
        overridesShipped: false,
        updatedAt: DateTime(2026, 8, 3),
      );
      final merged = YamlRuleSource({
        'overrides.yaml': store.overrideDocument(DateTime(2026, 8, 3)),
      }).parse();
      expect(merged.rules.map((r) => r.id), ['R-901']);
    });

    test('waehrend der Schattenzeit spricht die Regel nicht', () {
      final now = DateTime(2026, 8, 3);
      store.saveRuleOverride(
        id: 'R-902',
        yaml: ruleToYaml(sample(id: 'R-902')),
        overridesShipped: false,
        updatedAt: now,
        shadowUntil: now.add(kShadowPeriod),
      );

      final shadowed = YamlRuleSource({
        'overrides.yaml': store.overrideDocument(now),
      }).parse().rules.single;
      expect(shadowed.isShadow, isTrue,
          reason: 'Eine neue Regel wird an dem Tag beurteilt, an dem man sie '
              'geschrieben hat — und an dem haelt man sie fuer richtig.');

      final later = now.add(const Duration(days: 8));
      final live = YamlRuleSource({
        'overrides.yaml': store.overrideDocument(later),
      }).parse().rules.single;
      expect(live.isShadow, isFalse);
      expect(live.then.type, ActionType.notify,
          reason: 'nach Ablauf gilt wieder, was gespeichert wurde');
    });

    test('Loeschen stellt die mitgelieferte Fassung wieder her', () {
      store.saveRuleOverride(
        id: 'R-900',
        yaml: ruleToYaml(sample()),
        overridesShipped: true,
        updatedAt: DateTime(2026, 8, 3),
      );
      expect(store.ruleOverrides(), hasLength(1));
      store.deleteRuleOverride('R-900');
      expect(store.ruleOverrides(), isEmpty);
      expect(store.overrideDocument(DateTime(2026, 8, 3)), isEmpty);
    });
  });
}
