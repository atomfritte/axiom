/// Riverpod-Verdrahtung.
library;

import 'dart:async';
import 'dart:io';

import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

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

/// Baut die Laufzeit auf: Datenbank oeffnen, Regelwerk laden, Engine binden.
final runtimeProvider = FutureProvider<AxiomRuntime>((ref) async {
  final clock = ref.watch(clockProvider);

  final dir = await getApplicationSupportDirectory();
  final dbPath = '${dir.path}${Platform.pathSeparator}axiom.db';
  final store = SqliteEventStore.open(dbPath, clock: clock);
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

  final parsed = YamlRuleSource(sources).parse();
  final limits = sources.containsKey('limits.yaml')
      ? parseGlobalLimits(sources['limits.yaml']!)
      : const GlobalLimits();
  final weights = sources.containsKey('weights.yaml')
      ? parseWeights(sources['weights.yaml']!)
      : const Weights();

  return AxiomRuntime(
    store: store,
    clock: clock,
    rules: parsed.rules,
    limits: limits,
    weights: weights,
    ruleIssues: parsed.issues,
    weightsCalibrated: !(sources['weights.yaml'] ?? '')
        .contains('status: uncalibrated'),
  );
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
  final runtime = await ref.watch(runtimeProvider.future);
  final snapshot = await runtime.evaluate();
  // Zustand nach aussen spiegeln: Widget, Always-On, Geraeteautomation.
  unawaited(SystemSync.publish(snapshot));
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
final nowProvider = Provider<DateTime>((ref) {
  ref.watch(refreshTickProvider);
  return ref.watch(clockProvider).nowLocal();
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

/// Regelstatistik der letzten 7 Tage fuer den Systeminspektor.
final ruleStatsProvider = FutureProvider<List<RuleStats>>((ref) async {
  ref.watch(refreshTickProvider);
  final runtime = await ref.watch(runtimeProvider.future);
  return runtime.store.ruleStats(
    since: runtime.clock.nowUtc().subtract(const Duration(days: 7)),
  );
});

/// Helligkeit: 0 = System, 1 = dunkel, 2 = hell.
final class ThemeChoice extends Notifier<int> {
  @override
  int build() => 0;
  void set(int mode) => state = mode;
}

final themeModeProvider =
    NotifierProvider<ThemeChoice, int>(ThemeChoice.new);
