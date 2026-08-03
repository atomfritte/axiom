/// Health Connect → Events.
///
/// Schlaf und Bewegung gingen bisher nur über Selbstauskunft in die
/// Kapazitätsrechnung ein — also über genau den Kanal, der unter Last als
/// erstes ausfällt. Wer schlecht geschlafen hat, trägt das am nächsten Tag am
/// seltensten nach [D7, D8].
///
/// **Idempotent.** Events sind append-only: Ein doppelter Import wäre nicht
/// rückgängig zu machen und würde die Schlafschuld verdoppeln. Deshalb trägt
/// jedes importierte Ereignis die Quell-ID, und vor jedem Schreiben werden
/// die bereits vorhandenen gelesen. Zweimal importieren ändert nichts.
library;

import 'package:axiom_core/axiom_core.dart';

import '../state/runtime.dart';
import 'android_bridge.dart';

/// Verfügbarkeit von Health Connect, so wie die Oberfläche sie unterscheiden
/// muss. Ein pauschales „geht nicht" ließe offen, warum keine Daten kommen.
enum HealthAvailability {
  /// Auf diesem Gerät nicht vorhanden — etwa auf dem Linux-Desktop.
  unavailable,

  /// Vorhanden, aber die Systemkomponente ist zu alt.
  needsUpdate,

  /// Vorhanden, aber noch ohne Freigabe.
  notGranted,

  /// Nutzbar.
  ready,
}

final class HealthImportResult {
  /// Neu übernommene Schlaffenster.
  final int sleepNights;

  /// Neu übernommene Tagessummen Schritte.
  final int stepDays;

  /// Schon vorhanden, deshalb übersprungen.
  final int skipped;

  const HealthImportResult({
    this.sleepNights = 0,
    this.stepDays = 0,
    this.skipped = 0,
  });

  int get imported => sleepNights + stepDays;
  bool get isEmpty => imported == 0 && skipped == 0;
}

abstract final class HealthSync {
  /// Wie weit zurück importiert wird.
  ///
  /// Vier Wochen decken die Baseline (14 Tage) mit Reserve ab. Weiter zurück
  /// bringt nichts: Ältere Nächte gehen in keine Regel mehr ein.
  static const Duration window = Duration(days: 28);

  static Future<HealthAvailability> availability() async {
    if (!AndroidBridge.isSupported) return HealthAvailability.unavailable;
    final status = await AndroidBridge.healthStatus();
    if (status['available'] != true) {
      return status['needsUpdate'] == true
          ? HealthAvailability.needsUpdate
          : HealthAvailability.unavailable;
    }
    return status['granted'] == true
        ? HealthAvailability.ready
        : HealthAvailability.notGranted;
  }

  /// Öffnet den Systemdialog. Die Freigabe erteilt das System, nicht AXIOM.
  ///
  /// Gibt den Grund zurück, wenn sich nichts öffnet — sonst ist ein Knopf,
  /// der nichts tut, von einem kaputten nicht zu unterscheiden.
  static Future<PlatformOutcome> connect() =>
      AndroidBridge.healthRequestPermissions();

  static Future<void> openSettings() => AndroidBridge.healthOpenSettings();

  /// Holt neue Aufzeichnungen und legt sie als Events ab.
  ///
  /// Schreibt nur, was noch nicht da ist. Rechnet nichts aus, bewertet nichts
  /// — die Auswertung macht der StateDeriver, sichtbar und nachrechenbar (G2).
  static Future<HealthImportResult> import(AxiomRuntime runtime) async {
    if (await availability() != HealthAvailability.ready) {
      return const HealthImportResult();
    }

    final since = runtime.clock.nowUtc().subtract(window);
    final records = await AndroidBridge.healthRead(since);
    if (records.isEmpty) return const HealthImportResult();

    final known = await _knownSourceIds(runtime, since);

    var nights = 0;
    var days = 0;
    var skipped = 0;

    for (final record in records) {
      final sourceId = record['sourceId'] as String?;
      if (sourceId == null) continue;
      if (known.contains(sourceId)) {
        skipped++;
        continue;
      }

      final start = _millis(record['startMillis']);
      final end = _millis(record['endMillis']);
      if (start == null || end == null) continue;

      switch (record['kind']) {
        case 'sleep':
          await runtime.recordAt(
            end,
            EventType.sleepWindow,
            payload: {
              'bed_at': start.toUtc().toIso8601String(),
              'wake_at': end.toUtc().toIso8601String(),
              // Keine Qualitaetsangabe erfinden: Health Connect liefert
              // Phasen, aber keine Bewertung, und eine geratene Zahl waere
              // in der Herleitung nicht von einer gemessenen zu unterscheiden.
              'est_debt_min': _sleepDebtMinutes(start, end),
              'source_id': sourceId,
              'via': 'health_connect',
            },
          );
          known.add(sourceId);
          nights++;

        case 'steps':
          final count = (record['count'] as num?)?.round();
          if (count == null) continue;
          await runtime.recordAt(
            end,
            EventType.healthSample,
            payload: {
              'metric': 'steps',
              'value': count,
              'from': start.toUtc().toIso8601String(),
              'to': end.toUtc().toIso8601String(),
              'source_id': sourceId,
              'via': 'health_connect',
            },
          );
          known.add(sourceId);
          days++;
      }
    }

    return HealthImportResult(
      sleepNights: nights,
      stepDays: days,
      skipped: skipped,
    );
  }

  /// Schlafschuld gegen sieben Stunden Soll — dieselbe Annahme wie bei der
  /// Handeingabe, damit importierte und getippte Nächte vergleichbar bleiben.
  /// Der Wert wird nach der Eichung durch das persönliche Soll ersetzt.
  static int _sleepDebtMinutes(DateTime bedAt, DateTime wakeAt) {
    const targetMinutes = 7 * 60;
    final actual = wakeAt.difference(bedAt).inMinutes;
    return (targetMinutes - actual).clamp(0, 600);
  }

  static Future<Set<String>> _knownSourceIds(
    AxiomRuntime runtime,
    DateTime since,
  ) async {
    // Etwas Vorlauf, weil ein Schlaffenster am Rand des Zeitraums liegen kann.
    final events = await runtime.store.query(
      from: since.subtract(const Duration(days: 2)),
      types: {EventType.sleepWindow, EventType.healthSample},
    );
    return events
        .map((e) => e.payload['source_id'])
        .whereType<String>()
        .toSet();
  }

  static DateTime? _millis(Object? value) {
    final ms = (value as num?)?.toInt();
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }
}
