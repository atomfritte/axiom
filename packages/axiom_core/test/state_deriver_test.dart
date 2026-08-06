import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

void main() {
  const deriver = StateDeriver();
  final at = DateTime.utc(2026, 8, 3, 10);

  group('capacity [D8, D1]', () {
    test('ausgeruht und unbelastet -> hohe, aber nicht perfekte Kapazitaet',
        () {
      final s = deriver.derive(
        const Signals(recoveryQuality: 90, confidence: {'capacity': 1.0}),
        at,
      );
      // Basis ist bewusst 72, nicht 100: Volle exekutive Kapazitaet ist bei
      // diesem Profil die Ausnahme. Eine Skala, die nach dem ersten Check-in
      // 99 zeigt, wird zu Recht nicht ernst genommen (R3).
      expect(s.vector.capacity, inInclusiveRange(60, 80));
    });

    test('fehlende Daten ziehen Richtung neutral, nicht Richtung optimal', () {
      final blind = deriver.derive(
        const Signals(recoveryQuality: 90, confidence: {'capacity': 0.0}),
        at,
      );
      final known = deriver.derive(
        const Signals(recoveryQuality: 90, confidence: {'capacity': 1.0}),
        at,
      );
      expect(blind.vector.capacity, closeTo(kCapacityNeutral, 2));
      expect(blind.vector.capacity, lessThan(known.vector.capacity));
    });

    test('fehlende Daten beschoenigen einen schlechten Zustand nicht', () {
      final bad = deriver.derive(
        const Signals(
          sleepDebtNorm: 95,
          recoveryQuality: 5,
          compensationEffort: 95,
          confidence: {'capacity': 0.0},
        ),
        at,
      );
      // Ohne Vertrauen in die Daten landet der Wert neutral — er behauptet
      // weder Krise noch Bestzustand.
      expect(bad.vector.capacity, closeTo(kCapacityNeutral, 2));
    });

    test('Schlafschuld senkt die Kapazitaet deutlich', () {
      final rested = deriver.derive(const Signals(recoveryQuality: 90), at);
      final tired = deriver.derive(
        const Signals(recoveryQuality: 90, sleepDebtNorm: 80),
        at,
      );
      expect(tired.vector.capacity, lessThan(rested.vector.capacity - 20));
    });

    test('Fokuslast im Tagesverlauf senkt die Kapazitaet', () {
      final fresh = deriver.derive(const Signals(), at);
      final spent = deriver.derive(const Signals(focusDebt: 80), at);
      expect(spent.vector.capacity, lessThan(fresh.vector.capacity));
    });

    test('bleibt in 0..100', () {
      final worst = deriver.derive(
        const Signals(
          sleepDebtNorm: 100,
          focusDebt: 100,
          recoveryQuality: 0,
          compensationEffort: 100,
          irritabilityTrend: 100,
          socialWithdrawal: 100,
          incidentPressure: 100,
        ),
        at,
      );
      expect(worst.vector.capacity, inInclusiveRange(0, 100));
      expect(worst.vector.loadIndex, inInclusiveRange(0, 100));
    });
  });

  group('loadIndex und Eskalationsstufen [D1]', () {
    test('gesunde Signale -> L0', () {
      final s = deriver.derive(const Signals(recoveryQuality: 90), at);
      expect(s.vector.loadLevel, LoadLevel.l0);
    });

    test('Dauerbelastung erreicht L3 -> Erhaltungsmodus', () {
      final s = deriver.derive(
        const Signals(
          sleepDebtNorm: 90,
          recoveryQuality: 10,
          compensationEffort: 90,
          irritabilityTrend: 80,
          socialWithdrawal: 80,
        ),
        at,
      );
      expect(s.vector.loadLevel, LoadLevel.l3);
    });

    test('Schwellen L0/L1/L2/L3', () {
      expect(LoadLevel.fromIndex(0), LoadLevel.l0);
      expect(LoadLevel.fromIndex(54), LoadLevel.l0);
      expect(LoadLevel.fromIndex(55), LoadLevel.l1);
      expect(LoadLevel.fromIndex(70), LoadLevel.l2);
      expect(LoadLevel.fromIndex(85), LoadLevel.l3);
    });
  });

  group('sensationNeed [D5]', () {
    test('startet hoch — High Sensation Seeking ist Teil des Profils', () {
      final s = deriver.derive(const Signals(), at);
      expect(s.vector.sensationNeed, greaterThanOrEqualTo(40));
    });

    test('lange Niedrigreiz-Phase treibt den Bedarf hoch', () {
      final s = deriver.derive(
        const Signals(minutesInLowStimulus: 480),
        at,
      );
      expect(s.vector.sensationNeed, greaterThan(70));
    });

    test('gedeckter Bedarf senkt den Wert', () {
      final undeckt = deriver.derive(
        const Signals(minutesInLowStimulus: 480),
        at,
      );
      final gedeckt = deriver.derive(
        const Signals(minutesInLowStimulus: 480, sensationReliefLast24h: 60),
        at,
      );
      expect(gedeckt.vector.sensationNeed, lessThan(undeckt.vector.sensationNeed));
    });
  });

  group('Herleitung ist sichtbar (G2)', () {
    test('breakdown liefert die Terme jeder Formel', () {
      final s = deriver.derive(
        const Signals(sleepDebtNorm: 60, focusDebt: 30),
        at,
      );
      expect(s.breakdown.keys,
          containsAll(<String>['capacity', 'load_index', 'sensation_need']));
      expect(s.breakdown['capacity'], isNotEmpty);
      expect(
        s.breakdown['capacity']!.map((t) => t.label),
        contains('Schlafschuld'),
      );
    });

    test('Terme summieren sich auf den ausgewiesenen Wert — jede Konfidenz',
        () {
      // Vorher stand hier fest confidence: {'capacity': 1.0} — der einzige
      // Fall, in dem diese Zusicherung gar nicht scheitern kann. Der Waechter
      // war gruen und bewachte nichts: Ohne Schlafdaten liegt die Konfidenz
      // dauerhaft bei 0,5, und dort summierten sich die angezeigten Terme auf
      // 67,5, waehrend auf dem Bildschirm 60 stand.
      for (final c in <double>[0.0, 0.25, 0.4, 0.5, 0.75, 1.0]) {
        final s = deriver.derive(
          Signals(
            sleepDebtNorm: 40,
            focusDebt: 20,
            recoveryQuality: 60,
            confidence: {'capacity': c},
          ),
          at,
        );
        final sum = s.breakdown['capacity']!
            .fold<double>(0, (a, t) => a + t.contribution);
        expect(
          sum.round().clamp(0, 100),
          s.vector.capacity,
          reason: 'Konfidenz $c: Herleitung ergibt $sum, '
              'angezeigt wird ${s.vector.capacity}',
        );
      }
    });

    test('duenne Datenlage steht als eigener Term in der Herleitung', () {
      // Der Zug Richtung neutral ist der groesste Einzelposten, sobald
      // Schlafdaten fehlen. Er darf nicht unsichtbar wirken (G2).
      final s = deriver.derive(
        const Signals(recoveryQuality: 90, confidence: {'capacity': 0.5}),
        at,
      );
      expect(
        s.breakdown['capacity']!.map((t) => t.label),
        contains('Dünne Datenlage'),
      );
    });

    test('bei voller Konfidenz erscheint kein Term ohne Wirkung', () {
      // Eine Zeile "Dünne Datenlage +0.0" waere Rauschen und wuerde einen
      // Zweifel behaupten, den es nicht gibt.
      final s = deriver.derive(
        const Signals(recoveryQuality: 90, confidence: {'capacity': 1.0}),
        at,
      );
      expect(
        s.breakdown['capacity']!.map((t) => t.label),
        isNot(contains('Dünne Datenlage')),
      );
    });
  });

  test('Determinismus: gleiche Signale, gleicher Vektor', () {
    const signals = Signals(sleepDebtNorm: 33, focusDebt: 44);
    final a = deriver.derive(signals, at);
    final b = deriver.derive(signals, at);
    expect(a.vector.toJson(), b.vector.toJson());
  });
}
