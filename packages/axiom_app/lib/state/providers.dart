/// Riverpod-Verdrahtung.
library;

import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'dart:io';

import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../design/tokens.dart';
import '../i18n/i18n.dart';
import '../platform/android_bridge.dart';
import '../platform/health_sync.dart';
import '../server/expert_server.dart';
import '../platform/system_sync.dart';
import 'runtime.dart';

/// Regelwerk-Assets. Werden von `dart run tools/bin/sync_rules.dart`
/// aus rules/ hierher gespiegelt.
const _ruleAssets = <String>[
  'assets/rules/limits.yaml',
  'assets/rules/weights.yaml',
  'assets/rules/s1-baseline.yaml',
  'assets/rules/s2-live.yaml',
  'assets/rules/s3-regulation.yaml',
];

final clockProvider = Provider<Clock>((ref) => const SystemClock());

/// Wann die Datenbank zuletzt neu angelegt werden musste, als ISO-Zeit.
///
/// Steht in den Einstellungen der *neuen* Datenbank — die alte ist zu dem
/// Zeitpunkt weg. Der Systeminspektor zeigt es an; niemand soll es daran
/// merken, dass Aufgaben fehlen.
const kDatabaseResetSetting = 'db_reset_at';

/// Oeffnet die Datenbank, notfalls neu.
///
/// **Warum hier ueberhaupt geloescht wird.** Ist die Datei unlesbar, ist sie
/// unwiederbringlich: Ohne passenden Schluessel gibt es kein Verfahren, das
/// den Inhalt zurueckholt. Bleiben koennte sie trotzdem — dann startet die App
/// nie wieder, bis jemand von Hand eingreift. Fuer eine App, die
/// Selbstregulation stuetzen soll, ist ein Start ohne Bestand der deutlich
/// kleinere Schaden als gar kein Start.
///
/// Passiert ist es trotzdem, und deshalb wird es festgehalten statt
/// verschwiegen ([kDatabaseResetSetting]). Eine App, die kommentarlos leer
/// dasteht, laesst einen an sich selbst zweifeln — genau die Wirkung, die
/// dieses Projekt vermeiden will.
///
/// Der Fall tritt ein bei einer unverschluesselten Datei aus einer frueheren
/// Fassung, nach geloeschten App-Daten, nach einem zurueckgespielten Backup
/// und beim Geraetewechsel.
SqliteEventStore _openDatabase(String path, Clock clock, String? key) {
  try {
    return SqliteEventStore.open(path, clock: clock, encryptionKey: key);
  } on DatabaseUnreadable {
    // WAL und Shared-Memory muessen mit weg. Bleiben sie liegen, findet
    // SQLite eine Sitzung zu einer Datei vor, die es nicht mehr gibt.
    for (final suffix in ['', '-wal', '-shm']) {
      final file = File('$path$suffix');
      if (file.existsSync()) file.deleteSync();
    }
    final store = SqliteEventStore.open(path, clock: clock, encryptionKey: key);
    store.setSetting(
      kDatabaseResetSetting,
      clock.nowUtc().toIso8601String(),
    );
    return store;
  }
}

