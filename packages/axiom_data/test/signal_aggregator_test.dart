/// Prueft die Schicht VOR der Formel: was gemessen wird, bevor der
/// StateDeriver damit rechnet.
///
/// Diese Datei gab es nicht. 193 Zeilen, aus denen jeder Wert des
/// Zustandsvektors und jede Konfidenz entsteht, waren ungeprueft — die
/// App-Tests fuehren den Code aus, sehen aber kein Ergebnis an. Geprueft wird
/// hier deshalb Wirkung, nicht Signatur: Was passiert mit der Kapazitaet,
/// wenn jemand ein Nickerchen macht, und was, wenn die Daten alt werden.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
import 'package:test/test.dart';

void main() {
  late FakeClock clock;
  late SqliteEventStore store;
  late SignalAggregator aggregator;

  setUp(() {
    clock = FakeClock(DateTime(2026, 8, 10, 18));
    store = SqliteEventStore.inMemory(clock: clock);
    aggregator = SignalAggregator(store: store, clock: clock);
  });
  tearDown(() => store.close());

  Future<void> append(
    EventType type, {
    Map<String, Object?> payload = const {},
    Duration ago = Duration.zero,
  }) async {
    final at = clock.nowUtc().subtract(ago);
    await store.append(Event(
      id: newUlid(at),
      at: at,
      type: type,
      source: EventSource.user,
      payload: payload,
    ));
  }

  /// Ein Schlaffenster, wie es Health Connect und die Handeingabe schreiben.
  Future<void> sleepWindow(DateTime bedAt, DateTime wakeAt) => append(
        EventType.sleepWindow,
        ago: clock.nowUtc().difference(wakeAt.toUtc()),
        payload: {
          'bed_at': bedAt.toUtc().toIso8601String(),
          'wake_at': wakeAt.toUtc().toIso8601String(),
          'est_debt_min':
              (7 * 60 - wakeAt.difference(bedAt).inMinutes).clamp(0, 600),
        },
      );

  /// Sieben volle Naechte à 7 h, endend am Morgen des Auswertungstags.
  Future<void> perfectWeek() async {
    for (var i = 0; i < 7; i++) {
      final wake = DateTime(2026, 8, 10 - i, 7);
      await sleepWindow(wake.subtract(const Duration(hours: 7)), wake);
    }
  }

  group('Schlafschuld', () {
    test('eine perfekte Woche ergibt keine Schuld', () async {
      await perfectWeek();
      expect((await aggregator.aggregate()).sleepDebtNorm, 0);
    });

    test('ein Nickerchen erzeugt keine Schlafschuld', () async {
      // Der belegte Fall: sieben volle Naechte plus ein halbstuendiger
      // Mittagsschlaf. Health Connect legt den als eigenen Datensatz ab.
      // Vorher wurde er als eigene Nacht gegen 7 h Soll gerechnet — 390
      // Minuten Schuld, Schlafschuld 46, Kapazitaet 14 Punkte tiefer.
      await perfectWeek();
      await sleepWindow(
        DateTime(2026, 8, 10, 13),
        DateTime(2026, 8, 10, 13, 30),
      );

      expect((await aggregator.aggregate()).sleepDebtNorm, 0);
    });

    test('ein Nickerchen verkuerzt die Schuld einer kurzen Nacht', () async {
      // 5 h Nacht -> 120 min Schuld. Ein Schlaf von 60 min am Nachmittag
      // gehoert zum selben Tag und senkt sie auf 60.
      await sleepWindow(DateTime(2026, 8, 10, 2), DateTime(2026, 8, 10, 7));
      final withoutNap = (await aggregator.aggregate()).sleepDebtNorm;

      await sleepWindow(
        DateTime(2026, 8, 10, 14),
        DateTime(2026, 8, 10, 15),
      );
      final withNap = (await aggregator.aggregate()).sleepDebtNorm;

      expect(withoutNap, closeTo(120 / 7 / 120 * 100, 0.01));
      expect(withNap, closeTo(60 / 7 / 120 * 100, 0.01));
    });

    test('dieselbe Nacht aus zwei Quellen zaehlt einmal', () async {
      // Uhr und Herstellerapp melden dieselbe kurze Nacht leicht versetzt.
      await sleepWindow(DateTime(2026, 8, 10, 2), DateTime(2026, 8, 10, 7));
      await sleepWindow(
        DateTime(2026, 8, 10, 2, 5),
        DateTime(2026, 8, 10, 7, 5),
      );

      final debt = (await aggregator.aggregate()).sleepDebtNorm;
      // Vereinigt sind das 02:00 bis 07:05, also 305 min Schlaf und 115 min
      // Schuld. Vorher wurden beide Meldungen addiert: 235 min Schuld.
      expect(debt, closeTo(115 / 7 / 120 * 100, 0.01));
      expect(debt, lessThan(235 / 7 / 120 * 100));
    });

    test('eine kurze Nacht schlaegt in der Kapazitaet durch', () async {
      await sleepWindow(DateTime(2026, 8, 10, 4), DateTime(2026, 8, 10, 7));
      final debt = (await aggregator.aggregate()).sleepDebtNorm;
      expect(debt, greaterThan(0));
    });

    test('ohne verwertbare Zeiten bleibt der gemeldete Schaetzwert', () async {
      // Aeltere oder importierte Fenster ohne bed_at/wake_at duerfen nicht
      // stumm unter den Tisch fallen.
      await append(
        EventType.sleepWindow,
        payload: {'est_debt_min': 120},
        ago: const Duration(hours: 11),
      );
      final debt = (await aggregator.aggregate()).sleepDebtNorm;
      expect(debt, closeTo(120 / 7 / 120 * 100, 0.01));
    });

    test('ohne Schlafdaten wird keine Schuld erfunden', () async {
      expect((await aggregator.aggregate()).sleepDebtNorm, 0);
    });
  });

  group('Sozialer Rueckzug', () {
    test('ohne Messung traegt der Term nichts bei', () async {
      // `withdrawal` erhebt kein Screen. Vorher stand hier der Rueckfallwert
      // 1.5, also konstant 12,5 — und in der Herleitung von load_index
      // dauerhaft „Sozialer Rückzug +1.3", als waere er gemessen (G2).
      await append(EventType.checkin, payload: {'energy': 3, 'mood': 3});
      expect((await aggregator.aggregate()).socialWithdrawal, 0);
    });

    test('mit Messung rechnet der Term mit', () async {
      await append(EventType.checkin, payload: {'withdrawal': 5});
      expect((await aggregator.aggregate()).socialWithdrawal, 100);
    });
  });

  group('Konfidenz', () {
    test('ohne Daten wird nicht geraten', () async {
      final signals = await aggregator.aggregate();
      expect(signals.confidence['capacity'], 0);
      expect(signals.confidence['load_index'], 0);
      expect(signals.confidence['regulation'], 0);
    });

    test('ein frischer Check-in zaehlt voll', () async {
      await append(EventType.checkin, payload: {'energy': 3});
      expect((await aggregator.aggregate()).confidence['load_index'], 1.0);
    });

    test('genau am Frischefenster noch voll', () async {
      await append(EventType.checkin,
          payload: {'energy': 3}, ago: kCheckinFreshness);
      expect((await aggregator.aggregate()).confidence['load_index'], 1.0);
    });

    test('faellt mit dem Alter und erreicht null', () async {
      await append(EventType.checkin,
          payload: {'energy': 3}, ago: const Duration(hours: 16));
      final middle = (await aggregator.aggregate()).confidence['load_index']!;
      expect(middle, closeTo(2 / 3, 0.01));

      clock.advance(const Duration(hours: 16));
      final late = (await aggregator.aggregate()).confidence['load_index']!;
      expect(late, 0.0);
    });

    test('Schlafkonfidenz haengt am juengsten Schlaffenster', () async {
      await sleepWindow(
        DateTime(2026, 8, 10, 0),
        DateTime(2026, 8, 10, 7),
      );
      expect((await aggregator.aggregate()).confidence['sleep_debt'], 1.0);

      clock.advance(const Duration(days: 5));
      expect((await aggregator.aggregate()).confidence['sleep_debt'], 0.0);
    });
  });

  group('Reizbarkeit', () {
    test('unter drei Stimmungswerten wird nichts behauptet', () async {
      await append(EventType.checkin, payload: {'mood': 1});
      await append(EventType.checkin,
          payload: {'mood': 5}, ago: const Duration(hours: 2));
      expect((await aggregator.aggregate()).irritabilityTrend, 0);
    });

    test('ab drei Werten zaehlt die Schwankung, nicht das Niveau', () async {
      for (var i = 0; i < 3; i++) {
        await append(EventType.checkin,
            payload: {'mood': 4}, ago: Duration(hours: i * 2));
      }
      expect((await aggregator.aggregate()).irritabilityTrend, 0);

      await append(EventType.checkin,
          payload: {'mood': 1}, ago: const Duration(hours: 8));
      expect((await aggregator.aggregate()).irritabilityTrend, greaterThan(0));
    });
  });

  group('Niedrigreiz-Zeit', () {
    test('zaehlt ab dem Aufwachen, nicht ab Mitternacht', () async {
      await sleepWindow(
        DateTime(2026, 8, 10, 0),
        DateTime(2026, 8, 10, 7),
      );
      // 07:00 bis 18:00 sind elf Stunden.
      expect(
        (await aggregator.aggregate()).minutesInLowStimulus,
        11 * 60,
      );
    });

    test('endet mit dem letzten Reiz-Slot', () async {
      await sleepWindow(
        DateTime(2026, 8, 10, 0),
        DateTime(2026, 8, 10, 7),
      );
      await append(EventType.sensationSlot,
          payload: {'intensity': 3, 'duration_min': 30},
          ago: const Duration(hours: 2));
      expect((await aggregator.aggregate()).minutesInLowStimulus, 120);
    });
  });
}
