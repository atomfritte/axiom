/// Health Connect ist die einzige Datenquelle, die AXIOM nicht selbst
/// erzeugt — und war bis hierher ungeprueft: `import` laeuft nur auf einem
/// Geraet, und die Tests kamen nur bis zu den Konstanten.
///
/// Geprueft wird deshalb [HealthSync.plan]: die Entscheidung, was aus einem
/// Datensatz wird, getrennt vom Schreiben.
library;

import 'package:axiom_app/platform/health_sync.dart';
import 'package:axiom_core/axiom_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Ein Datensatz, wie ihn HealthBridge.kt liefert.
  Map<String, Object?> sleep(
    String id,
    DateTime from,
    DateTime to,
  ) =>
      {
        'kind': 'sleep',
        'sourceId': id,
        'startMillis': from.millisecondsSinceEpoch,
        'endMillis': to.millisecondsSinceEpoch,
      };

  Map<String, Object?> steps(String id, DateTime day, int count) => {
        'kind': 'steps',
        'sourceId': id,
        'startMillis': day.millisecondsSinceEpoch,
        'endMillis': day.add(const Duration(days: 1)).millisecondsSinceEpoch,
        'count': count,
      };

  final night = sleep(
    'uhr-1',
    DateTime.utc(2026, 8, 10, 23),
    DateTime.utc(2026, 8, 11, 6),
  );

  group('Was uebernommen wird', () {
    test('eine Nacht wird zum Schlaffenster', () {
      final planned = HealthSync.plan([night]);

      expect(planned.entries, hasLength(1));
      final entry = planned.entries.single;
      expect(entry.type, EventType.sleepWindow);
      expect(entry.at, DateTime.utc(2026, 8, 11, 6));
      expect(entry.payload['bed_at'], '2026-08-10T23:00:00.000Z');
      expect(entry.payload['wake_at'], '2026-08-11T06:00:00.000Z');
      expect(entry.payload['duration_min'], 7 * 60);
      expect(entry.payload['source_id'], 'uhr-1');
    });

    test('kein erfundener Schuldwert je Aufzeichnung', () {
      // Health Connect legt jede Schlafphase einzeln ab. Vorher rechnete
      // diese Stelle jeden Datensatz gegen sieben Stunden Soll und schrieb
      // die Differenz als `est_debt_min` mit — ein halbstuendiges
      // Nickerchen trug damit 390 Minuten Schlafschuld bei, obwohl es
      // Schlaf ist. Geschrieben werden nur noch Messwerte; die Schuld
      // entsteht dort, wo alle Naechte zusammen sichtbar sind.
      final nap = sleep(
        'uhr-2',
        DateTime.utc(2026, 8, 11, 13),
        DateTime.utc(2026, 8, 11, 13, 30),
      );
      for (final entry in HealthSync.plan([night, nap]).entries) {
        expect(entry.payload.containsKey('est_debt_min'), isFalse,
            reason: 'Schuld wird abgeleitet, nicht importiert');
      }
    });

    test('Schritte werden zur Tagessumme', () {
      final planned = HealthSync.plan([steps('fit-1', DateTime.utc(2026, 8, 10), 8123)]);

      expect(planned.entries, hasLength(1));
      expect(planned.entries.single.type, EventType.healthSample);
      expect(planned.entries.single.payload['metric'], 'steps');
      expect(planned.entries.single.payload['value'], 8123);
    });

    test('ein Nickerchen bleibt ein eigener Datensatz', () {
      // Es ueberlappt die Nacht nicht — verschluckt werden darf es nicht,
      // sonst fehlt der Schlaf in der Tagessumme.
      final nap = sleep(
        'uhr-2',
        DateTime.utc(2026, 8, 11, 13),
        DateTime.utc(2026, 8, 11, 13, 30),
      );
      expect(HealthSync.plan([night, nap]).entries, hasLength(2));
    });
  });

  group('Nichts zweimal', () {
    test('bekannte Quell-ID wird uebersprungen', () {
      final planned = HealthSync.plan([night], knownSourceIds: {'uhr-1'});
      expect(planned.entries, isEmpty);
      expect(planned.skipped, 1);
    });

    test('dieselbe Nacht aus einer zweiten App zaehlt einmal', () {
      // Uhr und Herstellerapp haben verschiedene Quell-IDs. Ueber die ID
      // allein war die Dublette nicht zu erkennen: Die Nacht landete zweimal
      // im append-only-Strom, verdoppelte die Schlafschuld und zaehlte in
      // der Baseline als zwei Naechte.
      final sameNight = sleep(
        'samsung-1',
        DateTime.utc(2026, 8, 10, 23, 5),
        DateTime.utc(2026, 8, 11, 6, 10),
      );

      final planned = HealthSync.plan([night, sameNight]);
      expect(planned.entries, hasLength(1));
      expect(planned.skipped, 1);
    });

    test('eine bereits erfasste Nacht wird nicht erneut importiert', () {
      final planned = HealthSync.plan(
        [night],
        knownSleep: [
          (
            from: DateTime.utc(2026, 8, 10, 22, 30),
            to: DateTime.utc(2026, 8, 11, 5, 45),
          ),
        ],
      );
      expect(planned.entries, isEmpty);
      expect(planned.skipped, 1);
    });

    test('eine andere Nacht bleibt eine andere Nacht', () {
      final planned = HealthSync.plan(
        [night],
        knownSleep: [
          (
            from: DateTime.utc(2026, 8, 9, 23),
            to: DateTime.utc(2026, 8, 10, 6),
          ),
        ],
      );
      expect(planned.entries, hasLength(1));
      expect(planned.skipped, 0);
    });
  });

  group('Unbrauchbare Datensaetze', () {
    test('ohne Quell-ID passiert nichts', () {
      expect(HealthSync.plan([
        {
          'kind': 'sleep',
          'startMillis': 0,
          'endMillis': 1000,
        }
      ]).entries, isEmpty);
    });

    test('ohne Zeiten passiert nichts', () {
      expect(
        HealthSync.plan([
          {'kind': 'sleep', 'sourceId': 'x'}
        ]).entries,
        isEmpty,
      );
    });

    test('ein Fenster ohne Dauer wird nicht uebernommen', () {
      final zero = DateTime.utc(2026, 8, 11, 6);
      expect(HealthSync.plan([sleep('x', zero, zero)]).entries, isEmpty);
    });

    test('eine unbekannte Art wird stillschweigend liegengelassen', () {
      // Health Connect kann jederzeit eine Aufzeichnungsart dazubekommen.
      // Sie darf hier nichts erzeugen — ein Ereignis ohne Bedeutung liesse
      // sich aus einem append-only-Strom nicht mehr entfernen.
      final planned = HealthSync.plan([
        {
          'kind': 'heart_rate',
          'sourceId': 'uhr-9',
          'startMillis': 0,
          'endMillis': 1000,
        }
      ]);
      expect(planned.entries, isEmpty);
      expect(planned.skipped, 0,
          reason: 'uebersprungen heisst „schon da", nicht „kenne ich nicht"');
    });

    test('Schritte ohne Zahl sind keine Schritte', () {
      expect(
        HealthSync.plan([
          {
            'kind': 'steps',
            'sourceId': 'fit-9',
            'startMillis': 0,
            'endMillis': 1000,
          }
        ]).entries,
        isEmpty,
      );
    });

    test('derselbe Datensatz zweimal im selben Schwung zaehlt einmal', () {
      // Der Aufrufer bekommt eine Liste vom Geraet, keine Menge. Ohne den
      // Merker innerhalb des Laufs stuende dieselbe Nacht zweimal im Strom —
      // und der zweite Import haette sie beide als bekannt uebersprungen.
      final planned = HealthSync.plan([night, night]);
      expect(planned.entries, hasLength(1));
      expect(planned.skipped, 1);
    });
  });

  group('Die Raender', () {
    test('zwei Fenster, die aneinander stossen, sind zwei Fenster', () {
      // Wer um 6:00 aufwacht und sich um 6:00 wieder hinlegt, hat zwei
      // Aufzeichnungen. Ein Vergleich mit `<=` statt `<` machte daraus eine
      // Dublette — und die zweite Nacht verschwaende.
      final planned = HealthSync.plan(
        [sleep('uhr-3', DateTime.utc(2026, 8, 11, 6), DateTime.utc(2026, 8, 11, 8))],
        knownSleep: [
          (from: DateTime.utc(2026, 8, 10, 23), to: DateTime.utc(2026, 8, 11, 6)),
        ],
      );
      expect(planned.entries, hasLength(1));
      expect(planned.skipped, 0);
    });

    test('was der Aufrufer mitgibt, kommt unveraendert zurueck', () {
      // `plan` bekommt den bekannten Stand aus dem Ereignisstrom. Schriebe
      // es hinein, waere der zweite Aufruf mit derselben Liste ein anderer —
      // und `import` ruft sie fuer jeden Lauf neu ab.
      const knownIds = <String>{'fit-1'};
      const knownSleep = <SleepWindow>[];

      HealthSync.plan([night], knownSourceIds: knownIds, knownSleep: knownSleep);

      expect(knownIds, {'fit-1'});
      expect(knownSleep, isEmpty);
    });
  });

  group('Was im Ereignisstrom landet', () {
    // Diese Felder liest der SignalAggregator. Sie umzubenennen ist kein
    // Fehler, den irgendetwas bemerkt: Der Import laeuft weiter, die Kapazitaet
    // rechnet weiter — nur ohne Schlaf. Deshalb stehen sie hier vollstaendig.

    test('ein Schlaffenster traegt genau diese Felder', () {
      expect(
        HealthSync.plan([night]).entries.single.payload.keys.toSet(),
        {'bed_at', 'wake_at', 'duration_min', 'source_id', 'via'},
      );
    });

    test('eine Tagessumme traegt genau diese Felder', () {
      final planned =
          HealthSync.plan([steps('fit-1', DateTime.utc(2026, 8, 10), 8123)]);
      expect(
        planned.entries.single.payload.keys.toSet(),
        {'metric', 'value', 'from', 'to', 'source_id', 'via'},
      );
      // Woher der Wert kommt, muss am Ereignis stehen: Ein von Hand
      // eingetragener und ein importierter Schlaf sind sonst nicht mehr zu
      // unterscheiden.
      expect(planned.entries.single.payload['via'], 'health_connect');
    });
  });
}
