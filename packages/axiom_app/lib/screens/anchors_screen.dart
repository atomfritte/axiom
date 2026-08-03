/// "Anker" — Termine mit ihrer echten Vorlaufzeit. M3.
///
/// Beim Anlegen wird nicht nach der Uhrzeit gefragt und fertig. Gefragt wird
/// nach Fahrzeit, Vorbereitung und Puffer — also nach genau den Größen, die
/// dieses Profil sonst jedes Mal neu im Kopf ausrechnet. Einmal eingetragen,
/// rechnet das System.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/widgets/anchor_chain.dart';
import '../design/widgets/instruments.dart';
import '../platform/system_sync.dart';
import '../state/providers.dart';
import '../i18n/i18n.dart';

class AnchorsScreen extends ConsumerWidget {
  const AnchorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(snapshotProvider);
    final now = ref.watch(nowProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.t('Anker'))),
      body: snapshot.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (snap) => snap.anchors.isEmpty
            ? const _EmptyAnchors()
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                    Space.lg, Space.sm, Space.lg, Space.huge * 2),
                children: [
                  SectionLabel(context.t('Anstehend · {0}', [snap.anchors.length])),
                  for (final anchor in snap.anchors)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.md),
                      child: Panel(
                        accent: anchor.isActive(now)
                            ? context.axiom.signal.withValues(alpha: 0.5)
                            : null,
                        onTap: () => _edit(context, ref, anchor),
                        child: AnchorChainView(anchor: anchor, now: now),
                      ),
                    ),
                  const SizedBox(height: Space.lg),
                  Text(
                    context.t('Die Vorlaufzeit ist die Zeit, die im Kalender nicht steht: aussteigen, fertigmachen, Puffer. Sie erklärt, warum ein Termin mehr kostet als seine Dauer.'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        backgroundColor: context.axiom.signal,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        icon: const Icon(Icons.add),
        label: Text(context.t('Termin')),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Anchor? existing,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AnchorSheet(existing: existing),
    );
  }
}

