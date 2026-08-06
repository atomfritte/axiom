/// Spiegelt `rules/core/` in die App-Assets.
///
/// Flutter kann nur Assets bündeln, die unterhalb des App-Verzeichnisses
/// liegen. Das Regelwerk gehört aber in die Projektwurzel — dort ist es
/// versioniert, diffbar und unabhängig von der App lesbar.
///
///   dart run tools/bin/sync_rules.dart
///
/// Vor jedem App-Build ausführen. Der Validator läuft mit: Ein ungültiges
/// Regelwerk soll nie ins Bundle gelangen. Er lief lange nicht — der Satz
/// stand hier, der Aufruf fehlte, und eine kaputte Regel wurde anstandslos
/// kopiert. Jetzt prüft `validateRules` das Quellverzeichnis, und bei einem
/// Fehler wird **keine** Datei angefasst: Lieber ein alter, gültiger
/// Regelsatz im Bundle als ein halb aktualisierter, dessen Zustand niemand
/// kennt.
library;

import 'dart:io';

import 'validate_rules.dart';

void main(List<String> args) {
  final source = Directory(args.isNotEmpty ? args[0] : 'rules/core');
  final target = Directory(
    args.length > 1 ? args[1] : 'packages/axiom_app/assets/rules',
  );

  if (!source.existsSync()) {
    stderr.writeln('Quelle nicht gefunden: ${source.path}');
    exit(2);
  }

  // Erst prüfen, dann kopieren. Warnungen sind kein Grund anzuhalten —
  // eine fehlende Übersetzung ist sichtbar unfertig, kein Ladefehler.
  final report = validateRules(source);
  for (final w in report.warnings) {
    stdout.writeln('WARN   $w');
  }
  if (!report.isValid) {
    for (final e in report.errors) {
      stderr.writeln('FEHLER $e');
    }
    stderr.writeln('');
    stderr.writeln('${report.errors.length} Fehler in ${source.path} — '
        'nichts gespiegelt.');
    stderr.writeln('Ein ungültiges Regelwerk gehört nicht ins Bundle.');
    exit(1);
  }

  target.createSync(recursive: true);

  final wanted = <String>{};
  var copied = 0;
  var unchanged = 0;

  for (final file in source
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.yaml'))) {
    final name = file.uri.pathSegments.last;
    wanted.add(name);
    final dest = File('${target.path}/$name');
    final content = file.readAsStringSync();
    if (dest.existsSync() && dest.readAsStringSync() == content) {
      unchanged++;
      continue;
    }
    dest.writeAsStringSync(content);
    copied++;
    stdout.writeln('aktualisiert: $name');
  }

  // Verwaiste Assets entfernen — sonst laedt die App eine geloeschte Regel
  // weiter, und niemand merkt es.
  for (final file in target.listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    if (name.endsWith('.yaml') && !wanted.contains(name)) {
      file.deleteSync();
      stdout.writeln('entfernt: $name');
    }
  }

  stdout.writeln('${report.ruleCount} Regeln geprüft, '
      '$copied aktualisiert, $unchanged unverändert.');
}
