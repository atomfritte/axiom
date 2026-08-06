/// Was ab dieser Runde für Schrift gilt — nachgelesen, nicht geglaubt.
///
/// **Warum es diese Datei gibt.** Drei typografische Entscheidungen waren
/// über zwei Jahre so weit verrutscht, dass sie das Gegenteil ihrer Absicht
/// bewirkten, und keine davon hätte ein Widget-Test gefunden: Sie sind alle
/// „sieht aus wie vorgesehen, wirkt anders als gemeint".
///
///  1. **Monospace.** Gedacht war „Mono signalisiert abgelesen" für die
///     Regel-ID. Gezählt wurden 117 `monoStyle`-Aufrufe gegen sieben
///     `RuleStamp` — jede Zahl, jede Uhrzeit, jede Beschriftung lief in
///     Schreibmaschine. Damit war die Regel-ID nicht mehr das auffällige
///     Element, sondern eines von hundert. G2 wurde leiser, nicht lauter.
///  2. **Gesperrte Versalien.** `AKTIVIERUNGSENERGIE` ist neunzehn
///     Großbuchstaben am Stück: Die Wortform fällt weg, man liest Buchstabe
///     für Buchstabe. Auf dem Schirm, der „was jetzt" beantworten soll, ist
///     das die teuerste Sekunde.
///  3. **`w300` in großen Graden.** Als Screenshot elegant, auf einem
///     Telefon dünn und blass — vor allem hell auf dunkel, wo Haarlinien
///     optisch weiter ausdünnen.
///
/// Der Quelltextteil dieser Datei ist bewusst eine **Ratsche**: Der
/// Gestaltungsteil (`lib/design/`) hat feste, kleine Obergrenzen, die
/// Schirme ihre heutigen Zahlen. Die dürfen sinken und nicht steigen. So
/// wird der Rückstand nicht zum Dauerrot, das man wegsieht — aber er wächst
/// auch nicht weiter.
library;

import 'dart:io';

import 'package:axiom_app/design/theme.dart';
import 'package:axiom_app/design/tokens.dart';
import 'package:axiom_app/design/widgets/instruments.dart';
import 'package:axiom_app/i18n/i18n.dart';
import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wie viele Fundstellen von `monoStyle`/`Fonts.mono` eine Datei haben darf.
///
/// Die vier Einträge aus `lib/` sind kein Rückstand, sondern die
/// verbleibenden legitimen Fälle:
///
///  * `theme.dart` — die Definition von `monoStyle` selbst.
///  * `instruments.dart` — die Regel-ID in `RuleStamp`. Der eigentliche Zweck.
///  * `prose.dart` — Code in der Hilfe und der Pfad eines fehlenden Bildes.
///  * `baseline_card.dart` — der Shell-Befehl zum Kopieren.
///  * `app.dart`/`main.dart` — Fehlerausgaben beim Absturz.
///
/// Alles darunter ist Altbestand aus den Schirmen. Wer einen Schirm anfasst,
/// setzt seine Zahl herunter; wer sie erhöhen müsste, hat einen Messwert in
/// Schreibmaschine gesetzt und soll stattdessen `readingStyle` nehmen.
const Map<String, int> _monoBudget = {
  // Gestaltung — fest.
  'lib/design/theme.dart': 2,
  'lib/design/widgets/instruments.dart': 1,
  'lib/design/widgets/prose.dart': 2,
  'lib/design/widgets/baseline_card.dart': 1,
  // Absturzausgaben.
  'lib/app.dart': 1,
  'lib/main.dart': 2,
  // Altbestand — Obergrenze, keine Zusage.
  'lib/screens/anchors_screen.dart': 3,
  'lib/screens/atomize_sheet.dart': 1,
  'lib/screens/body_sheet.dart': 3,
  'lib/screens/capture_sheet.dart': 1,
  'lib/screens/channels_screen.dart': 3,
  'lib/screens/check_screen.dart': 1,
  'lib/screens/expert_screen.dart': 6,
  'lib/screens/focus_screen.dart': 7,
  'lib/screens/help_screen.dart': 4,
  'lib/screens/inbox_screen.dart': 6,
  'lib/screens/intercept_screen.dart': 3,
  'lib/screens/now_screen.dart': 12,
  'lib/screens/onboarding_screen.dart': 3,
  'lib/screens/place_sheet.dart': 1,
  'lib/screens/review_screen.dart': 5,
  'lib/screens/rule_editor_screen.dart': 9,
  'lib/screens/sensation_screen.dart': 2,
  'lib/screens/signal_screen.dart': 6,
  'lib/screens/state_screen.dart': 1,
  'lib/screens/system_screen.dart': 12,
  'lib/screens/tasks_screen.dart': 6,
  'lib/screens/vault_screen.dart': 4,
};

