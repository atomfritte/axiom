/// Review — M11.
///
/// Aufgebaut wie ein Ops-Review, nicht wie ein Tagebuch: Kennzahlen,
/// Abweichungen, Entscheidungen. Ein „Gefühlstagebuch" wird von diesem Profil
/// nicht geführt, ein Wochenbericht schon — identischer Inhalt, anderes
/// Framing, und das Framing entscheidet über die Adhärenz. [D10, D12]
///
/// Der Zeitdeckel läuft sichtbar mit und schließt am Ende. Das ist keine
/// Bequemlichkeit: Ein Review ohne Grenze wird zur Meta-Work-Fläche (D3).
library;

import 'dart:async';

import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/widgets/instruments.dart';
import '../state/providers.dart';
import '../state/runtime.dart';
import '../i18n/i18n.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  final ReviewScope scope;
  const ReviewScreen({super.key, this.scope = ReviewScope.day});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final _startedAt = DateTime.now();
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  bool _closing = false;

  /// Waehrend des Aufbaus gemerkt: In dispose() ist `ref` nicht mehr
  /// benutzbar, die Nutzungszeit muss aber genau dann gebucht werden.
  AxiomRuntime? _runtime;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = DateTime.now().difference(_startedAt));
      if (_elapsed >= widget.scope.timeCap && !_closing) _closeOnTimeCap();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    // Review-Zeit zählt aufs Meta-Work-Budget — sie ist Arbeit am System,
    // nicht Arbeit im Leben (M12).
    _runtime?.logScreenTime('review', DateTime.now().difference(_startedAt));
    super.dispose();
  }

  Future<void> _closeOnTimeCap() async {
    _closing = true;
    await HapticFeedback.mediumImpact();
    if (!mounted) return;
    await _finish(reachedCap: true);
  }

  Future<void> _finish({bool reachedCap = false}) async {
    final runtime = await ref.read(runtimeProvider.future);
    final spent = DateTime.now().difference(_startedAt);
    await runtime.completeReview(widget.scope, spent);
    runtime.markReviewDone(widget.scope);
    refreshAxiom(ref);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(reachedCap
            ? context.t('Zeit um. Der Rest wartet bis zum nächsten Mal.')
            : context.t('{0}-Review abgeschlossen.', [widget.scope.label])),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _runtime ??= ref.watch(runtimeProvider).value;
    final review = ref.watch(reviewProvider(widget.scope));

    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('{0}-Review', [widget.scope.label])),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _TimeCapBar(elapsed: _elapsed, cap: widget.scope.timeCap),
        ),
      ),
      body: review.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (data) => ListView(
          padding: const EdgeInsets.fromLTRB(
              Space.lg, Space.lg, Space.lg, Space.huge),
          children: [
            _TimeCapNotice(scope: widget.scope, elapsed: _elapsed),
            const SizedBox(height: Space.xl),

            SectionLabel(context.t('Kennzahlen')),
            for (final metric in data.metrics)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.md),
                child: _MetricCard(metric: metric),
              ),

            if (data.verdicts.isNotEmpty) ...[
              const SizedBox(height: Space.xl),
              SectionLabel(context.t('Regelwerk · {0} offen', [data.verdicts.length])),
              for (final verdict in data.verdicts)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: _VerdictCard(verdict: verdict),
                ),
              const SizedBox(height: Space.sm),
              Text(
                widget.scope.allowsRuleChanges
                    ? context.t('Regeländerungen gehören in dieses Zeitfenster — und nur hierher.')
                    : context.t('Geändert wird erst im Wochen-Review.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],

            const SizedBox(height: Space.xl),
            _Prompts(scope: widget.scope),

            const SizedBox(height: Space.xl),
            FilledButton(
              onPressed: () => _finish(),
              child: Text(context.t('Review abschließen')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Die Zeit läuft sichtbar mit.
class _TimeCapBar extends StatelessWidget {
  final Duration elapsed;
  final Duration cap;
  const _TimeCapBar({required this.elapsed, required this.cap});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final ratio = (elapsed.inSeconds / cap.inSeconds).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, c) => Stack(
        children: [
          Container(height: 2, color: p.rule),
          Container(
            height: 2,
            width: c.maxWidth * ratio,
            color: ratio > 0.8 ? p.caution : p.signal,
          ),
        ],
      ),
    );
  }
}

class _TimeCapNotice extends StatelessWidget {
  final ReviewScope scope;
  final Duration elapsed;
  const _TimeCapNotice({required this.scope, required this.elapsed});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final left = scope.timeCap - elapsed;
    final minutes = left.inMinutes;
    final seconds = left.inSeconds % 60;

    return Row(
      children: [
        Flexible(
          child: Text(context.t('ZEITDECKEL'),
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall),
        ),
        const SizedBox(width: Space.md),
        Text(
          left.isNegative
              ? 'abgelaufen'
              : context.t('{0}:{1} übrig', [minutes, seconds.toString().padLeft(2, "0")]),
          style: monoStyle(context,
              size: 13,
              weight: FontWeight.w600,
              color: minutes < 2 ? p.caution : p.inkDim),
        ),
        const SizedBox(width: Space.md),
        Expanded(
          child: Text(context.t('von {0} min', [scope.timeCap.inMinutes]),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: monoStyle(context, size: 11, color: p.inkFaint)),
        ),
      ],
    );
  }
}

