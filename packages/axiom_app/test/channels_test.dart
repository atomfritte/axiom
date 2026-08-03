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

    testWidgets('nennt für jeden Kanal, wo man ihn findet', (tester) async {
      await pumpPhone(tester, h.wrap(const ChannelsScreen()));
      // Ein Kanal, von dem man nicht weiss, ist kein Kanal.
      await tester.dragUntilVisible(
        find.textContaining('Langes Tippen auf den Homescreen'),
        find.byType(ListView),
        const Offset(0, -180),
      );
      expect(find.textContaining('Langes Tippen auf den Homescreen'),
          findsOneWidget);
    });

    testWidgets('S-Pen und Sprache sind mit Anleitung dabei', (tester) async {
      await pumpPhone(tester, h.wrap(const ChannelsScreen()));
      await tester.dragUntilVisible(
        find.text('S-Pen'),
        find.byType(ListView),
        const Offset(0, -250),
      );
      expect(find.text('S-Pen'), findsOneWidget);
      expect(find.textContaining('Air Actions'), findsOneWidget);

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
        find.textContaining('axiom.FOCUS_START'),
        find.byType(ListView),
        const Offset(0, -250),
      );
      expect(find.textContaining('axiom.WINDDOWN'), findsOneWidget);
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
        find.text('Erfassen'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      expect(find.text('Erfassen'), findsOneWidget);
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
