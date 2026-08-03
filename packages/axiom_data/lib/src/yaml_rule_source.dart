/// Laedt das Regelwerk aus YAML.
///
/// Eine ungueltige Regel wird NICHT geladen und der Fehler ist sichtbar —
/// kein stilles Ueberspringen. In einem regelbasierten System ist eine stumm
/// ignorierte Regel schlimmer als ein Absturz.
///
/// Overlay-Semantik: gleiche `id` aus `personal` ersetzt `core` vollstaendig,
/// neue IDs werden additiv geladen.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:yaml/yaml.dart';

final class RuleLoadIssue {
  final String source;
  final String ruleId;
  final String message;
  const RuleLoadIssue(this.source, this.ruleId, this.message);

  @override
  String toString() => '$source [$ruleId]: $message';
}

final class RuleLoadResult {
  final List<Rule> rules;
  final List<RuleLoadIssue> issues;
  const RuleLoadResult(this.rules, this.issues);

  bool get isValid => issues.isEmpty;
}

final class YamlRuleSource implements RuleSource {
  /// YAML-Inhalte, Schluessel ist der Anzeigename (z. B. 'core/limits.yaml').
  /// Die Reihenfolge entscheidet beim Overlay: spaeter gewinnt.
  final Map<String, String> sources;

  const YamlRuleSource(this.sources);

  @override
  Future<List<Rule>> load() async {
    final result = parse();
    if (!result.isValid) {
      throw StateError(
        'Regelwerk ungueltig:\n${result.issues.join("\n")}',
      );
    }
    return result.rules;
  }

  /// Wie [load], aber ohne zu werfen — fuer den Regel-Inspektor in der App.
  RuleLoadResult parse() {
    final byId = <String, Rule>{};
    final issues = <RuleLoadIssue>[];

    for (final entry in sources.entries) {
      final Object? doc;
      try {
        doc = loadYaml(entry.value);
      } on Object catch (e) {
        issues.add(RuleLoadIssue(entry.key, '-', 'YAML nicht lesbar: $e'));
        continue;
      }
      if (doc is! YamlList) continue; // limits.yaml / weights.yaml

      for (final node in doc) {
        if (node is! YamlMap) {
          issues.add(RuleLoadIssue(entry.key, '-', 'Eintrag ist keine Map'));
          continue;
        }
        final id = node['id']?.toString() ?? '<ohne id>';
        try {
          byId[id] = _toRule(node);
        } on ConditionError catch (e) {
          issues.add(RuleLoadIssue(entry.key, id, e.message));
        } on Object catch (e) {
          issues.add(RuleLoadIssue(entry.key, id, '$e'));
        }
      }
    }

    final rules = byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    return RuleLoadResult(rules, issues);
  }

  Rule _toRule(YamlMap node) {
    final when = node['when'];
    if (when is! YamlMap) {
      throw ConditionError('when fehlt oder ist keine Map');
    }
    final then = node['then'];
    if (then is! YamlMap) {
      throw ConditionError('then fehlt oder ist keine Map');
    }
    final cooldown = node['cooldown'];
    if (cooldown is! YamlMap) {
      throw ConditionError(
        'cooldown fehlt. Ohne Cooldown entsteht Benachrichtigungsflut.',
      );
    }
    final minutes = cooldown['minutes'];
    if (minutes is! int) {
      throw ConditionError('cooldown.minutes muss eine ganze Zahl sein');
    }

    return Rule(
      id: node['id']?.toString() ?? '',
      title: node['title']?.toString() ?? '',
      rationale: node['rationale']?.toString() ?? '',
      deficit: node['deficit']?.toString(),
      when: Condition.fromMap(toPlainMap(when)),
      then: Action(
        ActionType.parse(then['action']?.toString() ?? ''),
        then['params'] is YamlMap
            ? toPlainMap(then['params'] as YamlMap).cast<String, Object?>()
            : const {},
      ),
      priority: node['priority'] is int ? node['priority'] as int : 50,
      severity: Severity.parse(node['severity']?.toString() ?? 'nudge'),
      cooldown: Cooldown(
        minInterval: Duration(minutes: minutes),
        maxPerDay: cooldown['max_per_day'] is int
            ? cooldown['max_per_day'] as int
            : null,
        exponentialBackoff: cooldown['backoff']?.toString() == 'exponential',
      ),
      enabled: node['enabled'] is bool ? node['enabled'] as bool : true,
      titleTranslations: _translations(node, 'title'),
      rationaleTranslations: _translations(node, 'rationale'),
    );
  }

