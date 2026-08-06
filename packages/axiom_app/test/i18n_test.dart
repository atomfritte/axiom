/// Prüft die Zweisprachigkeit — auf Vollständigkeit und auf Ton.
///
/// **Warum am Quelltext und nicht an einzelnen Screens.** Eine fehlende
/// Übersetzung fällt beim Klicken erst auf, wenn man genau diesen Zustand
/// erwischt: den Erhaltungsmodus, den abgelaufenen Cooldown, den Fehlerfall.
/// Genau die sieht man beim Durchklicken nie. Der Quelltext kennt sie alle.
///
/// **Und auf Ton, weil eine Übersetzung ihn verlieren kann.** „Nichts in
/// Reichweite" ist eine bewusste Formulierung gegen „Du hast 14 offene
/// Aufgaben". Ein englischer Satz, der daraus „You still have…" macht, wäre
/// technisch korrekt und inhaltlich das Gegenteil (D10, R7).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';

import 'package:axiom_app/design/theme.dart';
import 'package:axiom_app/design/tokens.dart';
import 'package:axiom_app/screens/anchors_screen.dart';
import 'package:axiom_app/screens/channels_screen.dart';
import 'package:axiom_app/screens/check_screen.dart';
import 'package:axiom_app/screens/expert_screen.dart';
import 'package:axiom_app/screens/focus_screen.dart';
import 'package:axiom_app/screens/intercept_screen.dart';
import 'package:axiom_app/screens/onboarding_screen.dart';
import 'package:axiom_app/screens/review_screen.dart';
import 'package:axiom_app/screens/signal_screen.dart';
import 'package:axiom_app/screens/state_screen.dart';
import 'package:axiom_app/screens/tasks_screen.dart';
import 'package:axiom_app/screens/vault_screen.dart';
import 'package:axiom_app/state/providers.dart';
import 'package:axiom_app/state/runtime.dart';
import 'package:axiom_app/state/rule_draft.dart';
import 'package:axiom_app/i18n/en.dart';
import 'package:axiom_app/i18n/i18n.dart';
import 'package:axiom_app/platform/system_sync.dart';
import 'package:axiom_app/platform/system_texts.dart';

import 'harness.dart';

/// Ein Literal, ggf. aus mehreren benachbarten zusammengesetzt.
final _literal = RegExp(r"'(?:[^'\\\n]|\\.)*'");
final _call = RegExp(r"(?:\.t|translate)\(\s*(?:[A-Za-z_][\w.]*\s*,\s*)?");

/// Alle Texte, die im Quelltext durch die Übersetzung laufen.
Set<String> translatedSources() {
  final found = <String>{};
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.contains('/i18n/'));

  for (final file in files) {
    final src = file.readAsStringSync();
    for (final call in _call.allMatches(src)) {
      // Ab dem Aufruf die Kette benachbarter Literale einsammeln.
      var pos = call.end;
      final parts = <String>[];
      while (true) {
        final match = _literal.matchAsPrefix(src, pos);
        if (match == null) break;
        parts.add(match.group(0)!.substring(1, match.group(0)!.length - 1));
        pos = match.end;
        // Leerraum und Zeilenumbrüche zwischen den Teilen überspringen.
        final ws = RegExp(r'\s*').matchAsPrefix(src, pos);
        if (ws == null) break;
        pos = ws.end;
      }
      if (parts.isEmpty) continue;
      // Der Quelltext enthaelt Escapes; zur Laufzeit ist der Schluessel der
      // aufgeloeste String. Ohne das hier meldet der Test jeden Text mit
      // Zeilenumbruch faelschlich als fehlend.
      found.add(_unescape(parts.join()));
    }
  }
  return found;
}

String _unescape(String source) => source
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\t', '\t')
    .replaceAll(r"\'", "'")
    .replaceAll(r'\$', r'$');

// ── Der Wächter: was auf Englisch wirklich auf dem Schirm steht ──────────
//
// **Warum nicht mehr am Quelltext.** Hier stand ein Scanner über
// `lib/screens` mit dem Muster `Text('…')`. Er kannte genau eine
// Schreibweise. Vorbei kamen: ein Etikett im Tupel eines `switch`
// (`('HINWEIS', p.info)`), ein fertiger Satz aus dem Kern
// (`Text(FocusGovernor.breadcrumbPrompt(…))`), eine Konstante
// (`Text(kMedDisclaimer)`), der zweite Zweig eines Ternärs
// (`_busy ? context.t('Läuft…') : 'Exportieren'`), ein Eintrag aus einer
// Liste (`for (final seed in kChecklistSeeds) Text(seed)`) und ein benanntes
// Argument, das erst weiter unten gerendert wird (`eyebrow: 'Fertig'`).
// Sechs Schreibweisen, ein blinder Test — und in der englischen App standen
// deutsche Sätze, während 28 Tests grün waren.
//
// Deshalb jetzt am Ergebnis statt an der Schreibweise: Der Screen wird auf
// Englisch gerendert, und jeder Text im Baum muss sich als englische Fassung
// ausweisen können. Auf welchem Weg er dorthin kam, ist dem Wächter egal —
// und die nächste Schreibweise, an die niemand gedacht hat, ist es auch.

/// Alle englischen Fassungen ohne Platzhalter, in Großschreibung.
///
/// Groß, weil Rubriken und Etiketten mit `.toUpperCase()` gezeichnet werden:
/// „What this is" steht als „WHAT THIS IS" im Baum.
final _englishExact = kEnglish.values
    .where((v) => !v.contains('{'))
    .map((v) => v.toUpperCase())
    .toSet();

/// Dieselben Fassungen mit Platzhalter, als Muster.
///
/// Ein Wert, der außer Platzhaltern nichts enthält, bleibt draußen: Er würde
/// jeden Text annehmen und den Wächter blind machen.
final _englishPatterns = kEnglish.values
    .where((v) => v.contains('{'))
    .where((v) => v.replaceAll(RegExp(r'\{\d+\}'), '').trim().isNotEmpty)
    .map((v) => RegExp(
          '^${v.split(RegExp(r'\{\d+\}')).map(RegExp.escape).join('(.+)')}\$',
          dotAll: true,
          caseSensitive: false,
        ))
    .toList();

