/// AxiomRuntime — verbindet Core-Engine und Persistenz.
///
/// Der komplette Auswertungszyklus aus docs/02-ARCHITEKTUR.md §4:
///   ingest -> derive -> evaluate -> resolve -> emit -> feedback
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
import 'package:flutter/foundation.dart';

/// Ergebnis eines Auswertungszyklus.
@immutable
final class AxiomSnapshot {
  final StateVector state;
  final Map<String, List<Term>> breakdown;

  /// Die eine naechste Handlung. Null, wenn keine Regel gefeuert hat —
  /// das ist ein gueltiger und haeufiger Zustand, kein Fehler.
  final Decision? decision;

  /// Die Regel hinter [decision].
  final Rule? decisionRule;

  final List<Task> tasks;

  /// Verbrauchtes Meta-Work-Budget heute (M12).
  final Duration metaUsedToday;

  /// Warum Regeln nicht gefeuert haben — fuer den Systeminspektor.
  final List<SkippedRule> skipped;

  /// Anstehende Zeitanker (M3).
  final List<Anchor> anchors;

  /// Der naechste Schritt ueber alle Anker hinweg — die Zahl, die das
  /// staendige Nachrechnen im Kopf ersetzt [D4].
  final ({Anchor anchor, AnchorStep step})? nextStep;

  /// Aufgaben, die zerlegt werden sollten (M2).
  final List<AtomizeCandidate> atomizeCandidates;

  /// Laufende Fokus-Sitzung und das Urteil des Governors (M4).
  final FocusSession? focus;
  final FocusVerdict? focusVerdict;

  /// Reiz-Haushalt und Vorschlag (M5).
  final SensationBudget sensationBudget;
  final SensationChannel? suggestedChannel;

  /// Laufender Impuls-Abfang (M6).
  final InterceptRun? activeIntercept;

  /// Geltende Load-Stufe mit ihren Konsequenzen (M9).
  final LoadRegime regime;

  /// Soll auf professionelle Abklaerung hingewiesen werden? (R10)
  final bool suggestsReferral;

  /// Zeitpunkt dieser Auswertung, lokal.
  ///
  /// Alles Zeitabhaengige rechnet hiergegen, nicht gegen `DateTime.now()`:
  /// Sonst sortiert der Snapshot nach einer anderen Zeit, als die Engine
  /// ihn erzeugt hat.
  final DateTime at;

  const AxiomSnapshot({
    required this.at,
    required this.state,
    required this.breakdown,
    required this.tasks,
    required this.metaUsedToday,
    this.decision,
    this.decisionRule,
    this.skipped = const [],
    this.anchors = const [],
    this.nextStep,
    this.atomizeCandidates = const [],
    this.focus,
    this.focusVerdict,
    this.sensationBudget = const SensationBudget(),
    this.suggestedChannel,
    this.activeIntercept,
    this.regime = const LoadRegime(
      level: LoadLevel.l0,
      headline: 'Normalbetrieb',
      description: 'Die Kompensationslast liegt im gewohnten Bereich.',
    ),
    this.suggestsReferral = false,
  });

  /// Aufgaben, die bei aktueller Kapazitaet startbar sind.
  ///
  /// Im Erhaltungsmodus zusaetzlich nach oben gedeckelt: Was jetzt
  /// vorgeschlagen wird, muss auch bei knapper Reserve tragbar sein (M9).
  List<Task> get startable {
    final cap = regime.maxSuggestedEnergy;
    final ready = tasks
        .where((t) => t.isStartable(state.capacity))
        .where((t) => cap == null || t.activationEnergy <= cap)
        .toList()
      ..sort((a, b) => taskScore(b, at).compareTo(taskScore(a, at)));
    return ready;
  }

  /// Laeuft gerade ein Fokusblock?
  bool get isFocusing => focus != null;

  List<Task> get inbox =>
      tasks.where((t) => t.state == TaskState.inbox).toList();
}

