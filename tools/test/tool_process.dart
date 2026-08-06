/// Gemeinsame Hilfen fuer die Werkzeug-Tests.
///
/// Die vier Werkzeuge sind Kommandozeilenprogramme. Ihr Ergebnis ist nicht
/// nur ein Rueckgabewert, sondern auch ein Exit-Code und das, was auf der
/// Konsole steht — CLAUDE.md schreibt sie in genau dieser Form vor („muss
/// immer gruen sein"). Deshalb starten die Tests sie als Prozess und lesen
/// beides.
library;

import 'dart:io';

/// Verzeichnis des Pakets `axiom_tools`.
///
/// Gesucht statt angenommen: `dart test` startet je nach Aufruf in
/// unterschiedlichen Verzeichnissen, und ein hart verdrahteter Pfad waere
/// der erste, der bricht.
Directory get toolsRoot {
  var dir = Directory.current.absolute;
  while (true) {
    if (File('${dir.path}/bin/calibrate.dart').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('tools/ nicht gefunden ab ${Directory.current.path}');
    }
    dir = parent;
  }
}

/// Die Projektwurzel — ein Verzeichnis ueber `tools/`.
Directory get repoRoot => toolsRoot.parent;

/// Startet ein Werkzeug so, wie CLAUDE.md es vorschreibt.
ProcessResult runTool(String script, List<String> args) => Process.runSync(
      Platform.resolvedExecutable,
      ['run', 'bin/$script', ...args],
      workingDirectory: toolsRoot.path,
    );

/// Ob das Kommandozeilenwerkzeug `sqlite3` vorhanden ist.
///
/// `calibrate.dart` braucht es; ohne wird der Ende-zu-Ende-Test
/// uebersprungen statt falsch gruen zu melden.
bool get hasSqlite3 {
  try {
    return Process.runSync('sqlite3', ['-version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}
