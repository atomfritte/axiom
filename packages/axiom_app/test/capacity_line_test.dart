/// Die Kapazitätslinie bleibt in ihrer Leinwand.
///
/// **Warum das ein Pixeltest ist.** Der Markenstapel wächst nach oben, und
/// er wuchs ohne Obergrenze: `y = 34 − 10 − stack * 9`. Ab der vierten
/// Aufgabe mit derselben Aktivierungsenergie lag der Punkt bei y = −3, ab
/// der fünften mitten in der Kopfzeile darüber. Es gab dabei keinen
/// Überlauffehler, den ein Widget-Test hätte einsammeln können — weder
/// `CustomPaint` noch `Panel` clippen, also malte die Marke einfach über
/// den Text. Sichtbar wird das nur im Bild.
///
/// Vier gleiche Werte entstehen im Alltag von selbst: Die Triage startet bei
/// AE 5, jede Zerlegung erzeugt einen ersten Schritt mit AE 2. Wer den
/// Regler stehen lässt, hat den Fall nach vier Notizen.
///
/// Dazu die Kopfzeile: Sie stand bis zu dieser Runde als
/// „AKTIVIERUNGSENERGIE" und „KAPAZITÄT 61" da — neunzehn Großbuchstaben am
/// Stück in Schreibmaschine, auf dem Bild, das die Frage „was kann ich jetzt
/// anfangen" vorbewusst beantworten soll.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:axiom_app/design/theme.dart';
import 'package:axiom_app/design/tokens.dart';
import 'package:axiom_app/design/widgets/capacity_line.dart';
import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _boundary = Key('leinwand');

List<Task> _sameEnergy(int count, {int energy = 5}) => [
      for (var i = 0; i < count; i++)
        Task(
          id: 'task-$i',
          title: 'Aufgabe $i',
          activationEnergy: energy,
          salience: 5,
          stakes: 5,
          state: TaskState.ready,
        ),
    ];

Future<void> _pump(WidgetTester tester, List<Task> tasks) async {
  tester.view.physicalSize = const Size(400, 400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAxiomTheme(brightness: Brightness.dark),
      home: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: _boundary,
          child: ColoredBox(
            color: const Color(0xFF000000),
            child: SizedBox(
              width: 348,
              child: CapacityLine(capacity: 100, tasks: tasks),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 600));
}

/// Rastert den umschlossenen Bereich.
Future<Uint32List> _raster(WidgetTester tester) async {
  late Uint32List pixels;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_boundary, skipOffstage: false));
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    pixels = data!.buffer.asUint32List();
    image.dispose();
  });
  return pixels;
}

/// Wo die Leinwand innerhalb des umschlossenen Bereichs beginnt.
double _canvasTop(WidgetTester tester) {
  final paint = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.size == const Size(double.infinity, 62));
  return tester.getTopLeft(paint).dy -
      tester.getTopLeft(find.byKey(_boundary)).dy;
}

void main() {
  testWidgets('keine Marke verlässt die Leinwand nach oben', (tester) async {
    await _pump(tester, _sameEnergy(3));
    final top = _canvasTop(tester).floor();
    final width = tester.getSize(find.byKey(_boundary)).width.round();
    final reference = await _raster(tester);

    // Acht Aufgaben mit AE 5: Vorher lag die achte Marke bei y = −33 und
    // damit oberhalb des gesamten Widgets.
    await _pump(tester, _sameEnergy(8));
    final crowded = await _raster(tester);

    final changedAbove = <int>[];
    for (var y = 0; y < top; y++) {
      for (var x = 0; x < width; x++) {
        final i = y * width + x;
        if (reference[i] != crowded[i]) changedAbove.add(y);
      }
    }
    expect(changedAbove, isEmpty,
        reason: 'Über der Leinwand (y < $top) wurde gemalt — dort steht die '
            'Kopfzeile „AKTIVIERUNGSENERGIE · KAPAZITÄT 100". '
            'Betroffene Zeilen: ${changedAbove.toSet().toList()}');
  });

  testWidgets('was der Stapel nicht fasst, wird angeschrieben',
      (tester) async {
    // Das Gegenstück: Deckeln allein wäre ein stummes Weglassen — die Skala
    // zeigte dann drei Aufgaben, wo acht sind, und eine Skala, der man das
    // nicht ansieht, ist schlimmer als keine (G2).
    await _pump(tester, _sameEnergy(3));
    final reference = await _raster(tester);

    await _pump(tester, _sameEnergy(8));
    final crowded = await _raster(tester);

    var differing = 0;
    for (var i = 0; i < reference.length; i++) {
      if (reference[i] != crowded[i]) differing++;
    }
    expect(differing, greaterThan(0),
        reason: 'Acht Aufgaben sehen aus wie drei — der Hinweis auf die '
            'fünf weiteren fehlt');
  });

  testWidgets('die Kopfzeile schreit nicht und der Messwert steht in signal',
      (tester) async {
    await _pump(tester, _sameEnergy(2));

    expect(find.text('Aktivierungsenergie'), findsOneWidget);
    expect(find.text('AKTIVIERUNGSENERGIE'), findsNothing);
    expect(find.text('KAPAZITÄT 100'), findsNothing);

    // Die Zahl steht getrennt von ihrer Beschriftung: So bekommt sie
    // Tabellenziffern, und so lässt sie sich vorlesen, ohne dass ein
    // Übersetzer sie aus einem fertigen Satz zurückrechnen muss.
    final value = tester.widget<Text>(find.text('100'));
    expect(value.style?.color, AxiomPalette.dark.signal);
    expect(value.style?.fontFamily, Fonts.sans);
    expect(value.style?.fontFeatures,
        contains(const FontFeature.tabularFigures()));
  });
}