final _monoPattern = RegExp(r'monoStyle\(|Fonts\.mono');

final _translatedLiteral = RegExp(r"""context\.t\(\s*'((?:[^'\\]|\\.)*)'""");

/// Die Wortmarke.
///
/// „AXIOM" in gesperrtem w300 ist keine Textrolle, sondern ein Bild — sie
/// steht einmal auf dem Startbildschirm und wird nicht gelesen, sondern
/// erkannt. Die Regeln dieser Datei gelten für Text, den jemand liest.
const _wordmark = 'lib/design/widgets/axiom_mark.dart';

List<File> _dartFiles(String directory) => Directory(directory)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

/// Der Quelltext ohne Kommentare.
///
/// Ohne das findet der Test die eigenen Begründungen: In `theme.dart` steht
/// im Kommentar, warum `.toUpperCase()` verschwunden ist — und genau das
/// hätte er als Verstoß gemeldet.
String _code(File file) => file
    .readAsLinesSync()
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

/// Ob eine Beschriftung durchgehend in Versalien gesetzt ist.
///
/// Nur ganze Beschriftungen zählen, nicht ein Wort in einem Satz: „betroffene
/// Regeln sind unten mit UNGEEICHT markiert" nennt eine Plakette beim Namen
/// und schreit nicht — der Satz drumherum ist normal gesetzt.
bool _isShoutingLabel(String literal) {
  final text = literal.replaceAll(RegExp(r'\{\d+\}'), '');
  final letters = text.replaceAll(RegExp(r'[^A-Za-zÄÖÜäöüß]'), '');
  return letters.length >= 8 && letters == letters.toUpperCase();
}