/// Tagesbudget fuer Zeit *in* AXIOM. Erfassung zaehlt nicht mit.
const Duration kMetaBudget = Duration(minutes: 12);

final class AxiomRuntime {
  final SqliteEventStore store;
  final Clock clock;
  final List<Rule> rules;
  final GlobalLimits limits;
  final Weights weights;
  final List<RuleLoadIssue> ruleIssues;

  /// Sind die Formelgewichte an echten Daten geeicht?
  ///
  /// Solange nicht, markiert der Systeminspektor Regeln, die auf abgeleitete
  /// Werte pruefen — sie koennen danebenliegen, und das gehoert sichtbar (G2).
  final bool weightsCalibrated;

  late final StateDeriver _deriver = StateDeriver(weights: weights);
  late final RuleEngine _engine = RuleEngine(limits: limits);
  late final SignalAggregator _aggregator =
      SignalAggregator(store: store, clock: clock);
  static const _resolver = DecisionResolver();

  AxiomRuntime({
    required this.store,
    required this.clock,
    required this.rules,
    required this.limits,
    required this.weights,
    this.ruleIssues = const [],
    this.weightsCalibrated = false,
  });

  // ── 1. Ingest ─────────────────────────────────────────────────────────

  Future<Event> record(
    EventType type, {
    Map<String, Object?> payload = const {},
    EventSource source = EventSource.user,
  }) async {
    final event = Event(
      id: newUlid(clock.nowUtc()),
      at: clock.nowUtc(),
      type: type,
      source: source,
      payload: payload,
    );
    await store.append(event);
    return event;
  }

  /// Erfassung. Bewusst ohne Kategorie, ohne Rueckfrage, ohne Pflichtfeld —
  /// jede Rueckfrage im Erfassungsmoment kostet den Gedanken. [D9]
  Future<void> capture(String text, {String via = 'app'}) =>
      record(EventType.capture, payload: {'text': text, 'via': via});

  Future<void> checkIn({
    required int energy,
    required int focus,
    required int mood,
    required int stimNeed,
    int? compensation,
    int? recovery,
    String slot = 'manual',
  }) =>
      record(EventType.checkin, payload: {
        'energy': energy,
        'focus': focus,
        'mood': mood,
        'stim_need': stimNeed,
        'compensation': ?compensation,
        'recovery': ?recovery,
        'slot': slot,
      });

  // ── 2.–5. Derive, Evaluate, Resolve, Emit ─────────────────────────────

