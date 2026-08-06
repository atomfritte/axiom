/// Architektur-Waechter. Bricht den Build bei Grenzverletzungen.
///
/// Prueft die harten Regeln aus CLAUDE.md und docs/02-ARCHITEKTUR.md:
///   1. axiom_core hat keine Flutter-, Platform- oder I/O-Abhaengigkeit
///   2. Kein DateTime.now() / Random() im Core — Zeit und Zufall werden
///      injiziert. Ohne das sind Regeln nicht deterministisch testbar,
///      und Determinismus ist die Grundlage von G2.
///   3. Abhaengigkeiten zeigen immer nach innen
///   4. Aufrufe, die eine Zusage umgehen koennen, stehen nur dort, wo sie
///      hingehoeren — siehe [_restrictedCalls].
///
///   dart run tools/bin/check_layering.dart [repo-wurzel]
///
/// Vorher standen hier nur axiom_core und axiom_data, und gelesen wurde nur
/// `lib/`. Der Lauf meldete „33 Dateien geprueft" und klang damit
/// vollstaendig — tatsaechlich waren axiom_app (das groesste Paket) und
/// `tools/` selbst ueberhaupt nicht abgedeckt. Zwei Konsequenzen daraus:
///
///   * Jedes Paket unter `packages/` braucht einen Eintrag in [_packages].
///     Ein Paket ohne Regelsatz ist eine Verletzung, keine Auslassung —
///     sonst faellt ein neues Paket lautlos durch.
///   * Der Lauf sagt am Ende, was er NICHT geprueft hat. Ein Waechter, der
///     seine Luecken verschweigt, erzeugt genau das falsche Vertrauen, das
///     er verhindern soll.
library;

import 'dart:io';

/// Ein geprueftes Paket: wo es liegt, welche Verzeichnisse gelesen werden
/// und was darin nicht vorkommen darf.
class PackageRules {
  const PackageRules({
    required this.name,
    required this.path,
    required this.directories,
    required this.forbiddenImports,
    this.checkInjectedPorts = false,
  });

  /// Anzeigename, zugleich der Verzeichnisname unter `packages/`.
  final String name;

  /// Pfad relativ zur Repo-Wurzel.
  final String path;

  /// Welche Unterverzeichnisse gelesen werden.
  final List<String> directories;

  /// Import-Praefixe, die in diesem Paket nicht vorkommen duerfen.
  final List<String> forbiddenImports;

  /// Ob zusaetzlich auf `DateTime.now()` und `Random()` geprueft wird.
  final bool checkInjectedPorts;
}

/// Der Regelsatz. Reihenfolge = Ausgabereihenfolge, von innen nach aussen.
const _packages = <PackageRules>[
  PackageRules(
    name: 'axiom_core',
    path: 'packages/axiom_core',
    directories: ['lib'],
    checkInjectedPorts: true,
    forbiddenImports: [
      'package:flutter/',
      'dart:io',
      'dart:ui',
      'dart:html',
      'package:http/',
      'package:sqflite/',
      'package:drift/',
      'package:sqlite3/',
      'package:yaml/',
      'package:axiom_data/',
      'package:axiom_app/',
    ],
  ),
  PackageRules(
    name: 'axiom_data',
    path: 'packages/axiom_data',
    directories: ['lib'],
    forbiddenImports: [
      // Vorher stand hier nur `package:flutter/material.dart`. Damit waeren
      // widgets.dart, foundation.dart und services.dart durchgegangen — und
      // eine davon reicht, um axiom_data an das Framework zu binden.
      'package:flutter/',
      'dart:ui',
      'dart:html',
      'package:http/',
      'package:axiom_app/',
    ],
  ),
  PackageRules(
    name: 'axiom_app',
    path: 'packages/axiom_app',
    directories: ['lib'],
    forbiddenImports: [
      // Persistenz und Regel-YAML gehoeren nach axiom_data. Die App spricht
      // ueber die Ports mit ihr; greift sie selbst zu SQL oder YAML, gibt es
      // zwei Wege in dieselben Daten und nur einer ist getestet.
      'package:sqlite3/',
      'package:yaml/',
      // ADR-0005: AXIOM lauscht, ruft nie. Die genaue Pruefung steht in
      // axiom_app/test/language_test.dart und kennt auch Socket.connect;
      // hier stehen die zwei Importe, die man ohne sie gar nicht erst
      // schreiben kann.
      'package:http/',
      'dart:html',
    ],
  ),
  PackageRules(
    name: 'tools',
    path: 'tools',
    directories: ['bin', 'test'],
    forbiddenImports: [
      // Werkzeuge laufen auf der Kommandozeile. Ein Flutter-Import hier
      // hiesse, dass das Werkzeug nur noch mit `flutter` startet — und die
      // Pruefkommandos aus CLAUDE.md laufen mit `dart`.
      'package:flutter/',
      'dart:ui',
      'package:axiom_app/',
    ],
  ),
];

