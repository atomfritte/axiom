/// Der Zustandsvektor selbst — bisher nur nebenbei getestet.
///
/// Sechs Zahlen, eine Stufeneinteilung und ein Namenszugriff. Klingt nach
/// wenig; es ist die Datenstruktur, gegen die **jede** Regel vergleicht. Ein
/// verschobener Schwellenwert oder ein umbenanntes Feld aendert das Verhalten
/// des ganzen Regelwerks, ohne dass eine einzelne Regel sich aendert.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

StateVector _vector({
  int capacity = 60,
  int focusDebt = 20,
  int sensationNeed = 40,
  int loadIndex = 30,
  int regulation = 70,
  int sleepDebt = 15,
  Map<String, double> confidence = const {},
}) =>
    StateVector(
      at: DateTime.utc(2026, 8, 3, 10),
      capacity: capacity,
      focusDebt: focusDebt,
      sensationNeed: sensationNeed,
      loadIndex: loadIndex,
      regulation: regulation,
      sleepDebt: sleepDebt,
      confidence: confidence,
    );

void main() {
  group('Laststufen — die Schwellen auf den Punkt', () {
    test('jede Stufe beginnt genau an ihrer Schwelle', () {
      expect(LoadLevel.fromIndex(0), LoadLevel.l0);
      expect(LoadLevel.fromIndex(54), LoadLevel.l0);
      expect(LoadLevel.fromIndex(55), LoadLevel.l1);
      expect(LoadLevel.fromIndex(69), LoadLevel.l1);
      expect(LoadLevel.fromIndex(70), LoadLevel.l2);
      expect(LoadLevel.fromIndex(84), LoadLevel.l2);
      expect(LoadLevel.fromIndex(85), LoadLevel.l3);
      expect(LoadLevel.fromIndex(100), LoadLevel.l3);
    });

    test('Werte ausserhalb der Skala kippen nicht durch', () {
      // Kann nur aus einer fremden Datei kommen — eine Ausnahme mitten in
      // der Auswertung waere die teuerste Antwort darauf.
      expect(LoadLevel.fromIndex(-10), LoadLevel.l0);
      expect(LoadLevel.fromIndex(999), LoadLevel.l3);
    });

    test('die Einteilung ist monoton', () {
      var vorher = LoadLevel.l0;
      for (var index = 0; index <= 100; index++) {
        final stufe = LoadLevel.fromIndex(index);
        expect(stufe.index, greaterThanOrEqualTo(vorher.index),
            reason: 'bei $index');
        vorher = stufe;
      }
      expect(vorher, LoadLevel.l3);
    });

    test('die hinterlegten Schwellen sind aufsteigend und passen zur '
        'Einteilung', () {
      // Sonst stuende im Systeminspektor eine andere Zahl, als die
      // Einteilung benutzt.
      final schwellen = LoadLevel.values.map((l) => l.threshold).toList();
      expect(schwellen, orderedEquals(List<int>.from(schwellen)..sort()));
      for (final stufe in LoadLevel.values) {
        expect(LoadLevel.fromIndex(stufe.threshold), stufe,
            reason: stufe.name);
      }
    });

    test('der Vektor meldet seine eigene Stufe', () {
      expect(_vector(loadIndex: 90).loadLevel, LoadLevel.l3);
      expect(_vector(loadIndex: 20).loadLevel, LoadLevel.l0);
    });
  });

  group('Zugriff ueber den Namen aus der Regel-DSL', () {
    test('jede der sechs Dimensionen ist erreichbar', () {
      final v = _vector(
        capacity: 61,
        focusDebt: 62,
        sensationNeed: 63,
        loadIndex: 64,
        regulation: 65,
        sleepDebt: 66,
      );
      expect(v.numeric('capacity'), 61);
      expect(v.numeric('focus_debt'), 62);
      expect(v.numeric('sensation_need'), 63);
      expect(v.numeric('load_index'), 64);
      expect(v.numeric('regulation'), 65);
      expect(v.numeric('sleep_debt'), 66);
    });

    test('nur snake_case, nicht der Feldname aus dem Quelltext', () {
      // Sonst gaebe es zwei Schreibweisen fuer dieselbe Variable, und nur
      // eine davon stuende im Editor.
      expect(_vector().numeric('focusDebt'), isNull);
      expect(_vector().numeric('sensationNeed'), isNull);
    });

    test('ein unbekannter Name liefert null — der Aufrufer wirft', () {
      expect(_vector().numeric('gibt_es_nicht'), isNull);
    });
  });

  group('Konfidenz', () {
    test('ohne Eintrag gilt volle Konfidenz', () {
      expect(_vector().confidenceOf('capacity'), 1.0);
    });

    test('ein Eintrag gilt nur fuer seine Dimension', () {
      final v = _vector(confidence: const {'capacity': 0.4});
      expect(v.confidenceOf('capacity'), 0.4);
      expect(v.confidenceOf('load_index'), 1.0);
    });

    test('auch die Null wird als gemessen behandelt, nicht als fehlend', () {
      // 0.0 heisst „gar keine Datengrundlage". Wuerde hier auf 1.0
      // zurueckgefallen, waere der schlechteste Fall der zuversichtlichste.
      expect(_vector(confidence: const {'capacity': 0.0}).confidenceOf('capacity'),
          0.0);
    });
  });

  group('copyWith', () {
    test('aendert genau ein Feld und laesst den Rest stehen', () {
      final vorher = _vector(confidence: const {'capacity': 0.5});
      final nachher = vorher.copyWith(capacity: 12);

      expect(nachher.capacity, 12);
      expect(nachher.at, vorher.at);
      expect(nachher.focusDebt, vorher.focusDebt);
      expect(nachher.sensationNeed, vorher.sensationNeed);
      expect(nachher.loadIndex, vorher.loadIndex);
      expect(nachher.regulation, vorher.regulation);
      expect(nachher.sleepDebt, vorher.sleepDebt);
      expect(nachher.confidence, vorher.confidence);
    });

    test('ohne Angabe bleibt alles wie es war', () {
      final vorher = _vector();
      final nachher = vorher.copyWith();
      expect(nachher.toJson(), vorher.toJson());
    });
  });

  group('toJson', () {
    test('nennt die Dimensionen so, wie die Regel-DSL sie kennt', () {
      // Der Expertenmodus und der Export lesen diese Schluessel. Wichen sie
      // von den Variablennamen ab, muesste man zweimal umdenken.
      final json = _vector().toJson();
      expect(
        json.keys.toSet(),
        {
          'at',
          'capacity',
          'focus_debt',
          'sensation_need',
          'load_index',
          'regulation',
          'sleep_debt',
          'confidence',
        },
      );
      for (final key in json.keys) {
        if (key == 'at' || key == 'confidence') continue;
        expect(_vector().numeric(key), isNotNull, reason: key);
      }
    });

    test('der Zeitstempel steht in UTC', () {
      // Alle Zeitstempel UTC, lokale Zone nur zur Anzeige.
      expect(_vector().toJson()['at'], endsWith('Z'));
    });
  });

  group('clamp100 — das Ende jeder Formel', () {
    test('haelt die Skala ein', () {
      expect(clamp100(-5), 0);
      expect(clamp100(0), 0);
      expect(clamp100(100), 100);
      expect(clamp100(140), 100);
    });

    test('rundet kaufmaennisch, nicht ab', () {
      // Sonst verlaere jede Formel im Mittel einen halben Punkt.
      expect(clamp100(29.4), 29);
      expect(clamp100(29.5), 30);
      expect(clamp100(29.6), 30);
    });

    test('rundet erst und begrenzt dann', () {
      expect(clamp100(99.6), 100);
      expect(clamp100(-0.4), 0);
    });
  });

  test('toString nennt alle sechs Dimensionen und die Stufe', () {
    // Die Zeile landet im Fehlerprotokoll und im Systeminspektor; fehlt
    // dort eine Zahl, sucht man sie im Zweifel stundenlang woanders.
    final text = _vector(loadIndex: 90).toString();
    for (final teil in ['cap=', 'focus=', 'stim=', 'load=', 'reg=', 'sleep=']) {
      expect(text, contains(teil));
    }
    expect(text, contains('l3'));
  });
}
