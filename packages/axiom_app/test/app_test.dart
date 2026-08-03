/// Verhaltenstests der Oberflaeche.
///
/// Geprueft wird nicht "sieht es aus wie gestern", sondern ob die
/// Designgesetze in der laufenden App tatsaechlich gelten: genau eine
/// Handlung (G1), sichtbare Regel-ID (G2), keine Schuldsprache.
library;

import 'dart:async';

import 'package:axiom_app/app.dart';
import 'package:axiom_app/design/widgets/capacity_line.dart';
import 'package:axiom_app/design/widgets/instruments.dart';
import 'package:axiom_app/screens/capture_sheet.dart';
import 'package:axiom_app/screens/inbox_screen.dart';
import 'package:axiom_app/screens/now_screen.dart';
import 'package:axiom_app/screens/onboarding_screen.dart';
import 'package:axiom_app/screens/state_screen.dart';
import 'package:axiom_app/screens/system_screen.dart';
import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  late TestHarness h;

  setUp(() => h = TestHarness.create());
  tearDown(() => h.dispose());

  group('Start', () {
    testWidgets('neue Installation landet im Onboarding', (tester) async {
      await pumpPhone(tester, h.wrap(const HomeShellGate()));
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.textContaining('Regelwerk'), findsWidgets);
    });

    testWidgets('nach dem Onboarding erscheint die Hauptansicht',
        (tester) async {
      h.completeOnboarding();
      await pumpPhone(tester, h.wrap(const HomeShellGate()));
      expect(find.byType(NowScreen), findsOneWidget);
      expect(find.text('Jetzt'), findsWidgets);
    });

    testWidgets('drei Navigationsziele, nicht mehr', (tester) async {
      h.completeOnboarding();
      await pumpPhone(tester, h.wrap(const HomeShellGate()));
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.destinations, hasLength(3));
    });
  });

  group('Onboarding fuehrt durch', () {
    testWidgets('fuenf Schritte, jeder ueberspringbar', (tester) async {
      await pumpPhone(tester, h.wrap(OnboardingScreen(onDone: () {})));

      expect(find.text('1/5'), findsOneWidget);
      expect(find.text('Überspringen'), findsOneWidget);

      for (var i = 2; i <= 5; i++) {
        await tester.tap(find.text('Weiter').last);
        await tester.pumpAndSettle();
        expect(find.text('$i/5'), findsOneWidget);
      }
      expect(find.text('Los geht’s'), findsOneWidget);
    });

    testWidgets('erklaert die Kapazitaetslinie mit einem echten Instrument',
        (tester) async {
      await pumpPhone(tester, h.wrap(OnboardingScreen(onDone: () {})));
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Weiter').last);
        await tester.pumpAndSettle();
      }
      expect(find.byType(CapacityLine), findsOneWidget);
    });

    testWidgets('sagt zu, was es NICHT tut', (tester) async {
      await pumpPhone(tester, h.wrap(OnboardingScreen(onDone: () {})));
      expect(find.textContaining('Keine Streaks'), findsOneWidget);
      expect(find.textContaining('Keine Cloud'), findsOneWidget);
      expect(find.textContaining('Keine KI'), findsOneWidget);
    });
  });

  group('G1 — genau eine Handlung', () {
    testWidgets('die Hauptansicht zeigt nie mehrere Vorschläge zur Auswahl',
        (tester) async {
      h.completeOnboarding();
      for (var i = 0; i < 5; i++) {
        await h.runtime.createTask(
          title: 'Aufgabe $i',
          activationEnergy: 2,
          salience: 5,
          stakes: 5,
        );
      }
      await pumpPhone(tester, h.wrap(const NowScreen()));

      // Fünf startbare Aufgaben, aber nur EIN "Jetzt"-Block.
      expect(find.text('JETZT'), findsOneWidget);
      expect(find.text('Anfangen').evaluate().length, lessThanOrEqualTo(1));
    });
  });

  group('G2 — jede Ausgabe traegt ihre Regel', () {
    testWidgets('Systeminspektor zeigt Regel-ID, Begründung und Bedingung',
        (tester) async {
      h.completeOnboarding();
      await pumpPhone(tester, h.wrap(const RulesScreen()));

      expect(find.textContaining('R-0'), findsWidgets);

      await tester.tap(find.textContaining('Check-in Morgen').first);
      await tester.pumpAndSettle();
      expect(find.text('BEGRÜNDUNG'), findsOneWidget);
      expect(find.text('BEDINGUNG'), findsOneWidget);
    });

    testWidgets('Messwerte lassen sich zur Herleitung aufklappen',
        (tester) async {
      h.completeOnboarding();
      await pumpPhone(tester, h.wrap(const StateScreen()));

      expect(find.byType(InstrumentBar), findsWidgets);
      await tester.tap(find.text('KAPAZITÄT'));
      await tester.pumpAndSettle();
      expect(find.text('SO WIRD GERECHNET'), findsOneWidget);
    });
  });

  group('Erfassung (D9)', () {
    testWidgets('speichert und taucht im Eingang auf', (tester) async {
      h.completeOnboarding();
      await pumpPhone(tester, h.wrap(const NowScreen()));

      await tester.tap(find.text('Erfassen'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Rückruf Werkstatt');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();

      final captures =
          await h.store.query(types: {EventType.capture});
      expect(captures, hasLength(1));
      expect(captures.single.payload['text'], 'Rückruf Werkstatt');
    });

    testWidgets('fragt beim Erfassen nach nichts ausser dem Text',
        (tester) async {
      await pumpPhone(tester, h.wrap(const Scaffold()));
      final context = tester.element(find.byType(Scaffold));
      unawaited(showCaptureSheet(context));
      await tester.pumpAndSettle();

      // Keine Kategorie, keine Priorität, kein Datum im Erfassungsmoment.
      expect(find.textContaining('Kategorie'), findsNothing);
      expect(find.textContaining('Priorität'), findsNothing);
      expect(find.textContaining('Projekt'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('Kapazitaetslinie (D2)', () {
    testWidgets('nennt startbare und ausserhalb liegende Aufgaben',
        (tester) async {
      final tasks = [
        for (final (i, ae) in [2, 3, 8, 9].indexed)
          Task(
            id: 't$i',
            title: 'A$i',
            activationEnergy: ae,
            salience: 5,
            stakes: 5,
            state: TaskState.ready,
          ),
      ];
      await pumpPhone(
        tester,
        h.wrap(Scaffold(body: CapacityLine(capacity: 50, tasks: tasks))),
      );
      expect(find.text('KAPAZITÄT 50'), findsOneWidget);
      expect(find.textContaining('2 startbar'), findsOneWidget);
    });

    testWidgets('formuliert Blockade ohne Schuld', (tester) async {
      final tasks = [
        Task(
          id: 't1',
          title: 'Schwer',
          activationEnergy: 9,
          salience: 5,
          stakes: 9,
          state: TaskState.ready,
        ),
      ];
      await pumpPhone(
        tester,
        h.wrap(Scaffold(body: CapacityLine(capacity: 20, tasks: tasks))),
      );
      expect(find.textContaining('Zerlegen hilft'), findsOneWidget);
    });
  });

  group('Sprache — keine Schuld, kein Urteil (D10, R7)', () {
    testWidgets('Leerzustand fuehrt weiter statt zu mahnen', (tester) async {
      h.completeOnboarding();
      await pumpPhone(tester, h.wrap(const NowScreen()));

      const forbidden = [
        'überfällig seit',
        'Du hast',
        'schon wieder',
        'Streak',
        'verloren',
        'versagt',
        'faul',
      ];
      for (final word in forbidden) {
        expect(find.textContaining(word), findsNothing,
            reason: 'Schuldsprache gefunden: "$word"');
      }
    });

    testWidgets('leerer Eingang lädt zum Handeln ein', (tester) async {
      h.completeOnboarding();
      await pumpPhone(tester, h.wrap(const InboxScreen()));
      expect(find.text('Nichts zu sortieren.'), findsOneWidget);
      expect(find.textContaining('landet hier'), findsOneWidget);
    });
  });

  group('Meta-Guard (M12/D3)', () {
    testWidgets('macht die eigenen Kosten sichtbar', (tester) async {
      h.completeOnboarding();
      await pumpPhone(tester, h.wrap(const NowScreen()));
      await tester.dragUntilVisible(
        find.text('ZEIT IN AXIOM HEUTE'),
        find.byType(ListView),
        const Offset(0, -250),
      );
      expect(find.text('ZEIT IN AXIOM HEUTE'), findsOneWidget);
      expect(find.textContaining('/12 min'), findsOneWidget);
    });

    testWidgets('sperrt Konfiguration bei aufgebrauchtem Budget',
        (tester) async {
      h.completeOnboarding();
      await h.store.logUsage('system', const Duration(minutes: 13));
      await pumpPhone(tester, h.wrap(const SystemScreen()));
      expect(find.textContaining('Budget aufgebraucht'), findsOneWidget);
    });
  });

  group('Zustand', () {
    testWidgets('zeigt alle sechs Dimensionen', (tester) async {
      h.completeOnboarding();
      await pumpPhone(tester, h.wrap(const StateScreen()));
      for (final label in [
        'KAPAZITÄT',
        'KOMPENSATIONSLAST',
        'REIZBEDARF',
        'FOKUSLAST HEUTE',
        'REGULATIONSRESERVE',
        'SCHLAFSCHULD',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('grenzt sich von Diagnostik ab', (tester) async {
      h.completeOnboarding();
      await pumpPhone(tester, h.wrap(const StateScreen()));
      await tester.dragUntilVisible(
        find.text('EINORDNUNG'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      expect(find.textContaining('keine Diagnose'), findsOneWidget);
    });
  });

  group('Beide Helligkeiten', () {
    for (final brightness in Brightness.values) {
      testWidgets('rendert in ${brightness.name} ohne Ueberlauf',
          (tester) async {
        h.completeOnboarding();
        await pumpPhone(
          tester,
          h.wrap(const NowScreen(), brightness: brightness),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Kleines Geraet', () {
    testWidgets('laeuft auf 360x640 ohne Overflow', (tester) async {
      h.completeOnboarding();
      await pumpPhone(tester, h.wrap(const NowScreen()),
          size: const Size(360, 640));
      expect(tester.takeException(), isNull);
    });
  });
}

/// Gate ohne Splash-Verzoegerung fuer Tests.
class HomeShellGate extends StatelessWidget {
  const HomeShellGate({super.key});

  @override
  Widget build(BuildContext context) => const AxiomGate();
}

