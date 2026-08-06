/// Erzeugt Referenzbilder der Oberflaeche.
///
///   flutter test test/screenshot_test.dart --update-goldens
///
/// Dient zwei Zwecken: visuelle Kontrolle beim Entwickeln und ein Regressions-
/// netz gegen unbeabsichtigte Layoutaenderungen.
///
/// **Eine Runde ansehen, ohne den Bestand anzufassen:**
///
///   AXIOM_GOLDEN_DIR=/tmp/schliff \
///     flutter test test/screenshot_test.dart --update-goldens
///
/// Siehe [_shots]. Ein Referenzbild, das niemand angesehen hat, nagelt einen
/// Fehler fest, statt ihn zu fangen — und `--update-goldens` schreibt sofort.
@Tags(['golden'])
library;

import 'dart:io';

import 'package:axiom_app/screens/anchors_screen.dart';
import 'package:axiom_app/screens/atomize_sheet.dart';
import 'package:axiom_app/screens/focus_screen.dart';
import 'package:axiom_app/screens/inbox_screen.dart';
import 'package:axiom_app/screens/intercept_screen.dart';
import 'package:axiom_app/screens/sensation_screen.dart';
import 'package:axiom_app/screens/signal_screen.dart';
import 'package:axiom_app/screens/review_screen.dart';
import 'package:axiom_app/screens/now_screen.dart';
import 'package:axiom_app/screens/onboarding_screen.dart';
import 'package:axiom_app/screens/state_screen.dart';
import 'package:axiom_app/screens/system_screen.dart';
import 'package:axiom_app/screens/tasks_screen.dart';
import 'package:axiom_app/design/theme.dart';
import 'package:axiom_app/design/tokens.dart';
import 'package:axiom_app/state/providers.dart';
import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// Verzeichnis der Referenzbilder — normalerweise `test/screenshots/`.
///
/// Ueber `AXIOM_GOLDEN_DIR` umlenkbar, und das ist keine Bequemlichkeit,
/// sondern die Arbeitsweise: `--update-goldens` schreibt ohne Rueckfrage. Wer
/// einen Schirm geaendert hat, rendert erst in ein Nebenverzeichnis, sieht
/// sich jedes Bild an und schreibt den Bestand erst danach fort. Sonst wird
/// aus dem Netz gegen Regressionen ein Protokoll davon.
final String _shots =
    Platform.environment['AXIOM_GOLDEN_DIR'] ?? 'screenshots';

/// Laedt die gebuendelten Schriften — ohne das rendern Goldens in Ahem.
Future<void> loadAppFonts() async {
  // Material-Icons aus dem Flutter-SDK, sonst erscheinen Symbole als Kaesten.
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
      '${Platform.environment['HOME']}/flutter';
  final iconFont = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (iconFont.existsSync()) {
    await (FontLoader('MaterialIcons')
          ..addFont(
              Future.value(ByteData.sublistView(iconFont.readAsBytesSync()))))
        .load();
  }

  for (final (family, files) in [
    ('PlexSans', [
      'IBMPlexSans-Light.ttf',
      'IBMPlexSans-Regular.ttf',
      'IBMPlexSans-Medium.ttf',
      'IBMPlexSans-SemiBold.ttf',
    ]),
    ('PlexMono', [
      'IBMPlexMono-Regular.ttf',
      'IBMPlexMono-Medium.ttf',
      'IBMPlexMono-SemiBold.ttf',
    ]),
  ]) {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = File('assets/fonts/$file').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}

/// Referenzbilder MIT Schatten.
///
/// **Warum das eine eigene Bindung braucht.** `flutter test` benutzt
/// `AutomatedTestWidgetsFlutterBinding`, und die setzt `disableShadows => true`
/// — Flutter zeichnet Schatten dann als harte, unweichgezeichnete Rechtecke.
/// Fuer die meisten Tests ist das richtig: Ein Weichzeichner ist nicht
/// bitgenau reproduzierbar, und ein Golden, das auf zwei Rechnern verschieden
/// aussieht, ist wertlos.
///
/// Fuer AXIOM war es fatal. Seit dem Umbau traegt der Schatten die halbe
/// Gestaltung: `Panel` hat keinen Rahmen mehr, sondern Erhebung; die
/// Reichweitenkante unterscheidet „in Reichweite" von „heute nicht" ueber
/// Schatten gegen Mulde; `Panel(reachable:)` ist nichts als ein staerkerer
/// Schatten. In den Referenzbildern stand davon **nichts** — unter jeder Karte
/// lag stattdessen ein zweiter Kasten mit scharfer Kante. Vier Designer, zwoelf
/// Juroren und der Nutzer haben damit eine haertere Fassung beurteilt als die,
/// die auf dem Geraet laeuft. Und eine Schattenregression konnte kein Golden
/// fangen, weil kein Golden je einen Schatten enthielt.
///
/// Der Preis: Diese Bilder sind minimal weniger reproduzierbar als harte
/// Kanten. Das ist der richtige Tausch — ein Bild, das die Gestaltung nicht
/// zeigt, prueft die Gestaltung nicht.
class _ShadowBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get disableShadows => false;
}

