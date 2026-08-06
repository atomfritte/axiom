/// „Jede Regel braucht einen Test in packages/axiom_core/test/rules/" — der
/// Satz stand in CLAUDE.md, in docs/02-ARCHITEKTUR.md („CI-Gate") und in
/// docs/04-REGELWERK.md („bricht hart ab"). Geprueft hat ihn nichts: 18
/// ausgelieferte Regeln, zwei Testdateien, und der Validator kannte das Wort
/// Test gar nicht. Eine Regel mit vertauschter Vergleichsrichtung ging so
/// durch jeden gruenen Lauf und feuerte am Geraet.
///
/// Seit dem Test-Gate im Validator gilt die Zusage fuer jede Regel, und seit
/// dem Abarbeiten des Altbestands ist die Ausnahmeliste leer: alle achtzehn
/// ausgelieferten Regeln haben einen Test. Hier wird das festgehalten — als
/// Verhalten des Werkzeugs, nicht als zweite Liste: Der Test startet
/// `validate_rules.dart` genau so, wie CLAUDE.md es vorschreibt, und liest
/// Exit-Code und Ausgabe. Eine Kopie der Ausnahmeliste waere binnen einer
/// Regel abgedriftet.
///
/// Warum in axiom_data: `rules/` ist von hier aus erreichbar, `dart:io`
/// erlaubt, und `dart test` in diesem Paket steht in CLAUDE.md unter den
/// Kommandos, die vor jedem Commit gruen sein muessen.
library;

import 'dart:io';

import 'package:test/test.dart';

/// Die Projektwurzel — gesucht statt angenommen, weil `dart test` je nach
/// Aufruf in verschiedenen Verzeichnissen startet.
Directory get repoRoot {
  var dir = Directory.current.absolute;
  while (true) {
    if (File('${dir.path}/tools/bin/validate_rules.dart').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Projektwurzel nicht gefunden ab ${Directory.current}');
    }
    dir = parent;
  }
}

/// Startet den Validator so, wie CLAUDE.md ihn vorschreibt.
ProcessResult validate(String rulesPath) => Process.runSync(
      Platform.resolvedExecutable,
      ['run', 'tools/bin/validate_rules.dart', rulesPath],
      workingDirectory: repoRoot.path,
    );

void main() {
  test('jede ausgelieferte Regel hat einen Test', () {
    final result = validate('${repoRoot.path}/rules');
    final out = result.stdout as String;

    expect(
      result.exitCode,
      0,
      reason: 'Eine neue Regel ohne Test in '
          'packages/axiom_core/test/rules/. Ohne ihn ist ihre Bedingung nie '
          'gegen einen Zustand ausgewertet worden — sie feuert trotzdem.\n'
          '$out',
    );
    // Hier stand die Umkehrung: Der Lauf MUSSTE die Zeile „16 Regeln ohne
    // Test" enthalten, weil der Altbestand sichtbar bleiben sollte, statt
    // als Stille durchzugehen. Der Altbestand ist abgearbeitet — jede der
    // achtzehn Regeln hat einen Test —, und damit dreht sich die Zusage um:
    // Taucht die Zeile wieder auf, ist eine Regel auf die Ausnahmeliste
    // gewandert, statt einen Test zu bekommen.
    expect(out, isNot(contains('Regeln ohne Test')));
  });

  group('das Test-Gate im Validator', () {
    late Directory tmp;
    late Directory rules;
    late Directory ruleTests;

    setUp(() {
      // Ein Mini-Repo: dieselbe Verzeichnisform wie das echte, damit der
      // Validator sein Testverzeichnis findet.
      tmp = Directory.systemTemp.createTempSync('axiom_rule_gate');
      rules = Directory('${tmp.path}/rules/core')..createSync(recursive: true);
      ruleTests = Directory('${tmp.path}/packages/axiom_core/test/rules')
        ..createSync(recursive: true);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    ProcessResult check() => validate('${tmp.path}/rules');

    test('eine neue Regel ohne Test ist ein Fehler', () {
      File('${rules.path}/neu.yaml').writeAsStringSync(_rule('R-999'));

      final result = check();

      expect(result.exitCode, 1);
      expect(result.stdout as String, contains('r999_<name>_test.dart'));
    });

    test('dieselbe Regel mit Testdatei ist gueltig', () {
      File('${rules.path}/neu.yaml').writeAsStringSync(_rule('R-999'));
      File('${ruleTests.path}/r999_neu_test.dart').writeAsStringSync('');

      final result = check();

      expect(result.exitCode, 0, reason: result.stdout as String);
    });

    test('die Ausnahmeliste ist leer — auch fuer den frueheren Altbestand', () {
      // R-001 stand bis zum 06.08.2026 auf der Liste und war damit von der
      // Pruefung ausgenommen. Ohne Testdatei ist genau diese ID heute ein
      // Fehler wie jede andere. Der Test ist die einzige Stelle, an der die
      // Leere der Liste ueberhaupt messbar ist: Sie ist eine Konstante im
      // Werkzeug, und eine Konstante liest man nach, statt sie zu pruefen.
      File('${rules.path}/alt.yaml').writeAsStringSync(_rule('R-001'));

      final result = check();

      expect(result.exitCode, 1);
      expect(result.stdout as String, contains('r001_<name>_test.dart'));
    });

    test('ohne Testverzeichnis sagt der Validator, dass er nicht '
        'abgeglichen hat', () {
      // Ein stumm uebersprungener Waechter sieht aus wie ein bestandener.
      ruleTests.parent.parent.parent.deleteSync(recursive: true);
      File('${rules.path}/neu.yaml').writeAsStringSync(_rule('R-999'));

      final result = check();

      expect(result.exitCode, 0);
      expect(result.stdout as String, contains('nicht abgeglichen'));
    });
  });
}

/// Eine in jeder anderen Hinsicht gueltige Regel.
String _rule(String id) => '''
- id: $id
  title: "Testregel"
  title_en: "Test rule"
  deficit: D1
  rationale: >
    Diese Regel existiert nur, damit das Test-Gate an einem sonst gueltigen
    Regelwerk gemessen werden kann.
  rationale_en: >
    This rule exists only so the test gate can be measured against an
    otherwise valid rulebook.
  when:
    all:
      - count_today: { event: checkin, lt: 1 }
  then:
    action: log_only
  priority: 10
  severity: info
  cooldown: { minutes: 60 }
  enabled: true
''';
