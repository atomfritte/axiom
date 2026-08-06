/// Der Darsteller für die Hilfe — ein festgelegter Markdown-Ausschnitt.
///
/// **Warum kein Markdown-Paket.** `flutter_markdown` und seine Geschwister
/// können HTML, verschachtelte Listen, Fußnoten, Syntaxfärbung und externe
/// Links. Nichts davon kommt in den vierzehn Hilfetexten vor, und jede
/// dieser Fähigkeiten ist eine Stelle, an der die Hilfe anders aussieht als
/// der Rest der App. Eine Abhängigkeit für vierzehn Textdateien wäre
/// unverhältnismäßig; dieser Darsteller ist kleiner als die Konfiguration,
/// die man dem Paket sonst mitgeben müsste.
///
/// **Was er kennt** — und nichts darüber:
///
/// ```
/// # H1 (genau eine je Datei)      ## H2      ### H3
/// Fließtext mit **fett**, *kursiv* und `Code`
/// - Aufzählung
/// 1. Nummerierte Aufzählung
/// > Hervorgehobener Absatz
/// | Tabelle | mit | Pipes |
/// ![Bildunterschrift](img/jetzt.webp)
/// [Kapiteltitel](kapitel:06)
/// ```
///
/// Zwei Zusagen, die zusammengehören: Er **wirft nie** und er
/// **verschluckt nie etwas**. Was er nicht erkennt — HTML, ein Zaunfeld,
/// ein externer Link — erscheint als Fließtext, so wie es dasteht. Ein
/// stumm verschwundener Absatz wäre in einer Hilfe der schlimmste Fehler:
/// Man sucht dann nach einer Erklärung, die es zu geben scheint.
///
/// **Speicher.** Ein dekodiertes Bild aus dieser Hilfe kostet rund 13 MB
/// (1240×2754). Flutters `ImageCache` behält es, auch wenn das Widget
/// längst weg ist. Deshalb zwei Maßnahmen an dieser Stelle: `cacheWidth`
/// begrenzt schon das Dekodieren auf die Breite, in der das Bild wirklich
/// erscheint, und `dispose` gibt jedes gezeigte Bild wieder frei.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../theme.dart';
import '../tokens.dart';

// ── Modell ──────────────────────────────────────────────────────────────

/// Ein Textstück innerhalb einer Zeile.
sealed class ProseSpan {
  const ProseSpan();
}

/// Gewöhnlicher Text, ggf. fett, kursiv oder als Code gesetzt.
///
/// Kursiv trägt in den Kapiteln eine Bedeutung und ist keine Zierde: Es
/// trennt Navigationswege (*System → Systemcheck*) und Beschriftungen von
/// Bedienelementen vom Fließtext. Ohne diese Auszeichnung liest sich ein
/// Pfad wie ein Satzteil.
final class ProseRun extends ProseSpan {
  final String text;
  final bool bold;
  final bool italic;
  final bool code;
  const ProseRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.code = false,
  });
}

/// Sprung in ein anderes Kapitel: `[Titel](kapitel:06)`.
final class ProseLink extends ProseSpan {
  final String label;

  /// Kapitelnummer, wie sie im Dateinamen steht ("06").
  final String chapter;
  const ProseLink(this.label, this.chapter);
}

/// Ein Block — eine Überschrift, ein Absatz, eine Liste, eine Tabelle.
sealed class ProseBlock {
  const ProseBlock();
}

final class ProseHeading extends ProseBlock {
  /// 1, 2 oder 3.
  final int level;
  final List<ProseSpan> spans;

  /// Derselbe Text ohne Auszeichnung — für Sprungmarken und Vorlesefunktion.
  final String plain;
  const ProseHeading(this.level, this.spans, this.plain);
}

final class ProseParagraph extends ProseBlock {
  final List<ProseSpan> spans;
  const ProseParagraph(this.spans);
}

final class ProseItems extends ProseBlock {
  final bool ordered;
  final List<List<ProseSpan>> items;
  const ProseItems({required this.ordered, required this.items});
}

final class ProseQuote extends ProseBlock {
  final List<ProseSpan> spans;
  const ProseQuote(this.spans);
}

/// Erste Zeile ist die Kopfzeile.
final class ProseTable extends ProseBlock {
  final List<List<List<ProseSpan>>> rows;
  const ProseTable(this.rows);
}

final class ProseImage extends ProseBlock {
  /// So, wie es in der Datei steht — meist `img/jetzt.webp`.
  final String path;
  final String caption;
  const ProseImage(this.path, this.caption);
}

