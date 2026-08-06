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

/// Deckkraft der Tönung hinter einem **gewählten Chip**.
///
/// Zweiter Ort desselben Musters, und einer, den die Plakettenprüfung oben
/// nicht erfasst: Der gewählte Formenchip im Zerlegen-Blatt
/// (`atomize_sheet.dart`, `_ShapeChip`) liegt in der Mulde, nicht auf `base`
/// oder `panel` — sein Grund ist `signal` mit 16 % über [AxiomPalette.well],
/// seine Schrift dieselbe Signalfarbe voll deckend.
const double kChipTint = 0.16;

/// Der heutige Stand für Signaltext auf Signaltönung in der Mulde.
///
/// **Nachgerechnet ist auch das ein Befund.** In den drei hellen Fassungen
/// außer `contrast` liegt der Wert unter AA: `instrument/light` 3,73:1,
/// `workbench/light` 3,82:1, `muted/light` 3,88:1. Der Grund ist derselbe
/// wie bei [kBadgeFloor] — Vorder- und Hintergrund sind derselbe Farbton —,
/// nur zusätzlich verschärft durch die Mulde: Sie zieht dem hellen Grund
/// 4 % Licht ab und dem Abstand damit ein Stück.
///
/// Der Chip ist eine Auswahl, kein Fließtext, und er trägt neben der Farbe
/// einen 1,5 px starken Rand in derselben Signalfarbe — gewählt oder nicht
/// ist also auch ohne den Textkontrast zu sehen. Trotzdem steht hier eine
/// Zahl und keine Ausnahme: Der Text **wird** gelesen, und wer die Tönung
/// kräftiger macht oder den Text auf `ink` setzt, hebt sie. Ratsche, keine
/// Zusage — sie darf sinken.
const double kChipFloor = 3.7;

/// Der heutige Stand für die Umrandung eines Eingabefelds.
///
/// **Der dritte Befund, und der praktischste.** Ein leeres Textfeld ist in
/// dieser Oberfläche gefüllt (`fillColor: panel`) und von einer Haarlinie in
/// [AxiomPalette.rule] umrandet. Steht es in einem Blatt, ist der Grund
/// ringsum ebenfalls `panel` — dann trägt allein die Haarlinie die Aussage
/// „hier kann man schreiben". Sie kommt in keiner der acht Fassungen über
/// **2,16:1**, im Regelfall liegt sie bei 1,3 bis 1,6:1, und in der Werkbank
/// gegen den Grund bei 1,21:1 — dem schlechtesten Wert der Palette. WCAG 1.4.11
/// verlangt für die Grenze eines Bedienelements 3:1, und anders als bei
/// einem Knopf gibt es hier keine Beschriftung, die das auffängt: Vor der
/// ersten Eingabe steht dort nur ein Hinweistext in [AxiomPalette.inkFaint].
///
/// Zu beheben wäre das in `tokens.dart` (kräftigere `rule`) oder in
/// `theme.dart` (eigener, kräftigerer `enabledBorder` nur für Felder) — beides
/// außerhalb dieser Datei. Bis dahin hält die Zahl den Stand fest.
const double kFieldEdgeFloor = 1.2;

/// Rollen, die im gedämpften Modus heute **heller** sind als in der Vorgabe.
///
/// Siehe die Gruppe „Der gedämpfte Modus" unten. Ratsche: Die Menge darf
/// kleiner werden, nicht größer.
const _mutedBrighter = <String>{'calm', 'info'};

/// Rollen, die im gedämpften Modus heute **mehr Blau** tragen als in der
/// Vorgabe. Ebenfalls eine Ratsche, siehe unten.
const _mutedMoreBlue = <String>{'signal', 'signalDeep', 'calm', 'caution'};

/// Alle zwölf Farbrollen einer Palette, für den Vergleich zweier Schemata.
const _allRoles = <String>[
  'base',
  'panel',
  'panelRaised',
  'rule',
  'ink',
  'inkDim',
  'inkFaint',
  'signal',
  'signalDeep',
  'calm',
  'caution',
  'info',
];

Color _anyRole(AxiomPalette p, String name) => switch (name) {
      'base' => p.base,
      'panel' => p.panel,
      'panelRaised' => p.panelRaised,
      'rule' => p.rule,
      'signalDeep' => p.signalDeep,
      _ => _role(p, name),
    };

/// Relative Leuchtdichte nach WCAG — hier als Maß für „wie hell strahlt das".
double luminance(Color c) => _luminance(c);

