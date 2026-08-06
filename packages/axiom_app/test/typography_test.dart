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
///
/// **Die Zahlen wandern nur nach unten, und sie wandern im selben Zug wie
/// der Quelltext.** Sie sind der gemessene Bestand, kein Kontingent: Wer eine
/// Fundstelle entfernt, trägt die kleinere Zahl hier ein — sonst sammelt die
/// Liste Vorlauf an und deckelt irgendwann nichts mehr. Genau das war der
/// Zustand, in dem sie gefunden wurde: `rule_editor_screen` stand bei 9 und
/// `expert_screen` bei 6, tatsächlich waren es 1 und 2 — elf Stellen Luft,
/// auf denen still Schreibmaschine hätte zurückkommen können. Steht eine
/// Datei bei 0, kommt sie ganz heraus.
library;

import 'dart:io';

import 'package:axiom_app/design/theme.dart';
import 'package:axiom_app/design/tokens.dart';
import 'package:axiom_app/design/widgets/instruments.dart';
import 'package:axiom_app/i18n/i18n.dart';
import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wie viele Fundstellen von `monoStyle`/`Fonts.mono` eine Datei hat.
///
/// **Die Zahlen dürfen nur nach unten wandern.** Sie sind kein Kontingent,
/// das man ausschöpfen darf, sondern der abgetragene Rückstand von gestern.
/// Wer eine Fundstelle entfernt, trägt die kleinere Zahl ein — steht eine
/// Datei bei 0, kommt sie ganz aus der Liste. Wer eine hinzufügen müsste,
/// hat vermutlich einen Messwert gesetzt und nimmt `readingStyle`.
///
/// **Warum die Zahlen exakt stimmen müssen und nicht nur nicht überschritten
/// werden dürfen.** Diese Liste stand nach dem Umbau bei Summe 100, während
/// im Quelltext 23 Fundstellen übrig waren — 77 Stellen Vorlauf. Eine Ratsche
/// mit Vorlauf ratscht nicht: Man hätte drei Dutzend Messwerte zurück in
/// Schreibmaschine setzen können, ohne dass ein Test etwas gesagt hätte. Der
/// Bestand wird deshalb **beziffert**, nicht gedeckelt.
///
/// Was hier steht, ist inzwischen kein Rückstand mehr, sondern die Liste der
/// verbleibenden legitimen Fälle — Schreibmaschine trägt nur noch, was
/// wörtlich abgetippt oder Zeichen für Zeichen verglichen wird:
///
///  * `theme.dart` — die Definition von `monoStyle` selbst.
///  * `instruments.dart` — die Regel-ID in `RuleStamp`. Der eigentliche Zweck.
///  * `prose.dart` — Code in der Hilfe und der Pfad eines fehlenden Bildes.
///  * `baseline_card.dart` — der Shell-Befehl zum Kopieren.
///  * `app.dart`, `main.dart`, `now_screen.dart` — Fehlerausgaben beim
///    Absturz. Der Wortlaut einer Ausnahme ist nichts, was man liest,
///    sondern etwas, das man sucht.
///  * `channels_screen`, `system_screen` — Wortlaut einer Ausnahme und die
///    Meldungen des Regelvalidators (`R-042: …`).
///  * `expert_screen` — Kopplungscode und Zertifikats-Fingerabdruck. Beide
///    werden gegen ein zweites Gerät gehalten, Zeichen gegen Zeichen.
///  * `rule_editor_screen`, `vault_screen` — YAML-Ausschnitt und Dateipfad.
const Map<String, int> _monoBudget = {
  // Gestaltung — fest.
  'lib/design/theme.dart': 2,
  'lib/design/widgets/instruments.dart': 1,
  'lib/design/widgets/prose.dart': 2,
  'lib/design/widgets/baseline_card.dart': 1,
  // Absturz- und Fehlerausgaben.
  'lib/app.dart': 1,
  'lib/main.dart': 2,
  'lib/screens/now_screen.dart': 1,
  // Wörtlich abzutippender oder Zeichen für Zeichen zu vergleichender Text.
  //
  // `inbox_screen.dart` stand hier bei 6 — die Zeitstempel des Eingangs
  // („3.8. 10:30"), dreimal der auffälligste Schreibmaschinenton auf dem
  // Schirm. Sie laufen jetzt in `readingStyle`, und die Datei ist deshalb
  // ganz aus der Liste verschwunden statt auf 0 stehenzubleiben.
  'lib/screens/channels_screen.dart': 1,
  'lib/screens/expert_screen.dart': 2,
  'lib/screens/rule_editor_screen.dart': 1,
  'lib/screens/system_screen.dart': 2,
  'lib/screens/vault_screen.dart': 1,
};

