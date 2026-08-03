/// Architektur-Waechter. Bricht den Build bei Grenzverletzungen.
///
/// Prueft die harten Regeln aus CLAUDE.md und docs/02-ARCHITEKTUR.md:
///   1. axiom_core hat keine Flutter-, Platform- oder I/O-Abhaengigkeit
///   2. Kein DateTime.now() / Random() im Core — Zeit und Zufall werden
///      injiziert. Ohne das sind Regeln nicht deterministisch testbar,
///      und Determinismus ist die Grundlage von G2.
///   3. Abhaengigkeiten zeigen immer nach innen
///
///   dart run tools/bin/check_layering.dart [repo-wurzel]
library;

import 'dart:io';

/// Was in welchem Package nicht vorkommen darf.
const _forbiddenImports = {
  'axiom_core': [
    'package:flutter/',
    'dart:io',
    'dart:ui',
    'dart:html',
    'package:http/',
    'package:sqflite/',
    'package:drift/',
    'package:axiom_data/',
    'package:axiom_app/',
  ],
  'axiom_data': [
    'package:flutter/material.dart',
    'package:axiom_app/',
  ],
};

/// Nur im Core verboten — SystemClock ist die eine erlaubte Ausnahme.
final _forbiddenCalls = <RegExp, String>{
  RegExp(r'DateTime\.now\(\)'):
      'DateTime.now() — Zeit wird ueber den Clock-Port injiziert',
  RegExp(r'\bRandom\s*\('):
      'Random() — Zufall wird ueber den Rng-Port injiziert',
};

/// Datei-Ausnahmen fuer die Call-Pruefung (die Port-Implementierung selbst).
const _callExceptions = {'lib/src/ports/ports.dart'};

void main(List<String> args) {
  final root = Directory(args.isNotEmpty ? args.first : '.');
  final packagesDir = Directory('${root.path}/packages');
  if (!packagesDir.existsSync()) {
    stderr.writeln('packages/ nicht gefunden unter ${root.path}');
    exit(2);
  }

  final violations = <String>[];
  var filesChecked = 0;

  for (final entry in packagesDir.listSync().whereType<Directory>()) {
    final packageName = entry.path.split(Platform.pathSeparator).last;
    final forbidden = _forbiddenImports[packageName];
    if (forbidden == null) continue;

    final libDir = Directory('${entry.path}/lib');
    if (!libDir.existsSync()) continue;

    for (final file in libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      filesChecked++;
      final relative =
          file.path.substring(entry.path.length + 1).replaceAll('\\', '/');
      final lines = file.readAsLinesSync();

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trimLeft();

        // 1 + 3: verbotene Imports
        if (trimmed.startsWith('import ') || trimmed.startsWith('export ')) {
          for (final bad in forbidden) {
            if (line.contains(bad)) {
              violations.add(
                '$packageName/$relative:${i + 1}  verbotener Import: $bad',
              );
            }
          }
        }

        // 2: verbotene Aufrufe (nur im Core)
        if (packageName != 'axiom_core') continue;
        if (_callExceptions.contains(relative)) continue;
        if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;

        for (final call in _forbiddenCalls.entries) {
          if (call.key.hasMatch(line)) {
            violations.add(
              '$packageName/$relative:${i + 1}  ${call.value}',
            );
          }
        }
      }
    }
  }

  for (final v in violations) {
    stdout.writeln('VERLETZUNG $v');
  }

  stdout.writeln('');
  stdout.writeln('$filesChecked Dateien geprueft, '
      '${violations.length} Verletzungen');

  if (violations.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('Architekturgrenzen verletzt. '
        'Siehe CLAUDE.md und docs/02-ARCHITEKTUR.md.');
    exit(1);
  }
  stdout.writeln('Architekturgrenzen eingehalten.');
}
