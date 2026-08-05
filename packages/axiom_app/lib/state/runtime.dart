/// AxiomRuntime — verbindet Core-Engine und Persistenz.
///
/// Der komplette Auswertungszyklus aus docs/02-ARCHITEKTUR.md §4:
///   ingest -> derive -> evaluate -> resolve -> emit -> feedback
library;
import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
import 'package:flutter/foundation.dart';
import '../design/tokens.dart';
import '../i18n/i18n.dart';
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

  /// Die Blocker-Beziehungen dieses Zyklus, einmal ausgewertet.
  ///
  /// Bewusst getrennt von [Task]: Ein Listenfeld an der Aufgabe muesste jede
  /// Abfrage mitladen, und der Graph waere dann n-mal zusammengesetzt statt
  /// einmal.
  final TaskLinkGraph links;

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

  /// Der gerade gesetzte Ort, oder null.
  ///
  /// Kein Geofence und keine Standortberechtigung — ein Name, den der Nutzer
  /// setzt oder eine Geraeteroutine schickt (`de.atomfritte.axiom.PLACE`). [D2]
  final String? place;

  /// Orte, die in diesem Bestand vorkommen — aus den Aufgaben und aus dem,
  /// was schon einmal gesetzt war. Die Liste ergibt sich aus dem Gebrauch;
  /// eine Ortsverwaltung gibt es bewusst nicht (D3).
  final List<String> knownPlaces;

  /// Die Aufgabe mit dem knappsten Vorlauf, samt Frist und Anlauf. [D4]
  final ({Task task, Duration untilDue, Duration runway})? deadlinePressure;
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
    this.links = TaskLinkGraph.empty,
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
    this.place,
    this.knownPlaces = const [],
    this.deadlinePressure,
  });
  /// Aufgaben, die bei aktueller Kapazitaet startbar sind.
  ///
  /// Im Erhaltungsmodus zusaetzlich nach oben gedeckelt: Was jetzt
  /// vorgeschlagen wird, muss auch bei knapper Reserve tragbar sein (M9).
  ///
  /// Und am gesetzten Ort: Eine Aufgabe, die woanders hingehoert, ist hier
  /// nicht startbar — sie vorzuschlagen hiesse, eine Handlung anzubieten, die
  /// nicht geht (G1). Ohne gesetzten Ort aendert sich nichts.
  /// Und nicht wartend: Eine Aufgabe mit offenem Blocker ist nicht startbar.
  /// Ein Vorschlag, den man nicht ausfuehren kann, ist keiner (G1).
  List<Task> get startable {
    final cap = regime.maxSuggestedEnergy;
    final ready = tasks
        .where((t) => t.isStartable(state.capacity, atPlace: place))
        .where((t) => cap == null || t.activationEnergy <= cap)
        .where((t) => !isWaiting(t.id))
        .toList()
      ..sort((a, b) => scoreOf(b).compareTo(scoreOf(a)));
    return ready;
  }

  /// Offene Aufgaben, die nur der Ort zurueckhaelt.
  ///
  /// Sie verschwinden nicht — sie stehen mit ihrem Ort da. Ein Bestand, aus
  /// dem etwas unbemerkt herausfaellt, wird nicht mehr geglaubt [D9].
  List<Task> get elsewhere => tasks
      .where((t) => t.state == TaskState.ready && !t.isHere(place))
      .toList()
    ..sort((a, b) => scoreOf(b).compareTo(scoreOf(a)));

  /// Offene Aufgaben, die auf einen Blocker warten.
  ///
  /// „Wartet" ist kein Zustand in [TaskState] — dort heisst `blocked` bereits
  /// „zerlegt". Es wird gerechnet, und deshalb loest sich das Warten von
  /// selbst, sobald der letzte Blocker erledigt ist.
  List<Task> get waiting => tasks
      .where((t) => t.state == TaskState.ready && isWaiting(t.id))
      .toList()
    ..sort((a, b) => scoreOf(b).compareTo(scoreOf(a)));

  /// Die **offenen** Blocker einer Aufgabe. Leer heisst: nichts haelt sie auf.
  List<String> blockersOf(String taskId) => links.blockersOf(taskId);

  /// Die offenen Aufgaben, die diese Aufgabe aufhaelt.
  List<String> blockedBy(String taskId) => links.blockedBy(taskId);

  bool isWaiting(String taskId) => links.isWaiting(taskId);

  /// Der Auswahl-Score dieser Aufgabe, samt Hebel.
  ///
  /// Eine Stelle, nicht drei: Die Aufgabenliste sortiert nach derselben
  /// Formel wie die Auswahl — „dieselbe Formel, kein zweiter Massstab".
  double scoreOf(Task task) =>
      taskScore(task, at, unblocks: links.unblocks(task.id));
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
  /// Ereignis mit eigenem Zeitpunkt — fuer Importe aus fremden Quellen.
  ///
  /// Ein importiertes Schlaffenster ist gestern passiert, nicht jetzt. Wuerde
  /// es mit der aktuellen Uhrzeit abgelegt, waeren alle Zeitfenster-Auswertungen
  /// falsch: Schlafschuld der letzten sieben Tage, Baseline-Naechte, Verlauf.
  /// Die ULID wird aus demselben Zeitpunkt gebildet, damit die Sortierung
  /// stimmt.
  Future<Event> recordAt(
    DateTime at,
    EventType type, {
    Map<String, Object?> payload = const {},
    EventSource source = EventSource.health,
  }) async {
    final utc = at.toUtc();
    final event = Event(
      id: newUlid(utc),
      at: utc,
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
  /// Der Auswertungskontext von jetzt — fuer die Vorschau im Regeleditor.
  ///
  /// Damit laesst sich eine Bedingung gegen den *aktuellen* Zustand pruefen,
  /// bevor sie gespeichert wird. Das ist der Unterschied zwischen einem
  /// Editor und einem Texteingabefeld: Man sieht sofort, ob die Regel jetzt
  /// zutraefe — und bei welchem Teil sie scheitert.
  Future<StateEvalContext> currentContext() async {
    final signals = await _aggregator.aggregate();
    final derived = _deriver.derive(signals, clock.nowUtc());
    return StateEvalContext(
      state: derived.vector,
      clock: clock,
      runtime: await _buildRuntimeContext(),
    );
  }
  /// [language] wirkt nur auf Texte, nie auf Urteile: Welche Regel feuert,
  /// haengt nicht von der Anzeigesprache ab (ADR-0003).
  Future<AxiomSnapshot> evaluate({
    AppLanguage language = AppLanguage.de,
  }) async {
    final signals = await _aggregator.aggregate();
    final derived = _deriver.derive(signals, clock.nowUtc());
    final tasks = await store.tasks();
    final links = TaskLinkGraph.from(
      tasks: tasks,
      links: await store.taskLinks(),
    );
    final metaUsed = await store.usageToday(clock.nowLocal());
    final runtimeContext = await _buildRuntimeContext(tasks: tasks);
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
      links: links,
      metaUsedToday: metaUsed,
      skipped: result.skipped,
      anchors: await upcomingAnchors(),
      nextStep: nextStep,
      atomizeCandidates:
          await atomizeCandidates(derived.vector.capacity, links: links),
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
      place: runtimeContext.place,
      knownPlaces: await knownPlaces(),
      deadlinePressure: tightestDeadline(tasks, now),
    );
  }
  /// Zeit seit der letzten Koerper-Quittierung, fuer den Focus Governor.
  static Duration? _sinceBody(RuntimeContext ctx) {
    final minutes = ctx.minutesSinceByEvent['body_prompt'];
    return minutes == null ? null : Duration(minutes: minutes);
  }
  Future<RuntimeContext> _buildRuntimeContext({List<Task>? tasks}) async {
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
    final pressure =
        tightestDeadline(tasks ?? await store.tasks(), clock.nowLocal());
    return RuntimeContext(
      activeSlot: focusRunning
          ? 'focus'
          : slotRunning
              ? 'sensation'
              : 'none',
      minutesSinceByEvent: minutesSince,
      countTodayByEvent: countToday,
      // Ohne diesen Wert kann keine Regel formulieren, dass das
      // Meta-Work-Budget aufgebraucht ist — und G4 bliebe eine
      // Absichtserklaerung (CLAUDE.md nennt es das wichtigste Gesetz).
      metaMinutesToday: (await store.usageToday(clock.nowLocal())).inMinutes,
      place: await currentPlace(),
      hoursToDeadline: pressure == null
          ? kNoDeadlineHours
          : hoursOf(pressure.untilDue),
      deadlineSlackHours: pressure == null
          ? kNoDeadlineHours
          : hoursOf(pressure.untilDue - pressure.runway),
    );
  }

  // ── Ort (M2) ──────────────────────────────────────────────────────────
  //
  // Kein GPS, kein Geofence, keine Standortberechtigung. Der Ort ist ein
  // Name, den der Nutzer setzt oder eine Geraeteroutine schickt. Was er
  // beantwortet, ist nicht „wo bin ich", sondern „was geht hier" — und das
  // steht in keiner Koordinate. [D2]

  /// Der zuletzt gesetzte Ort. Null heisst „keiner".
  ///
  /// **Ohne Verfallszeit, mit Absicht.** Ein Ort, der um Mitternacht von
  /// selbst verfaellt, waere nach einer WLAN-Routine, die ueber Nacht nicht
  /// neu ausloest, morgens einfach weg. Ein Ort, der bleibt, ist dagegen
  /// jederzeit sichtbar — die Hauptansicht zeigt ihn, solange er gesetzt ist,
  /// und zwei Tipps setzen ihn zurueck. Sichtbar und stehengeblieben ist
  /// besser als unsichtbar und schlau.
  Future<String?> currentPlace() async {
    final last = await store.last(EventType.placeEntered);
    final value = (last?.payload['place'] as String?)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  /// Setzt den Ort. `null` oder leer heisst: keiner mehr.
  ///
  /// Append-only wie alles: Der Wechsel ist ein Ereignis, kein ueberschriebenes
  /// Feld. Damit laesst sich spaeter auswerten, wo tatsaechlich gearbeitet
  /// wurde — und ob die Ortsbindung ueberhaupt etwas bringt.
  Future<void> setPlace(String? place, {EventSource source = EventSource.user}) {
    final value = place?.trim() ?? '';
    return record(
      EventType.placeEntered,
      source: source,
      payload: {'place': value},
    );
  }

  /// Orte, die vorkommen — aus den Aufgaben und aus dem Verlauf.
  ///
  /// Absteigend nach Aktualitaet: Der zuletzt gesetzte Ort steht vorn und ist
  /// damit im zweiten Tipp erreichbar.
  Future<List<String>> knownPlaces() async {
    final ordered = <String>[];
    void add(String? value) {
      final name = value?.trim();
      if (name == null || name.isEmpty) return;
      if (ordered.any((p) => samePlace(p, name))) return;
      ordered.add(name);
    }

    final history = await store.query(types: {EventType.placeEntered});
    for (final event in history.reversed) {
      add(event.payload['place'] as String?);
    }
    for (final task in await store.tasks()) {
      if (isTaskOpen(task)) add(task.place);
    }
    return ordered;
  }
  /// Erzeugt die Begruendung: Regeltext plus die konkreten Zustandswerte,
  /// die sie ausgeloest haben. Ohne die Zahlen bleibt es eine Behauptung.
  String explainRule(
    Rule rule,
    StateVector state, {
    AppLanguage language = AppLanguage.de,
  }) {
    final referenced = rule.when.referencedVariables
        .where((v) => !v.startsWith('event:') && v != 'time_between')
        .map((v) => '$v ${state.numeric(v) ?? "–"}')
        .join(' · ');
    final rationale = rule.rationaleFor(language.code).trim();
    return referenced.isEmpty
        ? rationale
        : '$rationale\n\n'
            '${translate(language, "Ausgelöst durch:")} $referenced';
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
    String? place,
    TaskState state = TaskState.ready,
  }) async {
    final trimmedPlace = place?.trim();
    final task = Task(
      id: newUlid(clock.nowUtc()),
      title: title,
      activationEnergy: activationEnergy,
      salience: salience,
      stakes: stakes,
      decayAt: decayAt,
      parentId: parentId,
      place: trimmedPlace == null || trimmedPlace.isEmpty ? null : trimmedPlace,
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
      // Ohne diesen Eintrag ueberlebt der Ort keinen Wiederaufbau aus dem
      // Ereignisstrom — und die Aufgabe kaeme ortsungebunden zurueck.
      'place': ?task.place,
    });
    return task;
  }
  Future<void> completeTask(Task task) async {
    await store.upsertTask(task.copyWith(state: TaskState.done));
    await record(EventType.taskCompleted, payload: {'task_id': task.id});
    // Ein Fokusfenster, das an dieser Aufgabe hing, hat seinen Anker
    // verloren. Es weiterlaufen zu lassen hiesse, Zeit auf etwas zu buchen,
    // das es nicht mehr gibt.
    await _closeFocusFor(task, exit: 'completed');
    await _reopenParentIfStepsDone(task);
  }
  Future<void> dropTask(Task task) async {
    await store.upsertTask(task.copyWith(state: TaskState.dropped));
    await record(EventType.taskAbandoned,
        payload: {'task_id': task.id, 'reason': 'manual'});
    await _reopenParentIfStepsDone(task);
  }
  /// Beginnt eine Aufgabe — und zwar genau eine.
  ///
  /// Zwei gleichzeitig laufende Aufgaben wären eine Liste mit zwei
  /// Einträgen, und die Frage „welche gilt jetzt?" ist genau die
  /// Entscheidung, die AXIOM abnehmen soll (G1). Die vorherige geht deshalb
  /// zurück in den Bestand, kommentarlos.
  ///
  /// Dazu startet ein Fokusfenster, an die Aufgabe gebunden. Ohne das war
  /// „Anfangen" ein Zustandswechsel ohne sichtbare Folge: Die Aufgabe
  /// verschwand aus der Auswahl, tauchte nirgends wieder auf und ließ sich
  /// nicht mehr abschließen [D9].
  Future<void> startTask(Task task, {Duration? planned}) async {
    for (final other in await store.tasks(states: {TaskState.active})) {
      if (other.id == task.id) continue;
      await store.upsertTask(other.copyWith(state: TaskState.ready));
      await record(EventType.taskAbandoned,
          payload: {'task_id': other.id, 'reason': 'superseded'});
    }

    await store.upsertTask(task.copyWith(state: TaskState.active));
    await record(EventType.taskStarted, payload: {'task_id': task.id});

    // Läuft schon ein Fokus, bleibt er. Ihn neu zu starten würde die
    // bisherige Zeit verwerfen.
    if (await store.activeFocus() == null) {
      // Die Länge folgt der Kapazität, nicht einem festen Ritual: Ein
      // kurzes Fenster, das hält, ist mehr wert als ein langes, das reißt.
      await startFocus(
        taskId: task.id,
        taskTitle: task.title,
        planned: planned ?? plannedFocusFor(await _capacityNow()),
      );
    }
  }

  /// Die Kapazität von jetzt — für die Länge des Fokusfensters.
  Future<int> _capacityNow() async {
    final signals = await _aggregator.aggregate();
    return _deriver.derive(signals, clock.nowUtc()).vector.capacity;
  }

  /// Zurück in den Bestand — ohne Kommentar, ohne Bewertung.
  ///
  /// Etwas anzufangen und nicht zu beenden ist der Normalfall, nicht das
  /// Versagen. Der Weg zurück muss deshalb genauso leicht sein wie der
  /// hinein, sonst wird die laufende Aufgabe zu einem Vorwurf, der stehen
  /// bleibt [D10].
  Future<void> releaseTask(Task task) async {
    await store.upsertTask(task.copyWith(state: TaskState.ready));
    await record(EventType.taskAbandoned,
        payload: {'task_id': task.id, 'reason': 'released'});
    await _closeFocusFor(task, exit: 'released');
  }

  /// Schliesst ein Fokusfenster, das an [task] hing — und nur dann.
  Future<void> _closeFocusFor(Task task, {required String exit}) async {
    final focus = await store.activeFocus();
    if (focus == null || focus.anchorTaskId != task.id) return;
    await endFocus(focus, exit: exit);
  }
  // ── Blocker (M2) ──────────────────────────────────────────────────────
  //
  // Genau eine Beziehungsart: A blockiert B. Kein „hängt zusammen mit", kein
  // „Duplikat von", kein „folgt auf" — ein Beziehungsgeflecht zu pflegen ist
  // befriedigender als die Arbeit, für die es gebaut wurde [D3].

  /// Alle Beziehungen, roh. Für den Editor am großen Bildschirm.
  Future<List<TaskLink>> taskLinks() => store.taskLinks();

  /// Legt „[blockerId] blockiert [blockedId]" an.
  ///
  /// Wirft [TaskLinkCycleError], wenn dadurch ein Kreis entstünde — mit dem
  /// Weg, an dem er sich schließt. Fail-Fast wie überall im Kern: Ein Kreis
  /// legt die Auswahl still lahm, und ein stiller Ausfall ist teurer als ein
  /// lauter (CLAUDE.md).
  ///
  /// Eine Beziehung, die es schon gibt, ist kein Fehler und kein Ereignis.
  Future<void> linkBlocker({
    required String blockerId,
    required String blockedId,
  }) async {
    // Beide Aufgaben müssen es geben. Eine Kante ins Leere ließe sich
    // anlegen, wäre nie sichtbar und hielte nie etwas auf — ein stummer
    // Fehlschlag, und genau die sind hier verboten.
    final ids = (await store.tasks()).map((t) => t.id).toSet();
    for (final id in [blockerId, blockedId]) {
      if (!ids.contains(id)) {
        throw ArgumentError.value(id, 'taskId', 'Diese Aufgabe gibt es nicht');
      }
    }

    final existing = await store.taskLinks();
    if (existing.any((l) =>
        l.blockerId == blockerId && l.blockedId == blockedId)) {
      return;
    }
    ensureAcyclic(
      existing: existing,
      blockerId: blockerId,
      blockedId: blockedId,
    );

    await store.addTaskLink(blockerId, blockedId);
    await record(EventType.taskLinked, payload: {
      'blocker_id': blockerId,
      'blocked_id': blockedId,
    });
  }

  /// Löst die Beziehung wieder. Gab es sie nicht, passiert nichts.
  Future<void> unlinkBlocker({
    required String blockerId,
    required String blockedId,
  }) async {
    if (!await store.removeTaskLink(blockerId, blockedId)) return;
    await record(EventType.taskUnlinked, payload: {
      'blocker_id': blockerId,
      'blocked_id': blockedId,
    });
  }

  // ── Zerlegen (M2) ─────────────────────────────────────────────────────
  static const _atomizer = Atomizer();
  /// Aufgaben, die zerlegt werden sollten. Die Oberfläche zeigt immer nur
  /// die erste — eine Liste von Zerlegungsaufträgen wäre selbst eine Hürde.
  ///
  /// Wartende Aufgaben fallen heraus: Sie zu zerlegen löst nichts, weil der
  /// Blocker auch die Teilschritte aufhält. Angeboten wird stattdessen, was
  /// die Kette aufhält — und das ist der Blocker selbst.
  Future<List<AtomizeCandidate>> atomizeCandidates(
    int capacity, {
    TaskLinkGraph? links,
  }) async {
    final tasks = await store.tasks();
    final graph = links ??
        TaskLinkGraph.from(tasks: tasks, links: await store.taskLinks());
    return _atomizer
        .candidates(
          tasks: tasks,
          capacity: capacity,
          now: clock.nowLocal(),
          createdAt: await store.taskCreationTimes(),
        )
        .where((c) => !graph.isWaiting(c.task.id))
        .toList();
  }
  /// Der Zerlegungsauftrag für eine bestimmte Aufgabe — auf Zuruf.
  ///
  /// Für den Weg, den der Nutzer selbst wählt: Jede offene Aufgabe lässt
  /// sich zerlegen, auch ein Teilschritt, auch eine, die AXIOM von sich aus
  /// nicht angeboten hätte. Der erste Schritt muss klein genug sein, und wie
  /// tief das führt, entscheidet nicht die Formel [D2].
  Future<AtomizeCandidate> atomizeCandidateFor(Task task) async =>
      _atomizer.candidateFor(
        task: task,
        capacity: await _capacityNow(),
        now: clock.nowLocal(),
        createdAt: (await store.taskCreationTimes())[task.id],
      );
  /// Zerlegt eine Aufgabe in die vom Nutzer benannten Schritte.
  ///
  /// Das Elternteil wird blockiert, nicht gelöscht: Es bleibt als Klammer
  /// erhalten, verschwindet aber aus der Auswahl, damit es nicht doppelt
  /// erscheint — neben seinen eigenen Schritten wäre es eine Wahl, und
  /// genau die soll die Zerlegung ersparen (G1).
  ///
  /// `blocked` heißt hier: **vertreten durch die eigenen Schritte**, nicht
  /// stillgelegt. Zerlegen bleibt möglich (die Schritte waren zu grob),
  /// und sobald kein Schritt mehr offen ist, kommt die Klammer zurück —
  /// siehe [_reopenParentIfStepsDone].
  Future<List<Task>> atomize({
    required Task parent,
    required List<({String title, int energy})> steps,
  }) async {
    final children = _atomizer.split(
      parent: parent,
      steps: steps,
      nextId: () => newUlid(clock.nowUtc()),
    );
    // Jeder Teilschritt bekommt ein eigenes taskCreated — nicht nur einen
    // Eintrag in der Projektion.
    //
    // Vorher standen die Kinder ausschliesslich in `tasks`, und der
    // taskSplit-Eintrag nannte nur ihre IDs. Ein Wiederaufbau aus dem
    // Ereignisstrom hat sie damit ersatzlos verloren — und genau das ist
    // die Zusage, die dieses System traegt: Projektionen sind aus `events`
    // neu aufbaubar. Eine Zerlegung ist der haeufigste Weg, wie eine
    // Aufgabe in Reichweite kommt (D2); sie zu verlieren ist der teuerste
    // Datenverlust, den es hier gibt.
    for (final child in children) {
      await store.upsertTask(child);
      await record(EventType.taskCreated, payload: {
        'task_id': child.id,
        'title': child.title,
        'ae': child.activationEnergy,
        'salience': child.salience,
        'stakes': child.stakes,
        'state': child.state.name,
        'parent_id': parent.id,
        if (child.decayAt != null)
          'decay_at': child.decayAt!.toUtc().toIso8601String(),
        'place': ?child.place,
      });
    }
    // Lief die Aufgabe gerade, endet damit auch ihr Fokusfenster: Die
    // Arbeit geht an den ersten Schritt über, und Zeit auf eine Klammer zu
    // buchen, an der niemand mehr sitzt, wäre eine Messung ohne Gegenstand.
    await _closeFocusFor(parent, exit: 'split');
    await store.upsertTask(parent.copyWith(state: TaskState.blocked));
    await record(EventType.taskSplit, payload: {
      'parent_id': parent.id,
      'child_ids': children.map((c) => c.id).toList(),
    });
    return children;
  }
  /// Die Klammer kommt zurück, wenn kein Schritt mehr offen ist.
  ///
  /// **Warum zurück in den Bestand und nicht automatisch erledigt.** Beim
  /// Zerlegen wird die allererste Handlung benannt und der Rest höchstens
  /// grob. Aus „Ordner auf den Tisch gelegt" folgt nicht „Steuererklärung
  /// erledigt". Eine Aufgabe still zu schließen, die es noch gibt, ist der
  /// teuerste Fehler dieses Systems: Man merkt es, wenn die Frist vorbei
  /// ist, und danach traut man dem Bestand nicht mehr [D9]. Der umgekehrte
  /// Fehler kostet einen Tipp — wer fertig ist, hakt die Klammer ab.
  ///
  /// Ewig blockiert stehen bleiben darf sie ebensowenig: Dann wäre sie
  /// weder startbar noch sichtbar noch zerlegbar, also faktisch gelöscht.
  ///
  /// Erklärbar bleibt es, weil der Übergang an genau einer Bedingung hängt
  /// und ein Ereignis schreibt (G2): kein offener Teilschritt mehr.
  Future<void> _reopenParentIfStepsDone(Task step) async {
    final parentId = step.parentId;
    if (parentId == null) return;
    final all = await store.tasks();
    final parent = all.where((t) => t.id == parentId).firstOrNull;
    if (parent == null || parent.state != TaskState.blocked) return;
    if (hasOpenSteps(all, parentId)) return;
    await store.upsertTask(parent.copyWith(state: TaskState.ready));
    // Eigener Grund, keine Tarnung als `released`: Eine Aufgabe, deren
    // Teilschritte alle erledigt sind, wurde nicht zurueckgelegt. Der
    // Ereignisstrom ist die Wahrheit dieses Systems — was dort steht, muss
    // stimmen, auch wenn zwei Faelle dieselbe Folge haben.
    await record(EventType.taskAbandoned, payload: {
      'task_id': parent.id,
      'reason': 'steps_done',
    });
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
  /// Derselbe Text mit getrennten Werten — uebersetzbar.
  Phrase interceptWaitingPhrase(InterceptRun run) =>
      _interceptor.waitingPhrase(run, clock.nowLocal());
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
  // ── Signal-Log (M10) ──────────────────────────────────────────────────
  static const _signalLog = SignalLog();
  /// Haelt einen Vorfall fest. Kurz, weil im Spike niemand viel schreibt.
  Future<void> logIncident({
    required int intensity,
    required TriggerClass triggerClass,
    String? note,
  }) =>
      record(EventType.signalIncident, payload: {
        'intensity': intensity,
        'trigger_class': triggerClass.name,
        'note': ?note,
      });
  Future<List<SignalIncident>> incidents({Duration window = const Duration(days: 30)}) =>
      store.incidentsSince(clock.nowUtc().subtract(window));
  /// Vorfaelle, deren Nachbetrachtung jetzt sinnvoll ist.
  ///
  /// Nicht sofort nach dem Ereignis: Im Spike ist niemand analysefaehig,
  /// und der Versuch verlaengert es (D10).
  Future<List<SignalIncident>> awaitingPostMortem() async =>
      _signalLog.awaitingPostMortem(
        incidents: await incidents(),
        reviewedIds: await store.reviewedIncidentIds(),
        now: clock.nowLocal(),
      );
  Future<void> savePostMortem({
    required String incidentId,
    String? rootCause,
    String? countermeasure,
    int? intensityInHindsight,
  }) async {
    await store.savePostMortem(PostMortem(
      incidentId: incidentId,
      at: clock.nowLocal(),
      rootCause: rootCause,
      countermeasure: countermeasure,
      intensityInHindsight: intensityInHindsight,
    ));
    await record(EventType.signalPostmortem, payload: {
      'incident_id': incidentId,
      'root_cause': ?rootCause,
      'countermeasure': ?countermeasure,
      'hindsight': ?intensityInHindsight,
    });
  }
  Future<Map<TriggerClass, int>> incidentPatterns() async =>
      _signalLog.patterns(await incidents());
  /// Um wie viel niedriger ein Vorfall im Rueckblick ausfaellt.
  Future<double?> hindsightDelta() async => _signalLog.hindsightDelta(
        incidents: await incidents(window: const Duration(days: 90)),
        reviews: await store.postMortems(),
      );
  // ── Wirkfenster (M13, opt-in) ─────────────────────────────────────────
  static const _medWindow = MedWindow();
  bool get medEnabled => store.medEnabled;
  set medEnabled(bool value) => store.medEnabled = value;
  Future<void> logMedEntry({
    required String label,
    String? dose,
    Duration onset = const Duration(minutes: 30),
    Duration duration = const Duration(hours: 6),
  }) async {
    final entry = MedEntry(
      id: newUlid(clock.nowUtc()),
      label: label,
      dose: dose,
      takenAt: clock.nowLocal(),
      onset: onset,
      duration: duration,
    );
    await store.saveMedEntry(entry);
    await record(EventType.medIntake, payload: {
      'substance': label,
      'dose': ?dose,
      'onset_min': onset.inMinutes,
      'duration_min': duration.inMinutes,
    });
  }
  Future<List<MedEntry>> medEntries({Duration window = const Duration(days: 14)}) =>
      store.medEntriesSince(clock.nowUtc().subtract(window));
  Future<MedEntry?> lastMedEntry() => store.lastMedEntry();
  Future<void> deleteMedEntry(String id) => store.deleteMedEntry(id);
  Future<MedWindowState> medState() async {
    if (!medEnabled) return const MedWindowState();
    final entries = await medEntries(window: const Duration(days: 2));
    return MedWindowState(
      enabled: true,
      active: _medWindow.activeAt(entries, clock.nowLocal()),
    );
  }
  String describeMedWindow(MedWindowState state) =>
      _medWindow.describe(state, clock.nowLocal());
  // ── Export und Import (S4) ────────────────────────────────────────────
  late final _vault = Vault(store: store, clock: clock);
  Future<Uint8List> exportVault(String passphrase) =>
      _vault.export(passphrase: passphrase);
  Future<VaultImportResult> importVault(
    Uint8List data,
    String passphrase, {
    bool dryRun = false,
  }) =>
      _vault.import(data: data, passphrase: passphrase, dryRun: dryRun);
  // ── Meta-Guard (M12) ──────────────────────────────────────────────────
  Future<void> logScreenTime(String screen, Duration duration,
          {bool countsToBudget = true}) =>
      store.logUsage(screen, duration, countsToBudget: countsToBudget);
  /// Konfiguration ist gesperrt, wenn das Tagesbudget aufgebraucht ist.
  /// Nicht als Strafe — als Schutz vor der Meta-Work-Falle (D3).
  /// Ist die Konfiguration gesperrt, weil das Tagesbudget aufgebraucht ist?
  ///
  /// Die Sperre gilt fuer Konfiguration, nicht fuer Erfassung, nicht fuer
  /// die Daten und nicht fuer den Zustand. Wer am Limit ist, soll trotzdem
  /// arbeiten, exportieren und nachsehen koennen — gedeckelt wird das
  /// Schrauben am System selbst (D3, R1).
  Future<bool> isConfigLocked() async =>
      (await store.usageToday(clock.nowLocal())) >= kMetaBudget;
  /// Soll der Expertenmodus mitstarten, wenn die App geöffnet wird?
  ///
  /// **Warum das eine Einstellung ist und keine Selbstverständlichkeit.**
  /// ADR-0005 hat den Autostart ausgeschlossen: Ein offener Port mit
  /// Gesundheitsdaten, der von selbst aufgeht, ist etwas anderes als einer,
  /// den man einschaltet. Was hier erlaubt wird, ist enger als das, was
  /// dort gemeint war — kein Start beim Hochfahren, kein Weiterlaufen ohne
  /// die App, sondern nur: Wer die App öffnet, hat den Server dabei.
  ///
  /// Die Sicherungen bleiben alle: PIN oder Zahlenabgleich, dauerhafte
  /// Anzeige mit Stopp-Knopf, Abschaltung nach dreißig Minuten Leerlauf.
  bool get expertAutostart => store.setting('expert_autostart') == 'true';
  set expertAutostart(bool on) =>
      store.setSetting('expert_autostart', on ? 'true' : 'false');

  bool get onboardingDone => store.setting('onboarding_done') == 'true';
  void markOnboardingDone() => store.setSetting('onboarding_done', 'true');
  /// Anzeigesprache als Sprachcode. Leer heisst: noch nie gewaehlt.
  String? get language => store.setting('language');
  set language(String? code) =>
      store.setSetting('language', code ?? AppLanguage.de.code);
  // ── Anzeige ───────────────────────────────────────────────────────────
  //
  // Drei Einstellungen, mehr nicht. Sie stehen hier statt im Speicher, weil
  // eine Schriftgroesse, die beim naechsten Start zurueckspringt, schlimmer
  // waere als gar keine Auswahl.
  String? get textSizeName => store.setting('text_size');
  set textSizeName(String? name) =>
      store.setSetting('text_size', name ?? TextSize.normal.name);
  String? get colorSchemeName => store.setting('color_scheme');
  set colorSchemeName(String? name) =>
      store.setSetting('color_scheme', name ?? AxiomScheme.instrument.name);
  /// 0 = System, 1 = dunkel, 2 = hell.
  int get brightnessChoice =>
      int.tryParse(store.setting('brightness') ?? '') ?? 0;
  set brightnessChoice(int value) =>
      store.setSetting('brightness', '$value');
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
