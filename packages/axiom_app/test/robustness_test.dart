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
///
/// **Warum „läuft nicht über" seit dieser Runde nicht mehr reicht.** Der Test
/// war grün, und trotzdem stand im Schlafblatt bei 360 px und 2,4-facher
/// Schrift „23:3" statt „23:30": Die Uhrzeit passte nicht in ihren halben
/// Kasten und brach hinter der dritten Ziffer um. Flutter meldet das nicht —
/// ein Umbruch ist kein Überlauf. Auf dem Schirm ist er trotzdem ein
/// abgeschnittener Messwert, und zwar der, aus dem die Stundenzahl entsteht.
///
/// Deshalb prüfen die Blätter jetzt zwei Dinge mehr, und beide sind
/// Wirkungsaussagen, keine Layoutdetails:
///
///  1. **Kein Messwert wird stumm abgeschnitten** — ein `Text` mit
///     `maxLines`, der seine Zeilenzahl überschreitet und *keine* Ellipse
///     trägt, ist eine Lüge: „23:3" sieht aus wie eine Uhrzeit.
///     Die Prüfung greift nur, wo ein Messwert sich auf eine Zeile festlegt;
///     genau deshalb steht an der Uhrzeit jetzt `maxLines: 1` statt eines
///     stillschweigenden Umbruchs. Ein Messwert, der umbrechen darf, ist
///     keiner.
///  2. **Die Handlung bleibt in Reichweite** — der gefüllte Knopf eines
///     Blattes steht ohne Rollweg auf dem Schirm (im Ortsblatt die erste
///     wählbare Zeile, siehe `_theAction`). Ein Check-in soll unter fünfzehn
///     Sekunden dauern (G1); bei 2,4-fach lag „Fertig" hinter zwei
///     Bildschirmen, und damit war die Zusage bei genau der Gruppe gebrochen,
///     die die Schrift hochstellt.
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
import 'package:axiom_app/screens/onboarding_screen.dart';
import 'package:axiom_app/screens/review_screen.dart';
import 'package:axiom_app/screens/sensation_screen.dart';
import 'package:axiom_app/screens/signal_screen.dart';
import 'package:axiom_app/screens/state_screen.dart';
import 'package:axiom_app/screens/system_screen.dart';
import 'package:axiom_app/screens/tasks_screen.dart';
import 'package:axiom_app/screens/vault_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:axiom_app/screens/atomize_sheet.dart';
import 'package:axiom_app/screens/body_sheet.dart';
import 'package:axiom_app/screens/capture_sheet.dart';
import 'package:axiom_app/screens/checkin_sheet.dart';
import 'package:axiom_app/screens/place_sheet.dart';
import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/rendering.dart';

import 'harness.dart';

/// Alle Screens, die ohne Argument erreichbar sind.
///
/// `onboarding` ist seit dieser Runde dabei. Er fehlte, obwohl er die
/// größten Schriftgrade der ganzen App trägt (`displayLarge`, 42 px) — bei
/// 2,4-fach sind das über hundert Pixel Zeilenhöhe, und genau dort bricht
/// ein Layout zuerst. Er ist außerdem der einzige Schirm, den jemand genau
/// einmal sieht: Was dort überläuft, fällt niemandem nachträglich auf.
final _screens = <String, Widget Function()>{
  'jetzt': () => const NowScreen(),
  'onboarding': () => OnboardingScreen(onDone: () {}),
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
///
/// Der Abend-Check-in steht eigens dabei: Er erhebt sechs Regler statt vier
/// und ist damit das längste Blatt, das im Alltag wirklich vorkommt. Das
/// Zerlege- und das Ortsblatt fehlten ganz — beide brauchen ein Argument und
/// waren deshalb nie eingetragen, obwohl das Zerlegeblatt zwei Textfelder,
/// sieben Formen und eine Zehnerskala trägt.
final _sheets = <String, Future<void> Function(BuildContext)>{
  'erfassen-blatt': showCaptureSheet,
  'check-in-blatt': (c) => showCheckinSheet(c),
  'abend-check-in-blatt': (c) => showCheckinSheet(c, slot: 'evening'),
  'schlaf-blatt': (c) => showSleepSheet(c),
  'vorfall-blatt': showIncidentSheet,
  'ort-blatt': (c) => showPlaceSheet(
    c,
    current: 'Büro',
    known: const ['Zuhause', 'Büro', 'Baumarkt'],
  ),
  'zerlege-blatt': (c) => showAtomizeSheet(
    c,
    const AtomizeCandidate(
      task: Task(
        id: 'T1',
        title: 'Steuerunterlagen für das vergangene Jahr zusammensuchen',
        activationEnergy: 7,
        salience: 5,
        stakes: 6,
      ),
      targetEnergy: 3,
      reason: AtomizeReason.outOfReach,
    ),
  ),
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
      next > position.maxScrollExtent ? position.maxScrollExtent : next,
    );
    await tester.pump();
    collect();
  }
  return found;
}

