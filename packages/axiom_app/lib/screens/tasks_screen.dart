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
import '../state/providers.dart';
import '../state/runtime.dart';

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(snapshotProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.t('Aufgaben'))),
      body: snapshot.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (snap) => _Body(snapshot: snap),
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

    List<Task> sorted(bool Function(Task) test) => snapshot.tasks
        .where(test)
        .toList()
      ..sort((a, b) => taskScore(b, at).compareTo(taskScore(a, at)));

    final running = sorted((t) => t.state == TaskState.active);
    final reachable =
        sorted((t) => t.state == TaskState.ready && t.isStartable(capacity));
    final outOfReach =
        sorted((t) => t.state == TaskState.ready && !t.isStartable(capacity));
    final done = sorted((t) => t.state == TaskState.done);

    if (snapshot.tasks.every((t) =>
        t.state != TaskState.active &&
        t.state != TaskState.ready &&
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
          for (final task in reachable) _Row(task: task, capacity: capacity),
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
          for (final task in outOfReach) _Row(task: task, capacity: capacity),
          const SizedBox(height: Space.xl),
        ],

        if (done.isNotEmpty) ...[
          SectionLabel(context.t('Erledigt · {0}', [done.length])),
          for (final task in done.take(20))
            _Row(task: task, capacity: capacity),
        ],
      ],
    );
  }
}

class _Row extends ConsumerWidget {
  final Task task;
  final int capacity;
  const _Row({required this.task, required this.capacity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    final now = ref.watch(nowProvider);
    final running = task.state == TaskState.active;
    final done = task.state == TaskState.done;
    final reachable = task.isStartable(capacity);

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
            ],
          ],
        ),
      ),
    );
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: Space.huge),
            Text(context.t('NICHTS EINGETRAGEN'),
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.md),
            Text(context.t('Keine Aufgaben.'),
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: Space.md),
            Text(
              context.t('Was du erfasst, landet zuerst im Eingang. Nach dem Sortieren steht es hier.'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
}
