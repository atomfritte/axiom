/// Prüft die Hilfe — den Darsteller, die Navigation und die Speicherfreigabe.
///
/// **Warum die Speicherfreigabe hier einen eigenen Abschnitt hat.** Sie ist
/// die einzige Anforderung an diese Ansicht, die man beim Benutzen nicht
/// bemerkt: Eine Hilfe, die dreizehn Megabyte je angesehenem Bild behält,
/// sieht genauso aus wie eine, die aufräumt — bis die App im Hintergrund
/// weggeräumt wird und der erfasste Gedanke weg ist [D9]. Was man nicht
/// sieht, muss ein Test halten.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:axiom_app/design/theme.dart';
import 'package:axiom_app/design/widgets/prose.dart';
import 'package:axiom_app/i18n/i18n.dart';
import 'package:axiom_app/screens/help_screen.dart';

import 'harness.dart';

/// Eigene Testvorlage — bewusst nicht der ausgelieferte Hilfetext.
///
/// Der Darsteller muss gegen das geprüft werden, was er können soll, nicht
/// gegen das, was gerade zufällig in `assets/help/` steht. Sonst fällt der
/// Test um, wenn jemand einen Absatz umformuliert, und schweigt, wenn eine
/// Auszeichnung wegfällt.
const _fixture = '''
# Der Zustand

Ein Absatz mit **fettem** Wort und `load_index` als Code.
Diese Zeile gehört noch zum selben Absatz.

## Die sechs Werte

- Kapazität
- Schlafschuld

1. Erst messen
2. Dann rechnen

> Ein Messwert, kein Urteil.

| Wert | Bedeutung |
|---|---|
| L0 | Normalbetrieb |

![Sechs Werte, jeder mit einer Ablesung.](img/zustand.webp)

Mehr dazu in [Aufgaben](kapitel:06).

### Nachsatz

Ende.
''';

/// Was der Darsteller ausdrücklich nicht kennt.
const _unknown = '''
<b>HTML</b> bleibt stehen.

```dart
final x = 1;
```

Ein [externer Link](https://example.org) ist keiner.

  * verschachtelt
''';

String _plain(List<ProseBlock> blocks) {
  final buffer = StringBuffer();
  void spans(List<ProseSpan> list) {
    for (final span in list) {
      buffer.write(switch (span) {
        ProseRun(:final text) => text,
        ProseLink(:final label) => label,
      });
      buffer.write(' ');
    }
  }

  for (final block in blocks) {
    switch (block) {
      case ProseHeading(spans: final s):
        spans(s);
      case ProseParagraph(spans: final s):
        spans(s);
      case ProseQuote(spans: final s):
        spans(s);
      case ProseItems(:final items):
        for (final item in items) {
          spans(item);
        }
      case ProseTable(:final rows):
        for (final row in rows) {
          for (final cell in row) {
            spans(cell);
          }
        }
      case ProseImage(:final caption, :final path):
        buffer.write('$caption $path ');
    }
  }
  return buffer.toString();
}

/// Alle Kapitelsprünge eines Dokuments.
Iterable<ProseLink> _linksIn(List<ProseBlock> blocks) sync* {
  for (final block in blocks) {
    final spans = switch (block) {
      ProseHeading(:final spans) => spans,
      ProseParagraph(:final spans) => spans,
      ProseQuote(:final spans) => spans,
      ProseItems(:final items) => items.expand((i) => i).toList(),
      ProseTable(:final rows) =>
        rows.expand((r) => r.expand((c) => c)).toList(),
      ProseImage() => const <ProseSpan>[],
    };
    yield* spans.whereType<ProseLink>();
  }
}

