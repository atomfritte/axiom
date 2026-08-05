/// Zerlegen — M2.
///
/// Die Frage lautet bewusst nicht „In welche Teile zerfällt das?". Darauf
/// antwortet ein Systemizer mit einem vollständigen Projektplan — und der
/// ist selbst wieder eine Aufgabe mit hoher Aktivierungsenergie.
///
/// Sie lautet: **Was ist die allererste körperliche Handlung?**
///
/// AXIOM schlägt keine Teilschritte vor. Es kann nicht wissen, was
/// „Steuererklärung" konkret bedeutet, und Raten wäre hier schlimmer als
/// Schweigen (ADR-0003). Was es beisteuert: die richtige Frage, einen
/// Formenkatalog und die Prüfung, ob das Ergebnis tatsächlich startbar ist.
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

/// Handle auf die Aktivierungsenergie-Skala.
///
/// Die Skala ist der einzige Weg, den Wert zu setzen. Ein Test, der sie
/// ueber „der letzte Row im Baum" sucht, bricht bei jeder Layoutaenderung
/// an einer voellig anderen Stelle.
const Key kEnergyScaleKey = ValueKey('atomize_energy_scale');

Future<bool> showAtomizeSheet(
  BuildContext context,
  AtomizeCandidate candidate,
) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AtomizeSheet(candidate: candidate),
    ) ??
    false;

class _AtomizeSheet extends ConsumerStatefulWidget {
  final AtomizeCandidate candidate;
  const _AtomizeSheet({required this.candidate});

  @override
  ConsumerState<_AtomizeSheet> createState() => _AtomizeSheetState();
}

class _AtomizeSheetState extends ConsumerState<_AtomizeSheet> {
  final _first = TextEditingController();
  final _rest = TextEditingController();
  final _focus = FocusNode();
  int _firstEnergy = 2;
  StepShape? _shape;
  bool _saving = false;

  Task get _task => widget.candidate.task;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _first.dispose();
    _rest.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _isReachable => _firstEnergy <= widget.candidate.targetEnergy + 1;

  Future<void> _save() async {
    final first = _first.text.trim();
    if (first.isEmpty || _saving) return;
    setState(() => _saving = true);

    final runtime = await ref.read(runtimeProvider.future);
    // Der Rest ist eine Stufe leichter als das Ganze — aber nie unter 1.
    // Bei einer Aufgabe mit Energie 1 kam hier vorher 0 heraus, und der
    // Wertebereich von `Task` ist 1..10: Das Zerlegen brach genau in dem
    // Moment ab, in dem der erste Schritt schon getippt war [D2].
    final restEnergy = (_task.activationEnergy - 1).clamp(1, 10);
    final steps = <({String title, int energy})>[
      (title: first, energy: _firstEnergy),
      if (_rest.text.trim().isNotEmpty)
        (title: _rest.text.trim(), energy: restEnergy),
    ];

    await runtime.atomize(parent: _task, steps: steps);
    await HapticFeedback.mediumImpact();
    refreshAxiom(ref);
    if (mounted) Navigator.of(context).pop(true);
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
            Text(context.t('ZERLEGEN'), style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.sm),
            Text(_task.title,
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: Space.md),
            Text(widget.candidate.explanation,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: Space.xl),

            Text(context.t('Was ist die allererste Handlung?'),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Space.xs),
            Text(
              context.t('Etwas Körperliches, das in zwei Minuten erledigt ist. Nicht der Plan — der erste Handgriff.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: Space.md),

            TextField(
              controller: _first,
              focusNode: _focus,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: _shape?.examples ?? context.t('Ordner auf den Tisch legen'),
              ),
            ),
            const SizedBox(height: Space.lg),

            Text(context.t('ODER EINE DIESER FORMEN'),
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final shape in StepShape.values)
                  _ShapeChip(
                    shape: shape,
                    selected: _shape == shape,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _shape = _shape == shape ? null : shape);
                      _focus.requestFocus();
                    },
                  ),
              ],
            ),
            const SizedBox(height: Space.xl),

            _EnergyPicker(
              value: _firstEnergy,
              target: widget.candidate.targetEnergy,
              onChanged: (v) => setState(() => _firstEnergy = v),
            ),

            if (!_isReachable) ...[
              const SizedBox(height: Space.md),
              Panel(
                accent: p.caution.withValues(alpha: 0.45),
                child: Text(
                  context.t('Das ist noch zu groß. Ein Schritt, der gerade so passt, passt morgen nicht mehr — dann fängt das Ganze von vorn an. Was wäre der Handgriff davor?'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],

            const SizedBox(height: Space.xl),
            Text(context.t('UND DANN? (OPTIONAL)'),
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.sm),
            TextField(
              controller: _rest,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: context.t('Der Rest, grob — kommt später dran'),
              ),
            ),

            const SizedBox(height: Space.xl),
            FilledButton(
              onPressed:
                  _saving || _first.text.trim().isEmpty ? null : _save,
              child: Text(context.t('Übernehmen')),
            ),
            const SizedBox(height: Space.sm),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(context.t('Später')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShapeChip extends StatelessWidget {
  final StepShape shape;
  final bool selected;
  final VoidCallback onTap;

  const _ShapeChip({
    required this.shape,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Space.md, vertical: Space.sm),
        decoration: BoxDecoration(
          color: selected ? p.signal.withValues(alpha: 0.18) : p.panel,
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: selected ? p.signal : p.rule),
        ),
        child: Text(
          shape.label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: selected ? p.signal : p.inkDim,
              ),
        ),
      ),
    );
  }
}

/// Wie schwer fällt DER erste Schritt? Zeigt die Zielmarke mit an, damit
/// sichtbar ist, wann die Zerlegung fein genug ist.
class _EnergyPicker extends StatelessWidget {
  final int value;
  final int target;
  final ValueChanged<int> onChanged;

  const _EnergyPicker({
    required this.value,
    required this.target,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(context.t('Wie schwer fällt dieser Schritt?'),
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            Text(context.t('ZIEL ≤ {0}', [target]),
                style: monoStyle(context,
                    size: 10.5, spacing: 0.6, color: p.calm)),
          ],
        ),
        const SizedBox(height: Space.md),
        // Fester Schluessel: Die Skala ist der einzige Weg, den Wert zu
        // setzen, und ein Test, der sie ueber "der letzte Row im Baum"
        // sucht, bricht bei jeder Layoutaenderung woanders.
        Row(
          key: kEnergyScaleKey,
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
                          ? (i <= target ? p.calm : p.caution)
                              .withValues(alpha: value == i ? 0.9 : 0.22)
                          : p.base,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: value == i
                            ? (i <= target ? p.calm : p.caution)
                            : i == target
                                ? p.calm.withValues(alpha: 0.5)
                                : p.rule,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
