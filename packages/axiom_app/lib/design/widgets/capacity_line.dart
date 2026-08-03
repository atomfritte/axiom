/// Die Kapazitaetslinie — das Kernbild dieser App.
///
/// Eine Skala der Aktivierungsenergie von 0 bis 10 mit einem Schwellenstrich
/// an der aktuellen Kapazitaet. Aufgaben sitzen als Marken auf der Skala.
///
/// Warum das die zentrale Darstellung ist: Klassische To-do-Listen sortieren
/// nach Wichtigkeit. Dabei bleibt die wichtigste Aufgabe wochenlang ganz oben
/// stehen, wird bei jedem Blick gesehen, nie gestartet — und erzeugt bei jedem
/// Blick Schuld. Schuld senkt die Regulationsreserve und macht den Start noch
/// unwahrscheinlicher.
///
/// Hier steht stattdessen sichtbar: *Das hier liegt heute in deiner
/// Reichweite. Das andere nicht — und das ist eine Messung, kein Urteil.* [D2]
library;

import 'dart:math' as math;

import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

@immutable
final class CapacityLine extends StatelessWidget {
  /// 0..100.
  final int capacity;

  /// Aufgaben, die als Marken erscheinen.
  final List<Task> tasks;

  /// Hervorgehobene Aufgabe (die aktuell vorgeschlagene).
  final String? highlightTaskId;

  const CapacityLine({
    super.key,
    required this.capacity,
    required this.tasks,
    this.highlightTaskId,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final reachable = tasks.where((t) => t.activationEnergy <= capacity / 10);
    final beyond = tasks.length - reachable.length;

    return Semantics(
      label: 'Kapazitaetslinie. Kapazitaet $capacity von 100. '
          '${reachable.length} von ${tasks.length} Aufgaben sind jetzt startbar.',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text('AKTIVIERUNGSENERGIE',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall),
              ),
              const SizedBox(width: Space.md),
              Text('KAPAZITÄT $capacity',
                  style: monoStyle(context,
                      size: 11,
                      weight: FontWeight.w600,
                      spacing: 0.8,
                      color: p.signal)),
            ],
          ),
          const SizedBox(height: Space.md),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: capacity / 100, end: capacity / 100),
            duration: reduceMotion ? Duration.zero : Motion.settle,
            curve: Motion.instrument,
            builder: (context, threshold, _) => CustomPaint(
              painter: _CapacityLinePainter(
                threshold: threshold,
                tasks: tasks,
                highlightTaskId: highlightTaskId,
                palette: p,
              ),
              size: const Size(double.infinity, 62),
            ),
          ),
          const SizedBox(height: Space.sm),
          Text(
            switch ((reachable.length, beyond)) {
              (0, 0) => 'Noch keine Aufgaben erfasst.',
              (0, _) => 'Heute liegt nichts davon in Reichweite. '
                  'Zerlegen hilft mehr als Anlauf nehmen.',
              (final r, 0) => '$r ${r == 1 ? "Aufgabe ist" : "Aufgaben sind"} '
                  'jetzt startbar.',
              (final r, final b) =>
                '$r startbar · $b heute außerhalb der Reichweite',
            },
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

final class _CapacityLinePainter extends CustomPainter {
  final double threshold;
  final List<Task> tasks;
  final String? highlightTaskId;
  final AxiomPalette palette;

  const _CapacityLinePainter({
    required this.threshold,
    required this.tasks,
    required this.highlightTaskId,
    required this.palette,
  });

  static const double _axisY = 34;
  static const double _padX = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final usable = size.width - _padX * 2;
    double xAt(double normalized) => _padX + usable * normalized.clamp(0, 1);

    // ── Skalenband ──────────────────────────────────────────────────────
    final track = Paint()
      ..color = palette.rule
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(_padX, _axisY), Offset(size.width - _padX, _axisY), track);

    // Teilstriche 0..10. Alle fuenf ein laengerer Strich — wie eine Skala.
    for (var i = 0; i <= 10; i++) {
      final x = xAt(i / 10);
      final long = i % 5 == 0;
      canvas.drawLine(
        Offset(x, _axisY),
        Offset(x, _axisY + (long ? 7 : 4)),
        Paint()
          ..color = long ? palette.inkFaint : palette.rule
          ..strokeWidth = 1,
      );
    }

    // ── Erreichbarer Bereich, sanft unterlegt ───────────────────────────
    final thresholdX = xAt(threshold);
    canvas.drawRect(
      Rect.fromLTRB(_padX, _axisY - 3, thresholdX, _axisY),
      Paint()..color = palette.signal.withValues(alpha: 0.14),
    );

    // ── Der Schwellenstrich ─────────────────────────────────────────────
    canvas.drawLine(
      Offset(thresholdX, _axisY - 22),
      Offset(thresholdX, _axisY + 10),
      Paint()
        ..color = palette.signal
        ..strokeWidth = 2,
    );
    // Kleine Fahne am Kopf — macht die Linie als Messmarke lesbar.
    final flag = Path()
      ..moveTo(thresholdX, _axisY - 22)
      ..lineTo(thresholdX + 7, _axisY - 18)
      ..lineTo(thresholdX, _axisY - 14)
      ..close();
    canvas.drawPath(flag, Paint()..color = palette.signal);

    // ── Aufgabenmarken ──────────────────────────────────────────────────
    // Gleiche Energie? Gestapelt statt uebereinander, damit nichts verdeckt.
    final byEnergy = <int, int>{};
    for (final task in tasks) {
      final energy = task.activationEnergy;
      final stack = byEnergy.update(energy, (v) => v + 1, ifAbsent: () => 0);
      final x = xAt(energy / 10);
      final y = _axisY - 10 - stack * 9.0;
      final reachable = energy <= threshold * 10;
      final isHighlight = task.id == highlightTaskId;

      if (isHighlight) {
        canvas.drawCircle(
          Offset(x, y),
          7,
          Paint()..color = palette.signal.withValues(alpha: 0.22),
        );
      }
      canvas.drawCircle(
        Offset(x, y),
        isHighlight ? 4.5 : 3.5,
        Paint()
          ..color = reachable
              ? (isHighlight ? palette.signal : palette.calm)
              : palette.inkFaint
          ..style = reachable ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }

    // ── Achsenbeschriftung ──────────────────────────────────────────────
    void label(String text, double x, Color color,
        {TextAlign align = TextAlign.left}) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: Fonts.mono,
            fontSize: 10,
            letterSpacing: 0.6,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: align,
      )..layout();
      final dx = switch (align) {
        TextAlign.right => x - painter.width,
        TextAlign.center => x - painter.width / 2,
        _ => x,
      };
      painter.paint(canvas, Offset(dx, _axisY + 12));
    }

    label('LEICHT', _padX, palette.inkFaint);
    label('SCHWER', size.width - _padX, palette.inkFaint,
        align: TextAlign.right);
    // Mittige Beschriftung nur, wenn genug Platz ist.
    if (thresholdX > 78 && thresholdX < size.width - 78) {
      label('HIER', thresholdX, palette.signal, align: TextAlign.center);
    }
  }

  @override
  bool shouldRepaint(_CapacityLinePainter old) =>
      old.threshold != threshold ||
      old.highlightTaskId != highlightTaskId ||
      old.tasks.length != tasks.length ||
      !_sameEnergies(old.tasks, tasks);

  static bool _sameEnergies(List<Task> a, List<Task> b) {
    for (var i = 0; i < math.min(a.length, b.length); i++) {
      if (a[i].activationEnergy != b[i].activationEnergy) return false;
    }
    return true;
  }
}
