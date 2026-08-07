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

/// Wo die gespiegelten Regel-Assets liegen. `dart run tools/bin/sync_rules.dart`
/// kopiert sie aus `rules/` hierher.
const _ruleAssetPrefix = 'assets/rules/';

/// Das ausgelieferte Regelwerk und was dabei nicht ging.
final class BundledRules {
  /// Dateiname (ohne Pfad) auf Inhalt.
  final Map<String, String> sources;

  /// Was nicht geladen werden konnte. Landet in `AxiomRuntime.ruleIssues`
  /// und damit sichtbar im Systeminspektor.
  final List<RuleLoadIssue> issues;

  const BundledRules(this.sources, this.issues);
}

/// Liest alle Regel-Assets aus dem Asset-Manifest.
///
/// **Aus dem Manifest und nicht aus einer Liste im Quelltext.** Vorher stand
/// hier eine feste Liste von fünf Dateinamen. Eine neue Regeldatei wurde
/// vom Validator geprüft, von `sync_rules.dart` kopiert und vom Build ins
/// Paket genommen — und danach nie geladen, weil die Liste sie nicht kannte.
/// Alle Tests blieben grün: Sie lesen `rules/`, die App liest das Bundle.
/// Eine Regel, die es gibt und die nie feuert, ist genau das, was CLAUDE.md
/// „schlimmer als ein Absturz" nennt.
///
/// Dasselbe gilt für den Fehlerfall: Ein Asset, das sich nicht lesen lässt,
/// wurde stumm übersprungen. Jetzt steht es als [RuleLoadIssue] im
/// Systeminspektor — sichtbar unfertig statt still verschwunden.
///
/// [bundle] ist für Tests da; in der App ist es immer der `rootBundle`.
Future<BundledRules> loadBundledRules([AssetBundle? bundle]) async {
  final from = bundle ?? rootBundle;
  final sources = <String, String>{};
  final issues = <RuleLoadIssue>[];

  final List<String> assets;
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(from);
    // Sortiert, damit die Overlay-Reihenfolge nicht davon abhängt, in
    // welcher Reihenfolge der Build die Assets aufgeschrieben hat.
    assets = manifest
        .listAssets()
        .where((a) => a.startsWith(_ruleAssetPrefix) && a.endsWith('.yaml'))
        .toList()
      ..sort();
  } on Object catch (e) {
    return BundledRules(
      const {},
      [RuleLoadIssue(_ruleAssetPrefix, '-', 'Asset-Verzeichnis nicht lesbar: $e')],
    );
  }

  if (assets.isEmpty) {
    issues.add(RuleLoadIssue(
      _ruleAssetPrefix,
      '-',
      'Kein Regelwerk im Paket. sync_rules.dart überträgt rules/ hierher.',
    ));
  }

  for (final asset in assets) {
    try {
      sources[asset.split('/').last] = await from.loadString(asset);
    } on Object catch (e) {
      issues.add(RuleLoadIssue(asset, '-', 'Asset nicht lesbar: $e'));
    }
  }

  return BundledRules(sources, issues);
}

final clockProvider = Provider<Clock>((ref) => const SystemClock());

/// Wann die Datenbank zuletzt neu angelegt werden musste, als ISO-Zeit.
///
/// Steht in den Einstellungen der *neuen* Datenbank — die alte ist zu dem
/// Zeitpunkt weg. Der Systeminspektor zeigt es an; niemand soll es daran
/// merken, dass Aufgaben fehlen.
const kDatabaseResetSetting = 'db_reset_at';

