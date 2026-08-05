/// Alle Aufgaben — der Überblick, den „Jetzt" bewusst nicht gibt.
///
/// **Warum es das gibt, obwohl G1 keine Liste zur Auswahl erlaubt.** Das
/// Gesetz verbietet, die Entscheidung *im Moment* an eine Liste zu delegieren
/// — nicht, den Bestand zu kennen. Beides sind verschiedene Tätigkeiten:
/// Planen ist etwas anderes als Entscheiden, und wer nie sieht, was
/// eingetragen ist, vertraut dem System nicht (D9). Was ohne diese Ansicht
/// passiert, ist absehbar: Man führt daneben eine zweite Liste im Kopf.
///
/// **Was sie deshalb nicht ist.** Nicht der Startbildschirm, nicht der Weg,
/// über den normalerweise gearbeitet wird, und ohne Sortierregler,
/// Filterleiste oder Ansichtswechsel — das wäre Meta-Work mit Aussicht (D3).
/// Die Reihenfolge ist die des Systems, dieselbe wie bei der Auswahl, und
/// sie ist nicht verstellbar.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/widgets/instruments.dart';
import '../i18n/i18n.dart';
import '../state/meta_time.dart';
import '../state/providers.dart';
import '../state/runtime.dart';
import 'atomize_sheet.dart';

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(snapshotProvider);

    return MetaTimedScope(
      screen: 'tasks',
      child: Scaffold(
      appBar: AppBar(title: Text(context.t('Aufgaben'))),
      body: snapshot.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (snap) => _Body(snapshot: snap),
      ),
    ),
    );
  }
}

