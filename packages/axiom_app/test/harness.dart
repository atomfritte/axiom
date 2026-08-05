/// Testgeruest: echte Engine, echtes Regelwerk, In-Memory-Datenbank.
///
/// Bewusst keine Mocks der Engine — die Tests pruefen das Zusammenspiel,
/// das in Produktion laeuft.
library;

import 'dart:io';

import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
import 'package:axiom_app/design/theme.dart';
import 'package:axiom_app/state/providers.dart';
import 'package:axiom_app/state/runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Laedt das ausgelieferte Regelwerk aus assets/rules/.
Map<String, String> loadRuleAssets() {
  final dir = Directory('assets/rules');
  if (!dir.existsSync()) return {};
  return {
    for (final f in dir.listSync().whereType<File>())
      f.uri.pathSegments.last: f.readAsStringSync(),
  };
}

final class TestHarness {
  final SqliteEventStore store;
  final FakeClock clock;
  final AxiomRuntime runtime;

  TestHarness._(this.store, this.clock, this.runtime);

  factory TestHarness.create({DateTime? at}) {
    final clock = FakeClock(at ?? DateTime(2026, 8, 3, 10, 30));
    final store = SqliteEventStore.inMemory(clock: clock);
    final sources = loadRuleAssets();
    final parsed = YamlRuleSource(sources).parse();

    // Sprache festnageln, nicht der Umgebung ueberlassen.
    //
    // Seit die App beim ersten Start die Geraetesprache uebernimmt, haengt
    // die Oberflaeche im Test an der Systemsprache des Rechners — dieselbe
    // Testdatei erzeugt dann auf einem deutschen und einem englischen
    // Rechner verschiedene Referenzbilder. Ein Test, dessen Ergebnis von
    // der Maschine abhaengt, prueft nichts.
    store.setSetting('language', 'de');

    return TestHarness._(
      store,
      clock,
      AxiomRuntime(
        store: store,
        clock: clock,
        rules: parsed.rules,
        limits: sources.containsKey('limits.yaml')
            ? parseGlobalLimits(sources['limits.yaml']!)
            : const GlobalLimits(),
        weights: sources.containsKey('weights.yaml')
            ? parseWeights(sources['weights.yaml']!)
            : const Weights(),
        ruleIssues: parsed.issues,
      ),
    );
  }

  void dispose() => store.close();

  /// Umgeht das Onboarding fuer Tests, die die Hauptansicht pruefen.
  void completeOnboarding() {
    runtime.markOnboardingDone();
    runtime.startBaseline();
  }

  /// Legt die Reizkanaele sofort an.
  ///
  /// In der App passiert das asynchron beim ersten Oeffnen; im Test wuerde
  /// das je nach Pump-Zeitpunkt mal greifen und mal nicht.
  Future<void> seedChannels() => store.seedChannelsIfEmpty();

  ProviderScope wrap(Widget child, {Brightness brightness = Brightness.dark}) =>
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(clock),
          runtimeProvider.overrideWith((ref) async => runtime),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAxiomTheme(brightness: brightness),
          home: child,
        ),
      );
}

/// Baut den Widget-Baum ab und laesst laufende Timer auslaufen.
///
/// Noetig fuer Screens mit periodischem Timer: Sonst greift der Timer nach
/// dem Testende auf die bereits geschlossene Datenbank zu.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 50));
}

/// Rendert ein Widget in Telefongroesse (Galaxy S25 Ultra, logisch).
Future<void> pumpPhone(
  WidgetTester tester,
  Widget widget, {
  Size size = const Size(412, 915),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle(const Duration(milliseconds: 600));
}

/// Rendert ein Widget in vorgegebener Groesse und Schriftskalierung.
///
/// Die Skalierung geht ueber `MediaQuery`, nicht ueber das Theme: Genau so
/// kommt sie in der App an (`app.dart` verrechnet Systemgroesse und eigene
/// Einstellung zu einem `TextScaler`), und nur so faellt auf, was bei
/// 2,4-fach bricht.
Future<void> pumpScaled(
  WidgetTester tester,
  Widget widget, {
  Size size = const Size(412, 915),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: widget,
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 600));
}
