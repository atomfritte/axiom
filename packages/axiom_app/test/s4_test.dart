/// Verhaltenstests für Stufe 4: Vorfälle, Wirkfenster, Datentresor.
library;

import 'package:axiom_app/screens/signal_screen.dart';
import 'package:axiom_app/screens/vault_screen.dart';
import 'package:axiom_core/axiom_core.dart';
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

  // ── M10 Vorfälle ──────────────────────────────────────────────────────

  group('Vorfälle (M10, D10)', () {
    testWidgets('leerer Zustand erklärt, was gemeint ist', (tester) async {
      await pumpPhone(tester, h.wrap(const SignalScreen()));
      expect(find.text('Noch keine Vorfälle.'), findsOneWidget);
      expect(find.textContaining('unverhältnismäßig hart'), findsOneWidget);
    });

    testWidgets('Erfassen fragt nach Auslöser und Stärke — mehr nicht',
        (tester) async {
      await pumpPhone(tester, h.wrap(const SignalScreen()));
      await tester.tap(find.text('Vorfall'));
      await tester.pumpAndSettle();

      expect(find.text('Woran hing es?'), findsOneWidget);
      expect(find.text('Wie hart?'), findsOneWidget);
      // Im Spike wird nicht nach Reflexion gefragt.
      expect(find.textContaining('Auslöser'), findsNothing);
      expect(find.textContaining('anders'), findsNothing);
    });

    testWidgets('speichert den Vorfall als Ereignis', (tester) async {
      await h.runtime.logIncident(
        intensity: 4,
        triggerClass: TriggerClass.rejection,
      );
      final events = await h.store.query(types: {EventType.signalIncident});
      expect(events, hasLength(1));
      expect(events.single.payload['trigger_class'], 'rejection');
      expect(events.single.payload['intensity'], 4);
    });

    testWidgets('frischer Vorfall wird nicht sofort zur Analyse gedrängt',
        (tester) async {
      await h.runtime.logIncident(
        intensity: 5,
        triggerClass: TriggerClass.criticism,
      );
      await pumpPhone(tester, h.wrap(const SignalScreen()));
      expect(find.text('Nachbetrachtung'), findsNothing);
    });

    testWidgets('nach zwölf Stunden wird sie angeboten', (tester) async {
      await h.runtime.logIncident(
        intensity: 5,
        triggerClass: TriggerClass.criticism,
      );
      h.clock.advance(const Duration(hours: 14));
      await pumpPhone(tester, h.wrap(const SignalScreen()));

      expect(find.text('Nachbetrachtung'), findsOneWidget);
      expect(find.textContaining('genug Abstand'), findsOneWidget);
    });

    testWidgets('die Zeitangabe ist nie negativ', (tester) async {
      // Die Oberflaeche muss ueber den Clock-Port rechnen, nicht ueber
      // DateTime.now() — sonst steht dort "vor -54 Stunden".
      await h.runtime.logIncident(
        intensity: 4,
        triggerClass: TriggerClass.rejection,
      );
      h.clock.advance(const Duration(hours: 30));
      await pumpPhone(tester, h.wrap(const SignalScreen()));

      expect(find.textContaining('vor -'), findsNothing);
      expect(find.textContaining('vor 30 Stunden'), findsOneWidget);
    });

    testWidgets('die Nachbetrachtung fragt nach Ursache und Rückblick',
        (tester) async {
      await h.runtime.logIncident(
        intensity: 5,
        triggerClass: TriggerClass.ownError,
      );
      h.clock.advance(const Duration(hours: 14));
      await pumpPhone(tester, h.wrap(const SignalScreen()));

      await tester.tap(find.text('Kurz durchgehen'));
      await tester.pumpAndSettle();

      expect(find.text('Wie fällt es heute aus?'), findsOneWidget);
      expect(find.text('Was war der eigentliche Auslöser?'), findsOneWidget);
      expect(find.textContaining('Damals: 5/5'), findsOneWidget);
    });

    testWidgets('erledigte Nachbetrachtung verschwindet', (tester) async {
      await h.runtime.logIncident(
        intensity: 4,
        triggerClass: TriggerClass.overload,
      );
      h.clock.advance(const Duration(hours: 14));
      final pending = await h.runtime.awaitingPostMortem();
      await h.runtime.savePostMortem(
        incidentId: pending.single.id,
        rootCause: 'Zu viel gleichzeitig zugesagt',
        intensityInHindsight: 2,
      );

      await pumpPhone(tester, h.wrap(const SignalScreen()));
      expect(find.text('Nachbetrachtung'), findsNothing);
    });

    testWidgets('zeigt Häufungen nach Auslöserklasse', (tester) async {
      for (var i = 0; i < 3; i++) {
        await h.runtime.logIncident(
          intensity: 3,
          triggerClass: TriggerClass.rejection,
        );
        h.clock.advance(const Duration(hours: 30));
      }
      await pumpPhone(tester, h.wrap(const SignalScreen()));
      expect(find.textContaining('Häufungen'), findsOneWidget);
      expect(find.text('Zurückweisung'), findsWidgets);
    });

    testWidgets('grenzt sich von Deutung und Behandlung ab', (tester) async {
      await pumpPhone(tester, h.wrap(const SignalScreen()));
      await tester.dragUntilVisible(
        find.textContaining('deutet nichts'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      expect(find.textContaining('Fachperson'), findsOneWidget);
    });
  });

  // ── M13 Wirkfenster ───────────────────────────────────────────────────

  group('Wirkfenster (M13)', () {
    testWidgets('ist standardmäßig aus', (tester) async {
      await pumpPhone(tester, h.wrap(const VaultScreen()));
      await tester.dragUntilVisible(
        find.text('Wirkfenster protokollieren'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      final toggle = tester.widget<Switch>(find.byType(Switch));
      expect(toggle.value, isFalse);
    });

    testWidgets('der Abgrenzungstext steht immer dabei', (tester) async {
      await pumpPhone(tester, h.wrap(const VaultScreen()));
      await tester.dragUntilVisible(
        find.textContaining('protokolliert nur'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      expect(find.textContaining('keine Dosis'), findsWidgets);
    });

    testWidgets('eingeschaltet lässt sich eine Einnahme eintragen',
        (tester) async {
      h.runtime.medEnabled = true;
      await h.runtime.logMedEntry(label: 'Morgens', dose: '1 Tablette');

      final entries = await h.runtime.medEntries();
      expect(entries.single.label, 'Morgens');

      final state = await h.runtime.medState();
      expect(state.enabled, isTrue);
    });

    testWidgets('ausgeschaltet gibt es keine Einträge', (tester) async {
      h.runtime.medEnabled = true;
      await h.runtime.logMedEntry(label: 'Morgens');
      h.runtime.medEnabled = false;

      final state = await h.runtime.medState();
      expect(state.enabled, isFalse);
      expect(state.hasActiveWindow, isFalse);
    });
  });

  // ── Datentresor ───────────────────────────────────────────────────────

  group('Datentresor', () {
    testWidgets('Export verlangt ein ausreichend langes Kennwort',
        (tester) async {
      await pumpPhone(tester, h.wrap(const VaultScreen()));

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Exportieren'),
      );
      expect(button.onPressed, isNull);

      await tester.enterText(find.byType(TextField).first, 'kurz');
      await tester.pumpAndSettle();
      final still = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Exportieren'),
      );
      expect(still.onPressed, isNull);
    });

    testWidgets('erklärt, dass das Kennwort nirgends steht', (tester) async {
      await pumpPhone(tester, h.wrap(const VaultScreen()));
      expect(find.textContaining('steht nirgends'), findsOneWidget);
    });

    testWidgets('Import bietet einen Probelauf an', (tester) async {
      await pumpPhone(tester, h.wrap(const VaultScreen()));
      expect(find.text('Probelauf'), findsOneWidget);
      expect(find.textContaining('wiederholbar'), findsOneWidget);
    });
  });

  // ── Sprache ───────────────────────────────────────────────────────────

  group('Sprache bleibt urteilsfrei', () {
    testWidgets('kein Vorwurf im Vorfall-Modul', (tester) async {
      await h.runtime.logIncident(
        intensity: 5,
        triggerClass: TriggerClass.criticism,
      );
      h.clock.advance(const Duration(hours: 14));
      await pumpPhone(tester, h.wrap(const SignalScreen()));

      for (final word in ['überreagiert', 'zu empfindlich', 'unnötig', 'versagt']) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
    });
  });
}