class _Body extends ConsumerWidget {
  final AxiomSnapshot snapshot;
  const _Body({required this.snapshot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capacity = snapshot.state.capacity;
    final at = snapshot.at;
    final place = snapshot.place;

    List<Task> sorted(bool Function(Task) test) => snapshot.tasks
        .where(test)
        .toList()
      ..sort((a, b) => taskScore(b, at).compareTo(taskScore(a, at)));

    final running = sorted((t) => t.state == TaskState.active);
    final reachable = sorted((t) =>
        t.state == TaskState.ready && t.isStartable(capacity, atPlace: place));
    // Eigener Abschnitt statt „nicht in Reichweite": Der Grund ist ein
    // anderer, und die Begründung darunter wäre schlicht falsch — die
    // Startenergie hat damit nichts zu tun. Die Menge kommt aus dem
    // Snapshot, damit „woanders" nur einmal definiert ist.
    final elsewhere = snapshot.elsewhere;
    final outOfReach = sorted((t) =>
        t.state == TaskState.ready &&
        t.isHere(place) &&
        !t.isStartable(capacity));
    // Zerlegte Aufgaben standen hier bisher nirgends. Damit war die
    // Klammer nach dem Zerlegen unsichtbar: nicht auffindbar, nicht
    // abschließbar, nicht weiter zerlegbar — und wer seinen Bestand nicht
    // sieht, führt daneben eine zweite Liste im Kopf [D9].
    final split = sorted((t) => t.state == TaskState.blocked);
    final done = sorted((t) => t.state == TaskState.done);

    /// Wie viele Teilschritte einer Aufgabe stehen noch aus?
    int openSteps(Task parent) => snapshot.tasks
        .where((t) => t.parentId == parent.id && isTaskOpen(t))
        .length;

    if (snapshot.tasks.every((t) =>
        t.state != TaskState.active &&
        t.state != TaskState.ready &&
        t.state != TaskState.blocked &&
        t.state != TaskState.done)) {
      return const _Empty();
    }

    return ListView(
      padding:
          const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.huge),
      children: [
        Text(
          context.t('Die Reihenfolge ist die der Auswahl — dieselbe Formel, kein zweiter Maßstab. Sie lässt sich hier nicht umstellen.'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: Space.xl),

        if (running.isNotEmpty) ...[
          SectionLabel(context.t('Läuft')),
          for (final task in running) _Row(task: task, capacity: capacity),
          const SizedBox(height: Space.xl),
        ],

        if (reachable.isNotEmpty) ...[
          SectionLabel(context.t('In Reichweite · {0}', [reachable.length])),
          for (final task in reachable)
            _Row(task: task, capacity: capacity, place: place),
          const SizedBox(height: Space.xl),
        ],

        if (elsewhere.isNotEmpty) ...[
          SectionLabel(context.t('Anderswo · {0}', [elsewhere.length])),
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Text(
              context.t('Gehört zu einem anderen Ort als „{0}". Sie kommen zurück, sobald der Ort passt oder keiner gesetzt ist.', [place ?? '']),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (final task in elsewhere)
            _Row(task: task, capacity: capacity, place: place),
          const SizedBox(height: Space.xl),
        ],

        if (outOfReach.isNotEmpty) ...[
          // Kein „außer" im Versalsatz: Das ß hat dort keine korrekte Form,
          // und die längere Fassung wurde ohnehin abgeschnitten.
          SectionLabel(
              context.t('Nicht in Reichweite · {0}', [outOfReach.length])),
          // Kein Vorwurf, eine Messung: Die Startenergie liegt über dem, was
          // die heutige Kapazität trägt. Morgen kann das anders sein [R7].
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Text(
              context.t('Startenergie über der heutigen Kapazität ({0}). Zerlegen macht sie erreichbar.', [capacity]),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (final task in outOfReach)
            _Row(task: task, capacity: capacity, place: place),
          const SizedBox(height: Space.xl),
        ],

        if (split.isNotEmpty) ...[
          SectionLabel(context.t('Zerlegt · {0}', [split.length])),
          // Keine Mahnung, eine Einordnung: Die Aufgabe ist durch ihre
          // Schritte vertreten, deshalb steht sie nicht bei der Auswahl.
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Text(
              context.t('Diese Aufgaben sind durch ihre Teilschritte vertreten. Sie kommen zurück, sobald kein Schritt mehr offen ist.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (final task in split)
            _Row(
              task: task,
              capacity: capacity,
              place: place,
              openSteps: openSteps(task),
            ),
          const SizedBox(height: Space.xl),
        ],

        if (done.isNotEmpty) ...[
          SectionLabel(context.t('Erledigt · {0}', [done.length])),
          for (final task in done.take(20))
            _Row(task: task, capacity: capacity, place: place),
        ],
      ],
    );
  }
}

class _Row extends ConsumerWidget {
  final Task task;
  final int capacity;

  /// Der gerade gesetzte Ort. Null heisst: keiner, dann bindet nichts.
  final String? place;

  /// Offene Teilschritte — nur bei zerlegten Aufgaben gesetzt.
  final int openSteps;

  const _Row({
    required this.task,
    required this.capacity,
    this.place,
    this.openSteps = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    final now = ref.watch(nowProvider);
    final running = task.state == TaskState.active;
    final done = task.state == TaskState.done;
    final split = task.state == TaskState.blocked;
    final reachable = task.isStartable(capacity, atPlace: place);
    final here = task.isHere(place);
    // Der Anlauf steht nur da, wenn er nicht mehr passt. Eine Zahl, die immer
    // da ist, wird nicht gelesen — und die Formel ist genau dann interessant,
    // wenn sie etwas aussagt (G2).
    final runway = task.decayAt == null || done
        ? null
        : taskRunway(task) > task.decayAt!.difference(now)
            ? taskRunway(task)
            : null;

    final accent = switch (true) {
      _ when running => p.calm,
      _ when done => p.rule,
      _ when reachable => p.signal,
      _ => p.rule,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Panel(
        accent: running ? p.calm.withValues(alpha: 0.5) : null,
        padding: const EdgeInsets.symmetric(
            horizontal: Space.lg, vertical: Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 3,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(
                              decoration:
                                  done ? TextDecoration.lineThrough : null,
                              color: done ? p.inkFaint : null,
                            ),
                      ),
                      const SizedBox(height: Space.xs),
                      Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.xs,
                        children: [
                          Text(
                            context.t('Start {0}/10', [task.activationEnergy]),
                            style: monoStyle(context,
                                size: 10.5,
                                color: reachable && !done ? p.calm : p.inkFaint),
                          ),
                          if (task.decayAt != null)
                            Text(
                              _deadline(context, task.decayAt!, now),
                              style: monoStyle(context,
                                  size: 10.5,
                                  color: task.decayAt!.isBefore(now)
                                      ? p.caution
                                      : p.inkFaint),
                            ),
                          if (runway != null)
                            Text(
                              context.t('ANLAUF {0} H',
                                  [hoursOf(runway).toStringAsFixed(1)]),
                              style: monoStyle(context,
                                  size: 10.5, color: p.caution),
                            ),
                          if (task.place != null)
                            Text(
                              task.place!.toUpperCase(),
                              style: monoStyle(context,
                                  size: 10.5,
                                  color: here ? p.inkFaint : p.info),
                            ),
                          if (split)
                            Text(
                              context.t('SCHRITTE OFFEN: {0}', [openSteps]),
                              style: monoStyle(context,
                                  size: 10.5, color: p.info),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!done) ...[
              const SizedBox(height: Space.md),
              Row(
                children: [
                  if (running) ...[
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _act(ref, (r) => r.completeTask(task)),
                        child: Text(context.t('Erledigt')),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _act(ref, (r) => r.releaseTask(task)),
                        child: Text(context.t('Zurücklegen')),
                      ),
                    ),
                  ] else if (split) ...[
                    // Kein „Anfangen": Die Aufgabe ist durch ihre Schritte
                    // vertreten, und sie neben ihnen zur Wahl zu stellen
                    // wäre genau die Doppelung, die das Zerlegen auflöst.
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _act(ref, (r) => r.completeTask(task)),
                        child: Text(context.t('Erledigt')),
                      ),
                    ),
                  ] else ...[
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () => _act(ref, (r) => r.startTask(task)),
                        child: Text(context.t('Anfangen')),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _act(ref, (r) => r.completeTask(task)),
                        child: Text(context.t('Erledigt')),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: Space.sm),
              // Zerlegen geht immer und auf jeder Ebene — auch bei einem
              // Teilschritt, der sich als immer noch zu groß herausstellt,
              // und auch bei einer Aufgabe, die AXIOM von sich aus nicht
              // angeboten hätte. Die Hürde liegt am Anfang; wo sie liegt,
              // weiß nur der Nutzer [D2].
              OutlinedButton.icon(
                onPressed: () => _splitIt(context, ref),
                icon: Icon(Icons.call_split, size: 18, color: p.signal),
                label: Text(context.t('Zerlegen')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Oeffnet das Zerlegen-Blatt fuer genau diese Aufgabe.
  Future<void> _splitIt(BuildContext context, WidgetRef ref) async {
    final runtime = await ref.read(runtimeProvider.future);
    final candidate = await runtime.atomizeCandidateFor(task);
    if (!context.mounted) return;
    await showAtomizeSheet(context, candidate);
    refreshAxiom(ref);
  }

  Future<void> _act(
    WidgetRef ref,
    Future<void> Function(AxiomRuntime) action,
  ) async {
    final runtime = await ref.read(runtimeProvider.future);
    await action(runtime);
    await HapticFeedback.mediumImpact();
    refreshAxiom(ref);
  }

  /// Verfallszeitpunkt in Worten. Kein Ausrufezeichen, keine Mahnung —
  /// überfällig ist eine Tatsache, kein Vorwurf [R7].
  static String _deadline(BuildContext context, DateTime when, DateTime now) {
    final diff = when.difference(now);
    if (diff.isNegative) return context.t('ÜBERFÄLLIG');
    if (diff.inHours < 24) return context.t('IN {0} H', [diff.inHours]);
    return context.t('IN {0} T', [diff.inDays]);
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => EmptyState(
        label: context.t('NICHTS EINGETRAGEN'),
        headline: context.t('Keine Aufgaben.'),
        body: context.t('Was du erfasst, landet zuerst im Eingang. Nach dem Sortieren steht es hier.'),
      );
}
