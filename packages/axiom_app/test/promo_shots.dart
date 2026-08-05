/// Erzeugt englische Aufnahmen für Beiträge — kein Test.
///
/// **Warum die Datei nicht auf `_test.dart` endet.** `flutter test` sammelt
/// alles mit dieser Endung ein. Ein Generator, der bei jedem Lauf Bilder
/// schreiben will, wäre dort ein Fremdkörper: Ohne `--update-goldens`
/// scheitert er, mit ihm überschreibt er bei jedem Durchlauf Dateien, die
/// niemand geprüft hat. Er wird deshalb einzeln aufgerufen:
///
///     flutter test test/promo_shots.dart --update-goldens
///
/// Die Bilder landen unter `promo/shots-en/`, und der Ordner ist
/// git-ignoriert: Screenshots veralten, und ein Repo, das sie mitschleppt,
/// zeigt irgendwann eine Oberfläche, die es nicht mehr gibt.
library;

import 'package:axiom_app/screens/anchors_screen.dart';
import 'package:axiom_app/screens/now_screen.dart';
import 'package:axiom_app/screens/state_screen.dart';
import 'package:axiom_app/screens/system_screen.dart';
import 'package:axiom_app/screens/tasks_screen.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:axiom_app/i18n/i18n.dart';

import 'harness.dart';

Future<void> loadAppFonts() async {
  // Material-Icons aus dem Flutter-SDK, sonst erscheinen Symbole als Kaesten.
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
      '${Platform.environment['HOME']}/flutter';
  final iconFont = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (iconFont.existsSync()) {
    await (FontLoader('MaterialIcons')
          ..addFont(
              Future.value(ByteData.sublistView(iconFont.readAsBytesSync()))))
        .load();
  }

  for (final (family, files) in [
    ('PlexSans', [
      'IBMPlexSans-Light.ttf',
      'IBMPlexSans-Regular.ttf',
      'IBMPlexSans-Medium.ttf',
      'IBMPlexSans-SemiBold.ttf',
    ]),
    ('PlexMono', [
      'IBMPlexMono-Regular.ttf',
      'IBMPlexMono-Medium.ttf',
      'IBMPlexMono-SemiBold.ttf',
    ]),
  ]) {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = File('assets/fonts/$file').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}

void main() {
  // Ohne geladene Schriften zeichnet die Testumgebung jeden Text als
  // Kaestchen — die Aufnahmen waeren huebsche Platzhalter ohne Aussage.
  setUpAll(loadAppFonts);

  late TestHarness h;

  setUp(() {
    h = TestHarness.create(at: DateTime(2026, 8, 5, 9, 40));
    // Englisch, im Gegensatz zur Testumgebung: Der Beitrag ist englisch,
    // und ein deutscher Screenshot darunter erklärt nichts.
    h.store.setSetting('language', 'en');
    h.completeOnboarding();
  });

  tearDown(() => h.dispose());

  Future<void> shoot(WidgetTester tester, String name, Widget screen) async {
    // `AxiomLanguage` selbst setzen.
    //
    // `context.t(...)` liest die Sprache aus diesem InheritedWidget, nicht
    // aus dem Speicher — in der App setzt `app.dart` es, der Testrahmen
    // baut aber ein nacktes `MaterialApp`. Ohne diesen Rahmen faellt jeder
    // Text auf die Quellsprache zurueck, und die Aufnahmen waeren deutsch,
    // obwohl in der Datenbank Englisch steht.
    await pumpPhone(
      tester,
      h.wrap(AxiomLanguage(language: AppLanguage.en, child: screen)),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../../promo/shots-en/$name.png'),
    );
  }

  /// Etwas Bestand, sonst zeigen die Bilder leere Bildschirme.
  Future<void> seed() async {
    final tasks = <(String, int, int)>[
      ('Sort out last year’s tax paperwork', 8, 7),
      ('Call the landlord back', 3, 6),
      ('Fix the leaking tap', 5, 4),
      ('Air the flat', 1, 2),
    ];
    for (final (title, ae, stakes) in tasks) {
      await h.runtime.createTask(
        title: title,
        activationEnergy: ae,
        salience: 5,
        stakes: stakes,
      );
    }
    await h.runtime.checkIn(energy: 3, focus: 3, mood: 4, stimNeed: 4);
  }

  testWidgets('01 now', (tester) async {
    await seed();
    await shoot(tester, '01-now', const NowScreen());
  });

  testWidgets('02 tasks', (tester) async {
    await seed();
    final all = await h.store.tasks();
    await h.runtime.startTask(all.firstWhere((t) => t.activationEnergy == 3));
    await shoot(tester, '02-tasks', const TasksScreen());
  });

  testWidgets('03 state', (tester) async {
    await seed();
    await shoot(tester, '03-state', const StateScreen());
  });

  testWidgets('04 anchors', (tester) async {
    await h.runtime.createAnchor(
      title: 'Dentist',
      arriveBy: DateTime(2026, 8, 5, 11, 45),
      location: 'Praxis Dr. Weber',
    );
    await shoot(tester, '04-anchors', const AnchorsScreen());
  });

  // Der Meta-Work-Deckel — das Bild, das die Idee ohne Text transportiert.
  testWidgets('05 meta budget', (tester) async {
    await h.store.logUsage('rules', const Duration(minutes: 11));
    await shoot(tester, '05-meta-budget', const SystemScreen());
  });
}