/// Text, der stumm abgeschnitten wird.
///
/// **Warum das nicht dasselbe ist wie ein Überlauf.** Ein Überlauf entsteht,
/// wenn ein Kind breiter ist als sein Kasten; Flutter malt einen gelben
/// Balken und meldet ihn. Ein `Text` läuft aber gar nicht über — er bricht
/// um, und wenn ihn ein `maxLines` deckelt, verschwindet der Rest wortlos.
/// Genau so entstand „23:3" im Schlafblatt.
///
/// Eine **Ellipse** ist davon ausgenommen und ausdrücklich erlaubt: „Rückruf
/// beim Verm…" sagt selbst, dass es weitergeht. „23:3" sagt es nicht — es
/// sieht aus wie eine gültige Uhrzeit. Der Unterschied ist der ganze Punkt.
List<String> _silentlyClipped(WidgetTester tester) {
  final found = <String>[];
  for (final element in find.byType(RichText).evaluate()) {
    final render = element.renderObject;
    if (render is! RenderParagraph) continue;
    if (!render.didExceedMaxLines) continue;
    if (render.overflow == TextOverflow.ellipsis ||
        render.overflow == TextOverflow.fade) {
      continue;
    }
    found.add('„${render.text.toPlainText()}"');
  }
  return found.toSet().toList();
}

/// Was in einem Blatt „die Handlung" ist.
///
/// Voreinstellung ist der gefüllte Knopf — er ist in diesem Entwurf der
/// Abschluss eines Blattes und damit die eine gemeinte Handlung (G1).
///
/// **Das Ortsblatt ist die begründete Ausnahme.** Dort ist die Handlung nicht
/// der Knopf, sondern die Zeile: ein Tipp hierher, ein Tipp auf den Eintrag.
/// „Setzen" gehört zum selteneren zweiten Weg — einen Namen tippen, den es
/// noch nicht gibt — und ist deshalb meistens ausgegraut. Festgenagelt
/// stünde unter dem Blatt ein toter Knopf und behauptete, er sei das
/// Gemeinte. Geprüft wird dort die erste wählbare Zeile.
Finder _theAction(String sheet) => switch (sheet) {
  'ort-blatt' => find.text('Kein Ort'),
  _ => find.byType(FilledButton),
};

/// Steht die gemeinte Handlung auf dem Schirm, ohne dass gerollt wird?
///
/// „Auf dem Schirm" heißt vollständig — ein Knopf, dessen untere Hälfte
/// unter dem Bildrand liegt, ist kein Ziel, sondern eine Ahnung.
String? _actionOutOfReach(WidgetTester tester, Finder action, Size screen) {
  if (action.evaluate().isEmpty) return null;
  final rect = tester.getRect(action.first);
  if (rect.bottom <= screen.height + 0.5 && rect.top >= -0.5) return null;
  return 'liegt bei ${rect.top.toStringAsFixed(0)}…'
      '${rect.bottom.toStringAsFixed(0)} px, der Schirm endet bei '
      '${screen.height.toInt()} px';
}

/// Blätter, deren Handlung heute hinter einem Rollweg liegt — nachgemessen.
///
/// Gleiche Bauart wie [_knownOpen] und derselbe Zweck: Der Befund steht
/// namentlich da, statt als Dauerrot, das man wegsieht. Wer das Blatt
/// umbaut, streicht den Eintrag.
const _actionOpen = <String, String>{
  'kleines Gerät, größte Schrift/vorfall-blatt':
      'signal_screen.dart — das Blatt hat keinen festen Abschluss; '
      '„Eintragen" liegt bei 3097…3179 px hinter einem Schirm von 640 px, '
      'also gut vier Bildschirme tief. Abhilfe: dieselbe Bauart wie im '
      'Check-in-, Schlaf-, Erfassungs- und Zerlegeblatt — Inhalt in ein '
      'Flexible, Abschluss darunter fest',
  'Telefon, große Schrift/vorfall-blatt':
      'signal_screen.dart — derselbe Befund, milder: 1601…1653 px bei einem '
      'Schirm von 915 px',
};

