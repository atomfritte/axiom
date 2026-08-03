/// Impuls-Abfang — M6.
///
/// Kein Verbot, keine Sperre, keine Moral (G3). Nur Latenz und Sichtbarkeit —
/// und der Impulsdurchbruch überlebt beides meistens nicht.
///
/// Der Wirkmechanismus ist ein anderer als bei Blocker-Apps: Eine fremde
/// Sperre ist eine Herausforderung, eine selbst gesetzte Regel ein Vertrag
/// mit dem Vergangenheits-Ich. Deshalb schreibt AXIOM die Prüffragen nicht
/// vor — sie werden im ruhigen Zustand selbst formuliert [D5, D10].
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/widgets/instruments.dart';
import '../state/providers.dart';

class InterceptScreen extends ConsumerWidget {
  const InterceptScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final triggers = ref.watch(triggersProvider).value ?? const [];
    final active = ref.watch(snapshotProvider).value?.activeIntercept;
    final stats = ref.watch(interceptStatsProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Bremse')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            Space.lg, Space.lg, Space.lg, Space.huge),
        children: [
          if (active != null) ...[
            _ActiveRunCard(run: active),
            const SizedBox(height: Space.xl),
          ],

          if (triggers.isEmpty)
            const _EmptyTriggers()
          else ...[
            SectionLabel('Trigger · ${triggers.length}'),
            for (final trigger in triggers)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: _TriggerRow(
                  trigger: trigger,
                  stats: stats
                      .where((s) => s.triggerId == trigger.id)
                      .firstOrNull,
                  disabled: active != null,
                ),
              ),
          ],

          const SizedBox(height: Space.lg),
          OutlinedButton.icon(
            onPressed: () => _edit(context, null),
            icon: Icon(Icons.add, size: 18, color: context.axiom.signal),
            label: const Text('Trigger anlegen'),
          ),

          const SizedBox(height: Space.xl),
          Text(
            'Die Prüffragen schreibst du im ruhigen Zustand. Eine fremde '
            'Frage klickt man weg, die eigene beantwortet man.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, InterceptTrigger? existing) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _TriggerSheet(existing: existing),
      );
}

class _EmptyTriggers extends StatelessWidget {
  const _EmptyTriggers();

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('KEINE TRIGGER', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Space.md),
          Text('Noch nichts eingerichtet.',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: Space.md),
          Text(
            'Ein Trigger ist eine Handlung, die du im Moment tun willst und '
            'am nächsten Tag oft nicht mehr. Statt sie zu sperren, schiebt '
            'AXIOM eine Wartezeit dazwischen — und stellt dir deine eigenen '
            'Fragen.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      );
}

/// Läuft gerade eine Wartezeit.
class _ActiveRunCard extends ConsumerStatefulWidget {
  final InterceptRun run;
  const _ActiveRunCard({required this.run});

  @override
  ConsumerState<_ActiveRunCard> createState() => _ActiveRunCardState();
}

class _ActiveRunCardState extends ConsumerState<_ActiveRunCard> {
  final _answers = <int, bool>{};

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final now = ref.watch(nowProvider);
    final run = widget.run;
    final released = !run.isActive(now);
    final runtime = ref.watch(runtimeProvider).value;
    final trigger = ref
        .watch(triggersProvider)
        .value
        ?.where((t) => t.id == run.triggerId)
        .firstOrNull;

    return Panel(
      accent: p.signal.withValues(alpha: 0.55),
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(released ? 'WARTEZEIT VORBEI' : 'WARTEZEIT LÄUFT',
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Space.md),
          Text(run.triggerLabel,
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: Space.md),

          if (!released)
            Text(
              '${run.remaining(now).inMinutes} min',
              style: TextStyle(
                fontFamily: Fonts.mono,
                fontSize: 36,
                fontWeight: FontWeight.w300,
                color: p.signal,
              ),
            ),
          const SizedBox(height: Space.sm),
          Text(
            runtime?.interceptWaitingText(run) ?? '',
            style: Theme.of(context).textTheme.bodyMedium,
          ),

          if (trigger != null && trigger.checklist.isNotEmpty) ...[
            const SizedBox(height: Space.xl),
            Text('DEINE FRAGEN',
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.sm),
            for (final (index, question) in trigger.checklist.indexed)
              _ChecklistRow(
                question: question,
                checked: _answers[index] ?? false,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _answers[index] = !(_answers[index] ?? false));
                },
              ),
          ],

          const SizedBox(height: Space.xl),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: FilledButton(
                  onPressed: () => _resolve(InterceptOutcome.aborted),
                  child: const Text('Lasse ich'),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  onPressed: released
                      ? () => _resolve(InterceptOutcome.proceeded)
                      : null,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                  ),
                  child: const Text('Mache ich',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
          if (!released) ...[
            const SizedBox(height: Space.sm),
            Text(
              '„Mache ich" wird frei, wenn die Wartezeit um ist.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _resolve(InterceptOutcome outcome) async {
    final runtime = await ref.read(runtimeProvider.future);
    final answers = List<bool>.generate(
      _answers.isEmpty ? 0 : _answers.keys.reduce((a, b) => a > b ? a : b) + 1,
      (i) => _answers[i] ?? false,
    );
    await runtime.resolveIntercept(widget.run, outcome, answers: answers);
    await HapticFeedback.mediumImpact();
    refreshAxiom(ref);
  }
}

class _ChecklistRow extends StatelessWidget {
  final String question;
  final bool checked;
  final VoidCallback onTap;

  const _ChecklistRow({
    required this.question,
    required this.checked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.control),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              checked ? Icons.check_box_outlined : Icons.check_box_outline_blank,
              size: 18,
              color: checked ? p.calm : p.inkFaint,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(question,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: checked ? p.ink : p.inkDim,
                      )),
            ),
          ],
        ),
      ),
    );
  }
}

