/// G4 — misst der Deckel, was er zu messen vorgibt?
///
/// `app_test.dart` prüft, dass in jedem Meta-Bildschirm das Wort `MetaTimed`
/// im Quelltext steht. Das ist eine Signatur, kein Verhalten: Die Buchung
/// hing an `dispose()`, und die drei Reiter der Hauptansicht hingen in einem
/// `IndexedStack`, der alle Kinder dauerhaft montiert hält. Daraus folgte
/// beides zugleich — ein Besuch im Systemschirm wurde nie gebucht (kein
/// `dispose()`), und eine Sitzung, in der man nur erfasst hat, wurde beim
/// Abbau doppelt gebucht (einmal für „Zustand", einmal für „System"). Sechs
/// Minuten Erfassen rissen so den Zwölf-Minuten-Deckel.
///
/// Diese Datei prüft die Wirkung statt der Schreibweise: Gebucht wird, was
/// man ansieht — und nur das.
library;

import 'package:axiom_app/app.dart';
import 'package:axiom_app/screens/now_screen.dart';
import 'package:axiom_app/screens/state_screen.dart';
import 'package:axiom_app/screens/system_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  late TestHarness h;

  setUp(() {
    h = TestHarness.create(at: DateTime(2026, 8, 4, 9, 0));
    h.completeOnboarding();
  });
  tearDown(() => h.dispose());

  Finder tab(IconData icon) => find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(icon),
      );

  Future<void> switchTo(WidgetTester tester, IconData icon) async {
    await tester.tap(tab(icon));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
  }

  Future<Duration> booked() => h.store.usageToday(h.clock.nowLocal());

  testWidgets('eine Sitzung nur auf „Jetzt" bucht keine Meta-Zeit',
      (tester) async {
    await pumpPhone(tester, h.wrap(const HomeShell()));
    expect(find.byType(NowScreen), findsOneWidget);

    // `skipOffstage: false` findet auch, was montiert, aber unsichtbar ist.
    // Genau daran ist die Buchung vorher gescheitert: Beide Nebenreiter
    // liefen von Sekunde eins mit.
    expect(find.byType(StateScreen, skipOffstage: false), findsNothing);
    expect(find.byType(SystemScreen, skipOffstage: false), findsNothing);

    h.clock.advance(const Duration(minutes: 40));
    await unmount(tester);

    expect(await booked(), Duration.zero,
        reason: 'Erfassung zählt nie, „Jetzt" auch nicht');
  });

  testWidgets('„Zustand" bucht genau die Verweildauer', (tester) async {
    await pumpPhone(tester, h.wrap(const HomeShell()));

    await switchTo(tester, Icons.show_chart_outlined);
    expect(find.byType(StateScreen), findsOneWidget);
    h.clock.advance(const Duration(minutes: 5));

    await switchTo(tester, Icons.adjust_outlined);
    expect(await booked(), const Duration(minutes: 5));

    // Und der zweite Besuch kommt dazu, statt von vorn zu zählen.
    await switchTo(tester, Icons.show_chart_outlined);
    h.clock.advance(const Duration(minutes: 3));
    await switchTo(tester, Icons.adjust_outlined);
    expect(await booked(), const Duration(minutes: 8));
  });

  testWidgets('kurz danebengetippt zählt nicht', (tester) async {
    // Ein Reiter, den man antippt und sofort wieder verlässt, ist keine
    // Nutzungszeit — sonst addiert sich jedes Durchtippen zu Minuten, die
    // niemand verbracht hat.
    await pumpPhone(tester, h.wrap(const HomeShell()));
    await switchTo(tester, Icons.show_chart_outlined);
    h.clock.advance(const Duration(seconds: 2));
    await switchTo(tester, Icons.adjust_outlined);

    expect(await booked(), Duration.zero);
  });

  testWidgets('der Wechsel in den Hintergrund bucht sofort', (tester) async {
    // Beendet Android den Prozess, läuft kein `dispose()` mehr. Ohne diese
    // Buchung war eine halbe Stunde im Zustandsschirm danach spurlos weg
    // und der Deckel griff nie.
    await pumpPhone(tester, h.wrap(const HomeShell()));
    await switchTo(tester, Icons.show_chart_outlined);
    h.clock.advance(const Duration(minutes: 7));

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }

    expect(await booked(), const Duration(minutes: 7));

    // Im Hintergrund läuft die Uhr nicht weiter — sonst bucht eine Nacht
    // auf dem Nachttisch das ganze Budget.
    h.clock.advance(const Duration(hours: 2));
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    expect(await booked(), const Duration(minutes: 7));

    // Nach der Rückkehr zählt sie wieder.
    h.clock.advance(const Duration(minutes: 4));
    await switchTo(tester, Icons.adjust_outlined);
    expect(await booked(), const Duration(minutes: 11));
  });
}
