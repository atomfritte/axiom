/// Erfassungskanäle — beantwortet „wie komme ich schnell rein?".
library;

import 'package:axiom_app/screens/channels_screen.dart';
import 'package:axiom_app/screens/system_screen.dart';
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

  group('Alle Wege stehen an einer Stelle', () {
    testWidgets('erklärt zuerst, warum es mehrere gibt', (tester) async {
      await pumpPhone(tester, h.wrap(const ChannelsScreen()));
      expect(find.textContaining('wenige Sekunden'), findsOneWidget);
    });

    testWidgets('listet die eingerichteten Kanäle', (tester) async {
      await pumpPhone(tester, h.wrap(const ChannelsScreen()));

      for (final label in [
        'Knopf in der App',
        'Schnelleinstellung',
        'Homescreen-Widget',
        'Aus anderen Apps teilen',
      ]) {
        await tester.dragUntilVisible(
          find.text(label),
          find.byType(ListView),
          const Offset(0, -180),
        );
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('das Widget laesst sich von hier aus platzieren',
        (tester) async {
      // Eine Anleitung durch fremde Systemmenues wird nicht befolgt — und
      // im Fall des Widgets fuehrte sie ins Leere, weil Samsungs
      // Startbildschirm seine Widget-Liste zwischenspeichert. Der Knopf
      // fragt das System direkt.
      await pumpPhone(tester, h.wrap(const ChannelsScreen()));
      await tester.dragUntilVisible(
        find.text('Widget hinzufügen'),
        find.byType(ListView),
        const Offset(0, -180),
      );
      expect(find.text('Widget hinzufügen'), findsOneWidget);
    });

    testWidgets('der Stift wird über Air Command angeboten, nicht über '
        'Air Actions', (tester) async {
      // Der S Pen des S25 Ultra hat kein Bluetooth. Eine Anleitung zu
      // Air Actions schickt in eine Einstellung, die es auf dem Gerät nicht
      // gibt — schlimmer als keine Anleitung, weil man sie sucht.
      await pumpPhone(tester, h.wrap(const ChannelsScreen()));
      await tester.dragUntilVisible(
        find.text('Notiz-Rolle anfragen'),
        find.byType(ListView),
        const Offset(0, -180),
      );
      expect(find.textContaining('Air Command'), findsWidgets);
      // Der Grund muss dabeistehen: Ohne ihn wirkt es wie ein Fehler.
      expect(find.textContaining('Rolle'), findsWidgets);
    });

    testWidgets('S-Pen und Sprache sind mit Anleitung dabei', (tester) async {
      await pumpPhone(tester, h.wrap(const ChannelsScreen()));
      await tester.dragUntilVisible(
        find.text('S-Pen'),
        find.byType(ListView),
        const Offset(0, -250),
      );
      expect(find.text('S-Pen'), findsOneWidget);
      expect(find.textContaining('Air Command'), findsWidgets);

      await tester.dragUntilVisible(
        find.text('Sprache'),
        find.byType(ListView),
        const Offset(0, -250),
      );
      expect(find.textContaining('Hey Google'), findsOneWidget);
    });

    testWidgets('nennt die Broadcast-Namen für Samsung-Routinen',
        (tester) async {
      await pumpPhone(tester, h.wrap(const ChannelsScreen()));
      await tester.dragUntilVisible(
        find.textContaining('de.atomfritte.axiom.FOCUS_START'),
        find.byType(ListView),
        const Offset(0, -250),
      );
      expect(find.textContaining('de.atomfritte.axiom.WINDDOWN'), findsOneWidget);
    });
  });

  group('Dauerhafte Anzeige', () {
    testWidgets('erklärt den eigentlichen Nutzen', (tester) async {
      await pumpPhone(tester, h.wrap(const ChannelsScreen()));
      expect(find.textContaining('Sperrbildschirm'), findsOneWidget);
      expect(find.textContaining('ohne zu entsperren'), findsOneWidget);
    });

    testWidgets('ist standardmäßig aus', (tester) async {
      await pumpPhone(tester, h.wrap(const ChannelsScreen()));
      final toggle = tester.widget<Switch>(find.byType(Switch));
      expect(toggle.value, isFalse);
    });
  });

  group('Erreichbarkeit', () {
    testWidgets('der Systemscreen führt hin', (tester) async {
      await pumpPhone(tester, h.wrap(const SystemScreen()));
      await tester.dragUntilVisible(
        find.text('Erfassungswege'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      expect(find.text('Erfassungswege'), findsOneWidget);
      expect(find.textContaining('Widget, Benachrichtigung, Stift'),
          findsOneWidget);
    });
  });

  group('Sprache', () {
    testWidgets('kein Versprechen, das die Plattform nicht hält',
        (tester) async {
      await pumpPhone(tester, h.wrap(const ChannelsScreen()));
      // Lockscreen-Widgets gibt es auf Android nicht — das darf hier auch
      // nicht behauptet werden.
      expect(find.textContaining('Sperrbildschirm-Widget'), findsNothing);
      expect(find.textContaining('Lockscreen-Widget'), findsNothing);
    });
  });
}
