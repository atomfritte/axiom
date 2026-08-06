/// Was die Weboberfläche des Expertenmodus beim Klick **tut**.
///
/// `expert_i18n_test.dart` liest den Quelltext von `assets/expert/index.html`.
/// Das findet einen vergessenen Satz, aber nicht einen Knopf, der nichts tut:
/// Zehn geprüfte Fehler dieser Seite hatten gemeinsam, dass ein abgelehnter
/// Aufruf überhaupt keinen Weg an die Oberfläche hatte — der Server schrieb
/// „Feld \"breadcrumb\" ist leer", die Seite schwieg, und der Fokus lief
/// weiter.
///
/// Deshalb hier ein zweiter Zugang: `test/expert_client.js` führt die echte
/// Seite unter Node aus, mit gerade so viel DOM, wie sie anfasst, drückt
/// Knöpfe und schreibt eine Zeile JSON. Dieser Test liest sie. Geprüft wird
/// Wirkung, nicht Schreibweise — welche Zeile den Fehler behebt, ist ihm
/// gleich.
///
/// Ohne `node` läuft er nicht. Er meldet das dann sichtbar, statt still
/// durchzuwinken.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ein Szenario laufen lassen und seine Antwort lesen.
Map<String, dynamic> drive(String scenario) {
  final script = File('test/expert_client.js').absolute.path;
  final result = Process.runSync('node', [script, scenario]);
  expect(result.exitCode, 0,
      reason: 'Szenario "$scenario" ist umgefallen:\n'
          '${result.stdout}\n${result.stderr}');
  final out = result.stdout.toString().trim();
  return jsonDecode(out.split('\n').last) as Map<String, dynamic>;
}

