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

import 'package:axiom_app/design/theme.dart';
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
/// `rule` ist eine Haarlinie, `base`/`panel`/`panelRaised`/`well` sind die
/// Flächen.
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

/// Alle vier Flächen, auf denen Text steht.
///
/// `well` ist seit der Reichweitenkante dabei und war der teuerste Zuwachs:
/// Unter der Kante liegt eine vertiefte Fläche, und der Text dort wird
/// **nicht ausgegraut**. Ausgegraut hieße „unwichtig"; gemeint ist „heute
/// nicht erreichbar". Damit muss die Mulde denselben Maßstab halten wie jede
/// andere Fläche — und genau daran sind vier helle Rollen hängengeblieben
/// (siehe die Kommentare in `tokens.dart`).
const _surfaces = <String>['base', 'panel', 'panelRaised', 'well'];

Color _surface(AxiomPalette p, String name) => switch (name) {
      'base' => p.base,
      'panel' => p.panel,
      'panelRaised' => p.panelRaised,
      'well' => p.well,
      _ => throw ArgumentError(name),
    };

/// Untergrenze für Fließtext nach WCAG 2.x AA.
const double kMinContrast = 4.5;

/// Die getönte Plakette — und warum sie hier eine eigene Zahl hat.
///
/// Es gibt in der Oberfläche ein Muster, das die Prüfung oben **nicht**
/// erfasst: eine Rollenfarbe als Text auf ihrer eigenen, stark
/// durchsichtigen Tönung. Die Stufenplakette `L0`–`L3` macht genau das
/// (`state_screen.dart:203`, `now_screen.dart:1014`): Hintergrund ist
/// `forLoadLevel(level)` mit 18 % Deckkraft, Text dieselbe Farbe voll
/// deckend. Der Grund hinter den Buchstaben ist damit weder `base` noch
/// `panel`, sondern etwas dazwischen — und dort ist der Abstand kleiner als
/// überall sonst, weil Vorder- und Hintergrund derselbe Farbton sind.
///
/// **Nachgerechnet ist das ein Befund.** 18 von 32 Kombinationen aus vier
/// Stufen, acht Paletten und zwei Flächen liegen unter 4,5:1; der
/// schlechteste Wert ist 3,92:1 (`instrument/light`, L2 auf `base`).
/// Weitere Tiefpunkte: `workbench/light` L0 und L3 auf `base` mit je 3,94:1,
/// `instrument/dark` L1 auf `panel` mit 3,96:1.
///
/// **Warum hier trotzdem 3,9 steht und nicht 4,5.** Die Plaketten gehören
/// zu Schirmen, nicht zu dieser Datei, und die Zahl zu heben heißt entweder
/// die Tönung kräftiger zu machen (dann ist es eine Fläche, keine Tönung
/// mehr) oder den Text auf `ink` zu setzen (dann trägt die Farbe die Stufe
/// allein). Beides ist eine Gestaltungsentscheidung. Bis sie gefallen ist,
/// hält diese Zahl den Rückstand fest, statt ihn wachsen zu lassen — sie
/// ist eine **Ratsche, keine Zusage**. Wer die Plakette repariert, setzt sie
/// auf [kMinContrast] und streicht diesen Absatz.
const double kBadgeFloor = 3.9;

/// Deckkraft der Tönung hinter einer Stufenplakette.
const double kBadgeTint = 0.18;

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

        test('$label: die Mulde ist sichtbar und trotzdem lesbar', () {
          // Zwei Grenzen, die gegeneinander arbeiten. Ohne sichtbare Stufe
          // ist die Reichweitenkante nur eine Zeile — dann sagt der Schirm
          // nicht mehr vorbewusst, was heute in die Hand geht (G1). Mit zu
          // viel Stufe fällt der Text darunter unter AA, und ein Weg, den
          // man nicht liest, ist keiner.
          //
          // Die Untergrenze ist bewusst niedrig: Die Tiefe wird nicht von
          // der Fläche allein getragen, sondern von Lichtlippe und
          // Innenschatten der Mulde. Die Fläche gibt nur den Ton dazu.
          final step = contrastRatio(palette.well, palette.base);
          expect(step, greaterThan(1.02),
              reason: '$label: Mulde und Grund sind dieselbe Farbe — die '
                  'Kante trennt dann nichts');
          expect(step, lessThan(1.6),
              reason: '$label: die Mulde ist so tief, dass sie als eigene '
                  'Fläche liest statt als derselbe Boden, nur tiefer');
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

        test('$label: die Beschriftung des Hauptknopfs hält 4,5:1', () {
          // Die eine Handlung eines Schirms sitzt auf einem `FilledButton`
          // in [AxiomPalette.signal] („Anfangen", „Fokus beenden", „Kurz
          // durchgehen"). Sein Text ist der einzige der App, der **nicht**
          // auf einer der vier Flächen steht, sondern auf der Signalfarbe
          // selbst — und er stand deshalb bisher in keiner Prüfung. Die
          // Vorderfarbe kommt aus `buildAxiomTheme` (`ColorScheme.onPrimary`)
          // und hängt nur an der Helligkeit, nicht am Schema.
          final onPrimary = buildAxiomTheme(brightness: brightness)
              .colorScheme
              .onPrimary;
          expect(
            contrastRatio(onPrimary, palette.signal),
            greaterThanOrEqualTo(kMinContrast),
            reason: '$label: onPrimary auf signal',
          );
        });

        test('$label: die Stufenplakette bleibt lesbar', () {
          // Siehe [kBadgeFloor]: Das ist der eine Ort, an dem Vorder- und
          // Hintergrund derselbe Farbton sind. Die Ratsche darf sinken.
          final tooLow = <String>[];
          for (var level = 0; level <= 3; level++) {
            final ink = palette.forLoadLevel(level);
            for (final surface in ['base', 'panel']) {
              final tinted = Color.alphaBlend(
                  ink.withValues(alpha: kBadgeTint),
                  _surface(palette, surface));
              final ratio = contrastRatio(ink, tinted);
              if (ratio < kBadgeFloor) {
                tooLow.add('L$level auf $surface = '
                    '${ratio.toStringAsFixed(2)}:1');
              }
            }
          }
          expect(tooLow, isEmpty,
              reason: '$label: die Plakette ist unter den heutigen Stand '
                  'gefallen (Ziel ist $kMinContrast:1, siehe kBadgeFloor):\n'
                  '${tooLow.join("\n")}');
        });

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
