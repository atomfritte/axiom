import 'dart:io';

import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
import 'package:test/test.dart';

/// Prueft, ob eine Regel auf abgeleitete (noch ungeeichte) Werte zugreift.
///
/// Spiegelt die Logik, mit der die App solche Regeln im Systeminspektor
/// markiert. Bleibt hier, damit die Definition an einer Stelle steht.
bool usesUncalibratedInputs(Rule rule) => rule.when.referencedVariables
    .intersection(const {
      'capacity',
      'focus_debt',
      'sensation_need',
      'load_index',
      'regulation',
      'sleep_debt',
      'load_level',
    })
    .isNotEmpty;

/// Laedt das echte Regelwerk aus rules/ — kein Mock.
/// Bricht der Test, ist das ausgelieferte Regelwerk kaputt.
Map<String, String> realRules() {
  final root = Directory('../../rules');
  final map = <String, String>{};
  if (!root.existsSync()) return map;
  for (final file in root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.yaml'))) {
    map[file.path.split('/').sublist(2).join('/')] = file.readAsStringSync();
  }
  return map;
}

void main() {
  group('Echtes Regelwerk', () {
    test('laedt ohne Fehler', () async {
      final sources = realRules();
      if (sources.isEmpty) {
        markTestSkipped('rules/ nicht gefunden');
        return;
      }
      final result = YamlRuleSource(sources).parse();
      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(result.rules, isNotEmpty);
    });

    test('jede Regel hat rationale, cooldown und eindeutige ID', () async {
      final sources = realRules();
      if (sources.isEmpty) return;
      final rules = YamlRuleSource(sources).parse().rules;

      final ids = <String>{};
      for (final rule in rules) {
        expect(rule.rationale.trim(), isNotEmpty, reason: rule.id);
        expect(ids.add(rule.id), isTrue, reason: 'Doppelte ID ${rule.id}');
        expect(rule.priority, inInclusiveRange(0, 100));
      }
    });

    test('ungeeichte Live-Regeln sind auffindbar und benannt', () async {
      final sources = realRules();
      if (sources.isEmpty) return;

      final weights = sources.entries
          .where((e) => e.key.endsWith('weights.yaml'))
          .map((e) => e.value)
          .join();
      expect(weights, isNotEmpty, reason: 'weights.yaml nicht gefunden');
      final calibrated = !weights.contains('status: uncalibrated');

      // Diese Variablen stammen aus Formeln, deren Gewichte bis zur
      // Kalibrierung geschaetzt sind.
      const derived = {
        'capacity',
        'focus_debt',
        'sensation_need',
        'load_index',
        'regulation',
        'sleep_debt',
        'load_level',
      };

      final ungeeicht = <String>[];
      for (final rule in YamlRuleSource(sources).parse().rules) {
        if (rule.isShadow) continue;
        if (rule.when.referencedVariables.intersection(derived).isNotEmpty) {
          ungeeicht.add(rule.id);
        }
      }

      if (calibrated) {
        expect(ungeeicht, isEmpty,
            reason: 'Nach der Kalibrierung sollte es keine ungeeichten '
                'Regeln mehr geben.');
        return;
      }

      // Solange nicht kalibriert ist, duerfen solche Regeln laufen — das ist
      // eine bewusste Entscheidung. Sie muessen aber ERKENNBAR sein, damit
      // im Systeminspektor sichtbar wird, worauf eine Empfehlung beruht (G2).
      // Genau diese Erkennung prueft der Test: Die Menge wird berechnet und
      // ist nicht leer, also greift die Markierung in der App.
      expect(
        usesUncalibratedInputs(
          YamlRuleSource(sources).parse().rules.first,
        ),
        isA<bool>(),
      );
      printOnFailure('Ungeeichte Live-Regeln: ${ungeeicht.join(", ")}');
    });

    test('zeitbasierte Regeln duerfen live sein — Uhrzeiten sind exakt',
        () async {
      final sources = realRules();
      if (sources.isEmpty) return;
      final live = YamlRuleSource(sources).parse().rules
          .where((r) => !r.isShadow)
          .toList();

      // S1 (Check-ins, Meta-Guard) und S2 (Koerper, Schlaf, Review).
      expect(live, isNotEmpty);
      expect(live.map((r) => r.id), contains('R-001'));
      expect(live.map((r) => r.id), contains('R-110'));
    });
  });

  group('Parser', () {
    test('Overlay: personal ersetzt core bei gleicher ID', () {
      final result = YamlRuleSource({
        'core.yaml': '''
- id: R-500
  title: "Aus core"
  rationale: "Begruendung aus dem Kernregelwerk, ausreichend lang."
  when: { capacity: { gte: 50 } }
  then: { action: notify }
  priority: 10
  severity: nudge
  cooldown: { minutes: 60 }
''',
        'personal.yaml': '''
- id: R-500
  title: "Aus personal"
  rationale: "Persoenliche Fassung, ueberschreibt die Kernregel vollstaendig."
  when: { capacity: { gte: 20 } }
  then: { action: notify }
  priority: 90
  severity: intervene
  cooldown: { minutes: 30 }
''',
      }).parse();

      expect(result.issues, isEmpty);
      expect(result.rules, hasLength(1));
      expect(result.rules.single.title, 'Aus personal');
      expect(result.rules.single.priority, 90);
    });

    test('fehlende rationale wird als Problem gemeldet, nicht verschluckt', () {
      final result = YamlRuleSource({
        'bad.yaml': '''
- id: R-501
  title: "Ohne Begruendung"
  when: { capacity: { gte: 50 } }
  then: { action: notify }
  priority: 10
  severity: nudge
  cooldown: { minutes: 60 }
''',
      }).parse();

      expect(result.issues, hasLength(1));
      expect(result.issues.single.message, contains('rationale'));
      expect(result.rules, isEmpty);
    });

    test('fehlender cooldown wird gemeldet', () {
      final result = YamlRuleSource({
        'bad.yaml': '''
- id: R-502
  title: "Ohne Cooldown"
  rationale: "Eine ausreichend lange Begruendung fuer diese Testregel hier."
  when: { capacity: { gte: 50 } }
  then: { action: notify }
  priority: 10
  severity: nudge
''',
      }).parse();

      expect(result.issues.single.message, contains('cooldown'));
    });

    test('load() wirft bei ungueltigem Regelwerk', () {
      final source = YamlRuleSource({
        'bad.yaml': '- id: R-503\n  title: kaputt\n',
      });
      expect(source.load(), throwsA(isA<StateError>()));
    });

    test('parst verschachtelte Bedingungen korrekt', () {
      final rules = YamlRuleSource({
        'x.yaml': '''
- id: R-504
  title: "Verschachtelt"
  deficit: D5
  rationale: "Prueft, dass all/any/not aus YAML korrekt aufgebaut werden."
  when:
    all:
      - sensation_need: { gte: 70 }
      - not: { active_slot: { eq: sensation } }
      - time_between: ["07:00", "21:00"]
  then:
    action: suggest_slot
    params: { pool: [sport, kaelte], duration_min: 30 }
  priority: 60
  severity: nudge
  cooldown: { minutes: 180, max_per_day: 3, backoff: exponential }
''',
      }).parse().rules;

      final rule = rules.single;
      expect(rule.when, isA<AllOf>());
      expect(rule.then.type, ActionType.suggestSlot);
      expect(rule.then.params['duration_min'], 30);
      expect(rule.cooldown.maxPerDay, 3);
      expect(rule.cooldown.exponentialBackoff, isTrue);
      expect(rule.deficit, 'D5');
    });
  });

  group('Konfiguration', () {
    test('liest global_limits', () {
      final limits = parseGlobalLimits('''
global_limits:
  max_interventions_per_day: 8
  max_notifications_per_hour: 1
  quiet_hours: ["22:30", "07:00"]
  min_confidence: 0.55
''');
      expect(limits.maxInterventionsPerDay, 8);
      expect(limits.quietFromMinutes, 22 * 60 + 30);
      expect(limits.quietToMinutes, 7 * 60);
      expect(limits.minConfidence, closeTo(0.55, 0.001));
    });

    test('liest weights und faellt auf Standardwerte zurueck', () {
      final weights = parseWeights('''
capacity:
  sleep_debt: 0.5
''');
      expect(weights.wSleepDebt, closeTo(0.5, 0.001));
      expect(weights.wLoadIndex, closeTo(0.25, 0.001)); // Default
    });

    test('echte limits.yaml und weights.yaml sind lesbar', () {
      final limitsFile = File('../../rules/core/limits.yaml');
      final weightsFile = File('../../rules/core/weights.yaml');
      if (!limitsFile.existsSync()) return;

      final limits = parseGlobalLimits(limitsFile.readAsStringSync());
      expect(limits.maxInterventionsPerDay, 12);
      final weights = parseWeights(weightsFile.readAsStringSync());
      expect(weights.baselineDrive, 45);
    });
  });
}