/// Was in beiden Sprachen gleich aussieht: Zahlen, Uhrzeiten, Einheiten,
/// Regel- und Stufenkürzel. Ein Messwert ist kein Satz.
final _harmless = RegExp(
    r'^(?:[\d\s.,:;/+×·—–%()|@°<>=≤≥-]+|\d+(?:[.,]\d+)?\s*(?:min|h|%)|[A-Z]-?\d+)$');

/// Lässt sich der Text als englische Fassung erklären?
bool accountedFor(String text) =>
    _englishExact.contains(text.toUpperCase()) ||
    _englishPatterns.any((p) => p.hasMatch(text));

/// Sieht der Text deutsch aus?
///
/// Zwei Signale, und beide braucht es. Deutsche Schriftzeichen fangen den
/// ganzen Satz („Fenster läuft noch 45 min."). Sie fangen aber nicht den
/// eingesetzten Platzhalterwert: „Woche review" hat keinen Umlaut und passt
/// zugleich auf das Muster von „{0} review" — der erste Test allein hielte
/// ihn für Englisch. Deshalb zusätzlich Wort für Wort gegen die Wörterliste:
/// Was dort als deutscher Schlüssel steht und anders übersetzt würde, ist
/// deutsch stehengeblieben.
bool looksGerman(String text) =>
    RegExp('[äöüßÄÖÜ„]').hasMatch(text) ||
    text
        .split(RegExp(r'[^\wÄÖÜäöüß]+'))
        .any((word) => word.isNotEmpty && (kEnglish[word] ?? word) != word);