bool get hasNode {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  final skip = hasNode ? null : 'node fehlt — die Weboberfläche bleibt ungeprüft';

  group('Weboberfläche des Expertenmodus — Verhalten', () {
    test('ein leeres Notizfeld heißt „nicht angegeben", nicht „leerer Text"',
        () {
      // Der Server lehnt ein optionales Feld ab, das als Leerstring ankommt.
      // Vorher lief der Fokus danach weiter, ohne dass irgendwo etwas stand.
      final r = drive('focus-end-empty');
      expect(r['breadcrumb'], isNull);
      expect(r['method'], 'DELETE');
    });

    test('eine Ablehnung des Servers erscheint auf dem Bildschirm', () {
      final r = drive('focus-end-empty');
      expect(r['toast'], contains('breadcrumb'),
          reason: 'Ein 400 ohne Meldung ist von einem kaputten Knopf nicht '
              'zu unterscheiden');
      expect(r['dialogOffen'], isTrue,
          reason: 'Was nicht angekommen ist, darf nicht weggeräumt werden');
    });

    test('Fokus starten ohne Ziel schickt kein leeres Feld', () {
      expect(drive('focus-start-empty')['title'], isNull);
    });

    test('eine lange Notiz lässt sich übernehmen', () {
      // Der Kern kennt keine Längengrenze, `/api/tasks` schon (500).
      // Ohne Kappung tat der Knopf nichts.
      final r = drive('adopt-long-note');
      expect(r['gesendet'], 1);
      expect(r['laenge'], lessThanOrEqualTo(500));
      expect(r['volltextErhalten'], isTrue,
          reason: 'Gekürzt wird am Anfang des Textes, nicht irgendwo');
      expect(r['toast'], isNotEmpty);
    });

    test('die Zahl am Reiter „Eingang" zählt, was im Eingang steht', () {
      // Sie kam aus `S.inboxCount` — Aufgaben im Zustand `inbox`, eine Menge,
      // die auf keinem Weg dieser App entsteht. Die Zahl stand deshalb auf
      // nichts, während Notizen lagen. Genau diese Zahl ist der Grund, den
      // Reiter NICHT öffnen zu müssen (G1).
      final r = drive('inbox-badge');
      expect(r['badge'], ' 3');
    });

    test('die Gruppen sprechen die Sprache des Telefons, nicht die des '
        'Browsers', () {
      // Browser deutsch, App englisch. Die Beschriftung entstand beim Laden
      // des Skripts — also bevor die Sprache vom Telefon da war.
      final r = drive('group-labels');
      expect(r['baender'], ['Running', 'Within reach', 'Out of reach']);
      expect(r['ariaLabels'].first, startsWith('Running'));
    });

    test('die Vergleichsliste steht in der Sprache der Oberfläche', () {
      final labels = (drive('operator-labels')['labels'] as List).cast<String>();
      expect(labels, ['less than', 'at most', 'at least', 'greater than',
        'exactly', 'not']);
    });

    test('zwei Klicks auf „Als Aufgabe" legen eine Aufgabe an', () {
      // Zwei identische Einträge sind genau die Auswahlentscheidung, die
      // AXIOM abnehmen soll (G1).
      final r = drive('double-adopt');
      expect(r['posts'], 1);
      expect(r['gesperrtWaehrendAnfrage'], isTrue);
    });

    test('die Zerlegung endet dort, wo der Kern sie ablehnt', () {
      // Vorher ließen sich beliebig viele Schritte tippen; ab dem 21. lehnte
      // der Server ab, und sichtbar geschah nichts.
      final r = drive('atomize-limit');
      expect(r['zeilen'], 20);
      expect(r['plusGesperrt'], isTrue);
      expect(r['geschickt'], 20);
      expect(r['toast'], isNotEmpty);
    });

    test('auf der Anmeldeseite wirkt kein Tastenkürzel', () {
      // Ohne Sitzung ist nichts fokussiert, also griffen sie alle: „f" las
      // einen Zustand, den es nicht gab, „n" zog den Cursor in ein
      // verstecktes Feld, die Ziffern klickten Reiter in der unsichtbaren
      // Anwendung an.
      final r = drive('keys-on-gate');
      expect(r['gateSichtbar'], isTrue);
      expect(r['fehler'], isEmpty);
      expect(r['blaetter'], isEmpty);
      expect(r['aufrufe'], 0);
      expect(r['fokusImVerstecktenFeld'], isFalse);
      expect(r['gespeicherterReiter'], isNull);
    });

    test('Reiterstreifen und Fläche laufen nie auseinander', () {
      // Der Reiter wurde markiert und gespeichert, bevor sein Inhalt da war.
      final r = drive('tab-load-fails');
      expect(r['markiert'], ['board']);
      expect(r['gespeichert'], 'board');
      expect(r['flaeche'], 'board');
      expect(r['toast'], isNotEmpty);
    });

    test('die Hilfe öffnet in der Sprache der Oberfläche', () {
      final r = drive('help-language');
      for (final url in (r['gefragt'] as List).cast<String>()) {
        expect(url, endsWith('lang=en'));
      }
      expect(r['gefragt'], isNotEmpty);
    });

    test('eine getroffene Sprachwahl der Hilfe gewinnt', () {
      final r = drive('help-language-chosen');
      for (final url in (r['gefragt'] as List).cast<String>()) {
        expect(url, endsWith('lang=de'));
      }
      expect(r['gefragt'], isNotEmpty);
    });

    test('kein deutscher Satz steht in der englischen Oberfläche', () {
      // Der Wächter, den es vorher nicht gab. Der Quelltexttest sieht nur
      // Umlaute — „leer", „voll", „sofort", „von", „bis", „mindestens" und
      // „genau" sind ihm deshalb entkommen. Hier wird gezeichnet und
      // gelesen: Jeder sichtbare Text, der als SCHLÜSSEL in der EN-Tabelle
      // steht, ist die deutsche Fassung eines Satzes, dessen englische es
      // gibt — also nicht durch `tr()` gegangen oder zu früh übersetzt.
      final leaks = (drive('german-leak')['deutschInEnglisch'] as List);
      expect(leaks, isEmpty,
          reason: 'Deutsch in der englischen Oberfläche:\n${leaks.join('\n')}');
    });
  }, skip: skip);
}