class _EmptyAnchors extends StatelessWidget {
  const _EmptyAnchors();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: Space.huge),
            Text(context.t('KEINE ANKER'), style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.md),
            Text(context.t('Nichts terminiert.'),
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: Space.md),
            Text(
              context.t('Trag einen Termin ein, und AXIOM rechnet rückwärts: wann du losmusst, wann du anfangen musst dich fertigzumachen, und wann Schluss ist mit dem, was du gerade tust.'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: Space.lg),
            Text(
              context.t('Der letzte Punkt ist der, den man im Kopf immer vergisst.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
}

// ── Anlegen und Ändern ──────────────────────────────────────────────────

class _AnchorSheet extends ConsumerStatefulWidget {
  final Anchor? existing;
  const _AnchorSheet({this.existing});

  @override
  ConsumerState<_AnchorSheet> createState() => _AnchorSheetState();
}

class _AnchorSheetState extends ConsumerState<_AnchorSheet> {
  late final _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final _location =
      TextEditingController(text: widget.existing?.location ?? '');
  late DateTime _arriveBy = widget.existing?.arriveBy ?? _defaultTime();
  late int _travel = widget.existing?.travel.inMinutes ?? 20;
  late int _prepare =
      widget.existing?.prepare.inMinutes ?? kDefaultPrepare.inMinutes;
  late int _buffer =
      widget.existing?.buffer.inMinutes ?? kDefaultBuffer.inMinutes;
  late int _context =
      widget.existing?.contextSwitch.inMinutes ?? kDefaultContextSwitch.inMinutes;
  bool _saving = false;

  static DateTime _defaultTime() {
    final now = DateTime.now();
    final next = now.add(const Duration(hours: 3));
    return DateTime(next.year, next.month, next.day, next.hour, 0);
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    super.dispose();
  }

  /// Vorschau der Kette, während man tippt — sie macht sofort sichtbar,
  /// was die Eingaben bedeuten.
  Anchor get _preview => Anchor(
        id: widget.existing?.id ?? 'preview',
        title: _title.text.trim().isEmpty ? 'Termin' : _title.text.trim(),
        arriveBy: _arriveBy,
        travel: Duration(minutes: _travel),
        prepare: Duration(minutes: _prepare),
        buffer: Duration(minutes: _buffer),
        contextSwitch: Duration(minutes: _context),
        location: _location.text.trim().isEmpty ? null : _location.text.trim(),
      );

  Future<void> _save() async {
    if (_saving || _title.text.trim().isEmpty) return;
    setState(() => _saving = true);
    // Vor dem ersten await lesen: Danach ist der Kontext moeglicherweise weg.
    final language = context.language;
    final runtime = await ref.read(runtimeProvider.future);

    final anchor = widget.existing == null
        ? await runtime.createAnchor(
            title: _title.text.trim(),
            arriveBy: _arriveBy,
            travel: Duration(minutes: _travel),
            prepare: Duration(minutes: _prepare),
            buffer: Duration(minutes: _buffer),
            contextSwitch: Duration(minutes: _context),
            location:
                _location.text.trim().isEmpty ? null : _location.text.trim(),
          )
        : _preview;

    if (widget.existing != null) await runtime.updateAnchor(anchor);
    await SystemSync.scheduleAnchorReminders(anchor, language: language);
    await HapticFeedback.mediumImpact();
    refreshAxiom(ref);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final runtime = await ref.read(runtimeProvider.future);
    await runtime.dismissAnchor(widget.existing!.id);
    await SystemSync.cancelAnchorReminders(widget.existing!);
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
            Text(widget.existing == null ? context.t('NEUER ANKER') : context.t('ANKER ÄNDERN'),
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.md),
            TextField(
              controller: _title,
              autofocus: widget.existing == null,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(hintText: context.t('Wobei musst du sein?')),
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: _location,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(hintText: context.t('Wo? (optional)')),
            ),
            const SizedBox(height: Space.lg),

            _TimeField(
              value: _arriveBy,
              onChanged: (v) => setState(() => _arriveBy = v),
            ),
            const SizedBox(height: Space.xl),

            Text(context.t('WAS VORHER PASSIEREN MUSS'),
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.md),
            _MinuteDial(
              label: context.t('Fahrzeit'),
              hint: context.t('Reine Wegzeit ohne Puffer.'),
              value: _travel,
              options: const [0, 5, 10, 15, 20, 30, 45, 60, 90],
              onChanged: (v) => setState(() => _travel = v),
            ),
            _MinuteDial(
              label: context.t('Fertigmachen'),
              hint: context.t('Anziehen, Sachen suchen, Tasche packen.'),
              value: _prepare,
              options: const [0, 5, 10, 15, 20, 30, 45],
              onChanged: (v) => setState(() => _prepare = v),
            ),
            _MinuteDial(
              label: context.t('Puffer'),
              hint: context.t('Für alles, was dazwischenkommt.'),
              value: _buffer,
              options: const [0, 5, 10, 15, 20, 30],
              onChanged: (v) => setState(() => _buffer = v),
            ),
            _MinuteDial(
              label: context.t('Aussteigen'),
              hint: context.t('Aus dem, was du gerade tust, herauszukommen dauert. Der Schritt, den man im Kopf immer vergisst.'),
              value: _context,
              options: const [0, 5, 10, 15, 20],
              onChanged: (v) => setState(() => _context = v),
            ),

            const SizedBox(height: Space.lg),
            Panel(
              accent: p.signal.withValues(alpha: 0.4),
              child: AnchorChainView(
                anchor: _preview,
                now: ref.watch(nowProvider),
              ),
            ),
            const SizedBox(height: Space.xl),

            FilledButton(
              onPressed: _saving || _title.text.trim().isEmpty ? null : _save,
              child: Text(widget.existing == null ? context.t('Anker setzen') : 'Speichern'),
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: Space.sm),
              Center(
                child: TextButton(
                  onPressed: _delete,
                  child: Text(context.t('Anker entfernen')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  const _TimeField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final isToday = DateUtils.isSameDay(value, DateTime.now());

    return Panel(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime.now().subtract(const Duration(days: 1)),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (date == null || !context.mounted) return;
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(value),
        );
        if (time == null) return;
        onChanged(DateTime(
            date.year, date.month, date.day, time.hour, time.minute));
      },
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.t('DA SEIN UM'),
                    style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: Space.xs),
                Text(
                  '${value.hour.toString().padLeft(2, "0")}:'
                  '${value.minute.toString().padLeft(2, "0")}'
                  '${isToday ? "" : "  ·  ${value.day}.${value.month}."}',
                  style: TextStyle(
                    fontFamily: Fonts.mono,
                    fontSize: 24,
                    fontWeight: FontWeight.w300,
                    color: p.ink,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.schedule, size: 20, color: p.inkDim),
        ],
      ),
    );
  }
}

/// Auswahl in Minuten. Feste Stufen statt Freitext — bei niedriger Kapazität
/// ist Tippen teurer als Antippen.
class _MinuteDial extends StatelessWidget {
  final String label;
  final String hint;
  final int value;
  final List<int> options;
  final ValueChanged<int> onChanged;

  const _MinuteDial({
    required this.label,
    required this.hint,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              Text(context.t('{0} min', [value]),
                  style: monoStyle(context,
                      size: 13, weight: FontWeight.w600, color: p.signal)),
            ],
          ),
          const SizedBox(height: 2),
          Text(hint, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: Space.sm),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: options.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
              itemBuilder: (context, i) {
                final option = options[i];
                final selected = option == value;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onChanged(option);
                  },
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                    decoration: BoxDecoration(
                      color: selected
                          ? p.signal.withValues(alpha: 0.9)
                          : p.panel,
                      borderRadius: BorderRadius.circular(Radii.control),
                      border:
                          Border.all(color: selected ? p.signal : p.rule),
                    ),
                    child: Text(
                      '$option',
                      style: monoStyle(context,
                          size: 13,
                          weight: FontWeight.w500,
                          color: selected
                              ? Theme.of(context).colorScheme.onPrimary
                              : p.inkDim),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
