/// Der Waechter selbst hatte keinen Waechter. Er las zwei von vier Paketen
/// und meldete trotzdem „33 Dateien geprueft, 0 Verletzungen" — eine Zahl,
/// die vollstaendig klingt. Diese Tests fuehren ihm gebaute Verstoesse vor:
/// Was er dabei nicht findet, findet er auch im Repo nicht.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'tool_process.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('axiom_layering'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Legt ein Mini-Repo an: jedes bekannte Paket vorhanden, alle leer.
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

  test('ein sauberes Mini-Repo ist gruen', () {
    scaffold();
    write('packages/axiom_core/lib/ok.dart', "import 'dart:convert';\n");

    final result = check();

    expect(result.exitCode, 0, reason: result.stdout as String);
    expect(result.stdout as String, contains('Architekturgrenzen eingehalten'));
  });

  test('axiom_app wird gelesen — SQL gehoert nach axiom_data', () {
    scaffold();
    write(
      'packages/axiom_app/lib/leak.dart',
      "import 'package:sqlite3/sqlite3.dart';\n",
    );

    final result = check();

    expect(result.exitCode, 1);
    expect(
      result.stdout as String,
      contains('axiom_app/lib/leak.dart:1  verbotener Import: '
          'package:sqlite3/'),
    );
  });

  test('tools wird gelesen — ein Werkzeug startet ohne Flutter', () {
    scaffold();
    write(
      'tools/bin/leak.dart',
      "import 'package:flutter/material.dart';\n",
    );

    final result = check();

    expect(result.exitCode, 1);
    expect(result.stdout as String, contains('tools/bin/leak.dart:1'));
  });

  test('axiom_data darf das Framework auch nicht ueber widgets.dart holen',
      () {
    // Vorher stand in der Verbotsliste nur `package:flutter/material.dart`;
    // widgets, foundation und services waeren durchgegangen.
    scaffold();
    write(
      'packages/axiom_data/lib/leak.dart',
      "import 'package:flutter/widgets.dart';\n",
    );

    final result = check();

    expect(result.exitCode, 1);
    expect(result.stdout as String, contains('axiom_data/lib/leak.dart:1'));
  });

  test('DateTime.now() im Kern ist eine Verletzung', () {
    scaffold();
    write(
      'packages/axiom_core/lib/clock.dart',
      'final t = DateTime.now();\n',
    );

    final result = check();

    expect(result.exitCode, 1);
    expect(result.stdout as String, contains('Clock-Port injiziert'));
  });

  test('DateTime.now() ausserhalb des Kerns ist keine Verletzung', () {
    // Die Oberflaeche braucht die Uhr; die Zusicherung gilt dem Kern, weil
    // dort die Regeln ausgewertet werden.
    scaffold();
    write('packages/axiom_app/lib/screen.dart', 'final t = DateTime.now();\n');

    final result = check();

    expect(result.exitCode, 0, reason: result.stdout as String);
  });

  test('ein Paket ohne Regelsatz ist eine Verletzung, keine Auslassung', () {
    // Genau die Luecke, durch die axiom_app gefallen ist: nicht aufgelistet
    // heisst sonst ungeprueft, und ungeprueft sieht aus wie sauber.
    scaffold();
    Directory('${tmp.path}/packages/axiom_neu/lib').createSync(recursive: true);

    final result = check();

    expect(result.exitCode, 1);
    expect(
      result.stdout as String,
      contains('axiom_neu: Paket ohne Regelsatz'),
    );
  });

  test('ein fehlendes Paket faellt auf', () {
    scaffold();
    Directory('${tmp.path}/packages/axiom_data').deleteSync(recursive: true);

    final result = check();

    expect(result.exitCode, 1);
    expect(result.stdout as String, contains('packages/axiom_data fehlt'));
  });

  test('der Lauf sagt, was er nicht geprueft hat', () {
    // Ein Waechter, der seine Luecken verschweigt, erzeugt genau das
    // falsche Vertrauen, das er verhindern soll.
    scaffold();

    final out = check().stdout as String;

    expect(out, contains('Nicht geprueft:'));
    expect(out, contains('Kotlin'));
  });

  test('das echte Repo haelt die Grenzen ein', () {
    final result = runTool('check_layering.dart', [repoRoot.path]);
    final out = result.stdout as String;

    expect(result.exitCode, 0, reason: out);
    // Alle vier Pakete tauchen mit einer Dateizahl auf — sonst ist eines
    // still herausgefallen.
    for (final package in ['axiom_core', 'axiom_data', 'axiom_app', 'tools']) {
      expect(
        RegExp('$package\\s+[1-9][0-9]* Dateien').hasMatch(out),
        isTrue,
        reason: '$package wurde nicht gelesen:\n$out',
      );
    }
  });

  test('ohne packages/ bricht es ab', () {
    final result = check();

    expect(result.exitCode, 2);
    expect(result.stderr as String, contains('packages/ nicht gefunden'));
  });
}
