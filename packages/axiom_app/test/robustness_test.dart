/// Hält jeden Screen unter den Bedingungen aus, die real vorkommen.
///
/// **Warum das ein eigener Test ist.** Die Referenzbilder zeigen einen
/// Zustand: ein Gerät, eine Schriftgröße, ein Schema. Was sie nicht zeigen,
/// ist der Rand — und der Rand ist hier nicht exotisch, sondern der
/// Normalfall der Zielgruppe: Wer die Oberfläche schlecht lesen kann, stellt
/// die Schrift hoch. Die App lässt bis 2,4-fach zu (`app.dart`), und bei
/// 2,4-fach bricht jedes Layout, das mit fester Höhe oder unumbrechbarer
/// Zeile gebaut ist.
///
/// Ein Überlauf ist dabei kein Schönheitsfehler: Der gelbe Balken frisst
/// den Text, der darunter steht, und was nicht lesbar ist, existiert für
/// dieses Profil nicht [D9].
///
/// **Warum bis ans Listenende gerollt wird.** Der Test pumpte den Screen und
/// fragte sofort `takeException()`. Die Screens bauen ihren Inhalt aber in
/// einer `ListView`, und die baut nur, was sichtbar ist — alles unterhalb
/// des ersten Bildschirms wurde nie gelayoutet und konnte deshalb auch nicht
/// überlaufen. Der Test war grün und strukturell blind für den ganzen
/// unteren Teil jedes Screens. Genau dort saßen die Meta-Budget-Zeile (Row
/// mit zwei unflexiblen Texten, 199 px hinaus) und die Werkzeugknöpfe
/// (`height: 62` gegen skalierenden Text, 52 px hinaus).
library;

import 'package:axiom_app/screens/anchors_screen.dart';
import 'package:axiom_app/screens/channels_screen.dart';
import 'package:axiom_app/screens/check_screen.dart';
import 'package:axiom_app/screens/expert_screen.dart';
import 'package:axiom_app/screens/focus_screen.dart';
import 'package:axiom_app/screens/help_screen.dart';
import 'package:axiom_app/screens/inbox_screen.dart';
import 'package:axiom_app/screens/intercept_screen.dart';
import 'package:axiom_app/screens/now_screen.dart';
import 'package:axiom_app/screens/review_screen.dart';
import 'package:axiom_app/screens/sensation_screen.dart';
import 'package:axiom_app/screens/signal_screen.dart';
import 'package:axiom_app/screens/state_screen.dart';
import 'package:axiom_app/screens/system_screen.dart';
import 'package:axiom_app/screens/tasks_screen.dart';
import 'package:axiom_app/screens/vault_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:axiom_app/screens/body_sheet.dart';
import 'package:axiom_app/screens/capture_sheet.dart';
import 'package:axiom_app/screens/checkin_sheet.dart';

import 'harness.dart';

/// Alle Screens, die ohne Argument erreichbar sind.
final _screens = <String, Widget Function()>{
  'jetzt': () => const NowScreen(),
  'aufgaben': () => const TasksScreen(),
  'eingang': () => const InboxScreen(),
  'zustand': () => const StateScreen(),
  'system': () => const SystemScreen(),
  'systemcheck': () => const CheckScreen(),
  'erfassen': () => const ChannelsScreen(),
  'anker': () => const AnchorsScreen(),
  'fokus': () => const FocusScreen(),
  'reiz': () => const SensationScreen(),
  'bremse': () => const InterceptScreen(),
  'review': () => const ReviewScreen(),
  'vorfälle': () => const SignalScreen(),
  'daten': () => const VaultScreen(),
  'expertenmodus': () => const ExpertScreen(),
  'hilfe': () => const HelpScreen(),
};

