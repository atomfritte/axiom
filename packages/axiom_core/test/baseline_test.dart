import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

void main() {
  const tracker = BaselineTracker();
  final now = DateTime(2026, 8, 20, 12);

  BaselineProgress evaluate({
    DateTime? startedAt,
    int checkins = 0,
    int nights = 0,
    bool calibrated = false,
  }) =>
      tracker.evaluate(
        startedAt: startedAt,
        now: now,
        checkins: checkins,
        sleepNights: nights,
        calibrated: calibrated,
      );

  group('Bereitschaft haengt an Daten, nicht nur an Zeit', () {
    test('14 Tage allein reichen nicht', () {
      final progress = evaluate(
        startedAt: now.subtract(const Duration(days: 20)),
        checkins: 5,
        nights: 2,
      );
      // Vierzehn Tage mit fuenf Check-ins wuerden die Gewichte auf Rauschen
      // eichen — schlechter als eine ehrliche Schaetzung (R3).
      expect(progress.status, BaselineStatus.collecting);
      expect(progress.open, hasLength(2));
    });

    test('genug Messpunkte, aber zu frueh', () {
      final progress = evaluate(
        startedAt: now.subtract(const Duration(days: 3)),
        checkins: 30,
        nights: 10,
      );
      expect(progress.status, BaselineStatus.collecting);
      expect(progress.open.single.label, 'Tage');
    });

    test('alle drei erfuellt -> bereit', () {
      final progress = evaluate(
        startedAt: now.subtract(const Duration(days: 15)),
        checkins: 34,
        nights: 12,
      );
      expect(progress.status, BaselineStatus.ready);
      expect(progress.isReady, isTrue);
      expect(progress.open, isEmpty);
    });

    test('nicht gestartet bleibt unterscheidbar von laufend', () {
      expect(evaluate().status, BaselineStatus.notStarted);
    });

    test('nach der Eichung ist die Phase abgeschlossen', () {
      final progress = evaluate(
        startedAt: now.subtract(const Duration(days: 40)),
        checkins: 100,
        nights: 40,
        calibrated: true,
      );
      expect(progress.status, BaselineStatus.calibrated);
      expect(progress.criteria, isEmpty);
    });
  });

  group('Fortschritt ist ablesbar', () {
    test('jede Bedingung nennt Stand und Ziel', () {
      final progress = evaluate(
        startedAt: now.subtract(const Duration(days: 7)),
        checkins: 12,
        nights: 4,
      );
      expect(progress.criteria.map((c) => c.label),
          ['Tage', 'Messpunkte', 'Nächte']);
      for (final c in progress.criteria) {
        expect(c.required, greaterThan(0));
        expect(c.progress, inInclusiveRange(0, 1));
      }
    });

    test('Tage werden nicht ueber das Ziel hinaus gezaehlt', () {
      final progress = evaluate(
        startedAt: now.subtract(const Duration(days: 60)),
        checkins: 5,
      );
      final tage = progress.criteria.first;
      expect(tage.current, kBaselineDays);
      expect(tage.progress, 1.0);
    });

    test('die Zusammenfassung benennt konkret, was fehlt', () {
      final progress = evaluate(
        startedAt: now.subtract(const Duration(days: 20)),
        checkins: 8,
        nights: 9,
      );
      expect(progress.summary, contains('Check-ins'));
      expect(progress.summary, isNot(contains('Schlafeintr')));
    });

    test('bereit wird als Aufforderung formuliert, nicht als Lob', () {
      final progress = evaluate(
        startedAt: now.subtract(const Duration(days: 15)),
        checkins: 25,
        nights: 8,
      );
      expect(progress.summary, contains('geeicht werden'));
      expect(progress.summary, isNot(contains('!')));
    });
  });

  test('Determinismus', () {
    final a = evaluate(
        startedAt: now.subtract(const Duration(days: 9)), checkins: 15);
    final b = evaluate(
        startedAt: now.subtract(const Duration(days: 9)), checkins: 15);
    expect(a.status, b.status);
    expect(a.summary, b.summary);
  });
}
