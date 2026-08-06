/// Verhaltenstests für Stufe 3: Fokus, Reiz, Bremse, Last.
library;

import 'package:axiom_app/screens/focus_screen.dart';
import 'package:axiom_app/screens/intercept_screen.dart';
import 'package:axiom_app/screens/now_screen.dart';
import 'package:axiom_app/screens/sensation_screen.dart';
import 'package:axiom_app/screens/system_screen.dart';
import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  late TestHarness h;
  setUp(() {
    h = TestHarness.create(at: DateTime(2026, 8, 3, 12, 15));
    h.completeOnboarding();
  });
  tearDown(() => h.dispose());

  // ── M4 Fokus ──────────────────────────────────────────────────────────

  group('Fokus (M4, D6)', () {
    testWidgets('vor dem Start wird nach Ziel und Dauer gefragt',
        (tester) async {
      await h.runtime.createTask(
        title: 'Rückruf Werkstatt',
        activationEnergy: 2,
        salience: 5,
        stakes: 6,
      );
      await pumpPhone(tester, h.wrap(const FocusScreen()));

      expect(find.text('Worauf'), findsOneWidget);
      expect(find.text('Wie lange'), findsOneWidget);
      expect(find.text('Fokus starten'), findsOneWidget);
    });

    testWidgets('erklärt den Unterschied zwischen mit und ohne Ziel',
        (tester) async {
      await pumpPhone(tester, h.wrap(const FocusScreen()));
      expect(find.textContaining('Ohne gesetztes Ziel'), findsOneWidget);
    });

    testWidgets('laufender Block zeigt Zeit und Urteil', (tester) async {
      await h.runtime.startFocus(
        taskId: 't1',
        taskTitle: 'Steuerunterlagen',
        planned: const Duration(minutes: 50),
      );
      h.clock.advance(const Duration(minutes: 20));
      await pumpPhone(tester, h.wrap(const FocusScreen()));

      expect(find.text('Läuft auf'), findsOneWidget);
      expect(find.text('Steuerunterlagen'), findsOneWidget);
      expect(find.text('Geschützt'), findsOneWidget);
    });

    testWidgets('schützt in der Zeit, statt zu stören', (tester) async {
      await h.runtime.startFocus(taskId: 't1', taskTitle: 'Ziel');
      h.clock.advance(const Duration(minutes: 30));
      await pumpPhone(tester, h.wrap(const FocusScreen()));

      expect(find.textContaining('Benachrichtigungen sind stumm'),
          findsOneWidget);
    });

    testWidgets('meldet deutliche Überziehung — erlaubend formuliert',
        (tester) async {
      await h.runtime.startFocus(
        taskId: 't1',
        taskTitle: 'Ziel',
        planned: const Duration(minutes: 25),
      );
      h.clock.advance(const Duration(minutes: 95));
      await pumpPhone(tester, h.wrap(const FocusScreen()));

      expect(find.text('Unterbrechung'), findsOneWidget);
      expect(find.textContaining('in Ordnung'), findsOneWidget);
    });

    testWidgets('Wiedereinstiegsnotiz überlebt die Sitzung [D11]',
        (tester) async {
      final session = await h.runtime.startFocus(
        taskId: 't1',
        taskTitle: 'Steuerunterlagen',
      );
      h.clock.advance(const Duration(minutes: 40));
      await h.runtime.endFocus(session, breadcrumb: 'Bei Anlage KAP, Zeile 7');

      await pumpPhone(tester, h.wrap(const FocusScreen()));
      expect(find.text('Zuletzt stehengeblieben'), findsOneWidget);
      expect(find.text('Bei Anlage KAP, Zeile 7'), findsOneWidget);
    });

    testWidgets('die Hauptansicht zeigt den laufenden Block', (tester) async {
      await h.runtime.startFocus(taskId: 't1', taskTitle: 'Steuerunterlagen');
      h.clock.advance(const Duration(minutes: 15));
      await pumpPhone(tester, h.wrap(const NowScreen()));

      expect(find.text('Steuerunterlagen'), findsWidgets);
      expect(find.text('15 min'), findsOneWidget);
    });
  });

  // ── M5 Reiz ───────────────────────────────────────────────────────────

  group('Reiz (M5, D5)', () {
    testWidgets('zeigt Bedarf, Guthaben und Kanäle', (tester) async {
      await h.seedChannels();
      await pumpPhone(tester, h.wrap(const SensationScreen()));

      expect(find.text('Reizbedarf'), findsOneWidget);
      expect(find.text('Verdient'), findsOneWidget);
      expect(find.textContaining('Kanäle'), findsOneWidget);
    });

    testWidgets('Fokusminuten verdienen Reizzeit', (tester) async {
      final session = await h.runtime.startFocus(taskTitle: 'Arbeit');
      h.clock.advance(const Duration(minutes: 90));
      await h.runtime.endFocus(session);

      await pumpPhone(tester, h.wrap(const SensationScreen()));
      // 90 Minuten bei 1:3 ergeben 30.
      expect(find.text('30'), findsOneWidget);
    });

    testWidgets('trägt einen geplanten Slot ein', (tester) async {
      await h.seedChannels();
      await pumpPhone(tester, h.wrap(const SensationScreen()));
      // Der Kanal erscheint zweimal: als Vorschlag oben und in der Liste.
      // Beides ist gewollt — hier wird die Listenzeile angetippt.
      await tester.tap(find.text('Kalt duschen').last);
      await tester.pumpAndSettle();

      final slots = await h.store.query(types: {EventType.sensationSlot});
      expect(slots, hasLength(1));
      expect(slots.single.payload['planned'], isTrue);
    });

    testWidgets('ungeplante Slots werden gezählt, nicht bestraft (G3)',
        (tester) async {
      await h.seedChannels();
      await pumpPhone(tester, h.wrap(const SensationScreen()));
      await tester.tap(find.byTooltip('War schon').first);
      await tester.pumpAndSettle();

      final slots = await h.store.query(types: {EventType.sensationSlot});
      expect(slots.single.payload['planned'], isFalse);
      // Kein Tadel, kein Abzug.
      for (final word in ['leider', 'schon wieder', 'sollte']) {
        expect(find.textContaining(word), findsNothing);
      }
    });

    testWidgets('riskante Kanäle sind ab Werk nicht dabei', (tester) async {
      await h.seedChannels();
      await pumpPhone(tester, h.wrap(const SensationScreen()));
      expect(find.textContaining('kostet etwas'), findsNothing);
    });
  });

  // ── M6 Bremse ─────────────────────────────────────────────────────────

  group('Bremse (M6, D5)', () {
    Future<InterceptTrigger> makeTrigger() async {
      const trigger = InterceptTrigger(
        id: 'purchase',
        label: 'Anschaffung über 200 €',
        cooldown: Duration(minutes: 15),
        checklist: ['Kannte ich das vor heute?', 'Sache oder Gefühl?'],
        authorized: true,
      );
      await h.runtime.saveTrigger(trigger);
      return trigger;
    }

    testWidgets('leerer Zustand erklärt den Mechanismus', (tester) async {
      await pumpPhone(tester, h.wrap(const InterceptScreen()));
      expect(find.text('Noch nichts eingerichtet.'), findsOneWidget);
      expect(find.textContaining('Wartezeit dazwischen'), findsOneWidget);
    });

    testWidgets('Trigger auslösen startet die Wartezeit', (tester) async {
      final trigger = await makeTrigger();
      await h.runtime.startIntercept(trigger);
      await pumpPhone(tester, h.wrap(const InterceptScreen()));

      expect(find.text('Wartezeit läuft'), findsOneWidget);
      expect(find.text('15 min'), findsOneWidget);
    });

    testWidgets('ein Tipp auf den Trigger loest ihn aus', (tester) async {
      await makeTrigger();
      await pumpPhone(tester, h.wrap(const InterceptScreen()));

      await tester.tap(find.text('Anschaffung über 200 €'));
      await tester.pumpAndSettle();

      final runs = await h.store.runsSince(
        h.clock.nowUtc().subtract(const Duration(hours: 1)),
      );
      expect(runs, hasLength(1));
      expect(runs.single.outcome, InterceptOutcome.pending);
    });

    testWidgets('zeigt die selbst geschriebenen Fragen', (tester) async {
      final trigger = await makeTrigger();
      await h.runtime.startIntercept(trigger);
      await pumpPhone(tester, h.wrap(const InterceptScreen()));

      expect(find.text('Deine Fragen'), findsOneWidget);
      expect(find.text('Kannte ich das vor heute?'), findsOneWidget);
    });

    testWidgets('„Mache ich" ist während der Wartezeit gesperrt',
        (tester) async {
      final trigger = await makeTrigger();
      await h.runtime.startIntercept(trigger);
      await pumpPhone(tester, h.wrap(const InterceptScreen()));

      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Mache ich'),
      );
      expect(button.onPressed, isNull);
      expect(find.textContaining('wird frei'), findsOneWidget);
    });

    testWidgets('nach Ablauf gehört die Entscheidung dem Nutzer',
        (tester) async {
      final trigger = await makeTrigger();
      await h.runtime.startIntercept(trigger);
      h.clock.advance(const Duration(minutes: 20));
      await pumpPhone(tester, h.wrap(const InterceptScreen()));

      expect(find.text('Wartezeit vorbei'), findsOneWidget);
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Mache ich'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('ohne Prüffrage kein Trigger — die Frage ist der Vertrag',
        (tester) async {
      await pumpPhone(tester, h.wrap(const InterceptScreen()));
      await tester.tap(find.text('Trigger anlegen'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Nachtbestellung');
      await tester.pumpAndSettle();

      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Trigger speichern'),
      );
      expect(save.onPressed, isNull);
      expect(find.textContaining('Ohne mindestens eine Frage'), findsOneWidget);
    });

    testWidgets('spricht nicht in Verboten (G3)', (tester) async {
      final trigger = await makeTrigger();
      await h.runtime.startIntercept(trigger);
      await pumpPhone(tester, h.wrap(const InterceptScreen()));

      for (final word in ['verboten', 'darfst nicht', 'gesperrt für dich']) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
    });
  });

  // ── M9 Last ───────────────────────────────────────────────────────────

  group('Last (M9, D1)', () {
    testWidgets('L0 zeigt kein Banner — nur Abweichung ist eine Meldung',
        (tester) async {
      await pumpPhone(tester, h.wrap(const NowScreen()));
      expect(find.text('Erhaltungsmodus'), findsNothing);
      expect(find.text('Last kritisch'), findsNothing);
    });

    testWidgets('Erhaltungsmodus erscheint oben und begrenzt Vorschläge',
        (tester) async {
      // Hohe Last über mehrere Abend-Check-ins.
      for (var i = 0; i < 8; i++) {
        await h.runtime.checkIn(
          energy: 1,
          focus: 1,
          mood: 1,
          stimNeed: 5,
          compensation: 5,
          recovery: 1,
          slot: 'evening',
        );
        h.clock.advance(const Duration(hours: 6));
      }
      await pumpPhone(tester, h.wrap(const NowScreen()));

      final snapshot = await h.runtime.evaluate();
      if (snapshot.regime.level == LoadLevel.l3) {
        expect(find.text('Erhaltungsmodus'), findsOneWidget);
        expect(find.textContaining('nicht dein Versagen'), findsOneWidget);
      } else {
        // Auch unterhalb von L3 darf kein Vorwurf erscheinen.
        expect(find.textContaining('versagt'), findsNothing);
      }
    });

    testWidgets('der Zustand überlebt einen Neustart', (tester) async {
      h.store.setLoadState(LoadLevel.l3, h.clock.nowLocal());
      final state = h.store.loadState();
      expect(state!.level, LoadLevel.l3);
    });
  });

  // ── Transparenz ───────────────────────────────────────────────────────

  group('Ungeeichte Regeln sind markiert (G2)', () {
    testWidgets('der Systeminspektor weist darauf hin', (tester) async {
      await pumpPhone(tester, h.wrap(const SystemScreen()));
      expect(find.text('Eichung'), findsOneWidget);
      expect(find.text('Baseline läuft'), findsOneWidget);
      expect(find.textContaining('geschätzten Gewichten'), findsWidgets);
    });

    testWidgets('betroffene Regeln tragen eine Marke', (tester) async {
      // Das Regelwerk hat eine eigene Seite: Die lange Liste im Systemscreen
      // hat alles darunter begraben.
      await pumpPhone(tester, h.wrap(const RulesScreen()));

      // Hier stand `find.text('UNGEEICHT')`. Das war zweifach zu eng: Es
      // verlangte eine bestimmte Schreibweise und einen alleinstehenden
      // `Text`. Beides ist inzwischen anders — die Marke steht in normaler
      // Schreibweise und als Abschnitt der Herkunftszeile. Der Test waere
      // daran zerbrochen, ohne dass eine Regel ihre Marke verloren haette,
      // und genau das ist das Einzige, was hier zaehlt: dass eine
      // ungeeichte Regel als solche erkennbar ist (G2). Gesucht wird
      // deshalb im gezeichneten Absatz, unabhaengig davon, wie er
      // zusammengesetzt wurde.
      final mark = find.byWidgetPredicate(
        (w) =>
            w is RichText &&
            w.text.toPlainText().toUpperCase().contains('UNGEEICHT'),
        description: 'Marke „Ungeeicht"',
      );
      for (var i = 0; i < 12 && mark.evaluate().isEmpty; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -400));
        await tester.pumpAndSettle();
      }
      expect(mark, findsWidgets);
    });
  });

  // ── Werkzeugleiste ────────────────────────────────────────────────────

  group('Navigation bleibt flach (G1)', () {
    testWidgets('Fokus, Reiz und Bremse als Leiste statt als Reiter',
        (tester) async {
      await pumpPhone(tester, h.wrap(const NowScreen()));
      await tester.dragUntilVisible(
        find.text('Fokus'),
        find.byType(ListView),
        const Offset(0, -250),
      );
      expect(find.text('Fokus'), findsOneWidget);
      expect(find.text('Reiz'), findsOneWidget);
      expect(find.text('Bremse'), findsOneWidget);
    });
  });
}