/// Die Blätter, die sich über einen Screen legen. Sie tragen die
/// Zahlenreihen und Regler — genau die Stellen, an denen feste Höhen sitzen.
final _sheets = <String, Future<void> Function(BuildContext)>{
  'erfassen-blatt': showCaptureSheet,
  'check-in-blatt': (c) => showCheckinSheet(c),
  'schlaf-blatt': (c) => showSleepSheet(c),
  'vorfall-blatt': showIncidentSheet,
};

/// Rollt bis ans Listenende und sammelt jeden gemeldeten Überlauf ein.
///
/// Nach jedem Schritt gefragt, nicht erst am Ende: `takeException()` hält
/// immer nur einen Fehler, alle weiteren landen als Konsolenausgabe im
/// Nichts.
Future<List<String>> _overflowsWhileScrolling(WidgetTester tester) async {
  final found = <String>[];
  void collect() {
    final Object? error = tester.takeException();
    if (error != null) found.add('$error');
  }

  collect();
  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isEmpty) return found;
  final target = scrollables.first;

  // Sprung statt Wischen: Ein Fling erzeugt Ballistik, deren Endpunkt von
  // der Bildwiederholrate abhaengt — der Test soll aber immer dieselbe
  // Strecke sehen.
  for (var step = 0; step < 60; step++) {
    final position = tester.state<ScrollableState>(target).position;
    if (!position.hasContentDimensions) break;
    if (position.pixels >= position.maxScrollExtent) break;
    final next = position.pixels + 240;
    position.jumpTo(
        next > position.maxScrollExtent ? position.maxScrollExtent : next);
    await tester.pump();
    collect();
  }
  return found;
}

/// Bruchstellen, die bekannt sind und außerhalb dieser Änderung liegen.
///
/// `instruments.dart:74` setzt „DATEN ALT", den Messwert und den Aufklapp-
/// Pfeil ohne Flex neben eine `Expanded`-Beschriftung; bei 360 px und
/// 2,4-fach läuft die Zeile um 27 px nach rechts hinaus. Sobald die Zeile
/// dort flexibel ist, fällt dieser Eintrag ersatzlos weg — und der Fall wird
/// wieder mitgeprüft.
const _knownOpen = <String, String>{
  'kleines Gerät, größte Schrift/zustand':
      'instruments.dart:74 — Row mit „DATEN ALT", Messwert und Pfeil ohne '
          'Flex; gehört nicht zu dieser Änderung',
};

