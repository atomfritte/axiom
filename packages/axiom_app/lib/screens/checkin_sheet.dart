/// Check-in — vier Regler, unter 15 Sekunden.
///
/// Die Fragen sind bewusst als Messung formuliert, nicht als Bewertung.
/// "Wie viel Kraft hat es gekostet?" ist eine Ablesung. "Wie produktiv
/// warst du?" waere ein Urteil — und Urteile treffen bei Rejection
/// Sensitivity (D10) genau die falsche Stelle.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../state/providers.dart';
import '../i18n/i18n.dart';

Future<bool> showCheckinSheet(BuildContext context, {String slot = 'manual'}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CheckinSheet(slot: slot),
    ) ??
    false;

class _CheckinSheet extends ConsumerStatefulWidget {
  final String slot;
  const _CheckinSheet({required this.slot});

  @override
  ConsumerState<_CheckinSheet> createState() => _CheckinSheetState();
}

class _CheckinSheetState extends ConsumerState<_CheckinSheet> {
  int _energy = 3;
  int _focus = 3;
  int _mood = 3;
  int _stim = 3;
  int _compensation = 3;
  int _recovery = 3;
  bool _saving = false;

  /// Der Abend-Check-in erhebt zusaetzlich die beiden Kernsignale des
  /// Load Monitors — sie sind das Einzige, was vor dem Bruch warnt. [D1]
  bool get _isEvening => widget.slot == 'evening';

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final runtime = await ref.read(runtimeProvider.future);
    await runtime.checkIn(
      energy: _energy,
      focus: _focus,
      mood: _mood,
      stimNeed: _stim,
      compensation: _isEvening ? _compensation : null,
      recovery: _isEvening ? _recovery : null,
      slot: widget.slot,
    );
    await HapticFeedback.mediumImpact();
    refreshAxiom(ref);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.t('CHECK-IN'), style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.xs),
            Text(
              _isEvening ? context.t('Wie war der Tag?') : context.t('Wie ist der Stand?'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: Space.xs),
            Text(context.t('Vier Regler. Ungefähr reicht.'),
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: Space.xl),
            _Scale(
              label: context.t('Energie'),
              low: 'leer',
              high: 'voll',
              value: _energy,
              color: p.signal,
              onChanged: (v) => setState(() => _energy = v),
            ),
            _Scale(
              label: context.t('Fokus'),
              low: 'zerstreut',
              high: 'klar',
              value: _focus,
              color: p.info,
              onChanged: (v) => setState(() => _focus = v),
            ),
            _Scale(
              label: context.t('Stimmung'),
              low: 'gereizt',
              high: 'gelassen',
              value: _mood,
              color: p.calm,
              onChanged: (v) => setState(() => _mood = v),
            ),
            _Scale(
              label: context.t('Reizhunger'),
              low: 'ruhig',
              high: 'kribbelig',
              value: _stim,
              color: p.caution,
              onChanged: (v) => setState(() => _stim = v),
            ),
            if (_isEvening) ...[
              const SizedBox(height: Space.sm),
              Divider(color: p.rule),
              const SizedBox(height: Space.sm),
              _Scale(
                label: context.t('Kraftaufwand für Struktur'),
                low: context.t('lief nebenbei'),
                high: context.t('ständig nachgehalten'),
                value: _compensation,
                color: p.caution,
                onChanged: (v) => setState(() => _compensation = v),
              ),
              _Scale(
                label: context.t('Erholung hat gewirkt'),
                low: context.t('gar nicht'),
                high: 'deutlich',
                value: _recovery,
                color: p.calm,
                onChanged: (v) => setState(() => _recovery = v),
              ),
            ],
            const SizedBox(height: Space.lg),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(context.t('Fertig')),
            ),
            const SizedBox(height: Space.sm),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(context.t('Jetzt nicht')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fünfstufiger Regler mit benannten Endpunkten.
///
/// Endpunkte statt Zahlen: "leer" bis "voll" ist ablesbar, "1 bis 5"
/// verlangt eine Übersetzung, die bei niedriger Kapazität Geld kostet.
final class _Scale extends StatelessWidget {
  final String label;
  final String low;
  final String high;
  final int value;
  final Color color;
  final ValueChanged<int> onChanged;

  const _Scale({
    required this.label,
    required this.low,
    required this.high,
    required this.value,
    required this.color,
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
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                Expanded(
                  child: Semantics(
                    selected: value == i,
                    label: context.t('{0} Stufe {1} von 5', [label, i]),
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onChanged(i);
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        height: 46,
                        margin: EdgeInsets.only(right: i < 5 ? 6 : 0),
                        decoration: BoxDecoration(
                          color: value >= i
                              ? color.withValues(alpha: value == i ? 0.9 : 0.28)
                              : p.panel,
                          borderRadius: BorderRadius.circular(Radii.control),
                          border: Border.all(
                            color: value == i ? color : p.rule,
                            width: value == i ? 1.5 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.xs + 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(low, style: monoStyle(context, size: 10.5, spacing: 0.4)),
              Text(high, style: monoStyle(context, size: 10.5, spacing: 0.4)),
            ],
          ),
        ],
      ),
    );
  }
}
