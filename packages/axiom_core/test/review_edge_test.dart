/// Review-Kennzahlen an den Raendern.
///
/// Die sechs Kennzahlen sind der einzige Ort, an dem AXIOM ueber sich selbst
/// Auskunft gibt — K6 ist ausdruecklich das Abbruchkriterium des Projekts.
/// Eine Kennzahl, die an ihrer Schwelle schweigt, ist deshalb schlimmer als
/// eine, die es gar nicht gibt: Sie sieht aus wie ein Waechter.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

const ReviewEngine _engine = ReviewEngine();

Metric _metric(String id, ReviewInputs input) =>
    _engine.metrics(input).firstWhere((m) => m.id == id);

void main() {
  group('Der Zeitdeckel ist Teil des Konzepts (D3)', () {
    test('jeder Umfang hat eine Obergrenze, und sie waechst mit dem Umfang',
        () {
      var vorher = Duration.zero;
      for (final scope in ReviewScope.values) {
        expect(scope.timeCap, greaterThan(vorher), reason: scope.name);
        expect(scope.label, isNotEmpty, reason: scope.name);
        vorher = scope.timeCap;
      }
    });

    test('der Tagesreview bleibt unter zwei Minuten (G1)', () {
      expect(ReviewScope.day.timeCap, lessThanOrEqualTo(const Duration(minutes: 2)));
    });

    test('Regeln aendern geht nicht taeglich', () {
      // Sonst waere der Regeleditor eine taegliche Meta-Work-Flaeche.
      expect(ReviewScope.day.allowsRuleChanges, isFalse);
      for (final scope in [
        ReviewScope.week,
        ReviewScope.month,
        ReviewScope.quarter
      ]) {
        expect(scope.allowsRuleChanges, isTrue, reason: scope.name);
      }
    });

    test('Module aktivieren geht noch seltener', () {
      expect(ReviewScope.day.allowsModuleChanges, isFalse);
      expect(ReviewScope.week.allowsModuleChanges, isFalse);
      expect(ReviewScope.month.allowsModuleChanges, isTrue);
      expect(ReviewScope.quarter.allowsModuleChanges, isTrue);
    });

    test('wer Module aendern darf, darf auch Regeln aendern', () {
      for (final scope in ReviewScope.values) {
        if (scope.allowsModuleChanges) {
          expect(scope.allowsRuleChanges, isTrue, reason: scope.name);
        }
      }
    });
  });

  group('Jede Kennzahl steht mit Herleitung da (G2)', () {
    test('alle sechs sind vorhanden und eindeutig benannt', () {
      final metrics = _engine.metrics(const ReviewInputs());
      expect(metrics, hasLength(6));
      expect(metrics.map((m) => m.id).toSet(), hasLength(6));
      for (final metric in metrics) {
        expect(metric.label, isNotEmpty, reason: metric.id);
        expect(metric.derivation, isNotEmpty, reason: metric.id);
        expect(metric.value, isNotEmpty, reason: metric.id);
      }
    });

    test('der Wert bleibt als Quelltext mit Werten erhalten — sonst waere er '
        'nicht uebersetzbar', () {
      final metric = _metric(
          'capture', const ReviewInputs(captures: 12, tasksCreated: 4, tasksCompleted: 3));
      expect(metric.valueSource.args, [12, 4, 3]);
      expect(metric.value, contains('12'));
    });

    test('kein Text nennt Schuld oder Ausrufezeichen (R7)', () {
      const schlecht = ReviewInputs(
        checkinRate: 0.2,
        loadIndex: 90,
        metaMinutes: 200,
        savedMinutesEstimate: 10,
        captures: 30,
        plannedSlots: 1,
        unplannedSlots: 9,
      );
      for (final metric in _engine.metrics(schlecht)) {
        for (final text in [
          metric.label,
          metric.value,
          metric.derivation,
          metric.consequence ?? ''
        ]) {
          expect(text, isNot(contains('!')), reason: '${metric.id}: $text');
          for (final wort in ['versagt', 'schon wieder', 'faul', 'endlich']) {
            expect(text.toLowerCase(), isNot(contains(wort)),
                reason: '${metric.id}: $text');
          }
        }
      }
    });
  });

  group('Schwellen auf den Punkt', () {
    test('Erfassungsquote: genau 80 Prozent reichen', () {
      expect(_metric('checkins', const ReviewInputs(checkinRate: 0.8)).needsAttention,
          isFalse);
      expect(
          _metric('checkins', const ReviewInputs(checkinRate: 0.79)).needsAttention,
          isTrue);
    });

    test('Kompensationslast: Aufmerksamkeit ab 55, Ansage ab 70', () {
      expect(_metric('load', const ReviewInputs(loadIndex: 54)).needsAttention,
          isFalse);
      expect(_metric('load', const ReviewInputs(loadIndex: 55)).needsAttention,
          isTrue);
      expect(_metric('load', const ReviewInputs(loadIndex: 69)).consequence,
          isNull);
      expect(_metric('load', const ReviewInputs(loadIndex: 70)).consequence,
          isNotNull);
    });

    test('die Laststufen des Reviews sind dieselben wie im Monitor', () {
      // Zwei Zahlenpaare fuer dieselbe Sache laufen auseinander.
      expect(
          _metric('load', ReviewInputs(loadIndex: LoadLevel.l1.threshold))
              .needsAttention,
          isTrue);
      expect(
          _metric('load', ReviewInputs(loadIndex: LoadLevel.l2.threshold))
              .consequence,
          isNotNull);
    });

    test('Richtung der Last: erst ab mehr als drei Punkten', () {
      MetricTrend? trend(int jetzt, int vorher) =>
          _metric('load', ReviewInputs(loadIndex: jetzt, loadIndexBefore: vorher))
              .trend;
      expect(trend(50, 53), MetricTrend.flat);
      expect(trend(50, 54), MetricTrend.down);
      expect(trend(53, 50), MetricTrend.flat);
      expect(trend(54, 50), MetricTrend.up);
      expect(trend(50, 50), MetricTrend.flat);
    });

    test('ohne Vorzeitraum gibt es keine Richtung, keine erfundene', () {
      final metric = _metric('load', const ReviewInputs(loadIndex: 50));
      expect(metric.trend, isNull);
      expect(metric.valueSource.args, [50]);
    });

    test('das Vorzeichen der Bewegung steht im Text', () {
      expect(
        _metric('load', const ReviewInputs(loadIndex: 60, loadIndexBefore: 50)).value,
        contains('+10'),
      );
      expect(
        _metric('load', const ReviewInputs(loadIndex: 40, loadIndexBefore: 50)).value,
        contains('-10'),
      );
    });

    test('Reizdeckung: genau 70 Prozent reichen', () {
      expect(
        _metric('sensation', const ReviewInputs(plannedSlots: 7, unplannedSlots: 3))
            .needsAttention,
        isFalse,
      );
      expect(
        _metric('sensation', const ReviewInputs(plannedSlots: 6, unplannedSlots: 4))
            .needsAttention,
        isTrue,
      );
    });

    test('ohne Slots keine erfundene Quote', () {
      final metric = _metric('sensation', const ReviewInputs());
      expect(metric.value, 'keine Daten');
      expect(metric.needsAttention, isFalse);
      expect(metric.consequence, isNull);
    });

    test('erfasst, aber nichts einsortiert — der Eingang laeuft voll', () {
      expect(
        _metric('capture', const ReviewInputs(captures: 12)).needsAttention,
        isTrue,
      );
      expect(
        _metric('capture', const ReviewInputs(captures: 12, tasksCreated: 1))
            .needsAttention,
        isFalse,
      );
      // Ohne Erfassungen ist nichts liegen geblieben.
      expect(_metric('capture', const ReviewInputs()).needsAttention, isFalse);
    });

    test('Impulse: ohne Abfang keine Zahl, mit Abfang die gehaltenen', () {
      expect(_metric('impulse', const ReviewInputs()).value, 'keine');
      final metric = _metric('impulse',
          const ReviewInputs(impulsesIntercepted: 5, impulsesProceeded: 2));
      expect(metric.valueSource.args, [3, 5]);
      // Diese Kennzahl bewertet ausdruecklich nicht.
      expect(metric.consequence, isNull);
      expect(metric.needsAttention, isFalse);
    });
  });

  group('K6 — das Abbruchkriterium', () {
    test('genau ausgeglichen ist noch in Ordnung, darueber nicht mehr', () {
      expect(
        _metric('meta',
                const ReviewInputs(metaMinutes: 40, savedMinutesEstimate: 40))
            .needsAttention,
        isFalse,
      );
      expect(
        _metric('meta',
                const ReviewInputs(metaMinutes: 41, savedMinutesEstimate: 40))
            .needsAttention,
        isTrue,
      );
    });

    test('ueber eins wird zurueckgebaut, nicht optimiert', () {
      final metric = _metric('meta',
          const ReviewInputs(metaMinutes: 120, savedMinutesEstimate: 40));
      expect(metric.consequence, contains('zurückgebaut'));
      expect(metric.value, contains('3.00'));
    });

    test('ohne eigene Schaetzung steht nur die Nutzungszeit da', () {
      // Ohne Schaetzung gibt es kein Verhaeltnis. Der Wert wird dann nicht
      // geraten — er waere sonst die wichtigste Zahl des Projekts auf
      // erfundener Grundlage.
      final metric = _metric('meta', const ReviewInputs(metaMinutes: 90));
      expect(metric.valueSource.args, [90]);
      expect(metric.value, contains('90'));
      expect(metric.trend, isNull);
      expect(metric.needsAttention, isFalse);
      expect(metric.consequence, isNull);
    });

    test('ohne jede Nutzung steht null da, nicht nichts', () {
      expect(_metric('meta', const ReviewInputs()).value, contains('0'));
    });
  });

  group('Regelurteile', () {
    test('ohne Auffaelligkeiten gibt es keine', () {
      expect(_engine.ruleVerdicts(const ReviewInputs()), isEmpty);
    });

    test('jede Gruppe bekommt ihr eigenes Urteil, jedes begruendet', () {
      final verdicts = _engine.ruleVerdicts(const ReviewInputs(
        weakRules: ['R-010'],
        silentRules: ['R-020'],
        suppressedRules: ['R-030'],
      ));
      expect(verdicts.map((v) => v.ruleId), ['R-010', 'R-020', 'R-030']);
      expect(verdicts.map((v) => v.verdict), [
        RuleAction.retire,
        RuleAction.widen,
        RuleAction.resolveConflict,
      ]);
      for (final verdict in verdicts) {
        expect(verdict.reason, isNotEmpty, reason: verdict.ruleId);
        expect(verdict.reason, isNot(contains('!')), reason: verdict.ruleId);
      }
    });

    test('die Reihenfolge haengt an der Gruppe, nicht an der Eingabe', () {
      final a = _engine.ruleVerdicts(const ReviewInputs(
        weakRules: ['R-010', 'R-011'],
        silentRules: ['R-020'],
      ));
      final b = _engine.ruleVerdicts(const ReviewInputs(
        weakRules: ['R-010', 'R-011'],
        silentRules: ['R-020'],
      ));
      expect(a.map((v) => v.ruleId), b.map((v) => v.ruleId));
      expect(a.map((v) => v.ruleId), ['R-010', 'R-011', 'R-020']);
    });

    test('jede Aktion kommt vor — keine ist nur deklariert', () {
      final genutzt = _engine
          .ruleVerdicts(const ReviewInputs(
            weakRules: ['a'],
            silentRules: ['b'],
            suppressedRules: ['c'],
          ))
          .map((v) => v.verdict)
          .toSet();
      expect(genutzt, RuleAction.values.toSet());
    });
  });

  test('Determinismus: gleiche Eingabe, gleiche Kennzahlen', () {
    const input = ReviewInputs(
      checkinRate: 0.75,
      loadIndex: 62,
      loadIndexBefore: 55,
      metaMinutes: 30,
      savedMinutesEstimate: 90,
      captures: 8,
      tasksCreated: 3,
      tasksCompleted: 2,
      plannedSlots: 3,
      unplannedSlots: 2,
      impulsesIntercepted: 4,
      impulsesProceeded: 1,
    );
    List<String> lauf() => _engine
        .metrics(input)
        .map((m) => '${m.id}=${m.value}|${m.trend}|${m.needsAttention}')
        .toList();
    expect(lauf(), lauf());
  });
}
