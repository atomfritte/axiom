/// Regel-Validator. Laeuft vor jedem Commit und vor jedem Spiegeln ins
/// App-Bundle.
///
/// Hier stand „Laeuft im CI und beim App-Start". Beides trifft nicht zu: Es
/// gibt kein CI, und die App kennt dieses Paket gar nicht. Genau die Sorte
/// Zusage, die dieser Validator verhindern soll.
///
/// Eine ungueltige Regel wird NICHT gespiegelt und nicht geladen — kein
/// stilles Ueberspringen. In einem regelbasierten System ist eine stumm
/// ignorierte Regel schlimmer als ein Absturz: Man verlaesst sich auf etwas,
/// das nicht existiert.
///
///   dart run tools/bin/validate_rules.dart [pfad]
///
/// Die Pruefung selbst ist eine Funktion (`validateRules`), kein `main()`:
/// `sync_rules.dart` ruft sie auf, bevor es eine Regel in die App-Assets
/// spiegelt. Vorher stand dort nur der Satz „Der Validator läuft mit" —
/// aufgerufen wurde er nie, und ein ungueltiges Regelwerk ging ungehindert
/// ins Bundle.
library;

import 'dart:io';

import 'package:axiom_core/axiom_core.dart';
import 'package:yaml/yaml.dart';

final _idPattern = RegExp(r'^R-\d{3}$');

/// Testdateien nach der Namenskonvention `r<nnn>_<name>_test.dart`.
/// `r<nnn>_test.dart` ohne Namensteil zaehlt ebenfalls — der Waechter soll
/// den Test finden, nicht den Dateinamen bewerten.
final _ruleTestPattern = RegExp(r'^r(\d{3})[_a-zA-Z0-9]*_test\.dart$');

/// Regeln, die vor dieser Pruefung entstanden sind — Altbestand.
///
/// **Diese Liste ist leer, und das ist ihr Endzustand.** Sie enthielt am
/// 06.08.2026 sechzehn der achtzehn ausgelieferten Regeln: Ein Validator,
/// der beim ersten Lauf sechzehn Fehler meldet, wird umgangen und haette
/// dieselbe Wirkung gehabt wie der Satz in CLAUDE.md, der die Pruefung
/// jahrelang nur behauptet hat. Also erst eine Warnung mit Namensliste, dann
/// die Tests. Beides ist erledigt — jede Regel in `rules/core/` hat heute
/// einen Test in `packages/axiom_core/test/rules/`.
///
/// Die Liste bleibt als Konstante stehen, damit die Ausnahme benannt und
/// leer sichtbar ist statt als geloeschter Codepfad. Sie waechst nicht: Wer
/// eine neue Regel ohne Test anlegt, bekommt einen Fehler, keinen Eintrag
/// hier.
const _rulesWithoutTest = <String>{};

/// Ergebnis einer Pruefung. Trennt Fehler (Regelwerk wird nicht geladen)
/// von Warnungen (Regelwerk laedt, ist aber sichtbar unfertig).
class ValidationReport {
  const ValidationReport({
    required this.errors,
    required this.warnings,
    required this.ruleCount,
    required this.shadowCount,
    required this.fileCount,
    this.ruleTestDir,
  });

  final List<String> errors;
  final List<String> warnings;
  final int ruleCount;
  final int shadowCount;
  final int fileCount;

  /// Gegen welches Testverzeichnis abgeglichen wurde, oder `null`, wenn
  /// keines gefunden wurde. Steht in der Ausgabe: Ein stumm uebersprungener
  /// Waechter ist schlimmer als keiner.
  final String? ruleTestDir;

  bool get isValid => errors.isEmpty;
}

void main(List<String> args) {
  final root = args.isNotEmpty ? args.first : 'rules';
  final dir = Directory(root);
  if (!dir.existsSync()) {
    stderr.writeln('Verzeichnis nicht gefunden: $root');
    exit(2);
  }

  final report = validateRules(dir);
  for (final w in report.warnings) {
    stdout.writeln('WARN   $w');
  }
  for (final e in report.errors) {
    stdout.writeln('FEHLER $e');
  }

  stdout.writeln('');
  stdout.writeln('${report.ruleCount} Regeln geprueft in '
      '${report.fileCount} Dateien '
      '(${report.shadowCount} im SHADOW-Modus)');
  stdout.writeln('${report.errors.length} Fehler, '
      '${report.warnings.length} Warnungen');

  // Was nicht geprueft wurde, steht da. Sonst sieht ein uebersprungener
  // Abgleich genauso aus wie ein bestandener.
  if (report.ruleTestDir == null) {
    stdout.writeln('Regel-Tests nicht abgeglichen: kein '
        'packages/axiom_core/test/rules/ oberhalb von $root gefunden.');
  }

  if (!report.isValid) {
    stdout.writeln('');
    stdout.writeln('Regelwerk ungueltig — wird nicht geladen.');
    exit(1);
  }
  stdout.writeln('Regelwerk gueltig.');
}

