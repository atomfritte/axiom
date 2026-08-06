/// `sync_rules.dart` ist der einzige Weg, auf dem eine Regel ins App-Bundle
/// kommt. Sein Kopfkommentar sagt seit jeher „Der Validator läuft mit: Ein
/// ungültiges Regelwerk soll nie ins Bundle gelangen" — aufgerufen wurde er
/// nicht. Diese Tests halten die Zusage fest, statt sie zu glauben.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'tool_process.dart';

void main() {
  late Directory tmp;
  late Directory source;
  late Directory target;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('axiom_sync');
    source = Directory('${tmp.path}/rules')..createSync();
    target = Directory('${tmp.path}/assets')..createSync();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  ProcessResult sync() =>
      runTool('sync_rules.dart', [source.path, target.path]);

  test('ein gueltiges Regelwerk wird gespiegelt', () {
    File('${source.path}/gut.yaml').writeAsStringSync(_validRule);

    final result = sync();

    expect(result.exitCode, 0, reason: result.stderr as String);
    expect(File('${target.path}/gut.yaml').readAsStringSync(), _validRule);
    expect(result.stdout as String, contains('1 Regeln geprüft'));
  });

  test('ein ungueltiges Regelwerk gelangt nicht ins Bundle', () {
    File('${source.path}/kaputt.yaml').writeAsStringSync(_ruleWithoutRationale);

    final result = sync();

    expect(result.exitCode, 1);
    expect(result.stderr as String, contains('rationale fehlt'));
    expect(
      File('${target.path}/kaputt.yaml').existsSync(),
      isFalse,
      reason: 'Eine Regel ohne rationale darf das Bundle nicht erreichen — '
          'am Geraet ist sie nicht mehr von einer gueltigen zu unterscheiden.',
    );
  });

  test('bei einem Fehler bleibt auch das Gueltige unangetastet', () {
    // Sonst entstuende ein halb aktualisiertes Bundle, dessen Zustand
    // niemand kennt: neue Regel drin, alte geloescht, Fehler gemeldet.
    File('${source.path}/gut.yaml').writeAsStringSync(_validRule);
    File('${source.path}/kaputt.yaml').writeAsStringSync(_ruleWithoutRationale);

    final result = sync();

    expect(result.exitCode, 1);
    expect(File('${target.path}/gut.yaml').existsSync(), isFalse);
    expect(result.stderr as String, contains('nichts gespiegelt'));
  });

  test('eine verwaiste Regel im Bundle wird entfernt', () {
    // Sonst laedt die App eine geloeschte Regel weiter, und niemand merkt es.
    File('${target.path}/alt.yaml').writeAsStringSync(_validRule);
    File('${source.path}/gut.yaml').writeAsStringSync(_validRule);

    final result = sync();

    expect(result.exitCode, 0, reason: result.stderr as String);
    expect(File('${target.path}/alt.yaml').existsSync(), isFalse);
    expect(result.stdout as String, contains('entfernt: alt.yaml'));
  });

  test('ein zweiter Lauf schreibt nichts neu', () {
    File('${source.path}/gut.yaml').writeAsStringSync(_validRule);
    sync();

    final result = sync();

    expect(result.stdout as String, contains('0 aktualisiert, 1 unverändert'));
  });

  test('eine fehlende Quelle ist ein Abbruch', () {
    final result = runTool(
      'sync_rules.dart',
      ['${tmp.path}/gibtsnicht', target.path],
    );

    expect(result.exitCode, 2);
    expect(result.stderr as String, contains('Quelle nicht gefunden'));
  });

  test('das echte Regelwerk liegt gespiegelt im Bundle', () {
    // Der Handschritt aus CLAUDE.md („VOR jedem App-Build"). Faellt dieser
    // Test um, ist er vergessen worden.
    final core = Directory('${repoRoot.path}/rules/core');
    final assets = Directory('${repoRoot.path}/packages/axiom_app/assets/rules');

    for (final file in core
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.yaml'))) {
      final name = file.uri.pathSegments.last;
      final mirrored = File('${assets.path}/$name');
      expect(
        mirrored.existsSync(),
        isTrue,
        reason: '$name fehlt im Bundle — dart run tools/bin/sync_rules.dart',
      );
      expect(
        mirrored.readAsStringSync(),
        file.readAsStringSync(),
        reason: '$name weicht ab — dart run tools/bin/sync_rules.dart',
      );
    }
  });
}

const _validRule = '''
- id: R-900
  title: "Testregel"
  title_en: "Test rule"
  deficit: D1
  rationale: >
    Diese Regel existiert nur, damit der Spiegelvorgang an einem gueltigen
    Regelwerk gemessen werden kann.
  rationale_en: >
    This rule exists only so the mirroring step can be measured against a
    valid rulebook.
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

/// Ohne `rationale` — der eine Fehler, den G2 nicht durchgehen laesst.
const _ruleWithoutRationale = '''
- id: R-901
  title: "Regel ohne Begruendung"
  title_en: "Rule without a rationale"
  deficit: D1
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
