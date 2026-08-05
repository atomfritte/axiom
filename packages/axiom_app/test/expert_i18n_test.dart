/// Die Weboberfläche spricht beide Sprachen — oder der Bau fällt um.
///
/// Dieselbe Zusage wie in `i18n_test.dart`, nur für `assets/expert/index.html`.
/// Sie steht getrennt, weil dort nichts von Flutters Werkzeug greift: Die
/// Oberfläche ist eine Datei, die ein Browser ausführt, und ein fest
/// verdrahteter deutscher Satz fällt darin durch jede Prüfung, die auf
/// Dart-Quelltext schaut. Genau so ist die Seite ein Jahr lang einsprachig
/// geblieben, während die App zwei Sprachen hatte.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Der Quelltext ohne Kommentare.
///
/// Ohne diesen Schritt zählt jedes Beispiel in einem Kommentar als Schlüssel
/// — die Erklärung von `tr()` nennt selbst einen, und der stünde dann als
/// fehlende Übersetzung da.
String stripComments(String source) {
  final withoutBlocks = source.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return withoutBlocks.replaceAll(RegExp(r'(?<![:"])//[^\n]*'), '');
}

void main() {
  final file = File('assets/expert/index.html');
  final html = file.readAsStringSync();
  final script = html.substring(html.indexOf('<script>'));
  final code = stripComments(script);

  /// Die Tabelle mit den englischen Fassungen.
  Map<String, String> englishTable() {
    final start = html.indexOf('const EN={');
    expect(start, isNot(-1), reason: 'Keine EN-Tabelle in index.html');
    final body = html.substring(start + 'const EN={'.length);
    final end = body.indexOf('\n};');
    expect(end, isNot(-1), reason: 'EN-Tabelle nicht geschlossen');

    final table = <String, String>{};
    final entry = RegExp(r'"((?:[^"\\]|\\.)*)":"((?:[^"\\]|\\.)*)",');
    for (final match in entry.allMatches(body.substring(0, end))) {
      table[unescape(match.group(1)!)] = unescape(match.group(2)!);
    }
    return table;
  }

  /// Jeder Schlüssel, den die Seite nachschlägt.
  Set<String> usedKeys() {
    final keys = <String>{};
    for (final m in RegExp(r"tr\('((?:[^'\\]|\\.)*)'").allMatches(code)) {
      keys.add(unescape(m.group(1)!));
    }
    // Fester Text im Markup trägt den deutschen Satz im Attribut — dieselbe
    // Regel wie im Skript, nur an anderer Stelle.
    for (final m in RegExp(r'data-t(?:-title|-ph|-label)?="([^"]+)"')
        .allMatches(html)) {
      keys.add(m.group(1)!);
    }
    keys.remove('');
    return keys;
  }

  group('Weboberfläche des Expertenmodus', () {
    test('jeder Text hat eine englische Fassung', () {
      final missing = usedKeys().difference(englishTable().keys.toSet());
      expect(missing, isEmpty,
          reason: 'Ohne Übersetzung:\n${missing.join("\n")}');
    });

    test('keine Übersetzung ohne Text', () {
      // Eine Fassung ohne Aufrufer ist entweder ein Tippfehler im Schlüssel
      // oder ein Rest. Beides steht besser laut da als still.
      final orphans = englishTable().keys.toSet().difference(usedKeys());
      expect(orphans, isEmpty,
          reason: 'Übersetzt, aber nirgends benutzt:\n${orphans.join("\n")}');
    });

    test('dieselben Platzhalter auf beiden Seiten', () {
      // `{0}` ist die Stelle, an der ein Wert steht. Fehlt er in der
      // englischen Fassung, verschwindet eine Zahl; steht einer zu viel da,
      // erscheint „{1}" im Satz.
      final holes = RegExp(r'\{(\d+)\}');
      final wrong = <String>[];
      englishTable().forEach((de, en) {
        final a = holes.allMatches(de).map((m) => m.group(1)!).toSet();
        final b = holes.allMatches(en).map((m) => m.group(1)!).toSet();
        if (a.length != b.length || !a.containsAll(b)) wrong.add('$de → $en');
      });
      expect(wrong, isEmpty, reason: 'Platzhalter passen nicht:\n${wrong.join("\n")}');
    });

    test('kein deutscher Satz steht ungeschützt im Skript', () {
      // Der eigentliche Wächter. Ein Umlaut in einem Literal, das nicht
      // durch `tr()` geht, ist fast immer ein vergessener Nutzertext —
      // Bezeichner, Klassennamen und Selektoren dieser Datei kommen ohne
      // Umlaute aus.
      final loose = <String>[];
      for (final m in RegExp(r"(tr\()?'((?:[^'\\\n]|\\.)*)'").allMatches(code)) {
        if (m.group(1) != null) continue;
        final value = m.group(2)!;
        if (RegExp('[äöüÄÖÜß]').hasMatch(value)) loose.add(value);
      }
      expect(loose, isEmpty,
          reason: 'Nicht übersetzbar, weil nicht durch tr():\n'
              '${loose.join("\n")}');
    });

    test('die englische Fassung ist nicht die deutsche', () {
      // Ein kopierter deutscher Satz ist schlimmer als ein fehlender: Der
      // fehlende faellt auf, der kopierte sieht nach getaner Arbeit aus.
      // Ausgenommen sind Woerter, die in beiden Sprachen gleich lauten.
      const same = {
        'AUTO', 'INSTRUMENT', 'Board', 'Review', 'Check-in', 'Check-in (c)',
        'YAML', 'Start', 'Focus', 'Fokus', 'Status', 'Details', 'Server',
        'ENGLISH', 'IN {0} H', 'START {0}/10', 'KAPAZITÄT', 'LAST',
        '{0} (optional)',
      };
      final copied = <String>[];
      englishTable().forEach((de, en) {
        if (de == en && !same.contains(de)) copied.add(de);
        if (RegExp('[äöüÄÖÜß]').hasMatch(en)) copied.add('$de (Umlaut in EN)');
      });
      expect(copied, isEmpty,
          reason: 'Deutsch in der englischen Spalte:\n${copied.join("\n")}');
    });

    test('kein Vorwurf in der englischen Fassung', () {
      // Dieselbe Prüfung wie für die App (`language_test.dart`): Der Ton
      // ist eine Zusage und keine Geschmacksfrage. Eine Übersetzung ist die
      // klassische Stelle, an der er kippt — „you should", „you failed to".
      const forbidden = [
        'you should', 'you failed', 'you forgot', 'you did not', "you didn't",
        'again?', 'still not', 'lazy', 'excuse', 'no excuses',
      ];
      final hits = <String>[];
      englishTable().forEach((de, en) {
        final lower = en.toLowerCase();
        for (final word in forbidden) {
          if (lower.contains(word)) hits.add('$word → $en');
        }
      });
      expect(hits, isEmpty, reason: 'Schuldsprache:\n${hits.join("\n")}');
    });

    test('die Sprache kommt vom Telefon, nicht vom Browser', () {
      // Beide Oberflächen sollen dieselbe Sprache sprechen. Die
      // Browsersprache ist die Voreinstellung eines Arbeitsrechners und
      // sagt darüber nichts; sie ist nur die Vermutung, solange noch keine
      // Antwort da ist.
      expect(code, contains('setLanguage(S.language)'));
      expect(code, contains('setLanguage(data.language)'));
      expect(
        File('lib/server/expert_server.dart').readAsStringSync(),
        contains("'language': runtime.language"),
        reason: 'Der Server muss die Sprache mitliefern',
      );
    });
  });
}

/// Macht aus JSON-Escapes wieder Zeichen.
String unescape(String value) => value
    .replaceAll(r'\"', '"')
    .replaceAll(r"\'", "'")
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\\', r'\');