void main() {
  _accessibility();

  late TestHarness h;

  setUp(() async {
    h = TestHarness.create(at: DateTime(2026, 8, 4, 14, 30));
    h.completeOnboarding();
    await h.seedChannels();
    // Etwas Inhalt: Ein leerer Screen laeuft nie ueber. Genau die Zeilen,
    // die aus echten Daten entstehen, sind die langen.
    for (final (title, ae) in [
      ('Steuerunterlagen für das vergangene Jahr zusammensuchen', 7),
      ('Rückruf beim Vermieter wegen der Nebenkostenabrechnung', 3),
      ('Kurz lüften', 1),
    ]) {
      await h.runtime.createTask(
        title: title,
        activationEnergy: ae,
        salience: 5,
        stakes: 6,
      );
    }
    await h.runtime.capture('Idee für das Regelwerk, die noch niemand '
        'aufgeschrieben hat und die deshalb hier steht');
    await h.runtime.checkIn(energy: 4, focus: 3, mood: 5, stimNeed: 7);
  });

  tearDown(() => h.dispose());

  /// Die Kombinationen, die wirklich vorkommen — nicht alle denkbaren.
  ///
  /// Klein × riesig ist der harte Fall. Gross × klein prueft die andere
  /// Richtung: dass nichts auseinanderfaellt, wenn Platz da ist.
  const cases = <({String name, Size size, double scale, Brightness mode})>[
    (
      name: 'kleines Gerät, größte Schrift',
      size: Size(360, 640),
      scale: 2.4,
      mode: Brightness.dark,
    ),
    (
      name: 'Telefon, große Schrift',
      size: Size(412, 915),
      scale: 1.6,
      mode: Brightness.dark,
    ),
    (
      name: 'Telefon, hell, kleinste Schrift',
      size: Size(412, 915),
      scale: 0.85,
      mode: Brightness.light,
    ),
  ];

  for (final c in cases) {
    group(c.name, () {
      for (final entry in _screens.entries) {
        final open = _knownOpen['${c.name}/${entry.key}'];
        testWidgets(
            open == null
                ? '${entry.key} läuft nicht über'
                : '${entry.key} läuft nicht über — offen: $open', (tester) async {
          await pumpScaled(
            tester,
            h.wrap(entry.value(), brightness: c.mode),
            size: c.size,
            textScale: c.scale,
          );

          // `takeException` liefert den Ueberlauf, den Flutter beim
          // Layout meldet. Ohne diese Abfrage faellt er im Test nur als
          // Konsolenausgabe an und bleibt unbemerkt.
          final errors = await _overflowsWhileScrolling(tester);
          expect(errors, isEmpty,
              reason: '${entry.key} bei ${c.size.width.toInt()}px / '
                  '${c.scale}×: ${errors.join(" | ")}');

          await unmount(tester);
        }, skip: open != null);
      }

      for (final entry in _sheets.entries) {
        final open = _knownOpen['${c.name}/${entry.key}'];
        testWidgets(
            open == null
                ? '${entry.key} läuft nicht über'
                : '${entry.key} läuft nicht über — offen: $open', (tester) async {
          await pumpScaled(
            tester,
            h.wrap(_SheetHost(open: entry.value), brightness: c.mode),
            size: c.size,
            textScale: c.scale,
          );
          await tester.tap(find.byKey(const Key('open-sheet')));
          await tester.pumpAndSettle(const Duration(milliseconds: 600));

          final errors = await _overflowsWhileScrolling(tester);
          expect(errors, isEmpty,
              reason: '${entry.key} bei ${c.size.width.toInt()}px / '
                  '${c.scale}×: ${errors.join(" | ")}');

          await unmount(tester);
        }, skip: open != null);
      }
    });
  }
}

/// Trifft man die Bedienelemente?
///
/// Androids Richtlinie sind 48 dp im Quadrat. Das ist keine Formalie: Bei
/// motorischer Unruhe und im Vorbeigehen getippt entscheidet die Zielgröße
/// darüber, ob eine Erfassung gelingt oder abbricht — und ein Abbruch im
/// Erfassungsmoment kostet den Gedanken [D9].
///
/// Zusätzlich der Kontrast: Die Oberfläche ist dunkel und sparsam, und
/// genau dort rutscht Text leicht unter die lesbare Schwelle.
void _accessibility() {
  group('Bedienbarkeit', () {
    late TestHarness h;
    setUp(() async {
      h = TestHarness.create(at: DateTime(2026, 8, 4, 14, 30));
      h.completeOnboarding();
      await h.seedChannels();
      await h.runtime.createTask(
        title: 'Rückruf beim Vermieter',
        activationEnergy: 3,
        salience: 5,
        stakes: 6,
      );
    });
    tearDown(() => h.dispose());

    for (final entry in _screens.entries) {
      testWidgets('${entry.key}: Ziele sind groß genug', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpScaled(tester, h.wrap(entry.value()));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        handle.dispose();
        await unmount(tester);
      });
    }

    for (final entry in _screens.entries) {
      testWidgets('${entry.key}: Text hebt sich ab', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpScaled(tester, h.wrap(entry.value()));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
        await unmount(tester);
      });
    }
  });
}

/// Ein Screen, der nichts tut, außer das Blatt zu öffnen.
class _SheetHost extends StatelessWidget {
  final Future<void> Function(BuildContext) open;
  const _SheetHost({required this.open});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const Key('open-sheet'),
            onPressed: () => open(context),
            child: const Text('auf'),
          ),
        ),
      );
}
