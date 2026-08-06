/// Was auf dem ersten Bildschirm gilt — nachgesehen, nicht angenommen.
///
/// **Warum es diese Datei gibt.** Das Onboarding ist der einzige Schirm, den
/// jeder Nutzer garantiert sieht, und der einzige, den man danach nie wieder
/// aufruft — also auch der, an dem eine Regression am längsten unbemerkt
/// bleibt. Die vier Zusagen hier sind allesamt Fälle, die einmal kaputt
/// waren und die kein anderer Test hält:
///
///  1. **Lesespalte.** AXIOM läuft auch als Fenster auf dem Rechner. Ohne
///     Deckel lief die erste Zeile über 1100 Pixel — rund 130 Zeichen.
///  2. **Der Ausweg bleibt lesbar.** Bei großer Schrift stand
///     „Überspringen" als „Überspri…" da: der Nebenweg unleserlich,
///     ausgerechnet auf dem Schirm, den man verlassen können muss.
///  3. **Genau eine Handlung am Ende** (G1). Auf der letzten Seite riefen
///     „Überspringen" und „Los geht’s" dieselbe Methode — zwei Knöpfe, eine
///     Wirkung, also eine Entscheidung ohne Unterschied.
///  4. **Der Einstiegssatz steht größer.** Ohne diese Stufe ist die Seite
///     eine gleichmäßige Textfläche, in der kein Satz wichtiger aussieht als
///     der nächste.
library;

import 'package:axiom_app/screens/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  late TestHarness h;

  setUp(() => h = TestHarness.create());
  tearDown(() => h.dispose());

  /// Blättert bis zur letzten Seite.
  Future<void> toEnd(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Weiter').last);
      await tester.pumpAndSettle();
    }
  }

  testWidgets('der erste Bildschirm bleibt eine Lesespalte, auch im Fenster',
      (tester) async {
    await pumpPhone(
      tester,
      h.wrap(OnboardingScreen(onDone: () {})),
      size: const Size(1100, 900),
    );

    // Nicht die Fensterbreite, sondern die Spalte: Eine Zeile, deren Anfang
    // das Auge nicht mehr findet, wird nicht gelesen — und hier wird gelesen.
    final column = tester.getSize(find.byType(PageView)).width;
    expect(column, lessThanOrEqualTo(kOnboardingMaxWidth));

    // Und sie steht in der Mitte, nicht in der linken oberen Ecke.
    final page = tester.getRect(find.byType(PageView));
    expect((page.left - (1100 - page.width) / 2).abs(), lessThan(1));
  });

  testWidgets('bei großer Schrift steht der Ausweg unter der Handlung',
      (tester) async {
    await pumpScaled(
      tester,
      h.wrap(OnboardingScreen(onDone: () {})),
      textScale: 1.5,
    );

    // Nebeneinander wurde „Überspringen" abgeschnitten. Untereinander bleibt
    // beides ganz — und die Handlung steht oben.
    final forward = tester.getRect(find.text('Weiter'));
    final skip = tester.getRect(find.text('Überspringen'));
    expect(skip.top, greaterThan(forward.bottom),
        reason: 'Der Ausweg gehört unter die Handlung, sobald er neben ihr '
            'nicht mehr ganz hinpasst');
  });

  testWidgets('die letzte Seite bietet genau eine Handlung', (tester) async {
    await pumpPhone(tester, h.wrap(OnboardingScreen(onDone: () {})));
    await toEnd(tester);

    expect(find.text('Los geht’s'), findsOneWidget);
    // „Überspringen" rief auf dieser Seite dasselbe wie „Los geht’s".
    expect(find.text('Überspringen'), findsNothing,
        reason: 'Zwei Knöpfe mit derselben Wirkung sind eine Entscheidung '
            'ohne Unterschied (G1)');
  });

  testWidgets('der Einstiegssatz steht größer als der Absatz darunter',
      (tester) async {
    await pumpPhone(tester, h.wrap(OnboardingScreen(onDone: () {})));

    double sizeOf(String start) => tester
        .widget<Text>(find.textContaining(start))
        .style!
        .fontSize!;

    final lead = sizeOf('AXIOM misst deinen Zustand');
    final body = sizeOf('Der Unterschied zu anderen Apps');
    expect(lead, greaterThan(body),
        reason: 'Ohne diese Stufe ist die Seite eine gleichmäßige Fläche, in '
            'der kein Satz wichtiger aussieht als der nächste');
  });
}