/// Baut die Laufzeit auf: Datenbank oeffnen, Regelwerk laden, Engine binden.
final runtimeProvider = FutureProvider<AxiomRuntime>((ref) async {
  final clock = ref.watch(clockProvider);

  final dir = await getApplicationSupportDirectory();
  final dbPath = '${dir.path}${Platform.pathSeparator}axiom.db';
  final store = _openDatabase(dbPath, clock, await AndroidBridge.databaseKey());
  ref.onDispose(store.close);

  final sources = <String, String>{};
  for (final asset in _ruleAssets) {
    try {
      sources[asset.split('/').last] = await rootBundle.loadString(asset);
    } on Object {
      // Fehlendes Asset ist ein Konfigurationsfehler, aber kein Grund,
      // die App nicht zu starten — der Systeminspektor zeigt es an.
    }
  }

  // Im Geraet bearbeitete Regeln kommen zuletzt: gleiche ID ersetzt die
  // mitgelieferte Fassung, neue ID kommt dazu — dieselbe Overlay-Semantik
  // wie rules/personal. Regeln in der Schattenzeit werden dabei auf
  // log_only gesetzt; sie laufen mit, sprechen aber nicht.
  final overlay = store.overrideDocument(clock.nowLocal());
  if (overlay.isNotEmpty) sources['im Gerät bearbeitet'] = overlay;

  final parsed = YamlRuleSource(sources).parse();
  final limits = sources.containsKey('limits.yaml')
      ? parseGlobalLimits(sources['limits.yaml']!)
      : const GlobalLimits();
  final weights = sources.containsKey('weights.yaml')
      ? parseWeights(sources['weights.yaml']!)
      : const Weights();

  final runtime = AxiomRuntime(
    store: store,
    clock: clock,
    rules: parsed.rules,
    limits: limits,
    weights: weights,
    ruleIssues: parsed.issues,
    weightsCalibrated: !(sources['weights.yaml'] ?? '')
        .contains('status: uncalibrated'),
  );

  // Schlaf und Bewegung nachziehen, ohne den Start aufzuhalten. Ohne
  // Freigabe passiert nichts; mit Freigabe sind es wenige Datensaetze.
  // Erst wenn wirklich etwas Neues dazukam, wird neu ausgewertet — sonst
  // liefe bei jedem Start eine ueberfluessige Runde.
  unawaited(HealthSync.import(runtime).then((result) {
    if (result.imported > 0) ref.read(refreshTickProvider.notifier).bump();
  }));

  return runtime;
});

/// Verfuegbarkeit von Health Connect. Wird bei jeder Anzeige neu geholt:
/// Freigaben koennen jederzeit einzeln entzogen werden (R8).
final healthAvailabilityProvider =
    FutureProvider<HealthAvailability>((ref) async {
  ref.watch(refreshTickProvider);
  return HealthSync.availability();
});

/// Erhoehen loest eine Neuauswertung aus.
final class RefreshTick extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state = state + 1;
}

final refreshTickProvider =
    NotifierProvider<RefreshTick, int>(RefreshTick.new);

/// Der aktuelle Auswertungszyklus.
final snapshotProvider = FutureProvider<AxiomSnapshot>((ref) async {
  ref.watch(refreshTickProvider);
  // Die Sprache gehoert hierher, weil die Begruendung im Snapshot steckt:
  // Ein Sprachwechsel muss den Zyklus neu rechnen, sonst bleibt die alte
  // Begruendung stehen.
  final language = ref.watch(languageProvider);
  final runtime = await ref.watch(runtimeProvider.future);
  final snapshot = await runtime.evaluate(language: language);
  // Zustand nach aussen spiegeln: Widget, Always-On, Geraeteautomation.
  // Die Sprache muss mit: Was auf dem Sperrbildschirm steht, darf nicht in
  // einer anderen Sprache stehen als der Screen daneben.
  unawaited(SystemSync.publish(snapshot, language: language));
  return snapshot;
});

/// Loest eine Neuauswertung aus.
void refreshAxiom(WidgetRef ref) =>
    ref.read(refreshTickProvider.notifier).bump();

/// Erfasste, noch nicht triagierte Notizen (M1 -> M2).
final inboxProvider = FutureProvider<List<Event>>((ref) async {
  ref.watch(refreshTickProvider);
  final runtime = await ref.watch(runtimeProvider.future);
  final captures = await runtime.store.query(types: {EventType.capture});
  final triaged = await runtime.store.query(types: {EventType.taskCreated});
  final done = triaged
      .map((e) => e.payload['from_capture'] as String?)
      .whereType<String>()
      .toSet();
  final dismissed = (await runtime.store.query(types: {EventType.taskAbandoned}))
      .map((e) => e.payload['from_capture'] as String?)
      .whereType<String>()
      .toSet();
  return captures
      .where((e) => !done.contains(e.id) && !dismissed.contains(e.id))
      .toList()
      .reversed
      .toList();
});

