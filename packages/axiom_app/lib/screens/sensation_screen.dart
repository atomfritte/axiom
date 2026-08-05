/// Reiz-Haushalt — M5.
///
/// Reizhunger ist ein Bedarf, kein Fehler. Er lässt sich nicht wegtrainieren;
/// ungedeckt sucht er sich den schnellsten Kanal, und der schnellste ist fast
/// immer der teuerste [D5].
///
/// Dieser Screen moralisiert nicht (G3). Er zeigt den Stand, schlägt einen
/// passenden Kanal vor und lässt eintragen, was war — geplant oder nicht.
/// Ungeplante Slots werden gezählt, nicht bestraft: Ein Haushalt, der zum
/// Schuldenkonto wird, trifft genau die falsche Stelle.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/widgets/instruments.dart';
import '../state/meta_time.dart';
import '../state/providers.dart';
import '../state/runtime.dart';
import '../i18n/i18n.dart';

class SensationScreen extends ConsumerWidget {
  const SensationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(snapshotProvider);
    final channels = ref.watch(channelsProvider).value ?? const [];

    return MetaTimedScope(
      screen: 'sensation',
      child: Scaffold(
      appBar: AppBar(title: Text(context.t('Reiz'))),
      body: snapshot.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (snap) => ListView(
          padding: const EdgeInsets.fromLTRB(
              Space.lg, Space.lg, Space.lg, Space.huge),
          children: [
            _NeedCard(snapshot: snap),
            const SizedBox(height: Space.lg),
            _BudgetCard(budget: snap.sensationBudget),

            if (snap.suggestedChannel != null) ...[
              const SizedBox(height: Space.lg),
              _SuggestionCard(channel: snap.suggestedChannel!),
            ],

            const SizedBox(height: Space.xl),
            SectionLabel(context.t('Kanäle · {0}', [channels.length])),
            for (final channel in channels)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: _ChannelRow(channel: channel),
              ),
            const SizedBox(height: Space.md),
            OutlinedButton.icon(
              onPressed: () => _editChannel(context, ref, null),
              icon: Icon(Icons.add, size: 18, color: context.axiom.signal),
              label: Text(context.t('Eigenen Kanal anlegen')),
            ),

            const SizedBox(height: Space.xl),
            Text(
              context.t('Was hier fehlt, deckst du sonst woanders. Trag ein, was bei dir wirklich wirkt — auch wenn es etwas kostet. Gezählt wird es ohnehin.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
    );
  }

  Future<void> _editChannel(
    BuildContext context,
    WidgetRef ref,
    SensationChannel? existing,
  ) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _ChannelSheet(existing: existing),
      );
}

class _NeedCard extends StatelessWidget {
  final AxiomSnapshot snapshot;
  const _NeedCard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final need = snapshot.state.sensationNeed;

    return Panel(
      accent: need >= 70 ? p.caution.withValues(alpha: 0.5) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InstrumentBar(
            label: context.t('Reizbedarf'),
            value: need,
            color: p.caution,
            reading: switch (need) {
              >= 85 => context.t('Hoch. Was jetzt nicht geplant wird, passiert ungeplant.'),
              >= 70 => context.t('Deutlich. Ein Slot wäre fällig.'),
              >= 40 => context.t('Normal.'),
              _ => context.t('Gedeckt.'),
            },
            breakdown: snapshot.breakdown['sensation_need'] ?? const [],
            confidence: snapshot.state.confidenceOf('sensation_need'),
          ),
        ],
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  final SensationBudget budget;
  const _BudgetCard({required this.budget});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t('VERDIENT'), style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Space.sm),
          BigReading(
            value: '${budget.availableMinutes}',
            unit: context.t('min offen'),
            valueColor: budget.hasCredit ? p.calm : p.inkDim,
            size: 32,
          ),
          const SizedBox(height: Space.md),
          Text(
            budget.hasCredit
                ? context.t('Aus konzentrierter Arbeit heute. Der Tausch ist der einzige, den dieses Belohnungssystem zuverlässig annimmt.')
                : context.t('Noch nichts verdient heute. Ein Slot geht trotzdem — er wird nur anders gezählt.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SuggestionCard extends ConsumerWidget {
  final SensationChannel channel;
  const _SuggestionCard({required this.channel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    return Panel(
      accent: p.signal.withValues(alpha: 0.5),
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t('VORSCHLAG'), style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Space.md),
          Text(channel.label,
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: Space.sm),
          Text(context.t('{0} min · Intensität {1}/5', [channel.typical.inMinutes, channel.intensity]),
              style: monoStyle(context, size: 12)),
          const SizedBox(height: Space.xl),
          FilledButton(
            onPressed: () => _log(context, ref, channel, planned: true),
            child: Text(context.t('Jetzt einplanen')),
          ),
        ],
      ),
    );
  }
}

class _ChannelRow extends ConsumerWidget {
  final SensationChannel channel;
  const _ChannelRow({required this.channel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.axiom;
    return Panel(
      padding: const EdgeInsets.symmetric(
          horizontal: Space.lg, vertical: Space.md),
      onTap: () => _log(context, ref, channel, planned: true),
      child: Row(
        children: [
          // Intensität als Skala, nicht als Zahl — sofort ablesbar.
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                Container(
                  width: 3,
                  height: 4.0 + i * 3,
                  margin: const EdgeInsets.only(right: 2),
                  color: i <= channel.intensity ? p.caution : p.rule,
                ),
            ],
          ),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(channel.label,
                    style: Theme.of(context).textTheme.bodyLarge),
                Text(
                  context.t('{0} min{1}', [channel.typical.inMinutes, channel.hasCost ? context.t(' · kostet etwas') : ""]),
                  style: monoStyle(context, size: 10.5),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: context.t('War schon'),
            icon: Icon(Icons.history, size: 18, color: p.inkDim),
            onPressed: () => _log(context, ref, channel, planned: false),
          ),
        ],
      ),
    );
  }
}

