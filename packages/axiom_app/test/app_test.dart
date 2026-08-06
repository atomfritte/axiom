/// Verhaltenstests der Oberflaeche.
///
/// Geprueft wird nicht "sieht es aus wie gestern", sondern ob die
/// Designgesetze in der laufenden App tatsaechlich gelten: genau eine
/// Handlung (G1), sichtbare Regel-ID (G2), keine Schuldsprache.
library;

import 'dart:async';
import 'dart:io';

import 'package:axiom_app/app.dart';
import 'package:axiom_app/design/tokens.dart';
import 'package:axiom_app/design/widgets/capacity_line.dart';
import 'package:axiom_app/design/widgets/instruments.dart';
import 'package:axiom_app/screens/anchors_screen.dart';
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

    testWidgets('die Zurücktaste führt auf „Jetzt", nicht aus der App',
        (tester) async {
      // Vorher schloss die Zurücktaste auf jedem Nebenreiter die App. Auf
      // Android ist das der häufigste Griff überhaupt, und er bedeutet dort
      // „eine Ebene höher". Wer bloß nachsehen wollte, verlor damit die
      // Handlung, wegen der er die App geöffnet hatte [D9].
      h.completeOnboarding();
      await pumpPhone(tester, h.wrap(const HomeShellGate()));

      await tester.tap(find.text('System'));
      await tester.pumpAndSettle();
      expect(find.byType(SystemScreen), findsOneWidget);

      await tester.state<NavigatorState>(find.byType(Navigator).first)
          .maybePop();
      await tester.pumpAndSettle();

      expect(find.byType(NowScreen), findsOneWidget);
      expect(find.byType(SystemScreen), findsNothing);
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
      expect(find.text('Jetzt'), findsOneWidget);
      expect(find.text('Anfangen').evaluate().length, lessThanOrEqualTo(1));
    });

    testWidgets('genau eine Fläche liegt in Griffhöhe', (tester) async {
      // Die Karte ist nicht deshalb die Handlung, weil „Jetzt" darübersteht,
      // sondern weil sie als einzige über dem Grund schwebt. Vorher trug
      // fast jede Fläche dieses Schirms einen farbigen Rahmen, und zwölf
      // gerahmte Kästen untereinander sind ein Gitter: alles gleich weit
      // weg, jede Fläche ein Angebot. Das ist kein Layoutgeschmack — es ist
      // die Frage, ob man die eine Handlung vorbewusst findet (G1).
      h.completeOnboarding();
      for (var i = 0; i < 4; i++) {
        await h.runtime.createTask(
          title: 'Aufgabe $i', activationEnergy: 2, salience: 5, stakes: 5);
      }
      await pumpPhone(tester, h.wrap(const NowScreen()));

      final raised = tester
          .widgetList<Panel>(find.byType(Panel))
          .where((p) => p.reachable)
          .length;
      expect(raised, 1);
    });

    testWidgets('die Reichweitenkante trennt beide Schirme', (tester) async {
      // Sie ist keine Verzierung: Über ihr steht, was heute in die Hand
      // geht, unter ihr, was da ist und heute nicht. Ohne sie ist die
      // Mulde nur eine zweite Farbe.
      h.completeOnboarding();
      await h.runtime.createTask(
        title: 'Wohnung streichen', activationEnergy: 9, salience: 5,
        stakes: 5);

      await pumpPhone(tester, h.wrap(const NowScreen()));
      expect(find.byType(ReachEdge), findsOneWidget);
      expect(find.byType(Well), findsOneWidget);
      await unmount(tester);

      await pumpPhone(tester, h.wrap(const TasksScreen()));
      expect(find.byType(ReachEdge), findsOneWidget);
      expect(find.byType(Well), findsOneWidget);
    });

    testWidgets('ein Messwert steht an genau einem Ort', (tester) async {
      // Unter der Kante standen Kapazität, Kompensationslast und Reizbedarf
      // als Balken samt aufklappbarer Herleitung — dieselben drei, die einen
      // Reiter weiter auf „Zustand" stehen. „Reichweite heute 61" und
      // „Kapazität 61" waren dabei dieselbe Zahl unter zwei Namen, drei
      // Zentimeter auseinander. Zwei Anzeigen desselben Messwerts lesen sich
      // als zwei Aussagen (R7), und jede davon ist auf diesem Schirm ein
      // zweites Angebot neben der einen Handlung (G1).
      h.completeOnboarding();
      await pumpPhone(tester, h.wrap(const NowScreen()));
      expect(find.byType(ReachEdge), findsOneWidget);
      expect(find.byType(InstrumentBar), findsNothing);
      await unmount(tester);

      await pumpPhone(tester, h.wrap(const StateScreen()));
      expect(find.byType(InstrumentBar), findsWidgets);
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

  group('Die Wege unter der Kante', () {
    /// Die Mulde ist der Bestandsnachweis der App: Was es gibt, steht hier,
    /// und zwar **immer an derselben Stelle**. Vorher erschien jede Zeile
    /// nur bei Inhalt — ein Weg, den es nur manchmal gibt, wird jedes Mal
    /// neu gesucht [D9].
    const wege = ['Aufgaben', 'Eingang', 'Anker', 'Tag-Review', 'Vorfälle'];

    testWidgets('jeder Weg hat einen festen Platz, auch wenn nichts da ist',
        (tester) async {
      h.completeOnboarding();
      await pumpPhone(tester, h.wrap(const NowScreen()));

      for (final label in wege) {
        await tester.dragUntilVisible(
          find.text(label),
          find.byType(ListView),
          const Offset(0, -200),
        );
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('ein Anker lässt sich anlegen, bevor es einen gibt',
        (tester) async {
      // Die Ankerverwaltung hing allein am Streifen über der Kante, und den
      // gibt es nur, wenn schon ein Anker mit nächstem Schritt existiert.
      // Der erste Anker war aus der laufenden App heraus nicht anzulegen —
      // nur über eine Geräteverknüpfung, die man dafür kennen muss.
      h.completeOnboarding();
      await pumpPhone(tester, h.wrap(const NowScreen()));
      await tester.dragUntilVisible(
        find.text('Anker'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.tap(find.text('Anker'));
      await tester.pumpAndSettle();

      expect(find.byType(AnchorsScreen), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('der Rückblick bleibt erreichbar, wenn er nicht fällig ist',
        (tester) async {
      // Er hing an `isReviewDue`. Nach dem Abhaken war der Schirm mit den
      // Zahlen der letzten Tage bis zum nächsten Fälligkeitsfenster nirgends
      // mehr zu öffnen — obwohl genau dort steht, was die Woche ergeben hat.
      h.completeOnboarding();
      h.runtime.markReviewDone(ReviewScope.day);
      await pumpPhone(tester, h.wrap(const NowScreen()));

      await tester.dragUntilVisible(
        find.text('Tag-Review'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      expect(find.text('Tag-Review'), findsOneWidget);
      // Und ohne die Behauptung, er sei fällig.
      expect(find.textContaining('Fällig'), findsNothing);
    });

    test('„System" ist kein zweiter Ort für Inhalte', () {
      // Aufgabenliste und Vorfallprotokoll standen dort ein zweites Mal.
      // Zwei Wege zu einer Liste sind kein Entgegenkommen, sondern zwei
      // Orte, an denen man sie suchen kann — und „System" wurde damit zur
      // Restekiste statt zur Maschine.
      final source =
          File('lib/screens/system_screen.dart').readAsStringSync();
      expect(source, isNot(contains('TasksScreen')));
      expect(source, isNot(contains('SignalScreen')));
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

    testWidgets('jede offene Aufgabe lässt sich von hier aus zerlegen',
        (tester) async {
      // Ohne diesen Weg gibt es nur den einen, den AXIOM von sich aus
      // anbietet — und ein Teilschritt, der immer noch zu gross ist, faellt
      // dann durch jedes Raster [D2].
      h.completeOnboarding();
      await h.runtime.createTask(
        title: 'Wohnung streichen', activationEnergy: 9, salience: 5,
        stakes: 5);
      await pumpPhone(tester, h.wrap(const TasksScreen()));

      expect(find.text('Zerlegen'), findsOneWidget);
      await tester.tap(find.text('Zerlegen'));
      await tester.pumpAndSettle();
      expect(find.text('Was ist die allererste Handlung?'), findsOneWidget);
    });

    testWidgets('unter der Kante wird nichts angeboten außer dem Weg nach oben',
        (tester) async {
      // Die Tiefzone hatte bisher denselben Knopfsatz wie die Zone darüber
      // — „Anfangen" inklusive. Das ist ein Angebot, das die Messung
      // daneben im selben Atemzug zurücknimmt: Die Startenergie liegt über
      // der heutigen Kapazität, und genau deshalb steht die Aufgabe hier
      // unten. Ein Weg, der ins Leere führt, kostet mehr als keiner (G1).
      h.completeOnboarding();
      await h.runtime.createTask(
        title: 'Wohnung streichen', activationEnergy: 10, salience: 5,
        stakes: 5);
      await pumpPhone(tester, h.wrap(const TasksScreen()));

      expect(find.textContaining('Nicht in Reichweite'), findsOneWidget);
      expect(find.text('Anfangen'), findsNothing);
      expect(find.text('Zerlegen'), findsOneWidget);
      // Und trotzdem abhakbar: Dass etwas auf anderem Weg erledigt wurde,
      // muss sich immer eintragen lassen [D9].
      expect(find.text('Erledigt'), findsOneWidget);
    });

    testWidgets('unter der Kante wird nichts ausgegraut', (tester) async {
      // Ausgegraut hieße „unwichtig"; gemeint ist „heute nicht erreichbar".
      // Der Unterschied ist der ganze Punkt der Signatur — deshalb behält
      // der Titel dort seine Textrolle und damit seinen vollen Kontrast
      // (R7, D10).
      h.completeOnboarding();
      await h.runtime.createTask(
        title: 'Wohnung streichen', activationEnergy: 10, salience: 5,
        stakes: 5);
      await pumpPhone(tester, h.wrap(const TasksScreen()));

      final palette = AxiomScheme.instrument.palette(Brightness.dark);
      final title = tester.widget<Text>(find.text('Wohnung streichen'));
      expect(title.style?.color, isNot(palette.inkFaint));
      expect(title.style?.decoration, isNot(TextDecoration.lineThrough));
    });

    testWidgets('eine zerlegte Aufgabe bleibt sichtbar und zerlegbar',
        (tester) async {
      // Vorher stand sie nirgends: nicht bei „In Reichweite", nicht bei
      // „Nicht in Reichweite", nicht bei „Erledigt". Wer seinen Bestand
      // nicht sieht, fuehrt daneben eine zweite Liste im Kopf [D9].
      h.completeOnboarding();
      final parent = await h.runtime.createTask(
        title: 'Steuerunterlagen sortieren', activationEnergy: 9,
        salience: 5, stakes: 5);
      await h.runtime.atomize(
        parent: parent,
        steps: [(title: 'Ordner holen', energy: 1)],
      );
      await pumpPhone(tester, h.wrap(const TasksScreen()));

      expect(find.text('Steuerunterlagen sortieren'), findsOneWidget);
      expect(find.text('Zerlegt · 1'), findsOneWidget);
      expect(find.text('Schritte offen: 1'), findsOneWidget);
      // Sie steht nicht neben ihren eigenen Schritten zur Wahl (G1) …
      expect(find.text('Anfangen'), findsOneWidget);
      // … laesst sich aber weiter zerlegen.
      expect(find.text('Zerlegen'), findsNWidgets(2));
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
      // Die Regel ist die Instanz, die entscheidet (G2) — sie schlägt jede
      // laufende Vertiefung. Sichtbar bleiben muss die Aufgabe trotzdem,
      // sonst ist sie genau dann weg, wenn etwas dazwischenkommt.
      //
      // Eigene Uhrzeit statt der des Testblocks: 09:00 liegt im Fenster von
      // R-001 („Check-in Morgen", 08:45–09:30), und bei frischem Stand ist
      // `count_today(checkin) < 1` erfüllt — die Regel feuert damit *durch
      // Konstruktion* und nicht, weil zufällig gerade eine passt. Der
      // frühere Stand lief um 12:15 und behauptete im Kommentar einen
      // Mittags-Check-in, den es zu dieser Zeit nie gab; er hielt nur,
      // solange irgendeine andere Regel zufällig griff.
      final morning = TestHarness.create(at: DateTime(2026, 8, 3, 9));
      addTearDown(morning.dispose);
      morning.completeOnboarding();
      final task = await morning.runtime.createTask(
        title: 'Etwas Angefangenes',
        activationEnergy: 2, salience: 5, stakes: 5);
      await morning.runtime.startTask(task);

      // Zwei Fallen, beide hier hineingelaufen und beide vermerkt:
      //
      // Kein `evaluate()` vorab, um die Lage zu prüfen. Regeln tragen
      // `max_per_day`, und jede Auswertung verbraucht das Kontingent — der
      // Vorab-Blick nimmt dem Bildschirm genau die Regel weg, die er zeigen
      // soll, und die zweitbeste rückt nach.
      //
      // Und keine Prüfung auf eine bestimmte Kennung. Welche Regel um 09:00
      // gewinnt, hängt an Prioritäten und Cooldowns des ganzen Regelwerks;
      // ein Test, der das festschreibt, fällt bei jeder neuen Regel um,
      // ohne dass etwas kaputt wäre. Geprüft wird die Zusicherung: Es steht
      // *eine* Regel da, mit Kennung (G2).
      await pumpPhone(tester, morning.wrap(const NowScreen()));
      expect(find.textContaining('R-'), findsWidgets);
      // … und die laufende Aufgabe bleibt daneben sichtbar.
      expect(find.text('Läuft'), findsWidgets);
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
      expect(find.text('Jetzt'), findsOneWidget);
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
      expect(findLabel('Begründung'), findsOneWidget);
      expect(findLabel('Bedingung'), findsOneWidget);
    });

    testWidgets('Messwerte lassen sich zur Herleitung aufklappen',
        (tester) async {
      h.completeOnboarding();
      await pumpPhone(tester, h.wrap(const StateScreen()));

      expect(find.byType(InstrumentBar), findsWidgets);
      await tester.tap(find.text('Kapazität'));
      await tester.pumpAndSettle();
      expect(find.text('So wird gerechnet'), findsOneWidget);
      // Und die Rechnung geht auf: Ohne Summe und Rest stand die sichtbare
      // Formel neben einer anderen gerechneten (G2).
      expect(find.text('Summe der Terme'), findsOneWidget);
      expect(find.text('Angezeigt'), findsOneWidget);
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
      expect(find.text('Kapazität'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
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
        find.text('Zeit im System heute'),
        find.byType(ListView),
        const Offset(0, -250),
      );
      expect(find.text('Zeit im System heute'), findsOneWidget);
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
        'Kapazität',
        'Kompensationslast',
        'Reizbedarf',
        'Fokuslast heute',
        'Regulationsreserve',
        'Schlafschuld',
      ]) {
        expect(findLabel(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('grenzt sich von Diagnostik ab', (tester) async {
      h.completeOnboarding();
      await pumpPhone(tester, h.wrap(const StateScreen()));
      await tester.dragUntilVisible(
        findLabel('Einordnung'),
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

/// Findet eine Beschriftung, ohne ihre Schreibweise festzuschreiben.
///
/// Ob eine Marke „Kapazität" oder „KAPAZITÄT" heisst, ist eine Frage der
/// Typografie, und die entscheidet `typography_test.dart`. Die Tests hier
/// halten etwas anderes fest — dass die Angabe ueberhaupt dasteht. Beides in
/// derselben Zusicherung zu vermischen macht diese Datei bei jeder
/// Schriftaenderung rot, ohne dass etwas fehlen wuerde.
Finder findLabel(String text) => find.byWidgetPredicate(
      (w) => w is Text && (w.data ?? '').toUpperCase() == text.toUpperCase(),
      description: 'Text „$text" (Schreibweise egal)',
    );

/// Gate ohne Splash-Verzoegerung fuer Tests.
class HomeShellGate extends StatelessWidget {
  const HomeShellGate({super.key});

  @override
  Widget build(BuildContext context) => const AxiomGate();
}