/// Ein Aufruf, den es geben muss, der aber nur an benannten Stellen stehen
/// darf.
class RestrictedCall {
  const RestrictedCall({
    required this.pattern,
    required this.allowedIn,
    required this.reason,
  });

  final RegExp pattern;

  /// Erlaubte Dateien als `<paket>/<pfad>` — dieselbe Schreibweise, in der
  /// der Waechter Verletzungen meldet.
  final Set<String> allowedIn;

  final String reason;
}

/// Aufrufe mit Ortsbindung. Geprueft wird nur in `lib/`: Tests muessen den
/// Store direkt fuellen duerfen, sonst liesse sich der Wiederaufbau gar
/// nicht pruefen.
///
/// Der Anlass: `upsertTask` schreibt an der Ereignisschicht vorbei. CLAUDE.md
/// sagt „Events sind append-only", und die Methode bot den Umweg als ganz
/// normale oeffentliche Methode an. Der Expertenmodus hat ihn genommen und
/// Aufgabenaenderungen ohne Ereignis geschrieben; jeder
/// `rebuildProjections()` hat sie stumm zurueckgesetzt. Die Stelle ist
/// behoben — der naechste Schreibpfad haette dieselbe Abkuerzung genommen,
/// und nichts haette es gemeldet.
final _restrictedCalls = <RestrictedCall>[
  RestrictedCall(
    pattern: RegExp(r'\bupsertTask\s*\('),
    allowedIn: {
      // Die Implementierung selbst und ihr Aufruf im Wiederaufbau.
      'axiom_data/lib/src/sqlite_event_store.dart',
      // Der eine Schreibpfad der App: hier steht zu jedem upsertTask ein
      // passendes Ereignis in derselben Methode.
      'axiom_app/lib/state/runtime.dart',
    },
    reason: 'upsertTask schreibt direkt in die Projektion, an den Ereignissen '
        'vorbei. Wer eine Aufgabe aendert, schreibt ein Ereignis; die '
        'Projektion folgt daraus (CLAUDE.md: Events sind append-only). '
        'Erlaubt in runtime.dart und sqlite_event_store.dart.',
  ),
];

/// Nur dort geprueft, wo [PackageRules.checkInjectedPorts] gesetzt ist.
final _forbiddenCalls = <RegExp, String>{
  RegExp(r'DateTime\.now\(\)'):
      'DateTime.now() — Zeit wird ueber den Clock-Port injiziert',
  RegExp(r'\bRandom\s*\('):
      'Random() — Zufall wird ueber den Rng-Port injiziert',
};

/// Datei-Ausnahmen fuer die Call-Pruefung (die Port-Implementierung selbst).
const _callExceptions = {'lib/src/ports/ports.dart'};

/// Was dieser Waechter nicht sieht. Steht in der Ausgabe, damit ein gruener
/// Lauf nicht mehr sagt, als er weiss.
const _notChecked = <String>[
  'test/-Verzeichnisse der drei Pakete (nur tools/test wird gelesen)',
  'Kotlin, Android-Manifest und Gradle — siehe '
      'axiom_app/test/platform_integration_test.dart',
  'assets/, darunter die Weboberflaeche des Expertenmodus',
  'Aufrufe ausser DateTime.now()/Random() im Kern und upsertTask in lib/',
];

