/// „Events sind append-only. Nie UPDATE, nie DELETE." — CLAUDE.md sagt es
/// seit dem ersten Commit, und der Typ, der die Zusage tragen muesste, bot
/// den Umweg als ganz normale oeffentliche Methode an: `upsertTask` schreibt
/// direkt in die Projektionstabelle.
///
/// Der Expertenmodus hat den Umweg genommen. Titel, Aktivierungsenergie,
/// Frist und Zustand wurden ohne Ereignis geschrieben, und jeder
/// `rebuildProjections()` — also jeder Vault-Import — hat sie stumm
/// zurueckgesetzt. Die Stelle ist behoben; diese Tests halten fest, dass der
/// naechste Schreibpfad dieselbe Abkuerzung nicht mehr lautlos nehmen kann.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'tool_process.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('axiom_appendonly'));
  tearDown(() => tmp.deleteSync(recursive: true));

  void scaffold() {
    for (final p in ['axiom_core', 'axiom_data', 'axiom_app']) {
      Directory('${tmp.path}/packages/$p/lib').createSync(recursive: true);
    }
    Directory('${tmp.path}/tools/bin').createSync(recursive: true);
  }

  void write(String relative, String source) {
    final file = File('${tmp.path}/$relative');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(source);
  }

  ProcessResult check() => runTool('check_layering.dart', [tmp.path]);

  test('ein zweiter Schreibpfad an den Ereignissen vorbei faellt auf', () {
    scaffold();
    write(
      'packages/axiom_app/lib/server/expert_server.dart',
      'Future<void> patch() async { await runtime.store.upsertTask(t); }\n',
    );

    final result = check();

    expect(result.exitCode, 1);
    expect(
      result.stdout as String,
      contains('axiom_app/lib/server/expert_server.dart:1'),
    );
    expect(result.stdout as String, contains('append-only'));
  });

  test('die zwei erlaubten Orte bleiben erlaubt', () {
    // Ohne sie waere die Regel keine Ortsbindung, sondern ein Verbot — und
    // die Projektion liesse sich gar nicht mehr schreiben.
    scaffold();
    write(
      'packages/axiom_app/lib/state/runtime.dart',
      'Future<void> add() async { await store.upsertTask(t); }\n',
    );
    write(
      'packages/axiom_data/lib/src/sqlite_event_store.dart',
      'Future<void> upsertTask(Task t) async {}\n',
    );

    final result = check();

    expect(result.exitCode, 0, reason: result.stdout as String);
  });

  test('ein Kommentar ist kein Aufruf', () {
    // Genau dieser Satz steht heute in expert_server.dart, dort wo der
    // Aufruf stand. Wuerde er als Verletzung gelten, waere die Begruendung
    // fuer die Aenderung nicht mehr aufschreibbar.
    scaffold();
    write(
      'packages/axiom_app/lib/server/expert_server.dart',
      '// Hier stand `runtime.store.upsertTask(...)` — ohne Ereignis.\n',
    );

    final result = check();

    expect(result.exitCode, 0, reason: result.stdout as String);
  });

  test('das echte Repo hat nur die zwei erlaubten Aufruforte', () {
    final result = runTool('check_layering.dart', [repoRoot.path]);
    final out = result.stdout as String;

    expect(
      result.exitCode,
      0,
      reason: 'Eine Aufgabenaenderung ohne Ereignis ueberlebt keinen '
          'rebuildProjections().\n$out',
    );
  });
}
