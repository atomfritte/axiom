/// Prüft die Zweisprachigkeit — auf Vollständigkeit und auf Ton.
///
/// **Warum am Quelltext und nicht an einzelnen Screens.** Eine fehlende
/// Übersetzung fällt beim Klicken erst auf, wenn man genau diesen Zustand
/// erwischt: den Erhaltungsmodus, den abgelaufenen Cooldown, den Fehlerfall.
/// Genau die sieht man beim Durchklicken nie. Der Quelltext kennt sie alle.
///
/// **Und auf Ton, weil eine Übersetzung ihn verlieren kann.** „Nichts in
/// Reichweite" ist eine bewusste Formulierung gegen „Du hast 14 offene
/// Aufgaben". Ein englischer Satz, der daraus „You still have…" macht, wäre
/// technisch korrekt und inhaltlich das Gegenteil (D10, R7).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:axiom_app/design/tokens.dart';
import 'package:axiom_app/i18n/en.dart';
import 'package:axiom_app/i18n/i18n.dart';

/// Ein Literal, ggf. aus mehreren benachbarten zusammengesetzt.
final _literal = RegExp(r"'(?:[^'\\\n]|\\.)*'");
final _call = RegExp(r"(?:\.t|translate)\(\s*(?:[A-Za-z_][\w.]*\s*,\s*)?");

/// Alle Texte, die im Quelltext durch die Übersetzung laufen.
Set<String> translatedSources() {
  final found = <String>{};
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.contains('/i18n/'));

  for (final file in files) {
    final src = file.readAsStringSync();
    for (final call in _call.allMatches(src)) {
      // Ab dem Aufruf die Kette benachbarter Literale einsammeln.
      var pos = call.end;
      final parts = <String>[];
      while (true) {
        final match = _literal.matchAsPrefix(src, pos);
        if (match == null) break;
        parts.add(match.group(0)!.substring(1, match.group(0)!.length - 1));
        pos = match.end;
        // Leerraum und Zeilenumbrüche zwischen den Teilen überspringen.
        final ws = RegExp(r'\s*').matchAsPrefix(src, pos);
        if (ws == null) break;
        pos = ws.end;
      }
      if (parts.isEmpty) continue;
      // Der Quelltext enthaelt Escapes; zur Laufzeit ist der Schluessel der
      // aufgeloeste String. Ohne das hier meldet der Test jeden Text mit
      // Zeilenumbruch faelschlich als fehlend.
      found.add(_unescape(parts.join()));
    }
  }
  return found;
}

String _unescape(String source) => source
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\t', '\t')
    .replaceAll(r"\'", "'")
    .replaceAll(r'\$', r'$');