void main() {
  // Vor allem anderen: Bindungen sind Singletons, die erste gewinnt.
  _ShadowBinding();
  setUpAll(loadAppFonts);

  late TestHarness h;
  setUp(() => h = TestHarness.create());
  tearDown(() => h.dispose());

  /// Wie `TestHarness.wrap`, nur mit waehlbarem Farbschema.
  ///
  /// **Warum das hier steht und nicht im Geruest.** `wrap` nimmt kein Schema
  /// entgegen, und die Referenzbilder zeigten deshalb jahrelang genau eine
  /// der acht Paletten: `instrument`, dunkel — dazu ein einziges helles Bild.
  /// `contrast`, `muted` und `workbench` hat nie jemand angesehen. Das ist
  /// nicht theoretisch: `muted` ist die Fassung, die abends laeuft (D8), und
  /// `workbench` die einzige mit blauem Signal und weissen Flaechen. Wenn
  /// eine Erhebung, eine Mulde oder eine Haarlinie in einem dieser Schemata
  /// verschwindet, faellt es ohne Bild nicht auf.
  ///
  /// Das Geruest bleibt unangetastet — andere Tests haengen daran.
  Widget wrapScheme(
    Widget child, {
    required Brightness brightness,
    required AxiomScheme scheme,
  }) =>
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(h.clock),
          runtimeProvider.overrideWith((ref) async => h.runtime),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAxiomTheme(brightness: brightness, scheme_: scheme),
          home: child,
        ),
      );

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget widget, {
    Brightness brightness = Brightness.dark,
    AxiomScheme scheme = AxiomScheme.instrument,
    double textScale = 1.0,
  }) async {
    final app = wrapScheme(widget, brightness: brightness, scheme: scheme);
    if (textScale == 1.0) {
      await pumpPhone(tester, app);
    } else {
      // Ueber `MediaQuery`, nicht ueber das Theme — genau so kommt die
      // Skalierung in der App an (`app.dart`).
      await pumpScaled(tester, app, textScale: textScale);
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('$_shots/$name.png'),
    );
  }

  testWidgets('01 onboarding — was das ist', (tester) async {
    await shoot(tester, '01-onboarding-was', OnboardingScreen(onDone: () {}));
  });

  testWidgets('02 onboarding — kapazitaetslinie', (tester) async {
    await pumpPhone(tester, h.wrap(OnboardingScreen(onDone: () {})));
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Weiter').last);
      await tester.pumpAndSettle();
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('$_shots/02-onboarding-linie.png'),
    );
  });

  testWidgets('03 jetzt — leer', (tester) async {
    h.completeOnboarding();
    await shoot(tester, '03-jetzt-leer', const NowScreen());
  });

  /// Der Bestand, an dem die Reichweitenkante etwas zu zeigen hat: zwei
  /// Aufgaben ueber und drei unter der heutigen Kapazitaet.
  Future<void> seedNow() async {
    h.completeOnboarding();
    await h.runtime.checkIn(energy: 4, focus: 4, mood: 4, stimNeed: 3);
    for (final (title, ae, stakes) in [
      ('Steuerunterlagen sortieren', 8, 9),
      ('Rückruf Werkstatt', 2, 6),
      ('Reifen wechseln lassen', 4, 5),
      ('Antrag Krankenkasse', 7, 8),
      ('Rechnung Elektriker prüfen', 3, 4),
    ]) {
      await h.runtime.createTask(
        title: title,
        activationEnergy: ae,
        salience: 4,
        stakes: stakes,
      );
    }
    await h.runtime.createAnchor(
      title: 'Zahnarzt',
      arriveBy: h.clock.nowLocal().add(const Duration(minutes: 75)),
      travel: const Duration(minutes: 25),
      location: 'Praxis',
    );
  }

  testWidgets('04 jetzt — mit Aufgaben', (tester) async {
    await seedNow();
    await shoot(tester, '04-jetzt-aufgaben', const NowScreen());
  });

  // ── Der Hauptfall: eine Regel hat gefeuert ──────────────────────────────
  //
  // **Warum das eine eigene Vorrichtung braucht.** Alle uebrigen
  // `jetzt`-Bilder zeigen den Rueckfallpfad: `_TaskCard` ohne Regel — die
  // Karte, die AXIOM zeigt, wenn *keine* Regel zutrifft. Der regelgetriebene
  // `_DecisionCard` mit `RuleStamp`, Defizitcode und antippbarer Begruendung
  // stand in **keinem** Referenzbild. Der Schirm, um den es in diesem Projekt
  // geht, war in seiner eigentlichen Form nie angesehen worden — und die
  // Karte, die G2 auf dem Hauptschirm einloest, war damit ungeprueft.
  //
  // Die Vorrichtung stellt die Uhr auf 09:00 und legt weder Check-in noch
  // Schlafeintrag an. Damit treffen zwei Regeln zu: R-001 („Check-in
  // Morgen", 08:45–09:30, Prioritaet 70) und R-111 („Schlaf eintragen",
  // 07:30–10:00, Prioritaet 55). Auf dem Bild steht **R-111**.
  //
  // Das ist kein Versehen der Vorrichtung, sondern ein Befund: Ein einziger
  // Aufruf des Jetzt-Schirms wertet das Regelwerk **zweimal** aus und
  // schreibt beide Male eine Entscheidung fort (nachgemessen:
  // `totalInterventionsToday() == 2`, `firedToday('R-001') == 1`). Ursache
  // ist `languageProvider`: Solange `runtimeProvider` laedt, liefert er die
  // Geraetesprache, danach die gespeicherte — `snapshotProvider` haengt
  // daran und rechnet neu. Die erste Auswertung gewinnt mit R-001, wird nie
  // gezeichnet und verbraucht dabei deren Cooldown (60 min, einmal am Tag);
  // die zweite sieht R-001 gesperrt und nimmt die naechstbeste Regel.
  //
  // Solange das so ist, zeigt dieses Bild, was das Geraet zeigt. Wird der
  // Doppellauf behoben, wechselt es auf R-001 — und genau dafuer ist ein
  // Referenzbild da.
  Future<void> seedFiringRule() async {
    // Das Geruest aus `setUp` traegt die falsche Uhrzeit. Es wegzuwerfen ist
    // billiger als eine zweite Uhr durchzureichen; `tearDown` schliesst das
    // neue.
    h.dispose();
    h = TestHarness.create(at: DateTime(2026, 8, 3, 9, 0));
    h.completeOnboarding();
    for (final (title, ae, stakes) in [
      ('Steuerunterlagen sortieren', 8, 9),
      ('Rückruf Werkstatt', 2, 6),
      ('Rechnung Elektriker prüfen', 3, 4),
    ]) {
      await h.runtime.createTask(
        title: title,
        activationEnergy: ae,
        salience: 4,
        stakes: stakes,
      );
    }
  }

  testWidgets('40 jetzt — eine Regel hat gefeuert', (tester) async {
    await seedFiringRule();
    await shoot(tester, '40-jetzt-regel', const NowScreen());
  });

  testWidgets('41 jetzt — eine Regel hat gefeuert, hell', (tester) async {
    // Die Regelplakette ist das einzige technisch gesetzte Element des
    // Schirms. Ob sie auf hellem Grund noch als das Besondere liest, sagt
    // nur das Bild — im Dunkeln traegt die Farbe mehr als die Schrift.
    await seedFiringRule();
    await shoot(tester, '41-jetzt-regel-hell', const NowScreen(),
        brightness: Brightness.light);
  });

  testWidgets('05 zustand', (tester) async {
    h.completeOnboarding();
    await h.runtime.checkIn(
      energy: 3,
      focus: 2,
      mood: 3,
      stimNeed: 4,
      compensation: 4,
      recovery: 2,
      slot: 'evening',
    );
    await shoot(tester, '05-zustand', const StateScreen());
  });

  testWidgets('06 system — regelinspektor', (tester) async {
    h.completeOnboarding();
    await shoot(tester, '06-system', const SystemScreen());
  });

  testWidgets('07 eingang', (tester) async {
    h.completeOnboarding();
    for (final text in [
      'Termin Zahnarzt verschieben',
      'Idee: Regelwerk um Wochenreview ergänzen',
      'Kabel für den Monitor bestellen',
    ]) {
      await h.runtime.capture(text);
    }
    await shoot(tester, '07-eingang', const InboxScreen());
  });

  testWidgets('19 onboarding — health connect', (tester) async {
    await pumpPhone(tester, h.wrap(OnboardingScreen(onDone: () {})));
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Weiter').last);
      await tester.pumpAndSettle();
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('$_shots/19-onboarding-health.png'),
    );
  });

  testWidgets('18 aufgaben — der ganze bestand', (tester) async {
    h.completeOnboarding();
    final tasks = [
      ('Steuerunterlagen sortieren', 3),
      ('Rechnung Werkstatt bezahlen', 2),
      ('Wohnung streichen', 9),
      ('Rückruf Vermieter', 2),
    ];
    for (final (title, ae) in tasks) {
      await h.runtime.createTask(
        title: title,
        activationEnergy: ae,
        salience: 5,
        stakes: 6,
      );
    }
    final all = await h.store.tasks();
    await h.runtime.startTask(all.firstWhere((t) => t.activationEnergy == 2));
    await shoot(tester, '18-aufgaben', const TasksScreen());
  });

  testWidgets('09 anker — rückwärtsverkettung', (tester) async {
    h.completeOnboarding();
    await h.runtime.createAnchor(
      title: 'Zahnarzt',
      arriveBy: h.clock.nowLocal().add(const Duration(hours: 3, minutes: 30)),
      travel: const Duration(minutes: 25),
      location: 'Praxis Bergmann',
    );
    await h.runtime.createAnchor(
      title: 'Elterngespräch',
      arriveBy: h.clock.nowLocal().add(const Duration(hours: 8)),
      travel: const Duration(minutes: 15),
      location: 'Schule',
    );
    await shoot(tester, '09-anker', const AnchorsScreen());
  });

  testWidgets('10 zerlegen — erster Schritt', (tester) async {
    h.completeOnboarding();
    final task = await h.runtime.createTask(
      title: 'Steuerunterlagen für 2025 sortieren',
      activationEnergy: 9,
      salience: 2,
      stakes: 9,
      decayAt: h.clock.nowLocal().add(const Duration(hours: 40)),
    );
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
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('$_shots/10-zerlegen.png'),
    );
  });

  testWidgets('11 review — wochenbericht', (tester) async {
    h.completeOnboarding();
    for (var i = 0; i < 12; i++) {
      await h.runtime.checkIn(
        energy: 3,
        focus: 3,
        mood: 3,
        stimNeed: 4,
        compensation: 4,
        recovery: 2,
        slot: 'evening',
      );
      await h.runtime.capture('Notiz $i');
    }
    await h.store.logUsage('system', const Duration(minutes: 7));
    await shoot(tester, '11-review',
        const ReviewScreen(scope: ReviewScope.week));
    await unmount(tester);
  });

  testWidgets('12 fokus — laufender block', (tester) async {
    h.completeOnboarding();
    await h.runtime.startFocus(
      taskId: 't1',
      taskTitle: 'Steuerunterlagen sortieren',
      planned: const Duration(minutes: 50),
    );
    h.clock.advance(const Duration(minutes: 62));
    await shoot(tester, '12-fokus', const FocusScreen());
  });

  testWidgets('13 reiz — haushalt', (tester) async {
    h.completeOnboarding();
    await h.seedChannels();
    final session = await h.runtime.startFocus(taskTitle: 'Arbeit');
    h.clock.advance(const Duration(minutes: 120));
    await h.runtime.endFocus(session);
    await h.runtime.checkIn(energy: 3, focus: 3, mood: 3, stimNeed: 5);
    await shoot(tester, '13-reiz', const SensationScreen());
  });

  testWidgets('14 bremse — wartezeit', (tester) async {
    h.completeOnboarding();
    const trigger = InterceptTrigger(
      id: 'purchase',
      label: 'Anschaffung über 200 €',
      cooldown: Duration(minutes: 15),
      checklist: [
        'Kannte ich das vor heute?',
        'Ist es die Sache oder das Gefühl?',
        'Wie sehe ich das in vier Wochen?',
      ],
      authorized: true,
    );
    await h.runtime.saveTrigger(trigger);
    await h.runtime.startIntercept(trigger);
    h.clock.advance(const Duration(minutes: 4));
    await shoot(tester, '14-bremse', const InterceptScreen());
  });

  testWidgets('15 eichung — baseline bereit', (tester) async {
    h.completeOnboarding();
    for (var i = 0; i < 22; i++) {
      await h.runtime.checkIn(energy: 3, focus: 3, mood: 3, stimNeed: 3);
      h.clock.advance(const Duration(hours: 5));
    }
    for (var i = 0; i < 8; i++) {
      await h.runtime.logSleep(
        bedAt: h.clock.nowLocal().subtract(const Duration(hours: 8)),
        wakeAt: h.clock.nowLocal(),
        quality: 3,
      );
      h.clock.advance(const Duration(hours: 24));
    }
    h.clock.advance(const Duration(days: 2));
    await shoot(tester, '15-eichung-bereit', const SystemScreen());
  });

  testWidgets('16 eichung — baseline laeuft', (tester) async {
    h.completeOnboarding();
    for (var i = 0; i < 9; i++) {
      await h.runtime.checkIn(energy: 3, focus: 3, mood: 3, stimNeed: 3);
      h.clock.advance(const Duration(hours: 8));
    }
    for (var i = 0; i < 3; i++) {
      await h.runtime.logSleep(
        bedAt: h.clock.nowLocal().subtract(const Duration(hours: 7)),
        wakeAt: h.clock.nowLocal(),
        quality: 3,
      );
      h.clock.advance(const Duration(hours: 24));
    }
    await shoot(tester, '16-eichung-laeuft', const SystemScreen());
  });

  testWidgets('17 vorfaelle — nachbetrachtung faellig', (tester) async {
    h.completeOnboarding();
    for (final (trigger, intensity) in [
      (TriggerClass.rejection, 5),
      (TriggerClass.criticism, 3),
      (TriggerClass.rejection, 4),
      (TriggerClass.overload, 2),
    ]) {
      await h.runtime.logIncident(intensity: intensity, triggerClass: trigger);
      h.clock.advance(const Duration(hours: 30));
    }
    await shoot(tester, '17-vorfaelle', const SignalScreen());
  });

  testWidgets('08 jetzt — hell', (tester) async {
    h.completeOnboarding();
    await h.runtime.checkIn(energy: 4, focus: 4, mood: 4, stimNeed: 2);
    await h.runtime.createTask(
      title: 'Rückruf Werkstatt',
      activationEnergy: 2,
      salience: 5,
      stakes: 6,
    );
    await shoot(tester, '08-jetzt-hell', const NowScreen(),
        brightness: Brightness.light);
  });

  // ── Die vier Schemata ───────────────────────────────────────────────────
  //
  // Bis hierher zeigen fast alle Bilder `instrument`. Vier Schemata sind aber
  // keine Geschmacksfrage, sondern vier Umgebungen (siehe `AxiomScheme`):
  // Sonne, Abend, grosser Bildschirm. Und weil eine Palette in beiden
  // Helligkeiten existiert, sind es acht Fassungen — von denen bis zu dieser
  // Runde vier nie jemand gesehen hat: `contrast/light`, `muted/light`,
  // `workbench/dark` und `instrument/light` mit gefuelltem Bestand.
  //
  // Was daran haengt, ist nicht Geschmack:
  //
  //  * Die **Mulde** ist eine gerechnete Verdunklung des Grundes. In einem
  //    sehr dunklen Schema (`contrast/dark`, Grund #0A0C0E) bleibt davon
  //    rechnerisch fast nichts uebrig — ohne Bild faellt nicht auf, dass die
  //    Signatur dort nur noch aus Lichtlippe und Innenschatten besteht.
  //  * Die **Erhebung** kommt im Hellen aus Schatten, im Dunkeln aus
  //    Kantenlicht. `workbench/dark` ist das einzige dunkle Schema mit blauem
  //    Signal; ob die eine erhobene Karte dort noch heraussticht (G1), sagt
  //    nur das Bild.
  //  * `muted` soll abends nichts zum Leuchten bringen (D8). Ob das gelingt,
  //    entscheidet die groesste helle Flaeche des Schirms — der Hauptknopf.
  //
  // Der Hauptschirm bekommt deshalb alle acht Fassungen mit demselben
  // Bestand, damit sie sich nebeneinander vergleichen lassen.

  testWidgets('20 jetzt — kontrast', (tester) async {
    await seedNow();
    await shoot(tester, '20-jetzt-kontrast', const NowScreen(),
        scheme: AxiomScheme.contrast);
  });

  testWidgets('21 jetzt — gedämpft', (tester) async {
    await seedNow();
    await shoot(tester, '21-jetzt-gedaempft', const NowScreen(),
        scheme: AxiomScheme.muted);
  });

  testWidgets('22 jetzt — werkbank', (tester) async {
    await seedNow();
    await shoot(tester, '22-jetzt-werkbank', const NowScreen(),
        brightness: Brightness.light, scheme: AxiomScheme.workbench);
  });

  // Der Zustandsschirm traegt die Herleitungstafel — die eine Stelle, an der
  // Messwerte, Terme und Summe untereinander stehen (G2). In der Werkbank
  // ist das Signal blau statt bernstein; wenn die Messfarbe irgendwo als
  // Note gelesen wird, dann hier.
  testWidgets('23 zustand — werkbank', (tester) async {
    h.completeOnboarding();
    await h.runtime.checkIn(
      energy: 3,
      focus: 2,
      mood: 3,
      stimNeed: 4,
      compensation: 4,
      recovery: 2,
      slot: 'evening',
    );
    await shoot(tester, '23-zustand-werkbank', const StateScreen(),
        brightness: Brightness.light, scheme: AxiomScheme.workbench);
  });

  /// Der Zustandsschirm mit **aufgeklappter** Herleitung.
  ///
  /// G2 verlangt: kein Score ohne sichtbare Formel. Sichtbar ist die Formel
  /// aber erst nach einem Tippen, und lange zeigte **kein** Referenzbild sie
  /// — ausgerechnet die Tafel, deren Termsumme frueher eine andere Zahl
  /// ergab als die Anzeige darueber.
  Future<void> shootBreakdown(
    WidgetTester tester,
    String name, {
    Brightness brightness = Brightness.dark,
    AxiomScheme scheme = AxiomScheme.instrument,
  }) async {
    h.completeOnboarding();
    await h.runtime.checkIn(
      energy: 3,
      focus: 2,
      mood: 3,
      stimNeed: 4,
      compensation: 4,
      recovery: 2,
      slot: 'evening',
    );
    await pumpPhone(tester,
        wrapScheme(const StateScreen(), brightness: brightness, scheme: scheme));
    await tester.tap(find.text('Kapazität').first);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('$_shots/$name.png'),
    );
  }

  testWidgets('24 zustand — herleitung aufgeklappt', (tester) async {
    await shootBreakdown(tester, '24-herleitung');
  });

  // ── Die vier Fassungen, die nie jemand gesehen hat ──────────────────────

  testWidgets('25 jetzt — kontrast hell', (tester) async {
    // `contrast` ist fuer Sonne auf dem Display gedacht — also fuer draussen,
    // also fuer hell. Ausgerechnet diese Haelfte hatte kein Bild.
    await seedNow();
    await shoot(tester, '25-jetzt-kontrast-hell', const NowScreen(),
        brightness: Brightness.light, scheme: AxiomScheme.contrast);
  });

  testWidgets('26 jetzt — gedämpft hell', (tester) async {
    await seedNow();
    await shoot(tester, '26-jetzt-gedaempft-hell', const NowScreen(),
        brightness: Brightness.light, scheme: AxiomScheme.muted);
  });

  testWidgets('27 jetzt — werkbank dunkel', (tester) async {
    // Das einzige dunkle Schema mit blauem Signal und blaeulichem Grund.
    await seedNow();
    await shoot(tester, '27-jetzt-werkbank-dunkel', const NowScreen(),
        scheme: AxiomScheme.workbench);
  });

  testWidgets('28 jetzt — instrument hell', (tester) async {
    // `08-jetzt-hell` zeigt dieselbe Palette mit einer einzigen Aufgabe und
    // damit ohne Tiefzone. Fuer den Vergleich der acht Fassungen braucht es
    // denselben Bestand wie 04, 20, 21, 22 und 25 bis 27.
    await seedNow();
    await shoot(tester, '28-jetzt-instrument-hell', const NowScreen(),
        brightness: Brightness.light);
  });

  // ── Die Reichweitenkante mit tiefer Mulde ───────────────────────────────
  //
  // Auf dem Hauptschirm liegt unter der Kante eine Liste von Zugaengen; der
  // Aufgabenschirm ist der Ort, an dem darunter wirklich Aufgaben liegen —
  // mit „zerlegen ›" als einziger farbiger Handlung der Tiefzone. Wenn das
  // Ausgrauen jemals zurueckkommt, faellt es hier auf.

  testWidgets('29 aufgaben — gedämpft', (tester) async {
    await seedNow();
    await shoot(tester, '29-aufgaben-gedaempft', const TasksScreen(),
        scheme: AxiomScheme.muted);
  });

  testWidgets('30 aufgaben — werkbank hell', (tester) async {
    await seedNow();
    await shoot(tester, '30-aufgaben-werkbank-hell', const TasksScreen(),
        brightness: Brightness.light, scheme: AxiomScheme.workbench);
  });

  // ── Die Herleitung in den uebrigen Fassungen ────────────────────────────

  testWidgets('31 herleitung — gedämpft', (tester) async {
    // Die Tafel ist die groesste zusammenhaengende Textflaeche der App. Wenn
    // abends etwas ermuedet, dann diese.
    await shootBreakdown(tester, '31-herleitung-gedaempft',
        scheme: AxiomScheme.muted);
  });

  testWidgets('32 herleitung — kontrast hell', (tester) async {
    await shootBreakdown(tester, '32-herleitung-kontrast-hell',
        brightness: Brightness.light, scheme: AxiomScheme.contrast);
  });

  testWidgets('33 herleitung — werkbank dunkel', (tester) async {
    await shootBreakdown(tester, '33-herleitung-werkbank-dunkel',
        scheme: AxiomScheme.workbench);
  });

  // ── Ein Blatt ───────────────────────────────────────────────────────────
  //
  // Im Blatt ist `panel` der Untergrund selbst. Alles, was sich sonst mit
  // `panel` von `base` abhebt, muss hier anders arbeiten — die Formenchips
  // etwa liegen in der Mulde statt auf einer Flaeche. Ob das in jedem Schema
  // traegt, sagt nur das Bild.

  Future<void> shootAtomize(
    WidgetTester tester,
    String name, {
    Brightness brightness = Brightness.dark,
    AxiomScheme scheme = AxiomScheme.instrument,
  }) async {
    h.completeOnboarding();
    final task = await h.runtime.createTask(
      title: 'Steuerunterlagen für 2025 sortieren',
      activationEnergy: 9,
      salience: 2,
      stakes: 9,
      decayAt: h.clock.nowLocal().add(const Duration(hours: 40)),
    );
    await pumpPhone(tester,
        wrapScheme(const Scaffold(), brightness: brightness, scheme: scheme));
    showAtomizeSheet(
      tester.element(find.byType(Scaffold)),
      AtomizeCandidate(
        task: task,
        reason: AtomizeReason.urgentButUnreachable,
        targetEnergy: 2,
      ),
    ).ignore();
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('$_shots/$name.png'),
    );
  }

  testWidgets('34 zerlegen — gedämpft', (tester) async {
    await shootAtomize(tester, '34-zerlegen-gedaempft',
        scheme: AxiomScheme.muted);
  });

  testWidgets('35 zerlegen — werkbank hell', (tester) async {
    await shootAtomize(tester, '35-zerlegen-werkbank-hell',
        brightness: Brightness.light, scheme: AxiomScheme.workbench);
  });

  // ── Das Regelwerk ───────────────────────────────────────────────────────
  //
  // Die laengste Liste der App und der Ort, an dem G2 sichtbar wird: Jede
  // Zeile traegt ihre Regel-ID, und die ist seit dem Umbau das einzige
  // technisch gesetzte Element eines Schirms. Ohne Bild ist nicht pruefbar,
  // ob sie in einer hellen Palette noch als das Besondere liest.

  testWidgets('36 regelwerk', (tester) async {
    h.completeOnboarding();
    await shoot(tester, '36-regelwerk', const RulesScreen());
  });

  testWidgets('37 regelwerk — kontrast hell', (tester) async {
    h.completeOnboarding();
    await shoot(tester, '37-regelwerk-kontrast-hell', const RulesScreen(),
        brightness: Brightness.light, scheme: AxiomScheme.contrast);
  });

  // ── Grosse Schrift ──────────────────────────────────────────────────────
  //
  // Die Systemschriftgroesse ist bei diesem Profil kein Randfall: Was man
  // zusammenkneifen muss, wird uebersprungen [D9]. Bei 1,6-facher Schrift
  // bricht Layout, das bei 1,0 sauber aussieht — die Reichweitenkante ist
  // eine Zeile aus Beschriftung, Zahl und auslaufendem Strich und damit der
  // erste Kandidat.

  testWidgets('38 jetzt — grosse Schrift', (tester) async {
    await seedNow();
    await shoot(tester, '38-jetzt-gross', const NowScreen(), textScale: 1.6);
  });

  testWidgets('39 aufgaben — grosse Schrift, werkbank hell', (tester) async {
    await seedNow();
    await shoot(tester, '39-aufgaben-gross-werkbank', const TasksScreen(),
        brightness: Brightness.light,
        scheme: AxiomScheme.workbench,
        textScale: 1.6);
  });
}