Widget _wrap(Widget child, {Brightness brightness = Brightness.dark}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAxiomTheme(brightness: brightness),
      home: AxiomLanguage(
        language: AppLanguage.de,
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  group('Monospace trägt nur noch, was sie tragen soll', () {
    test('keine Datei setzt mehr Schreibmaschine als erlaubt', () {
      final tooMany = <String>[];
      for (final file in _dartFiles('lib')) {
        final path = file.path;
        final count = _monoPattern.allMatches(file.readAsStringSync()).length;
        final budget = _monoBudget[path] ?? 0;
        if (count > budget) {
          tooMany.add('$path: $count (erlaubt $budget)');
        }
      }
      expect(tooMany, isEmpty,
          reason: 'Ein Messwert gehört in readingStyle (Hausschrift mit '
              'Tabellenziffern), nicht in monoStyle. Monospace bleibt der '
              'Regel-ID und wörtlich abzutippendem Text:\n'
              '${tooMany.join("\n")}');
    });

    test('die Ratsche zeigt keine Datei an, die es nicht mehr gibt', () {
      // Sonst altert die Liste still weiter und deckelt nichts mehr.
      final gone = [
        for (final path in _monoBudget.keys)
          if (!File(path).existsSync()) path,
      ];
      expect(gone, isEmpty);
    });

    test('in den Instrumenten steht Monospace nur in der Regelplakette', () {
      final source =
          File('lib/design/widgets/instruments.dart').readAsStringSync();
      final start = source.indexOf('final class RuleStamp');
      expect(start, greaterThan(-1));
      final end = source.indexOf('final class ', start + 1);
      expect(end, greaterThan(start));

      for (final match in _monoPattern.allMatches(source)) {
        expect(match.start, inInclusiveRange(start, end),
            reason: 'Monospace außerhalb von RuleStamp: '
                '„${source.substring(match.start, match.end)}" bei '
                'Zeichen ${match.start}. Die Regel-ID ist das einzige '
                'technisch gesetzte Element eines Schirms — genau deshalb '
                'findet man sie sofort (G2).');
      }
    });
  });

  group('Keine gesperrten Versalien mehr', () {
    test('kein Text im Gestaltungsteil schreit', () {
      final shouting = <String>[];
      for (final file in _dartFiles('lib/design')) {
        if (file.path == _wordmark) continue;
        for (final match in _translatedLiteral.allMatches(_code(file))) {
          final literal = match.group(1)!;
          if (_isShoutingLabel(literal)) {
            shouting.add('${file.path}: „$literal"');
          }
        }
      }
      expect(shouting, isEmpty,
          reason: 'Versalien mit Sperrung sind langsamer zu lesen — die '
              'Wortform fällt weg. Normale Schreibweise, 13,5 px, w600:\n'
              '${shouting.join("\n")}');
    });

    test('kein Baustein macht aus einem Text nachträglich Versalien', () {
      // Der eigentliche Schuldige war nicht der Quelltext der Schirme,
      // sondern `SectionLabel`, `InstrumentBar` und `_CriterionRow`: Sie
      // riefen `.toUpperCase()` auf einer sauber geschriebenen Beschriftung.
      // Ein Text, der im Quelltext richtig aussieht und auf dem Schirm
      // schreit, ist nirgends zu finden.
      final offenders = <String>[];
      for (final file in _dartFiles('lib/design')) {
        if (_code(file).contains('.toUpperCase()')) offenders.add(file.path);
      }
      expect(offenders, isEmpty);
    });
  });

  group('Große Grade sind nicht mehr dünn', () {
    test('w300 kommt im Gestaltungsteil nicht mehr vor', () {
      final offenders = <String>[];
      for (final file in _dartFiles('lib/design')) {
        if (file.path == _wordmark) continue;
        for (final line in _code(file).split('\n')) {
          if (line.contains('FontWeight.w300')) {
            offenders.add('${file.path}: ${line.trim()}');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'w300 in großen Graden wirkt auf einem Telefon blass. '
              'Display und Headline stehen in w600 mit optischer '
              'Laufweitenkorrektur:\n${offenders.join("\n")}');
    });

    testWidgets('Display und Headline stehen in w600 und laufen eng',
        (tester) async {
      late TextTheme text;
      await tester.pumpWidget(_wrap(Builder(builder: (context) {
        text = Theme.of(context).textTheme;
        return const SizedBox();
      })));

      for (final style in [
        text.displayLarge!,
        text.displayMedium!,
        text.headlineLarge!,
        text.headlineMedium!,
      ]) {
        expect(style.fontWeight, FontWeight.w600, reason: '${style.fontSize}');
        // −0,028 × Größe, mit etwas Spiel für gerundete Werte.
        expect(style.letterSpacing, isNotNull);
        expect(style.letterSpacing!, lessThan(0),
            reason: 'große Grade brauchen negative Laufweite');
        expect((style.letterSpacing! + 0.028 * style.fontSize!).abs(),
            lessThan(0.05),
            reason: 'optische Korrektur weicht ab (${style.fontSize} px)');
      }
    });

    testWidgets('die Abschnittsmarke ist Hausschrift, nicht Schreibmaschine',
        (tester) async {
      late TextStyle label;
      await tester.pumpWidget(_wrap(Builder(builder: (context) {
        label = sectionStyle(context);
        return const SizedBox();
      })));
      expect(label.fontFamily, Fonts.sans);
      expect(label.fontWeight, FontWeight.w600);
      expect(label.fontSize, 13.5);
      // Leicht gesperrt ist gewollt, gesperrte Versalien sind es nicht.
      expect(label.letterSpacing, lessThanOrEqualTo(0.5));
    });

    testWidgets('Messwerte laufen mit Tabellenziffern', (tester) async {
      late TextStyle reading;
      await tester.pumpWidget(_wrap(Builder(builder: (context) {
        reading = readingStyle(context);
        return const SizedBox();
      })));
      expect(reading.fontFamily, Fonts.sans);
      expect(reading.fontFeatures, contains(const FontFeature.tabularFigures()),
          reason: 'Der einzige sachliche Grund für Monospace war, dass 61 '
              'unter 88 steht. Genau das leistet tnum.');
    });
  });

  group('Eine Farbe für alle Messwerte', () {
    testWidgets('ein Messwert wird in signal gezeichnet — egal was übergeben '
        'wird', (tester) async {
      final palette = AxiomScheme.instrument.palette(Brightness.dark);
      await tester.pumpWidget(_wrap(const InstrumentBar(
        label: 'Kompensationslast',
        value: 61,
        // Vorher wählte jede Aufrufstelle ihre eigene Rolle. Drei Messwerte
        // untereinander in drei Farben lesen sich als drei Urteile (R7).
        color: Color(0xFF00FF00),
      )));

      final value = tester.widget<Text>(find.text('61'));
      expect(value.style?.color, palette.signal);
      expect(value.style?.fontFamily, Fonts.sans);
    });

    testWidgets('die Beschriftung schreit nicht mehr', (tester) async {
      await tester.pumpWidget(_wrap(const InstrumentBar(
        label: 'Kompensationslast',
        value: 61,
      )));
      expect(find.text('Kompensationslast'), findsOneWidget);
      expect(find.text('KOMPENSATIONSLAST'), findsNothing);
    });
  });

  group('Die Herleitung geht auf', () {
    // Die Terme standen da, die Summe nicht. Wer nachrechnete, kam auf eine
    // andere Zahl als die angezeigte — bei Konfidenz 0,50 summierten sich
    // sichtbare 67,5 zu einer angezeigten 60. Eine Formel, die etwas anderes
    // rechnet, als sie zeigt, erklärt nichts (G2).
    const terms = [
      Term('Basis', 60),
      Term('Schlafschuld', -12.5),
      Term('Tagesrhythmus', 7.5),
      Term('Dünne Datenlage', -6.5),
    ];

    testWidgets('Summe, Rest und angezeigter Wert stehen unter den Termen',
        (tester) async {
      await tester.pumpWidget(_wrap(const InstrumentBar(
        label: 'Kapazität',
        value: 49,
        breakdown: terms,
        confidence: 0.5,
      )));

      await tester.tap(find.text('Kapazität'));
      await tester.pumpAndSettle();

      expect(find.text('Summe der Terme'), findsOneWidget);
      expect(find.text('Rundung und Grenze 0 bis 100'), findsOneWidget);
      expect(find.text('Angezeigt'), findsOneWidget);

      // 60 − 12,5 + 7,5 − 6,5 = 48,5 — und angezeigt werden 49.
      expect(find.text('48,5'), findsOneWidget);
      expect(find.text('+0,5'), findsOneWidget);
      // Die angezeigte Zahl steht zweimal: oben am Balken und unten in der
      // Tafel als Ergebnis derselben Rechnung.
      expect(find.text('49'), findsNWidgets(2));
    });

    testWidgets('die Konfidenz steht dabei, wenn sie unter eins liegt',
        (tester) async {
      await tester.pumpWidget(_wrap(const InstrumentBar(
        label: 'Kapazität',
        value: 49,
        breakdown: terms,
        confidence: 0.5,
      )));
      await tester.tap(find.text('Kapazität'));
      await tester.pumpAndSettle();
      expect(find.text('Konfidenz 0,50'), findsOneWidget);
    });

    testWidgets('die Beiträge tragen keine Note', (tester) async {
      // „Schlafschuld −12,5" in Kupfer liest sich als Rüge. Das Vorzeichen
      // steht ohnehin da; es braucht keine Farbe, die es bewertet (R7, D10).
      final palette = AxiomScheme.instrument.palette(Brightness.dark);
      await tester.pumpWidget(_wrap(const InstrumentBar(
        label: 'Kapazität',
        value: 49,
        breakdown: terms,
        confidence: 0.5,
      )));
      await tester.tap(find.text('Kapazität'));
      await tester.pumpAndSettle();

      for (final label in ['+60,0', '−12,5', '+7,5']) {
        final style = tester.widget<Text>(find.text(label)).style;
        expect(style?.color, isNot(palette.calm), reason: label);
        expect(style?.color, isNot(palette.caution), reason: label);
      }
    });
  });
}
