/// Das Regelwerk liegt zweimal im Repo, und nur eine der beiden Fassungen
/// läuft am Gerät.
///
/// `rules/core/` ist die Quelle — dort wird geändert, dort prüft der
/// Validator, dort liest `axiom_data/test/rule_source_test.dart`.
/// `assets/rules/` ist der Spiegel, den Flutter ins Bundle nimmt; ihn liest
/// `harness.dart`, und ihn zeigt der Systeminspektor als „das Regelwerk" an.
/// Zwischen beiden steht ein Handschritt: `dart run tools/bin/sync_rules.dart`.
///
/// Wird er vergessen, ist nichts rot. Der Validator sieht nur die Quelle, die
/// App-Tests sehen nur den Spiegel, und am Gerät ist der Unterschied nicht
/// erkennbar, weil der Systeminspektor ebenfalls den Spiegel anzeigt. Eine
/// geänderte Schwelle liegt dann committet im Repo und feuert trotzdem mit
/// dem alten Wert.
///
/// Dieser Test ist der Handschritt als Zusicherung. Er gehört in diese Suite,
/// weil hier der Spiegel gelesen wird: Wer eine veraltete Regel testet,
/// bekommt die Meldung dort, wo er ihr vertraut hat.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Vergleicht Quelle und Spiegel Datei für Datei. Leere Liste heißt gleich.
///
/// Geprüft wird in beide Richtungen. Eine Regeldatei, die in `rules/core/`
/// gelöscht wurde, bleibt sonst als Waise im Bundle liegen und feuert weiter
/// — `sync_rules.dart` räumt sie beim nächsten Lauf weg, aber genau der Lauf
/// ist ja der vergessene.
List<String> ruleParityProblems(Directory source, Directory mirror) {
  const hint = 'dart run tools/bin/sync_rules.dart ausführen';
  final problems = <String>[];

  if (!source.existsSync()) return ['${source.path} fehlt'];
  if (!mirror.existsSync()) return ['${mirror.path} fehlt — $hint'];

  Map<String, String> yamlFiles(Directory dir) => {
        for (final file in dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.yaml')))
          file.uri.pathSegments.last: file.readAsStringSync(),
      };

  final expected = yamlFiles(source);
  final actual = yamlFiles(mirror);

  for (final name in {...expected.keys, ...actual.keys}.toList()..sort()) {
    if (!actual.containsKey(name)) {
      problems.add('$name fehlt im Bundle — $hint');
    } else if (!expected.containsKey(name)) {
      problems.add('$name liegt im Bundle, aber nicht in ${source.path} — '
          '$hint');
    } else if (expected[name] != actual[name]) {
      problems.add('$name weicht vom Bundle ab — $hint');
    }
  }

  return problems;
}

void main() {
  test('das ausgelieferte Regelwerk ist das committete', () {
    final problems = ruleParityProblems(
      Directory('../../rules/core'),
      Directory('assets/rules'),
    );

    expect(
      problems,
      isEmpty,
      reason: 'Der Spiegel in assets/rules weicht von rules/core ab. Alles, '
          'was diese Suite prüft, prüft dann eine andere Fassung als die '
          'committete:\n${problems.join("\n")}',
    );
  });

  group('der Vergleich selbst', () {
    late Directory tmp;
    late Directory source;
    late Directory mirror;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('axiom_parity');
      source = Directory('${tmp.path}/core')..createSync();
      mirror = Directory('${tmp.path}/assets')..createSync();
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    void write(Directory dir, String name, String content) =>
        File('${dir.path}/$name').writeAsStringSync(content);

    test('gleiche Dateien sind kein Befund', () {
      write(source, 's2-live.yaml', 'gte: 72\n');
      write(mirror, 's2-live.yaml', 'gte: 72\n');

      expect(ruleParityProblems(source, mirror), isEmpty);
    });

    test('eine geänderte Schwelle fällt auf', () {
      write(source, 's2-live.yaml', 'gte: 24\n');
      write(mirror, 's2-live.yaml', 'gte: 72\n');

      expect(
        ruleParityProblems(source, mirror),
        ['s2-live.yaml weicht vom Bundle ab — '
            'dart run tools/bin/sync_rules.dart ausführen'],
      );
    });

    test('eine neue Regeldatei ohne Spiegel fällt auf', () {
      write(source, 's4-signals.yaml', 'x\n');

      expect(
        ruleParityProblems(source, mirror).single,
        contains('s4-signals.yaml fehlt im Bundle'),
      );
    });

    test('eine gelöschte Regeldatei bleibt nicht als Waise im Bundle', () {
      write(mirror, 'alt.yaml', 'x\n');

      expect(
        ruleParityProblems(source, mirror).single,
        contains('alt.yaml liegt im Bundle'),
      );
    });
  });
}