/// Aktuelle lokale Zeit — immer ueber den Clock-Port.
///
/// Die Oberflaeche darf `DateTime.now()` nicht direkt aufrufen: Sonst
/// rechnet sie mit einer anderen Zeit als die Engine, und in Tests zeigt
/// sie Schritte als vergangen an, die noch bevorstehen.
///
/// **Warum das tickt.** Vorher aktualisierte sich dieser Wert nur, wenn
/// `refreshTickProvider` hochzaehlte — also bei einer Nutzeraktion. Damit
/// stand jede Zeitanzeige still: Die Wartezeit der Bremse lief auf dem
/// Bildschirm nie ab, die Fokusuhr blieb auf der Minute stehen, in der man
/// hingesehen hatte, und der Countdown zum naechsten Zeitanker zaehlte
/// nicht herunter. Eine Uhr, die nicht laeuft, ist schlimmer als keine:
/// Man glaubt ihr.
///
/// Sekundentakt, weil die Bremse Sekunden anzeigt. `autoDispose`, damit der
/// Takt stehenbleibt, sobald ihn niemand mehr ansieht.
final nowProvider = Provider.autoDispose<DateTime>((ref) {
  ref.watch(refreshTickProvider);
  final clock = ref.watch(clockProvider);

  // In Tests laeuft eine FakeClock. Ein echter Timer wuerde dort nur
  // Nachlaufzeit erzeugen, ohne dass sich der Wert je aendert.
  if (clock is SystemClock) {
    final timer = Timer.periodic(const Duration(seconds: 1), (_) {
      ref.invalidateSelf();
    });
    ref.onDispose(timer.cancel);
  }

  return clock.nowLocal();
});

/// Kennzahlen und Regelurteile fuer einen Review-Umfang.
final reviewProvider = FutureProvider.family<
    ({List<Metric> metrics, List<RuleVerdict> verdicts}),
    ReviewScope>((ref, scope) async {
  ref.watch(refreshTickProvider);
  final runtime = await ref.watch(runtimeProvider.future);
  return runtime.review(scope);
});

/// Faellige Reviews. Die Hauptansicht bietet sie an, ohne zu draengen.
final dueReviewProvider = FutureProvider<ReviewScope?>((ref) async {
  ref.watch(refreshTickProvider);
  final runtime = await ref.watch(runtimeProvider.future);
  // Groesster faelliger Umfang gewinnt: Wer den Monat macht, hat den Tag mit.
  for (final scope in ReviewScope.values.reversed) {
    if (runtime.isReviewDue(scope)) return scope;
  }
  return null;
});

/// Stand der Baseline — Zeit UND Daten.
final baselineProvider = FutureProvider<BaselineProgress>((ref) async {
  ref.watch(refreshTickProvider);
  final runtime = await ref.watch(runtimeProvider.future);
  return runtime.baselineProgress();
});

/// Reizkanaele (M5).
final channelsProvider = FutureProvider<List<SensationChannel>>((ref) async {
  ref.watch(refreshTickProvider);
  final runtime = await ref.watch(runtimeProvider.future);
  await runtime.store.seedChannelsIfEmpty();
  return runtime.channels();
});

/// Impuls-Trigger (M6).
final triggersProvider = FutureProvider<List<InterceptTrigger>>((ref) async {
  ref.watch(refreshTickProvider);
  final runtime = await ref.watch(runtimeProvider.future);
  return runtime.triggers();
});

final interceptStatsProvider =
    FutureProvider<List<InterceptStats>>((ref) async {
  ref.watch(refreshTickProvider);
  final runtime = await ref.watch(runtimeProvider.future);
  return runtime.interceptStats();
});