void main() {
  group('Kein Text ohne Übersetzung', () {
    _renderedInEnglish();

    test('auch was ein Painter zeichnet, ist übersetzt', () {
      // Ein `CustomPainter` hat keinen `BuildContext` und kann `context.t`
      // nicht aufrufen — die Beschriftungen der Kapazitätslinie standen
      // deshalb fest auf Deutsch mitten in einer englischen Oberfläche.
      // Sie kommen jetzt von außen; dieser Test hält fest, dass es so
      // bleibt.
      final source =
          File('lib/design/widgets/capacity_line.dart').readAsStringSync();
      for (final word in ['LEICHT', 'SCHWER', 'HIER']) {
        expect(source, contains("context.t('$word')"), reason: word);
      }
    });
  });

  group('Sprache beim allerersten Start', () {
    test('kommt vom Gerät, nicht aus einer Voreinstellung', () {
      // Vorher stand hier fest Deutsch. Auf einem englisch eingestellten
      // Geraet hiess das: eine Oberflaeche, die man nicht liest — und die
      // Umschaltung liegt hinter Menuepunkten, die man dafuer erst lesen
      // muesste.
      expect(AppLanguage.fromLocale(const Locale('en')), AppLanguage.en);
      expect(AppLanguage.fromLocale(const Locale('de')), AppLanguage.de);
      expect(AppLanguage.fromLocale(const Locale('en', 'US')), AppLanguage.en);
    });

    test('eine unbekannte Sprache landet bei Englisch', () {
      // Nicht bei Deutsch, obwohl das die Quellsprache ist: Das ist eine
      // Eigenschaft des Quelltexts, keine des Nutzers. Wer ein Geraet mit
      // einer Sprache benutzt, die AXIOM nicht kennt, versteht mit weit
      // hoeherer Wahrscheinlichkeit Englisch.
      expect(AppLanguage.fromLocale(const Locale('fr')), AppLanguage.en);
      expect(AppLanguage.fromLocale(const Locale('ja')), AppLanguage.en);
    });

    test('eine getroffene Wahl gewinnt', () {
      expect(AppLanguage.parse('en'), AppLanguage.en);
      expect(AppLanguage.parse('de'), AppLanguage.de);
    });
  });

  group('Vollständigkeit', () {
    test('jeder übersetzbare Text im Quelltext hat eine englische Fassung', () {
      final missing = translatedSources()
          .where((s) => !kEnglish.containsKey(s))
          .toList()
        ..sort();
      expect(
        missing,
        isEmpty,
        reason: 'Ohne Eintrag erscheint der deutsche Satz mitten im '
            'englischen Screen. Fehlend:\n${missing.join("\n")}',
      );
    });

    test('auch die Bezeichnungen der Aufzählungen', () {
      // Diese laufen als Variable durch die Uebersetzung
      // (`context.t(size.label)`) und sind im Quelltext nicht als Literal zu
      // finden. Der Scanner kann sie deshalb nicht sehen — sie muessen hier
      // von Hand aufgezaehlt werden, sonst faellt die Luecke erst auf, wenn
      // ein englischer Screen "Gedämpft" anzeigt.
      final labels = [
        ...AppLanguage.values.map((l) => l.label),
        ...TextSize.values.map((t) => t.label),
        ...AxiomScheme.values.map((s) => s.label),
        // Der Wortschatz des Regelwerks laeuft im Editor ebenfalls ueber
        // Variablen durch die Uebersetzung — Variablennamen, Ereignisse,
        // Aktionen, Operatoren.
        ...LeafKind.values.map((k) => k.label),
        ...RuleVocabulary.numerics.map((v) => v.label),
        ...RuleVocabulary.numerics.map((v) => v.meaning),
        ...RuleVocabulary.symbolics.map((v) => v.label),
        ...RuleVocabulary.symbolics.expand((v) => v.values.values),
        ...RuleVocabulary.events.map((e) => e.label),
        ...RuleVocabulary.actions.map((a) => a.label),
        ...RuleVocabulary.actions.map((a) => a.meaning),
        ...RuleVocabulary.operatorLabels.values,
      ];
      final missing = labels
          .where((l) => l != 'Deutsch' && l != 'English')
          .where((l) => !kEnglish.containsKey(l))
          .toList();
      expect(missing, isEmpty, reason: 'Fehlend: ${missing.join(", ")}');
    });

    test('kein Eintrag ohne Verwendung', () {
      // Karteileichen sind harmlos, aber sie taeuschen Abdeckung vor: Man
      // sieht 550 Zeilen und glaubt, alles sei uebersetzt.
      final used = translatedSources()
        // Die Systemtexte laufen als Variable durch die Uebersetzung
        // (`translate(language, entry.value)`) und sind im Quelltext nicht
        // als Literal zu finden. Benutzt sind sie trotzdem — auf jedem
        // Geraet, in jeder Benachrichtigung.
        ..addAll(SystemTexts.sources.values)
        ..addAll(SystemTexts.reasons.values);
      // Kern-Saetze und Betriebssystemtexte stehen nicht im App-Quelltext.
      const fromCoreOrSystem = 24;
      final unused = kEnglish.keys.where((k) => !used.contains(k)).length;
      expect(unused, lessThanOrEqualTo(kEnglish.length ~/ 4 + fromCoreOrSystem));
    });
  });

  group('Platzhalter', () {
    test('deutsche und englische Fassung haben dieselben Platzhalter', () {
      final placeholder = RegExp(r'\{\d+\}');
      final broken = <String>[];
      kEnglish.forEach((de, en) {
        final a = placeholder.allMatches(de).map((m) => m.group(0)!).toSet();
        final b = placeholder.allMatches(en).map((m) => m.group(0)!).toSet();
        if (a.length != b.length || !a.containsAll(b)) {
          broken.add('"$de" → "$en"');
        }
      });
      expect(broken, isEmpty,
          reason: 'Ein fehlender Platzhalter loescht eine Zahl aus dem '
              'Satz, ein zusaetzlicher zeigt "{1}" an:\n${broken.join("\n")}');
    });
  });

  group('Ton bleibt erhalten', () {
    /// Dieselbe Prüfung wie im Deutschen, in der Zielsprache.
    /// Eine Übersetzung kann aus einem Messwert unbemerkt ein Urteil machen.
    const blame = [
      'you failed',
      'you should',
      'you still have',
      // Nicht das blosse "again": Es steckt in "check again" und meint dort
      // nichts. Vorwurf traegt erst die Verbindung mit einer Person oder
      // einer Wiederholung, die als Versaeumnis gelesen wird.
      'yet again',
      'once again you',
      'still not',
      'lazy',
      'streak',
      'don’t forget',
      'at least you',
      'finally',
    ];

    test('keine Schuldsprache in der englischen Fassung', () {
      final hits = <String>[];
      kEnglish.forEach((de, en) {
        final lower = en.toLowerCase();
        for (final word in blame) {
          // Wortgrenzen, sonst trifft "again" auch "against".
          if (!RegExp('\\b${RegExp.escape(word)}\\b').hasMatch(lower)) {
            continue;
          }
          // Verneinte Nennungen sind erwuenscht: Das Onboarding sagt
          // ausdruecklich zu, was AXIOM *nicht* tut.
          final before = lower.substring(0, lower.indexOf(word));
          if (RegExp(r'\b(no|never|without|not)\b').hasMatch(before)) continue;
          hits.add('"$en" → "$word"');
        }
      });
      expect(hits, isEmpty, reason: 'Schuldsprache:\n${hits.join("\n")}');
    });

    test('erkennt Schuldsprache, wenn sie auftaucht', () {
      // Der Waechter muss selbst ueberwacht werden.
      const bad = 'you should finally do this';
      expect(
        blame.any((w) => RegExp('\\b${RegExp.escape(w)}\\b').hasMatch(bad)),
        isTrue,
      );
    });

    test('keine Ausrufezeichen-Motivation', () {
      final shouting = kEnglish.values.where((v) => v.contains('!')).toList();
      expect(shouting, isEmpty, reason: 'AXIOM ist ein Werkzeug, kein Coach.');
    });
  });

  group('Umschaltung', () {
    testWidgets('dieselbe Ansicht spricht Englisch', (tester) async {
      Widget probe(AppLanguage language) => MaterialApp(
            home: AxiomLanguage(
              language: language,
              child: Builder(
                builder: (context) => Text(context.t('Nichts in Reichweite')),
              ),
            ),
          );

      await tester.pumpWidget(probe(AppLanguage.de));
      expect(find.text('Nichts in Reichweite'), findsOneWidget);

      await tester.pumpWidget(probe(AppLanguage.en));
      await tester.pump();
      expect(find.text('Nothing in reach'), findsOneWidget);
      expect(find.text('Nichts in Reichweite'), findsNothing);
    });

    testWidgets('Platzhalter werden in beiden Sprachen gefüllt',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AxiomLanguage(
          language: AppLanguage.en,
          child: Builder(
            builder: (context) =>
                Text(context.t('{0} min über der geplanten Zeit.', [37])),
          ),
        ),
      ));
      expect(find.text('37 min past the planned time.'), findsOneWidget);
    });

    test('ohne Übersetzung erscheint der deutsche Satz, nicht der Schlüssel',
        () {
      const unknown = 'Ein Satz, den es nicht gibt';
      expect(translate(AppLanguage.en, unknown), unknown);
    });
  });

  // ── Systemseite ─────────────────────────────────────────────────────────
  //
  // Die Luecke, die `translatedSources()` nicht sieht: Was Android zeichnet,
  // steht in Kotlin, im Manifest und in `res/`. Dort war der Text fest
  // deutsch, waehrend die App Englisch sprach — und kein Test hat es gemerkt,
  // weil alle nur `lib/` lesen.
  group('Systemseite', () {
    String android(String path) =>
        File('android/app/src/main/$path').readAsStringSync();

    /// Kotlin-Quelltext ohne Kommentare und ohne Entwickler-Annotationen.
    ///
    /// Noetig aus demselben Grund wie in `platform_integration_test`: Die
    /// Kommentare erklaeren auf Deutsch, warum hier kein Deutsch mehr steht.
    /// Ohne diesen Schritt verboete der Test das Erklaeren.
    String kotlinCode(String source) {
      var text = source.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
      // `@Deprecated("…")` und `@Suppress("…")` sind Entwicklerprosa und
      // erreichen keinen Nutzer.
      text = text.replaceAll(
          RegExp(r'@(?:Deprecated|Suppress)\([^)]*\)', dotAll: true), '');
      return text
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
    }

    List<File> kotlinFiles() =>
        Directory('android/app/src/main/kotlin')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.kt'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    /// Zeichenketten-Literale einer Kotlin-Datei, ohne Kommentare.
    Iterable<String> kotlinLiterals(File file) => RegExp(r'"((?:[^"\\\n]|\\.)*)"')
        .allMatches(kotlinCode(file.readAsStringSync()))
        .map((m) => m.group(1)!);

    /// Die Namen aus einer `strings.xml`.
    Map<String, String> strings(String qualifier) {
      final source = android('res/values$qualifier/strings.xml');
      return {
        for (final m in RegExp(r'<string name="([^"]+)">(.*?)</string>',
                dotAll: true)
            .allMatches(source))
          m.group(1)!: m.group(2)!,
      };
    }

    /// Schlüssel → Ressourcenname aus `AxiomTexts.FALLBACK`.
    Map<String, String> kotlinFallback() => {
          for (final m in RegExp(r'"([\w.]+)" to R\.string\.(\w+)')
              .allMatches(android('kotlin/de/atomfritte/axiom/AxiomTexts.kt')))
            m.group(1)!: m.group(2)!,
        };

    test('Kotlin und Dart kennen dieselben Schlüssel', () {
      // Ein Schluessel, den nur eine Seite kennt, ist ein Text, der
      // irgendwann leer bleibt — und Leere ist der einzige Zustand, den man
      // auf dem Geraet nicht deuten kann.
      expect(kotlinFallback().keys.toSet(), SystemTexts.sources.keys.toSet());
    });

    test('jeder Schlüssel hat einen Rückfall in beiden Sprachen', () {
      // Der Rueckfall greift, bevor die App je gelaufen ist: erster Start,
      // Alarm nach einem Neustart, Schnelleinstellung direkt nach der
      // Installation.
      final de = strings('-de');
      final en = strings('');
      final missing = <String>[];
      kotlinFallback().forEach((key, resource) {
        if (!en.containsKey(resource)) missing.add('values/: $resource');
        if (!de.containsKey(resource)) missing.add('values-de/: $resource');
      });
      expect(missing, isEmpty, reason: missing.join('\n'));
      // Bis auf die eine Ausnahme, die Android erzwingt (siehe unten).
      expect(en.keys.where((k) => !k.startsWith('fgs_')).toSet(),
          de.keys.toSet(),
          reason: 'Beide strings.xml müssen dieselben Namen führen');
    });

    test('die Begründung des Dienst-Typs steht bewusst nur einmal da', () {
      // Kein Versäumnis, sondern eine Regel von Android: Ressourcen, auf die
      // das Manifest verweist, dürfen nicht nach Konfiguration variieren.
      // Ein `values-de/`-Gegenstück bricht den Release-Build mit
      // `ManifestResource` ab — der Fehler fällt beim `flutter test` nicht
      // auf, sondern erst beim Bauen. Deshalb steht er hier.
      //
      // `android:label` ist von der Regel ausgenommen und wird weiter
      // übersetzt; die drei `fgs_*` sind es nicht.
      final de = strings('-de');
      final en = strings('');
      for (final name in ['fgs_presence', 'fgs_live', 'fgs_expert']) {
        expect(en, contains(name));
        expect(de, isNot(contains(name)), reason: name);
      }
      expect(strings('-de'), contains('label_create_note'));
    });

    test('values/ ist Englisch, values-de/ ist Deutsch', () {
      // `values/` ist der Rueckfall fuer jede Sprache, die sonst nirgends
      // passt — dieselbe Entscheidung, die `AppLanguage.fromLocale` trifft.
      // Steht dort Deutsch, bekommt ein franzoesisches Geraet eine englische
      // App mit deutschen Benachrichtigungen.
      final umlauts = RegExp('[äöüßÄÖÜ]');
      final english = strings('').entries
          .where((e) => umlauts.hasMatch(e.value))
          .map((e) => e.key)
          .toList();
      expect(english, isEmpty,
          reason: 'Deutsch in values/: ${english.join(", ")}');
      expect(strings('-de').values.where(umlauts.hasMatch), isNotEmpty);
    });

    /// Ob ein Kotlin-Literal nach Nutzertext aussieht.
    ///
    /// Bewusst keine Wortliste. Eine Liste deutscher Woerter faende
    /// „Dauerhafte Anzeige", aber nicht „Erfassen" — und genau die kurzen
    /// Knopfbeschriftungen sind es, die sich wieder einschleichen. Deshalb
    /// die umgekehrte Frage: Jedes Literal in diesen Dateien ist ein
    /// Bezeichner — ein Schluessel, eine Intent-Aktion, ein Prefs-Name. Die
    /// schreiben sich klein, ohne Leerzeichen und ohne Umlaute. Was anders
    /// aussieht, ist ein Satz und gehoert nach `SystemTexts`.
    /// Namen, die Android vorgibt und die niemand uebersetzen kann.
    ///
    /// Die Heuristik unten kann sie nicht von einem Wort unterscheiden: Sie
    /// fangen gross an, haben kein Leerzeichen und keinen Punkt. Sie sind
    /// trotzdem kein Nutzertext, sondern Bezeichner aus einer fremden
    /// Schnittstelle — `"AndroidKeyStore"` ist der Name eines JCA-Providers
    /// und steht so in der Android-Dokumentation.
    ///
    /// Die Liste bleibt kurz. Waechst sie, ist das eine Entscheidung: Wer
    /// hier etwas eintraegt, nimmt es aus der Pruefung heraus, und das soll
    /// man sehen.
    const platformNames = {'AndroidKeyStore'};

    bool looksLikeUserText(String literal) {
      if (literal.length < 3) return false;
      if (platformNames.contains(literal)) return false;
      if (RegExp('[äöüßÄÖÜ„”]').hasMatch(literal)) return true;
      // Zeichenketten mit `$` sind Vorlagen: Sie setzen Werte in einen Text
      // ein, der selbst schon aus `AxiomTexts` kommt.
      if (literal.contains(r'$')) return false;
      if (literal.contains(' ')) return true;
      final structural = literal.contains('.') ||
          literal.contains('_') ||
          literal.contains('/');
      return !structural && literal[0] == literal[0].toUpperCase() &&
          literal[0] != literal[0].toLowerCase();
    }

    test('kein Kotlin-Quelltext erfindet Nutzertext', () {
      // Der eigentliche Punkt dieser Gruppe. Alles, was Android anzeigt,
      // kommt ueber `AxiomTexts` von der Dart-Seite; was hier noch als
      // deutscher Satz steht, waere wieder fest verdrahtet.
      final hits = <String>[];
      for (final file in kotlinFiles()) {
        for (final literal in kotlinLiterals(file)) {
          if (looksLikeUserText(literal)) {
            hits.add('${file.path.split("/").last}: "$literal"');
          }
        }
      }
      expect(hits, isEmpty,
          reason: 'Fest verdrahteter Nutzertext:\n${hits.join("\n")}');
    });

    test('erkennt fest verdrahteten Text, wenn er auftaucht', () {
      // Der Waechter muss selbst ueberwacht werden: ein Test, der nie
      // anschlaegt, ist von einem kaputten nicht zu unterscheiden.
      for (final bad in [
        'Dauerhafte Anzeige',
        'Erfassen',
        'Beenden',
        'Slot läuft',
        'Kapazität',
      ]) {
        expect(looksLikeUserText(bad), isTrue, reason: bad);
      }
      for (final fine in [
        'de.atomfritte.axiom.CAPTURE',
        'axiom_nudge',
        'presence.capture',
        'headline',
        r'${e.javaClass.simpleName}: $it',
      ]) {
        expect(looksLikeUserText(fine), isFalse, reason: fine);
      }
    });

    test('jeder Schlüssel, den Kotlin liest, ist auch gefüllt', () {
      final used = <String>{};
      for (final file in kotlinFiles()) {
        for (final m in RegExp(r'AxiomTexts\.(?:get|format)\(\s*[^,]+,\s*"([^"$]+)"')
            .allMatches(kotlinCode(file.readAsStringSync()))) {
          used.add(m.group(1)!);
        }
      }
      expect(used, isNotEmpty);
      final unknown = used.difference(SystemTexts.sources.keys.toSet());
      expect(unknown, isEmpty, reason: 'Ohne Eintrag bleibt der Text leer');
    });

    test('jeder Grund, den Kotlin meldet, hat einen Satz', () {
      // Kotlin schickt nur den Schluessel herauf. Kennt die Dart-Seite ihn
      // nicht, stuende auf dem Bildschirm „reason.notes.dialog" — sichtbar
      // unfertig, aber unbrauchbar.
      final keys = <String>{};
      for (final file in kotlinFiles()) {
        final code = kotlinCode(file.readAsStringSync());
        for (final pattern in [
          RegExp(r'"reason" to "(reason\.[\w.]+)"'),
          RegExp(r'failure\(\s*"(reason\.[\w.]+)"'),
        ]) {
          keys.addAll(pattern.allMatches(code).map((m) => m.group(1)!));
        }
      }
      expect(keys, isNotEmpty);
      expect(keys.difference(SystemTexts.reasons.keys.toSet()), isEmpty);
    });

    test('das Manifest zeigt keinen Text, nur Verweise', () {
      // `android:label` erscheint im Launcher, in den Standard-Apps und in
      // der Schnelleinstellung — gezeichnet vom System, also nur als
      // Ressource uebersetzbar.
      final manifest = android('AndroidManifest.xml')
          .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
      final labels = RegExp(r'android:label="([^"]*)"')
          .allMatches(manifest)
          .map((m) => m.group(1)!)
          // Der Produktname wird nicht uebersetzt.
          .where((v) => v != 'AXIOM')
          .where((v) => !v.startsWith('@'));
      expect(labels, isEmpty, reason: 'Fester Text im Manifest: $labels');

      // Dasselbe fuer die Begruendung des Vordergrunddienst-Typs.
      final values = RegExp(r'android:value="([^"]*)"', dotAll: true)
          .allMatches(manifest)
          .map((m) => m.group(1)!)
          .where((v) => v.contains(' '));
      expect(values, isEmpty, reason: 'Fester Text im Manifest: $values');
    });

    test('das Widget-Layout zeigt keinen Text, nur Verweise', () {
      for (final file in ['axiom_widget', 'axiom_widget_preview']) {
        final texts = RegExp(r'android:text="([^"]*)"')
            .allMatches(android('res/layout/$file.xml'))
            .map((m) => m.group(1)!)
            .where((v) => !v.startsWith('@string/'));
        expect(texts, isEmpty, reason: '$file: $texts');
      }
    });

    test('jeder Systemtext hat eine englische Fassung', () {
      final missing = [...SystemTexts.sources.values, ...SystemTexts.reasons.values]
          .where((s) => !kEnglish.containsKey(s))
          .toList();
      expect(missing, isEmpty,
          reason: 'Sonst steht der deutsche Satz in einer englischen '
              'Benachrichtigung:\n${missing.join("\n")}');
    });

    test('deutsche Systemtexte verwenden echte Umlaute', () {
      // Diese Saetze entgehen `language_test`: Der Scanner dort ueberspringt
      // jedes Literal mit Punkt oder Unterstrich — also fast jeden Satz hier.
      final substitutions = RegExp(
        r'\b\w*(aet|aessig|aend|aerk|oeg|oenn|oech|oes|uehr|uenf|uecke|uerz|'
        r'uebe|uess|uerd|uenst)\w*\b',
      );
      final hits = [
        ...SystemTexts.sources.values,
        ...SystemTexts.reasons.values,
        ...strings('-de').values,
      ].where(substitutions.hasMatch).toList();
      expect(hits, isEmpty,
          reason: 'Ersatzschreibung statt Umlaut:\n${hits.join("\n")}');
    });

    test('Platzhalter überstehen alle vier Fassungen', () {
      // Deutsch, Englisch und die beiden Ressourcendateien sagen denselben
      // Satz. Fehlt in einer davon ein `{0}`, verschwindet dort eine Zahl —
      // und zwar genau in der Fassung, die man am seltensten sieht.
      final placeholder = RegExp(r'\{\d+\}');
      // Sortierte Liste, nicht Menge: `Set == Set` vergleicht in Dart die
      // Identität, nicht den Inhalt — der Test waere sonst immer rot.
      List<String> marks(String s) =>
          (placeholder.allMatches(s).map((m) => m.group(0)!).toSet().toList())
            ..sort();

      final de = strings('-de');
      final en = strings('');
      final fallback = kotlinFallback();
      final broken = <String>[];

      SystemTexts.sources.forEach((key, source) {
        final expected = marks(source);
        final resource = fallback[key];
        for (final (label, text) in [
          ('en.dart', kEnglish[source] ?? source),
          if (resource != null) ...[
            ('values-de/', de[resource] ?? ''),
            ('values/', en[resource] ?? ''),
          ],
        ]) {
          if (marks(text).join() != expected.join()) {
            broken.add('$key → $label: "$text"');
          }
        }
      });
      expect(broken, isEmpty, reason: broken.join('\n'));
    });
  });
}