Widget _wrapProse(Widget child, {Brightness brightness = Brightness.dark}) =>
    MediaQuery(
      data: const MediaQueryData(size: Size(412, 915), devicePixelRatio: 3),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAxiomTheme(brightness: brightness),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  group('Darsteller', () {
    test('erkennt genau den vereinbarten Umfang', () {
      final blocks = parseProse(_fixture);

      expect(
        blocks.whereType<ProseHeading>().map((h) => (h.level, h.plain)),
        containsAll(<(int, String)>[
          (1, 'Der Zustand'),
          (2, 'Die sechs Werte'),
          (3, 'Nachsatz'),
        ]),
      );

      final lists = blocks.whereType<ProseItems>().toList();
      expect(lists, hasLength(2));
      expect(lists.first.ordered, isFalse);
      expect(lists.first.items, hasLength(2));
      expect(lists.last.ordered, isTrue);

      expect(blocks.whereType<ProseQuote>(), hasLength(1));

      final table = blocks.whereType<ProseTable>().single;
      // Die Trennzeile |---|---| ist Auszeichnung, kein Inhalt.
      expect(table.rows, hasLength(2));
      expect(table.rows.first, hasLength(2));

      final image = blocks.whereType<ProseImage>().single;
      expect(image.path, 'img/zustand.webp');
      expect(image.caption, startsWith('Sechs Werte'));
    });

    test('genau eine H1 je Datei — und sie steht vorn', () {
      final blocks = parseProse(_fixture);
      final ones = blocks.whereType<ProseHeading>().where((h) => h.level == 1);
      expect(ones, hasLength(1));
      expect(blocks.first, isA<ProseHeading>());
    });

    test('weiche Zeilenumbrüche sind keine Absätze', () {
      final paragraph = parseProse(_fixture).whereType<ProseParagraph>().first;
      final text = _plain([paragraph]);
      expect(text, contains('Diese Zeile gehört noch zum selben Absatz.'));
    });

    test('fett, Code und Kapitelsprung werden erkannt', () {
      final spans = parseProseSpans(
        'Ein **fettes** Wort, `load_index` und [Aufgaben](kapitel:06).',
      );
      expect(
        spans.whereType<ProseRun>().any((r) => r.bold && r.text == 'fettes'),
        isTrue,
      );
      expect(
        spans.whereType<ProseRun>().any((r) => r.code && r.text == 'load_index'),
        isTrue,
      );
      final link = spans.whereType<ProseLink>().single;
      expect(link.chapter, '06');
      expect(link.label, 'Aufgaben');
    });

    test('fett, kursiv und Code sind drei verschiedene Spannen', () {
      final spans = parseProseSpans('**a** *b* `c`')
          .whereType<ProseRun>()
          .where((r) => r.text.trim().isNotEmpty)
          .toList();
      expect(spans, hasLength(3));
      expect((spans[0].text, spans[0].bold), ('a', true));
      expect((spans[1].text, spans[1].italic), ('b', true));
      expect((spans[2].text, spans[2].code), ('c', true));
      // Und keine Spanne trägt zwei Auszeichnungen gleichzeitig.
      expect(spans[0].italic, isFalse);
      expect(spans[1].bold, isFalse);
    });

    test('ein Navigationspfad wird genau einmal kursiv', () {
      final spans = parseProseSpans(
        'Wie es ausgefallen ist, steht unter *System → Erfassen*.',
      );
      final italics = spans.whereType<ProseRun>().where((r) => r.italic);
      expect(italics, hasLength(1));
      expect(italics.single.text, 'System → Erfassen');
    });

    test('das einzelne Sternchen frisst die Fettauszeichnung nicht', () {
      // Die Reihenfolge der Prüfungen ist die ganze Regel: Wird `*` vor `**`
      // erkannt, wird aus fettem Text ein Sternchen mit Kursivschrift.
      final spans = parseProseSpans('**Air Actions gibt es nicht.** Der Rest.');
      final bold = spans.whereType<ProseRun>().where((r) => r.bold);
      expect(bold, hasLength(1));
      expect(bold.single.text, 'Air Actions gibt es nicht.');
      expect(spans.whereType<ProseRun>().where((r) => r.italic), isEmpty);
    });

    test('was er nicht kennt, gibt er als Fließtext aus', () {
      final text = _plain(parseProse(_unknown));
      // Nichts verschluckt: Jedes Wort der Vorlage steht noch da.
      for (final word in [
        'HTML',
        'bleibt',
        'final',
        'externer',
        'Link',
        'verschachtelt',
      ]) {
        expect(text, contains(word), reason: '"$word" ist verschwunden');
      }
      // Und ein externes Ziel wird nicht zu einem Kapitelsprung umgedeutet.
      expect(parseProse(_unknown).whereType<ProseLink>(), isEmpty);
      for (final block in parseProse(_unknown)) {
        if (block case ProseParagraph(:final spans)) {
          expect(spans.whereType<ProseLink>(), isEmpty);
        }
      }
    });

    test('wirft nie — auch nicht bei kaputter Auszeichnung', () {
      const broken = [
        '',
        '#',
        '####### zu tief',
        '**offen',
        '`offen',
        '[ohne Ziel](',
        '![ohne Klammer](img/x.webp',
        '|',
        '||||',
        '> ',
        '- ',
        '1.',
      ];
      for (final source in broken) {
        expect(() => parseProse(source), returnsNormally, reason: source);
      }
    });
  });

  group('Optik', () {
    testWidgets('stellt Überschrift, Liste, Tabelle und Zitat dar', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapProse(ProseView(blocks: parseProse(_fixture))),
      );
      await tester.pump();

      expect(
        find.textContaining('Der Zustand', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Normalbetrieb', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Ein Messwert, kein Urteil.', findRichText: true),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ein Kapitelsprung meldet die Nummer', (tester) async {
      String? opened;
      await tester.pumpWidget(
        _wrapProse(
          ProseView(
            blocks: parseProse('[Aufgaben](kapitel:6)'),
            onChapter: (c) => opened = c,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.textContaining('Aufgaben', findRichText: true));
      await tester.pump();
      // Die Nummer kommt so, wie sie in der Datei steht; die Ansicht füllt
      // sie auf zwei Stellen auf.
      expect(normalizeChapter(opened ?? ''), '06');
    });

    test('keine eigenen Farben und keine eigenen Größen', () {
      // Die Hilfe soll aussehen wie der Rest der App. Eine eigene Farbe hier
      // ist der Anfang eines zweiten Designsystems.
      final source = File('lib/design/widgets/prose.dart').readAsStringSync();
      expect(source, isNot(contains('Color(0x')));
      expect(source, isNot(contains('Colors.')));
      expect(
        source,
        contains('Theme.of(context).textTheme'),
        reason: 'Typografie kommt aus dem Theme, nicht aus dieser Datei',
      );
    });

    test('kein Markdown-Paket', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, isNot(contains('markdown')));
      expect(pubspec, isNot(contains('flutter_html')));
    });
  });

  group('Speicher', () {
    setUp(imageCache.clear);

    test('Bilder werden nicht in voller Auflösung dekodiert', () {
      const phone = MediaQueryData(size: Size(412, 915), devicePixelRatio: 3);
      const tablet = MediaQueryData(size: Size(1280, 800), devicePixelRatio: 2);

      // Der Deckel greift auf beiden Geräten — ein Bildschirmfoto braucht
      // keine Bildschirmbreite, um lesbar zu sein.
      expect(proseDecodeWidth(phone), (kProseImageMaxWidth * 3).round());
      expect(proseDecodeWidth(tablet), (kProseImageMaxWidth * 2).round());
      // Und nie die volle Bildbreite: 1240 px kosten dekodiert rund 13 MB.
      expect(proseDecodeWidth(tablet), lessThan(1240));
    });

    testWidgets('gibt dekodierte Bilder frei, wenn die Hilfe geht', (
      tester,
    ) async {
      const media = MediaQueryData(size: Size(412, 915), devicePixelRatio: 3);
      final width = proseDecodeWidth(media);
      // Genau der Schlüssel, unter dem `Image.asset(cacheWidth: …)` ablegt.
      final provider = ResizeImage.resizeIfNeeded(
        width,
        null,
        const AssetImage('assets/help/img/zustand.webp'),
      );

      await tester.pumpWidget(
        _wrapProse(
          ProseView(blocks: parseProse('![Zustand](img/zustand.webp)')),
        ),
      );
      await tester.pump();

      // Ein dekodiertes Bild vortäuschen. Echtes Dekodieren im Widget-Test
      // ist unzuverlässig; geprüft wird ohnehin die Freigabe, nicht das
      // Dekodieren.
      final key = await tester.runAsync(
        () => provider.obtainKey(ImageConfiguration.empty),
      );
      final image = await tester.runAsync(
        () => createTestImage(width: 4, height: 4),
      );
      imageCache.putIfAbsent(
        key!,
        () => OneFrameImageStreamCompleter(
          SynchronousFuture(ImageInfo(image: image!)),
        ),
      );
      expect(imageCache.containsKey(key), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );

      expect(
        imageCache.containsKey(key),
        isFalse,
        reason: 'Ein dekodiertes Bild überlebt sonst die Ansicht, die es '
            'gezeigt hat — und kostet rund 13 MB',
      );
    });

    test('der Darsteller deckelt die Dekodiergröße und gibt sie frei', () {
      final source = File('lib/design/widgets/prose.dart').readAsStringSync();
      expect(source, contains('cacheWidth:'));
      expect(source, contains('.evict('));
      expect(
        RegExp(r'void dispose\(\)[\s\S]{0,400}_release\(\)').hasMatch(source),
        isTrue,
        reason: 'Die Freigabe muss am Abbau hängen, nicht an einer Geste',
      );
    });

    test('kein Provider hält den Hilfetext', () {
      final providers = File('lib/state/providers.dart').readAsStringSync();
      expect(
        providers.toLowerCase(),
        isNot(contains('help')),
        reason: 'Ein Provider überlebt den Bildschirm — genau das soll der '
            'Text nicht',
      );

      final screen = File('lib/screens/help_screen.dart').readAsStringSync();
      for (final long in ['FutureProvider', 'NotifierProvider', 'StateProvider']) {
        expect(screen, isNot(contains(long)));
      }
      // `rootBundle` behält jede gelesene Datei, wenn man ihn lässt. Ohne
      // `cache: false` wäre jede Freigabe Buchhaltung ohne Wirkung.
      expect(
        RegExp(r'loadString\([\s\S]{0,120}?cache:\s*false')
            .allMatches(screen)
            .length,
        equals('loadString('.allMatches(screen).length),
        reason: 'Jede Ladestelle muss den Bundle-Cache umgehen',
      );
    });

    test('die Zeit in der Hilfe zählt nicht auf das Meta-Work-Budget', () {
      // Nachlesen ist das Gegenteil von Schrauben: Wer die Hilfe liest,
      // ändert nichts. Steht diese Zeile eines Tages falsch herum, war es
      // eine Entscheidung und kein Versehen.
      final screen = File('lib/screens/help_screen.dart').readAsStringSync();
      expect(screen, isNot(contains("state/meta_time.dart")));
      expect(screen, isNot(contains('MetaTimedScope(')));
      expect(screen, isNot(contains('logScreenTime')));
      // Und die Begründung steht daneben, damit die Zeile nicht eines Tages
      // als vergessene Verdrahtung „nachgetragen" wird.
      expect(screen, contains('Meta-Work-Budget'));
    });
  });

  group('Kapitel', () {
    test('Nummern werden auf zwei Stellen gebracht', () {
      expect(normalizeChapter('6'), '06');
      expect(normalizeChapter('06'), '06');
      expect(normalizeChapter(' 13 '), '13');
    });

    test('ohne englische Fassung gilt die deutsche — sichtbar', () {
      const chapter = HelpChapter(
        number: '09',
        slug: 'regelwerk',
        assetDe: 'assets/help/de/09-regelwerk.md',
      );
      expect(chapter.assetFor(AppLanguage.en), 'assets/help/de/09-regelwerk.md');
      expect(chapter.translated(AppLanguage.en), isFalse);
      expect(chapter.translated(AppLanguage.de), isTrue);

      const translated = HelpChapter(
        number: '09',
        slug: 'regelwerk',
        assetDe: 'assets/help/de/09-regelwerk.md',
        assetEn: 'assets/help/en/09-regelwerk.md',
      );
      expect(
        translated.assetFor(AppLanguage.en),
        'assets/help/en/09-regelwerk.md',
      );
      expect(translated.translated(AppLanguage.en), isTrue);
    });

    test('das Verzeichnis kommt aus dem Asset-Manifest', () async {
      final chapters = await loadHelpChapters();
      if (chapters.isEmpty) return; // Hilfetexte noch nicht mitgeliefert
      expect(chapters.first.number, '00');
      expect(chapters.map((c) => c.number), everyElement(hasLength(2)));
      // Sortiert, sonst führt „Weiter" irgendwohin.
      final numbers = chapters.map((c) => c.number).toList();
      expect(numbers, orderedEquals([...numbers]..sort()));
    });

    test('die Suche liest und lässt wieder los', () async {
      final chapters = await loadHelpChapters();
      if (chapters.isEmpty) return;

      final hits = await searchHelp(chapters, 'Kapazität', AppLanguage.de);
      expect(hits, isNotEmpty);
      expect(hits.every((h) => h.number != '00'), isTrue);
      // Ein Treffer trägt nur seinen Ausschnitt, nicht das Kapitel.
      expect(hits.every((h) => h.snippet.length <= 200), isTrue);
      // Und keine Auszeichnungszeichen: Eine Trefferliste ist kein Quelltext.
      expect(hits.every((h) => !h.snippet.contains('*')), isTrue);
      expect(hits.every((h) => !h.snippet.contains('](')), isTrue);

      expect(
        await searchHelp(chapters, 'Quallenzucht', AppLanguage.de),
        isEmpty,
      );
      // Zu kurz zu suchen lohnt nicht — und lädt deshalb auch nichts.
      expect(await searchHelp(chapters, 'a', AppLanguage.de), isEmpty);
    });

    /// Die Kapitel schreibt jemand anders als den Darsteller. Diese Prüfung
    /// hält die Naht zwischen beiden: keine Textbehauptungen, nur das, was
    /// stimmen muss, damit die Hilfe benutzbar bleibt.
    test('jedes ausgelieferte Kapitel lässt sich darstellen', () async {
      final chapters = await loadHelpChapters();
      if (chapters.isEmpty) return;

      for (final chapter in chapters) {
        for (final language in AppLanguage.values) {
          final source = await rootBundle.loadString(
            chapter.assetFor(language),
            cache: false,
          );
          final blocks = parseProse(source);
          final where = '${chapter.number} (${language.code})';

          expect(blocks, isNotEmpty, reason: where);

          // Kein Auszeichnungszeichen bleibt sichtbar stehen. Genau das war
          // der Fehler, als der Darsteller `*kursiv*` noch nicht kannte:
          // Die Sternchen standen im Text und sahen aus wie Tippfehler.
          expect(
            _plain(blocks),
            isNot(contains('*')),
            reason: 'unerkannte Auszeichnung in $where',
          );

          expect(
            blocks.whereType<ProseHeading>().where((h) => h.level == 1),
            hasLength(1),
            reason: 'genau eine H1 je Datei — $where',
          );

          // Jeder Sprung zeigt auf ein Kapitel, das es gibt. Eine tote
          // Verknüpfung in einer Hilfe ist schlimmer als keine.
          for (final link in _linksIn(blocks)) {
            expect(
              findChapter(chapters, normalizeChapter(link.chapter)),
              isNotNull,
              reason: '$where → kapitel:${link.chapter}',
            );
          }

          // Und jedes Bild liegt wirklich im Bündel.
          for (final image in blocks.whereType<ProseImage>()) {
            await expectLater(
              rootBundle.load('assets/help/${image.path}'),
              completes,
              reason: '$where → ${image.path}',
            );
          }
        }
      }
    });
  });

  group('Ansicht', () {
    late TestHarness h;

    setUp(() {
      h = TestHarness.create();
      h.completeOnboarding();
    });
    tearDown(() => h.dispose());

    testWidgets('zeigt die Übersicht und öffnet ein Kapitel', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(h.wrap(const HelpScreen()));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();

      if (find.textContaining('Inhalt', findRichText: true).evaluate().isEmpty) {
        return; // Hilfetexte noch nicht mitgeliefert
      }

      // Am linken Rand tippen, nicht in die Mitte: Die Zeile ist
      // „[Zustand](kapitel:05) — Kapazität, Last …", und nur der Anfang ist
      // der Sprung.
      final link = find.textContaining('Zustand', findRichText: true).first;
      await tester.tapAt(tester.getTopLeft(link) + const Offset(10, 10));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HelpChapterScreen), findsOneWidget);

      // Am Fuß steht, wo es weitergeht — erreichbar, ohne die Ansicht zu
      // verlassen.
      await tester.scrollUntilVisible(
        find.text('Übersicht'),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.textContaining('Kapitel '), findsWidgets);
      await unmount(tester);
    });
  });
}