/// Wiedereinstiegsnotiz der letzten Fokus-Sitzung (M4, D11).
final breadcrumbProvider = FutureProvider<String?>((ref) async {
  ref.watch(refreshTickProvider);
  final runtime = await ref.watch(runtimeProvider.future);
  return runtime.lastBreadcrumb();
});

// ── Stufe 4 ─────────────────────────────────────────────────────────────

/// Vorfaelle der letzten 30 Tage (M10).
final incidentsProvider = FutureProvider<List<SignalIncident>>((ref) async {
  ref.watch(refreshTickProvider);
  final runtime = await ref.watch(runtimeProvider.future);
  return runtime.incidents();
});

/// Vorfaelle, deren Nachbetrachtung jetzt sinnvoll ist.
final pendingPostMortemsProvider =
    FutureProvider<List<SignalIncident>>((ref) async {
  ref.watch(refreshTickProvider);
  final runtime = await ref.watch(runtimeProvider.future);
  return runtime.awaitingPostMortem();
});

final incidentPatternsProvider =
    FutureProvider<Map<TriggerClass, int>>((ref) async {
  ref.watch(refreshTickProvider);
  final runtime = await ref.watch(runtimeProvider.future);
  return runtime.incidentPatterns();
});

/// Um wie viel niedriger ein Vorfall im Rueckblick ausfaellt.
final hindsightProvider = FutureProvider<double?>((ref) async {
  ref.watch(refreshTickProvider);
  final runtime = await ref.watch(runtimeProvider.future);
  return runtime.hindsightDelta();
});

/// Wirkfenster (M13, opt-in).
final medStateProvider = FutureProvider<MedWindowState>((ref) async {
  ref.watch(refreshTickProvider);
  final runtime = await ref.watch(runtimeProvider.future);
  return runtime.medState();
});

final medEntriesProvider = FutureProvider<List<MedEntry>>((ref) async {
  ref.watch(refreshTickProvider);
  final runtime = await ref.watch(runtimeProvider.future);
  return runtime.medEnabled ? runtime.medEntries() : const [];
});

/// Regelstatistik der letzten 7 Tage fuer den Systeminspektor.
final ruleStatsProvider = FutureProvider<List<RuleStats>>((ref) async {
  ref.watch(refreshTickProvider);
  final runtime = await ref.watch(runtimeProvider.future);
  return runtime.store.ruleStats(
    since: runtime.clock.nowUtc().subtract(const Duration(days: 7)),
  );
});

// ── Expertenmodus (ADR-0005) ────────────────────────────────────────────

/// Der lokale Server. **Aus, bis er eingeschaltet wird.**
///
/// Kein Autostart, kein Weiterlaufen nach einem Neustart, kein
/// Wiederanschalten nach einem Absturz. Ein Port mit Gesundheitsdaten geht
/// nur auf, wenn jemand ihn aufmacht — und schliesst sich von selbst wieder.
final class ExpertMode extends Notifier<ExpertStatus> {
  ExpertServer? _server;

  @override
  ExpertStatus build() {
    ref.onDispose(() => _server?.stop());
    return ExpertStatus.off;
  }

  Future<void> start() async {
    _server ??= ExpertServer(
      resolveRuntime: () => ref.read(runtimeProvider.future),
      onChanged: () {
        // Was im Browser geaendert wird, muss auf dem Telefon ankommen.
        ref.invalidate(runtimeProvider);
        ref.read(refreshTickProvider.notifier).bump();
        _sync();
      },
    );
    state = await _server!.start();
    await AndroidBridge.startExpertNotice(address: state.address ?? '');
  }

  Future<void> stop() async {
    await _server?.stop();
    _server = null;
    state = ExpertStatus.off;
    await AndroidBridge.stopExpertNotice();
  }

  /// Uebernimmt den Zustand des Servers, wenn er sich selbst abgeschaltet hat
  /// — nach Leerlauf oder zu vielen Fehlversuchen.
  void _sync() {
    final running = _server?.isRunning ?? false;
    if (!running && state.running) {
      state = ExpertStatus.off;
      AndroidBridge.stopExpertNotice();
    } else if (running) {
      state = _server!.status;
    }
  }

