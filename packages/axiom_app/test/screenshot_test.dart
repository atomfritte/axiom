/// Erzeugt Referenzbilder der Oberflaeche.
///
///   flutter test test/screenshot_test.dart --update-goldens
///
/// Dient zwei Zwecken: visuelle Kontrolle beim Entwickeln und ein Regressions-
/// netz gegen unbeabsichtigte Layoutaenderungen.
@Tags(['golden'])
library;

import 'dart:io';

import 'package:axiom_app/screens/anchors_screen.dart';
import 'package:axiom_app/screens/atomize_sheet.dart';
import 'package:axiom_app/screens/focus_screen.dart';
import 'package:axiom_app/screens/inbox_screen.dart';
import 'package:axiom_app/screens/intercept_screen.dart';
import 'package:axiom_app/screens/sensation_screen.dart';
import 'package:axiom_app/screens/signal_screen.dart';
import 'package:axiom_app/screens/review_screen.dart';
import 'package:axiom_app/screens/now_screen.dart';
import 'package:axiom_app/screens/onboarding_screen.dart';
import 'package:axiom_app/screens/state_screen.dart';
import 'package:axiom_app/screens/system_screen.dart';
import 'package:axiom_app/screens/tasks_screen.dart';
import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// Laedt die gebuendelten Schriften — ohne das rendern Goldens in Ahem.
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
  setUpAll(loadAppFonts);

  late TestHarness h;
  setUp(() => h = TestHarness.create());
  tearDown(() => h.dispose());

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget widget, {
    Brightness brightness = Brightness.dark,
  }) async {
    await pumpPhone(tester, h.wrap(widget, brightness: brightness));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('screenshots/$name.png'),
    );
  }

  testWidgets('01 onboarding — was das ist', (tester) async {
    await shoot(tester, '01-onboarding-was', OnboardingScreen(onDone: () {}));
  });

  testWidgets('02 onboarding — kapazitaetslinie', (tester) async {
    await pumpPhone(tester, h.wrap(OnboardingScreen(onDone: () {})));
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Weiter').last);
      await tester.pumpAndSettle();
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('screenshots/02-onboarding-linie.png'),
    );
  });

  testWidgets('03 jetzt — leer', (tester) async {
    h.completeOnboarding();
    await shoot(tester, '03-jetzt-leer', const NowScreen());
  });

  testWidgets('04 jetzt — mit Aufgaben', (tester) async {
    h.completeOnboarding();
    await h.runtime.checkIn(energy: 4, focus: 4, mood: 4, stimNeed: 3);
    for (final (title, ae, stakes) in [
      ('Steuerunterlagen sortieren', 8, 9),
      ('Rückruf Werkstatt', 2, 6),
      ('Reifen wechseln lassen', 4, 5),
      ('Antrag Krankenkasse', 7, 8),
      ('Rechnung Elektriker prüfen', 3, 4),
    ]) {
      await h.runtime.createTask(
        title: title,
        activationEnergy: ae,
        salience: 4,
        stakes: stakes,
      );
    }
    await h.runtime.createAnchor(
      title: 'Zahnarzt',
      arriveBy: h.clock.nowLocal().add(const Duration(minutes: 75)),
      travel: const Duration(minutes: 25),
      location: 'Praxis',
    );
    await shoot(tester, '04-jetzt-aufgaben', const NowScreen());
  });

  testWidgets('05 zustand', (tester) async {
    h.completeOnboarding();
    await h.runtime.checkIn(
      energy: 3,
      focus: 2,
      mood: 3,
      stimNeed: 4,
      compensation: 4,
      recovery: 2,
      slot: 'evening',
    );
    await shoot(tester, '05-zustand', const StateScreen());
  });

  testWidgets('06 system — regelinspektor', (tester) async {
    h.completeOnboarding();
    await shoot(tester, '06-system', const SystemScreen());
  });

  testWidgets('07 eingang', (tester) async {
    h.completeOnboarding();
    for (final text in [
      'Termin Zahnarzt verschieben',
      'Idee: Regelwerk um Wochenreview ergänzen',
      'Kabel für den Monitor bestellen',
    ]) {
      await h.runtime.capture(text);
    }
    await shoot(tester, '07-eingang', const InboxScreen());
  });

  testWidgets('19 onboarding — health connect', (tester) async {
    await pumpPhone(tester, h.wrap(OnboardingScreen(onDone: () {})));
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Weiter').last);
      await tester.pumpAndSettle();
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('screenshots/19-onboarding-health.png'),
    );
  });

  testWidgets('18 aufgaben — der ganze bestand', (tester) async {
    h.completeOnboarding();
    final tasks = [
      ('Steuerunterlagen sortieren', 3),
      ('Rechnung Werkstatt bezahlen', 2),
      ('Wohnung streichen', 9),
      ('Rückruf Vermieter', 2),
    ];
    for (final (title, ae) in tasks) {
      await h.runtime.createTask(
        title: title,
        activationEnergy: ae,
        salience: 5,
        stakes: 6,
      );
    }
    final all = await h.store.tasks();
    await h.runtime.startTask(all.firstWhere((t) => t.activationEnergy == 2));
    await shoot(tester, '18-aufgaben', const TasksScreen());
  });

  testWidgets('09 anker — rückwärtsverkettung', (tester) async {
    h.completeOnboarding();
    await h.runtime.createAnchor(
      title: 'Zahnarzt',
      arriveBy: h.clock.nowLocal().add(const Duration(hours: 3, minutes: 30)),
      travel: const Duration(minutes: 25),
      location: 'Praxis Bergmann',
    );
    await h.runtime.createAnchor(
      title: 'Elterngespräch',
      arriveBy: h.clock.nowLocal().add(const Duration(hours: 8)),
      travel: const Duration(minutes: 15),
      location: 'Schule',
    );
    await shoot(tester, '09-anker', const AnchorsScreen());
  });

  testWidgets('10 zerlegen — erster Schritt', (tester) async {
    h.completeOnboarding();
    final task = await h.runtime.createTask(
      title: 'Steuerunterlagen für 2025 sortieren',
      activationEnergy: 9,
      salience: 2,
      stakes: 9,
      decayAt: h.clock.nowLocal().add(const Duration(hours: 40)),
    );
    await pumpPhone(tester, h.wrap(const Scaffold()));
    final context = tester.element(find.byType(Scaffold));
    showAtomizeSheet(
      context,
      AtomizeCandidate(
        task: task,
        reason: AtomizeReason.urgentButUnreachable,
        targetEnergy: 2,
      ),
    ).ignore();
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('screenshots/10-zerlegen.png'),
    );
  });

  testWidgets('11 review — wochenbericht', (tester) async {
    h.completeOnboarding();
    for (var i = 0; i < 12; i++) {
      await h.runtime.checkIn(
        energy: 3,
        focus: 3,
        mood: 3,
        stimNeed: 4,
        compensation: 4,
        recovery: 2,
        slot: 'evening',
      );
      await h.runtime.capture('Notiz $i');
    }
    await h.store.logUsage('system', const Duration(minutes: 7));
    await shoot(tester, '11-review',
        const ReviewScreen(scope: ReviewScope.week));
    await unmount(tester);
  });

  testWidgets('12 fokus — laufender block', (tester) async {
    h.completeOnboarding();
    await h.runtime.startFocus(
      taskId: 't1',
      taskTitle: 'Steuerunterlagen sortieren',
      planned: const Duration(minutes: 50),
    );
    h.clock.advance(const Duration(minutes: 62));
    await shoot(tester, '12-fokus', const FocusScreen());
  });

  testWidgets('13 reiz — haushalt', (tester) async {
    h.completeOnboarding();
    await h.seedChannels();
    final session = await h.runtime.startFocus(taskTitle: 'Arbeit');
    h.clock.advance(const Duration(minutes: 120));
    await h.runtime.endFocus(session);
    await h.runtime.checkIn(energy: 3, focus: 3, mood: 3, stimNeed: 5);
    await shoot(tester, '13-reiz', const SensationScreen());
  });

  testWidgets('14 bremse — wartezeit', (tester) async {
    h.completeOnboarding();
    const trigger = InterceptTrigger(
      id: 'purchase',
      label: 'Anschaffung über 200 €',
      cooldown: Duration(minutes: 15),
      checklist: [
        'Kannte ich das vor heute?',
        'Ist es die Sache oder das Gefühl?',
        'Wie sehe ich das in vier Wochen?',
      ],
      authorized: true,
    );
    await h.runtime.saveTrigger(trigger);
    await h.runtime.startIntercept(trigger);
    h.clock.advance(const Duration(minutes: 4));
    await shoot(tester, '14-bremse', const InterceptScreen());
  });

  testWidgets('15 eichung — baseline bereit', (tester) async {
    h.completeOnboarding();
    for (var i = 0; i < 22; i++) {
      await h.runtime.checkIn(energy: 3, focus: 3, mood: 3, stimNeed: 3);
      h.clock.advance(const Duration(hours: 5));
    }
    for (var i = 0; i < 8; i++) {
      await h.runtime.logSleep(
        bedAt: h.clock.nowLocal().subtract(const Duration(hours: 8)),
        wakeAt: h.clock.nowLocal(),
        quality: 3,
      );
      h.clock.advance(const Duration(hours: 24));
    }
    h.clock.advance(const Duration(days: 2));
    await shoot(tester, '15-eichung-bereit', const SystemScreen());
  });

  testWidgets('16 eichung — baseline laeuft', (tester) async {
    h.completeOnboarding();
    for (var i = 0; i < 9; i++) {
      await h.runtime.checkIn(energy: 3, focus: 3, mood: 3, stimNeed: 3);
      h.clock.advance(const Duration(hours: 8));
    }
    for (var i = 0; i < 3; i++) {
      await h.runtime.logSleep(
        bedAt: h.clock.nowLocal().subtract(const Duration(hours: 7)),
        wakeAt: h.clock.nowLocal(),
        quality: 3,
      );
      h.clock.advance(const Duration(hours: 24));
    }
    await shoot(tester, '16-eichung-laeuft', const SystemScreen());
  });

  testWidgets('17 vorfaelle — nachbetrachtung faellig', (tester) async {
    h.completeOnboarding();
    for (final (trigger, intensity) in [
      (TriggerClass.rejection, 5),
      (TriggerClass.criticism, 3),
      (TriggerClass.rejection, 4),
      (TriggerClass.overload, 2),
    ]) {
      await h.runtime.logIncident(intensity: intensity, triggerClass: trigger);
      h.clock.advance(const Duration(hours: 30));
    }
    await shoot(tester, '17-vorfaelle', const SignalScreen());
  });

  testWidgets('08 jetzt — hell', (tester) async {
    h.completeOnboarding();
    await h.runtime.checkIn(energy: 4, focus: 4, mood: 4, stimNeed: 2);
    await h.runtime.createTask(
      title: 'Rückruf Werkstatt',
      activationEnergy: 2,
      salience: 5,
      stakes: 6,
    );
    await shoot(tester, '08-jetzt-hell', const NowScreen(),
        brightness: Brightness.light);
  });
}
