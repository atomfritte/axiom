/// Prüft die Sprache der Oberfläche.
///
/// Zwei Dinge entscheiden bei dieser Zielgruppe über Adhärenz, und beide
/// sind reine Textfragen:
///
///   1. Keine Schuldsprache. Ein Vorwurf trifft bei Rejection Sensitivity
///      (D10) genau die Stelle, die das System entlasten soll — und erzeugt
///      Vermeidung statt Handlung.
///   2. Korrekte Umlaute. Ersatzschreibung wie "Kapazitaet" liest sich
///      unfertig, und ein System, das unfertig wirkt, bekommt keine ehrlichen
///      Daten.
///
/// Geprüft wird der Quelltext, nicht ein einzelner Screen — so entgeht auch
/// kein Text, der nur in seltenen Zuständen erscheint.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Alle Dart-Dateien, die Nutzertexte enthalten können.
///
/// Auch `axiom_core`: Die Term-Bezeichnungen der Formeln erscheinen in der
/// aufklappbaren Herleitung ("Schlafschuld −18"). Ein Rechtschreibfehler
/// dort ist genauso sichtbar wie einer im Screen.
List<File> appSources() => [
      ...Directory('lib').listSync(recursive: true),
      if (Directory('../axiom_core/lib').existsSync())
        ...Directory('../axiom_core/lib').listSync(recursive: true),
      if (Directory('../axiom_data/lib').existsSync())
        ...Directory('../axiom_data/lib').listSync(recursive: true),
    ]
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

/// Einfach und doppelt gequotete Literale, mindestens vier Zeichen lang.
final _stringLiterals = [
  RegExp("'([^'\\\\\n]{4,})'"),
  RegExp('"([^"\\\\\n]{4,})"'),
];

/// Zeichenketten-Literale einer Datei, ohne Kommentare.
///
/// Kommentare sind Entwicklerprosa und dürfen ASCII-Umschrift enthalten;
/// alles, was der Nutzer liest oder vorgelesen bekommt, nicht.
List<(int, String)> userFacingStrings(File file) {
  final result = <(int, String)>[];
  final lines = file.readAsLinesSync();
  var inBlockComment = false;

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    if (inBlockComment) {
      final end = line.indexOf('*/');
      if (end == -1) continue;
      line = line.substring(end + 2);
      inBlockComment = false;
    }
    final blockStart = line.indexOf('/*');
    if (blockStart != -1) {
      line = line.substring(0, blockStart);
      inBlockComment = !line.contains('*/');
    }
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('//')) continue;

    // Import-Pfade, Asset-Pfade und Kanalnamen sind keine Nutzertexte.
    if (trimmed.startsWith('import ') ||
        trimmed.startsWith('export ') ||
        trimmed.startsWith('part ')) {
      continue;
    }

    for (final pattern in _stringLiterals) {
      for (final match in pattern.allMatches(line)) {
        final text = match.group(1) ?? '';
        if (text.contains('/') || text.contains('_') || text.contains('.')) {
          continue; // Pfade, Schlüssel, Kanalnamen
        }
        result.add((i + 1, text));
      }
    }
  }
  return result;
}

