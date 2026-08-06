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
///
/// Die Quell-ID allein reicht dafür nicht: Uhr und Hersteller-App schreiben
/// dieselbe Nacht als zwei Aufzeichnungen mit verschiedenen IDs. Ein
/// Schlaffenster, das ein bereits erfasstes überlappt, wird deshalb ebenfalls
/// übersprungen — siehe [HealthSync.plan].
library;

import 'package:axiom_core/axiom_core.dart';

import '../i18n/i18n.dart';
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

/// Ein bereits erfasstes Schlaffenster. Beide Zeiten UTC.
typedef SleepWindow = ({DateTime from, DateTime to});

/// Ein Datensatz, so wie er in den Ereignisstrom soll.
///
/// **Warum es diesen Typ gibt.** [HealthSync.import] laeuft nur auf einem
/// Geraet mit Health Connect; die Zuordnung von Datensaetzen zu Ereignissen
/// war damit nur dort pruefbar — und blieb ungeprueft. [HealthSync.plan]
/// trennt das Entscheiden vom Schreiben und laeuft ueberall.
final class HealthEntry {
  final EventType type;

  /// Zeitpunkt des Ereignisses: das Ende der Aufzeichnung.
  final DateTime at;

  final Map<String, Object?> payload;

  const HealthEntry({
    required this.type,
    required this.at,
    required this.payload,
  });
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
  /// [language] entscheidet nur, in welcher Sprache der Grund erklärt wird.
  static Future<PlatformOutcome> connect({
    AppLanguage language = AppLanguage.de,
  }) =>
      AndroidBridge.healthRequestPermissions(language: language);

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

    final known = await _known(runtime, since);
    final planned = plan(
      records,
      knownSourceIds: known.sourceIds,
      knownSleep: known.sleep,
    );

    var nights = 0;
    var days = 0;
    for (final entry in planned.entries) {
      await runtime.recordAt(entry.at, entry.type, payload: entry.payload);
      if (entry.type == EventType.sleepWindow) {
        nights++;
      } else {
        days++;
      }
    }

    return HealthImportResult(
      sleepNights: nights,
      stepDays: days,
      skipped: planned.skipped,
    );
  }

  /// Was aus den Datensaetzen wird — ohne Geraet, ohne Datenbank.
  ///
  /// Uebersprungen wird aus zwei Gruenden, und beide sind derselbe Gedanke:
  /// Ein Ereignis, das schon da ist, darf nicht zweimal in einen
  /// append-only-Strom.
  ///
  /// 1. Die Quell-ID ist schon bekannt — ein zweiter Import derselben
  ///    Aufzeichnung.
  /// 2. **Das Schlaffenster ueberlappt ein bereits erfasstes.** Uhr und
  ///    Herstellerapp schreiben dieselbe Nacht mit verschiedenen Quell-IDs;
  ///    ueber die ID allein war das nicht zu erkennen. Die Nacht landete
  ///    zweimal im Strom, verdoppelte die Schlafschuld und zaehlte in der
  ///    Baseline als zwei Naechte.
  static ({List<HealthEntry> entries, int skipped}) plan(
    List<Map<String, Object?>> records, {
    Set<String> knownSourceIds = const {},
    List<SleepWindow> knownSleep = const [],
  }) {
    final seen = {...knownSourceIds};
    final sleepSoFar = [...knownSleep];
    final entries = <HealthEntry>[];
    var skipped = 0;

    for (final record in records) {
      final sourceId = record['sourceId'] as String?;
      if (sourceId == null) continue;
      if (seen.contains(sourceId)) {
        skipped++;
        continue;
      }

      final start = _millis(record['startMillis']);
      final end = _millis(record['endMillis']);
      if (start == null || end == null) continue;

      switch (record['kind']) {
        case 'sleep':
          if (!end.isAfter(start)) continue;
          if (sleepSoFar
              .any((w) => start.isBefore(w.to) && end.isAfter(w.from))) {
            skipped++;
            continue;
          }
          sleepSoFar.add((from: start, to: end));
          seen.add(sourceId);
          entries.add(HealthEntry(
            type: EventType.sleepWindow,
            at: end,
            payload: {
              'bed_at': start.toUtc().toIso8601String(),
              'wake_at': end.toUtc().toIso8601String(),
              'duration_min': end.difference(start).inMinutes,
              // Keine Qualitaetsangabe erfinden: Health Connect liefert
              // Phasen, aber keine Bewertung, und eine geratene Zahl waere
              // in der Herleitung nicht von einer gemessenen zu
              // unterscheiden.
              //
              // Aus demselben Grund steht hier kein `est_debt_min` mehr.
              // Vorher wurde jeder Datensatz gegen sieben Stunden Soll
              // gerechnet — Health Connect legt aber jede Schlafphase
              // einzeln ab, ein halbstuendiges Nickerchen trug so 390
              // Minuten Schuld bei, obwohl es Schlaf ist. Schuld entsteht
              // jetzt dort, wo alle Naechte zusammen sichtbar sind
              // (SignalAggregator); hier stehen nur Messwerte. Genau das
              // sagt der Dateikopf zu: Diese Datei rechnet nicht.
              'source_id': sourceId,
              'via': 'health_connect',
            },
          ));

        case 'steps':
          final count = (record['count'] as num?)?.round();
          if (count == null) continue;
          seen.add(sourceId);
          entries.add(HealthEntry(
            type: EventType.healthSample,
            at: end,
            payload: {
              'metric': 'steps',
              'value': count,
              'from': start.toUtc().toIso8601String(),
              'to': end.toUtc().toIso8601String(),
              'source_id': sourceId,
              'via': 'health_connect',
            },
          ));
      }
    }

    return (entries: entries, skipped: skipped);
  }

  /// Was schon im Strom steht: Quell-IDs und gemessene Schlaffenster.
  ///
  /// Die Fenster kommen bewusst aus dem Ereignisstrom und nicht nur aus dem
  /// Import — so faellt auch eine von Hand eingetragene Nacht auf, die
  /// Health Connect spaeter noch einmal liefert.
  static Future<({Set<String> sourceIds, List<SleepWindow> sleep})> _known(
    AxiomRuntime runtime,
    DateTime since,
  ) async {
    // Etwas Vorlauf, weil ein Schlaffenster am Rand des Zeitraums liegen kann.
    final events = await runtime.store.query(
      from: since.subtract(const Duration(days: 2)),
      types: {EventType.sleepWindow, EventType.healthSample},
    );
    final sourceIds = <String>{};
    final sleep = <SleepWindow>[];
    for (final event in events) {
      final id = event.payload['source_id'];
      if (id is String) sourceIds.add(id);
      if (event.type != EventType.sleepWindow) continue;
      final from = _parseUtc(event.payload['bed_at']);
      final to = _parseUtc(event.payload['wake_at']);
      if (from != null && to != null && to.isAfter(from)) {
        sleep.add((from: from, to: to));
      }
    }
    return (sourceIds: sourceIds, sleep: sleep);
  }

  static DateTime? _parseUtc(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;

  static DateTime? _millis(Object? value) {
    final ms = (value as num?)?.toInt();
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }
}