void main() {
  group('Vollständigkeit', () {
    test('jeder übersetzbare Text im Quelltext hat eine englische Fassung', () {
      final missing = translatedSources()
          .where((s) => !kEnglish.containsKey(s))
          .toList()
        ..sort();
      expect(
        missing,
        isEmpty,
        reason: 'Ohne Eintrag erscheint der deutsche Satz mitten im '
            'englischen Screen. Fehlend:\n${missing.join("\n")}',
      );
    });

    test('auch die Bezeichnungen der Aufzählungen', () {
      // Diese laufen als Variable durch die Uebersetzung
      // (`context.t(size.label)`) und sind im Quelltext nicht als Literal zu
      // finden. Der Scanner kann sie deshalb nicht sehen — sie muessen hier
      // von Hand aufgezaehlt werden, sonst faellt die Luecke erst auf, wenn
      // ein englischer Screen "Gedämpft" anzeigt.
      final labels = [
        ...AppLanguage.values.map((l) => l.label),
        ...TextSize.values.map((t) => t.label),
        ...AxiomScheme.values.map((s) => s.label),
      ];
      final missing = labels
          .where((l) => l != 'Deutsch' && l != 'English')
          .where((l) => !kEnglish.containsKey(l))
          .toList();
      expect(missing, isEmpty, reason: 'Fehlend: ${missing.join(", ")}');
    });

    test('kein Eintrag ohne Verwendung', () {
      // Karteileichen sind harmlos, aber sie taeuschen Abdeckung vor: Man
      // sieht 550 Zeilen und glaubt, alles sei uebersetzt.
      final used = translatedSources();
      // Kern-Saetze und Betriebssystemtexte stehen nicht im App-Quelltext.
      const fromCoreOrSystem = 24;
      final unused = kEnglish.keys.where((k) => !used.contains(k)).length;
      expect(unused, lessThanOrEqualTo(kEnglish.length ~/ 4 + fromCoreOrSystem));
    });
  });

  group('Platzhalter', () {
    test('deutsche und englische Fassung haben dieselben Platzhalter', () {
      final placeholder = RegExp(r'\{\d+\}');
      final broken = <String>[];
      kEnglish.forEach((de, en) {
        final a = placeholder.allMatches(de).map((m) => m.group(0)!).toSet();
        final b = placeholder.allMatches(en).map((m) => m.group(0)!).toSet();
        if (a.length != b.length || !a.containsAll(b)) {
          broken.add('"$de" → "$en"');
        }
      });
      expect(broken, isEmpty,
          reason: 'Ein fehlender Platzhalter loescht eine Zahl aus dem '
              'Satz, ein zusaetzlicher zeigt "{1}" an:\n${broken.join("\n")}');
    });
  });

  group('Ton bleibt erhalten', () {
    /// Dieselbe Prüfung wie im Deutschen, in der Zielsprache.
    /// Eine Übersetzung kann aus einem Messwert unbemerkt ein Urteil machen.
    const blame = [
      'you failed',
      'you should',
      'you still have',
      // Nicht das blosse "again": Es steckt in "check again" und meint dort
      // nichts. Vorwurf traegt erst die Verbindung mit einer Person oder
      // einer Wiederholung, die als Versaeumnis gelesen wird.
      'yet again',
      'once again you',
      'still not',
      'lazy',
      'streak',
      'don’t forget',
      'at least you',
      'finally',
    ];

    test('keine Schuldsprache in der englischen Fassung', () {
      final hits = <String>[];
      kEnglish.forEach((de, en) {
        final lower = en.toLowerCase();
        for (final word in blame) {
          // Wortgrenzen, sonst trifft "again" auch "against".
          if (!RegExp('\\b${RegExp.escape(word)}\\b').hasMatch(lower)) {
            continue;
          }
          // Verneinte Nennungen sind erwuenscht: Das Onboarding sagt
          // ausdruecklich zu, was AXIOM *nicht* tut.
          final before = lower.substring(0, lower.indexOf(word));
          if (RegExp(r'\b(no|never|without|not)\b').hasMatch(before)) continue;
          hits.add('"$en" → "$word"');
        }
      });
      expect(hits, isEmpty, reason: 'Schuldsprache:\n${hits.join("\n")}');
    });

    test('erkennt Schuldsprache, wenn sie auftaucht', () {
      // Der Waechter muss selbst ueberwacht werden.
      const bad = 'you should finally do this';
      expect(
        blame.any((w) => RegExp('\\b${RegExp.escape(w)}\\b').hasMatch(bad)),
        isTrue,
      );
    });

    test('keine Ausrufezeichen-Motivation', () {
      final shouting = kEnglish.values.where((v) => v.contains('!')).toList();
      expect(shouting, isEmpty, reason: 'AXIOM ist ein Werkzeug, kein Coach.');
    });
  });

  group('Umschaltung', () {
    testWidgets('dieselbe Ansicht spricht Englisch', (tester) async {
      Widget probe(AppLanguage language) => MaterialApp(
            home: AxiomLanguage(
              language: language,
              child: Builder(
                builder: (context) => Text(context.t('Nichts in Reichweite')),
              ),
            ),
          );

      await tester.pumpWidget(probe(AppLanguage.de));
      expect(find.text('Nichts in Reichweite'), findsOneWidget);

      await tester.pumpWidget(probe(AppLanguage.en));
      await tester.pump();
      expect(find.text('Nothing in reach'), findsOneWidget);
      expect(find.text('Nichts in Reichweite'), findsNothing);
    });

    testWidgets('Platzhalter werden in beiden Sprachen gefüllt',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AxiomLanguage(
          language: AppLanguage.en,
          child: Builder(
            builder: (context) =>
                Text(context.t('{0} min über der geplanten Zeit.', [37])),
          ),
        ),
      ));
      expect(find.text('37 min past the planned time.'), findsOneWidget);
    });

    test('ohne Übersetzung erscheint der deutsche Satz, nicht der Schlüssel',
        () {
      const unknown = 'Ein Satz, den es nicht gibt';
      expect(translate(AppLanguage.en, unknown), unknown);
    });
  });
}
