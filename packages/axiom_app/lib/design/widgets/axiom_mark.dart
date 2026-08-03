/// Die Bildmarke als Widget.
///
/// Gezeichnet statt als Bild eingebunden: So folgt sie der Palette (hell und
/// dunkel) und bleibt bei jeder Groesse scharf. Das Zeichen ist dieselbe
/// Kapazitaetslinie, die die App ausmacht — eine Skala mit einer gesetzten
/// Schwelle.
library;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../../i18n/i18n.dart';

@immutable
final class AxiomMark extends StatelessWidget {
  final double size;

  /// Einfarbig zeichnen — fuer Stellen, an denen die Marke sich unterordnet.
  final Color? color;

  const AxiomMark({super.key, this.size = 32, this.color});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Semantics(
      label: context.t('AXIOM'),
      child: CustomPaint(
        size: Size(size, size * 0.62),
        painter: _MarkPainter(
          reachable: color ?? p.signal,
          beyond: color ?? p.rule,
        ),
      ),
    );
  }
}

final class _MarkPainter extends CustomPainter {
  final Color reachable;
  final Color beyond;
  const _MarkPainter({required this.reachable, required this.beyond});

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 72;
    final baseline = size.height * 0.72;

    // In Reichweite: kraeftig.
    canvas.drawRect(
      Rect.fromLTWH(0, baseline - 4.5 * unit, 36 * unit, 9 * unit),
      Paint()..color = reachable,
    );
    // Darueber hinaus: vorhanden, aber zurueckgenommen.
    canvas.drawRect(
      Rect.fromLTWH(36 * unit, baseline - 1.5 * unit, 36 * unit, 3 * unit),
      Paint()..color = beyond,
    );
    // Die gesetzte Schwelle.
    canvas.drawRect(
      Rect.fromLTWH(32 * unit, baseline - 27 * unit, 9 * unit, 35 * unit),
      Paint()..color = reachable,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.reachable != reachable || old.beyond != beyond;
}

/// Marke mit Schriftzug. Fuer Splash und Onboarding-Kopf.
final class AxiomWordmark extends StatelessWidget {
  final double markSize;
  const AxiomWordmark({super.key, this.markSize = 34});

  @override
  Widget build(BuildContext context) {
    final p = context.axiom;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AxiomMark(size: markSize),
        SizedBox(width: markSize * 0.55),
        Text(
          context.t('AXIOM'),
          style: TextStyle(
            fontFamily: 'PlexSans',
            fontSize: markSize * 0.62,
            fontWeight: FontWeight.w300,
            letterSpacing: markSize * 0.22,
            color: p.ink,
          ),
        ),
      ],
    );
  }
}