void main(List<String> args) {
  final root = args.isNotEmpty ? args.first : '.';
  final packagesDir = Directory('$root/packages');
  if (!packagesDir.existsSync()) {
    stderr.writeln('packages/ nicht gefunden unter $root');
    exit(2);
  }

  final violations = <String>[];
  final checkedPerPackage = <String, int>{};

  for (final rules in _packages) {
    final dir = Directory('$root/${rules.path}');
    if (!dir.existsSync()) {
      violations.add('${rules.name}: Verzeichnis ${rules.path} fehlt. '
          'Entweder ist das Paket weg oder der Regelsatz zeigt ins Leere.');
      continue;
    }
    checkedPerPackage[rules.name] = _checkPackage(dir, rules, violations);
  }

  // Ein neues Paket ohne Regelsatz waere sonst still ungeprueft — genau die
  // Luecke, durch die axiom_app jahrelang gefallen ist.
  final configured = {for (final p in _packages) p.name};
  for (final entry in packagesDir.listSync().whereType<Directory>()) {
    final name = entry.path.split(Platform.pathSeparator).last;
    if (name.startsWith('.')) continue;
    if (configured.contains(name)) continue;
    violations.add('$name: Paket ohne Regelsatz in check_layering.dart. '
        'Ungeprueft heisst hier nicht erlaubt.');
  }

  for (final v in violations) {
    stdout.writeln('VERLETZUNG $v');
  }

  final total = checkedPerPackage.values.fold(0, (a, b) => a + b);
  stdout.writeln('');
  for (final rules in _packages) {
    final count = checkedPerPackage[rules.name];
    if (count == null) continue;
    stdout.writeln('  ${rules.name.padRight(12)} $count Dateien '
        '(${rules.directories.join(", ")})');
  }
  stdout.writeln('$total Dateien geprueft, ${violations.length} Verletzungen');

  stdout.writeln('');
  stdout.writeln('Nicht geprueft:');
  for (final gap in _notChecked) {
    stdout.writeln('  - $gap');
  }

  if (violations.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('Architekturgrenzen verletzt. '
        'Siehe CLAUDE.md und docs/02-ARCHITEKTUR.md.');
    exit(1);
  }
  stdout.writeln('');
  stdout.writeln('Architekturgrenzen eingehalten.');
}

/// Liest ein Paket und haengt Verletzungen an [violations]. Gibt die Zahl
/// der gelesenen Dateien zurueck.
int _checkPackage(
  Directory packageDir,
  PackageRules rules,
  List<String> violations,
) {
  var filesChecked = 0;

  for (final sub in rules.directories) {
    final dir = Directory('${packageDir.path}/$sub');
    if (!dir.existsSync()) continue;

    for (final file in dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      filesChecked++;
      final relative = file.path
          .substring(packageDir.path.length + 1)
          .replaceAll('\\', '/');
      final lines = file.readAsLinesSync();

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trimLeft();
        final isComment = trimmed.startsWith('//');

        // 1 + 3: verbotene Imports
        if (trimmed.startsWith('import ') || trimmed.startsWith('export ')) {
          for (final bad in rules.forbiddenImports) {
            if (line.contains(bad)) {
              violations.add(
                '${rules.name}/$relative:${i + 1}  verbotener Import: $bad',
              );
            }
          }
        }

        // 4: Aufrufe mit Ortsbindung
        if (sub == 'lib' && !isComment) {
          for (final call in _restrictedCalls) {
            if (!call.pattern.hasMatch(line)) continue;
            if (call.allowedIn.contains('${rules.name}/$relative')) continue;
            violations.add('${rules.name}/$relative:${i + 1}  ${call.reason}');
          }
        }

        // 2: verbotene Aufrufe
        if (!rules.checkInjectedPorts) continue;
        if (_callExceptions.contains(relative)) continue;
        if (isComment) continue;

        for (final call in _forbiddenCalls.entries) {
          if (call.key.hasMatch(line)) {
            violations.add('${rules.name}/$relative:${i + 1}  ${call.value}');
          }
        }
      }
    }
  }

  return filesChecked;
}
