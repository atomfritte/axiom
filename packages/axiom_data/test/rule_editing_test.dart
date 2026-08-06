/// Der Weg einer bearbeiteten Regel: Objekt → YAML → Objekt.
///
/// Der Editor darf keine Einbahnstrasse sein. Was im Geraet entsteht, muss
/// sich unveraendert nach `rules/` zurueckkopieren lassen — sonst hat das
/// Regelwerk zwei Wahrheiten, und G2 haengt daran, dass es eine gibt.
library;

import 'dart:io';

import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
import 'package:test/test.dart';

/// Das echte ausgelieferte Regelwerk — kein Mock.
/// Der Round-Trip wird an ihm gemessen, nicht an einem Wunschbeispiel.
Map<String, String> shippedRules() {
  final dir = Directory('../../rules/core');
  if (!dir.existsSync()) return {};
  return {
    for (final file in dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.yaml')))
      file.path.split('/').last: file.readAsStringSync(),
  };
}

Rule sample({
  String id = 'R-900',
  ActionType action = ActionType.notify,
  bool enabled = true,
  Map<String, Object?> params = const {'text': 'Kleines zuerst.'},
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
      then: Action(action, params),
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

    test('Listen und Maps in params behalten ihren Typ', () {
      // Eine Liste, die als Zeichenkette zurueckkommt, parst fehlerfrei und
      // ist trotzdem kaputt — genau die stumme Sorte Verlust, die der
      // Round-Trip ausschliessen soll.
      final original = sample(
        action: ActionType.suggestSlot,
        params: const {
          'pool': ['sport', 'kaelte', 'musik_laut'],
          'duration_min': 30,
          'grenze': {'lt': 3},
        },
      );
      final params = reparse(ruleToYaml(original)).then.params;

      expect(params['pool'], isA<List<Object?>>());
      expect(params['pool'], ['sport', 'kaelte', 'musik_laut']);
      expect(params['duration_min'], 30);
      expect(params['grenze'], {'lt': 3});
    });
  });

  group('Round-Trip mit dem ausgelieferten Regelwerk', () {
    test('kein Parameter wechselt dabei seinen Typ', () {
      final sources = shippedRules();
      if (sources.isEmpty) {
        markTestSkipped('rules/core nicht gefunden');
        return;
      }
      final rules = YamlRuleSource(sources).parse().rules;
      expect(rules, isNotEmpty);

      for (final rule in rules) {
        final again = reparse(ruleToYaml(rule));
        // Map-Gleichheit prueft tief und typgenau: "[a, b]" ist nicht [a, b].
        expect(again.then.params, rule.then.params, reason: rule.id);
        expect(again.when.toMap(), rule.when.toMap(), reason: rule.id);
        // Getrimmt verglichen: `_folded` schreibt bewusst `>-` und laesst den
        // Zeilenumbruch weg, den `>` im Regelwerk anhaengt. Der Text selbst
        // muss stimmen, der Umbruch dahinter ist keiner.
        expect(again.rationale.trim(), rule.rationale.trim(), reason: rule.id);
        expect(again.severity, rule.severity, reason: rule.id);
      }
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

    // Die Schattenzeit ist das einzige Versprechen, das der Editor dem
    // Nutzer gibt ("laeuft zuerst sieben Tage stumm mit"). Sie darf an
    // keiner Schreibweise haengen — deshalb hier die Formen, die ein
    // handgeschriebener Regeltext annimmt.
    test('auch im Flow-Stil spricht die Regel im Schatten nicht', () {
      final now = DateTime(2026, 8, 3);
      store.saveRuleOverride(
        id: 'R-902',
        yaml: '''
- id: R-902
  title: "Von Hand im Rohtext geschrieben"
  deficit: D2
  rationale: >-
    Flow-Stil ist im Regelwerk ueblich, und der Rohtext-Modus des
    Expertenmodus laesst ihn durch — er darf keine Abkuerzung sein.
  when: { capacity: { lt: 100 } }
  then: { action: notify, params: { text: "jetzt" } }
  priority: 60
  severity: intervene
  cooldown: { minutes: 60 }
''',
        overridesShipped: false,
        updatedAt: now,
        shadowUntil: now.add(kShadowPeriod),
      );

      final shadowed = YamlRuleSource({
        'overrides.yaml': store.overrideDocument(now),
      }).parse().rules.single;
      expect(shadowed.isShadow, isTrue,
          reason: 'Der Expertenmodus sagt sieben stumme Tage zu.');

      final live = YamlRuleSource({
        'overrides.yaml': store.overrideDocument(now.add(const Duration(days: 8))),
      }).parse().rules.single;
      expect(live.then.type, ActionType.notify);
      expect(live.then.params['text'], 'jetzt',
          reason: 'nach Ablauf gilt wieder, was gespeichert wurde');
    });

    test('eine Begruendung, die wie eine Aktion aussieht, bleibt unangetastet',
        () {
      final now = DateTime(2026, 8, 3);
      store.saveRuleOverride(
        id: 'R-903',
        yaml: '''
- id: R-903
  title: "Begruendung mit Doppelpunkt"
  deficit: D2
  rationale: |
    Warum diese Regel spricht:
    action: notify passt hier, weil der Abend sonst kippt und das
    Nachdenken dann teuer wird.
  when: { capacity: { lt: 100 } }
  then:
    action: notify
  priority: 60
  severity: intervene
  cooldown: { minutes: 60 }
''',
        overridesShipped: false,
        updatedAt: now,
        shadowUntil: now.add(kShadowPeriod),
      );

      final shadowed = YamlRuleSource({
        'overrides.yaml': store.overrideDocument(now),
      }).parse().rules.single;
      expect(shadowed.isShadow, isTrue);
      expect(shadowed.rationale, contains('passt hier'),
          reason: 'Die Begruendung ist Nutzertext (G2) und keine Aktion.');
    });

    test('ein zweiter Eintrag mit derselben ID hebt den Schatten nicht auf', () {
      final now = DateTime(2026, 8, 3);
      store.saveRuleOverride(
        id: 'R-904',
        yaml: '''
- id: R-904
  title: "Der Koeder"
  deficit: D2
  rationale: >-
    Erster Eintrag, stumm — damit die Vorschau nichts zu beanstanden hat
    und die Waechterpruefung genau eine Regel zaehlt.
  when: { capacity: { lt: 100 } }
  then:
    action: log_only
  priority: 10
  severity: nudge
  cooldown: { minutes: 120 }
- id: R-904
  title: "Die zweite Fassung"
  deficit: D2
  rationale: >-
    Zweiter Eintrag mit derselben ID — er darf die erste nicht stumm
    verdraengen und schon gar nicht den Schatten aushebeln.
  when: { capacity: { lt: 100 } }
  then:
    action: notify
  priority: 90
  severity: intervene
  cooldown: { minutes: 1 }
''',
        overridesShipped: false,
        updatedAt: now,
        shadowUntil: now.add(kShadowPeriod),
      );

      final loaded = YamlRuleSource({
        'overrides.yaml': store.overrideDocument(now),
      }).parse().rules.single;
      expect(loaded.isShadow, isTrue);
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
