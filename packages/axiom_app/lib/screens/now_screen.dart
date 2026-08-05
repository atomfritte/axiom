/// "Jetzt" — die Hauptansicht.
///
/// Zeigt genau EINE naechste Handlung, nie eine Liste zur Auswahl. Die
/// Auswahl aus einer Liste ist genau die Entscheidung, die bei niedriger
/// Kapazitaet am teuersten ist (G1). Die vollstaendige Liste bleibt
/// erreichbar, ist aber nie der Standardweg.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/widgets/anchor_chain.dart';
import '../design/widgets/capacity_line.dart';
import '../design/widgets/instruments.dart';
import '../state/providers.dart';
import '../state/runtime.dart';
import 'anchors_screen.dart';
import 'atomize_sheet.dart';
import 'body_sheet.dart';
import 'focus_screen.dart';
import 'intercept_screen.dart';
import 'sensation_screen.dart';
import 'signal_screen.dart';
import 'capture_sheet.dart';
import 'checkin_sheet.dart';
import 'inbox_screen.dart';
import 'place_sheet.dart';
import 'review_screen.dart';
import 'system_screen.dart';
import 'tasks_screen.dart';
import '../i18n/i18n.dart';

class NowScreen extends ConsumerWidget {
  const NowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(snapshotProvider);
    final inbox = ref.watch(inboxProvider).value ?? const [];

    return Scaffold(
      body: SafeArea(
        child: snapshot.when(
          loading: () => PatientLoader(
            hint: context.t('Das dauert länger als vorgesehen. Bleibt es dabei, sagt System → Systemcheck, ob eine Systemschnittstelle nicht antwortet.'),
          ),
          error: (e, _) => _ErrorPane(error: e),
          data: (snap) => RefreshIndicator(
            onRefresh: () async => refreshAxiom(ref),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  Space.lg, Space.lg, Space.lg, Space.huge * 2),
              children: [
                _Header(snapshot: snap),
                if (snap.regime.level != LoadLevel.l0) ...[
                  const SizedBox(height: Space.lg),
                  _RegimeBanner(snapshot: snap),
                ],
                if (snap.activeIntercept != null) ...[
                  const SizedBox(height: Space.lg),
                  _InterceptStrip(run: snap.activeIntercept!),
                ],
                // Hängt der Fokus an der laufenden Aufgabe, steht die Zeit
                // schon auf deren Karte. Zweimal dasselbe wäre eine Liste
                // mit einem Eintrag.
                if (snap.focus != null &&
                    !snap.tasks.any((t) =>
                        t.state == TaskState.active &&
                        t.id == snap.focus!.anchorTaskId)) ...[
                  const SizedBox(height: Space.lg),
                  _FocusStrip(snapshot: snap),
                ],
                if (snap.nextStep != null) ...[
                  const SizedBox(height: Space.lg),
                  _AnchorStrip(next: snap.nextStep!),
                ],
                // Die Regel bekommt die Karte, die laufende Aufgabe diesen
                // Streifen. Ohne ihn waere sie in genau dem Moment
                // unsichtbar, in dem etwas anderes dazwischenkommt — und
                // das ist der Moment, in dem man sie am ehesten vergisst.
                if (snap.decision != null && snap.decisionRule != null)
                  for (final task in snap.tasks
                      .where((t) => t.state == TaskState.active)) ...[
                    const SizedBox(height: Space.lg),
                    _RunningStrip(task: task),
                  ],
                // Steht direkt über der Handlung, weil er sie mitbestimmt:
                // Was hier vorgeschlagen wird, hängt am gesetzten Ort. Ein
                // Filter, den man nicht sieht, wirkt wie ein Fehler (G2).
                //
                // Erscheint nur, wenn es etwas zu sehen gibt — solange keine
                // Aufgabe einen Ort trägt und keiner gesetzt ist, ist die
                // Zeile eine Einstellung ohne Wirkung, und die gehört nicht
                // auf den Hauptbildschirm (D3).
                if (snap.place != null ||
                    snap.tasks.any((t) => t.place != null && isTaskOpen(t))) ...[
                  const SizedBox(height: Space.lg),
                  _PlaceStrip(snapshot: snap),
                ],
                const SizedBox(height: Space.xl),
                _PrimaryAction(snapshot: snap),
                if (inbox.isNotEmpty) ...[
                  const SizedBox(height: Space.md),
                  _InboxTeaser(count: inbox.length),
                ],
                const SizedBox(height: Space.md),
                const _BaselineTeaser(),
                const _PostMortemTeaser(),
                const _ReviewTeaser(),
                const SizedBox(height: Space.xxl),
                // Die Leiste zeigt den Bestand schon als Balken — sie ist
                // der natuerliche Weg zur vollstaendigen Liste. Erreichbar,
                // aber nie der Standardweg (G1).
                Panel(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const TasksScreen()),
                  ),
                  child: CapacityLine(
                    capacity: snap.state.capacity,
                    tasks: snap.tasks
                        .where((t) => t.state == TaskState.ready)
                        .toList(),
                    highlightTaskId: snap.startable.firstOrNull?.id,
                    onOpen: true,
                  ),
                ),
                const SizedBox(height: Space.xxl),
                _QuickState(snapshot: snap),
                const SizedBox(height: Space.xl),
                SectionLabel(context.t('Körper')),
                const BodyStrip(),
                const SizedBox(height: Space.xl),
                _Tools(snapshot: snap),
                const SizedBox(height: Space.xl),
                _MetaBudget(used: snap.metaUsedToday),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCaptureSheet(context),
        backgroundColor: context.axiom.signal,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        icon: const Icon(Icons.add),
        label: Text(context.t('Erfassen')),
      ),
    );
  }
}

