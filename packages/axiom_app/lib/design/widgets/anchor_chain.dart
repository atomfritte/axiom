/// Die Ankerkette — das visuelle Kernstück von M3.
///
/// Ein Kalender zeigt „14:00 Zahnarzt". Was er nicht zeigt: dass um 13:00
/// Schluss ist mit allem anderen. Genau diese Rechnung läuft bei diesem
/// Profil sonst permanent im Kopf mit, kostet Aufmerksamkeit und erzeugt
/// Dauerspannung vor jedem Termin [D4].
///
/// Hier steht sie einmal fertig da — mit der Vorlaufzeit als eigener Zahl,
/// weil die erklärt, warum ein einstündiger Termin einen Nachmittag kostet.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

@immutable
final class AnchorChainView extends StatelessWidget {
  final Anchor anchor;
  final DateTime now;

  /// Kompakt: nur der nächste Schritt. Für die Übersicht.
  final bool compact;

  const AnchorChainView({
    super.key,
    required this.anchor,
    required this.now,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final steps = anchor.chain;
    final next = anchor.nextStep(now);

    return Semantics(
      label: '${anchor.title} um ${_hhmm(anchor.arriveBy)}. '
          'Vorlauf ${anchor.leadTime.inMinutes} Minuten. '
          '${next == null ? "Vorbei." : "Als Nächstes: ${next.label} um ${_hhmm(next.at)}."}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(anchor.title,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              const SizedBox(width: Space.md),
              Text(_hhmm(anchor.arriveBy),
                  style: monoStyle(context,
                      size: 15, weight: FontWeight.w600, color: p.ink)),
            ],
          ),
          const SizedBox(height: Space.xs),
          Row(
            children: [
              Text('VORLAUF ${anchor.leadTime.inMinutes} MIN',
                  style: monoStyle(context,
                      size: 10, spacing: 0.6, color: p.signal)),
              if (anchor.location != null) ...[
                const SizedBox(width: Space.md),
                Flexible(
                  child: Text(anchor.location!,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle(context, size: 10, spacing: 0.4)),
                ),
              ],
            ],
          ),
          const SizedBox(height: Space.lg),
          for (final (index, step) in steps.indexed)
            if (!compact || step == next || step == steps.last)
              _StepRow(
                step: step,
                now: now,
                isNext: step == next,
                isLast: index == steps.length - 1,
                showConnector: !compact,
              ),
        ],
      ),
    );
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, "0")}:'
      '${t.minute.toString().padLeft(2, "0")}';
}

class _StepRow extends StatelessWidget {
  final AnchorStep step;
  final DateTime now;
  final bool isNext;
  final bool isLast;
  final bool showConnector;

  const _StepRow({
    required this.step,
    required this.now,
    required this.isNext,
    required this.isLast,
    required this.showConnector,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final past = step.at.isBefore(now);
    final minutes = step.at.difference(now).inMinutes;

    final color = past
        ? p.inkFaint
        : isNext
            ? p.signal
            : p.inkDim;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Zeitspalte, monospaced — sie muss untereinander fluchten.
          SizedBox(
            width: 48,
            child: Text(
              AnchorChainView._hhmm(step.at),
              style: monoStyle(context,
                  size: 13,
                  weight: isNext ? FontWeight.w600 : FontWeight.w400,
                  color: color),
            ),
          ),
          // Zeitstrahl.
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(
                  width: isNext ? 9 : 6,
                  height: isNext ? 9 : 6,
                  margin: EdgeInsets.only(top: isNext ? 4 : 6),
                  decoration: BoxDecoration(
                    color: past || step.kind == AnchorStepKind.arrive
                        ? color
                        : Colors.transparent,
                    border: Border.all(color: color, width: 1.4),
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast && showConnector)
                  Expanded(
                    child: Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: p.rule,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.label,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: color,
                          fontWeight:
                              isNext ? FontWeight.w500 : FontWeight.w400,
                          decoration:
                              past ? TextDecoration.lineThrough : null,
                          decorationColor: p.inkFaint,
                        ),
                  ),
                  if (isNext && minutes >= 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        minutes == 0
                            ? 'jetzt'
                            : minutes < 60
                                ? 'in $minutes min'
                                : 'in ${(minutes / 60).toStringAsFixed(1)} h',
                        style: monoStyle(context, size: 11, color: p.signal),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kompakte Zeile für die Hauptansicht: der eine nächste Schritt.
final class NextStepBadge extends StatelessWidget {
  final Anchor anchor;
  final AnchorStep step;
  final DateTime now;

  const NextStepBadge({
    super.key,
    required this.anchor,
    required this.step,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final minutes = step.at.difference(now).inMinutes;
    // Unter zwanzig Minuten wird der Hinweis dringlicher — aber nie laut.
    final near = minutes <= 20;

    return Row(
      children: [
        Container(
          width: 3,
          height: 34,
          decoration: BoxDecoration(
            color: near ? p.signal : p.info,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: Space.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(step.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge),
              Text(
                '${anchor.title} · ${AnchorChainView._hhmm(anchor.arriveBy)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: Space.md),
        Text(
          minutes <= 0
              ? 'jetzt'
              : minutes < 60
                  ? '$minutes min'
                  : '${(minutes / 60).toStringAsFixed(1)} h',
          style: monoStyle(context,
              size: 13,
              weight: FontWeight.w600,
              color: near ? p.signal : p.inkDim),
        ),
      ],
    );
  }
}