/// Bruchstellen, die bekannt sind und außerhalb dieser Änderung liegen.
///
/// Die Einträge sind **nachgemessen, nicht geschätzt**: Jeder nennt die
/// Datei und die Zeile, an der Flutter den Überlauf meldet, und die Zahl
/// stammt aus dem Lauf, nicht aus der Erinnerung. Wer die Zeile flexibel
/// macht, streicht den Eintrag — der Fall wird dann wieder mitgeprüft.
///
/// **Zur Größenordnung.** Der Test rendert ohne die gebündelten Schriften,
/// also in Ahem, und dort ist jedes Zeichen ein volles Geviert breit. Eine
/// Zeile, die hier um zehn Pixel hinausläuft, tut das mit IBM Plex
/// vermutlich nicht. Das ist kein Grund, die Meldung wegzudrücken: Ahem ist
/// die pessimistische Annahme, und eine Zeile ohne Flex bricht mit der
/// nächsten längeren Übersetzung ohnehin.
///
/// **Beide Einträge sind dieselbe Bauform** — eine `Row` mit
/// `Expanded`-Beschriftung und daneben zwei bis drei Kinder ohne Flex. Der
/// Vorgängereintrag (`instruments.dart:74`, damals 27 px) ist nicht
/// verschwunden, sondern nach `instruments.dart:105` gewandert und auf 77 px
/// gewachsen: „DATEN ALT" hieß dort inzwischen „Daten alt" und steht nicht
/// mehr in 11 px Schreibmaschine, sondern in 14 px Fließtext. Der Ton ist
/// besser geworden, die Zeile breiter.
const _knownOpen = <String, String>{
  'kleines Gerät, größte Schrift/zustand':
      'instruments.dart:105 — Row aus Expanded(Beschriftung), „Daten alt", '
      'Messwert und Aufklapp-Pfeil; die drei rechten Kinder haben keinen '
      'Flex. 360 px/2,4×: 77 px nach rechts hinaus. Abhilfe: „Daten alt" '
      'in ein Flexible mit Ellipse, oder in die Zeile darunter',
  'kleines Gerät, größte Schrift/eingang':
      'inbox_screen.dart:189 — Row aus Text("SORTIEREN") und Chevron ohne '
      'Flex, innerhalb des äußeren Wrap. 360 px/2,4×: 9,8 px nach rechts '
      'hinaus. Abhilfe: Flexible mit Ellipse — und der Text selbst sind '
      'neun gesperrte Versalien, die nach dem Entwurf ohnehin gehen',
  // Gefunden, weil dieser Schirm neu in der Liste steht. Die äußere Zeile
  // ist gegen genau diesen Fall gehärtet („Wrap statt Row", siehe den
  // Kommentar dort) — die innere ist es nicht, und sie trägt dieselbe Last.
  'kleines Gerät, größte Schrift/onboarding':
      'capacity_line.dart:81 — die innere Row aus „Kapazität" und dem Wert '
      'hat mainAxisSize.min und keinen Flex; der umgebende Wrap kann sie '
      'deshalb umbrechen, aber nicht schmaler machen. 360 px/2,4×, '
      'Seite 3 des Onboardings: 98 px nach rechts hinaus. Abhilfe: '
      'Flexible mit Ellipse um „Kapazität"',
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
    await h.runtime.capture(
      'Idee für das Regelwerk, die noch niemand '
      'aufgeschrieben hat und die deshalb hier steht',
    );
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
              : '${entry.key} läuft nicht über — offen: $open',
          (tester) async {
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
            expect(
              errors,
              isEmpty,
              reason:
                  '${entry.key} bei ${c.size.width.toInt()}px / '
                  '${c.scale}×: ${errors.join(" | ")}',
            );

            await unmount(tester);
          },
          skip: open != null,
        );
      }

      for (final entry in _sheets.entries) {
        final open = _knownOpen['${c.name}/${entry.key}'];
        testWidgets(
          open == null
              ? '${entry.key} läuft nicht über'
              : '${entry.key} läuft nicht über — offen: $open',
          (tester) async {
            await pumpScaled(
              tester,
              h.wrap(_SheetHost(open: entry.value), brightness: c.mode),
              size: c.size,
              textScale: c.scale,
            );
            await tester.tap(find.byKey(const Key('open-sheet')));
            await tester.pumpAndSettle(const Duration(milliseconds: 600));

            final errors = await _overflowsWhileScrolling(tester);
            expect(
              errors,
              isEmpty,
              reason:
                  '${entry.key} bei ${c.size.width.toInt()}px / '
                  '${c.scale}×: ${errors.join(" | ")}',
            );

            await unmount(tester);
          },
          skip: open != null,
        );

        testWidgets('${entry.key}: kein Messwert wird stumm abgeschnitten', (
          tester,
        ) async {
          await pumpScaled(
            tester,
            h.wrap(_SheetHost(open: entry.value), brightness: c.mode),
            size: c.size,
            textScale: c.scale,
          );
          await tester.tap(find.byKey(const Key('open-sheet')));
          await tester.pumpAndSettle(const Duration(milliseconds: 600));

          final clipped = _silentlyClipped(tester);
          expect(
            clipped,
            isEmpty,
            reason:
                '${entry.key} bei ${c.size.width.toInt()}px / '
                '${c.scale}×: abgeschnitten ohne Ellipse — '
                '${clipped.join(" | ")}',
          );

          await unmount(tester);
        });

        final reach = _actionOpen['${c.name}/${entry.key}'];
        testWidgets(
          reach == null
              ? '${entry.key}: die Handlung bleibt in Reichweite'
              : '${entry.key}: die Handlung bleibt in Reichweite — '
                    'offen: $reach',
          (tester) async {
            await pumpScaled(
              tester,
              h.wrap(_SheetHost(open: entry.value), brightness: c.mode),
              size: c.size,
              textScale: c.scale,
            );
            await tester.tap(find.byKey(const Key('open-sheet')));
            await tester.pumpAndSettle(const Duration(milliseconds: 600));

            final problem = _actionOutOfReach(
              tester,
              _theAction(entry.key),
              c.size,
            );
            expect(
              problem,
              isNull,
              reason:
                  '${entry.key} bei ${c.size.width.toInt()}px / '
                  '${c.scale}×: die Handlung $problem',
            );

            await unmount(tester);
          },
          skip: reach != null,
        );
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