  Future<AxiomSnapshot> evaluate() async {
    final signals = await _aggregator.aggregate();
    final derived = _deriver.derive(signals, clock.nowUtc());
    final tasks = await store.tasks();
    final metaUsed = await store.usageToday(clock.nowLocal());

    final runtimeContext = await _buildRuntimeContext();
    final ctx = StateEvalContext(
      state: derived.vector,
      clock: clock,
      runtime: runtimeContext,
    );

    final result = _engine.evaluate(
      rules: rules,
      ctx: ctx,
      history: store.historyAt(clock.nowLocal()),
      nowLocal: clock.nowLocal(),
    );

    final snapshotId = newUlid(clock.nowUtc());
    final resolved = _resolver.resolve(
      fired: result.fired,
      at: clock.nowLocal(),
      stateSnapshotId: snapshotId,
      explain: (rule) => explainRule(rule, derived.vector),
      nextId: () => newUlid(clock.nowUtc()),
    );

    // SHADOW-Regeln protokollieren, ohne etwas anzuzeigen.
    for (final fired in result.fired.where((f) => f.rule.isShadow)) {
      await store.saveDecision(Decision(
        id: newUlid(clock.nowUtc()),
        at: clock.nowLocal(),
        ruleId: fired.rule.id,
        action: fired.rule.then,
        explanation: fired.rule.rationale,
        stateSnapshotId: snapshotId,
        suppressed: true,
      ));
    }

    if (resolved.winner != null) {
      await store.saveDecision(resolved.winner!);
      for (final s in resolved.suppressed) {
        await store.saveDecision(s);
      }
    }

    final rule = resolved.winner == null
        ? null
        : rules.where((r) => r.id == resolved.winner!.ruleId).firstOrNull;

    // ── Stufe 3: Fokus, Reiz, Impuls, Last ──────────────────────────────
    final now = clock.nowLocal();
    final nextStep = await nextAnchorStep();
    final regime = resolveRegime(derived.vector.loadLevel);

    final focus = await store.activeFocus();
    final focusVerdict = focus == null
        ? null
        : _governor.assess(
            session: focus,
            now: now,
            state: derived.vector,
            nextAnchorStep: nextStep,
            sinceBodyPrompt: _sinceBody(runtimeContext),
          );

    final budget = _ledger.compute(
      focusMinutesToday: await store.focusMinutesToday(now),
      slotsToday: await store.slotsSince(
        DateTime(now.year, now.month, now.day).toUtc(),
      ),
    );

    return AxiomSnapshot(
      at: now,
      state: derived.vector,
      breakdown: derived.breakdown,
      decision: resolved.winner,
      decisionRule: rule,
      tasks: tasks,
      metaUsedToday: metaUsed,
      skipped: result.skipped,
      anchors: await upcomingAnchors(),
      nextStep: nextStep,
      atomizeCandidates: await atomizeCandidates(derived.vector.capacity),
      focus: focus,
      focusVerdict: focusVerdict,
      sensationBudget: budget,
      suggestedChannel: _ledger.suggest(
        sensationNeed: derived.vector.sensationNeed,
        channels: await store.channels(),
        available: Duration(minutes: budget.availableMinutes.clamp(15, 120)),
      ),
      activeIntercept: await store.activeRun(now),
      regime: regime,
      suggestsReferral: shouldSuggestReferral(regime.level),
    );
  }

  /// Zeit seit der letzten Koerper-Quittierung, fuer den Focus Governor.
  static Duration? _sinceBody(RuntimeContext ctx) {
    final minutes = ctx.minutesSinceByEvent['body_prompt'];
    return minutes == null ? null : Duration(minutes: minutes);
  }

  Future<RuntimeContext> _buildRuntimeContext() async {
    final now = clock.nowUtc();
    final dayStart = DateTime(
      clock.nowLocal().year,
      clock.nowLocal().month,
      clock.nowLocal().day,
    ).toUtc();

    final minutesSince = <String, int>{};
    final countToday = <String, int>{};
    for (final type in EventType.values) {
      final last = await store.last(type);
      if (last != null) {
        minutesSince[_snake(type)] = now.difference(last.at).inMinutes;
      }
      countToday[_snake(type)] = await store.countSince(type, dayStart);
    }

    final focusStart = await store.last(EventType.focusStart);
    final focusEnd = await store.last(EventType.focusEnd);
    final slotEvent = await store.last(EventType.sensationSlot);
    final focusRunning = focusStart != null &&
        (focusEnd == null || focusEnd.at.isBefore(focusStart.at));
    final slotRunning = slotEvent != null &&
        now.difference(slotEvent.at) < const Duration(minutes: 45);

    return RuntimeContext(
      activeSlot: focusRunning
          ? 'focus'
          : slotRunning
              ? 'sensation'
              : 'none',
      minutesSinceByEvent: minutesSince,
      countTodayByEvent: countToday,
    );
  }

  /// Erzeugt die Begruendung: Regeltext plus die konkreten Zustandswerte,
  /// die sie ausgeloest haben. Ohne die Zahlen bleibt es eine Behauptung.
  String explainRule(Rule rule, StateVector state) {
    final referenced = rule.when.referencedVariables
        .where((v) => !v.startsWith('event:') && v != 'time_between')
        .map((v) => '$v ${state.numeric(v) ?? "–"}')
        .join(' · ');
    return referenced.isEmpty
        ? rule.rationale.trim()
        : '${rule.rationale.trim()}\n\nAusgeloest durch: $referenced';
  }

