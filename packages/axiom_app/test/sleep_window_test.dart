/// Aus zwei Uhrzeiten wird eine Nacht.
///
/// Der gemeldete Fehler: „Wenn die Schlafdauer beim morgendlichen Check-in von
/// Hand eingetragen wird, sind 24 Stunden zu viel gezählt." Die Ursache war
/// nicht die Rechnung, sondern das Datum — `_TimeButton` behielt Jahr, Monat
/// und Tag des Vorschlags (gestern 23:30) und änderte nur Stunde und Minute.
/// Wer 00:30 eintrug, bekam damit *gestern* 00:30 und gegen das Aufwachen
/// heute 07:00 eine Nacht von 30,5 Stunden.
///
/// Sichtbar war das nur an der Stundenzahl im Blatt. Die Schlafschuld selbst
/// fiel nicht auf: `clamp(0, 600)` zog das negative Ergebnis auf null, also
/// stand dort „keine Schuld" — ein stumm falscher Wert im stärksten
/// Einzelfaktor der Kapazitätsformel.
library;

import 'package:axiom_app/state/runtime.dart';
import 'package:axiom_core/axiom_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  group('Zwei Uhrzeiten ergeben genau eine Nacht', () {
    test('vor Mitternacht ins Bett — unverändert', () {
      final w = AxiomRuntime.normaliseSleepWindow(
        DateTime(2026, 8, 5, 23, 30),
        DateTime(2026, 8, 6, 7),
      );
      expect(w.wakeAt.difference(w.bedAt), const Duration(hours: 7, minutes: 30));
    });

    test('nach Mitternacht ins Bett — der gemeldete Fall', () {
      // Genau die Eingabe aus der Meldung: Die Maske schlägt „gestern 23:30"
      // vor, der Nutzer stellt auf 00:30. Ohne die Ableitung stünden hier
      // 30,5 Stunden — 24 zu viel.
      final w = AxiomRuntime.normaliseSleepWindow(
        DateTime(2026, 8, 5, 0, 30),
        DateTime(2026, 8, 6, 7),
      );
      expect(
        w.wakeAt.difference(w.bedAt),
        const Duration(hours: 6, minutes: 30),
        reason: '00:30 bis 07:00 sind sechseinhalb Stunden, nicht dreißig',
      );
      expect(w.bedAt.day, 6, reason: 'Die Nacht gehört zum Aufwachtag');
    });

    test('gleiche Uhrzeit heißt volle vierundzwanzig Stunden', () {
      // Die Kante. Wer beides auf 07:00 stellt, meint nicht „null Schlaf" —
      // null wäre kein Eintrag. Gemeint ist der Tag davor.
      final w = AxiomRuntime.normaliseSleepWindow(
        DateTime(2026, 8, 6, 7),
        DateTime(2026, 8, 6, 7),
      );
      expect(w.wakeAt.difference(w.bedAt), const Duration(hours: 24));
    });

    test('das Datum des Zubettgehens spielt keine Rolle', () {
      // Aus der Maske kommen zwei Uhrzeiten. Welcher Tag am Zubettgehen
      // steht, ist ein Rest des Vorschlags und keine Angabe des Nutzers —
      // deshalb wird er verworfen. Drei verschiedene Tage, dieselbe Nacht.
      const nacht = Duration(hours: 8);
      for (final tag in [1, 5, 9]) {
        final w = AxiomRuntime.normaliseSleepWindow(
          DateTime(2026, 8, tag, 23),
          DateTime(2026, 8, 6, 7),
        );
        expect(w.wakeAt.difference(w.bedAt), nacht, reason: 'Tag $tag');
      }
    });
  });

  group('Was in der Datenbank landet', () {
    late TestHarness h;

    setUp(() => h = TestHarness.create());
    tearDown(() => h.dispose());

    test('die gespeicherte Nacht ist die gemeinte', () async {
      await h.runtime.logSleep(
        bedAt: DateTime(2026, 8, 2, 0, 30),
        wakeAt: DateTime(2026, 8, 3, 7),
        quality: 3,
      );

      final event = (await h.store.query(types: {EventType.sleepWindow})).single;
      final bed = DateTime.parse(event.payload['bed_at']! as String).toLocal();
      final wake = DateTime.parse(event.payload['wake_at']! as String).toLocal();

      expect(wake.difference(bed), const Duration(hours: 6, minutes: 30));
      // Und die Schuld ist die, die sich daraus ergibt: 7 h Soll minus
      // 6,5 h Schlaf.
      expect(event.payload['est_debt_min'], 30);
    });

    test('eine kurze Nacht nach Mitternacht meldet echte Schuld', () async {
      // Der eigentliche Schaden des Fehlers: Aus 30,5 Stunden wurde eine
      // negative Schuld, und `clamp` machte daraus null. Wer um halb drei
      // ins Bett ging, bekam „keine Schlafschuld" angezeigt.
      await h.runtime.logSleep(
        bedAt: DateTime(2026, 8, 2, 2, 30),
        wakeAt: DateTime(2026, 8, 3, 7),
        quality: 2,
      );

      final event = (await h.store.query(types: {EventType.sleepWindow})).single;
      expect(event.payload['est_debt_min'], 150,
          reason: '4,5 Stunden Schlaf sind 2,5 Stunden unter dem Soll');
    });
  });
}
