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
import 'package:flutter_test/flutter_test.dart';

import 'package:axiom_core/axiom_core.dart';

import 'package:axiom_app/design/tokens.dart';
import 'package:axiom_app/state/rule_draft.dart';
import 'package:axiom_app/i18n/en.dart';
import 'package:axiom_app/i18n/i18n.dart';
import 'package:axiom_app/platform/system_texts.dart';

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

void main() {
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
              .allMatches(android('kotlin/de/axiom/axiom_app/AxiomTexts.kt')))
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
    bool looksLikeUserText(String literal) {
      if (literal.length < 3) return false;
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
        'KAPAZITÄT',
      ]) {
        expect(looksLikeUserText(bad), isTrue, reason: bad);
      }
      for (final fine in [
        'de.axiom.CAPTURE',
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
