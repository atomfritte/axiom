/// Regel-Validator. Laeuft im CI und beim App-Start.
///
/// Eine ungueltige Regel wird NICHT geladen und die App startet mit einem
/// sichtbaren Fehler — kein stilles Ueberspringen. In einem regelbasierten
/// System ist eine stumm ignorierte Regel schlimmer als ein Absturz: Man
/// verlaesst sich auf etwas, das nicht existiert.
///
///   dart run tools/bin/validate_rules.dart [pfad]
library;

import 'dart:io';

import 'package:axiom_core/axiom_core.dart';
import 'package:yaml/yaml.dart';

final _idPattern = RegExp(r'^R-\d{3}$');

void main(List<String> args) {
  final root = args.isNotEmpty ? args.first : 'rules';
  final dir = Directory(root);
  if (!dir.existsSync()) {
    stderr.writeln('Verzeichnis nicht gefunden: $root');
    exit(2);
  }

  final errors = <String>[];
  final warnings = <String>[];
  final seenIds = <String, String>{};
  var ruleCount = 0;
  var shadowCount = 0;

  final files = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.yaml') || f.path.endsWith('.yml'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final relative = file.path;
    final Object? doc;
    try {
      doc = loadYaml(file.readAsStringSync());
    } on Object catch (e) {
      errors.add('$relative: YAML nicht lesbar — $e');
      continue;
    }

    // Konfigurationsdateien (limits, weights) enthalten keine Regelliste.
    if (doc is! YamlList) continue;

    for (final entry in doc) {
      if (entry is! YamlMap) {
        errors.add('$relative: Regeleintrag ist keine Map');
        continue;
      }
      ruleCount++;
      final id = entry['id']?.toString() ?? '<ohne id>';
      final where = '$relative [$id]';

      // ── id ──
      if (!_idPattern.hasMatch(id)) {
        errors.add('$where: id muss dem Muster R-NNN entsprechen');
      }
      final previous = seenIds[id];
      if (previous != null) {
        errors.add('$where: id bereits vergeben in $previous. '
            'IDs werden nie wiederverwendet.');
      } else {
        seenIds[id] = relative;
      }

      // ── rationale (G2) ──
      final rationale = entry['rationale']?.toString().trim() ?? '';
      if (rationale.isEmpty) {
        errors.add('$where: rationale fehlt. Jede Ausgabe muss '
            'begruendbar sein (G2).');
      } else if (rationale.length < 40) {
        warnings.add('$where: rationale sehr kurz (${rationale.length} Zeichen)');
      }

      // ── Uebersetzungen ──
      //
      // Kein Fehler, sondern eine Warnung: Eine fehlende Uebersetzung zeigt
      // den deutschen Satz — sichtbar unfertig. Eine deshalb nicht geladene
      // Regel waere schlimmer, weil man sich auf etwas verlaesst, das
      // stumm fehlt.
      for (final field in ['title', 'rationale']) {
        final hasTranslation = entry.keys
            .map((k) => k.toString())
            .any((k) => k.startsWith('${field}_'));
        if (!hasTranslation) {
          warnings.add('$where: keine Uebersetzung fuer $field. In der '
              'englischen Oberflaeche erscheint der deutsche Text.');
        }
      }

      // ── deficit ──
      final deficit = entry['deficit']?.toString();
      if (deficit == null) {
        warnings.add('$where: kein deficit-Bezug. Regeln ohne Bezug zu '
            'D1-D12 sind verdaechtig.');
      } else if (!RegExp(r'^D([1-9]|1[0-3])$').hasMatch(deficit)) {
        errors.add('$where: unbekanntes deficit "$deficit"');
      }

      // ── cooldown (R2) ──
      final cooldown = entry['cooldown'];
      if (cooldown is! YamlMap) {
        errors.add('$where: cooldown fehlt. Ohne Cooldown entsteht '
            'Benachrichtigungsflut (R2).');
      } else if (cooldown['minutes'] is! int) {
        errors.add('$where: cooldown.minutes muss eine ganze Zahl sein');
      }

      // ── priority ──
      final priority = entry['priority'];
      if (priority is! int || priority < 0 || priority > 100) {
        errors.add('$where: priority muss eine ganze Zahl 0..100 sein');
      }

      // ── severity ──
      final severity = entry['severity']?.toString() ?? '';
      try {
        final parsed = Severity.parse(severity);
        if (parsed == Severity.enforce) {
          warnings.add('$where: severity=enforce. Nur zulaessig, wenn der '
              'Nutzer diese Regel im ruhigen Zustand selbst autorisiert hat.');
        }
      } on Object {
        errors.add('$where: unbekannte severity "$severity"');
      }

      // ── action ──
      final then = entry['then'];
      if (then is! YamlMap) {
        errors.add('$where: then fehlt');
      } else {
        final action = then['action']?.toString() ?? '';
        try {
          if (ActionType.parse(action) == ActionType.logOnly) shadowCount++;
        } on Object {
          errors.add('$where: unbekannte Aktion "$action"');
        }
      }

      // ── when: Bedingungsbaum parsen ──
      final when = entry['when'];
      if (when is! YamlMap) {
        errors.add('$where: when fehlt oder ist keine Map');
      } else {
        try {
          final condition = Condition.fromMap(_toPlainMap(when));
          final unknown = _unknownVariables(condition.referencedVariables);
          if (unknown.isNotEmpty) {
            errors.add('$where: unbekannte Variablen: ${unknown.join(", ")}');
          }
        } on ConditionError catch (e) {
          errors.add('$where: ${e.message}');
        }
      }
    }
  }

  // ── Ausgabe ──
  for (final w in warnings) {
    stdout.writeln('WARN   $w');
  }
  for (final e in errors) {
    stdout.writeln('FEHLER $e');
  }

  stdout.writeln('');
  stdout.writeln('$ruleCount Regeln geprueft in ${files.length} Dateien '
      '($shadowCount im SHADOW-Modus)');
  stdout.writeln('${errors.length} Fehler, ${warnings.length} Warnungen');

  if (errors.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('Regelwerk ungueltig — wird nicht geladen.');
    exit(1);
  }
  stdout.writeln('Regelwerk gueltig.');
}

/// Bekannte Variablen der Regel-DSL. Siehe docs/04-REGELWERK.md §2.
const _knownVariables = {
  'capacity',
  'focus_debt',
  'sensation_need',
  'load_index',
  'regulation',
  'sleep_debt',
  'load_level',
  'active_slot',
  'weekday',
  'time_between',
};

List<String> _unknownVariables(Set<String> referenced) => referenced
    .where((v) => !v.startsWith('event:') && !_knownVariables.contains(v))
    .toList()
  ..sort();

Map<Object?, Object?> _toPlainMap(YamlMap map) => {
      for (final entry in map.entries) entry.key: _toPlain(entry.value),
    };

Object? _toPlain(Object? value) => switch (value) {
      final YamlMap m => _toPlainMap(m),
      final YamlList l => l.map(_toPlain).toList(),
      _ => value,
    };
