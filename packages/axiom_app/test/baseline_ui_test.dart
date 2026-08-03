/// Sichtbarkeit der Baseline — beantwortet die Frage „wo sehe ich das?".
library;

import 'package:axiom_app/screens/now_screen.dart';
import 'package:axiom_app/screens/system_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  late TestHarness h;
  setUp(() => h = TestHarness.create(at: DateTime(2026, 8, 3, 12, 15)));
  tearDown(() => h.dispose());

  /// Erzeugt [count] Check-ins und [nights] Schlafeintraege ueber die Zeit.
  Future<void> collect({required int count, required int nights}) async {
    for (var i = 0; i < count; i++) {
      await h.runtime.checkIn(energy: 3, focus: 3, mood: 3, stimNeed: 3);
      h.clock.advance(const Duration(hours: 5));
    }
    for (var i = 0; i < nights; i++) {
      await h.runtime.logSleep(
        bedAt: h.clock.nowLocal().subtract(const Duration(hours: 8)),
        wakeAt: h.clock.nowLocal(),
        quality: 3,
      );
      h.clock.advance(const Duration(hours: 24));
    }
  }

  group('Der Stand ist ablesbar', () {
    testWidgets('der Systemscreen zeigt alle drei Bedingungen',
        (tester) async {
      h.completeOnboarding();
      await pumpPhone(tester, h.wrap(const SystemScreen()));

      expect(find.text('EICHUNG'), findsOneWidget);
      expect(find.text('BASELINE LÄUFT'), findsOneWidget);
      expect(find.text('TAGE'), findsOneWidget);
      expect(find.text('MESSPUNKTE'), findsOneWidget);
      expect(find.text('NÄCHTE'), findsOneWidget);
    });

    testWidgets('jede Bedingung nennt Stand und Ziel', (tester) async {
      h.completeOnboarding();
      await collect(count: 5, nights: 2);
      await pumpPhone(tester, h.wrap(const SystemScreen()));

      expect(find.text('5 / 20'), findsOneWidget);
      expect(find.text('2 / 7'), findsOneWidget);
    });

    testWidgets('die Zusammenfassung benennt, was konkret fehlt',
        (tester) async {
      h.completeOnboarding();
      await collect(count: 3, nights: 1);
      await pumpPhone(tester, h.wrap(const SystemScreen()));

      expect(find.textContaining('Es fehlt noch'), findsOneWidget);
      expect(find.textContaining('Check-ins'), findsWidgets);
    });
  });

  group('Zeit allein reicht nicht', () {
    testWidgets('nach 20 Tagen ohne Daten bleibt es beim Sammeln',
        (tester) async {
      h.completeOnboarding();
      h.clock.advance(const Duration(days: 20));
      await pumpPhone(tester, h.wrap(const SystemScreen()));

      expect(find.text('BASELINE LÄUFT'), findsOneWidget);
      expect(find.text('BASELINE VOLLSTÄNDIG'), findsNothing);
    });

    testWidgets('der Hinweis verschwindet nicht nach Tag 14', (tester) async {
      h.completeOnboarding();
      h.clock.advance(const Duration(days: 20));
      await pumpPhone(tester, h.wrap(const NowScreen()));

      // Frueher verschwand das Badge genau dann, wenn es relevant wurde.
      expect(find.textContaining('BASELINE TAG'), findsOneWidget);
    });
  });

  group('Wenn es soweit ist', () {
    Future<void> completeBaseline() async {
      h.completeOnboarding();
      await collect(count: 22, nights: 8);
      // Die Sammelschleife deckt knapp 13 Tage ab — die Zeit-Bedingung
      // verlangt 14. Alle drei muessen erfuellt sein, nicht zwei von drei.
      h.clock.advance(const Duration(days: 2));
    }

    testWidgets('meldet Bereitschaft in der Hauptansicht', (tester) async {
      await completeBaseline();
      await pumpPhone(tester, h.wrap(const NowScreen()));

      expect(find.text('Baseline vollständig'), findsOneWidget);
      expect(find.textContaining('geeicht werden'), findsOneWidget);
    });

    testWidgets('der Systemscreen nennt die konkreten Schritte',
        (tester) async {
      await completeBaseline();
      await pumpPhone(tester, h.wrap(const SystemScreen()));

      expect(find.text('BASELINE VOLLSTÄNDIG'), findsOneWidget);
      expect(find.text('WAS ZU TUN IST'), findsOneWidget);
      expect(find.textContaining('calibrate.dart'), findsOneWidget);
      expect(find.textContaining('weights.yaml'), findsOneWidget);
      expect(find.textContaining('sync_rules.dart'), findsOneWidget);
    });

    testWidgets('das Laufband verschwindet, sobald es bereit ist',
        (tester) async {
      await completeBaseline();
      await pumpPhone(tester, h.wrap(const NowScreen()));
      expect(find.textContaining('BASELINE TAG'), findsNothing);
    });
  });
}