/// Wie oft eine Datei aus einer Beschriftung nachträglich Versalien macht.
///
/// `.toUpperCase()` ist der Weg, auf dem gesperrte Versalien zurückkommen,
/// ohne im Quelltext sichtbar zu sein: Der String liest sich richtig, und
/// auf dem Schirm schreit er. Im Gestaltungsteil ist der Aufruf deshalb
/// vollständig verboten (eigener Test weiter unten); überall sonst steht
/// hier, wofür er noch dasteht — und auch diese Zahlen wandern nur nach
/// unten:
///
///  * `state_screen`, `now_screen` — die Stufenplakette `L0`–`L3`. Zwei
///    Zeichen haben keine Wortform, die verlorengehen könnte.
///  * `rule_editor_screen` — erster Buchstabe eines Namens.
///  * `expert_server`, `expert_certificate` — kein Oberflächentext:
///    JSON-Werte und ein Zertifikats-Fingerabdruck.
///
/// `system_screen` stand hier bei 4 und ist ganz herausgefallen. Darunter
/// war der eine Befund dieser Liste: die Plakette **`UNGEEICHT`** — neun
/// Großbuchstaben, während die Vorgabe Versalien nur bis sieben Zeichen
/// zulässt, an jeder ungeeichten Regel im Regelinspektor. Sie ist normal
/// geschrieben, ebenso das Sprachkürzel und der Schemaname.
const Map<String, int> _upperBudget = {
  'lib/screens/now_screen.dart': 1,
  'lib/screens/rule_editor_screen.dart': 1,
  'lib/screens/state_screen.dart': 1,
  'lib/server/expert_certificate.dart': 1,
  'lib/server/expert_server.dart': 2,
};