// ── Parser ──────────────────────────────────────────────────────────────

final _headingPattern = RegExp(r'^(#{1,3})\s+(.*)$');
final _imagePattern = RegExp(r'^!\[([^\]]*)\]\(([^)\s]+)\)$');
final _bulletPattern = RegExp(r'^[-*]\s+(.*)$');
final _orderedPattern = RegExp(r'^\d+[.)]\s+(.*)$');
final _rulePattern = RegExp(r'^:?-{3,}:?$');

/// Zerlegt eine Markdown-Datei in Blöcke. Wirft nicht.
List<ProseBlock> parseProse(String source) {
  final blocks = <ProseBlock>[];
  final lines = source.split(RegExp(r'\r?\n'));
  final paragraph = <String>[];

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    // Weiche Umbrüche in der Quelle sind Zeilenumbrüche im Editor, keine
    // Absätze — sonst zerfällt jeder von Hand umbrochene Text in Fetzen.
    blocks.add(ProseParagraph(parseProseSpans(paragraph.join(' '))));
    paragraph.clear();
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i].trim();

    if (line.isEmpty) {
      flushParagraph();
      i++;
      continue;
    }

    final image = _imagePattern.firstMatch(line);
    if (image != null) {
      flushParagraph();
      blocks.add(ProseImage(image.group(2)!, image.group(1)!));
      i++;
      continue;
    }

    final heading = _headingPattern.firstMatch(line);
    if (heading != null) {
      flushParagraph();
      final spans = parseProseSpans(heading.group(2)!.trim());
      blocks.add(
        // Der schmucklose Text kommt aus den Stücken, nicht aus der Zeile:
        // Sonst stünden in den Sprungmarken die Sternchen mit drin.
        ProseHeading(heading.group(1)!.length, spans, plainProse(spans)),
      );
      i++;
      continue;
    }

    if (line.startsWith('>')) {
      flushParagraph();
      final quoted = <String>[];
      while (i < lines.length && lines[i].trim().startsWith('>')) {
        quoted.add(lines[i].trim().substring(1).trim());
        i++;
      }
      blocks.add(ProseQuote(parseProseSpans(quoted.join(' '))));
      continue;
    }

    if (_bulletPattern.hasMatch(line) || _orderedPattern.hasMatch(line)) {
      flushParagraph();
      final ordered = _orderedPattern.hasMatch(line);
      final items = <List<ProseSpan>>[];
      while (i < lines.length) {
        final current = lines[i].trim();
        final match = ordered
            ? _orderedPattern.firstMatch(current)
            : _bulletPattern.firstMatch(current);
        if (match == null) break;
        items.add(parseProseSpans(match.group(1)!.trim()));
        i++;
      }
      blocks.add(ProseItems(ordered: ordered, items: items));
      continue;
    }

    if (line.startsWith('|')) {
      flushParagraph();
      final rows = <List<List<ProseSpan>>>[];
      while (i < lines.length && lines[i].trim().startsWith('|')) {
        final cells = _splitRow(lines[i].trim());
        // Die Trennzeile unter der Kopfzeile ist Auszeichnung, kein Inhalt.
        if (!cells.every((c) => _rulePattern.hasMatch(c))) {
          rows.add([for (final cell in cells) parseProseSpans(cell)]);
        }
        i++;
      }
      if (rows.isNotEmpty) blocks.add(ProseTable(rows));
      continue;
    }

    paragraph.add(line);
    i++;
  }

  flushParagraph();
  return blocks;
}

/// Der Text ohne Auszeichnung — für Sprungmarken und Vorlesefunktion.
String plainProse(List<ProseSpan> spans) => spans
    .map(
      (s) => switch (s) {
        ProseRun(:final text) => text,
        ProseLink(:final label) => label,
      },
    )
    .join();

List<String> _splitRow(String line) {
  var row = line;
  if (row.startsWith('|')) row = row.substring(1);
  if (row.endsWith('|')) row = row.substring(0, row.length - 1);
  return [for (final cell in row.split('|')) cell.trim()];
}

