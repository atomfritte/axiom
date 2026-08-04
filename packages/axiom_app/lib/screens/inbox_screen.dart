/// Eingang — Triage von erfassten Notizen zu Aufgaben.
///
/// Getrennt von der Erfassung, weil beides unterschiedliche Zustaende
/// braucht: Erfassen passiert im Impuls und muss null Reibung haben.
/// Sortieren passiert bewusst und darf Fragen stellen.
///
/// Gefragt wird nur nach dem, was der Algorithmus wirklich braucht:
/// Wie schwer faellt der Start, und was kostet es, wenn es liegenbleibt.
/// Nach "Prioritaet" wird nicht gefragt — die Achse fuehrt in die Irre. [D2]
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/widgets/instruments.dart';
import '../state/providers.dart';
import '../i18n/i18n.dart';

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(inboxProvider);
    final tasks = ref.watch(snapshotProvider).value?.tasks ?? const [];
    final open = tasks.where((t) => t.state == TaskState.ready).toList();

    return Scaffold(
      appBar: AppBar(title: Text(context.t('Eingang'))),
      body: inbox.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (notes) => ListView(
          padding: const EdgeInsets.fromLTRB(
              Space.lg, Space.sm, Space.lg, Space.huge),
          children: [
            if (notes.isEmpty && open.isEmpty)
              const _EmptyInbox()
            else ...[
              if (notes.isNotEmpty) ...[
                SectionLabel(context.t('Unsortiert · {0}', [notes.length])),
                for (final note in notes)
                  _NoteCard(
                    note: note,
                    onTriage: () => _triage(context, ref, note),
                    onDismiss: () async {
                      final runtime = await ref.read(runtimeProvider.future);
                      await runtime.record(EventType.taskAbandoned, payload: {
                        'from_capture': note.id,
                        'reason': 'dismissed',
                      });
                      refreshAxiom(ref);
                    },
                  ),
                const SizedBox(height: Space.xl),
              ],
              if (open.isNotEmpty) ...[
                SectionLabel(context.t('Offen · {0}', [open.length])),
                for (final task in open) _TaskRow(task: task),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _triage(BuildContext context, WidgetRef ref, Event note) async {
    final text = note.payload['text'] as String? ?? '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TriageSheet(text: text, captureId: note.id),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Space.huge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.t('EINGANG LEER'),
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.md),
            Text(context.t('Nichts zu sortieren.'),
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: Space.md),
            Text(
              context.t('Was dir zwischendurch einfällt, landet hier. Erfassen kannst du von überall — über den Knopf unten, die Schnelleinstellung oder den S-Pen.'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
}

class _NoteCard extends StatelessWidget {
  final Event note;
  final VoidCallback onTriage;
  final VoidCallback onDismiss;

  const _NoteCard({
    required this.note,
    required this.onTriage,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final at = note.at.toLocal();
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Dismissible(
        key: ValueKey(note.id),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => onDismiss(),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: Space.lg),
          decoration: BoxDecoration(
            color: p.panel,
            borderRadius: BorderRadius.circular(Radii.panel),
          ),
          child: Text(context.t('Verwerfen'),
              style: monoStyle(context, size: 12, color: p.inkDim)),
        ),
        child: Panel(
          onTap: onTriage,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(note.payload['text'] as String? ?? '',
                  style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: Space.md),
              Row(
                children: [
                  Text(
                    '${at.day}.${at.month}. '
                    '${at.hour.toString().padLeft(2, "0")}:'
                    '${at.minute.toString().padLeft(2, "0")}',
                    style: monoStyle(context, size: 11, color: p.inkFaint),
                  ),
                  const Spacer(),
                  Text(context.t('SORTIEREN'),
                      style: monoStyle(context,
                          size: 10.5, weight: FontWeight.w600, color: p.signal)),
                  Icon(Icons.chevron_right, size: 16, color: p.signal),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskRow extends ConsumerWidget {
  final Task task;
  const _TaskRow({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    final capacity =
        ref.watch(snapshotProvider).value?.state.capacity ?? 50;
    final reachable = task.isStartable(capacity);

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Panel(
        padding: const EdgeInsets.symmetric(
            horizontal: Space.lg, vertical: Space.md),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 32,
              decoration: BoxDecoration(
                color: reachable ? p.calm : p.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.title,
                      style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 2),
                  Text(
                    reachable
                        ? 'Start ${task.activationEnergy}/10 · in Reichweite'
                        : 'Start ${task.activationEnergy}/10 · heute zu hoch',
                    style: monoStyle(context,
                        size: 10.5,
                        color: reachable ? p.calm : p.inkFaint),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: context.t('Erledigt'),
              icon: Icon(Icons.check, size: 20, color: p.inkDim),
              onPressed: () async {
                final runtime = await ref.read(runtimeProvider.future);
                await runtime.completeTask(task);
                await HapticFeedback.selectionClick();
                refreshAxiom(ref);
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Triage ──────────────────────────────────────────────────────────────

class _TriageSheet extends ConsumerStatefulWidget {
  final String text;
  final String captureId;
  const _TriageSheet({required this.text, required this.captureId});

  @override
  ConsumerState<_TriageSheet> createState() => _TriageSheetState();
}

class _TriageSheetState extends ConsumerState<_TriageSheet> {
  late final _title = TextEditingController(text: widget.text);
  int _ae = 5;
  int _stakes = 5;
  bool _saving = false;

  /// Ab wann es weh tut. Treibt die Dringlichkeit in der Auswahl, war aber
  /// bisher nur über den Expertenmodus setzbar — am Telefon gab es keinen
  /// Weg dorthin, obwohl die Aufgabe hier entsteht.
  DateTime? _decayAt;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final runtime = await ref.read(runtimeProvider.future);
    final task = await runtime.createTask(
      title: _title.text.trim(),
      activationEnergy: _ae,
      // Salienz wird nicht abgefragt — sie ist im Erfassungsmoment nicht
      // ehrlich zugaenglich. Mittelwert, bis Nutzungsdaten Besseres zeigen.
      salience: 5,
      stakes: _stakes,
      decayAt: _decayAt,
    );
    await runtime.record(EventType.taskCreated, payload: {
      'task_id': task.id,
      'from_capture': widget.captureId,
      'title': task.title,
      'ae': _ae,
      'salience': 5,
      'stakes': _stakes,
      'decay_at': ?_decayAt?.toIso8601String(),
      'state': TaskState.ready.name,
    });
    await HapticFeedback.mediumImpact();
    refreshAxiom(ref);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: Space.lg,
          right: Space.lg,
          top: Space.lg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + Space.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.t('SORTIEREN'), style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.md),
            TextField(
              controller: _title,
              maxLines: 3,
              minLines: 1,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: Space.xl),
            _Dial(
              label: context.t('Wie schwer fällt der Start?'),
              hint: context.t('Nicht wie lang es dauert. Nur der Anfang.'),
              value: _ae,
              low: 'sofort',
              high: context.t('große Hürde'),
              onChanged: (v) => setState(() => _ae = v),
            ),
            const SizedBox(height: Space.xl),
            _Dial(
              label: context.t('Was kostet es, wenn es liegenbleibt?'),
              hint: context.t('Folgen, nicht Wichtigkeit.'),
              value: _stakes,
              low: 'nichts',
              high: 'viel',
              onChanged: (v) => setState(() => _stakes = v),
            ),
            const SizedBox(height: Space.xl),
            _Deadline(
              value: _decayAt,
              onChanged: (v) => setState(() => _decayAt = v),
            ),
            const SizedBox(height: Space.xl),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(context.t('Übernehmen')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Zehnstufiger Wähler. Zehn Stufen, weil die Skala auf der
/// Kapazitätslinie direkt ablesbar bleiben muss.
class _Dial extends StatelessWidget {
  final String label;
  final String hint;
  final int value;
  final String low;
  final String high;
  final ValueChanged<int> onChanged;

  const _Dial({
    required this.label,
    required this.hint,
    required this.value,
    required this.low,
    required this.high,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(hint, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: Space.md),
        Row(
          children: [
            for (var i = 1; i <= 10; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onChanged(i);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: 40,
                    margin: EdgeInsets.only(right: i < 10 ? 3 : 0),
                    decoration: BoxDecoration(
                      color: value >= i
                          ? p.signal.withValues(alpha: value == i ? 0.9 : 0.22)
                          : p.base,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: value == i ? p.signal : p.rule,
                      ),
                    ),
                    child: value == i
                        ? Center(
                            child: Text('$i',
                                style: monoStyle(context,
                                    size: 11,
                                    weight: FontWeight.w600,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimary)),
                          )
                        : null,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.xs + 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(low, style: monoStyle(context, size: 10.5)),
            Text(high, style: monoStyle(context, size: 10.5)),
          ],
        ),
      ],
    );
  }
}

/// Wann es weh tut — vier Griffe, kein Kalender.
///
/// Absichtlich keine Uhrzeit und kein Standard-Kalenderdialog an erster
/// Stelle: Ein Datum auszuwählen ist im Sortiermoment die teuerste Frage
/// auf dem Blatt, und die häufigen Fälle sind ohnehin „heute", „morgen"
/// und „diese Woche". Wer ein echtes Datum braucht, bekommt es hinter dem
/// letzten Griff.
class _Deadline extends StatelessWidget {
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  const _Deadline({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 23, 59);
    final options = <(String, DateTime?)>[
      (context.t('offen'), null),
      (context.t('heute'), today),
      (context.t('morgen'), today.add(const Duration(days: 1))),
      (context.t('diese Woche'),
          today.add(Duration(days: 7 - now.weekday))),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.t('Ab wann tut es weh?'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: Space.xs),
        Text(context.t('Treibt die Dringlichkeit. Kein Termin, keine Mahnung.'),
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: Space.md),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (final (label, at) in options)
              ChoiceChip(
                label: Text(label),
                selected: _sameDay(value, at),
                onSelected: (_) => onChanged(at),
              ),
            ActionChip(
              label: Text(_custom(context)),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: value ?? today,
                  firstDate: today,
                  lastDate: today.add(const Duration(days: 365 * 3)),
                );
                if (picked != null) {
                  onChanged(DateTime(
                      picked.year, picked.month, picked.day, 23, 59));
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  /// Zeigt das gewählte Datum, sobald es keiner der Voreinstellungen ist.
  String _custom(BuildContext context) {
    final v = value;
    if (v == null) return context.t('Datum …');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 23, 59);
    for (final preset in [
      today,
      today.add(const Duration(days: 1)),
      today.add(Duration(days: 7 - now.weekday)),
    ]) {
      if (_sameDay(v, preset)) return context.t('Datum …');
    }
    return '${v.day}.${v.month}.';
  }

  static bool _sameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return a == null && b == null;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