  // ── 6. Feedback ───────────────────────────────────────────────────────

  Future<void> respondTo(Decision decision, DecisionResponse response) async {
    await store.setDecisionResponse(decision.id, response);
    await record(
      EventType.decisionFeedback,
      payload: {'decision_id': decision.id, 'response': response.name},
    );
  }

  // ── Aufgaben ──────────────────────────────────────────────────────────

  Future<Task> createTask({
    required String title,
    required int activationEnergy,
    required int salience,
    required int stakes,
    DateTime? decayAt,
    String? parentId,
    TaskState state = TaskState.ready,
  }) async {
    final task = Task(
      id: newUlid(clock.nowUtc()),
      title: title,
      activationEnergy: activationEnergy,
      salience: salience,
      stakes: stakes,
      decayAt: decayAt,
      parentId: parentId,
      state: state,
    );
    await store.upsertTask(task);
    await record(EventType.taskCreated, payload: {
      'task_id': task.id,
      'title': title,
      'ae': activationEnergy,
      'salience': salience,
      'stakes': stakes,
      'state': state.name,
      if (decayAt != null) 'decay_at': decayAt.toUtc().toIso8601String(),
      'parent_id': ?parentId,
    });
    return task;
  }

  Future<void> completeTask(Task task) async {
    await store.upsertTask(task.copyWith(state: TaskState.done));
    await record(EventType.taskCompleted, payload: {'task_id': task.id});
  }

  Future<void> dropTask(Task task) async {
    await store.upsertTask(task.copyWith(state: TaskState.dropped));
    await record(EventType.taskAbandoned,
        payload: {'task_id': task.id, 'reason': 'manual'});
  }

  Future<void> startTask(Task task) async {
    await store.upsertTask(task.copyWith(state: TaskState.active));
    await record(EventType.taskStarted, payload: {'task_id': task.id});
  }

  // ── Zerlegen (M2) ─────────────────────────────────────────────────────

  static const _atomizer = Atomizer();

  /// Aufgaben, die zerlegt werden sollten. Die Oberfläche zeigt immer nur
  /// die erste — eine Liste von Zerlegungsaufträgen wäre selbst eine Hürde.
  Future<List<AtomizeCandidate>> atomizeCandidates(int capacity) async =>
      _atomizer.candidates(
        tasks: await store.tasks(),
        capacity: capacity,
        now: clock.nowLocal(),
        createdAt: await store.taskCreationTimes(),
      );

  /// Zerlegt eine Aufgabe in die vom Nutzer benannten Schritte.
  ///
  /// Das Elternteil wird blockiert, nicht gelöscht: Es bleibt als Klammer
  /// erhalten, verschwindet aber aus der Auswahl, damit es nicht doppelt
  /// erscheint.
  Future<List<Task>> atomize({
    required Task parent,
    required List<({String title, int energy})> steps,
  }) async {
    final children = _atomizer.split(
      parent: parent,
      steps: steps,
      nextId: () => newUlid(clock.nowUtc()),
    );
    for (final child in children) {
      await store.upsertTask(child);
    }
    await store.upsertTask(parent.copyWith(state: TaskState.blocked));
    await record(EventType.taskSplit, payload: {
      'parent_id': parent.id,
      'child_ids': children.map((c) => c.id).toList(),
    });
    return children;
  }

  // ── Zeitanker (M3) ────────────────────────────────────────────────────

  Future<Anchor> createAnchor({
    required String title,
    required DateTime arriveBy,
    Duration travel = Duration.zero,
    Duration prepare = kDefaultPrepare,
    Duration buffer = kDefaultBuffer,
    Duration contextSwitch = kDefaultContextSwitch,
    String? location,
    String source = 'manual',
    String? externalId,
  }) async {
    final anchor = Anchor(
      id: newUlid(clock.nowUtc()),
      title: title,
      arriveBy: arriveBy,
      travel: travel,
      prepare: prepare,
      buffer: buffer,
      contextSwitch: contextSwitch,
      location: location,
    );
    await store.upsertAnchor(anchor, source: source, externalId: externalId);
    return anchor;
  }