Future<void> _log(
  BuildContext context,
  WidgetRef ref,
  SensationChannel channel, {
  required bool planned,
}) async {
  final runtime = await ref.read(runtimeProvider.future);
  await runtime.logSlot(
    channel: channel,
    duration: channel.typical,
    planned: planned,
  );
  await HapticFeedback.mediumImpact();
  refreshAxiom(ref);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(planned
          ? context.t('{0} eingeplant.', [channel.label])
          : context.t('{0} notiert.', [channel.label])),
      duration: const Duration(milliseconds: 1400),
    ),
  );
}

// ── Kanal anlegen ───────────────────────────────────────────────────────

class _ChannelSheet extends ConsumerStatefulWidget {
  final SensationChannel? existing;
  const _ChannelSheet({this.existing});

  @override
  ConsumerState<_ChannelSheet> createState() => _ChannelSheetState();
}

class _ChannelSheetState extends ConsumerState<_ChannelSheet> {
  late final _label =
      TextEditingController(text: widget.existing?.label ?? '');
  late int _intensity = widget.existing?.intensity ?? 4;
  late int _minutes = widget.existing?.typical.inMinutes ?? 30;
  late bool _hasCost = widget.existing?.hasCost ?? false;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final label = _label.text.trim();
    if (label.isEmpty) return;
    final runtime = await ref.read(runtimeProvider.future);
    await runtime.saveChannel(SensationChannel(
      id: widget.existing?.id ??
          label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_'),
      label: label,
      intensity: _intensity,
      typical: Duration(minutes: _minutes),
      hasCost: _hasCost,
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
            Text(context.t('KANAL'), style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.md),
            TextField(
              controller: _label,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: context.t('Was wirkt bei dir wirklich?'),
              ),
            ),
            const SizedBox(height: Space.xl),

            Text(context.t('Wie stark'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Space.sm),
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _intensity = i);
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        height: 44,
                        margin: EdgeInsets.only(right: i < 5 ? 6 : 0),
                        decoration: BoxDecoration(
                          color: _intensity >= i
                              ? p.caution.withValues(
                                  alpha: _intensity == i ? 0.9 : 0.28)
                              : p.panel,
                          borderRadius: BorderRadius.circular(Radii.control),
                          border: Border.all(
                              color: _intensity == i ? p.caution : p.rule),
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: Space.xl),
            Text(context.t('Wie lange typischerweise'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              children: [
                for (final option in [5, 15, 30, 45, 60, 90])
                  ChoiceChip(
                    label: Text(context.t('{0} min', [option])),
                    selected: _minutes == option,
                    onSelected: (_) => setState(() => _minutes = option),
                  ),
              ],
            ),

            const SizedBox(height: Space.lg),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _hasCost,
              onChanged: (v) => setState(() => _hasCost = v),
              title: Text(context.t('Kostet etwas'),
                  style: Theme.of(context).textTheme.titleMedium),
              subtitle: Text(
                context.t('Geld, Schlaf, Gesundheit oder Beziehung. Wird nicht verboten — nur nicht von selbst vorgeschlagen.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),

            const SizedBox(height: Space.lg),
            FilledButton(
              onPressed: _label.text.trim().isEmpty ? null : _save,
              child: Text(context.t('Kanal speichern')),
            ),
          ],
        ),
      ),
    );
  }
}
