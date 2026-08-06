/// Baseline-Bereitschaft an den Raendern.
///
/// Die Kalibrierung eicht die Formelgewichte auf echte Daten. Sagt dieses
/// Modul zu frueh „bereit", werden die Gewichte auf Rauschen geeicht — und
/// ein auf Rauschen geeichtes System ist schlechter als ein ehrlich
/// geschaetztes (R3). Der vorhandene Test prueft komfortable Abstaende zur
/// Schwelle; hier steht jede Schwelle auf den Punkt, dazu die Faelle mit zu
/// wenig, mit genau genug und mit einer Zeit, die nicht stimmt.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

void main() {
  const tracker = BaselineTracker();
  final now = DateTime(2026, 8, 20, 12);

  BaselineProgress evaluate({
    Duration? seit,
    int checkins = 0,
    int nights = 0,
    bool calibrated = false,
  }) =>
      tracker.evaluate(
        startedAt: seit == null ? null : now.subtract(seit),
        now: now,
        checkins: checkins,
        sleepNights: nights,
        calibrated: calibrated,
      );

  /// Genau die Mindestwerte, damit sich einzelne Bedingungen gezielt
  /// unterschreiten lassen.
  BaselineProgress gerade({
    int tage = kBaselineDays,
    int checkins = kBaselineCheckins,
    int nights = kBaselineSleepNights,
  }) =>
      evaluate(
        // Tag 1 ist der Starttag; kBaselineDays sind erreicht, wenn
        // kBaselineDays - 1 volle Tage vergangen sind.
        seit: Duration(days: tage - 1),
        checkins: checkins,
        nights: nights,
      );

  group('Genau an der Schwelle', () {
    test('exakt die Mindestwerte genuegen', () {
      final progress = gerade();
      expect(progress.status, BaselineStatus.ready);
      expect(progress.day, kBaselineDays);
      expect(progress.open, isEmpty);
      for (final c in progress.criteria) {
        expect(c.isMet, isTrue, reason: c.label);
        expect(c.missing, 0, reason: c.label);
        expect(c.progress, 1.0, reason: c.label);
      }
    });

    test('ein Tag zu frueh reicht nicht', () {
      final progress = gerade(tage: kBaselineDays - 1);
      expect(progress.status, BaselineStatus.collecting);
      expect(progress.open.single.label, 'Tage');
      expect(progress.open.single.missing, 1);
    });

    test('ein Check-in zu wenig reicht nicht', () {
      final progress = gerade(checkins: kBaselineCheckins - 1);
      expect(progress.status, BaselineStatus.collecting);
      expect(progress.open.single.label, 'Messpunkte');
      expect(progress.open.single.missing, 1);
    });

    test('eine Nacht zu wenig reicht nicht', () {
      final progress = gerade(nights: kBaselineSleepNights - 1);
      expect(progress.status, BaselineStatus.collecting);
      expect(progress.open.single.label, 'Nächte');
      expect(progress.open.single.missing, 1);
    });

    test('viel Zeit ersetzt keine Daten', () {
      // Der eigentliche Punkt des Moduls: „sind 14 Tage um?" ist nicht die
      // Frage.
      final progress = evaluate(seit: const Duration(days: 400), checkins: 3);
      expect(progress.status, BaselineStatus.collecting);
      expect(progress.open.map((c) => c.label), ['Messpunkte', 'Nächte']);
    });

    test('viele Daten ersetzen keine Zeit', () {
      // Und umgekehrt: Zwanzig Check-ins an zwei Tagen erfassen keinen
      // Wochenrhythmus.
      final progress = evaluate(
        seit: const Duration(days: 1),
        checkins: 200,
        nights: 40,
      );
      expect(progress.status, BaselineStatus.collecting);
      expect(progress.open.single.label, 'Tage');
    });
  });

  group('Der Tag wird gezaehlt, nicht geschaetzt', () {
    test('der Starttag ist Tag 1, nicht Tag 0', () {
      expect(evaluate(seit: Duration.zero).day, 1);
      expect(evaluate(seit: const Duration(hours: 23)).day, 1);
      expect(evaluate(seit: const Duration(days: 1)).day, 2);
    });

    test('die Tage werden fuer die Anzeige gedeckelt, der Tag selbst nicht',
        () {
      // Der Balken soll bei 100 % stehen bleiben; die Zahl darf trotzdem
      // sagen, wie lange es tatsaechlich laeuft.
      final progress = evaluate(seit: const Duration(days: 60), checkins: 5);
      expect(progress.criteria.first.current, kBaselineDays);
      expect(progress.criteria.first.progress, 1.0);
      expect(progress.day, 61);
    });

    test('ein Startzeitpunkt in der Zukunft kippt nichts um', () {
      // Uhr umgestellt oder Import aus einem anderen Geraet. Der Fortschritt
      // darf dann nicht negativ werden.
      final progress = tracker.evaluate(
        startedAt: now.add(const Duration(days: 5)),
        now: now,
        checkins: 0,
        sleepNights: 0,
        calibrated: false,
      );
      expect(progress.status, BaselineStatus.collecting);
      for (final c in progress.criteria) {
        expect(c.current, greaterThanOrEqualTo(0), reason: c.label);
        expect(c.progress, inInclusiveRange(0, 1), reason: c.label);
        expect(c.missing, lessThanOrEqualTo(c.required), reason: c.label);
      }
    });
  });

  group('Die vier Zustaende bleiben unterscheidbar', () {
    test('nicht gestartet ist nicht dasselbe wie „sammelt ohne Daten"', () {
      final nichtGestartet = evaluate();
      final gestartet = evaluate(seit: Duration.zero);
      expect(nichtGestartet.status, BaselineStatus.notStarted);
      expect(nichtGestartet.day, isNull);
      expect(nichtGestartet.criteria, isEmpty);
      expect(nichtGestartet.isReady, isFalse);
      expect(gestartet.status, BaselineStatus.collecting);
      expect(gestartet.day, 1);
    });

    test('geeicht schlaegt alles andere — auch fehlende Daten', () {
      // `calibrated` kommt aus `weights.yaml`. Steht es dort, ist die Phase
      // vorbei, egal was die Zaehler sagen.
      final progress = evaluate(checkins: 0, nights: 0, calibrated: true);
      expect(progress.status, BaselineStatus.calibrated);
      expect(progress.criteria, isEmpty);
      expect(progress.open, isEmpty);
      expect(progress.isReady, isFalse);
      expect(progress.day, isNull);
    });

    test('geeicht gilt auch ohne Startzeitpunkt', () {
      expect(evaluate(calibrated: true).status, BaselineStatus.calibrated);
    });
  });

  group('Die Zusammenfassung beschreibt, ohne zu draengen', () {
    test('nennt genau die offenen Bedingungen und keine erledigten', () {
      final progress = gerade(checkins: 12, nights: 3);
      expect(progress.summary, contains('Check-ins'));
      expect(progress.summary, contains('Schlafeinträge'));
      expect(progress.summary, isNot(contains('Tage')));
    });

    test('nennt die fehlende Anzahl, nicht nur die Bedingung', () {
      // „Es fehlt noch etwas" waere keine Auskunft.
      final progress = gerade(checkins: kBaselineCheckins - 6);
      expect(progress.summary, contains('6 Check-ins'));
    });

    test('jeder Zustand hat einen eigenen Satz', () {
      final saetze = <String>{
        evaluate().summary,
        gerade(checkins: 1).summary,
        gerade().summary,
        evaluate(calibrated: true).summary,
      };
      expect(saetze, hasLength(4));
    });

    test('kein Satz enthaelt Schuld, Lob oder Ausrufezeichen (R7)', () {
      final saetze = [
        evaluate().summary,
        gerade(checkins: 1).summary,
        gerade().summary,
        evaluate(calibrated: true).summary,
      ];
      for (final satz in saetze) {
        expect(satz, isNot(contains('!')), reason: satz);
        for (final wort in ['super', 'endlich', 'schon wieder', 'solltest']) {
          expect(satz.toLowerCase(), isNot(contains(wort)), reason: satz);
        }
      }
    });
  });

  group('Fortschritt einer einzelnen Bedingung', () {
    test('waechst linear bis eins und nicht darueber', () {
      const c = BaselineCriterion(label: 'x', current: 10, required: 20);
      expect(c.progress, 0.5);
      expect(c.missing, 10);
      expect(c.isMet, isFalse);

      const voll = BaselineCriterion(label: 'x', current: 40, required: 20);
      expect(voll.progress, 1.0);
      expect(voll.missing, 0);
      expect(voll.isMet, isTrue);
    });

    test('eine Bedingung ohne Ziel gilt als erfuellt, statt durch null zu '
        'teilen', () {
      const c = BaselineCriterion(label: 'x', current: 0, required: 0);
      expect(c.progress, 1);
      expect(c.isMet, isTrue);
      expect(c.missing, 0);
    });

    test('die Schwellen stehen als benannte Konstanten da', () {
      // `tools/bin/calibrate.dart` benutzt dieselben. Zwei Zahlen an zwei
      // Stellen laufen auseinander.
      expect(kBaselineDays, 14);
      expect(kBaselineCheckins, 20);
      expect(kBaselineSleepNights, 7);
    });
  });

  test('Determinismus: gleiche Lage, gleicher Stand und gleicher Satz', () {
    final a = gerade(checkins: 11, nights: 4);
    final b = gerade(checkins: 11, nights: 4);
    expect(a.status, b.status);
    expect(a.day, b.day);
    expect(a.summary, b.summary);
    expect(a.open.map((c) => c.label), b.open.map((c) => c.label));
  });
}