  Future<void> updateAnchor(Anchor anchor) => store.upsertAnchor(anchor);

  Future<void> dismissAnchor(String id) => store.dismissAnchor(id);

  /// Anker von jetzt bis morgen früh — mehr braucht die Tagesansicht nicht.
  Future<List<Anchor>> upcomingAnchors() async {
    final now = clock.nowLocal();
    return store.anchors(
      from: now.subtract(const Duration(hours: 2)),
      to: DateTime(now.year, now.month, now.day + 2),
    );
  }

  /// Der nächste Schritt über alle Anker hinweg.
  ///
  /// Das ist die Zahl, die aufs Widget und ins Always-On gehört: Sie ersetzt
  /// das permanente Nachrechnen im Kopf [D4].
  Future<({Anchor anchor, AnchorStep step})?> nextAnchorStep() async {
    final now = clock.nowLocal();
    ({Anchor anchor, AnchorStep step})? best;
    for (final anchor in await upcomingAnchors()) {
      final step = anchor.nextStep(now);
      if (step == null) continue;
      if (best == null || step.at.isBefore(best.step.at)) {
        best = (anchor: anchor, step: step);
      }
    }
    return best;
  }

  // ── Review (M11) ──────────────────────────────────────────────────────

  late final _reviewAggregator =
      ReviewAggregator(store: store, clock: clock);
  static const _reviewEngine = ReviewEngine();

  Future<({List<Metric> metrics, List<RuleVerdict> verdicts})> review(
    ReviewScope scope,
  ) async {
    final input = await _reviewAggregator.collect(
      scope,
      knownRuleIds: rules.map((r) => r.id).toList(),
    );
    return (
      metrics: _reviewEngine.metrics(input),
      verdicts: _reviewEngine.ruleVerdicts(input),
    );
  }

  Future<void> completeReview(ReviewScope scope, Duration spent) =>
      record(EventType.reviewCompleted, payload: {
        'scope': scope.name,
        'duration_min': spent.inMinutes,
      });

  DateTime? lastReview(ReviewScope scope) {
    final value = store.setting('last_review_${scope.name}');
    return value == null ? null : DateTime.tryParse(value);
  }

  void markReviewDone(ReviewScope scope) => store.setSetting(
      'last_review_${scope.name}', clock.nowUtc().toIso8601String());

  /// Ist ein Review fällig? Tag täglich, Woche sonntags, Monat zum Ersten.
  bool isReviewDue(ReviewScope scope) {
    final last = lastReview(scope);
    final now = clock.nowLocal();
    if (last == null) return scope == ReviewScope.day;
    final since = now.difference(last.toLocal());
    return switch (scope) {
      ReviewScope.day => since.inHours >= 20,
      ReviewScope.week => since.inDays >= 7,
      ReviewScope.month => since.inDays >= 30,
      ReviewScope.quarter => since.inDays >= 90,
    };
  }

  // ── Körper und Schlaf (M7, M8) ────────────────────────────────────────

  Future<void> acknowledgeBodyPrompt(String kind) =>
      record(EventType.bodyPrompt, payload: {'kind': kind, 'ack': true});

  Future<void> logSleep({
    required DateTime bedAt,
    required DateTime wakeAt,
    required int quality,
  }) {
    // Schlafschuld gegen sieben Stunden Soll. Der Wert ist eine Annahme und
    // wird nach der Baseline durch das persönliche Soll ersetzt.
    const targetMinutes = 7 * 60;
    final actual = wakeAt.difference(bedAt).inMinutes;
    return record(EventType.sleepWindow, payload: {
      'bed_at': bedAt.toUtc().toIso8601String(),
      'wake_at': wakeAt.toUtc().toIso8601String(),
      'quality': quality,
      'est_debt_min': (targetMinutes - actual).clamp(0, 600),
    });
  }

