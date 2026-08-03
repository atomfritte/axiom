/// Verhaltenstests für Stufe 2: Anker, Zerlegen, Review, Körper.
library;

import 'package:axiom_app/design/widgets/anchor_chain.dart';
import 'package:axiom_app/screens/anchors_screen.dart';
import 'package:axiom_app/screens/atomize_sheet.dart';
import 'package:axiom_app/screens/body_sheet.dart';
import 'package:axiom_app/screens/now_screen.dart';
import 'package:axiom_app/screens/review_screen.dart';
import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  late TestHarness h;
  setUp(() {
    // 12:00: liegt bewusst in keinem Regelfenster. Sonst gewinnt eine
    // zeitgetriggerte Regel gegen den Vorschlag, den der Test pruefen will —
    // korrektes Verhalten, aber hier nicht der Pruefgegenstand.
    h = TestHarness.create(at: DateTime(2026, 8, 3, 12, 15));
    h.completeOnboarding();
  });
  tearDown(() => h.dispose());

  // ── M3 Zeitanker ──────────────────────────────────────────────────────

  group('Zeitanker (M3, D4)', () {
    testWidgets('leerer Zustand erklärt, wofür Anker gut sind',
        (tester) async {
      await pumpPhone(tester, h.wrap(const AnchorsScreen()));
      expect(find.text('Nichts terminiert.'), findsOneWidget);
      expect(find.textContaining('rechnet rückwärts'), findsOneWidget);
    });

    testWidgets('zeigt die volle Kette, nicht nur den Termin', (tester) async {
      await h.runtime.createAnchor(
        title: 'Zahnarzt',
        arriveBy: h.clock.nowLocal().add(const Duration(hours: 4)),
        travel: const Duration(minutes: 25),
        location: 'Praxis',
      );
      await pumpPhone(tester, h.wrap(const AnchorsScreen()));

      expect(find.text('Zahnarzt'), findsWidgets);
      expect(find.text('Laufendes abschließen'), findsOneWidget);
      expect(find.text('Fertigmachen'), findsOneWidget);
      expect(find.textContaining('Los nach Praxis'), findsOneWidget);
    });

    testWidgets('macht die Vorlaufzeit als eigene Zahl sichtbar',
        (tester) async {
      await h.runtime.createAnchor(
        title: 'Werkstatt',
        arriveBy: h.clock.nowLocal().add(const Duration(hours: 5)),
        travel: const Duration(minutes: 20),
      );
      await pumpPhone(tester, h.wrap(const AnchorsScreen()));
      // 20 Fahrt + 10 Puffer + 15 fertigmachen + 10 aussteigen = 55
      expect(find.text('VORLAUF 55 MIN'), findsOneWidget);
    });

    testWidgets('die Hauptansicht führt den nächsten Schritt oben',
        (tester) async {
      await h.runtime.createAnchor(
        title: 'Termin',
        arriveBy: h.clock.nowLocal().add(const Duration(minutes: 90)),
        travel: const Duration(minutes: 20),
      );
      await pumpPhone(tester, h.wrap(const NowScreen()));
      expect(find.byType(NextStepBadge), findsOneWidget);
    });

    testWidgets('vergangene Anker verschwinden aus der Ansicht',
        (tester) async {
      await h.runtime.createAnchor(
        title: 'Vorbei',
        arriveBy: h.clock.nowLocal().subtract(const Duration(hours: 5)),
      );
      await pumpPhone(tester, h.wrap(const AnchorsScreen()));
      expect(find.text('Vorbei'), findsNothing);
    });
  });

  // ── M2 Zerlegen ───────────────────────────────────────────────────────

  group('Zerlegen (M2, D2)', () {
    Future<Task> heavyTask() => h.runtime.createTask(
          title: 'Steuerunterlagen sortieren',
          activationEnergy: 9,
          salience: 2,
          stakes: 9,
          decayAt: h.clock.nowLocal().add(const Duration(hours: 30)),
        );

    testWidgets('bietet Zerlegen an, statt anzumahnen', (tester) async {
      await heavyTask();
      await pumpPhone(tester, h.wrap(const NowScreen()));

      expect(find.text('ZU GROSS FÜR HEUTE'), findsOneWidget);
      expect(find.text('In einen ersten Schritt zerlegen'), findsOneWidget);
      // Kein Vorwurf, keine Fälligkeitsmahnung.
      expect(find.textContaining('überfällig'), findsNothing);
    });

    testWidgets('fragt nach der ersten Handlung, nicht nach einem Plan',
        (tester) async {
      final task = await heavyTask();
      final candidate = AtomizeCandidate(
        task: task,
        reason: AtomizeReason.urgentButUnreachable,
        targetEnergy: 2,
      );
      await pumpPhone(tester, h.wrap(const Scaffold()));
      final context = tester.element(find.byType(Scaffold));
      showAtomizeSheet(context, candidate).ignore();
      await tester.pumpAndSettle();

      expect(find.text('Was ist die allererste Handlung?'), findsOneWidget);
      expect(find.textContaining('zwei Minuten'), findsOneWidget);
      // Der Formenkatalog steht bereit, schlägt aber nichts Konkretes vor.
      expect(find.text('Etwas holen'), findsOneWidget);
      expect(find.text('Zwei Minuten dranbleiben'), findsOneWidget);
    });

    testWidgets('meldet, wenn der erste Schritt noch zu groß ist',
        (tester) async {
      final task = await heavyTask();
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

      // Eine hohe Stufe antippen — deutlich ueber dem Ziel von 2.
      //
      // Erst sichtbar machen: Das Blatt scrollt, und ein Tipp ins Leere
      // wuerde sonst stumm bleiben. Genau das hat die frueherere Fassung
      // mit `warnIfMissed: false` getan — der Test war damit blind fuer
      // seinen eigenen Fehlschlag.
      await tester.ensureVisible(find.byKey(kEnergyScaleKey));
      await tester.pumpAndSettle();
      final scale = find.descendant(
        of: find.byKey(kEnergyScaleKey),
        matching: find.byType(GestureDetector),
      );
      await tester.tap(scale.at(7));
      await tester.pumpAndSettle();
      expect(find.textContaining('noch zu groß'), findsOneWidget);
    });

    testWidgets('erzeugt Teilaufgaben und blockiert das Elternteil',
        (tester) async {
      final parent = await heavyTask();
      await h.runtime.atomize(
        parent: parent,
        steps: [(title: 'Ordner auf den Tisch legen', energy: 1)],
      );

      final tasks = await h.store.tasks();
      final child = tasks.firstWhere((t) => t.parentId == parent.id);
      expect(child.title, 'Ordner auf den Tisch legen');
      expect(child.state, TaskState.ready);
      expect(
        tasks.firstWhere((t) => t.id == parent.id).state,
        TaskState.blocked,
      );
    });

    testWidgets('nach dem Zerlegen ist etwas startbar', (tester) async {
      final parent = await heavyTask();
      await h.runtime.atomize(
        parent: parent,
        steps: [(title: 'Ordner holen', energy: 1)],
      );
      await pumpPhone(tester, h.wrap(const NowScreen()));

      expect(find.text('JETZT'), findsOneWidget);
      expect(find.text('Ordner holen'), findsOneWidget);
    });
  });

  // ── M11 Review ────────────────────────────────────────────────────────

  group('Review (M11, D12)', () {
    testWidgets('zeigt alle sechs Kennzahlen mit Herleitung', (tester) async {
      await pumpPhone(tester, h.wrap(const ReviewScreen()));

      for (final label in [
        'MESSPUNKTE ERFASST',
        'KOMPENSATIONSLAST',
        'ERFASST UND EINSORTIERT',
        'REIZBEDARF GEPLANT GEDECKT',
        'IMPULSE ABGEFANGEN',
        'ZEIT IM SYSTEM GEGEN ZEIT GESPART',
      ]) {
        await tester.dragUntilVisible(
          find.text(label),
          find.byType(ListView),
          const Offset(0, -160),
        );
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await unmount(tester);
    });

    testWidgets('der Zeitdeckel läuft sichtbar mit', (tester) async {
      await pumpPhone(tester, h.wrap(const ReviewScreen()));
      expect(find.text('ZEITDECKEL'), findsOneWidget);
      expect(find.text('von 2 min'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('jeder Umfang hat seine eigenen Leitfragen', (tester) async {
      await pumpPhone(
        tester,
        h.wrap(const ReviewScreen(scope: ReviewScope.quarter)),
      );
      expect(find.text('von 60 min'), findsOneWidget);
      await tester.dragUntilVisible(
        find.textContaining('Was kann WEG?'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      expect(find.textContaining('Was kann WEG?'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('Regeln aendern ist erst ab dem Wochen-Review erlaubt',
        (tester) async {
      expect(ReviewScope.day.allowsRuleChanges, isFalse);
      expect(ReviewScope.week.allowsRuleChanges, isTrue);
      await pumpPhone(tester, h.wrap(const ReviewScreen()));
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  });

  // ── M7 Körper ─────────────────────────────────────────────────────────

  group('Körper (M7, D7)', () {
    testWidgets('vier Signale, alle mit einem Tipp quittierbar',
        (tester) async {
      await pumpPhone(tester, h.wrap(const Scaffold(body: BodyStrip())));
      for (final signal in BodySignal.values) {
        expect(find.text(signal.label), findsOneWidget);
      }
    });

    testWidgets('quittieren schreibt ein Ereignis', (tester) async {
      await pumpPhone(tester, h.wrap(const Scaffold(body: BodyStrip())));
      await tester.tap(find.text('Wasser'));
      await tester.pumpAndSettle();

      final events = await h.store.query(types: {EventType.bodyPrompt});
      expect(events, hasLength(1));
      expect(events.single.payload['kind'], 'water');
    });

    testWidgets('zeigt keine Soll-Vorgabe und keinen Zähler', (tester) async {
      await pumpPhone(tester, h.wrap(const Scaffold(body: BodyStrip())));
      // "3 von 8 Gläsern" wäre eine Bewertung, keine Messung (R7).
      expect(find.textContaining(' von '), findsNothing);
      expect(find.textContaining('Ziel'), findsNothing);
    });
  });

  // ── Sprache ───────────────────────────────────────────────────────────

  group('Sprache bleibt urteilsfrei', () {
    testWidgets('Zerlegen begründet, ohne vorzuwerfen', (tester) async {
      await h.runtime.createTask(
        title: 'Schwere Sache',
        activationEnergy: 9,
        salience: 2,
        stakes: 9,
        decayAt: h.clock.nowLocal().add(const Duration(hours: 20)),
      );
      await pumpPhone(tester, h.wrap(const NowScreen()));

      for (final word in ['versagt', 'endlich', 'schon wieder', 'faul']) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
    });
  });
}