// ── Kopfzeile ───────────────────────────────────────────────────────────

class _Header extends ConsumerWidget {
  final AxiomSnapshot snapshot;
  const _Header({required this.snapshot});

  /// Wochentage und Monate als Funktion, nicht als Konstante: Sie haengen
  /// an der eingestellten Sprache wie jeder andere Text auch.
  static List<String> _weekdays(BuildContext c) => [
        c.t('Montag'), c.t('Dienstag'), c.t('Mittwoch'), c.t('Donnerstag'),
        c.t('Freitag'), c.t('Samstag'), c.t('Sonntag'),
      ];

  static List<String> _months(BuildContext c) => [
        c.t('Januar'), c.t('Februar'), c.t('März'), c.t('April'),
        c.t('Mai'), c.t('Juni'), c.t('Juli'), c.t('August'),
        c.t('September'), c.t('Oktober'), c.t('November'), c.t('Dezember'),
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider);
    final p = context.axiom;
    final baseline = ref.watch(baselineProvider).value;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_weekdays(context)[now.weekday - 1].toUpperCase()} '
                '${now.day}. ${_months(context)[now.month - 1].toUpperCase()}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: Space.xs),
              Text(
                _greeting(context, now.hour),
                style: Theme.of(context).textTheme.headlineLarge,
              ),
            ],
          ),
        ),
        // Der Hinweis bleibt, bis geeicht ist — er verschwindet nicht
        // ausgerechnet dann, wenn er relevant wird.
        if (baseline != null &&
            baseline.status == BaselineStatus.collecting)
          // Flexible mit Ellipse: Bei grosser Schrift ist die Marke breiter
          // als der Platz, den die Begruessung uebrig laesst.
          Flexible(
              child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Space.sm, vertical: Space.xs),
            decoration: BoxDecoration(
              border: Border.all(color: p.info.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(Radii.control),
            ),
            child: Text(context.t('BASELINE TAG {0}', [baseline.day]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: monoStyle(context,
                    size: 10, weight: FontWeight.w600, color: p.info)),
          )),
      ],
    );
  }

  static String _greeting(BuildContext context, int hour) => switch (hour) {
        < 5 => context.t('Noch wach.'),
        < 11 => context.t('Morgen.'),
        < 14 => context.t('Mittag.'),
        < 18 => context.t('Nachmittag.'),
        < 22 => context.t('Abend.'),
        _ => context.t('Spät.'),
      };
}

// ── Die eine Handlung ───────────────────────────────────────────────────