class _TriggerRow extends ConsumerWidget {
  final InterceptTrigger trigger;
  final InterceptStats? stats;
  final bool disabled;

  const _TriggerRow({
    required this.trigger,
    required this.stats,
    required this.disabled,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    final hold = stats?.holdRate;

    return Panel(
      accent: stats?.needsReview == true
          ? p.caution.withValues(alpha: 0.4)
          : null,
      onTap: disabled
          ? null
          : () async {
              final runtime = await ref.read(runtimeProvider.future);
              await runtime.startIntercept(trigger);
              await HapticFeedback.mediumImpact();
              refreshAxiom(ref);
            },
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trigger.label,
                    style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 2),
                Text(
                  trigger.releaseAt != null
                      ? 'Freigabe ${trigger.releaseAt}'
                      : '${trigger.cooldown.inMinutes} min warten'
                          '${hold == null ? "" : " · ${(hold * 100).round()} % gehalten"}',
                  style: monoStyle(context,
                      size: 10.5,
                      color: stats?.needsReview == true ? p.caution : p.inkFaint),
                ),
              ],
            ),
          ),
          if (!disabled)
            Text('AUSLÖSEN',
                style: monoStyle(context,
                    size: 10, weight: FontWeight.w600, color: p.signal)),
        ],
      ),
    );
  }
}

// ── Trigger anlegen ─────────────────────────────────────────────────────

class _TriggerSheet extends ConsumerStatefulWidget {
  final InterceptTrigger? existing;
  const _TriggerSheet({this.existing});

  @override
  ConsumerState<_TriggerSheet> createState() => _TriggerSheetState();
}

class _TriggerSheetState extends ConsumerState<_TriggerSheet> {
  late final _label =
      TextEditingController(text: widget.existing?.label ?? '');
  late final _question = TextEditingController();
  late final List<String> _checklist =
      List.of(widget.existing?.checklist ?? const []);
  late int _minutes = widget.existing?.cooldown.inMinutes ?? 15;
  late String? _releaseAt = widget.existing?.releaseAt;

  @override
  void dispose() {
    _label.dispose();
    _question.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _label.text.trim().isNotEmpty && _checklist.isNotEmpty;

  Future<void> _save() async {
    if (!_canSave) return;
    final runtime = await ref.read(runtimeProvider.future);
    final label = _label.text.trim();
    await runtime.saveTrigger(InterceptTrigger(
      id: widget.existing?.id ??
          label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_'),
      label: label,
      cooldown: Duration(minutes: _minutes),
      releaseAt: _releaseAt,
      checklist: _checklist,
      // Selbst angelegt heißt selbst autorisiert — genau das ist der Vertrag.
      authorized: true,
    ));
    refreshAxiom(ref);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
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
            Text('TRIGGER', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.md),
            TextField(
              controller: _label,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Wobei willst du eine Wartezeit?',
              ),
            ),

            const SizedBox(height: Space.xl),
            Text('Wie lange warten',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              children: [
                for (final option in [5, 15, 30, 60, 1440])
                  ChoiceChip(
                    label: Text(option >= 1440 ? '24 h' : '$option min'),
                    selected: _releaseAt == null && _minutes == option,
                    onSelected: (_) => setState(() {
                      _minutes = option;
                      _releaseAt = null;
                    }),
                  ),
                ChoiceChip(
                  label: const Text('bis 09:00'),
                  selected: _releaseAt == '09:00',
                  onSelected: (_) => setState(() => _releaseAt = '09:00'),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Text(
              'Für Nachtentscheidungen ist „bis 09:00" das Wirksamste — was '
              'um eins dringend wirkt, sieht um neun anders aus.',
              style: Theme.of(context).textTheme.bodySmall,
            ),

            const SizedBox(height: Space.xl),
            Text('Deine Prüffragen',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Space.xs),
            Text(
              'Ohne mindestens eine Frage kein Trigger. Sie ist der Vertrag.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: Space.md),

            for (final (index, question) in _checklist.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(question,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, size: 16, color: p.inkFaint),
                      onPressed: () =>
                          setState(() => _checklist.removeAt(index)),
                    ),
                  ],
                ),
              ),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _question,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => _addQuestion(),
                    decoration: const InputDecoration(
                      hintText: 'Eigene Frage…',
                    ),
                  ),
                ),
                const SizedBox(width: Space.sm),
                IconButton(
                  icon: Icon(Icons.add, color: p.signal),
                  onPressed: _addQuestion,
                ),
              ],
            ),

            const SizedBox(height: Space.md),
            Text('ODER EINE VORLAGE',
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final seed in kChecklistSeeds)
                  if (!_checklist.contains(seed))
                    ActionChip(
                      label: Text(seed,
                          style: Theme.of(context).textTheme.bodySmall),
                      onPressed: () => setState(() => _checklist.add(seed)),
                    ),
              ],
            ),

            const SizedBox(height: Space.xl),
            FilledButton(
              onPressed: _canSave ? _save : null,
              child: const Text('Trigger speichern'),
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: Space.sm),
              Center(
                child: TextButton(
                  onPressed: () async {
                    final runtime = await ref.read(runtimeProvider.future);
                    await runtime.archiveTrigger(widget.existing!.id);
                    refreshAxiom(ref);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: const Text('Trigger entfernen'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _addQuestion() {
    final text = _question.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _checklist.add(text);
      _question.clear();
    });
  }
}