class _MetricCard extends StatefulWidget {
  final Metric metric;
  const _MetricCard({required this.metric});

  @override
  State<_MetricCard> createState() => _MetricCardState();
}

class _MetricCardState extends State<_MetricCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final m = widget.metric;
    // Die Farbe traegt die Bewertung, der Pfeil nur die Richtung der Zahl.
    // Beides in ein Symbol zu packen liest sich zwangslaeufig falsch: Bei
    // "Messpunkte erfasst" ist mehr gut, bei "Kompensationslast" schlecht.
    final accent = m.needsAttention ? p.caution : p.calm;

    return Panel(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(context.t(m.label).toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall),
              ),
              if (m.trend != null)
                Icon(
                  switch (m.trend!) {
                    MetricTrend.up => Icons.arrow_upward,
                    MetricTrend.down => Icons.arrow_downward,
                    MetricTrend.flat => Icons.remove,
                  },
                  size: 14,
                  color: p.inkDim,
                ),
              if (m.needsAttention) ...[
                const SizedBox(width: Space.sm),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: p.caution,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(context.p(m.valueSource),
              style: TextStyle(
                fontFamily: Fonts.mono,
                fontSize: 19,
                fontWeight: FontWeight.w400,
                color: p.ink,
              )),
          if (m.consequence != null) ...[
            const SizedBox(height: Space.md),
            Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                border: Border.all(color: accent.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              child: Text(context.t(m.consequence!),
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
          if (_expanded) ...[
            const SizedBox(height: Space.md),
            Text(context.t('SO WIRD GERECHNET'),
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: Space.xs),
            Text(context.t(m.derivation),
                style: monoStyle(context, size: 11.5)),
          ],
        ],
      ),
    );
  }
}

class _VerdictCard extends StatelessWidget {
  final RuleVerdict verdict;
  const _VerdictCard({required this.verdict});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final (label, color) = switch (verdict.verdict) {
      RuleAction.retire => ('STREICHEN', p.caution),
      RuleAction.widen => (context.t('ZU ENG'), p.info),
      RuleAction.resolveConflict => ('KONFLIKT', p.signal),
    };

    return Panel(
      padding: const EdgeInsets.symmetric(
          horizontal: Space.lg, vertical: Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RuleStamp(ruleId: verdict.ruleId, color: color),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: monoStyle(context,
                        size: 10, weight: FontWeight.w600, color: color)),
                const SizedBox(height: 2),
                Text(context.t(verdict.reason),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Die Leitfragen des jeweiligen Umfangs.
class _Prompts extends StatelessWidget {
  final ReviewScope scope;
  const _Prompts({required this.scope});

  static Map<ReviewScope, List<String>> _byScope(BuildContext context) => {
    ReviewScope.day: [
      context.t('Was ist heute liegengeblieben, das nicht liegenbleiben durfte?'),
      context.t('Morgen: ein Anker, eine Aufgabe.'),
    ],
    ReviewScope.week: [
      context.t('Was ist auffällig abgewichen?'),
      context.t('Welche Regel hat genervt statt geholfen?'),
      context.t('Nächste Woche: höchstens drei Vorhaben.'),
    ],
    ReviewScope.month: [
      context.t('Wovon habe ich mich lautlos verabschiedet?'),
      context.t('Gab es Erhaltungsmodus-Tage? Was ging voraus?'),
      context.t('Welches Modul ist reif — und welches kann weg?'),
    ],
    ReviewScope.quarter: [
      context.t('Ist die Last gesunken? Belegen, nicht behaupten.'),
      context.t('Rechtfertigt AXIOM seine eigenen Kosten?'),
      context.t('Was kann WEG?'),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(context.t('Kurz durchgehen')),
        for (final prompt in _byScope(context)[scope]!)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(width: 10, height: 1, color: p.inkFaint),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(prompt,
                      style: Theme.of(context).textTheme.bodyLarge),
                ),
              ],
            ),
          ),
        if (scope == ReviewScope.quarter)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Text(
              context.t('Der letzte Punkt ist Pflicht. Jedes Review ohne Streichoption lässt das System nur wachsen.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
