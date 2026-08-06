/// Rechnet den Textkontrast jeder Palette nach, statt ihn zu glauben.
///
/// **Warum das nicht der Widget-Test erledigt.** `textContrastGuideline`
/// rendert einen Bildschirm und misst die Pixel, die dabei entstehen — und
/// gerendert wurde bisher genau eine der acht Paletten: `harness.wrap`
/// baut ohne Schema-Parameter, also immer `AxiomScheme.instrument`, und der
/// Bedienbarkeitsblock in `robustness_test.dart` ruft ihn ohne Helligkeit,
/// also immer dunkel. Sieben von acht Paletten hat nie jemand geprüft. In
/// einer davon war der Tertiärtext bei 2,96:1 gelandet — unterhalb sogar der
/// 3:1-Grenze, die für reine Grafik gilt.
///
/// Der Kontrast einer Farbrolle hängt aber gar nicht davon ab, welcher
/// Bildschirm sie gerade zeigt. Er steht in `tokens.dart` und lässt sich
/// dort ausrechnen — für alle acht Paletten, in Millisekunden, ohne
/// Referenzbild. Genau das tut diese Datei.
///
/// Maßstab ist WCAG 2.x AA für Fließtext: 4,5:1. Die Large-Text-Ausnahme
/// (3:1 ab 18,66 px fett bzw. 24 px) greift hier nirgends — die kleinste
/// Schrift der App liegt bei 12,5 px (`kMinReadableSize`), und die
/// Beschriftungen, die diese Rollen tragen, sind genau die kleinen.
/// Was nicht lesbar ist, existiert für dieses Profil nicht [D9].
library;

import 'dart:math' as math;

import 'package:axiom_app/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Relative Leuchtdichte nach WCAG 2.x.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

/// Kontrastverhältnis zweier Farben, 1:1 bis 21:1.
double contrastRatio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Die Rollen, die als Text erscheinen — und damit 4,5:1 halten müssen.
///
/// `signalDeep` fehlt bewusst: Er ist der gedrückte Zustand der Signalfarbe,
/// also eine Fläche, kein Text. Der Test unten hält fest, dass das so bleibt.
/// `rule` ist eine Haarlinie, `base`/`panel`/`panelRaised` sind die Flächen.
const _textRoles = <String>[
  'ink',
  'inkDim',
  'inkFaint',
  'signal',
  'calm',
  'caution',
  'info',
];

Color _role(AxiomPalette p, String name) => switch (name) {
      'ink' => p.ink,
      'inkDim' => p.inkDim,
      'inkFaint' => p.inkFaint,
      'signal' => p.signal,
      'calm' => p.calm,
      'caution' => p.caution,
      'info' => p.info,
      _ => throw ArgumentError(name),
    };

const _surfaces = <String>['base', 'panel', 'panelRaised'];

Color _surface(AxiomPalette p, String name) => switch (name) {
      'base' => p.base,
      'panel' => p.panel,
      'panelRaised' => p.panelRaised,
      _ => throw ArgumentError(name),
    };

/// Untergrenze für Fließtext nach WCAG 2.x AA.
const double kMinContrast = 4.5;

void main() {
  group('Textkontrast', () {
    for (final scheme in AxiomScheme.values) {
      for (final brightness in Brightness.values) {
        final palette = scheme.palette(brightness);
        final label = '${scheme.name}/${brightness.name}';

        test('$label: jede Textrolle hält 4,5:1 auf jeder Fläche', () {
          final tooLow = <String>[];
          for (final role in _textRoles) {
            for (final surface in _surfaces) {
              final ratio = contrastRatio(
                  _role(palette, role), _surface(palette, surface));
              if (ratio < kMinContrast) {
                tooLow.add('$role auf $surface = '
                    '${ratio.toStringAsFixed(2)}:1');
              }
            }
          }
          expect(tooLow, isEmpty,
              reason: '$label liegt unter der Lesbarkeitsgrenze:\n'
                  '${tooLow.join("\n")}');
        });

        test('$label: Sekundärtext bleibt heller als Tertiärtext', () {
          // Sonst tauschen die beiden Rollen beim Anheben stillschweigend
          // die Bedeutung: Eine Fußnote, die kräftiger wirkt als die
          // Beschriftung darüber, liest sich als das Wichtigere.
          expect(
            contrastRatio(palette.inkDim, palette.base),
            greaterThan(contrastRatio(palette.inkFaint, palette.base)),
            reason: label,
          );
          expect(
            contrastRatio(palette.ink, palette.base),
            greaterThan(contrastRatio(palette.inkDim, palette.base)),
            reason: label,
          );
        });
      }
    }

    for (final scheme in AxiomScheme.values) {
      for (final brightness in Brightness.values) {
        final palette = scheme.palette(brightness);
        final label = '${scheme.name}/${brightness.name}';

        test('$label: signalDeep bleibt als Fläche unterscheidbar', () {
          // `signalDeep` ist der gedrückte Zustand der Signalfarbe, also
          // eine Fläche und kein Text. Für den gilt WCAG 1.4.11: 3:1 gegen
          // die Umgebung, sonst ist der gedrückte Knopf vom ungedrückten
          // nicht zu unterscheiden. Wird die Rolle je einem `Text` gegeben,
          // gehört sie nach oben zu `_textRoles` — dort sind es 4,5:1.
          for (final surface in _surfaces) {
            expect(
              contrastRatio(palette.signalDeep, _surface(palette, surface)),
              greaterThanOrEqualTo(3.0),
              reason: '$label: signalDeep auf $surface',
            );
          }
        });
      }
    }
  });
}