class _PrimaryAction extends ConsumerWidget {
  final AxiomSnapshot snapshot;
  const _PrimaryAction({required this.snapshot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decision = snapshot.decision;
    final rule = snapshot.decisionRule;
    final candidate = snapshot.atomizeCandidates.firstOrNull;
    final next = snapshot.startable.firstOrNull;


    // Eine Regel hat gefeuert — sie gewinnt vor jedem eigenen Vorschlag.
    //
    // Aber: Die Aktion bestimmt, WAS gezeigt wird. Eine Regel, die zerlegen
    // will, muss die Zerlegung anbieten — nicht eine allgemeine Karte mit
    // ihrem Titel. Sonst ist die Ausgabe formal korrekt und praktisch
    // wertlos: Man liest, was zu tun waere, und kann es nicht tun (G1).
    if (decision != null && rule != null) {
      return switch (rule.then.type) {
        ActionType.forceAtomize when candidate != null =>
          _AtomizeCard(candidate: candidate, rule: rule),
        ActionType.suggestTask when next != null =>
          _TaskCard(task: next, rule: rule),
        _ => _DecisionCard(decision: decision, rule: rule),
      };
    }

    // Eine angefangene Aufgabe schlägt jeden eigenen Vorschlag — aber
    // keine Regel.
    //
    // Sie fiel vorher aus der Auswahl heraus (`startable` kennt nur
    // `ready`) und war damit weg: nicht abschließbar, nicht auffindbar,
    // nirgends sichtbar [D9]. Sie hier vor die Regeln zu setzen wäre
    // allerdings der nächste Fehler: Eine feuernde Regel ist die Instanz,
    // die entscheidet, und ein Termin in zehn Minuten schlägt jede laufende
    // Vertiefung. Feuert eine, steht die laufende Aufgabe stattdessen als
    // Streifen darüber — sichtbar, nur nicht als Handlung.
    final running = snapshot.tasks
        .where((t) => t.state == TaskState.active)
        .firstOrNull;
    if (running != null) return _RunningCard(task: running);

    if (next != null) return _TaskCard(task: next);

    // Nichts startbar, aber etwas wartet: zerlegen statt anmahnen (M2, D2).
    if (candidate != null) return _AtomizeCard(candidate: candidate);

    return _EmptyState(snapshot: snapshot);
  }
}

/// Die Aufgabe, die gerade läuft.
///
/// Solange sie läuft, ist sie die Ausgabe — kein Vorschlag daneben, keine
/// Auswahl. Zwei Wege hinaus, beide gleich leicht: fertig oder zurück in
/// den Bestand. Der Rückweg ist absichtlich genauso prominent wie der
/// Abschluss; etwas anzufangen und nicht zu beenden ist der Normalfall und
/// bekommt hier keinen Kommentar [D10].
class _RunningCard extends ConsumerWidget {
  final Task task;
  const _RunningCard({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    final session = ref.watch(snapshotProvider).value?.focus;
    final focus = session?.anchorTaskId == task.id ? session : null;
    final elapsed = focus?.elapsed(ref.watch(nowProvider));

    return Panel(
      accent: p.calm.withValues(alpha: 0.6),
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(context.t('LÄUFT'),
                    style: Theme.of(context).textTheme.labelSmall),
              ),
              if (elapsed != null && focus != null)
                Text(
                  context.t('{0} von {1} min',
                      [elapsed.inMinutes, focus.planned.inMinutes]),
                  style: monoStyle(context,
                      size: 13, weight: FontWeight.w600, color: p.calm),
                ),
            ],
          ),
          const SizedBox(height: Space.md),
          Text(task.title, style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: Space.xl),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () async {
                    final runtime = await ref.read(runtimeProvider.future);
                    await runtime.completeTask(task);
                    await HapticFeedback.mediumImpact();
                    refreshAxiom(ref);
                  },
                  child: Text(context.t('Erledigt')),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final runtime = await ref.read(runtimeProvider.future);
                    await runtime.releaseTask(task);
                    await HapticFeedback.selectionClick();
                    refreshAxiom(ref);
                  },
                  child: Text(context.t('Zurücklegen')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DecisionCard extends ConsumerWidget {
  final Decision decision;
  final Rule rule;
  const _DecisionCard({required this.decision, required this.rule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    final isCheckin = rule.then.type == ActionType.promptCheckin;

    return Panel(
      accent: p.signal.withValues(alpha: 0.55),
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t('JETZT'), style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Space.md),
          Text(context.ruleTitle(rule),
              style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: Space.lg),
          Row(
            children: [
              RuleStamp(
                ruleId: rule.id,
                color: p.signal,
                onTap: () => _showRationale(context, rule, decision),
              ),
              if (rule.deficit != null) ...[
                const SizedBox(width: Space.sm),
                Text(rule.deficit!,
                    style: monoStyle(context, size: 11, color: p.inkFaint)),
              ],
            ],
          ),
          const SizedBox(height: Space.xl),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () async {
                    final runtime = await ref.read(runtimeProvider.future);
                    if (isCheckin && context.mounted) {
                      final done = await showCheckinSheet(context,
                          slot: rule.then.params['slot'] as String? ?? 'manual');
                      if (!done) return;
                    }
                    await runtime.respondTo(decision, DecisionResponse.followed);
                    refreshAxiom(ref);
                  },
                  child: Text(isCheckin
                      ? context.t('Check-in machen')
                      : context.t('Verstanden')),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final runtime = await ref.read(runtimeProvider.future);
                    await runtime.respondTo(decision, DecisionResponse.deferred);
                    refreshAxiom(ref);
                  },
                  child: Text(context.t('Später')),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Center(
            child: TextButton(
              onPressed: () async {
                final runtime = await ref.read(runtimeProvider.future);
                await runtime.respondTo(decision, DecisionResponse.rejected);
                refreshAxiom(ref);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          context.t('Notiert. Diese Regel meldet sich seltener.')),
                    ),
                  );
                }
              },
              child: Text(context.t('Passt nicht')),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends ConsumerWidget {
  final Task task;

  /// Die Regel, die das ausgeloest hat — falls es eine gab.
  final Rule? rule;

  const _TaskCard({required this.task, this.rule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    return Panel(
      accent: p.signal.withValues(alpha: 0.55),
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t('JETZT'), style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Space.md),
          Text(task.title, style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: Space.lg),
          Row(
            children: [
              _Chip(label: context.t('START {0}/10', [task.activationEnergy]), color: p.signal),
              const SizedBox(width: Space.sm),
              if (rule != null) ...[
                RuleStamp(ruleId: rule!.id, color: p.info),
                const SizedBox(width: Space.sm),
              ],
              if (task.decayAt != null)
                _Chip(
                  label: _until(context, task.decayAt!, ref.watch(nowProvider)),
                  color: p.info,
                ),
              // Ohne gesetzten Ort wird eine ortsgebundene Aufgabe nicht
              // unterdrückt — sie steht mit ihrem Ort da. Etwas zu
              // verstecken, das der Nutzer nie eingeschaltet hat, wäre der
              // schlimmere Fehler [D9].
              if (task.place != null) ...[
                const SizedBox(width: Space.sm),
                _Chip(label: task.place!.toUpperCase(), color: p.inkDim),
              ],
            ],
          ),
          const SizedBox(height: Space.xl),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () async {
                    final runtime = await ref.read(runtimeProvider.future);
                    await runtime.startTask(task);
                    await HapticFeedback.mediumImpact();
                    refreshAxiom(ref);
                  },
                  child: Text(context.t('Anfangen')),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final runtime = await ref.read(runtimeProvider.future);
                    await runtime.completeTask(task);
                    await HapticFeedback.mediumImpact();
                    refreshAxiom(ref);
                  },
                  child: Text(context.t('Erledigt')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _until(BuildContext context, DateTime when, DateTime now) {
    final diff = when.difference(now);
    if (diff.isNegative) return context.t('ÜBERFÄLLIG');
    if (diff.inHours < 24) return context.t('IN {0} H', [diff.inHours]);
    return context.t('IN {0} T', [diff.inDays]);
  }
}

/// Wichtig, aber außer Reichweite. Statt anzumahnen wird zerlegt.
///
/// Das ist der Bruch mit dem üblichen Muster: Andere Apps zeigen die Aufgabe
/// weiter oben an und markieren sie irgendwann rot. Beides macht den Start
/// unwahrscheinlicher, weil Schuld die Regulationsreserve senkt [D2, D10].
class _AtomizeCard extends ConsumerWidget {
  final AtomizeCandidate candidate;

  /// Die Regel, die das ausgeloest hat — falls es eine gab.
  final Rule? rule;

  const _AtomizeCard({required this.candidate, this.rule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    return Panel(
      accent: p.info.withValues(alpha: 0.5),
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(context.t('ZU GROSS FÜR HEUTE'),
                    style: Theme.of(context).textTheme.labelSmall),
              ),
              if (rule != null) RuleStamp(ruleId: rule!.id, color: p.info),
            ],
          ),
          const SizedBox(height: Space.md),
          Text(candidate.task.title,
              style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: Space.lg),
          Text(candidate.explanation,
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: Space.xl),
          FilledButton(
            onPressed: () async {
              final done = await showAtomizeSheet(context, candidate);
              if (done) refreshAxiom(ref);
            },
            child: Text(context.t('In einen ersten Schritt zerlegen')),
          ),
          const SizedBox(height: Space.sm),
          Center(
            child: TextButton(
              onPressed: () async {
                final runtime = await ref.read(runtimeProvider.future);
                await runtime.dropTask(candidate.task);
                refreshAxiom(ref);
              },
              child: Text(context.t('Fällt weg')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Leerzustand. Fuehrt zur naechsten Handlung, statt Leere zu zeigen.
class _EmptyState extends ConsumerWidget {
  final AxiomSnapshot snapshot;
  const _EmptyState({required this.snapshot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    final hasTasks = snapshot.tasks.any((t) => t.state == TaskState.ready);
    final blocked = hasTasks && snapshot.startable.isEmpty;
    // Wartet alles Offene auf etwas anderes, ist die Begründung eine andere:
    // Nicht die Startenergie hält zurück, sondern eine Abhängigkeit. Den
    // falschen Grund zu nennen ist schlimmer als keinen (G2).
    final waiting = blocked &&
        snapshot.waiting.isNotEmpty &&
        snapshot.waiting.length ==
            snapshot.tasks.where((t) => t.state == TaskState.ready).length;

    return Panel(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              waiting
                  ? context.t('ALLES WARTET')
                  : blocked
                      ? context.t('NICHTS IN REICHWEITE')
                      : context.t('NICHTS ANLIEGEND'),
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Space.md),
          Text(
            waiting
                ? context.t('Alles Offene hängt an etwas anderem.')
                : blocked
                    ? context.t('Heute liegt nichts unter der Linie.')
                    : context.t('Ruhig gerade.'),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: Space.md),
          Text(
            waiting
                ? context.t('Jede offene Aufgabe wartet auf einen Blocker, der selbst noch aussteht. Die Aufgabenliste zeigt, worauf.')
                : blocked
                    ? context.t('Alles Offene braucht mehr Anlauf, als heute da ist. Das ist eine Messung, keine Bewertung. Eine Aufgabe in kleinere Schritte zu zerlegen hilft mehr als Anlauf nehmen.')
                    : context.t('Kein Vorschlag heißt: gerade ist nichts nötig. Was dir einfällt, kannst du unten erfassen.'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (blocked) ...[
            const SizedBox(height: Space.lg),
            // Ziel ist die Aufgabenliste, nicht der Eingang: Dort steht,
            // was außer Reichweite liegt, und dort führt jede Zeile ihren
            // eigenen Weg ins Zerlegen. Der Eingang enthält Erfasstes —
            // dort war nichts zu zerlegen, und der Weg endete im Nichts.
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const TasksScreen()),
              ),
              icon: Icon(waiting ? Icons.link : Icons.call_split,
                  size: 18, color: p.signal),
              label: Text(waiting
                  ? context.t('Ansehen, was wartet')
                  : context.t('Aufgabe zerlegen')),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Nebenelemente ───────────────────────────────────────────────────────

/// Die geltende Last-Stufe, wenn sie über L0 liegt (M9).
///
/// Steht ganz oben, weil sie alles darunter verändert: Was vorgeschlagen
/// wird, wie lang Fokusblöcke sein dürfen, ob Optionales überhaupt
/// erscheint. Eine Einschränkung, deren Grund man nicht sieht, wirkt
/// willkürlich (G2).
class _RegimeBanner extends StatelessWidget {
  final AxiomSnapshot snapshot;
  const _RegimeBanner({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final regime = snapshot.regime;
    final color = p.forLoadLevel(regime.level.index);

    return Panel(
      accent: color.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Space.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(Radii.control),
                ),
                child: Text(regime.level.name.toUpperCase(),
                    style: monoStyle(context,
                        size: 11, weight: FontWeight.w600, color: color)),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(context.t(regime.headline),
                    style: Theme.of(context).textTheme.titleLarge),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Text(context.t(regime.description),
              style: Theme.of(context).textTheme.bodyMedium),
          if (snapshot.suggestsReferral) ...[
            const SizedBox(height: Space.md),
            Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                border: Border.all(color: p.rule),
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              child: Text(
                context.t('Die Last ist seit über zwei Wochen auf diesem Niveau. AXIOM misst nur — für die Einordnung ist ärztliche oder psychotherapeutische Abklärung der richtige Weg.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Laufender Fokusblock mit dem Urteil des Governors (M4).
class _FocusStrip extends ConsumerWidget {
  final AxiomSnapshot snapshot;
  const _FocusStrip({required this.snapshot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    final session = snapshot.focus!;
    final verdict = snapshot.focusVerdict;
    final elapsed = session.elapsed(ref.watch(nowProvider));
    final urgent = verdict?.action == FocusAction.hardStop ||
        verdict?.action == FocusAction.clearInterrupt;

    return Panel(
      accent: (urgent ? p.signal : p.calm).withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(
          horizontal: Space.lg, vertical: Space.md),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const FocusScreen()),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(
              color: urgent ? p.signal : p.calm,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.anchorTitle ?? context.t('Fokus läuft'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge),
                Text(
                  verdict == null
                      ? context.t('Läuft.')
                      : context.p(verdict.reason),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          Text(context.t('{0} min', [elapsed.inMinutes]),
              style: monoStyle(context,
                  size: 13,
                  weight: FontWeight.w600,
                  color: urgent ? p.signal : p.inkDim)),
        ],
      ),
    );
  }
}

/// Der gesetzte Ort — eine Zeile, ein Tipp.
///
/// Kein eigener Bildschirm und keine Ortsverwaltung: Der Ort ist ein
/// Schalter, kein Datensatz. Ein Tipp öffnet die Auswahl, ein zweiter setzt
/// ihn — „kein Ort" steht dort immer an erster Stelle, und der zuletzt
/// gesetzte gleich darunter.
class _PlaceStrip extends ConsumerWidget {
  final AxiomSnapshot snapshot;
  const _PlaceStrip({required this.snapshot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    final place = snapshot.place;
    final elsewhere = snapshot.elsewhere.length;

    return Panel(
      padding: const EdgeInsets.symmetric(
          horizontal: Space.lg, vertical: Space.md),
      onTap: () => showPlaceSheet(
        context,
        current: place,
        known: snapshot.knownPlaces,
      ),
      child: Row(
        children: [
          Icon(
            place == null ? Icons.place_outlined : Icons.place,
            size: 18,
            color: place == null ? p.inkDim : p.signal,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(place ?? context.t('Kein Ort'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge),
                Text(
                  // Zustandsbeschreibung, keine Bewertung: Was der Filter
                  // gerade tut, steht da — nicht, was man tun sollte [R7].
                  place == null
                      ? context.t('Alles steht zur Auswahl.')
                      : elsewhere == 0
                          ? context.t('Nichts liegt woanders.')
                          : elsewhere == 1
                              ? context.t('Eine Aufgabe gehört woanders hin.')
                              : context.t('{0} Aufgaben gehören woanders hin.',
                                  [elsewhere]),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: p.inkFaint),
        ],
      ),
    );
  }
}

/// Laufende Wartezeit eines Impuls-Abfangs (M6).
class _InterceptStrip extends ConsumerWidget {
  final InterceptRun run;
  const _InterceptStrip({required this.run});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    final now = ref.watch(nowProvider);
    final released = !run.isActive(now);

    return Panel(
      accent: p.signal.withValues(alpha: 0.55),
      padding: const EdgeInsets.symmetric(
          horizontal: Space.lg, vertical: Space.md),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const InterceptScreen()),
      ),
      child: Row(
        children: [
          Icon(released ? Icons.lock_open : Icons.hourglass_bottom,
              size: 18, color: p.signal),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(run.triggerLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge),
                Text(
                  released ? context.t('Wartezeit vorbei') : context.t('Wartezeit läuft'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (!released)
            Text(context.t('{0} min', [run.remaining(now).inMinutes]),
                style: monoStyle(context,
                    size: 13, weight: FontWeight.w600, color: p.signal)),
        ],
      ),
    );
  }
}

/// Zugang zu Fokus, Reiz und Bremse.
///
/// Bewusst als Leiste statt als eigene Navigationsreiter: Drei Ziele in der
/// Navigation, nicht sechs. Jeder weitere Reiter ist eine Entscheidung, die
/// vor dem eigentlichen Tun steht (G1).
class _Tools extends StatelessWidget {
  final AxiomSnapshot snapshot;
  const _Tools({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final need = snapshot.state.sensationNeed;

    return Row(
      children: [
        _ToolButton(
          icon: Icons.center_focus_strong_outlined,
          label: snapshot.isFocusing ? context.t('Läuft') : 'Fokus',
          active: snapshot.isFocusing,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const FocusScreen()),
          ),
        ),
        const SizedBox(width: Space.sm),
        _ToolButton(
          icon: Icons.bolt_outlined,
          label: context.t('Reiz'),
          // Auffällig nur, wenn der Bedarf wirklich hoch ist — ein dauerhaft
          // markierter Knopf wird nicht mehr gesehen.
          active: need >= 70,
          activeColor: p.caution,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SensationScreen()),
          ),
        ),
        const SizedBox(width: Space.sm),
        _ToolButton(
          icon: Icons.pan_tool_outlined,
          label: context.t('Bremse'),
          active: snapshot.activeIntercept != null,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const InterceptScreen()),
          ),
        ),
      ],
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color? activeColor;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final color = active ? (activeColor ?? p.signal) : p.inkDim;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 62,
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.14) : p.panel,
            borderRadius: BorderRadius.circular(Radii.control),
            border: Border.all(color: active ? color : p.rule),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(height: 3),
              Text(label,
                  style: monoStyle(context,
                      size: 10, spacing: 0.4, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Der nächste Ankerschritt, direkt unter dem Datum.
///
/// Steht bewusst über allem anderen: Ein Schritt mit Uhrzeit ist die einzige
/// Sache auf diesem Screen, die durch Warten teurer wird [D4].
class _AnchorStrip extends ConsumerWidget {
  final ({Anchor anchor, AnchorStep step}) next;
  const _AnchorStrip({required this.next});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    final now = ref.watch(nowProvider);
    final minutes = next.step.at.difference(now).inMinutes;
    final near = minutes <= 20;

    return Panel(
      accent: near ? p.signal.withValues(alpha: 0.5) : null,
      padding: const EdgeInsets.symmetric(
          horizontal: Space.lg, vertical: Space.md),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const AnchorsScreen()),
      ),
      child: NextStepBadge(
        anchor: next.anchor,
        step: next.step,
        now: now,
      ),
    );
  }
}

/// Bietet eine faellige Nachbetrachtung an.
///
/// Erscheint fruehestens zwoelf Stunden nach dem Vorfall — vorher ist
/// niemand analysefaehig, und die Aufforderung verlaengert das Ereignis [D10].
class _PostMortemTeaser extends ConsumerWidget {
  const _PostMortemTeaser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingPostMortemsProvider).value ?? const [];
    if (pending.isEmpty) return const SizedBox.shrink();
    final p = context.axiom;

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Panel(
        padding: const EdgeInsets.symmetric(
            horizontal: Space.lg, vertical: Space.md),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SignalScreen()),
        ),
        child: Row(
          children: [
            Icon(Icons.history_toggle_off, size: 18, color: p.inkDim),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(
                pending.length == 1
                    ? context.t('Ein Vorfall wartet auf Einordnung')
                    : context.t('{0} Vorfälle warten auf Einordnung', [pending.length]),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: p.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// Meldet, wenn die Baseline vollständig ist.
///
/// Ohne diesen Hinweis müsste man selbst daran denken — und genau darauf
/// kann sich dieses Profil nicht verlassen [D12].
class _BaselineTeaser extends ConsumerWidget {
  const _BaselineTeaser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseline = ref.watch(baselineProvider).value;
    if (baseline == null || !baseline.isReady) return const SizedBox.shrink();
    final p = context.axiom;

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Panel(
        accent: p.signal.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(
            horizontal: Space.lg, vertical: Space.md),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SystemScreen()),
        ),
        child: Row(
          children: [
            Icon(Icons.tune, size: 18, color: p.signal),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.t('Baseline vollständig'),
                      style: Theme.of(context).textTheme.bodyLarge),
                  Text(context.t('Die Gewichte können jetzt geeicht werden.'),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: p.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// Bietet ein fälliges Review an, ohne zu drängen.
class _ReviewTeaser extends ConsumerWidget {
  const _ReviewTeaser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = ref.watch(dueReviewProvider).value;
    if (due == null) return const SizedBox.shrink();
    final p = context.axiom;

    return Panel(
      padding: const EdgeInsets.symmetric(
          horizontal: Space.lg, vertical: Space.md),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReviewScreen(scope: due),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.checklist_outlined, size: 18, color: p.inkDim),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              context.t('{0}-Review offen · {1} min', [due.label, due.timeCap.inMinutes]),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: p.inkFaint),
        ],
      ),
    );
  }
}

class _InboxTeaser extends StatelessWidget {
  final int count;
  const _InboxTeaser({required this.count});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Panel(
      padding: const EdgeInsets.symmetric(
          horizontal: Space.lg, vertical: Space.md),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const InboxScreen()),
      ),
      child: Row(
        children: [
          Icon(Icons.inbox_outlined, size: 18, color: p.inkDim),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              context.t('{0} {1} auf Sortieren', [count, count == 1 ? context.t('Notiz wartet') : context.t('Notizen warten')]),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: p.inkFaint),
        ],
      ),
    );
  }
}

class _QuickState extends StatelessWidget {
  final AxiomSnapshot snapshot;
  const _QuickState({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final s = snapshot.state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(context.t('Zustand')),
        Panel(
          child: Column(
            children: [
              InstrumentBar(
                label: context.t('Kapazität'),
                value: s.capacity,
                color: p.signal,
                reading: _capacityReading(context, s.capacity),
                breakdown: snapshot.breakdown['capacity'] ?? const [],
                confidence: s.confidenceOf('capacity'),
              ),
              Divider(color: p.rule, height: Space.xl),
              InstrumentBar(
                label: context.t('Kompensationslast'),
                value: s.loadIndex,
                color: p.forLoadLevel(s.loadLevel.index),
                reading: _loadReading(context, s.loadLevel),
                breakdown: snapshot.breakdown['load_index'] ?? const [],
                confidence: s.confidenceOf('load_index'),
              ),
              Divider(color: p.rule, height: Space.xl),
              InstrumentBar(
                label: context.t('Reizbedarf'),
                value: s.sensationNeed,
                color: p.caution,
                reading: _sensationReading(context, s.sensationNeed),
                breakdown: snapshot.breakdown['sensation_need'] ?? const [],
                confidence: s.confidenceOf('sensation_need'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _capacityReading(BuildContext context, int v) => switch (v) {
        >= 75 => context.t('Viel möglich heute.'),
        >= 50 => context.t('Solide Mitte.'),
        >= 30 => context.t('Begrenzt — Kleines zuerst.'),
        _ => context.t('Wenig da. Nur das Nötige.'),
      };

  static String _loadReading(BuildContext context, LoadLevel level) =>
      switch (level) {
        LoadLevel.l0 => context.t('Im Normalbereich.'),
        LoadLevel.l1 => context.t('Erhöht. Im Blick behalten.'),
        LoadLevel.l2 => context.t('Kritisch. Nichts Neues aufnehmen.'),
        LoadLevel.l3 => context.t('Erhaltungsmodus. Nur Pflicht und Erholung.'),
      };

  static String _sensationReading(BuildContext context, int v) => switch (v) {
        >= 85 => context.t('Hoch. Jetzt planen, was sonst ungeplant passiert.'),
        >= 70 => context.t('Deutlich. Ein Reiz-Slot wäre fällig.'),
        >= 40 => context.t('Normal.'),
        _ => context.t('Gedeckt.'),
      };
}

/// Zeigt das Meta-Work-Budget. Die App macht ihre eigenen Kosten sichtbar —
/// wenn sie mehr Zeit frisst als sie spart, ist sie das Problem (M12).
class _MetaBudget extends StatelessWidget {
  final Duration used;
  const _MetaBudget({required this.used});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final ratio = (used.inSeconds / kMetaBudget.inSeconds).clamp(0.0, 1.0);
    final over = used >= kMetaBudget;

    return Row(
      children: [
        Text(context.t('ZEIT IN AXIOM HEUTE'),
            style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(width: Space.md),
        Expanded(
          child: Stack(
            children: [
              Container(height: 2, color: p.rule),
              LayoutBuilder(
                builder: (context, c) => Container(
                  height: 2,
                  width: c.maxWidth * ratio,
                  color: over ? p.caution : p.inkFaint,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: Space.md),
        Text(context.t('{0}/{1} min', [used.inMinutes, kMetaBudget.inMinutes]),
            style: monoStyle(context,
                size: 11, color: over ? p.caution : p.inkFaint)),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Space.sm, vertical: Space.xs),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        child: Text(label,
            style: monoStyle(context,
                size: 10.5, weight: FontWeight.w500, color: color)),
      );
}

class _ErrorPane extends StatelessWidget {
  final Object error;
  const _ErrorPane({required this.error});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.t('SYSTEM'), style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.md),
            Text(context.t('AXIOM konnte nicht starten.'),
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: Space.md),
            Text('$error', style: monoStyle(context, size: 12)),
          ],
        ),
      );
}

void _showRationale(BuildContext context, Rule rule, Decision decision) {
  showDialog<void>(
    context: context,
    builder: (context) {
      final p = context.axiom;
      return AlertDialog(
        title: Row(
          children: [
            RuleStamp(ruleId: rule.id, color: p.signal),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(context.ruleTitle(rule),
                  style: Theme.of(context).textTheme.titleMedium),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.t('WARUM ES DIESE REGEL GIBT'),
                  style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: Space.sm),
              Text(decision.explanation,
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: Space.lg),
              Row(
                children: [
                  Text(context.t('Stufe {0}', [rule.severity.name]),
                      style: monoStyle(context, size: 11)),
                  const SizedBox(width: Space.md),
                  Text(context.t('Priorität {0}', [rule.priority]),
                      style: monoStyle(context, size: 11)),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('Schließen')),
          ),
        ],
      );
    },
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Die laufende Aufgabe, während eine Regel die Hauptkarte belegt.
///
/// Schmal und ohne Knöpfe: Sie ist hier kein Angebot, sondern eine
/// Erinnerung daran, dass etwas offen ist. Der Tipp führt zur Liste, wo sie
/// sich abschließen lässt.
class _RunningStrip extends ConsumerWidget {
  final Task task;
  const _RunningStrip({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    return Panel(
      accent: p.calm.withValues(alpha: 0.5),
      padding:
          const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const TasksScreen()),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(
              color: p.calm,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.t('LÄUFT'),
                    style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 2),
                Text(task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          Icon(Icons.chevron_right, size: 18, color: p.inkFaint),
        ],
      ),
    );
  }
}