  Future<void> startWindDown() =>
      record(EventType.focusEnd, source: EventSource.rule, payload: {
        'actual_min': 0,
        'exit': 'winddown',
        'on_anchor': false,
      });

  // ── Fokus (M4) ────────────────────────────────────────────────────────

  static const _governor = FocusGovernor();

  Future<FocusSession> startFocus({
    String? taskId,
    String? taskTitle,
    Duration planned = const Duration(minutes: 50),
  }) async {
    final session = FocusSession(
      id: newUlid(clock.nowUtc()),
      startedAt: clock.nowLocal(),
      anchorTaskId: taskId,
      anchorTitle: taskTitle,
      planned: planned,
    );
    await store.startFocus(session);
    await record(EventType.focusStart, payload: {
      'anchor_task_id': ?taskId,
      'planned_min': planned.inMinutes,
    });
    return session;
  }

  /// Beendet den Fokus und sichert den Wiedereinstieg.
  ///
  /// Die Notiz ist der eigentliche Zweck des Ausstiegs: Ohne sie beginnt
  /// beim naechsten Mal das Laden des Kontexts von vorn [D11].
  Future<void> endFocus(
    FocusSession session, {
    String? breadcrumb,
    String exit = 'planned',
  }) async {
    final now = clock.nowLocal();
    await store.endFocus(session.id,
        at: now, breadcrumb: breadcrumb, exitKind: exit);
    await record(EventType.focusEnd, payload: {
      'actual_min': session.elapsed(now).inMinutes,
      'on_anchor': session.hasAnchor,
      'exit': exit,
      'breadcrumb': ?breadcrumb,
    });
  }

  Future<String?> lastBreadcrumb() => store.lastBreadcrumb();

  // ── Reiz-Haushalt (M5) ────────────────────────────────────────────────

  static const _ledger = SensationLedger();

  Future<List<SensationChannel>> channels() => store.channels();

  Future<void> saveChannel(SensationChannel channel) =>
      store.upsertChannel(channel);

  Future<void> deleteChannel(String id) => store.deleteChannel(id);

  /// Traegt einen Reiz-Slot ein.
  ///
  /// [planned] unterscheidet vorher eingeplant von hinterher protokolliert —
  /// genau darum geht es in Kennzahl K4. Ungeplant wird gezaehlt, nicht
  /// bestraft (G3).
  Future<void> logSlot({
    required SensationChannel channel,
    required Duration duration,
    required bool planned,
  }) =>
      record(EventType.sensationSlot, payload: {
        'channel': channel.id,
        'label': channel.label,
        'intensity': channel.intensity,
        'duration_min': duration.inMinutes,
        'planned': planned,
      });

  // ── Impuls-Abfang (M6) ────────────────────────────────────────────────

  static const _interceptor = Interceptor();

  Future<List<InterceptTrigger>> triggers() => store.triggers();

  Future<void> saveTrigger(InterceptTrigger trigger) =>
      store.upsertTrigger(trigger);

  Future<void> archiveTrigger(String id) => store.archiveTrigger(id);

  Future<InterceptRun> startIntercept(InterceptTrigger trigger) async {
    final run = _interceptor.start(
      trigger: trigger,
      now: clock.nowLocal(),
      id: newUlid(clock.nowUtc()),
    );
    await store.saveRun(run);
    await record(EventType.impulseIntercepted, payload: {
      'trigger_id': trigger.id,
      'outcome': 'pending',
      'cooldown_min': trigger.cooldown.inMinutes,
    });
    return run;
  }