void main() {
  // ── Der gedämpfte Modus ─────────────────────────────────────────────────
  //
  // `tokens.dart` sagt über `darkMuted`: „Diese Fassung nimmt Leuchtdichte
  // und Blauanteil zurück." Das ist keine Geschmacksfrage, sondern der Grund,
  // aus dem das Schema existiert (D8, Sleep Gate) — und es stand bisher als
  // Behauptung im Kommentar, ohne dass es jemand nachgerechnet hätte.
  //
  // Nachgerechnet gilt es für acht der zwölf Rollen und für vier nicht.
  // Die Prüfung hält beides fest: die Zusage für die acht, den Rückstand
  // namentlich für die vier.
  group('Der gedämpfte Modus nimmt zurück, was er zurücknehmen soll', () {
    final plain = AxiomScheme.instrument.palette(Brightness.dark);
    final muted = AxiomScheme.muted.palette(Brightness.dark);

    test('keine Rolle strahlt heller als in der Vorgabe', () {
      // Nur die dunkle Fassung: Abends ist der Schirm dunkel, und dort heißt
      // „heller" tatsächlich „strahlt mehr". Im Hellen wäre dieselbe Zahl
      // eine Kontrastfrage und keine Leuchtfrage.
      //
      // **Befund.** `calm` (#8FA98C gegen #7FA88A) und `info` (#8B9AA0 gegen
      // #6E90A4) sind heute heller als in der Vorgabe — `info` um ein Fünftel.
      // Beide sind Zustandsfarben und stehen abends auf jedem Regime-Abzeichen.
      final brighter = [
        for (final role in _allRoles)
          if (luminance(_anyRole(muted, role)) >
              luminance(_anyRole(plain, role)))
            role,
      ];
      expect(brighter, everyElement(isIn(_mutedBrighter)),
          reason: 'Neue Rolle heller als in der Vorgabe: $brighter. '
              'Gedämpft heißt gedämpft — sonst ist es nur ein zweiter '
              'Farbton (D8).');
    });

    test('keine Rolle trägt mehr Blau als in der Vorgabe', () {
      // Blau ist hier kein Farbgeschmack: Der kurzwellige Anteil ist der,
      // der abends am stärksten gegen das Einschlafen arbeitet. Deshalb der
      // **absolute** Blaukanal und nicht sein Anteil am Farbton — eine
      // entsättigte Farbe kann dunkler wirken und trotzdem mehr Blau
      // abstrahlen.
      //
      // **Befund.** Genau das ist passiert: Das gedämpfte Signal #D79A55
      // trägt B=85 gegen B=61 der Vorgabe #E8A33D — knapp 40 % mehr Blau,
      // und das auf der größten farbigen Fläche des Schirms (dem
      // Hauptknopf). Dasselbe bei `signalDeep`, `calm` und `caution`.
      final moreBlue = [
        for (final role in _allRoles)
          if (_anyRole(muted, role).b > _anyRole(plain, role).b) role,
      ];
      expect(moreBlue, everyElement(isIn(_mutedMoreBlue)),
          reason: 'Neue Rolle mit mehr Blau als in der Vorgabe: $moreBlue.');
    });

    test('die Flächen bleiben dunkler als in der Vorgabe', () {
      // Die Zusage, die heute ohne Einschränkung gilt: Grund, Karte, erhobene
      // Karte und Haarlinie sind durchgehend zurückgenommen. Das ist der
      // größte Teil der abgestrahlten Fläche und damit der Teil, der zählt.
      for (final role in ['base', 'panel', 'panelRaised', 'rule', 'ink']) {
        expect(
          luminance(_anyRole(muted, role)),
          lessThan(luminance(_anyRole(plain, role))),
          reason: role,
        );
      }
    });
  });

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

        test('$label: der gewählte Chip bleibt lesbar', () {
          // Siehe [kChipFloor]. Zweiter Ort desselben Musters wie die
          // Stufenplakette, nur in der Mulde statt auf einer Fläche.
          final tinted = Color.alphaBlend(
              palette.signal.withValues(alpha: kChipTint), palette.well);
          expect(
            contrastRatio(palette.signal, tinted),
            greaterThanOrEqualTo(kChipFloor),
            reason: '$label: signal auf signal@$kChipTint über der Mulde '
                '(Ziel ist $kMinContrast:1, siehe kChipFloor)',
          );
        });

        test('$label: die Umrandung eines Eingabefelds ist auffindbar', () {
          // Siehe [kFieldEdgeFloor]. Ein leeres Feld hat keine Beschriftung,
          // die für es einspringt — es ist genau seine Umrandung.
          for (final surface in ['panel', 'base']) {
            expect(
              contrastRatio(palette.rule, _surface(palette, surface)),
              greaterThanOrEqualTo(kFieldEdgeFloor),
              reason: '$label: rule auf $surface (Ziel sind 3:1 nach '
                  'WCAG 1.4.11, siehe kFieldEdgeFloor)',
            );
          }
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
