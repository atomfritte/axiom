/// Erledigtes im Aufgabenbestand: gezählt, zugeklappt, wiederfindbar.
///
/// Geprüft wird die Wirkung, nicht die Verdrahtung — was auf dem Schirm
/// steht, was nach einem Neustart noch gilt, und ob die Zahlen zu den
/// sichtbaren Zeilen passen.
library;

import 'package:axiom_app/screens/tasks_screen.dart';
import 'package:axiom_app/state/providers.dart';
import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  late TestHarness h;
  setUp(() {
    // 12:15 liegt in keinem Regelfenster — sonst mischt sich eine
    // zeitgetriggerte Regel in den Bestand, um den es hier geht.
    h = TestHarness.create(at: DateTime(2026, 8, 3, 12, 15));
    h.completeOnboarding();
  });
  tearDown(() => h.dispose());

  Future<Task> task(String title, {int ae = 2}) => h.runtime.createTask(
        title: title,
        activationEnergy: ae,
        salience: 5,
        stakes: 5,
      );

  /// Die Marke des Abschnitts. Sie trägt die Zahl und ist der Schalter.
  Finder doneLabel(int count) => find.text('Erledigt · $count');

  group('Vorgabe: aus', () {
    testWidgets('eine erledigte Aufgabe steht nicht mehr im Bestand',
        (tester) async {
      final erledigt = await task('Rechnung Werkstatt bezahlen');
      await task('Steuerunterlagen sortieren');
      await h.runtime.completeTask(erledigt);

      await pumpPhone(tester, h.wrap(const TasksScreen()));

      expect(find.text('Rechnung Werkstatt bezahlen'), findsNothing);
      // Das Offene steht selbstverständlich weiter da.
      expect(find.text('Steuerunterlagen sortieren'), findsOneWidget);
    });

    testWidgets('aber die Zahl steht da — der Bestand lügt nicht',
        (tester) async {
      // Ein Abschnitt, der spurlos verschwindet, schiebt „habe ich das
      // schon abgehakt?" zurück in den Kopf. Genau das soll AXIOM
      // abnehmen [D9].
      for (final titel in ['Erste', 'Zweite', 'Dritte']) {
        await h.runtime.completeTask(await task(titel));
      }

      await pumpPhone(tester, h.wrap(const TasksScreen()));

      expect(doneLabel(3), findsOneWidget);
      expect(find.text('Erste'), findsNothing);
    });

    testWidgets('ohne Erledigtes steht die Marke gar nicht da',
        (tester) async {
      await task('Steuerunterlagen sortieren');
      await pumpPhone(tester, h.wrap(const TasksScreen()));

      expect(find.textContaining('Erledigt · '), findsNothing);
    });
  });

  group('Der eine Schalter', () {
    testWidgets('die Marke klappt die Zeilen auf', (tester) async {
      final erledigt = await task('Rechnung Werkstatt bezahlen');
      await h.runtime.completeTask(erledigt);

      await pumpPhone(tester, h.wrap(const TasksScreen()));
      expect(find.text('Rechnung Werkstatt bezahlen'), findsNothing);

      await tester.tap(doneLabel(1));
      await tester.pumpAndSettle();

      expect(find.text('Rechnung Werkstatt bezahlen'), findsOneWidget);
      // Und wieder zu.
      await tester.tap(doneLabel(1));
      await tester.pumpAndSettle();
      expect(find.text('Rechnung Werkstatt bezahlen'), findsNothing);
    });

    testWidgets('er überlebt das Schließen der App', (tester) async {
      // Eine Einstellung, die man bei jedem Öffnen neu setzt, ist keine.
      final erledigt = await task('Rechnung Werkstatt bezahlen');
      await h.runtime.completeTask(erledigt);

      await pumpPhone(tester, h.wrap(const TasksScreen()));
      await tester.tap(doneLabel(1));
      await tester.pumpAndSettle();
      expect(find.text('Rechnung Werkstatt bezahlen'), findsOneWidget);

      // Neuer Baum, neuer ProviderScope — dieselbe Datenbank. Das ist der
      // Unterschied zwischen einer gemerkten und einer vergessenen Wahl.
      await unmount(tester);
      await pumpPhone(tester, h.wrap(const TasksScreen()));

      expect(find.text('Rechnung Werkstatt bezahlen'), findsOneWidget);
      expect(h.store.setting(kShowDoneTasksSetting), 'true');
    });

    testWidgets('es bleibt bei einem — keine Filterleiste daneben',
        (tester) async {
      // Zeitraum, Sortierung und Zustandsfilter wären Meta-Work mit
      // Aussicht [D3]. Der Schalter ist die Marke selbst; ein zweites
      // Bedienelement gibt es auf diesem Schirm nicht.
      await h.runtime.completeTask(await task('Erledigte Sache'));
      await task('Offene Sache');

      await pumpPhone(tester, h.wrap(const TasksScreen()));

      expect(find.byType(Switch), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.byType(TabBar), findsNothing);
    });
  });

  group('Die Zahl passt zu den Zeilen', () {
    testWidgets('aufgeklappt steht genau so viel da, wie die Marke nennt',
        (tester) async {
      // Vorher: Marke „Erledigt · 24", darunter `done.take(20)`. Eine Zahl,
      // zu der die sichtbaren Zeilen nicht passen, beschädigt das Vertrauen
      // in jede andere Zahl dieses Schirms.
      for (var i = 1; i <= 24; i++) {
        await h.runtime.completeTask(await task('Vorgang $i'));
      }

      await pumpPhone(tester, h.wrap(const TasksScreen()));
      expect(doneLabel(24), findsOneWidget);

      await tester.tap(doneLabel(24));
      await tester.pumpAndSettle();

      // Der vierundzwanzigste ist der, der vorher unter den Tisch fiel.
      await tester.scrollUntilVisible(
        find.text('Vorgang 24'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Vorgang 24'), findsOneWidget);
    });
  });

  group('Teilschritte', () {
    testWidgets('„Schritte offen" zählt nur das, was auch als Zeile dasteht',
        (tester) async {
      // Die Plakette heißt „Schritte offen: N", nicht „N von M erledigt".
      // Deshalb verbiegt der Schalter sie nicht: Sie nennt genau die
      // Schritte, die im Bestand stehen.
      final parent = await h.runtime.createTask(
        title: 'Steuerunterlagen sortieren',
        activationEnergy: 9,
        salience: 5,
        stakes: 5,
      );
      await h.runtime.atomize(
        parent: parent,
        steps: [
          (title: 'Ordner holen', energy: 1),
          (title: 'Belege stapeln', energy: 1),
          (title: 'Abheften', energy: 1),
        ],
      );
      final steps = await h.store.tasks();
      await h.runtime.completeTask(
          steps.firstWhere((t) => t.title == 'Ordner holen'));

      await pumpPhone(tester, h.wrap(const TasksScreen()));

      expect(find.text('Schritte offen: 2'), findsOneWidget);
      expect(find.text('Belege stapeln'), findsOneWidget);
      expect(find.text('Abheften'), findsOneWidget);
      // Der abgehakte Schritt liegt bei allem anderen Erledigten …
      expect(find.text('Ordner holen'), findsNothing);
      expect(doneLabel(1), findsOneWidget);
    });

    testWidgets('ein abgehakter Teilschritt bleibt über den Schalter findbar',
        (tester) async {
      // Ohne ihn wäre er faktisch gelöscht — und danach traut man dem
      // Bestand nicht mehr [D9].
      final parent = await h.runtime.createTask(
        title: 'Steuerunterlagen sortieren',
        activationEnergy: 9,
        salience: 5,
        stakes: 5,
      );
      await h.runtime.atomize(
        parent: parent,
        steps: [
          (title: 'Ordner holen', energy: 1),
          (title: 'Abheften', energy: 1),
        ],
      );
      final steps = await h.store.tasks();
      await h.runtime.completeTask(
          steps.firstWhere((t) => t.title == 'Ordner holen'));

      await pumpPhone(tester, h.wrap(const TasksScreen()));
      await tester.tap(doneLabel(1));
      await tester.pumpAndSettle();

      expect(find.text('Ordner holen'), findsOneWidget);
    });
  });
}