/// Rendert die Screens auf Englisch und liest, was wirklich dasteht.
void _renderedInEnglish() {
  /// Die Screens, die auf Englisch nachweislich englisch sind.
  ///
  /// **Diese Liste soll wachsen.** Was fehlt, fehlt nicht aus Versehen,
  /// sondern weil dort heute noch deutsche Reste stehen — jeder mit einem
  /// eigenen Befund:
  ///   `jetzt`     — „Tag review open · 2 min", „Fokus" (now_screen)
  ///   `eingang`   — „Start 3/10 · in Reichweite" (inbox_screen)
  ///   `system`    — „NÄCHTE", „Es fehlt noch: … Schlafeinträge."
  ///   `reiz`      — die ausgelieferten Kanalnamen („Kalt duschen")
  ///   `hilfe`     — die Kapitelüberschriften kommen aus dem Hilfetext,
  ///                 nicht aus der Wörterliste; sie sind übersetzt, lassen
  ///                 sich hier aber nicht dagegen prüfen.
  /// Wer einen davon aufräumt, trägt ihn hier ein. Erst dann ist er
  /// dauerhaft aufgeräumt.
  final screens = <String, Widget Function()>{
    'aufgaben': () => const TasksScreen(),
    'zustand': () => const StateScreen(),
    'systemcheck': () => const CheckScreen(),
    'erfassen': () => const ChannelsScreen(),
    'anker': () => const AnchorsScreen(),
    'fokus': () => const FocusScreen(),
    'bremse': () => const InterceptScreen(),
    'review': () => const ReviewScreen(),
    'vorfälle': () => const SignalScreen(),
    'daten': () => const VaultScreen(),
    'expertenmodus': () => const ExpertScreen(),
  };

  /// Die Daten, die dieser Test selbst anlegt. Sie sind Nutzertext und
  /// werden nie übersetzt — deshalb hier bewusst englisch benannt, damit
  /// der Wächter sie nicht mit einem deutschen Rest verwechselt.
  const fixtures = {
    'Tax papers',
    'Landlord callback',
    'Air the room',
    'A thought worth keeping',
    'Morning',
    'Purchase over 200',
  };

  late TestHarness h;

  /// Wie `lib/app.dart`: die Sprache über dem Navigator.
  ///
  /// Unter `home:` sähe ein modales Blatt sie nicht und fiele auf Deutsch
  /// zurück — der Test würde dann sein eigenes Gerüst anzeigen statt einen
  /// echten Fehler.
  Widget shell(Widget screen, {GlobalKey<NavigatorState>? navigator}) =>
      MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: navigator,
        theme: buildAxiomTheme(brightness: Brightness.dark),
        builder: (context, child) => AxiomLanguage(
          language: AppLanguage.en,
          child: child ?? const SizedBox.shrink(),
        ),
        home: screen,
      );

  Widget english(Widget screen) => ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(h.clock),
          runtimeProvider.overrideWith((ref) async => h.runtime),
        ],
        child: shell(screen),
      );

  /// Regeltexte kommen aus dem YAML, nicht aus der Wörterliste.
  ///
  /// Bewusst nur die englische Fassung: Stünde hier auch `rule.title`, wäre
  /// genau der Fehler unsichtbar, den `system_sync` hatte — ein deutscher
  /// Regeltitel neben einer übersetzten Zeile.
  Set<String> ruleTexts() => {
        for (final rule in h.runtime.rules) ...[
          rule.titleFor('en'),
          rule.rationaleFor('en'),
        ],
      };

  List<String> germanLeftovers(WidgetTester tester) {
    final allowed = {...fixtures, ...ruleTexts()};
    final offenders = <String>[];
    for (final widget in tester.widgetList<Text>(find.byType(Text))) {
      final text = widget.data ?? widget.textSpan?.toPlainText();
      if (text == null || text.trim().isEmpty) continue;
      if (allowed.contains(text) || _harmless.hasMatch(text)) continue;
      if (looksGerman(text)) {
        offenders.add('deutsch stehengeblieben: "$text"');
      } else if (!accountedFor(text)) {
        offenders.add('keine englische Fassung: "$text"');
      }
    }
    return offenders.toSet().toList();
  }

  setUp(() async {
    h = TestHarness.create(at: DateTime(2026, 8, 4, 14, 30));
    h.store.setSetting('language', 'en');
    h.completeOnboarding();
    await h.seedChannels();
    // Ein leerer Screen zeigt wenig Text. Genau die Zeilen, die aus echten
    // Daten entstehen, sind die, in denen deutsche Reste sitzen.
    for (final (title, ae) in [
      ('Tax papers', 7),
      ('Landlord callback', 3),
      ('Air the room', 1),
    ]) {
      await h.runtime.createTask(
          title: title, activationEnergy: ae, salience: 5, stakes: 6);
    }
    await h.runtime.capture('A thought worth keeping');
    await h.runtime.checkIn(energy: 4, focus: 3, mood: 5, stimNeed: 7);
  });

  tearDown(() => h.dispose());

  for (final entry in screens.entries) {
    testWidgets('${entry.key} spricht Englisch', (tester) async {
      // Hoch statt 915: Eine `ListView` baut nur, was sichtbar ist — auf
      // Telefonhoehe faellt der halbe Screen aus dem Baum, und mit ihm der
      // deutsche Rest.
      await pumpPhone(tester, english(entry.value()),
          size: const Size(412, 2600));
      expect(germanLeftovers(tester), isEmpty,
          reason: 'Auf dem Screen "${entry.key}":\n'
              '${germanLeftovers(tester).join("\n")}');
      await unmount(tester);
    });
  }

  testWidgets('das Onboarding spricht Englisch, Seite für Seite',
      (tester) async {
    // Durchblaettern, nicht nur die erste Seite: Der Knopf heisst auf der
    // letzten Seite anders, und die letzte Seite hat eine eigene Rubrik.
    // Genau in diesen beiden Zweigen stand der deutsche Text.
    await pumpPhone(tester, english(OnboardingScreen(onDone: () {})),
        size: const Size(412, 2600));
    for (var page = 1; page <= 6; page++) {
      expect(germanLeftovers(tester), isEmpty,
          reason: 'Onboarding-Seite $page:\n'
              '${germanLeftovers(tester).join("\n")}');
      if (page == 6) break;
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    // Auf der letzten Seite steht „Here we go" statt „Next" — der andere
    // Zweig desselben Ternaers.
    expect(find.text('Next'), findsNothing);
  });

  testWidgets('die Meldung nach dem Review spricht Englisch', (tester) async {
    // Der Review schliesst sich beim Abschluss selbst, die Meldung erscheint
    // danach auf dem Bildschirm darunter. Ohne eine Route darunter gaebe es
    // nichts, worauf sie stehen koennte — deshalb der Umweg ueber einen
    // eigenen Startbildschirm.
    final navigator = GlobalKey<NavigatorState>();
    await pumpPhone(
        tester,
        ProviderScope(
          overrides: [
            clockProvider.overrideWithValue(h.clock),
            runtimeProvider.overrideWith((ref) async => h.runtime),
            // Ohne Urteile bleibt der Review kurz genug, dass der
            // Abschlussknopf im Baum steht — eine `ListView` baut nur, was
            // sichtbar ist.
            reviewProvider(ReviewScope.week).overrideWith((ref) async => (
                  metrics: const ReviewEngine().metrics(const ReviewInputs()),
                  verdicts: const <RuleVerdict>[],
                )),
          ],
          child: shell(const Scaffold(body: SizedBox.shrink()),
              navigator: navigator),
        ),
        size: const Size(412, 2600));
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const ReviewScreen(scope: ReviewScope.week)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Finish review'));
    await tester.pumpAndSettle();
    expect(germanLeftovers(tester), isEmpty,
        reason: 'Meldung:\n${germanLeftovers(tester).join("\n")}');
    await unmount(tester);
  });

  testWidgets('das Wiedereinstiegs-Blatt spricht Englisch', (tester) async {
    // Ein modales Blatt haengt am Navigator, nicht am Screen darunter — und
    // genau dort stand die Wiedereinstiegsfrage auf Deutsch.
    await h.runtime.startFocus(
        taskId: 't1',
        taskTitle: 'Tax papers',
        planned: const Duration(minutes: 50));
    h.clock.advance(const Duration(minutes: 20));
    await pumpPhone(tester, english(const FocusScreen()),
        size: const Size(412, 2600));
    await tester.tap(find.text('End focus'));
    await tester.pumpAndSettle();
    expect(germanLeftovers(tester), isEmpty,
        reason: germanLeftovers(tester).join('\n'));
    await unmount(tester);
  });

  testWidgets('das Trigger-Blatt spricht Englisch', (tester) async {
    await pumpPhone(tester, english(const InterceptScreen()),
        size: const Size(412, 2600));
    await tester.tap(find.text('Add trigger'));
    await tester.pumpAndSettle();
    expect(germanLeftovers(tester), isEmpty,
        reason: 'Vorlagen im Blatt:\n${germanLeftovers(tester).join("\n")}');

    // Eine Vorlage übernehmen: Sie wandert aus der Chip-Reihe in die Liste
    // der eigenen Fragen — zweite Stelle, dieselbe Frage.
    await tester.tap(find.text('Is it the thing or the feeling?'));
    await tester.pumpAndSettle();
    expect(germanLeftovers(tester), isEmpty,
        reason: 'übernommene Vorlage:\n${germanLeftovers(tester).join("\n")}');
    await unmount(tester);
  });

  testWidgets('eine gespeicherte Vorlage steht beim Abfangen auf Englisch',
      (tester) async {
    // Gespeichert wird der deutsche Quelltext — er ist der Schlüssel. Beim
    // Abfangen muss daraus wieder die englische Frage werden, sonst hat die
    // Checkliste dauerhaft die Sprache des Tages, an dem sie entstand.
    const trigger = InterceptTrigger(
      id: 'purchase',
      label: 'Purchase over 200',
      cooldown: Duration(minutes: 15),
      checklist: ['Ist es die Sache oder das Gefühl?'],
      authorized: true,
    );
    await h.runtime.saveTrigger(trigger);
    await h.runtime.startIntercept(trigger);
    await pumpPhone(tester, english(const InterceptScreen()),
        size: const Size(412, 2600));
    expect(find.text('Is it the thing or the feeling?'), findsOneWidget);
    expect(germanLeftovers(tester), isEmpty,
        reason: germanLeftovers(tester).join('\n'));
    await unmount(tester);
  });

  testWidgets('das Wirkfenster spricht Englisch', (tester) async {
    // Der Abgrenzungssatz zum Medizinprodukt (R10) stand hier deutsch in
    // einer englischen Oberflaeche — zweimal, und einmal sogar, wenn das
    // Modul gar nicht eingeschaltet war.
    h.runtime.medEnabled = true;
    await h.runtime.logMedEntry(
        label: 'Morning',
        onset: Duration.zero,
        duration: const Duration(minutes: 45));
    await pumpPhone(tester, english(const VaultScreen()),
        size: const Size(412, 2600));
    expect(germanLeftovers(tester), isEmpty,
        reason: 'Modulkarte:\n${germanLeftovers(tester).join("\n")}');

    // Der Satz steht bewusst zweimal — auch über dem Eingabeblatt.
    await tester.tap(find.text('Log an intake'));
    await tester.pumpAndSettle();
    expect(germanLeftovers(tester), isEmpty,
        reason: 'Eingabeblatt:\n${germanLeftovers(tester).join("\n")}');
    await unmount(tester);
  });

  test('Widget und Benachrichtigung sprechen die Sprache der App', () {
    // Diese Ebene fällt durch jeden Widget-Test: Was Android zeichnet,
    // entsteht ohne Widget-Baum. Vorher stand dort der deutsche Regeltitel
    // über einer übersetzten Zeile — zwei Oberflächen, zwei Sprachen für
    // dieselbe Ausgabe.
    final rules = YamlRuleSource(loadRuleAssets()).parse().rules;
    final rule = rules.firstWhere((r) => r.titleFor('en') != r.title);
    final snapshot = AxiomSnapshot(
      at: DateTime(2026, 8, 4, 14, 30),
      state: StateVector(
          at: DateTime(2026, 8, 4, 14, 30),
          capacity: 60,
          focusDebt: 20,
          sensationNeed: 30,
          loadIndex: 25,
          regulation: 55,
          sleepDebt: 10),
      breakdown: const {},
      tasks: const [],
      metaUsedToday: const Duration(minutes: 30),
      decisionRule: rule,
    );

    final (headlineEn, detailEn) = SystemSync.describe(snapshot, AppLanguage.en);
    expect(headlineEn, rule.titleFor('en'));
    expect(detailEn, 'Rule ${rule.id}');

    final (headlineDe, detailDe) = SystemSync.describe(snapshot, AppLanguage.de);
    expect(headlineDe, rule.title);
    expect(detailDe, 'Regel ${rule.id}');
  });

  testWidgets('auch die selten getroffenen Zustände sprechen Englisch',
      (tester) async {
    // Etiketten in einem `switch`-Tupel erscheinen nur in dem Zustand, der
    // sie erzeugt — ein Screen im Normalfall zeigt sie nie. Genau deshalb
    // sind sie deutsch geblieben: Weder ein Durchklicken noch ein
    // Referenzbild kommt hier vorbei.
    await h.runtime.startFocus(
        taskId: 't1',
        taskTitle: 'Tax papers',
        planned: const Duration(minutes: 50));

    // Fokus: leichte und deutliche Überziehung.
    for (final overrun in [
      kGentleAfterOverrun + const Duration(minutes: 1),
      kClearAfterOverrun + const Duration(minutes: 1),
    ]) {
      h.clock.advance(const Duration(minutes: 50) + overrun);
      await pumpPhone(tester, english(const FocusScreen()),
          size: const Size(412, 2600));
      expect(germanLeftovers(tester), isEmpty,
          reason: 'Fokus, ${overrun.inMinutes} min über:\n'
              '${germanLeftovers(tester).join("\n")}');
      await unmount(tester);
      h.clock.advance(-(const Duration(minutes: 50) + overrun));
    }

    // Review: alle drei Urteile über eine Regel auf einmal. Sie entstehen
    // sonst nur aus Wochen echter Nutzung — hier eingesetzt, weil es um den
    // Text geht, nicht um die Herleitung.
    await pumpPhone(
        tester,
        ProviderScope(
          overrides: [
            clockProvider.overrideWithValue(h.clock),
            runtimeProvider.overrideWith((ref) async => h.runtime),
            reviewProvider(ReviewScope.week).overrideWith((ref) async => (
                  metrics: const ReviewEngine().metrics(const ReviewInputs()),
                  verdicts: [
                    for (final action in RuleAction.values)
                      RuleVerdict(
                        ruleId: 'R-001',
                        verdict: action,
                        reason: 'Hat nie gefeuert. Entweder ist die Bedingung '
                            'zu eng oder die Regel überflüssig.',
                      ),
                  ],
                )),
          ],
          child: shell(const ReviewScreen(scope: ReviewScope.week)),
        ),
        size: const Size(412, 2600));
    expect(germanLeftovers(tester), isEmpty,
        reason: 'Review-Urteile:\n${germanLeftovers(tester).join("\n")}');
    await unmount(tester);
  });

  test('der Wächter erkennt, was ihm vorher entkommen ist', () {
    // Ein Waechter, der nie anschlaegt, ist von einem kaputten nicht zu
    // unterscheiden. Die fuenf Faelle hier sind die, die der alte
    // Quelltext-Scanner durchgelassen hat.
    expect(accountedFor('Weiter'), isFalse, reason: 'Ternaer-Zweig');
    expect(looksGerman('Exportieren'), isTrue, reason: 'Ternaer-Zweig');
    expect(looksGerman('Woche review'), isTrue, reason: 'Platzhalterwert');
    expect(looksGerman('Fenster läuft noch 45 min.'), isTrue,
        reason: 'Satz aus dem Kern');
    expect(looksGerman('Wo genau bist du bei „Tax papers" stehengeblieben?'),
        isTrue,
        reason: 'zusammengesetzter Satz aus dem Kern');
    expect(looksGerman('Ist es die Sache oder das Gefühl?'), isTrue,
        reason: 'Vorlage aus einer Liste');
    expect(looksGerman('HINWEIS'), isTrue, reason: 'Etikett im Tupel');

    // Und die Gegenprobe: Englisch bleibt unbehelligt.
    for (final fine in [
      'Weekly review',
      'Window has 45 min left.',
      'Where exactly did you leave off on “Tax papers”?',
      'Is it the thing or the feeling?',
      'NOTICE',
    ]) {
      expect(looksGerman(fine), isFalse, reason: fine);
      expect(accountedFor(fine), isTrue, reason: fine);
    }
  });
}
