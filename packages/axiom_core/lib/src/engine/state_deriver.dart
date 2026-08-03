/// StateDeriver — projiziert aggregierte Signale auf den StateVector.
///
/// Jede Dimension hat eine dokumentierte Formel (docs/03-DATENMODELL.md §3.1)
/// und liefert ihre Herleitung mit. Ein Score ohne sichtbaren Rechenweg wird
/// von diesem Nutzerprofil zu Recht als Willkuer verworfen (G2).
///
/// WICHTIG: Die Gewichte in [Weights] sind plausibel geraten, NICHT validiert.
/// Sie werden nach der 14-taegigen Baseline-Phase (S1) an echten Daten
/// kalibriert. Bis dahin laufen alle Regeln im SHADOW-Modus.
library;

import 'package:meta/meta.dart';

import '../domain/state_vector.dart';

/// Ausgangswert der Kapazitaetsformel — ein guter, kein idealer Tag.
///
/// Nicht 100: Volle exekutive Kapazitaet ist bei diesem Profil kein
/// Normalzustand, sondern die Ausnahme. Eine Skala, die nach dem ersten
/// Check-in 99 anzeigt, wird zu Recht nicht ernst genommen.
const double kCapacityBaseline = 72;

/// Wert, gegen den bei fehlenden Daten interpoliert wird.
const double kCapacityNeutral = 52;

/// Kalibrierbare Gewichte. Spiegelbild von `rules/core/weights.yaml`.
@immutable
final class Weights {
  // capacity
  final double wSleepDebt;
  final double wLoadIndex;
  final double wFocusDebt;
  final double wRegulation;
  final double wCircadian;

  // sensationNeed
  final double baselineDrive;
  final double wLowStimulus;
  final double wSlotRelief;

  // loadIndex
  final double lSleep;
  final double lRecovery;
  final double lCompensation;
  final double lIrritability;
  final double lWithdrawal;

  const Weights({
    this.wSleepDebt = 0.30,
    this.wLoadIndex = 0.25,
    this.wFocusDebt = 0.20,
    this.wRegulation = 0.15,
    this.wCircadian = 0.10,
    // Hoher Startwert: High Sensation Seeking ist Teil des Ausgangsprofils. [D5]
    this.baselineDrive = 45,
    this.wLowStimulus = 0.40,
    this.wSlotRelief = 0.60,
    this.lSleep = 0.30,
    this.lRecovery = 0.25,
    this.lCompensation = 0.20,
    this.lIrritability = 0.15,
    this.lWithdrawal = 0.10,
  });
}

/// Aggregierte Rohsignale aus dem Event-Strom.
///
/// Alle Felder 0..100, sofern nicht anders vermerkt. Die Aggregation aus
/// Events erfolgt in `axiom_data` (S1) — der Deriver bleibt eine reine
/// Funktion ueber bereits aggregierten Werten und damit trivial testbar.
@immutable
final class Signals {
  final double sleepDebtNorm;
  final double focusDebt;
  final double recoveryQuality;
  final double compensationEffort;
  final double irritabilityTrend;
  final double socialWithdrawal;
  final double minutesInLowStimulus;
  final double sensationReliefLast24h;
  final double incidentPressure;
  final double circadianBonus;

  /// Optional, nur wenn M13 aktiv. Default: aus.
  final double medWindowBonus;

  final Map<String, double> confidence;

  const Signals({
    this.sleepDebtNorm = 0,
    this.focusDebt = 0,
    this.recoveryQuality = 70,
    this.compensationEffort = 0,
    this.irritabilityTrend = 0,
    this.socialWithdrawal = 0,
    this.minutesInLowStimulus = 0,
    this.sensationReliefLast24h = 0,
    this.incidentPressure = 0,
    this.circadianBonus = 0,
    this.medWindowBonus = 0,
    this.confidence = const {},
  });
}

/// Ein Term einer Formel — fuer die aufklappbare Herleitung im UI.
@immutable
final class Term {
  final String label;
  final double contribution;
  const Term(this.label, this.contribution);