/// Ob die Datei ohne Schluessel lesbar waere.
///
/// Eine unverschluesselte SQLite-Datei beginnt mit `SQLite format 3\0`. Das
/// steht so im Dateiformat und gilt unabhaengig davon, welche Bibliothek
/// gerade eingebunden ist; `SqliteEventStore.isEncrypted` fragt dieselbe
/// Kennung ab, braucht dafuer aber eine offene Verbindung — und genau die
/// gibt es an der Stelle, an der das hier gebraucht wird, nicht mehr.
bool _isPlainSqlite(String path) {
  const header = <int>[
    0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66, //
    0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00, // "SQLite format 3\0"
  ];
  final file = File(path);
  if (!file.existsSync()) return false;
  final handle = file.openSync();
  try {
    final head = handle.readSync(header.length);
    if (head.length < header.length) return false;
    for (var i = 0; i < header.length; i++) {
      if (head[i] != header[i]) return false;
    }
    return true;
  } on FileSystemException {
    return false;
  } finally {
    handle.closeSync();
  }
}

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
/// **Und warum hier trotzdem fast nie geloescht wird.** Eine Datei, die mit
/// `SQLite format 3\0` beginnt, ist ohne Schluessel vollstaendig lesbar. Sie
/// wegzuwerfen, weil ein *Schluessel* nicht passt, war der teuerste Fehler
/// dieses Projekts: Ein einziger Fehlschlag des Keystore genuegte, damit die
/// App eine Klartextdatenbank anlegte — und der naechste Start warf sie weg,
/// weil inzwischen ein Schluessel da war. Der Fall wird deshalb erkannt und
/// unverschluesselt geoeffnet. Sichtbar unverschluesselt (*System → Daten*)
/// ist besser als sauber geloescht.
///
/// Geloescht wird nur noch, was wirklich nicht mehr zu lesen ist: eine
/// verschluesselte Datei, deren Schluessel nicht mehr passt — nach
/// geloeschten App-Daten, nach einem zurueckgespielten Backup, beim
/// Geraetewechsel.
///
/// Oeffentlich, weil ein Test genau diesen Weg fahren koennen muss.
SqliteEventStore openAxiomDatabase(String path, Clock clock, String? key) {
  try {
    return SqliteEventStore.open(path, clock: clock, encryptionKey: key);
  } on DatabaseUnreadable {
    if (key != null && _isPlainSqlite(path)) {
      // Der Schluessel ist neu, die Datei ist aelter als er. Nichts ist
      // verloren — sie wird ohne Schluessel geoeffnet und bleibt es, bis
      // jemand sie bewusst umschluesselt.
      try {
        return SqliteEventStore.open(path, clock: clock);
      } on DatabaseUnreadable {
        // Auch ohne Schluessel nicht zu lesen. Dann lag es nicht an ihm,
        // und es bleibt beim dokumentierten Neuanfang.
      }
    }
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

/// Die Datenbank. Genau einmal geoeffnet, fuer die Lebensdauer der App.
///
/// **Warum sie nicht in [runtimeProvider] liegt.** Dort lag sie, und dort
/// wurde sie bei jedem `ref.invalidate(runtimeProvider)` geschlossen — nach
/// jedem gespeicherten Regeleditor-Eintrag und nach jeder Aenderung im
/// Expertenmodus. Riverpod gibt waehrend des Neuaufbaus aber weiterhin die
/// *alte* Laufzeit heraus; wer in diesem Fenster etwas las (die Weiche in
/// `app.dart`, die vier Anzeige-Einstellungen unten), traf auf eine
/// geschlossene Datenbank: `StateError`, und statt der App stand fuer einige
/// hundert Millisekunden ein Fehlerbildschirm da.
///
/// Getrennt gehalten loest sich das an der Wurzel statt an fuenf Stellen:
/// Die Verbindung ueberlebt jedes Neuladen des Regelwerks, weil sie mit ihm
/// nichts zu tun hat.
final storeProvider = FutureProvider<SqliteEventStore>((ref) async {
  final clock = ref.watch(clockProvider);

  final key = await AndroidBridge.databaseKey();
  if (key.state == DatabaseKeyState.unavailable) {
    // Nicht oeffnen, nicht anlegen, nicht loeschen. Der Startbildschirm
    // sagt, was los ist (G1: ein Bildschirm ist teuer, Datenverlust
    // teurer; G2: der Grund steht dabei).
    throw const DatabaseKeyUnavailable();
  }

  final dir = await getApplicationSupportDirectory();
  final dbPath = '${dir.path}${Platform.pathSeparator}axiom.db';
  final store = openAxiomDatabase(dbPath, clock, key.key);
  ref.onDispose(store.close);
  return store;
});

/// Baut die Laufzeit auf: Regelwerk laden, Engine an die Datenbank binden.
final runtimeProvider = FutureProvider<AxiomRuntime>((ref) async {
  final clock = ref.watch(clockProvider);
  final store = await ref.watch(storeProvider.future);

  final bundled = await loadBundledRules();
  final sources = Map<String, String>.of(bundled.sources);

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
    // Zuerst, was gar nicht erst geladen werden konnte, dann was sich nicht
    // uebersetzen liess. Beides gehoert in denselben Kasten im
    // Systeminspektor — sonst faellt genau der Fall durch, der niemandem
    // auffaellt.
    ruleIssues: [...bundled.issues, ...parsed.issues],
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
  // Die Definition von „unsortiert" steht in der Laufzeit, nicht hier: Der
  // Server braucht dieselbe, und zwei Fassungen davon waren schon einmal
  // eine zu viel.
  return runtime.unsortedCaptures();
});

// ── Aufgabenbestand ─────────────────────────────────────────────────────

/// Schluessel des einen Schalters, den der Aufgabenschirm hat.
const kShowDoneTasksSetting = 'tasks_show_done';

/// Ob der Aufgabenschirm die erledigten mitzeigt. **Vorgabe: aus.**
///
/// **Warum sie voreingestellt wegbleiben.** Erledigtes stand als eigener
/// Abschnitt unter dem Bestand — bis zu zwanzig durchgestrichene Zeilen, an
/// denen der Blick jedes Mal vorbeimuss, um das Offene zu finden. Was getan
/// ist, verlangt nichts mehr; es kostet aber Suchzeit, und Suchzeit ist bei
/// diesem Profil die teuerste Waehrung (D9).
///
/// **Warum es trotzdem einen Schalter gibt und nicht bloss ein Weglassen.**
/// Wer seinen Bestand nicht vollstaendig einsehen kann, fuehrt daneben eine
/// zweite Liste im Kopf. „Habe ich das schon abgehakt?" muss beantwortbar
/// bleiben, sonst wandert die Frage zurueck in den Kopf — genau das, was
/// AXIOM auslagern soll (G1, D9).
///
/// **Warum genau einer.** Ein Ansichtswechsel mit Zeitraum, Sortierung und
/// Zustandsfilter waere Meta-Work mit Aussicht (D3). Ein einziger Schalter
/// an der Stelle, an der die Liste steht, ist die kleinste Antwort, die die
/// Frage beantwortet.
///
/// **Warum er in der Einstellungstabelle liegt.** Eine Einstellung, die man
/// bei jedem Oeffnen neu setzt, ist keine. Derselbe Weg wie Sprache,
/// Helligkeit und Textgroesse — kein zweiter Speicherort fuer denselben
/// Zweck.
final class ShowDoneTasks extends Notifier<bool> {
  @override
  bool build() {
    final runtime = ref.watch(runtimeProvider).value;
    // Alles ausser einem ausdruecklichen „true" heisst aus — auch der Fall,
    // in dem noch nie jemand etwas gesetzt hat.
    return runtime?.store.setting(kShowDoneTasksSetting) == 'true';
  }

  Future<void> set({required bool shown}) async {
    final runtime = await ref.read(runtimeProvider.future);
    runtime.store.setSetting(kShowDoneTasksSetting, shown ? 'true' : 'false');
    state = shown;
  }

  Future<void> toggle() => set(shown: !state);
}

final showDoneTasksProvider =
    NotifierProvider<ShowDoneTasks, bool>(ShowDoneTasks.new);

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