  /// Fuer die Anzeige: der Server kann sich zwischen zwei Blicken selbst
  /// abgeschaltet haben.
  void refresh() => _sync();

  /// Freigeben oder ablehnen — die Antwort auf den Zahlenabgleich.
  void resolvePending({required bool approve}) {
    _server?.resolvePending(approve: approve);
    _sync();
  }
}

final expertModeProvider =
    NotifierProvider<ExpertMode, ExpertStatus>(ExpertMode.new);

/// Anzeigesprache. Deutsch ist die Quelle, Englisch die Uebersetzung.
///
/// Liegt in der Einstellungstabelle und nicht im Speicher: Eine Sprache, die
/// beim naechsten Start wieder umspringt, waere schlimmer als keine Auswahl.
final class LanguageChoice extends Notifier<AppLanguage> {
  @override
  AppLanguage build() {
    final runtime = ref.watch(runtimeProvider).value;
    final chosen = runtime?.language;
    // Eine getroffene Wahl gewinnt immer. Nur wenn noch nie eine getroffen
    // wurde, entscheidet das Geraet.
    //
    // Vorher stand hier fest Deutsch. Fuer ein Geraet, auf dem Englisch
    // eingestellt ist, hiess das: eine App in einer Sprache, die man nicht
    // liest — und die Umschaltung liegt hinter Menuepunkten, die man dafuer
    // erst lesen muesste. Wer die Systemsprache setzt, hat die Frage
    // bereits beantwortet.
    if (chosen != null && chosen.isNotEmpty) return AppLanguage.parse(chosen);
    return AppLanguage.fromLocale(PlatformDispatcher.instance.locale);
  }

  Future<void> set(AppLanguage language) async {
    final runtime = await ref.read(runtimeProvider.future);
    runtime.language = language.code;
    state = language;
  }
}

final languageProvider =
    NotifierProvider<LanguageChoice, AppLanguage>(LanguageChoice.new);

// ── Anzeige ─────────────────────────────────────────────────────────────
//
// Drei Einstellungen: Textgroesse, Helligkeit, Farbschema. Alle drei
// ueberleben den Neustart — eine Einstellung, die zurueckspringt, ist
// schlimmer als keine.

/// Helligkeit: 0 = System, 1 = dunkel, 2 = hell.
final class ThemeChoice extends Notifier<int> {
  @override
  int build() => ref.watch(runtimeProvider).value?.brightnessChoice ?? 0;

  Future<void> set(int mode) async {
    final runtime = await ref.read(runtimeProvider.future);
    runtime.brightnessChoice = mode;
    state = mode;
  }
}

final themeModeProvider = NotifierProvider<ThemeChoice, int>(ThemeChoice.new);

/// Textgroesse in vier Stufen.
final class TextSizeChoice extends Notifier<TextSize> {
  @override
  TextSize build() =>
      TextSize.parse(ref.watch(runtimeProvider).value?.textSizeName);

  Future<void> set(TextSize size) async {
    final runtime = await ref.read(runtimeProvider.future);
    runtime.textSizeName = size.name;
    state = size;
  }
}

final textSizeProvider =
    NotifierProvider<TextSizeChoice, TextSize>(TextSizeChoice.new);

/// Farbschema.
final class SchemeChoice extends Notifier<AxiomScheme> {
  @override
  AxiomScheme build() =>
      AxiomScheme.parse(ref.watch(runtimeProvider).value?.colorSchemeName);

  Future<void> set(AxiomScheme scheme) async {
    final runtime = await ref.read(runtimeProvider.future);
    runtime.colorSchemeName = scheme.name;
    state = scheme;
  }
}

final schemeProvider =
    NotifierProvider<SchemeChoice, AxiomScheme>(SchemeChoice.new);
