/// Der Validator ist die Stelle, an der G2 erzwungen statt gehofft wird:
/// Eine Regel ohne `rationale` wird nicht geladen, eine ohne `cooldown`
/// auch nicht. Bisher war er ein `main()` ohne Test — geprueft wurde er
/// dadurch, dass das echte Regelwerk zufaellig gueltig ist.
///
/// Diese Tests fuehren ihm ungueltige Regelwerke vor. Was er durchgehen
/// laesst, geht am Geraet live.
library;

import 'dart:io';

import 'package:test/test.dart';

import '../bin/validate_rules.dart';
import 'tool_process.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('axiom_validate'));
  tearDown(() => tmp.deleteSync(recursive: true));

  ValidationReport check(String yaml) {
    File('${tmp.path}/rules.yaml').writeAsStringSync(yaml);
    return validateRules(tmp);
  }

  test('das echte Regelwerk ist gueltig', () {
    final report = validateRules(Directory('${repoRoot.path}/rules'));

    expect(report.errors, isEmpty);
    expect(report.ruleCount, greaterThan(0));
    expect(report.isValid, isTrue);
  });

  test('eine Regel ohne rationale ist ein Fehler (G2)', () {
    final report = check(_rule(rationale: null));

    expect(report.isValid, isFalse);
    expect(report.errors.join(), contains('rationale fehlt'));
  });

  test('eine Regel ohne cooldown ist ein Fehler (R2)', () {
    final report = check(_rule(cooldown: null));

    expect(report.isValid, isFalse);
    expect(report.errors.join(), contains('cooldown fehlt'));
  });

  test('dieselbe id zweimal ist ein Fehler', () {
    final report = check('${_rule()}\n${_rule()}');

    expect(report.isValid, isFalse);
    expect(report.errors.join(), contains('bereits vergeben'));
  });

  test('eine unbekannte Variable in when ist ein Fehler', () {
    final report = check(_rule(when: '''
  when:
    all:
      - gibt_es_nicht: { gt: 3 }
'''));

    expect(report.isValid, isFalse);
    expect(report.errors.join(), contains('gibt_es_nicht'));
  });

  group('Ereignisnamen', () {
    test('ein vertippter Ereignisname ist ein Fehler', () {
      // Der teuerste Tippfehler im ganzen Regelwerk: Er macht die Regel
      // nicht ungueltig, sondern still wirkungslos. `count_today` auf ein
      // Ereignis, das niemand schreibt, ist immer 0 — die Regel unten
      // feuert damit jeden Tag, ohne dass je etwas passiert waere.
      final report = check(_rule(when: '''
  when:
    all:
      - count_today: { event: checkim, lt: 1 }
'''));

      expect(report.isValid, isFalse);
      expect(report.errors.join(), contains('checkim'));
      expect(report.errors.join(), contains('still wirkungslos'));
    });

    test('auch in minutes_since', () {
      // Hier kippt die Wirkung in die andere Richtung: Ein nie
      // eingetretenes Ereignis gilt als „unendlich lange her", `gte`
      // trifft also immer zu.
      final report = check(_rule(when: '''
  when:
    all:
      - minutes_since: { event: focus_begin, gte: 90 }
'''));

      expect(report.isValid, isFalse);
      expect(report.errors.join(), contains('focus_begin'));
    });

    test('ein interner Ereignistyp zaehlt, auch wenn der Editor ihn nicht '
        'anbietet', () {
      // `decision_feedback` steht nicht in RuleVocabulary.events — der
      // Wortschatz laesst interne Buchungen bewusst weg. Geschrieben wird
      // das Ereignis trotzdem (Runtime.respondTo), und R-130 wertet es aus.
      // Wer gegen den Wortschatz statt gegen EventType prueft, wirft genau
      // die gueltigen Regeln weg.
      final report = check(_rule(when: '''
  when:
    all:
      - minutes_since: { event: decision_feedback, gte: 1440 }
'''));

      expect(report.isValid, isTrue);
    });
  });

  test('eine fehlende Uebersetzung ist eine Warnung, kein Fehler', () {
    // Sichtbar unfertig ist besser als stumm fehlend: Eine deshalb nicht
    // geladene Regel waere schlimmer als der deutsche Satz in der
    // englischen Oberflaeche.
    final report = check(_rule());

    expect(report.isValid, isTrue);
    expect(report.warnings.join(), contains('keine Uebersetzung fuer title'));
  });

  test('Konfigurationsdateien ohne Regelliste stoeren nicht', () {
    File('${tmp.path}/weights.yaml').writeAsStringSync('capacity:\n  x: 0.3\n');
    final report = check(_rule());

    expect(report.isValid, isTrue);
    expect(report.ruleCount, 1);
    expect(report.fileCount, 2);
  });

  group('info gehoert zum Schatten', () {
    // `info` ist auf dem Geraet IMPORTANCE_MIN: kein Symbol in der
    // Statusleiste, kein Ton. Fuer eine Schattenregel richtig, fuer jede
    // andere ein Widerspruch — sie meldet sich, und niemand bemerkt es.
    //
    // Der Fall ist nicht erfunden. R-150 („Etwas liegt seit Tagen im
    // Eingang") sollte genau das leisten, was ein Badge leistet, und stand
    // auf `info`. Live geschaltet haette sie dasselbe getan wie vorher im
    // Schatten, nur mit mehr Aufwand.

    test('info mit log_only ist in Ordnung', () {
      final report = check(_rule(severity: 'info'));
      expect(report.isValid, isTrue);
    });

    test('info mit notify ist ein Fehler', () {
      final report = check(_rule(severity: 'info', action: 'notify'));

      expect(report.isValid, isFalse);
      expect(report.errors.join(), contains('unsichtbar'));
    });

    test('nudge mit notify ist der Normalfall', () {
      final report = check(_rule(severity: 'nudge', action: 'notify'));
      expect(report.isValid, isTrue);
    });

    test('das ausgelieferte Regelwerk haelt es ein', () {
      final report = validateRules(Directory('../rules'));
      expect(report.isValid, isTrue);
    });
  });

  group('enforce braucht eine Autorisierung', () {
    // `enforce` bricht Ruhezeit und Tagesdeckel. CLAUDE.md laesst das nur zu,
    // wenn der Nutzer die Regel im ruhigen Zustand selbst autorisiert hat —
    // vorher war das eine Warnung bei jedem Lauf, die niemand beantworten
    // konnte und die man deshalb nach dem dritten Mal ueberliest.

    test('ohne authorised_on wird gemeldet, aber nicht abgelehnt', () {
      final report = check(_rule(severity: 'enforce'));

      expect(report.isValid, isTrue,
          reason: 'Eine unautorisierte Regel bleibt ladbar — sonst waere der '
              'Validator ein Schalter, der die App abschaltet');
      expect(report.warnings.join(), contains('authorised_on'));
    });

    test('mit Datum schweigt die Warnung', () {
      final report =
          check(_rule(severity: 'enforce', authorisedOn: '2026-08-06'));

      expect(report.isValid, isTrue);
      expect(report.warnings.join(), isNot(contains('authorised_on')));
    });

    test('ein kaputtes Datum ist ein Fehler, keine Warnung', () {
      // Sonst haette „authorised_on: bald" dieselbe Wirkung wie ein Datum,
      // und die Zusage waere wieder nur ein Wort im Text.
      final report = check(_rule(severity: 'enforce', authorisedOn: 'bald'));

      expect(report.isValid, isFalse);
      expect(report.errors.join(), contains('kein Datum'));
    });

    test('an einer Regel ohne enforce ist das Feld wirkungslos — und sagt es',
        () {
      final report = check(_rule(authorisedOn: '2026-08-06'));

      expect(report.isValid, isTrue);
      expect(report.warnings.join(), contains('keine Wirkung'));
    });

    test('das ausgelieferte Regelwerk: R-052 ist autorisiert', () {
      // Der Fall, um den es wirklich geht. R-052 faengt naechtliche
      // Bestellungen ab und muss dafuer die Ruhezeit brechen — sechs von
      // sieben Stunden war sie vorher tot.
      final report = validateRules(Directory('../rules'));

      expect(report.isValid, isTrue);
      expect(report.warnings.where((w) => w.contains('R-052')), isEmpty,
          reason: 'R-052 traegt authorised_on');
      expect(report.warnings.where((w) => w.contains('R-090')), isNotEmpty,
          reason: 'R-090 ist NICHT autorisiert — die Warnung gehoert stehen '
              'zu bleiben, bis jemand sie beantwortet');
    });
  });

  group('als Kommandozeilenwerkzeug', () {
    test('ein ungueltiges Regelwerk endet mit Exit-Code 1', () {
      File('${tmp.path}/rules.yaml').writeAsStringSync(_rule(rationale: null));

      final result = runTool('validate_rules.dart', [tmp.path]);

      expect(result.exitCode, 1);
      expect(result.stdout as String, contains('Regelwerk ungueltig'));
    });

    test('das echte Regelwerk endet mit Exit-Code 0', () {
      final result =
          runTool('validate_rules.dart', ['${repoRoot.path}/rules']);

      expect(result.exitCode, 0);
      expect(result.stdout as String, contains('Regelwerk gueltig.'));
    });

    test('ein fehlendes Verzeichnis ist ein Abbruch', () {
      final result = runTool('validate_rules.dart', ['${tmp.path}/nichts']);

      expect(result.exitCode, 2);
      expect(result.stderr as String, contains('Verzeichnis nicht gefunden'));
    });
  });
}

/// Eine gueltige Regel, aus der einzelne Pflichtteile entfernt werden
/// koennen. `rationale: null` heisst „ohne rationale".
String _rule({
  String? rationale = 'Eine Begruendung, lang genug fuer den Validator und '
      'ohne Zeilenumbruch.',
  String? cooldown = '  cooldown: { minutes: 60 }',
  String severity = 'info',
  String action = 'log_only',
  String? authorisedOn,
  String when = '''
  when:
    all:
      - count_today: { event: checkin, lt: 1 }
''',
}) =>
    [
      '- id: R-900',
      '  title: "Testregel"',
      '  deficit: D1',
      if (rationale != null) '  rationale: "$rationale"',
      when.trimRight(),
      '  then:',
      '    action: $action',
      '  priority: 10',
      '  severity: $severity',
      if (authorisedOn != null) '  authorised_on: $authorisedOn',
      if (cooldown != null) cooldown,
      '  enabled: true',
      '',
    ].join('\n');