  @override
  String toString() =>
      '$label ${contribution >= 0 ? "+" : ""}${contribution.toStringAsFixed(1)}';
}

@immutable
final class DerivedState {
  final StateVector vector;

  /// Herleitung je Dimension. Pflicht fuer G2: Das UI muss
  /// "capacity = 62, weil: Schlafschuld -18, Load -12, Fokuslast -8" zeigen
  /// koennen.
  final Map<String, List<Term>> breakdown;

  const DerivedState(this.vector, this.breakdown);
}

final class StateDeriver {
  final Weights weights;
  const StateDeriver({this.weights = const Weights()});

  DerivedState derive(Signals s, DateTime at) {
    final regulation = _regulation(s);
    final loadTerms = _loadTerms(s);
    final loadIndex = clamp100(loadTerms.fold(0.0, (a, t) => a + t.contribution));

    final capacityTerms = <Term>[
      // Basis ist bewusst NICHT 100. Volle exekutive Kapazitaet ist fuer
      // dieses Profil kein realistischer Normalzustand, und ein Wert von 99
      // nach dem ersten Check-in wuerde die Skala unglaubwuerdig machen —
      // was das gesamte System entwertet (Risiko R3).
      const Term('Basis', kCapacityBaseline),
      Term('Schlafschuld', -weights.wSleepDebt * s.sleepDebtNorm),
      Term('Kompensationslast', -weights.wLoadIndex * loadIndex),
      Term('Fokuslast heute', -weights.wFocusDebt * s.focusDebt),
      Term('Emotionale Belastung', -weights.wRegulation * (100 - regulation)),
      Term('Tagesrhythmus', weights.wCircadian * s.circadianBonus),
      if (s.medWindowBonus != 0) Term('Wirkfenster', s.medWindowBonus),
    ];
    final rawCapacity = capacityTerms.fold(0.0, (a, t) => a + t.contribution);

    // Bei duenner Datenlage Richtung neutral ziehen statt zu raten.
    // Fehlende Daten heissen "unbekannt", nicht "alles bestens". (R8)
    final confidence = s.confidence['capacity'] ?? 1.0;
    final capacity = clamp100(
      rawCapacity * confidence + kCapacityNeutral * (1 - confidence),
    );

    final sensationTerms = <Term>[
      Term('Grunddrive', weights.baselineDrive),
      Term(
        'Niedrigreiz-Zeit',
        weights.wLowStimulus * (s.minutesInLowStimulus / 60) * 10,
      ),
      Term('Gedeckt (24 h)', -weights.wSlotRelief * s.sensationReliefLast24h),
    ];
    final sensationNeed =
        clamp100(sensationTerms.fold(0.0, (a, t) => a + t.contribution));

    return DerivedState(
      StateVector(
        at: at,
        capacity: capacity,
        focusDebt: clamp100(s.focusDebt),
        sensationNeed: sensationNeed,
        loadIndex: loadIndex,
        regulation: regulation,
        sleepDebt: clamp100(s.sleepDebtNorm),
        confidence: s.confidence,
      ),
      {
        'capacity': capacityTerms,
        'load_index': loadTerms,
        'sensation_need': sensationTerms,
      },
    );
  }

  List<Term> _loadTerms(Signals s) => [
        Term('Schlafschuld', weights.lSleep * s.sleepDebtNorm),
        // Kernsignal von D1: Erholung wirkt nicht mehr.
        Term('Erholung wirkt nicht', weights.lRecovery * (100 - s.recoveryQuality)),
        Term('Kompensationsaufwand', weights.lCompensation * s.compensationEffort),
        Term('Reizbarkeit', weights.lIrritability * s.irritabilityTrend),
        // Rueckzug als Fruehindikator — faellt sonst erst spaet auf.
        Term('Sozialer Rückzug', weights.lWithdrawal * s.socialWithdrawal),
      ];

  /// Regulationsreserve faellt mit der Intensitaet emotionaler Spikes der
  /// letzten 72 h und erholt sich abklingend. [D10]
  int _regulation(Signals s) => clamp100(100 - s.incidentPressure);
}