void main() {
  group('Keine Schuldsprache (D10, R7)', () {
    // Formulierungen, die aus einem Messwert ein Urteil machen.
    const forbidden = [
      'überfällig seit',
      'schon wieder',
      'Streak',
      'du solltest',
      'Du solltest',
      'versagt',
      'faul',
      'endlich mal',
      'Immerhin',
      'nur noch',
    ];

    /// Verneinte Nennungen sind erwünscht — das Onboarding sagt ausdrücklich
    /// zu, was AXIOM *nicht* tut ("Keine Streaks, die brechen können").
    bool isNegated(String text, String word) {
      final before = text.substring(0, text.indexOf(word)).toLowerCase();
      return RegExp(r'\b(kein|keine|keinen|nie|niemals|ohne)\b\s*$')
              .hasMatch(before) ||
          RegExp(r'\b(kein|keine|keinen|nie|niemals|ohne)\b').hasMatch(before);
    }

    test('kommt in keinem Oberflächentext vor', () {
      final hits = <String>[];
      // Wie bei den Umlauten: Die englische Fassung wird von i18n_test
      // geprueft, mit englischen Woertern. Hier trifft „faul" sonst
      // „fault", und der Test verbietet ein voellig harmloses Wort.
      for (final file in appSources().where(
          (f) => !f.path.endsWith('i18n/en.dart'))) {
        for (final (line, text) in userFacingStrings(file)) {
          for (final word in forbidden) {
            // Wortgrenzen: „faul" darf nicht in „Faulheit"-fremden
            // Zusammensetzungen anschlagen.
            final hit = RegExp('\\b${RegExp.escape(word)}\\b',
                    caseSensitive: false)
                .hasMatch(text);
            if (hit && !isNegated(text, word)) {
              hits.add('${file.path}:$line  "$text"  → "$word"');
            }
          }
        }
      }
      expect(hits, isEmpty, reason: 'Schuldsprache gefunden:\n${hits.join("\n")}');
    });

    test('erkennt Schuldsprache, wenn sie auftaucht', () {
      // Der Wächter muss selbst überwacht werden: ein Test, der nie
      // anschlägt, ist von einem kaputten Test nicht unterscheidbar.
      const bad = 'Du solltest das endlich mal erledigen';
      expect(forbidden.any((w) => bad.contains(w) && !isNegated(bad, w)),
          isTrue);
    });
  });

  group('Umlaute', () {
    /// Wörter, in denen "ae/oe/ue" echte Umschrift ist — nicht Wörter wie
    /// "neue", "Steuer" oder "aktuelle", in denen die Folge legitim ist.
    final substitutions = RegExp(
      r'\b\w*('
      r'aet|aessig|aehl|aeng|aell|aeuf|aehr|aend|aerk|aecht|aemt|'
      r'oeg|oenn|oech|oehe|oepf|oes|oerp|oell|'
      r'uehr|uehl|uenf|uecke|uerz|uebe|uess|uerd|uenst'
      r')\w*\b',
    );

    test('Nutzertexte verwenden echte Umlaute, keine Ersatzschreibung', () {
      final hits = <String>[];
      // Nur deutsche Texte. Im Englischen sind "does", "goes" und "guessing"
      // voellig richtig geschrieben — die englische Fassung prueft
      // i18n_test, mit den Regeln ihrer eigenen Sprache.
      for (final file in appSources().where(
          (f) => !f.path.endsWith('i18n/en.dart'))) {
        for (final (line, text) in userFacingStrings(file)) {
          for (final match in substitutions.allMatches(text)) {
            hits.add('${file.path}:$line  "${match.group(0)}"  in: "$text"');
          }
        }
      }
      expect(hits, isEmpty,
          reason: 'Ersatzschreibung statt Umlaut:\n${hits.join("\n")}');
    });

    test('auch im ausgelieferten Regelwerk', () {
      final dir = Directory('assets/rules');
      if (!dir.existsSync()) return;
      final hits = <String>[];
      for (final file in dir.listSync().whereType<File>()) {
        final lines = file.readAsLinesSync();
        // Uebersetzte Felder (title_en, rationale_en) sind englisch und
        // gehoeren nicht in diese Pruefung.
        var inTranslation = false;
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (RegExp(r'^\s{0,4}\w+_[a-z]{2}:').hasMatch(line)) {
            inTranslation = true;
            continue;
          }
          if (inTranslation) {
            if (line.trim().isEmpty || line.startsWith('    ')) continue;
            inTranslation = false;
          }
          for (final match in substitutions.allMatches(line)) {
            hits.add('${file.path}:${i + 1}  "${match.group(0)}"');
          }
        }
      }
      expect(hits, isEmpty,
          reason: 'Ersatzschreibung im Regelwerk:\n${hits.join("\n")}');
    });
  });

  group('Datenschutz', () {
    test('AXIOM ruft nichts von sich aus auf (ADR-0005)', () {
      // Die frühere Zusage war stärker: Ohne INTERNET-Berechtigung *konnte*
      // nichts hinaus. Mit dem Expertenmodus ist die Berechtigung da, und
      // was bleibt, ist diese engere Aussage — AXIOM lauscht, ruft aber nie.
      // Ohne diesen Test wäre sie eine Absichtserklärung.
      final hits = <String>[];
      for (final file in appSources()) {
        final content = file.readAsStringSync();
        for (final forbidden in [
          "import 'dart:html'",
          'package:http/',
          'HttpClient(',
          'Socket.connect',
          'WebSocket.connect',
          // Auch ohne Verbindung: Wer ein Paket verschickt, ruft etwas
          // auf. Die eine erlaubte Ausnahme steht im Test darunter.
          'RawDatagramSocket.bind',
        ]) {
          if (file.path.endsWith('server/mdns_responder.dart') &&
              forbidden == 'RawDatagramSocket.bind') {
            continue;
          }
          if (content.contains(forbidden)) {
            hits.add('${file.path}: $forbidden');
          }
        }
      }
      expect(hits, isEmpty,
          reason: 'Ausgehender Netzwerkzugriff gefunden:\n${hits.join("\n")}');
    });

    test('der Expertenmodus startet nur mit der App, nie von selbst', () {
      // ADR-0005 §3b erlaubt genau einen Weg: den, der laeuft, wenn der
      // Nutzer die App oeffnet. Ein Start aus einem Dienst, einem Empfaenger
      // oder beim Hochfahren waere ein Port, der aufgeht, ohne dass jemand
      // davon weiss.
      final starters = appSources()
          .where((f) => f.readAsStringSync().contains('expertModeProvider.notifier).start()'))
          .map((f) => f.path)
          .toList();
      for (final path in starters) {
        expect(
          path.endsWith('platform/intent_handler.dart') ||
              path.endsWith('screens/expert_screen.dart'),
          isTrue,
          reason: '$path startet den Server — erlaubt sind nur der '
              'App-Start und der Schalter im Expertenmodus',
        );
      }
      // Und der BootReceiver darf ihn nicht kennen.
      expect(
        File('android/app/src/main/kotlin/de/atomfritte/axiom/BootReceiver.kt')
            .readAsStringSync(),
        isNot(contains('Expert')),
      );
    });

    test('genau eine Datei darf etwas ins Netz schicken', () {
      // mDNS sendet — damit ist es die einzige Stelle, an der AXIOM von
      // sich aus ein Paket verschickt. Die Zusage aus ADR-0005 bleibt
      // trotzdem gehalten, aber nur unter drei Bedingungen, und die
      // stehen hier als Test, nicht als Absichtserklaerung:
      //
      //   1. link-lokale Multicast-Adresse (kein Router leitet sie weiter)
      //   2. nur Name und IP dieses Geraets, keine Nutzdaten
      //   3. nur solange der Expertenmodus laeuft
      final senders = appSources()
          .where((f) => f.readAsStringSync().contains('RawDatagramSocket'))
          .map((f) => f.path)
          .toList();
      expect(senders, hasLength(1));
      expect(senders.single, endsWith('server/mdns_responder.dart'));

      final source = File(senders.single).readAsStringSync();
      // Nur an die feste Gruppe aus RFC 6762, an keine andere Adresse.
      final targets = RegExp(r'InternetAddress\(([^)]*)\)')
          .allMatches(source)
          .map((m) => m.group(1)!.trim())
          .toSet();
      expect(targets, {'kMdnsGroup'},
          reason: 'Ein anderes Ziel als die Multicast-Gruppe wäre eine '
              'ausgehende Verbindung');
      expect(source, contains("kMdnsGroup = '224.0.0.251'"));
      // Der Abschied beim Beenden gehoert dazu: Ohne ihn zeigt der Name
      // noch minutenlang auf ein Geraet, das nicht mehr lauscht.
      expect(source, contains('ttl: 0'));
    });

    test('der lauschende Server ist die einzige Netzwerkstelle', () {
      // Genau eine Datei darf einen Socket öffnen, und auch die nur
      // lauschend. Wächst diese Liste, ist das eine Entscheidung und kein
      // Versehen.
      final binding = appSources()
          .where((f) => f.readAsStringSync().contains('HttpServer.bind'))
          .map((f) => f.path)
          .toList();
      expect(binding, hasLength(1));
      expect(binding.single, endsWith('server/expert_server.dart'));
    });
  });
}
