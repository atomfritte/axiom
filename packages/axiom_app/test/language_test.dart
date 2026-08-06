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

/// Der Quelltext einer Datei ohne Kommentare.
///
/// Kommentare sind Entwicklerprosa — sie dürfen veralten, ohne dass ein
/// Nutzer je etwas Falsches liest. Wo ein Test eine *Zusage an den Nutzer*
/// prüft, gehören sie deshalb nicht dazu. [userFacingStrings] macht denselben
/// Schnitt, gibt aber nur kurze Literale ohne Punkt und Schrägstrich zurück —
/// ganze Sätze fallen dort durch.
String codeWithoutComments(File file) {
  final out = StringBuffer();
  var inBlockComment = false;
  for (var line in file.readAsLinesSync()) {
    if (inBlockComment) {
      final end = line.indexOf('*/');
      if (end == -1) continue;
      line = line.substring(end + 2);
      inBlockComment = false;
    }
    final blockStart = line.indexOf('/*');
    if (blockStart != -1) {
      inBlockComment = !line.substring(blockStart).contains('*/');
      line = line.substring(0, blockStart);
    }
    // `//` zählt nur als Kommentarbeginn, wenn kein Doppelpunkt davorsteht —
    // sonst verschwindet jede URL, die in einem Literal steht.
    final slash = RegExp(r'(?<!:)//').firstMatch(line);
    if (slash != null) line = line.substring(0, slash.start);
    out.writeln(line);
  }
  return out.toString();
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
    /// Alles, was von sich aus hinausginge.
    ///
    /// Die Liste ist nach **Richtung** geschnitten, nicht nach Stichwort:
    /// `WebSocket.connect` baut eine Verbindung auf und ist verboten;
    /// `WebSocketTransformer.upgrade` nimmt eine an, die der Browser
    /// aufgebaut hat, und ist erlaubt (ADR-0005 — AXIOM lauscht, ruft nie).
    /// Ein Test, der jedes Vorkommen von „WebSocket" verböte, wäre beim Bau
    /// der Verbindungsanzeige abgeschaltet worden — und hätte danach auch
    /// den Verbindungsaufbau nicht mehr gefangen.
    const outgoing = [
      "import 'dart:html'",
      'package:http/',
      'HttpClient(',
      'Socket.connect',
      'WebSocket.connect',
      // Ein Client-Paket käme an der Zeile darüber vorbei: Dort heißt der
      // Aufbau `IOWebSocketChannel.connect`. Ohne diesen Eintrag ließe sich
      // die Zusage mit einer Abhängigkeit umgehen.
      'WebSocketChannel.connect',
      'package:web_socket_channel',
      // Auch ohne Verbindung: Wer ein Paket verschickt, ruft etwas
      // auf. Die eine erlaubte Ausnahme steht im Test darunter.
      'RawDatagramSocket.bind',
      // `basic_utils` liefert dem Expertenmodus die Zertifikatserzeugung
      // (`X509Utils`, `CryptoUtils`) — sein Sammelmodul exportiert aber auch
      // `HttpUtils` (ein `package:http`-Client) und `DnsUtils` (DNS über
      // HTTPS gegen dns.google.com und cloudflare-dns.com). Beides steht
      // damit im Namensraum jeder Datei, die das Sammelmodul importiert.
      // Die Zeilen darüber greifen dort nicht: Im eigenen Quelltext stünde
      // kein `package:http/`, nur ein Aufruf. Also den Aufruf verbieten.
      'HttpUtils.',
      'DnsUtils.',
    ];

    test('AXIOM ruft nichts von sich aus auf (ADR-0005)', () {
      // Die frühere Zusage war stärker: Ohne INTERNET-Berechtigung *konnte*
      // nichts hinaus. Mit dem Expertenmodus ist die Berechtigung da, und
      // was bleibt, ist diese engere Aussage — AXIOM lauscht, ruft aber nie.
      // Ohne diesen Test wäre sie eine Absichtserklärung.
      final hits = <String>[];
      for (final file in appSources()) {
        final content = file.readAsStringSync();
        for (final forbidden in outgoing) {
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

    test('die Regel lässt die Annahme durch und fängt den Aufbau', () {
      // Der Wächter selbst geprüft, wie bei der Schuldsprache: Ein Test, der
      // die richtige Richtung mitverbietet, wird beim ersten Bedarf
      // abgeschaltet — und fängt danach gar nichts mehr.
      bool flagged(String line) => outgoing.any(line.contains);

      expect(flagged("await WebSocket.connect('wss://irgendwo')"), isTrue);
      expect(flagged('IOWebSocketChannel.connect(uri)'), isTrue);
      expect(flagged("import 'package:web_socket_channel/io.dart';"), isTrue);
      // Der Weg über das Sammelmodul von `basic_utils`, der bis hierher an
      // allen Einträgen vorbeikam.
      expect(flagged("DnsUtils.lookupRecord('exfil.example.com')"), isTrue);
      expect(flagged("HttpUtils.postForFullResponse(url: 'https://x.test')"),
          isTrue);
      // Und das, was der Expertenmodus tatsächlich tut, bleibt erlaubt.
      expect(flagged('await WebSocketTransformer.upgrade(request)'), isFalse);
      expect(flagged('WebSocketTransformer.isUpgradeRequest(request)'), isFalse);
      expect(flagged('X509Utils.generateSelfSignedCertificate(k, s, 3650)'),
          isFalse);
      expect(flagged('CryptoUtils.generateRSAKeyPair(keySize: 2048)'), isFalse);
    });

    test('kein Netzwerkpaket als direkte Abhängigkeit (ADR-0005)', () {
      // Vorher hing die Zusage allein an einer Wortsuche im eigenen
      // Quelltext. Damit war sie über eine Abhängigkeit zu umgehen, ohne
      // eine einzige verbotene Zeile zu schreiben — genau das ist mit
      // `basic_utils` passiert, das `package:http` mitbringt. Der Aufruf ist
      // oben verboten; hier steht die zweite Hälfte: Wer einen Client als
      // *direkte* Abhängigkeit aufnimmt, hat das entschieden und nicht
      // übersehen. `http` als transitiver Eintrag bleibt erlaubt und ist in
      // README und ADR-0005 offen benannt.
      const clients = [
        'http',
        'http2',
        'dio',
        'grpc',
        'web_socket_channel',
        'socket_io_client',
        'universal_html',
      ];

      final direct = <String>{};
      var inDependencies = false;
      for (final line in File('pubspec.yaml').readAsLinesSync()) {
        if (RegExp(r'^\S').hasMatch(line)) {
          inDependencies = line.startsWith('dependencies:');
          continue;
        }
        if (!inDependencies) continue;
        final name = RegExp(r'^  ([a-z_0-9]+):').firstMatch(line)?.group(1);
        if (name != null) direct.add(name);
      }
      expect(direct, isNotEmpty, reason: 'pubspec.yaml nicht gelesen');
      expect(
        direct.intersection(clients.toSet()),
        isEmpty,
        reason: 'Ein Netzwerk-Client als direkte Abhängigkeit widerspricht '
            'ADR-0005. Wenn das gewollt ist, gehört es dort begründet.',
      );

      // Und die Gegenprobe: `http` liegt weiterhin nur transitiv im Baum.
      // Wechselt der Eintrag auf "direct", ist die Zusage in README.md und
      // ADR-0005 neu zu schreiben — nicht der Test.
      final lock = File('pubspec.lock').readAsStringSync();
      final entry = RegExp(r'\n  http:\n    dependency: (\w+)').firstMatch(lock);
      if (entry != null) expect(entry.group(1), 'transitive');
    });

    test('einen WebSocket nimmt genau eine Datei entgegen', () {
      // Dieselbe Buchführung wie beim lauschenden Server: Die Annahme einer
      // Aufwertung ist erlaubt, aber nicht überall. Wächst diese Liste, ist
      // das eine Entscheidung und kein Versehen.
      final accepting = appSources()
          .where((f) => f.readAsStringSync().contains('WebSocketTransformer'))
          .map((f) => f.path)
          .toList();
      expect(accepting, hasLength(1));
      expect(accepting.single, endsWith('server/expert_server.dart'));
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

    test('kein Text bestreitet eine Berechtigung, die im Manifest steht', () {
      // Die Datenquellen-Karte sagte dem Nutzer zu, AXIOM habe keine
      // Berechtigung fuers Netz — waehrend das Manifest `INTERNET`
      // deklariert und der laufende Expertenmodus dieselben Health-Connect-
      // Ereignisse ueber `GET /api/events` ausliefert. Eine falsche
      // Datenschutzzusage, und ausgerechnet auf dem Schirm fuer
      // Gesundheitsdaten.
      //
      // Der Test liest die Regel nicht aus einer Liste, sondern aus dem
      // Manifest: Solange dort INTERNET steht, darf kein Nutzertext das
      // Gegenteil behaupten. Verschwindet die Berechtigung wieder, wird die
      // alte Zusage wahr — und dieser Test tritt von selbst zurueck.
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync()
              // Der Kommentarkopf nennt die Berechtigung samt Begruendung.
              .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
      if (!manifest.contains('android.permission.INTERNET')) return;

      const denials = [
        'keine Netzwerkberechtigung',
        'ohne Netzwerkberechtigung',
        'keine Netzwerk-Berechtigung',
        'keine INTERNET-Berechtigung',
        'no network permission',
        'without network permission',
      ];
      final hits = <String>[];
      // Wie bei Schuldsprache und Umlauten: Die englische Fassung folgt dem
      // deutschen Schluessel und wird von i18n_test geprueft — dort faellt
      // ein Eintrag ohne deutsche Entsprechung auf.
      for (final file
          in appSources().where((f) => !f.path.endsWith('i18n/en.dart'))) {
        final code = codeWithoutComments(file);
        for (final denial in denials) {
          if (code.contains(denial)) hits.add('${file.path}: "$denial"');
        }
      }
      expect(hits, isEmpty,
          reason: 'Das Manifest deklariert INTERNET (ADR-0005). Was bleibt, '
              'ist die engere Zusage — AXIOM lauscht, ruft aber nichts von '
              'sich aus auf:\n${hits.join("\n")}');
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
