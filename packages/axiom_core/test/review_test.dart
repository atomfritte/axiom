import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

void main() {
  const engine = ReviewEngine();

  Metric metricOf(List<Metric> all, String id) =>
      all.firstWhere((m) => m.id == id);

  group('Zeitdeckel — Review darf nicht ausufern (D3)', () {
    test('jeder Umfang hat eine harte Obergrenze', () {
      expect(ReviewScope.day.timeCap, const Duration(minutes: 2));
      expect(ReviewScope.week.timeCap, const Duration(minutes: 15));
      expect(ReviewScope.month.timeCap, const Duration(minutes: 30));
      expect(ReviewScope.quarter.timeCap, const Duration(minutes: 60));
    });

    test('Regeländerungen frühestens im Wochen-Review (M12)', () {
      expect(ReviewScope.day.allowsRuleChanges, isFalse);
      expect(ReviewScope.week.allowsRuleChanges, isTrue);
    });

    test('Module aktivieren erst monatlich', () {
      expect(ReviewScope.week.allowsModuleChanges, isFalse);
      expect(ReviewScope.month.allowsModuleChanges, isTrue);
    });
  });

  group('Kennzahlen', () {
    test('liefert alle sechs', () {
      final metrics = engine.metrics(const ReviewInputs());
      expect(metrics.map((m) => m.id), [
        'checkins',
        'load',
        'capture',
        'sensation',
        'impulse',
        'meta',
      ]);
    });

    test('jede Kennzahl nennt ihre Herleitung (G2)', () {
      for (final metric in engine.metrics(const ReviewInputs())) {
        expect(metric.derivation, isNotEmpty, reason: metric.id);
      }
    });

    test('Erfassungsquote unter 80 % blockiert den Ausbau', () {
      final metric = metricOf(
        engine.metrics(const ReviewInputs(checkinRate: 0.5)),
        'checkins',
      );
      expect(metric.needsAttention, isTrue);
      expect(metric.consequence, contains('leichter werden'));
      // Kein Richtungspfeil ohne Vergleichszeitraum — er waere erfunden.
      expect(metric.trend, isNull);
    });

    test('gute Erfassungsquote braucht keine Konsequenz', () {
      final metric = metricOf(
        engine.metrics(const ReviewInputs(checkinRate: 0.95)),
        'checkins',
      );
      expect(metric.consequence, isNull);
      expect(metric.needsAttention, isFalse);
    });

    test('sinkende Last wird als fallende Zahl ausgewiesen', () {
      final metric = metricOf(
        engine.metrics(
            const ReviewInputs(loadIndex: 40, loadIndexBefore: 55)),
        'load',
      );
      // Der Pfeil zeigt die Richtung der Zahl. Dass Fallen hier gut ist,
      // steht in der Kennzahl selbst, nicht im Symbol.
      expect(metric.trend, MetricTrend.down);
      expect(metric.value, contains('-15'));
    });

    test('hohe Last löst eine klare Ansage aus', () {
      final metric = metricOf(
        engine.metrics(const ReviewInputs(loadIndex: 75)),
        'load',
      );
      expect(metric.consequence, contains('nichts Neues'));
    });

    test('erfasst, aber nichts einsortiert — Eingang läuft voll', () {
      final metric = metricOf(
        engine.metrics(const ReviewInputs(captures: 12, tasksCreated: 0)),
        'capture',
      );
      expect(metric.consequence, isNotNull);
    });

    test('Reizdeckung unter 70 % wird benannt', () {
      final metric = metricOf(
        engine.metrics(
            const ReviewInputs(plannedSlots: 2, unplannedSlots: 6)),
        'sensation',
      );
      expect(metric.needsAttention, isTrue);
      expect(metric.consequence, contains('schnellsten'));
    });

    test('ohne Slots keine erfundene Zahl', () {
      final metric = metricOf(
        engine.metrics(const ReviewInputs()),
        'sensation',
      );
      expect(metric.value, 'keine Daten');
      expect(metric.trend, isNull);
    });
  });

  group('K6 — das Abbruchkriterium des Projekts', () {
    test('gutes Verhältnis gilt als Verbesserung', () {
      final metric = metricOf(
        engine.metrics(
            const ReviewInputs(metaMinutes: 40, savedMinutesEstimate: 400)),
        'meta',
      );
      expect(metric.needsAttention, isFalse);
    });

    test('mehr Zeit im System als gespart fordert Rückbau', () {
      final metric = metricOf(
        engine.metrics(
            const ReviewInputs(metaMinutes: 300, savedMinutesEstimate: 100)),
        'meta',
      );
      expect(metric.needsAttention, isTrue);
      expect(metric.consequence, contains('zurückgebaut'));
      expect(metric.consequence, isNot(contains('optimiert werden')));
    });
  });

  group('Regelurteile', () {
    test('schwache Regeln kommen auf die Streichliste', () {
      final verdicts =
          engine.ruleVerdicts(const ReviewInputs(weakRules: ['R-050']));
      expect(verdicts.single.verdict, RuleAction.retire);
      expect(verdicts.single.ruleId, 'R-050');
    });

    test('stumme Regeln: Bedingung zu eng oder überflüssig', () {
      final verdicts =
          engine.ruleVerdicts(const ReviewInputs(silentRules: ['R-070']));
      expect(verdicts.single.verdict, RuleAction.widen);
    });

    test('verdrängte Regeln zeigen einen verborgenen Konflikt', () {
      final verdicts =
          engine.ruleVerdicts(const ReviewInputs(suppressedRules: ['R-090']));
      expect(verdicts.single.verdict, RuleAction.resolveConflict);
    });

    test('ohne Auffälligkeiten keine Urteile', () {
      expect(engine.ruleVerdicts(const ReviewInputs()), isEmpty);
    });

    test('jedes Urteil ist begründet (G2)', () {
      final verdicts = engine.ruleVerdicts(const ReviewInputs(
        weakRules: ['R-001'],
        silentRules: ['R-002'],
        suppressedRules: ['R-003'],
      ));
      expect(verdicts, hasLength(3));
      for (final v in verdicts) {
        expect(v.reason, isNotEmpty);
      }
    });
  });

  test('Determinismus: gleiche Eingabe, gleiche Kennzahlen', () {
    const input = ReviewInputs(checkinRate: 0.8, loadIndex: 42, captures: 7);
    final a = engine.metrics(input).map((m) => '${m.id}:${m.value}').toList();
    final b = engine.metrics(input).map((m) => '${m.id}:${m.value}').toList();
    expect(a, b);
  });
}