/// Zerlegt eine Zeile in Textstücke. Wirft nicht.
///
/// Alles, was nicht sauber schließt — ein einzelner Stern, ein offener
/// Backtick, ein Link auf etwas anderes als ein Kapitel — bleibt Zeichen für
/// Zeichen stehen. Lieber ein sichtbares Sternchen als ein verschwundener
/// Halbsatz.
List<ProseSpan> parseProseSpans(String text) {
  final spans = <ProseSpan>[];
  final buffer = StringBuffer();

  void flush() {
    if (buffer.isEmpty) return;
    spans.add(ProseRun(buffer.toString()));
    buffer.clear();
  }

  var i = 0;
  while (i < text.length) {
    final char = text[i];

    if (char == '`') {
      final end = text.indexOf('`', i + 1);
      if (end > i + 1) {
        flush();
        spans.add(ProseRun(text.substring(i + 1, end), code: true));
        i = end + 1;
        continue;
      }
    } else if (char == '*' && i + 1 < text.length && text[i + 1] == '*') {
      final end = text.indexOf('**', i + 2);
      if (end > i + 1) {
        flush();
        spans.add(ProseRun(text.substring(i + 2, end), bold: true));
        i = end + 2;
        continue;
      }
    } else if (char == '*') {
      // Erst nach der Prüfung auf `**`, nie davor: Sonst frisst das einzelne
      // Sternchen die erste Hälfte einer Fettauszeichnung, und aus fettem
      // Text wird ein Sternchen mit Kursivschrift.
      final end = text.indexOf('*', i + 1);
      if (end > i + 1) {
        flush();
        spans.add(ProseRun(text.substring(i + 1, end), italic: true));
        i = end + 1;
        continue;
      }
    } else if (char == '[') {
      final close = text.indexOf(']', i + 1);
      if (close > i && close + 1 < text.length && text[close + 1] == '(') {
        final end = text.indexOf(')', close + 2);
        if (end > close) {
          final target = text.substring(close + 2, end).trim();
          // Nur Kapitelsprünge. Externe Ziele gibt es in dieser Hilfe nicht
          // — sie erscheinen deshalb als das, was sie sind: Text.
          if (target.startsWith('kapitel:') || target.startsWith('chapter:')) {
            flush();
            spans.add(
              ProseLink(
                text.substring(i + 1, close),
                target.substring(target.indexOf(':') + 1).trim(),
              ),
            );
            i = end + 1;
            continue;
          }
        }
      }
    }

    buffer.write(char);
    i++;
  }

  flush();
  return spans;
}

// ── Darstellung ─────────────────────────────────────────────────────────

/// Breite, über die ein Bild in der Hilfe nicht hinauswächst.
///
/// Ohne Deckel füllt ein Screenshot am Tablet den halben Bildschirm und
/// drängt den Text weg, den er erklären soll.
const double kProseImageMaxWidth = 320;

/// Breite, über die eine Textspalte nicht hinauswächst.
///
/// Eine Zeile über die volle Tabletbreite hat gut hundert Zeichen; danach
/// findet das Auge den Zeilenanfang nicht mehr zuverlässig.
const double kProseMaxWidth = 640;

/// In wie vielen **Pixeln** ein Bild dekodiert wird.
///
/// Ohne das dekodiert Flutter in voller Auflösung: 1240×2754 sind rund
/// 13 MB im Speicher, für ein Bild, das nie breiter als [kProseImageMaxWidth]
/// erscheint. Öffentlich, damit der Test dieselbe Zahl bilden kann, ohne sie
/// abzuschreiben.
int proseDecodeWidth(MediaQueryData media) => math.max(
  1,
  (math.min(kProseImageMaxWidth, media.size.width) * media.devicePixelRatio)
      .round(),
);

/// Stellt geparste Blöcke dar. Ohne eigenes Scrollen — der Aufrufer bettet
/// das in seine Liste ein.
class ProseView extends StatefulWidget {
  final List<ProseBlock> blocks;

  /// Wird bei `[Titel](kapitel:06)` mit "06" gerufen.
  final void Function(String chapter)? onChapter;

  /// Verzeichnis, auf das sich relative Bildpfade beziehen.
  final String imageBase;

  /// Sprungmarken: Blockindex → Schlüssel, den der Aufrufer anspringen kann.
  final Map<int, GlobalKey> anchors;

  const ProseView({
    super.key,
    required this.blocks,
    this.onChapter,
    this.imageBase = 'assets/help/',
    this.anchors = const {},
  });

  @override
  State<ProseView> createState() => _ProseViewState();
}

class _ProseViewState extends State<ProseView> {
  /// Ein Erkenner je Kapitelziel. Sie hier zu halten statt sie im `build`
  /// anzulegen ist kein Feinschliff: Ein neuer Erkenner je Bau-Durchlauf
  /// wäre ein Leck, das mit jedem Bildaufbau wächst.
  final _links = <String, TapGestureRecognizer>{};

  /// Aufgelöste Asset-Pfade der Bilder dieses Kapitels.
  var _images = <String>{};