  Future<void> resolveIntercept(
    InterceptRun run,
    InterceptOutcome outcome, {
    List<bool> answers = const [],
    String? note,
  }) async {
    await store.saveRun(InterceptRun(
      id: run.id,
      triggerId: run.triggerId,
      triggerLabel: run.triggerLabel,
      startedAt: run.startedAt,
      releasesAt: run.releasesAt,
      answers: answers,
      outcome: outcome,
      note: note,
    ));
    await record(EventType.impulseIntercepted, payload: {
      'trigger_id': run.triggerId,
      'outcome': outcome.name,
    });
  }

  String interceptWaitingText(InterceptRun run) =>
      _interceptor.waitingText(run, clock.nowLocal());

  Future<List<InterceptStats>> interceptStats() => store.interceptStats(
        since: clock.nowUtc().subtract(const Duration(days: 30)),
      );

  // ── Load Monitor (M9) ─────────────────────────────────────────────────

  static const _loadMonitor = LoadMonitor();

  /// Bestimmt die geltende Stufe und schreibt sie fort.
  ///
  /// Hoch geht es sofort, runter erst nach der Mindesthaltezeit: Ein
  /// einzelner guter Tag beendet keinen Erhaltungsmodus.
  LoadRegime resolveRegime(LoadLevel measured) {
    final now = clock.nowLocal();
    final stored = store.loadState();
    final effective = _loadMonitor.effectiveLevel(
      measured: measured,
      current: stored?.level,
      now: now,
      since: stored?.since,
    );
    if (stored == null || stored.level != effective) {
      store.setLoadState(effective, now);
    }
    return _loadMonitor.regimeFor(effective);
  }

  bool shouldSuggestReferral(LoadLevel level) => _loadMonitor.suggestsReferral(
        level: level,
        since: store.loadState()?.since,
        now: clock.nowLocal(),
      );

  // ── Meta-Guard (M12) ──────────────────────────────────────────────────

  Future<void> logScreenTime(String screen, Duration duration,
          {bool countsToBudget = true}) =>
      store.logUsage(screen, duration, countsToBudget: countsToBudget);

  /// Konfiguration ist gesperrt, wenn das Tagesbudget aufgebraucht ist.
  /// Nicht als Strafe — als Schutz vor der Meta-Work-Falle (D3).
  Future<bool> isConfigLocked() async =>
      (await store.usageToday(clock.nowLocal())) >= kMetaBudget;

  bool get onboardingDone => store.setting('onboarding_done') == 'true';
  void markOnboardingDone() => store.setSetting('onboarding_done', 'true');

  DateTime? get baselineStart {
    final value = store.setting('baseline_start');
    return value == null ? null : DateTime.tryParse(value);
  }

  void startBaseline() => store.setSetting(
      'baseline_start', clock.nowUtc().toIso8601String());

  /// Tag der Baseline-Phase, 1-basiert. Null, wenn nicht gestartet.
  int? get baselineDay {
    final start = baselineStart;
    if (start == null) return null;
    return clock.nowUtc().difference(start).inDays + 1;
  }

  static const _baselineTracker = BaselineTracker();

  /// Stand der Baseline — aus echten Daten, nicht nur aus dem Kalender.
  ///
  /// Zaehlt Messpunkte und Schlafnaechte seit dem Start, nicht insgesamt:
  /// Was vor der Baseline lag, gehoert nicht in ihre Auswertung.
  Future<BaselineProgress> baselineProgress() async {
    final start = baselineStart;
    if (start == null) {
      return _baselineTracker.evaluate(
        startedAt: null,
        now: clock.nowUtc(),
        checkins: 0,
        sleepNights: 0,
        calibrated: weightsCalibrated,
      );
    }
    return _baselineTracker.evaluate(
      startedAt: start,
      now: clock.nowUtc(),
      checkins: await store.countSince(EventType.checkin, start),
      sleepNights: await store.countSince(EventType.sleepWindow, start),
      calibrated: weightsCalibrated,
    );
  }

  static String _snake(EventType type) {
    final name = type.name;
    return name.replaceAllMapped(
      RegExp('[A-Z]'),
      (m) => '_${m.group(0)!.toLowerCase()}',
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