/// Prueft jede YAML-Datei unterhalb von [dir]. Schreibt nichts.
ValidationReport validateRules(Directory dir) {
  final errors = <String>[];
  final warnings = <String>[];
  final seenIds = <String, String>{};
  var ruleCount = 0;
  var shadowCount = 0;

  final ruleTests = _findRuleTests(dir);
  final testedIds = ruleTests == null ? null : _testedRuleIds(ruleTests);
  final untested = <String>[];

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

      // ── Test in packages/axiom_core/test/rules/ ──
      //
      // CLAUDE.md sagt diese Kopplung seit Langem zu, erzwungen wurde sie
      // nirgends: 18 Regeln, 2 Testdateien. Eine ungetestete Regel feuert am
      // Geraet, ohne dass ihre Bedingung je gegen einen Zustand ausgewertet
      // wurde — eine vertauschte Vergleichsrichtung faellt erst dort auf.
      if (testedIds != null && _idPattern.hasMatch(id)) {
        final number = id.substring(2);
        if (testedIds.contains(id)) {
          if (_rulesWithoutTest.contains(id)) {
            warnings.add('$where: hat einen Test — Eintrag aus '
                '_rulesWithoutTest in tools/bin/validate_rules.dart '
                'streichen.');
          }
        } else if (_rulesWithoutTest.contains(id)) {
          untested.add(id);
        } else {
          errors.add('$where: kein Test in packages/axiom_core/test/rules/. '
              'Erwartet wird r${number}_<name>_test.dart. Eine Regel ohne '
              'Test feuert am Geraet, ohne dass ihre Bedingung je gegen '
              'einen Zustand ausgewertet wurde.');
        }
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

  // Eine Zeile statt sechzehn: Die Namensliste soll gelesen werden, nicht
  // ueberblaettert.
  if (untested.isNotEmpty) {
    untested.sort();
    warnings.add('${untested.length} Regeln ohne Test in '
        'packages/axiom_core/test/rules/: ${untested.join(", ")}. '
        'Altbestand — eine neue Regel ohne Test ist ein Fehler.');
  }

  return ValidationReport(
    errors: errors,
    warnings: warnings,
    ruleCount: ruleCount,
    shadowCount: shadowCount,
    fileCount: files.length,
    ruleTestDir: ruleTests?.path,
  );
}

/// Sucht `packages/axiom_core/test/rules/` ab [start] aufwaerts.
///
/// Gesucht statt angenommen: Der Validator laeuft mal ueber `rules/`, mal
/// ueber `rules/core/` (aus `sync_rules.dart`) und in Tests ueber eine Kopie
/// im temporaeren Verzeichnis. Ein fester Pfad waere der erste, der bricht.
Directory? _findRuleTests(Directory start) {
  var dir = start.absolute;
  while (true) {
    final probe = Directory('${dir.path}/packages/axiom_core/test/rules');
    if (probe.existsSync()) return probe;
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

/// Welche Regel-IDs eine Testdatei haben. Der Dateiname ist die Kopplung —
/// ein Kommentar waere nicht pruefbar.
Set<String> _testedRuleIds(Directory ruleTests) => {
      for (final file in ruleTests.listSync().whereType<File>())
        if (_ruleTestPattern.firstMatch(file.uri.pathSegments.last)
            case final match?)
          'R-${match.group(1)}',
    };

/// Bekannte Variablen der Regel-DSL — abgeleitet, nicht abgeschrieben.
///
/// Hier stand eine handgepflegte Zweitliste. Sie ist genau das geworden, was
/// eine Zweitliste wird: Sie driftete ab. Eine im Wortschatz ergaenzte
/// Variable galt dem Validator als unbekannt, und die Regel, die sie
/// benutzte, wurde nicht geladen — mit einer Fehlermeldung, die nach einem
/// Tippfehler in der Regel aussah statt nach einer Luecke im Werkzeug.
final _knownVariables = <String>{
  for (final v in RuleVocabulary.numerics) v.id,
  for (final v in RuleVocabulary.symbolics) v.id,
  // Kein Variablenname, sondern ein eigener Knotentyp — der Bedingungsbaum
  // meldet ihn trotzdem als referenziert.
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