  int _decodeWidth = 0;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final width = proseDecodeWidth(MediaQuery.of(context));
    if (width != _decodeWidth) {
      // Andere Breite heißt anderer Cache-Schlüssel. Die alte Fassung wird
      // sonst nie wieder angefasst und bleibt trotzdem im Speicher.
      _release();
      _decodeWidth = width;
    }
  }

  @override
  void didUpdateWidget(ProseView old) {
    super.didUpdateWidget(old);
    if (!identical(old.blocks, widget.blocks)) {
      _release();
      _bind();
    }
  }

  @override
  void dispose() {
    // Der eigentliche Punkt der ganzen Übung: Beim Verlassen der Hilfe darf
    // nichts von ihr im Speicher zurückbleiben.
    _release();
    for (final recognizer in _links.values) {
      recognizer.dispose();
    }
    _links.clear();
    super.dispose();
  }

  void _bind() {
    for (final recognizer in _links.values) {
      recognizer.dispose();
    }
    _links.clear();
    _images = {
      for (final block in widget.blocks)
        if (block is ProseImage) _resolve(block.path),
    };
    for (final block in widget.blocks) {
      for (final span in _spansOf(block)) {
        if (span is! ProseLink || _links.containsKey(span.chapter)) continue;
        _links[span.chapter] = TapGestureRecognizer()
          ..onTap = () => widget.onChapter?.call(span.chapter);
      }
    }
  }

  /// Gibt die dekodierten Bilder wieder frei.
  void _release() {
    if (_decodeWidth <= 0) return;
    for (final path in _images) {
      final provider = ResizeImage.resizeIfNeeded(
        _decodeWidth,
        null,
        AssetImage(path),
      );
      // Genau der Schlüssel, unter dem `Image.asset(cacheWidth: …)` ablegt.
      // Fehlt das Bild, kommt der Schlüssel nie zustande — das ist kein
      // Grund, beim Verlassen eines Kapitels abzustürzen.
      unawaited(provider.evict().catchError((Object _) => false));
    }
  }

  String _resolve(String path) =>
      path.startsWith('assets/') ? path : '${widget.imageBase}$path';

  static Iterable<ProseSpan> _spansOf(ProseBlock block) => switch (block) {
    ProseHeading(:final spans) => spans,
    ProseParagraph(:final spans) => spans,
    ProseQuote(:final spans) => spans,
    ProseItems(:final items) => items.expand((i) => i),
    ProseTable(:final rows) => rows.expand((r) => r.expand((c) => c)),
    ProseImage() => const [],
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < widget.blocks.length; i++)
          _keyed(i, _block(context, widget.blocks[i])),
      ],
    );
  }

  Widget _keyed(int index, Widget child) {
    final key = widget.anchors[index];
    return key == null ? child : KeyedSubtree(key: key, child: child);
  }

  Widget _block(BuildContext context, ProseBlock block) {
    final p = context.axiom;
    final text = Theme.of(context).textTheme;

    switch (block) {
      case ProseHeading(:final level, :final spans):
        final style = switch (level) {
          1 => text.headlineMedium,
          2 => text.titleLarge,
          _ => text.titleMedium,
        };
        return Padding(
          padding: EdgeInsets.only(
            top: level == 1 ? 0 : Space.xl,
            bottom: level == 1 ? Space.lg : Space.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text.rich(_inline(context, spans, style)),
              ),
              // Nur die zweite Ebene bekommt den Strich: Er gliedert das
              // Kapitel, und ein Strich unter jeder Zwischenüberschrift
              // gliedert nichts mehr.
              if (level == 2) ...[
                const SizedBox(height: Space.sm),
                Container(height: 1, color: p.rule),
              ],
            ],
          ),
        );

      case ProseParagraph(:final spans):
        return Padding(
          padding: const EdgeInsets.only(bottom: Space.md),
          child: Text.rich(_inline(context, spans, text.bodyLarge)),
        );

      case ProseItems(:final ordered, :final items):
        // Die Spalte für Punkt und Zahl wächst mit der Schrift. Fest gesetzt
        // schneidet sie bei 2,4-facher Textgröße die Ziffer ab — und eine
        // Aufzählung ohne Nummern ist keine mehr.
        final marker = MediaQuery.textScalerOf(
          context,
        ).scale(ordered ? 26 : 16);
        return Padding(
          padding: const EdgeInsets.only(bottom: Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var n = 0; n < items.length; n++)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: marker,
                        child: Text(
                          ordered ? '${n + 1}.' : '·',
                          // War Monospace. Eine Aufzaehlungsnummer ist keine
                          // Codestelle — sie muss nur untereinander stehen,
                          // und dafuer sind Tabellenziffern da.
                          style: readingStyle(context,
                              size: 15, weight: FontWeight.w500,
                              color: p.inkFaint),
                        ),
                      ),
                      Expanded(
                        child: Text.rich(
                          _inline(context, items[n], text.bodyLarge),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );

      case ProseQuote(:final spans):
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: Space.md),
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.md, Space.md),
          decoration: BoxDecoration(
            color: p.panel,
            borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(Radii.control)),
            border: Border(left: BorderSide(color: p.signal, width: 2)),
          ),
          child: Text.rich(_inline(context, spans, text.bodyMedium)),
        );

      case ProseTable(:final rows):
        final columns = rows.fold(0, (max, r) => math.max(max, r.length));
        if (columns == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: Space.md),
          child: Table(
            border: TableBorder.all(color: p.rule),
            children: [
              for (var r = 0; r < rows.length; r++)
                TableRow(
                  children: [
                    for (var c = 0; c < columns; c++)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.sm,
                          vertical: Space.sm,
                        ),
                        child: Text.rich(
                          _inline(
                            context,
                            c < rows[r].length ? rows[r][c] : const [],
                            r == 0 ? text.labelSmall : text.bodySmall,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        );

      case ProseImage(:final path, :final caption):
        return _ProseFigure(
          asset: _resolve(path),
          caption: caption,
          decodeWidth: _decodeWidth,
        );
    }
  }

  /// Baut die Textstücke einer Zeile zu einem Span zusammen.
  InlineSpan _inline(
    BuildContext context,
    List<ProseSpan> spans,
    TextStyle? base,
  ) {
    final p = context.axiom;
    return TextSpan(
      style: base,
      children: [
        for (final span in spans)
          switch (span) {
            ProseRun(:final text, :final code) when code => TextSpan(
                text: text,
                style: monoStyle(
                  context,
                  size: (base?.fontSize ?? 15) - 2,
                  color: p.info,
                ),
              ),
            // Kursiv im vorhandenen Stil — keine eigene Größe, keine eigene
            // Farbe. Es markiert einen Pfad, es ruft nicht.
            ProseRun(:final text, :final bold, :final italic) => TextSpan(
              text: text,
              style: bold
                  ? TextStyle(fontWeight: FontWeight.w600, color: p.ink)
                  : italic
                  ? const TextStyle(fontStyle: FontStyle.italic)
                  : null,
            ),
            // Farbe allein trägt den Sprung nicht: In der hellen Fassung
            // läge Bernstein auf Papier knapp an der Lesbarkeitsgrenze, und
            // eine Verknüpfung, die man nicht liest, ist keine. Also
            // Textfarbe wie der Fließtext, Signalfarbe in der Unterstreichung.
            ProseLink(:final label, :final chapter) => TextSpan(
              text: label,
              style: TextStyle(
                color: p.ink,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.underline,
                decorationColor: p.signal,
                decorationThickness: 1.5,
              ),
              recognizer: _links[chapter],
            ),
          },
      ],
    );
  }
}

/// Ein Bild mit Rahmen und Unterschrift.
class _ProseFigure extends StatelessWidget {
  final String asset;
  final String caption;
  final int decodeWidth;

  const _ProseFigure({
    required this.asset,
    required this.caption,
    required this.decodeWidth,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm, bottom: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kProseImageMaxWidth),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: p.rule),
                borderRadius: BorderRadius.circular(Radii.panel),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                asset,
                // Deckelt die Dekodiergröße. Ohne das liegt ein
                // Bildschirmfoto in voller Auflösung im Speicher.
                cacheWidth: decodeWidth > 0 ? decodeWidth : null,
                fit: BoxFit.contain,
                semanticLabel: caption.isEmpty ? null : caption,
                // Sichtbar unfertig statt stumm fehlend: Ein Kapitel, in dem
                // wortlos ein Bild fehlt, liest sich wie ein Kapitel ohne
                // Bild — und niemand meldet, was niemand vermisst.
                errorBuilder: (context, error, stack) => Padding(
                  padding: const EdgeInsets.all(Space.md),
                  child: Text(
                    '${context.t('Bild fehlt')} · $asset',
                    style: monoStyle(context, size: 11, color: p.inkFaint),
                  ),
                ),
              ),
            ),
          ),
          if (caption.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kProseImageMaxWidth),
              child: Text(
                caption,
                // Eine Bildunterschrift ist Fliesstext, kein Protokoll.
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: p.inkFaint),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