/// Wie viele durchgehend in Versalien gesetzte Beschriftungen eine Datei hat.
///
/// **Der Rückstand dieser Runde — abgetragen.** Der Gestaltungsteil war schon
/// sauber (`SectionLabel`, `InstrumentBar` und die Typskala setzen normale
/// Schreibweise durch), geprüft wurde aber **nur** `lib/design`. In den
/// Schirmen standen darunter 26 Beschriftungen, die im Quelltext selbst schon
/// schrieen: `ODER EINE DIESER FORMEN`, `ZU GROSS FÜR HEUTE`,
/// `ZULETZT STEHENGEBLIEBEN`, `WARTEZEIT LÄUFT`. Gegen die half kein
/// Baustein — sie waren so getippt, und sie sind einzeln umgeschrieben
/// worden. Übrig ist genau einer, und der bleibt.
///
/// Damit ist die Liste kein Rückstand mehr, sondern eine Ausnahme. Sie darf
/// **nicht wieder wachsen**: Wer hier einen Eintrag bräuchte, hat eine
/// Beschriftung in Versalien getippt, und die gehört in normale Schreibweise.
///
/// Nicht gezählt wird ein Wort in einem Satz („betroffene Regeln sind unten
/// mit UNGEEICHT markiert") und alles unter acht Buchstaben; Plaketten dürfen
/// Versalien behalten (siehe [_isShoutingLabel]).
const Map<String, int> _shoutBudget = {
  // Absturzschirm — „START FEHLGESCHLAGEN". Der eine Ort, an dem die
  // Oberfläche laut sein darf, weil sonst nichts mehr da ist.
  'lib/app.dart': 1,
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

/// Zählt eine Fundstelle je Datei unter `lib/` und vergleicht mit dem Bestand.
///
/// Zwei getrennte Meldungen, weil die zwei Fälle verschiedene Bedeutung
/// haben: **mehr** als verzeichnet ist ein Rückschritt, **weniger** ist ein
/// Fortschritt, der nur noch eingetragen werden muss. Beides bricht den
/// Test — sonst sammelt die Liste Vorlauf an und deckelt irgendwann nichts
/// mehr (siehe [_monoBudget]).
void expectTally(
  Map<String, int> budget,
  int Function(File file) count, {
  required String regression,
}) {
  final grown = <String>[];
  final shrunk = <String>[];
  for (final file in _dartFiles('lib')) {
    final actual = count(file);
    final noted = budget[file.path] ?? 0;
    if (actual > noted) grown.add('${file.path}: $actual statt $noted');
    if (actual < noted) shrunk.add('${file.path}: $actual statt $noted');
  }
  expect(grown, isEmpty, reason: '$regression\n${grown.join("\n")}');
  expect(shrunk, isEmpty,
      reason: 'Weniger als verzeichnet — schön, aber die Zahl muss mit. Eine '
          'Ratsche mit Vorlauf ratscht nicht:\n${shrunk.join("\n")}');

  final gone = [
    for (final path in budget.keys)
      if (!File(path).existsSync()) path,
  ];
  expect(gone, isEmpty,
      reason: 'Die Liste nennt Dateien, die es nicht mehr gibt:\n'
          '${gone.join("\n")}');
}

void main() {
  group('Monospace trägt nur noch, was sie tragen soll', () {
    test('der Bestand an Schreibmaschine stimmt Datei für Datei', () {
      expectTally(
        _monoBudget,
        (file) => _monoPattern.allMatches(file.readAsStringSync()).length,
        regression: 'Ein Messwert gehört in readingStyle (Hausschrift mit '
            'Tabellenziffern), nicht in monoStyle. Monospace bleibt der '
            'Regel-ID und wörtlich abzutippendem Text:',
      );
    });

    testWidgets('keine Rolle der Typskala ist Schreibmaschine',
        (tester) async {
      // Der eine Weg, auf dem die Schreibmaschine zurückkommen könnte, ohne
      // dass die Zählung oben etwas merkt: ein einziges `fontFamily` in
      // `buildAxiomTheme`. Dann liefe die halbe Oberfläche in Mono, und im
      // Quelltext stünde nirgends `monoStyle`.
      late ThemeData theme;
      await tester.pumpWidget(_wrap(Builder(builder: (context) {
        theme = Theme.of(context);
        return const SizedBox();
      })));

      final roles = <String, TextStyle?>{
        'displayLarge': theme.textTheme.displayLarge,
        'displayMedium': theme.textTheme.displayMedium,
        'headlineLarge': theme.textTheme.headlineLarge,
        'headlineMedium': theme.textTheme.headlineMedium,
        'titleLarge': theme.textTheme.titleLarge,
        'titleMedium': theme.textTheme.titleMedium,
        'bodyLarge': theme.textTheme.bodyLarge,
        'bodyMedium': theme.textTheme.bodyMedium,
        'bodySmall': theme.textTheme.bodySmall,
        'labelLarge': theme.textTheme.labelLarge,
        'labelMedium': theme.textTheme.labelMedium,
        'labelSmall': theme.textTheme.labelSmall,
      };
      for (final entry in roles.entries) {
        expect(entry.value?.fontFamily, isNot(Fonts.mono),
            reason: entry.key);
      }
      expect(theme.textTheme.bodyLarge?.fontFamily, Fonts.sans);
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

    test('der Bestand an Versalien in den Schirmen stimmt Datei für Datei',
        () {
      // Der Test darüber sieht nur `lib/design`. Genau das war die Lücke:
      // Die Bausteine schreien nicht mehr, die Schirme schon — 26 Stück,
      // und keiner davon hätte irgendeinen Test rot gemacht. Ein Wächter,
      // der nur die Fälle kennt, die es beim Schreiben schon gab, ist in
      // einem halben Jahr blind.
      expectTally(
        _shoutBudget,
        (file) => file.path == _wordmark
            ? 0
            : _translatedLiteral
                .allMatches(_code(file))
                .where((m) => _isShoutingLabel(m.group(1)!))
                .length,
        regression: 'Neue Beschriftung durchgehend in Versalien. Sie ist '
            'langsamer zu lesen, weil die Wortform wegfällt, und trägt den '
            'Ton eines Beipackzettels. Normale Schreibweise, 13,5 px, w600 '
            '— Plaketten unter acht Buchstaben dürfen bleiben:',
      );
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

    test('der Bestand an .toUpperCase() stimmt Datei für Datei', () {
      // Außerhalb des Gestaltungsteils ist der Aufruf nicht verboten,
      // sondern beziffert: `L0`, `DE`, ein Anfangsbuchstabe und zwei
      // JSON-Werte sind legitim. Siehe [_upperBudget] — dort steht auch,
      // welcher der sechs Einträge ein Befund ist.
      expectTally(
        _upperBudget,
        (file) => '.toUpperCase()'.allMatches(_code(file)).length,
        regression: 'Neuer .toUpperCase()-Aufruf. Ein Text, der im '
            'Quelltext richtig aussieht und auf dem Schirm schreit, ist '
            'nirgends zu finden:',
      );
    });
  });

  group('Große Grade sind nicht mehr dünn', () {
    test('kein dünner Schnitt im ganzen App-Code', () {
      // Geprüft wurde bisher nur `lib/design`. Ein Schirm, der eine
      // 34-px-Überschrift auf w300 setzt, sieht als Screenshot elegant aus
      // und ist auf einem Telefon blass — und wäre durchgerutscht. w200 und
      // w100 gleich mit: Sie sind dieselbe Entscheidung, nur weiter getrieben.
      final offenders = <String>[];
      for (final file in _dartFiles('lib')) {
        if (file.path == _wordmark) continue;
        for (final line in _code(file).split('\n')) {
          for (final weight in ['w100', 'w200', 'w300']) {
            if (line.contains('FontWeight.$weight')) {
              offenders.add('${file.path}: ${line.trim()}');
            }
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'Dünne Schnitte wirken auf einem Telefon blass — vor allem '
              'hell auf dunkel, wo Haarlinien optisch weiter ausdünnen. '
              'Display und Headline stehen in w600 mit optischer '
              'Laufweitenkorrektur, Fließtext in w400:\n'
              '${offenders.join("\n")}');
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

    testWidgets('jede gezeichnete Zahl läuft in Hausschrift mit '
        'Tabellenziffern', (tester) async {
      // Die Zählung im Quelltext oben sieht `monoStyle(`. Sie sieht **nicht**,
      // ob eine Zahl versehentlich in einer Rolle landet, die keine
      // Tabellenziffern führt — dann steht 61 nicht mehr sauber unter 88,
      // und genau das war der einzige sachliche Grund für Monospace.
      //
      // Dieser Test geht deshalb über das gezeichnete Ergebnis: Er sammelt
      // jeden `Text`, dessen Inhalt eine reine Zahl ist, rechnet den
      // wirksamen Stil aus (Vorgabe des Baums plus eigener Stil) und prüft
      // ihn. Wie die Zahl dorthin gekommen ist, spielt keine Rolle.
      await tester.pumpWidget(_wrap(const InstrumentBar(
        label: 'Kapazität',
        value: 49,
        breakdown: [
          Term('Basis', 60),
          Term('Schlafschuld', -12.5),
          Term('Tagesrhythmus', 7.5),
          Term('Dünne Datenlage', -6.5),
        ],
        confidence: 0.5,
      )));
      await tester.tap(find.text('Kapazität'));
      await tester.pumpAndSettle();

      final number = RegExp(r'^[+−-]?\d+([.,]\d+)?$');
      final wrong = <String>[];
      var checked = 0;
      for (final element in tester.elementList(find.byType(Text))) {
        final text = element.widget as Text;
        final content = text.data;
        if (content == null || !number.hasMatch(content)) continue;
        checked++;
        final style =
            DefaultTextStyle.of(element).style.merge(text.style);
        if (style.fontFamily == Fonts.mono) {
          wrong.add('„$content" steht in Schreibmaschine');
        } else if (!(style.fontFeatures ?? const [])
            .contains(const FontFeature.tabularFigures())) {
          wrong.add('„$content" läuft ohne Tabellenziffern');
        }
      }
      expect(checked, greaterThan(5),
          reason: 'Die Herleitung zeigt keine Zahlen mehr — dann prüft '
              'dieser Test nichts');
      expect(wrong, isEmpty,
          reason: 'Ein Messwert gehört in readingStyle:\n'
              '${wrong.join("\n")}');
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
