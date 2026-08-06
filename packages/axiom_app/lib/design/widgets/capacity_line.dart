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
import '../../i18n/i18n.dart';

@immutable
final class CapacityLine extends StatelessWidget {
  /// 0..100.
  final int capacity;

  /// Aufgaben, die als Marken erscheinen.
  final List<Task> tasks;

  /// Hervorgehobene Aufgabe (die aktuell vorgeschlagene).
  final String? highlightTaskId;

  /// Ob die Leiste zu etwas führt. Steuert nur das Zeichen — den Tipp
  /// nimmt das umgebende `Panel` entgegen.
  final bool onOpen;

  const CapacityLine({
    super.key,
    required this.capacity,
    required this.tasks,
    this.highlightTaskId,
    this.onOpen = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final reachable = tasks.where((t) => t.activationEnergy <= capacity / 10);
    final beyond = tasks.length - reachable.length;

    return Semantics(
      label: context.t('Kapazitaetslinie. Kapazitaet {0} von 100. {1} von {2} Aufgaben sind jetzt startbar.', [capacity, reachable.length, tasks.length]),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // `Wrap` statt `Row`: Der Messwert rechts war unflexibel, und bei
          // 360 px und angehobener Schrift lief die Kopfzeile um bis zu
          // 88 px nach rechts hinaus — ausgerechnet die Zahl, um die es
          // geht, verschwand hinter dem Überlaufmuster. Passt beides
          // nebeneinander, sieht es aus wie vorher; passt es nicht, rutscht
          // die Kapazität in die zweite Zeile, statt abgeschnitten zu
          // werden. [D9]
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Space.md,
            runSpacing: Space.xs,
            children: [
              // War „AKTIVIERUNGSENERGIE" und „KAPAZITÄT 61" in gesperrten
              // Versalien und Schreibmaschine. Neunzehn Grossbuchstaben am
              // Stueck liest niemand als Wort, sondern Buchstabe fuer
              // Buchstabe — teuer ausgerechnet auf dem Schirm, der die
              // Antwort auf „was jetzt" tragen soll.
              Text(context.t('Aktivierungsenergie'),
                  style: Theme.of(context).textTheme.labelSmall),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.t('Kapazität'),
                      style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(width: Space.sm),
                  Text('$capacity',
                      style: readingStyle(context, size: 15, color: p.signal)),
                ],
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: capacity / 100, end: capacity / 100),
            duration: reduceMotion ? Duration.zero : Motion.settle,
            curve: Motion.instrument,
            builder: (context, threshold, _) => CustomPaint(
              painter: _CapacityLinePainter(
                labels: (
                  easy: context.t('LEICHT'),
                  here: context.t('HIER'),
                  hard: context.t('SCHWER'),
                ),
                threshold: threshold,
                tasks: tasks,
                highlightTaskId: highlightTaskId,
                palette: p,
              ),
              size: const Size(double.infinity, 62),
            ),
          ),
          const SizedBox(height: Space.sm),
          // Die Leiste führt zur vollständigen Liste. Ohne sichtbares
          // Zeichen sieht sie aus wie jede andere Kachel, und ein Weg, den
          // man nicht sieht, ist keiner [D9].
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
            switch ((reachable.length, beyond)) {
              (0, 0) => context.t('Noch keine Aufgaben erfasst.'),
              (0, _) => context.t('Heute liegt nichts davon in Reichweite. Zerlegen hilft mehr als Anlauf nehmen.'),
              (final r, 0) => context.t('{0} {1} jetzt startbar.', [r, r == 1 ? "Aufgabe ist" : "Aufgaben sind"]),
              (final r, final b) =>
                context.t('{0} startbar · {1} heute außerhalb der Reichweite', [r, b]),
            },
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (onOpen) ...[
                const SizedBox(width: Space.sm),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.chevron_right,
                      size: 16, color: context.axiom.inkFaint),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Die drei Beschriftungen der Achse.
///
/// Sie kommen von aussen, weil ein `CustomPainter` keinen `BuildContext`
/// hat — und ohne Kontext gibt es keine Sprache. Fest verdrahtet standen
/// hier drei deutsche Woerter mitten in einer sonst englischen Oberflaeche,
/// und kein Test konnte das sehen: Der i18n-Test sucht `context.t(...)`,
/// und genau das war hier nicht moeglich.
///
/// Sie bleiben in Versalien, wo alles andere sie verloren hat: LEICHT, HIER
/// und SCHWER sind vier bis sechs Zeichen, und unter sieben liest man Formen
/// statt Buchstaben. Ein Skalenstrich ist ausserdem keine Ueberschrift —
/// hier soll nichts gelesen, sondern verortet werden.
typedef CapacityLabels = ({String easy, String here, String hard});

final class _CapacityLinePainter extends CustomPainter {
  final CapacityLabels labels;
  final double threshold;
  final List<Task> tasks;
  final String? highlightTaskId;
  final AxiomPalette palette;

  const _CapacityLinePainter({
    required this.labels,
    required this.threshold,
    required this.tasks,
    required this.highlightTaskId,
    required this.palette,
  });

  static const double _axisY = 34;
  static const double _padX = 6;

  /// Wie viele Marken übereinander passen, bevor der Stapel die Leinwand
  /// verlässt.
  ///
  /// Vorher rechnete der Stapel ohne Obergrenze nach oben: `y = 34 - 10 -
  /// stack * 9`. Ab der vierten Aufgabe mit derselben Aktivierungsenergie
  /// lag der Punkt bei y = −3, ab der fünften mitten in der Kopfzeile
  /// darüber. Es gab dabei keinen Überlauffehler — weder `CustomPaint` noch
  /// `Panel` clippen —, das Bild war einfach falsch, und eine Skala, die man
  /// falsch abliest, ist schlimmer als keine. [D2]
  ///
  /// Vier gleiche Werte entstehen im Alltag von selbst: Die Triage startet
  /// bei AE 5, jede Zerlegung erzeugt einen ersten Schritt mit AE 2.
  static const int _maxStack = 2;
  static const double _markStep = 9;
  static const double _markBase = 10;

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
    //
    // Die hervorgehobene Aufgabe kommt zuerst. Sie ist die eine, die
    // sichtbar bleiben muss — nach ihr wird der Stapel gedeckelt, und wer
    // dort herausfaellt, ist nicht mehr zu sehen (G1).
    final ordered = <Task>[
      ...tasks.where((t) => t.id == highlightTaskId),
      ...tasks.where((t) => t.id != highlightTaskId),
    ];
    final byEnergy = <int, int>{};
    final hidden = <int, int>{};
    for (final task in ordered) {
      final energy = task.activationEnergy;
      final stack = byEnergy.update(energy, (v) => v + 1, ifAbsent: () => 0);
      final x = xAt(energy / 10);
      if (stack > _maxStack) {
        hidden.update(energy, (v) => v + 1, ifAbsent: () => 1);
        continue;
      }
      final y = _axisY - _markBase - stack * _markStep;
      final reachable = energy <= threshold * 10;
      final isHighlight = task.id == highlightTaskId;

      if (isHighlight) {
        // Der Hof wird nur so gross, wie oberhalb der Marke Platz ist —
        // sonst ragte gerade die wichtigste Marke aus der Leinwand.
        canvas.drawCircle(
          Offset(x, y),
          math.min(7.0, y),
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

    // Was der Stapel nicht mehr fasst, wird angeschrieben statt verschwiegen.
    // Eine stumm weggelassene Aufgabe waere derselbe Fehler wie ein Punkt
    // ausserhalb der Leinwand: Die Skala zeigt dann etwas anderes an, als da
    // ist.
    final topY = _axisY - _markBase - _maxStack * _markStep;
    hidden.forEach((energy, count) {
      final painter = TextPainter(
        text: TextSpan(
          text: '+$count',
          style: TextStyle(
            fontFamily: Fonts.sans,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFeatures: kTabularFigures,
            color: palette.inkFaint,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final anchorX = xAt(energy / 10);
      final left = anchorX + 6 + painter.width <= size.width
          ? anchorX + 6
          : anchorX - 6 - painter.width;
      painter.paint(
        canvas,
        Offset(
          math.max(0, left),
          // Der Anschlag lag bei 0 und damit exakt auf der Oberkante — die
          // Randglaettung der Schrift malte dann eine Zeile darueber, also
          // in die Kopfzeile. Zwei Pixel Luft kosten optisch nichts und
          // halten die Beschriftung sicher in der Leinwand; der Stapel
          // darunter beginnt ohnehin erst bei y = 6.
          math.max(2, topY - painter.height / 2),
        ),
      );
    });

    // ── Achsenbeschriftung ──────────────────────────────────────────────
    void label(String text, double x, Color color,
        {TextAlign align = TextAlign.left}) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: Fonts.sans,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
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

    label(labels.easy, _padX, palette.inkFaint);
    label(labels.hard, size.width - _padX, palette.inkFaint,
        align: TextAlign.right);
    // Mittige Beschriftung nur, wenn genug Platz ist.
    if (thresholdX > 78 && thresholdX < size.width - 78) {
      label(labels.here, thresholdX, palette.signal, align: TextAlign.center);
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
