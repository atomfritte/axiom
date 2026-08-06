/// Phrase — der Weg, auf dem jeder Satz des Kerns die Oberflaeche erreicht.
///
/// Bis hierher gab es dazu keine einzige Zeile. Dabei laeuft jeder Text, den
/// `FocusGovernor`, `Interceptor` oder `ReviewEngine` erzeugt, durch
/// [interpolate] — und ein Satz, der beim Einsetzen der Werte kaputtgeht,
/// steht anschliessend so auf dem Bildschirm.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

void main() {
  group('Werte einsetzen', () {
    test('ohne Werte bleibt der Quelltext unangetastet', () {
      expect(const Phrase('Laeuft. Benachrichtigungen sind stumm.').text,
          'Laeuft. Benachrichtigungen sind stumm.');
      expect(interpolate('{0} min', const []), '{0} min');
    });

    test('derselbe Platzhalter zweimal bekommt zweimal denselben Wert', () {
      // Uebersetzungen duerfen einen Wert wiederholen — im Englischen steht
      // die Zahl oft an zwei Stellen.
      expect(const Phrase('{0} von {0}', [3]).text, '3 von 3');
    });

    test('die Reihenfolge der Werte ist frei waehlbar', () {
      // Der ganze Grund fuer nummerierte Platzhalter: Die Uebersetzung darf
      // die Wortfolge aendern.
      expect(const Phrase('{1} nach {0}', ['A', 'B']).text, 'B nach A');
    });

    test('ueberzaehlige Werte aendern nichts', () {
      expect(const Phrase('{0}', [1, 2, 3]).text, '1');
    });

    test('ein Platzhalter ohne Wert bleibt sichtbar stehen', () {
      // Sichtbar unfertig ist besser als stumm verschluckt: Ein fehlendes
      // Argument faellt beim ersten Blick auf, ein weggekuerzter Halbsatz
      // nicht.
      expect(const Phrase('{0} von {1}', [5]).text, '5 von {1}');
    });

    test('null wird gezeigt, nicht verschluckt', () {
      expect(const Phrase('{0}', [null]).text, 'null');
    });
  });

  group('Ein Wert ist ein Wert, kein neuer Quelltext', () {
    test('ein Wert, der wie ein Platzhalter aussieht, wird nicht ausgewertet',
        () {
      // Belegter Fall: `FocusGovernor` setzt `anchor.title` und den aus dem
      // Ortsnamen gebauten `step.label` als Werte ein — beides Nutzertext.
      // Wird in Indexreihenfolge nacheinander ersetzt, kann der erste Wert
      // den zweiten Platzhalter mitbringen, und der zweite Durchgang
      // ueberschreibt ihn. Aus zwei verschiedenen Werten wird derselbe.
      expect(const Phrase('{0} — {1}', ['{1}', 'Zahnarzt']).text,
          '{1} — Zahnarzt');
    });

    test('ein zweistelliger Platzhalter wird nicht vom einstelligen zerteilt',
        () {
      final args = List<Object?>.generate(11, (i) => i);
      expect(Phrase('{10}', args).text, '10');
      expect(Phrase('{1}/{10}', args).text, '1/10');
    });

    test('unbekannte Indizes bleiben stehen, statt den Satz zu verschieben',
        () {
      expect(const Phrase('{3}', ['a']).text, '{3}');
    });
  });

  group('Gleichheit', () {
    test('gleicher Quelltext und gleiche Werte sind dasselbe', () {
      expect(const Phrase('{0} min', [12]), const Phrase('{0} min', [12]));
      expect(const Phrase('{0} min', [12]).hashCode,
          const Phrase('{0} min', [12]).hashCode);
    });

    test('andere Werte sind eine andere Phrase', () {
      expect(const Phrase('{0} min', [12]) == const Phrase('{0} min', [13]),
          isFalse);
    });

    test('andere Anzahl Werte ist eine andere Phrase', () {
      expect(const Phrase('{0}', [1]) == const Phrase('{0}', [1, 2]), isFalse);
    });

    test('anderer Quelltext ist eine andere Phrase', () {
      // Sonst waere die englische Fassung „dieselbe" wie die deutsche.
      expect(const Phrase('{0} min', [12]) == const Phrase('{0} Min.', [12]),
          isFalse);
    });

    test('toString liefert den fertigen Satz, nicht den Quelltext', () {
      expect(const Phrase('{0} min ueber der Zeit', [37]).toString(),
          '37 min ueber der Zeit');
    });
  });

  test('Determinismus: gleicher Quelltext, gleiche Werte, gleicher Satz', () {
    const p = Phrase('{0} min : {1} min ({2})', [12, 40, '0.30']);
    expect(p.text, p.text);
    expect(p.text, const Phrase('{0} min : {1} min ({2})', [12, 40, '0.30']).text);
  });
}
