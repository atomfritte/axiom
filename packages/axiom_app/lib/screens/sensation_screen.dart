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
    final need = snapshot.state.sensationNeed;

    // Hier lag ab 70 ein kupferner Rahmen um die Karte. Reizbedarf ist eine
    // Ablesung, kein Alarm: „hoch" heisst nicht „falsch", es heisst „was
    // jetzt nicht geplant wird, passiert ungeplant" — und genau das steht
    // eine Zeile tiefer in Worten. Ein Rahmen darum haette daraus eine Note
    // gemacht (R7, G3).
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InstrumentBar(
            label: context.t('Reizbedarf'),
            value: need,
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
          // War `VERDIENT`. Gesperrte Versalien ueber einer Zahl, die ohnehin
          // die groesste Figur der Karte ist — die Marke musste nie laut
          // sein, sie musste nur dastehen.
          Text(context.t('Verdient'), style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Space.sm),
          // War gruen, wenn Guthaben da ist, und grau, wenn nicht. Grün sagt
          // „gut gemacht", grau sagt „noch nichts geleistet" — beides sind
          // Noten ueber verdiente Minuten. Es ist eine Ablesung wie jede
          // andere und traegt deshalb dieselbe Farbe wie jede andere (R7).
          // Dass nichts da ist, sagt schon die Null; der Satz darunter sagt,
          // dass ein Slot trotzdem geht.
          BigReading(
            value: '${budget.availableMinutes}',
            unit: context.t('min offen'),
            valueColor: p.signal,
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
    // Der Vorschlag ist die eine Handlung dieses Schirms — also die eine
    // erhobene Flaeche (G1). Vorher ein Signalrahmen; der sagte dasselbe
    // wie die drei anderen Rahmen daneben, naemlich nichts.
    return Panel(
      reachable: true,
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // War `VORSCHLAG`.
          Text(context.t('Vorschlag'), style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Space.md),
          Text(channel.label,
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: Space.sm),
          // War Schreibmaschine. Dauer und Intensitaet sind Messwerte.
          Text(context.t('{0} min · Intensität {1}/5', [channel.typical.inMinutes, channel.intensity]),
              style: readingStyle(context,
                  size: 14, weight: FontWeight.w400, color: p.inkDim)),
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
          // Kupfer hiess hier „Achtung, stark". Intensitaet ist eine
          // Eigenschaft des Kanals, keine Warnung davor — Reizbedarf wird
          // budgetiert, nicht moralisiert (G3). Dieselbe Messfarbe wie
          // ueberall, unterschieden wird ueber die Hoehe der Striche.
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                Container(
                  width: 3,
                  height: 4.0 + i * 3,
                  margin: const EdgeInsets.only(right: 2),
                  color: i <= channel.intensity ? p.signal : p.rule,
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
                const SizedBox(height: 2),
                Text(
                  context.t('{0} min{1}', [channel.typical.inMinutes, channel.hasCost ? context.t(' · kostet etwas') : ""]),
                  style: readingStyle(context,
                      size: 13.5, weight: FontWeight.w400, color: p.inkFaint),
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

/// Auswahl-Chips in der Sprache dieser Oberflaeche.
///
/// Material setzt fuer einen gewaehlten Chip `secondaryContainer` — in
/// dieser Palette ein Blau. Direkt unter einer Skala, deren Auswahl
/// bernsteinfarben ist, sind das zwei Farben fuer dieselbe Aussage
/// („das hier ist gewaehlt"). Ein Haken zusaetzlich zur Fuellung sagt es
/// ein drittes Mal.
///
/// Ungewaehlt liegt der Chip in der Mulde, gewaehlt kommt er heraus —
/// genau wie die Regler und die Ortszeilen.
///
/// **Der richtige Ort dafuer ist `theme.dart`** (`chipTheme`), dann gilt es
/// auch fuer Eingang und Aufgaben. Solange es den Eintrag dort nicht gibt,
/// steht dasselbe Stueck in den drei Dateien, die Chips zeigen.
ChipThemeData _chipLook(BuildContext context) {
  final p = context.axiom;
  return ChipThemeData(
    backgroundColor: p.well,
    selectedColor: p.signal.withValues(alpha: 0.16),
    showCheckmark: false,
    side: BorderSide.none,
    labelStyle: Theme.of(context).textTheme.bodyMedium!.copyWith(color: p.ink),
    secondaryLabelStyle:
        Theme.of(context).textTheme.bodyMedium!.copyWith(color: p.signal),
    padding: const EdgeInsets.symmetric(
        horizontal: Space.md, vertical: Space.sm),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.control),
    ),
  );
}

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
            // War `KANAL`. Fuenf Zeichen duerften nach der Vorgabe Versalien
            // behalten — die Ausnahme gilt aber Plaketten, und das hier ist
            // die Rubrik ueber der Ueberschrift eines Blattes, dieselbe
            // Rolle wie „Zerlegen" im Zerlegeblatt.
            Text(context.t('Kanal'), style: Theme.of(context).textTheme.labelSmall),
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
            const SizedBox(height: Space.md),
            // Vorher kupfern und bis zur gewaehlten Stufe gefuellt. Kupfer
            // ist die Aufmerksamkeitsfarbe — sie sagte hier „je staerker,
            // desto bedenklicher", und das ist genau die Moralisierung, die
            // G3 ausschliesst. Der Lauf bleibt: Intensitaet ist eine Menge,
            // keine Stelle zwischen zwei Enden.
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
                        height: 52,
                        margin: EdgeInsets.only(right: i < 5 ? Space.sm : 0),
                        decoration: BoxDecoration(
                          color: _intensity >= i
                              ? p.signal.withValues(
                                  alpha: _intensity == i ? 1 : 0.3)
                              : p.well,
                          borderRadius: BorderRadius.circular(Radii.control),
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: Space.xl),
            Text(context.t('Wie lange typischerweise'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Space.md),
            ChipTheme(
              data: _chipLook(context),
              child: Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final option in [5, 15, 30, 45, 60, 90])
                    ChoiceChip(
                      label: Text(context.t('{0} min', [option])),
                      selected: _minutes == option,
                      onSelected: (_) => setState(() => _minutes = option),
                    ),
                ],
              ),
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
