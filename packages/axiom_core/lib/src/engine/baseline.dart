/// Baseline-Bereitschaft — wann darf kalibriert werden?
///
/// Die eigentliche Frage ist nicht *„sind 14 Tage um?"*, sondern *„liegen
/// genug Daten vor?"*. Vierzehn Tage mit fünf Check-ins sind wertlos: Die
/// Formelgewichte würden auf Rauschen geeicht, und ein auf Rauschen geeichtes
/// System ist schlechter als ein ehrlich geschätztes (R3).
///
/// Deshalb prüft AXIOM drei Dinge getrennt und zeigt alle drei an:
/// Zeitraum, Messpunkte, Schlafnächte. Erst wenn alle erfüllt sind, ist die
/// Kalibrierung fällig.
///
/// Dieselben Schwellen nutzt `tools/bin/calibrate.dart` — sie stehen hier,
/// damit App und Werkzeug nicht auseinanderlaufen.
library;

import 'package:meta/meta.dart';

/// Mindestzeitraum. Kürzer erfasst keinen vollen Wochenrhythmus.
const int kBaselineDays = 14;

/// Mindestzahl Check-ins. Unter 20 ist das circadiane Profil nicht
/// belastbar — pro Tageszeit blieben zu wenige Messungen übrig.
const int kBaselineCheckins = 20;

/// Mindestzahl Schlafnächte für die Schlaf-Kapazitäts-Kopplung.
const int kBaselineSleepNights = 7;

enum BaselineStatus {
  /// Noch nicht gestartet.
  notStarted,

  /// Läuft, mindestens eine Bedingung offen.
  collecting,

  /// Alle Bedingungen erfüllt — kalibrieren.
  ready,

  /// Kalibriert. Die Gewichte stammen aus echten Daten.
  calibrated,
}

/// Eine einzelne Bedingung mit ihrem Stand.
@immutable
final class BaselineCriterion {
  final String label;
  final int current;
  final int required;

  /// Was fehlt, wenn es nicht reicht — in Nutzersprache.
  final String? shortfall;

  const BaselineCriterion({
    required this.label,
    required this.current,
    required this.required,
    this.shortfall,
  });

  bool get isMet => current >= required;
  double get progress => required == 0 ? 1 : (current / required).clamp(0, 1);
  int get missing => (required - current).clamp(0, required);
}

@immutable
final class BaselineProgress {
  final BaselineStatus status;
  final List<BaselineCriterion> criteria;

  /// Tag der Baseline, 1-basiert. Null, wenn nicht gestartet.
  final int? day;

  const BaselineProgress({
    required this.status,
    required this.criteria,
    this.day,
  });

  bool get isReady => status == BaselineStatus.ready;

  /// Bedingungen, die noch offen sind.
  List<BaselineCriterion> get open =>
      criteria.where((c) => !c.isMet).toList();

  /// Eine Zeile für die Übersicht — beschreibt den Stand, ohne zu drängen.
  String get summary => switch (status) {
        BaselineStatus.notStarted => 'Noch nicht gestartet.',
        BaselineStatus.calibrated =>
          'Geeicht. Die Gewichte stammen aus deinen Daten.',
        BaselineStatus.ready =>
          'Genug Daten. Die Gewichte können jetzt geeicht werden.',
        BaselineStatus.collecting => open.isEmpty
            ? 'Sammelt.'
            : 'Es fehlt noch: ${open.map((c) => c.shortfall ?? c.label).join(", ")}.',
      };
}

final class BaselineTracker {
  const BaselineTracker();

  /// Bewertet den Stand.
  ///
  /// [calibrated] kommt aus `weights.yaml` — sobald dort
  /// `status: calibrated` steht, ist die Phase abgeschlossen.
  BaselineProgress evaluate({
    required DateTime? startedAt,
    required DateTime now,
    required int checkins,
    required int sleepNights,
    required bool calibrated,
  }) {
    if (calibrated) {
      return const BaselineProgress(
        status: BaselineStatus.calibrated,
        criteria: [],
      );
    }
    if (startedAt == null) {
      return const BaselineProgress(
        status: BaselineStatus.notStarted,
        criteria: [],
      );
    }

    final day = now.difference(startedAt).inDays + 1;
    final criteria = [
      BaselineCriterion(
        label: 'Tage',
        current: day.clamp(0, kBaselineDays),
        required: kBaselineDays,
        shortfall: '${(kBaselineDays - day).clamp(0, kBaselineDays)} Tage',
      ),
      BaselineCriterion(
        label: 'Messpunkte',
        current: checkins,
        required: kBaselineCheckins,
        shortfall: '${(kBaselineCheckins - checkins).clamp(0, kBaselineCheckins)} '
            'Check-ins',
      ),
      BaselineCriterion(
        label: 'Nächte',
        current: sleepNights,
        required: kBaselineSleepNights,
        shortfall:
            '${(kBaselineSleepNights - sleepNights).clamp(0, kBaselineSleepNights)} '
                'Schlafeinträge',
      ),
    ];

    return BaselineProgress(
      status: criteria.every((c) => c.isMet)
          ? BaselineStatus.ready
          : BaselineStatus.collecting,
      criteria: criteria,
      day: day,
    );
  }
}
