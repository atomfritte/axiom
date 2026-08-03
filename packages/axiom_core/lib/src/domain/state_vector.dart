/// Der Zustandsvektor — die Projektion aller Events auf sechs Dimensionen.
///
/// Jede Dimension liegt in 0..100 und hat eine dokumentierte Formel
/// (docs/03-DATENMODELL.md §3.1). Kein Wert ohne nachvollziehbare Herleitung:
/// Ein Score, dessen Rechenweg unsichtbar ist, wird von diesem Nutzerprofil
/// zu Recht als Willkuer verworfen (G2).
library;

import 'package:meta/meta.dart';

/// Eskalationsstufen des Load Monitors (M9).
///
/// L3 ist bewusst unbequem: Ein hochkompensiertes System bemerkt seinen
/// eigenen Absturz zuletzt und braucht einen externen Notaus, den es im
/// Vorfeld selbst autorisiert hat. [D1]
enum LoadLevel {
  l0(0),
  l1(55),
  l2(70),
  l3(85);

  const LoadLevel(this.threshold);
  final int threshold;

  static LoadLevel fromIndex(int loadIndex) {
    if (loadIndex >= LoadLevel.l3.threshold) return LoadLevel.l3;
    if (loadIndex >= LoadLevel.l2.threshold) return LoadLevel.l2;
    if (loadIndex >= LoadLevel.l1.threshold) return LoadLevel.l1;
    return LoadLevel.l0;
  }
}

/// Konfidenz einer Dimension. Bei alten oder fehlenden Daten sinkt sie.
///
/// Regeln unterhalb eines Schwellenwerts feuern nicht: lieber schweigen als
/// raten. Verhindert kaskadierende Fehlentscheidungen bei Datenluecken (R8).
typedef Confidence = double;

@immutable
final class StateVector {
  final DateTime at;

  /// Verfuegbare exekutive Kapazitaet. Steuert, welche Aufgaben ueberhaupt
  /// sichtbar sind (M2). [D2]
  final int capacity;

  /// Ununterbrochene Fokuslast heute. Steuert M4. [D6]
  final int focusDebt;

  /// Ungedeckter Reizbedarf. Steuert M5/M6. [D5]
  final int sensationNeed;

  /// Kumulierte Kompensationskosten, 7-Tage-Mittel. Steuert M9. [D1]
  final int loadIndex;

  /// Emotionale Regulationsreserve. Steuert M6/M10. [D10]
  final int regulation;

  /// Schlafschuld, normiert. Speist capacity und loadIndex. [D8]
  final int sleepDebt;

  /// Konfidenz je Dimension, 0.0..1.0.
  final Map<String, Confidence> confidence;

  const StateVector({
    required this.at,
    required this.capacity,
    required this.focusDebt,
    required this.sensationNeed,
    required this.loadIndex,
    required this.regulation,
    required this.sleepDebt,
    this.confidence = const {},
  });

  LoadLevel get loadLevel => LoadLevel.fromIndex(loadIndex);

  /// Zugriff ueber den Variablennamen aus der Regel-DSL (snake_case).
  /// Unbekannte Namen liefern null — der ConditionEvaluator wirft dann,
  /// statt still `false` zu liefern.
  num? numeric(String variable) => switch (variable) {
        'capacity' => capacity,
        'focus_debt' => focusDebt,
        'sensation_need' => sensationNeed,
        'load_index' => loadIndex,
        'regulation' => regulation,
        'sleep_debt' => sleepDebt,
        _ => null,
      };

  Confidence confidenceOf(String variable) => confidence[variable] ?? 1.0;

  StateVector copyWith({
    DateTime? at,
    int? capacity,
    int? focusDebt,
    int? sensationNeed,
    int? loadIndex,
    int? regulation,
    int? sleepDebt,
    Map<String, Confidence>? confidence,
  }) =>
      StateVector(
        at: at ?? this.at,
        capacity: capacity ?? this.capacity,
        focusDebt: focusDebt ?? this.focusDebt,
        sensationNeed: sensationNeed ?? this.sensationNeed,
        loadIndex: loadIndex ?? this.loadIndex,
        regulation: regulation ?? this.regulation,
        sleepDebt: sleepDebt ?? this.sleepDebt,
        confidence: confidence ?? this.confidence,
      );

  Map<String, Object?> toJson() => {
        'at': at.toIso8601String(),
        'capacity': capacity,
        'focus_debt': focusDebt,
        'sensation_need': sensationNeed,
        'load_index': loadIndex,
        'regulation': regulation,
        'sleep_debt': sleepDebt,
        'confidence': confidence,
      };

  @override
  String toString() => 'StateVector(cap=$capacity, focus=$focusDebt, '
      'stim=$sensationNeed, load=$loadIndex/${loadLevel.name}, '
      'reg=$regulation, sleep=$sleepDebt)';
}

/// Begrenzt einen Wert auf 0..100. Alle Formeln enden hiermit.
int clamp100(num value) => value.round().clamp(0, 100);
