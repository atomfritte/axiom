/// Verhaltenstests der Oberflaeche.
///
/// Geprueft wird nicht "sieht es aus wie gestern", sondern ob die
/// Designgesetze in der laufenden App tatsaechlich gelten: genau eine
/// Handlung (G1), sichtbare Regel-ID (G2), keine Schuldsprache.
library;

import 'dart:async';
import 'dart:io';

import 'package:axiom_app/app.dart';
import 'package:axiom_app/design/widgets/capacity_line.dart';
import 'package:axiom_app/design/widgets/instruments.dart';
import 'package:axiom_app/screens/capture_sheet.dart';
import 'package:axiom_app/screens/inbox_screen.dart';
import 'package:axiom_app/screens/rule_editor_screen.dart';
import 'package:axiom_app/state/runtime.dart';
import 'package:axiom_app/screens/now_screen.dart';
import 'package:axiom_app/screens/onboarding_screen.dart';
import 'package:axiom_app/screens/state_screen.dart';
import 'package:axiom_app/screens/system_screen.dart';
import 'package:axiom_app/screens/tasks_screen.dart';
import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
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
    testWidgets('sechs Schritte, jeder ueberspringbar', (tester) async {
      await pumpPhone(tester, h.wrap(OnboardingScreen(onDone: () {})));

      expect(find.text('1/6'), findsOneWidget);
      expect(find.text('Überspringen'), findsOneWidget);

      for (var i = 2; i <= 6; i++) {
        await tester.tap(find.text('Weiter').last);
        await tester.pumpAndSettle();
        expect(find.text('$i/6'), findsOneWidget);
      }
      expect(find.text('Los geht’s'), findsOneWidget);
    });

    testWidgets('fragt Health Connect, ohne es vorauszusetzen',
        (tester) async {
      // Die drei Systemrechte davor sind Voraussetzungen. Das hier ist eine
      // Entscheidung — und sie muss als solche gestellt werden, samt der
      // Aussage, was gelesen wird und was nicht.
      await pumpPhone(tester, h.wrap(OnboardingScreen(onDone: () {})));
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text('Weiter').last);
        await tester.pumpAndSettle();
      }
      expect(find.text('6/6'), findsOneWidget);
      // Im Test laeuft die App nicht auf Android. Die Seite sagt dann, was
      // dort gilt, statt eine Freigabe anzubieten, die es nicht gibt —
      // dieselbe Ehrlichkeit wie ueberall an der Systemgrenze.
      expect(find.textContaining('nur auf Android'), findsWidgets);
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

    testWidgets('eine angefangene Aufgabe bleibt sichtbar und abschließbar',
        (tester) async {
      // Der teuerste Fehler dieser Oberfläche: „Anfangen" setzte den
      // Zustand auf `active`, und `active` fällt aus `startable` heraus.
      // Die Aufgabe war damit weg — nicht abschließbar, nicht auffindbar,
      // nirgends sichtbar [D9].
      h.completeOnboarding();
      final task = await h.runtime.createTask(
        title: 'Steuerunterlagen sortieren',
        activationEnergy: 2,
        salience: 5,
        stakes: 5,
      );
      await h.runtime.startTask(task);

      // Auf „Jetzt" muss sie zu sehen sein — als Karte, wenn keine Regel
      // feuert, sonst als Streifen über der Regelkarte.
      await pumpPhone(tester, h.wrap(const NowScreen()));
      expect(find.text('Steuerunterlagen sortieren'), findsWidgets);
      // Kein Vorschlag, etwas anderes anzufangen, solange etwas läuft (G1).
      expect(find.text('Anfangen'), findsNothing);
      await unmount(tester);

      // Und sie muss sich abschließen lassen.
      await pumpPhone(tester, h.wrap(const TasksScreen()));
      expect(find.text('Erledigt'), findsOneWidget);
      expect(find.text('Zurücklegen'), findsOneWidget);
    });

    testWidgets('es läuft immer höchstens eine Aufgabe', (tester) async {
      h.completeOnboarding();
      final first = await h.runtime.createTask(
        title: 'Erste', activationEnergy: 2, salience: 5, stakes: 5);
      final second = await h.runtime.createTask(
        title: 'Zweite', activationEnergy: 2, salience: 5, stakes: 5);

      await h.runtime.startTask(first);
      await h.runtime.startTask(second);

      final active = (await h.store.tasks(states: {TaskState.active}))
          .map((t) => t.title)
          .toList();
      expect(active, ['Zweite']);
    });

    testWidgets('abschließen beendet auch das Fokusfenster', (tester) async {
      h.completeOnboarding();
      final task = await h.runtime.createTask(
        title: 'Kurz was', activationEnergy: 2, salience: 5, stakes: 5);
      await h.runtime.startTask(task);
      expect(await h.store.activeFocus(), isNotNull);

      await h.runtime.completeTask(task);
      // Zeit auf etwas zu buchen, das es nicht mehr gibt, wäre eine
      // Messung ohne Gegenstand.
      expect(await h.store.activeFocus(), isNull);
    });
  });

  group('Die Liste ist erreichbar, aber nicht der Standardweg', () {
    testWidgets('zeigt den ganzen Bestand, auch das Laufende',
        (tester) async {
      h.completeOnboarding();
      for (final (title, ae) in [('Leicht', 2), ('Schwer', 10)]) {
        await h.runtime.createTask(
          title: title, activationEnergy: ae, salience: 5, stakes: 5);
      }
      final all = await h.store.tasks();
      await h.runtime.startTask(all.firstWhere((t) => t.title == 'Leicht'));
      await pumpPhone(tester, h.wrap(const TasksScreen()));

      // Nichts wird versteckt, nur eingeordnet — verbieten tut AXIOM
      // nichts (G3). Auch die laufende Aufgabe steht hier.
      expect(find.text('Leicht'), findsOneWidget);
      expect(find.text('Schwer'), findsOneWidget);
      expect(find.text('Zurücklegen'), findsOneWidget);
    });

    testWidgets('sortiert nach der Formel und bietet keinen zweiten Maßstab',
        (tester) async {
      h.completeOnboarding();
      await h.runtime.createTask(
        title: 'Egal', activationEnergy: 2, salience: 5, stakes: 5);
      await pumpPhone(tester, h.wrap(const TasksScreen()));

      // Sortierregler und Filterleisten waeren Meta-Work mit Aussicht (D3).
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.textContaining('Sortieren nach'), findsNothing);
      expect(find.textContaining('Reihenfolge ist die der Auswahl'),
          findsOneWidget);
    });

    testWidgets('eine feuernde Regel schlägt die laufende Aufgabe',
        (tester) async {
      // Die Regel ist die Instanz, die entscheidet (G2) — ein Termin in
      // zehn Minuten schlägt jede laufende Vertiefung. Sichtbar bleiben
      // muss die Aufgabe trotzdem, sonst ist sie genau dann weg, wenn
      // etwas dazwischenkommt.
      h.completeOnboarding();
      final task = await h.runtime.createTask(
        title: 'Etwas Angefangenes',
        activationEnergy: 2, salience: 5, stakes: 5);
      await h.runtime.startTask(task);
      await pumpPhone(tester, h.wrap(const NowScreen()));

      // Um 12:15 feuert der Mittags-Check-in. Er bekommt die Karte …
      expect(find.textContaining('R-'), findsWidgets);
      // … und die laufende Aufgabe bleibt daneben sichtbar.
      expect(find.text('LÄUFT'), findsWidgets);
      expect(find.text('Etwas Angefangenes'), findsWidgets);
    });

    testWidgets('„Jetzt" zeigt trotzdem weiter genau eine Handlung',
        (tester) async {
      // Die Liste darf G1 nicht durch die Hintertuer aushebeln.
      h.completeOnboarding();
      for (var i = 0; i < 4; i++) {
        await h.runtime.createTask(
          title: 'Aufgabe $i', activationEnergy: 2, salience: 5, stakes: 5);
      }
      await pumpPhone(tester, h.wrap(const NowScreen()));
      expect(find.text('JETZT'), findsOneWidget);
      expect(find.text('Anfangen').evaluate().length, lessThanOrEqualTo(1));
    });
  });

  group('G4 — Selbstbegrenzung', () {
    testWidgets('der Regeleditor macht zu, wenn das Budget aufgebraucht ist',
        (tester) async {
      // Das wichtigste Gesetz dieses Projekts war reine Dekoration:
      // `isConfigLocked()` gab es, aufgerufen hat sie niemand, und die
      // Nutzungszeit wurde nur auf zwei Bildschirmen gebucht. Das
      // Hauptrisiko ist nicht technisches Scheitern, sondern dass das Bauen
      // des Systems zur Prokrastination wird (R1).
      h.completeOnboarding();
      expect(await h.runtime.isConfigLocked(), isFalse);

      await h.store.logUsage('rules', kMetaBudget + const Duration(minutes: 1));
      expect(await h.runtime.isConfigLocked(), isTrue);

      await pumpPhone(tester, h.wrap(Builder(
        builder: (context) => TextButton(
          onPressed: () => showRuleEditor(context),
          child: const Text('auf'),
        ),
      )));
      await tester.tap(find.text('auf'));
      await tester.pumpAndSettle();

      // Kein Editor, sondern die Begruendung — mit Regel-ID (G2).
      expect(find.text('Regelwerk heute zu'), findsOneWidget);
      expect(find.textContaining('R-010'), findsWidgets);
      // Und ohne Vorwurf.
      expect(find.textContaining('keine Strafe'), findsOneWidget);
    });

    test('jeder Bildschirm, auf dem man sich verliert, zählt mit', () {
      // Gebucht wurde vorher nur auf zwei Bildschirmen. Wer im Regeleditor,
      // im Systemcheck oder im Expertenmodus versackte, verbrauchte kein
      // Budget — und der Deckel griff nie. Ein Deckel, der nicht misst, ist
      // keiner.
      const timed = [
        'check_screen', 'channels_screen', 'expert_screen',
        'rule_editor_screen', 'system_screen', 'review_screen',
        'state_screen', 'vault_screen', 'signal_screen',
        'anchors_screen', 'sensation_screen', 'intercept_screen',
        'tasks_screen',
      ];
      for (final name in timed) {
        final source = File('lib/screens/$name.dart').readAsStringSync();
        expect(
          source.contains('MetaTimed') || source.contains('logScreenTime'),
          isTrue,
          reason: '$name bucht keine Zeit auf das Meta-Work-Budget',
        );
      }

      // Und das Gegenstueck: Erfassung darf nie mitzaehlen (G1).
      for (final name in ['capture_sheet', 'now_screen']) {
        final source = File('lib/screens/$name.dart').readAsStringSync();
        expect(source, isNot(contains('MetaTimed')), reason: name);
      }
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