  /// Uebersetzungen aus `title_en`, `rationale_en` und so weiter.
  ///
  /// Deutsch steht ohne Suffix da und ist die Quelle. Ein Suffix wird als
  /// Sprachcode gelesen, ohne Liste erlaubter Sprachen — eine weitere Sprache
  /// soll nichts als eine YAML-Zeile kosten.
  static Map<String, String> _translations(YamlMap node, String field) {
    final result = <String, String>{};
    for (final entry in node.entries) {
      final key = entry.key.toString();
      if (!key.startsWith('${field}_')) continue;
      final code = key.substring(field.length + 1);
      final value = entry.value?.toString().trim() ?? '';
      if (code.isEmpty || value.isEmpty) continue;
      result[code] = value;
    }
    return result;
  }
}

/// Liest `global_limits` aus limits.yaml.
GlobalLimits parseGlobalLimits(String yamlText) {
  final doc = loadYaml(yamlText);
  if (doc is! YamlMap) return const GlobalLimits();
  final limits = doc['global_limits'];
  if (limits is! YamlMap) return const GlobalLimits();

  final quiet = limits['quiet_hours'];
  var quietFrom = 23 * 60;
  var quietTo = 6 * 60 + 30;
  if (quiet is YamlList && quiet.length == 2) {
    quietFrom = _hhmm(quiet[0].toString()) ?? quietFrom;
    quietTo = _hhmm(quiet[1].toString()) ?? quietTo;
  }

  return GlobalLimits(
    maxInterventionsPerDay:
        limits['max_interventions_per_day'] as int? ?? 12,
    maxNotificationsPerHour:
        limits['max_notifications_per_hour'] as int? ?? 2,
    quietFromMinutes: quietFrom,
    quietToMinutes: quietTo,
    minConfidence: (limits['min_confidence'] as num?)?.toDouble() ?? 0.4,
  );
}

/// Liest die Formelgewichte aus weights.yaml.
Weights parseWeights(String yamlText) {
  final doc = loadYaml(yamlText);
  if (doc is! YamlMap) return const Weights();
  double read(String section, String key, double fallback) {
    final s = doc[section];
    if (s is! YamlMap) return fallback;
    return (s[key] as num?)?.toDouble() ?? fallback;
  }

  return Weights(
    wSleepDebt: read('capacity', 'sleep_debt', 0.30),
    wLoadIndex: read('capacity', 'load_index', 0.25),
    wFocusDebt: read('capacity', 'focus_debt', 0.20),
    wRegulation: read('capacity', 'regulation', 0.15),
    wCircadian: read('capacity', 'circadian', 0.10),
    baselineDrive: read('sensation_need', 'baseline_drive', 45),
    wLowStimulus: read('sensation_need', 'low_stimulus', 0.40),
    wSlotRelief: read('sensation_need', 'slot_relief', 0.60),
    lSleep: read('load_index', 'sleep_debt', 0.30),
    lRecovery: read('load_index', 'recovery_quality', 0.25),
    lCompensation: read('load_index', 'compensation', 0.20),
    lIrritability: read('load_index', 'irritability', 0.15),
    lWithdrawal: read('load_index', 'social_withdrawal', 0.10),
  );
}

int? _hhmm(String s) {
  final parts = s.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

Map<Object?, Object?> toPlainMap(YamlMap map) => {
      for (final e in map.entries) e.key: _toPlain(e.value),
    };

Object? _toPlain(Object? value) => switch (value) {
      final YamlMap m => toPlainMap(m),
      final YamlList l => l.map(_toPlain).toList(),
      _ => value,
    };
