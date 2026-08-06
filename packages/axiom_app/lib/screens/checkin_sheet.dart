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
import '../design/widgets/instruments.dart';
import '../state/providers.dart';
import '../i18n/i18n.dart';

Future<bool> showCheckinSheet(
  BuildContext context, {
  String slot = 'manual',
}) async =>
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
      // **Die Handlung bleibt stehen, der Inhalt rollt darunter durch.**
      //
      // Dieses Blatt hat ein Zeitbudget: Ein Check-in soll unter fuenfzehn
      // Sekunden dauern (G1). Bei 360 px und 2,4-facher Schrift standen vier
      // Regler und ihre Beschriftungen auf gut zwei Bildschirmen, und
      // „Fertig" lag hinter allen. Wer die Schrift hochstellt, zahlte damit
      // nicht mehr Platz, sondern mehr Zeit — und ein Check-in, der dreimal
      // so lange dauert, wird ausgelassen.
      //
      // `Flexible` statt fester Hoehe: Passt der Inhalt, ist das Blatt so
      // hoch wie er, und es aendert sich nichts. Passt er nicht, rollt er
      // unter dem Abschluss durch. Dieselbe Bauart tragen das Schlaf-,
      // Erfassungs- und Zerlegeblatt.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.lg,
                Space.lg,
                Space.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t('Check-in'),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    _isEvening
                        ? context.t('Wie war der Tag?')
                        : context.t('Wie ist der Stand?'),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    context.t('Vier Regler. Ungefähr reicht.'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: Space.xl),
                  _Scale(
                    label: context.t('Energie'),
                    low: 'leer',
                    high: 'voll',
                    value: _energy,
                    onChanged: (v) => setState(() => _energy = v),
                  ),
                  _Scale(
                    label: context.t('Fokus'),
                    low: 'zerstreut',
                    high: 'klar',
                    value: _focus,
                    onChanged: (v) => setState(() => _focus = v),
                  ),
                  _Scale(
                    label: context.t('Stimmung'),
                    low: 'gereizt',
                    high: 'gelassen',
                    value: _mood,
                    onChanged: (v) => setState(() => _mood = v),
                  ),
                  _Scale(
                    label: context.t('Reizhunger'),
                    low: 'ruhig',
                    high: 'kribbelig',
                    value: _stim,
                    onChanged: (v) => setState(() => _stim = v),
                  ),
                  if (_isEvening) ...[
                    const SizedBox(height: Space.xs),
                    Divider(color: p.rule),
                    const SizedBox(height: Space.lg),
                    _Scale(
                      label: context.t('Kraftaufwand für Struktur'),
                      low: context.t('lief nebenbei'),
                      high: context.t('ständig nachgehalten'),
                      value: _compensation,
                      onChanged: (v) => setState(() => _compensation = v),
                    ),
                    _Scale(
                      label: context.t('Erholung hat gewirkt'),
                      low: context.t('gar nicht'),
                      high: 'deutlich',
                      value: _recovery,
                      onChanged: (v) => setState(() => _recovery = v),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Die Haarlinie sagt: darueber geht es weiter. Sie steht nur da,
          // wenn ein Abschluss darunter steht — ein Strich, der nichts
          // trennt, waere das Lineal, das dieser Entwurf gerade abgeschafft
          // hat.
          Container(height: 1, color: p.rule),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.md,
              Space.lg,
              Space.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(context.t('Fertig')),
                ),
                const SizedBox(height: Space.xs),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(context.t('Jetzt nicht')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fünfstufiger Regler mit benannten Endpunkten.
///
/// Endpunkte statt Zahlen: "leer" bis "voll" ist ablesbar, "1 bis 5"
/// verlangt eine Übersetzung, die bei niedriger Kapazität Geld kostet.
///
/// **Zwei Dinge sind hier ausgetauscht, und beide aus demselben Grund.**
///
/// Erstens die **Farbe**. Jeder Regler hatte seine eigene: Energie bernstein,
/// Fokus blau, Stimmung grün, Reizhunger kupfern. Untereinander gelesen —
/// und genau so steht das Blatt da — sagte Grün „gut" und Kupfer „Achtung",
/// über dieselbe Person, viermal hintereinander. Das sind Noten, und Noten
/// sind hier verboten: Ein Zustandswert ist ein Messwert (R7). Jetzt trägt
/// jeder Regler [AxiomPalette.signal]; unterschieden wird über Beschriftung
/// und Position.
///
/// Zweitens die **Füllung**. Vorher waren alle Stufen bis zur gewählten
/// eingefärbt — ein Balken, der bei 5 voll ist. Ein voller Balken ist eine
/// Bestleistung, und „Reizhunger 5" wäre dann die beste Ablesung des
/// Tages. Gemeint ist keine Menge, sondern eine **Stelle** auf einer
/// Strecke zwischen zwei benannten Enden. Deshalb steht jetzt genau ein
/// Feld erhoben da, der Rest liegt zurück.
final class _Scale extends StatelessWidget {
  final String label;
  final String low;
  final String high;
  final int value;
  final ValueChanged<int> onChanged;

  const _Scale({
    required this.label,
    required this.low,
    required this.high,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Space.md),
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
                        // 52 statt 46: Das Blatt wird einhändig und im Gehen
                        // bedient, und ein danebengetippter Regler kostet
                        // mehr Zeit als die Zeile, die er gewinnt (G1).
                        height: 52,
                        margin: EdgeInsets.only(right: i < 5 ? Space.sm : 0),
                        decoration: BoxDecoration(
                          // Zurückliegende Felder liegen in der Mulde
                          // ([AxiomPalette.well]): dieselbe Fläche mit
                          // weniger Licht darauf. Das ist die Vertiefung,
                          // die diese Oberfläche ohnehin führt — und sie
                          // trägt in allen acht Paletten, während der
                          // Seitengrund im Kontrastschema fast so hell ist
                          // wie das Blatt selbst. Kein Rahmen: Fünf
                          // umrandete Kästchen wären ein Raster.
                          color: value == i ? p.signal : p.well,
                          borderRadius: BorderRadius.circular(Radii.control),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          ScaleEnds(low: low, high: high),
        ],
      ),
    );
  }
}
