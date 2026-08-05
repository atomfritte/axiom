/// Ortsgebundene Aufgaben in der laufenden App.
///
/// Geprueft wird das Verhalten, nicht die Verdrahtung: Was wird vorgeschlagen,
/// was verschwindet, und vor allem — was passiert, solange niemand einen Ort
/// gesetzt hat. Der Ort ist ein Name, kein Geofence; es gibt in dieser App
/// keine Standortberechtigung und keine Koordinate, die geprueft werden
/// koennte.
library;

import 'package:axiom_app/screens/now_screen.dart';
import 'package:axiom_app/screens/place_sheet.dart';
import 'package:axiom_app/screens/tasks_screen.dart';
import 'package:axiom_core/axiom_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  late TestHarness h;

  // Mittags: kein Zeitfenster einer mitgelieferten Regel liegt hier. Sonst
  // belegt eine feuernde Regel die Hauptkarte, und geprueft waere ihr
  // Vorrang statt der Ortsauswahl.
  setUp(() => h = TestHarness.create(at: DateTime(2026, 8, 3, 12, 20)));
  tearDown(() => h.dispose());

  group('Ohne gesetzten Ort aendert sich nichts', () {
    testWidgets('eine ortsgebundene Aufgabe wird ganz normal vorgeschlagen',
        (tester) async {
      h.completeOnboarding();
      await h.runtime.createTask(
        title: 'Dichtungsring kaufen',
        activationEnergy: 2,
        salience: 5,
        stakes: 5,
        place: 'Baumarkt',
      );

      await pumpPhone(tester, h.wrap(const NowScreen()));
      expect(find.text('Dichtungsring kaufen'), findsWidgets);
      expect(find.text('Anfangen'), findsOneWidget);
      // Sie steht mit ihrem Ort da, statt heimlich zu verschwinden [D9].
      expect(find.text('BAUMARKT'), findsWidgets);
    });

    testWidgets('die Ortszeile erscheint erst, wenn es etwas zu sehen gibt',
        (tester) async {
      // Eine Einstellung ohne Wirkung gehoert nicht auf den
      // Hauptbildschirm — jede Zeile dort kostet Aufmerksamkeit (D3).
      h.completeOnboarding();
      await h.runtime.createTask(
        title: 'Irgendwas', activationEnergy: 2, salience: 5, stakes: 5);
      await pumpPhone(tester, h.wrap(const NowScreen()));
      expect(find.text('Kein Ort'), findsNothing);
      await unmount(tester);

      await h.runtime.createTask(
        title: 'Regal aufbauen',
        activationEnergy: 2,
        salience: 5,
        stakes: 5,
        place: 'Zuhause',
      );
      await pumpPhone(tester, h.wrap(const NowScreen()));
      expect(find.text('Kein Ort'), findsOneWidget);
    });
  });

  group('Mit gesetztem Ort', () {
    testWidgets('eine Aufgabe fuer einen anderen Ort wird nicht vorgeschlagen',
        (tester) async {
      h.completeOnboarding();
      await h.runtime.createTask(
        title: 'Dichtungsring kaufen',
        activationEnergy: 2,
        salience: 9,
        stakes: 9,
        place: 'Baumarkt',
      );
      await h.runtime.createTask(
        title: 'Rechnung prüfen',
        activationEnergy: 2,
        salience: 3,
        stakes: 3,
        place: 'Büro',
      );
      await h.runtime.setPlace('Büro');

      await pumpPhone(tester, h.wrap(const NowScreen()));
      // Trotz hoeherem Score bleibt die Baumarkt-Aufgabe aussen vor: Sie
      // vorzuschlagen hiesse, eine Handlung anzubieten, die hier nicht geht.
      expect(find.text('Rechnung prüfen'), findsWidgets);
      expect(find.text('Dichtungsring kaufen'), findsNothing);
    });

    testWidgets('ortsungebundene Aufgaben bleiben unberuehrt', (tester) async {
      h.completeOnboarding();
      await h.runtime.createTask(
        title: 'Überall möglich', activationEnergy: 2, salience: 5, stakes: 5);
      await h.runtime.setPlace('Baumarkt');

      await pumpPhone(tester, h.wrap(const NowScreen()));
      expect(find.text('Überall möglich'), findsWidgets);
    });

    testWidgets('die Liste zeigt sie weiter — unter eigenem Titel',
        (tester) async {
      // Ein Bestand, aus dem etwas unbemerkt herausfaellt, wird nicht mehr
      // geglaubt. Und der Grund muss stimmen: „nicht in Reichweite" waere
      // hier schlicht falsch, die Startenergie hat damit nichts zu tun.
      h.completeOnboarding();
      await h.runtime.createTask(
        title: 'Dichtungsring kaufen',
        activationEnergy: 2,
        salience: 5,
        stakes: 5,
        place: 'Baumarkt',
      );
      await h.runtime.setPlace('Büro');

      await pumpPhone(tester, h.wrap(const TasksScreen()));
      expect(find.text('Dichtungsring kaufen'), findsOneWidget);
      expect(find.textContaining('ANDERSWO'), findsOneWidget);
      // Und nicht unter dem falschen Grund: Mit der Startenergie hat es
      // nichts zu tun.
      expect(find.textContaining('NICHT IN REICHWEITE'), findsNothing);
    });
  });

  group('Umschalten — zwei Tipps', () {
    testWidgets('Ortszeile antippen, Eintrag antippen, fertig', (tester) async {
      h.completeOnboarding();
      await h.runtime.createTask(
        title: 'Dichtungsring kaufen',
        activationEnergy: 2,
        salience: 5,
        stakes: 5,
        place: 'Baumarkt',
      );
      await pumpPhone(tester, h.wrap(const NowScreen()));

      // Erster Tipp: die Zeile.
      await tester.tap(find.text('Kein Ort'));
      await tester.pumpAndSettle();
      expect(find.byType(PlaceChips), findsNothing);
      // Der bekannte Ort steht zur Wahl, ohne dass er getippt werden muss.
      expect(find.text('Baumarkt'), findsOneWidget);

      // Zweiter Tipp: der Ort.
      await tester.tap(find.text('Baumarkt'));
      await tester.pumpAndSettle();
      expect(await h.runtime.currentPlace(), 'Baumarkt');
    });

    testWidgets('und zurueck auf „kein Ort" genauso schnell', (tester) async {
      h.completeOnboarding();
      await h.runtime.createTask(
        title: 'Dichtungsring kaufen',
        activationEnergy: 2,
        salience: 5,
        stakes: 5,
        place: 'Baumarkt',
      );
      await h.runtime.setPlace('Büro');
      await pumpPhone(tester, h.wrap(const NowScreen()));

      await tester.tap(find.text('Büro'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kein Ort'));
      await tester.pumpAndSettle();
      expect(await h.runtime.currentPlace(), isNull);
    });
  });

  group('Der Ort ist append-only', () {
    test('jeder Wechsel ist ein Ereignis, kein ueberschriebenes Feld',
        () async {
      await h.runtime.setPlace('Büro');
      h.clock.advance(const Duration(hours: 2));
      await h.runtime.setPlace('Baumarkt');
      h.clock.advance(const Duration(hours: 1));
      await h.runtime.setPlace(null);

      final events = await h.store.query(types: {EventType.placeEntered});
      expect(events.map((e) => e.payload['place']), ['Büro', 'Baumarkt', '']);
      expect(await h.runtime.currentPlace(), isNull);
    });

    test('eine Geraeteroutine ist als Quelle unterscheidbar', () async {
      // Damit spaeter nachlesbar bleibt, ob ein Ort von Hand oder von einer
      // Routine kam — und ob die Routine ueberhaupt etwas taugt.
      await h.runtime.setPlace('Büro', source: EventSource.device);
      final event = await h.store.last(EventType.placeEntered);
      expect(event!.source, EventSource.device);
    });

    test('bekannte Orte stehen mit dem zuletzt gesetzten vorn', () async {
      await h.runtime.setPlace('Büro');
      h.clock.advance(const Duration(hours: 1));
      await h.runtime.setPlace('Baumarkt');
      await h.runtime.createTask(
        title: 'Regal aufbauen',
        activationEnergy: 2,
        salience: 5,
        stakes: 5,
        place: 'Zuhause',
      );

      expect(await h.runtime.knownPlaces(), ['Baumarkt', 'Büro', 'Zuhause']);
    });
  });

  group('Fristdruck (R-140)', () {
    test('die Regel sieht die Stunden und den Anlauf des Bestands', () async {
      // Anlauf einer Aufgabe mit Startenergie 8: 8 x 15 min + 30 min = 2,5 h.
      // Bei zwei Stunden Restzeit reicht das rechnerisch nicht mehr.
      await h.runtime.createTask(
        title: 'Steuerunterlagen',
        activationEnergy: 8,
        salience: 5,
        stakes: 9,
        decayAt: h.clock.nowLocal().add(const Duration(hours: 2)),
      );

      final ctx = await h.runtime.currentContext();
      expect(ctx.numeric('hours_to_deadline'), 2.0);
      expect(ctx.numeric('deadline_slack_hours'), -0.5);
    });

    test('ohne Frist steht ein Wert da, kein Fehler', () async {
      await h.runtime.createTask(
        title: 'Ohne Frist', activationEnergy: 3, salience: 5, stakes: 5);
      final ctx = await h.runtime.currentContext();
      expect(ctx.numeric('hours_to_deadline'), kNoDeadlineHours);
      expect(ctx.numeric('deadline_slack_hours'), kNoDeadlineHours);
    });

    testWidgets('die Liste zeigt den Anlauf erst, wenn er nicht mehr passt',
        (tester) async {
      // Eine Zahl, die immer da ist, wird nicht gelesen. Sichtbar wird die
      // Formel genau dann, wenn sie etwas aussagt (G2).
      h.completeOnboarding();
      await h.runtime.createTask(
        title: 'Steuerunterlagen',
        activationEnergy: 8,
        salience: 5,
        stakes: 9,
        decayAt: h.clock.nowLocal().add(const Duration(hours: 2)),
      );
      await pumpPhone(tester, h.wrap(const TasksScreen()));
      expect(find.textContaining('ANLAUF'), findsOneWidget);
      await unmount(tester);

      h.dispose();
      h = TestHarness.create(at: DateTime(2026, 8, 3, 12, 20));
      h.completeOnboarding();
      await h.runtime.createTask(
        title: 'Steuerunterlagen',
        activationEnergy: 8,
        salience: 5,
        stakes: 9,
        decayAt: h.clock.nowLocal().add(const Duration(days: 4)),
      );
      await pumpPhone(tester, h.wrap(const TasksScreen()));
      expect(find.textContaining('ANLAUF'), findsNothing);
    });

    test('R-140 ist ausgeliefert und laeuft stumm mit', () async {
      final found = h.runtime.rules.where((r) => r.id == 'R-140').toList();
      expect(found, hasLength(1), reason: 'Die Regel muss im Bundle liegen');
      final rule = found.single;
      expect(rule.isShadow, isTrue,
          reason: 'Jede neue Regel laeuft sieben Tage stumm (CLAUDE.md)');
      expect(rule.rationale.trim(), isNotEmpty);
      expect(rule.cooldown.minInterval, greaterThan(Duration.zero));
    });
  });
}
