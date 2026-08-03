/// Instrumente — die Bausteine der Zustandsanzeige.
///
/// Jeder Messwert zeigt auf Wunsch seine Herleitung. Ein Score ohne
/// sichtbaren Rechenweg ist fuer dieses Nutzerprofil Willkuer (G2).
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../tokens.dart';
import '../../i18n/i18n.dart';

/// Eine Messwertzeile: Name, Balken, Zahl — aufklappbar zur Herleitung.
final class InstrumentBar extends StatefulWidget {
  final String label;

  /// 0..100.
  final int value;
  final Color color;

  /// Kurze Einordnung ohne Bewertung ("ausgeruht", "hohe Last").
  final String? reading;

  /// Terme der Formel. Leer = nicht aufklappbar.
  final List<Term> breakdown;

  /// 0..1. Unter 0.4 feuern Regeln nicht — das wird sichtbar gemacht.
  final double confidence;

  const InstrumentBar({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.reading,
    this.breakdown = const [],
    this.confidence = 1.0,
  });

  @override
  State<InstrumentBar> createState() => _InstrumentBarState();
}

class _InstrumentBarState extends State<InstrumentBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final expandable = widget.breakdown.isNotEmpty;
    final stale = widget.confidence < 0.4;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      button: expandable,
      label: context.t('{0}: {1} von 100{2}{3}', [widget.label, widget.value, widget.reading == null ? "" : ", ${widget.reading}", stale ? context.t(', Daten veraltet') : ""]),
      child: InkWell(
        onTap: expandable
            ? () {
                HapticFeedback.selectionClick();
                setState(() => _expanded = !_expanded);
              }
            : null,
        borderRadius: BorderRadius.circular(Radii.control),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(widget.label.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall),
                  ),
                  if (stale)
                    Padding(
                      padding: const EdgeInsets.only(right: Space.sm),
                      child: Text(context.t('DATEN ALT'),
                          style: monoStyle(context,
                              size: 9.5, spacing: 0.8, color: p.inkFaint)),
                    ),
                  Text(
                    '${widget.value}',
                    style: monoStyle(context,
                        size: 15,
                        weight: FontWeight.w600,
                        color: stale ? p.inkFaint : widget.color),
                  ),
                  if (expandable)
                    Padding(
                      padding: const EdgeInsets.only(left: Space.xs),
                      child: AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: reduceMotion ? Duration.zero : Motion.quick,
                        child: Icon(Icons.keyboard_arrow_down,
                            size: 16, color: p.inkFaint),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Space.xs + 2),
              _Bar(
                value: widget.value,
                color: stale ? p.inkFaint : widget.color,
                track: p.rule,
              ),
              if (widget.reading != null) ...[
                const SizedBox(height: Space.xs + 2),
                Text(widget.reading!,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              // AnimatedSize statt AnimatedCrossFade: Letzteres haelt beide
              // Kinder dauerhaft im Baum — die eingeklappte Herleitung waere
              // fuer Screenreader und Suchen weiterhin vorhanden.
              AnimatedSize(
                duration: reduceMotion ? Duration.zero : Motion.quick,
                curve: Motion.instrument,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? _Breakdown(terms: widget.breakdown)
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _Bar extends StatelessWidget {
  final int value;
  final Color color;
  final Color track;
  const _Bar({required this.value, required this.color, required this.track});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          Container(height: 4, color: track),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: value / 100, end: value / 100),
            duration: reduceMotion ? Duration.zero : Motion.settle,
            curve: Motion.instrument,
            builder: (context, t, _) => Container(
              height: 4,
              width: constraints.maxWidth * t,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Die Herleitung: jeder Term mit seinem Beitrag.
final class _Breakdown extends StatelessWidget {
  final List<Term> terms;
  const _Breakdown({required this.terms});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: Space.md),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: p.base,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: p.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t('SO WIRD GERECHNET'),
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Space.sm),
          for (final term in terms)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(term.label,
                        style: monoStyle(context, size: 12, color: p.inkDim)),
                  ),
                  Text(
                    '${term.contribution >= 0 ? "+" : "−"}'
                    '${term.contribution.abs().toStringAsFixed(1)}',
                    style: monoStyle(
                      context,
                      size: 12,
                      weight: FontWeight.w500,
                      color: term.contribution >= 0 ? p.calm : p.caution,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Kleine Plakette mit der Regel-ID. Macht G2 sichtbar: Jede Ausgabe traegt
/// die Regel, die sie erzeugt hat.
final class RuleStamp extends StatelessWidget {
  final String ruleId;
  final VoidCallback? onTap;
  final Color? color;

  const RuleStamp({super.key, required this.ruleId, this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final tint = color ?? p.info;
    return Semantics(
      button: onTap != null,
      label: context.t('Regel {0}{1}', [ruleId, onTap == null ? "" : context.t(', zeigt die Begruendung')]),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.control),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: Space.sm, vertical: Space.xs),
          decoration: BoxDecoration(
            border: Border.all(color: tint.withValues(alpha: 0.45)),
            borderRadius: BorderRadius.circular(Radii.control),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(ruleId,
                  style: monoStyle(context,
                      size: 11, weight: FontWeight.w600, spacing: 0.6,
                      color: tint)),
              if (onTap != null) ...[
                const SizedBox(width: Space.xs),
                Icon(Icons.info_outline, size: 12, color: tint),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Karte im Frontplatten-Stil.
final class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? accent;
  final VoidCallback? onTap;

  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.lg),
    this.accent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final content = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(Radii.panel),
        border: Border.all(color: accent ?? p.rule),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.panel),
      child: content,
    );
  }
}

/// Abschnittsueberschrift im Skalen-Stil.
final class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Row(
        children: [
          Text(text.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(width: Space.md),
          Expanded(child: Container(height: 1, color: p.rule)),
          if (trailing != null) ...[
            const SizedBox(width: Space.md),
            trailing!,
          ],
        ],
      ),
    );
  }
}
