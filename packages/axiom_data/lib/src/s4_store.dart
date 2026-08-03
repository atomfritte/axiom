/// Persistenz für Stufe 4: Nachbetrachtungen und Wirkfenster.
///
/// Vorfälle selbst liegen als Events im Strom — sie sind unveränderlich.
/// Die Nachbetrachtung bekommt eine eigene Tabelle, weil sie später entsteht
/// und ergänzt wird.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'sqlite_event_store.dart';

extension S4Store on SqliteEventStore {
  Database get _db => rawDatabase;

  // ── M10 Signal-Log ────────────────────────────────────────────────────

  /// Vorfälle aus dem Ereignisstrom.
  Future<List<SignalIncident>> incidentsSince(DateTime from) async {
    final events = await query(from: from, types: {EventType.signalIncident});
    return events
        .map((e) => SignalIncident(
              id: e.id,
              at: e.at.toLocal(),
              intensity: (e.payload['intensity'] as num?)?.toInt() ?? 3,
              triggerClass: TriggerClass.values.firstWhere(
                (t) => t.name == e.payload['trigger_class'],
                orElse: () => TriggerClass.unclear,
              ),
              note: e.payload['note'] as String?,
            ))
        .toList();
  }

  Future<void> savePostMortem(PostMortem review) async {
    _db.execute(
      'INSERT INTO post_mortems (incident_id, at, root_cause, counter, '
      'hindsight) VALUES (?,?,?,?,?) '
      'ON CONFLICT(incident_id) DO UPDATE SET root_cause=excluded.root_cause, '
      'counter=excluded.counter, hindsight=excluded.hindsight',
      [
        review.incidentId,
        review.at.millisecondsSinceEpoch,
        review.rootCause,
        review.countermeasure,
        review.intensityInHindsight,
      ],
    );
  }

  Future<List<PostMortem>> postMortems() async => _db
      .select('SELECT * FROM post_mortems ORDER BY at DESC')
      .map((r) => PostMortem(
            incidentId: r['incident_id'] as String,
            at: DateTime.fromMillisecondsSinceEpoch(r['at'] as int),
            rootCause: r['root_cause'] as String?,
            countermeasure: r['counter'] as String?,
            intensityInHindsight: r['hindsight'] as int?,
          ))
      .toList();

  Future<Set<String>> reviewedIncidentIds() async => _db
      .select('SELECT incident_id FROM post_mortems')
      .map((r) => r['incident_id'] as String)
      .toSet();

  // ── M13 Wirkfenster ───────────────────────────────────────────────────

  /// Ist das Modul eingeschaltet? Standardmäßig nein.
  bool get medEnabled => setting('med_enabled') == 'true';
  set medEnabled(bool value) => setSetting('med_enabled', '$value');

  Future<void> saveMedEntry(MedEntry entry) async {
    _db.execute(
      'INSERT INTO med_entries (id, label, dose, taken_at, onset_min, dur_min) '
      'VALUES (?,?,?,?,?,?) '
      'ON CONFLICT(id) DO UPDATE SET label=excluded.label, dose=excluded.dose, '
      'taken_at=excluded.taken_at, onset_min=excluded.onset_min, '
      'dur_min=excluded.dur_min',
      [
        entry.id,
        entry.label,
        entry.dose,
        entry.takenAt.millisecondsSinceEpoch,
        entry.onset.inMinutes,
        entry.duration.inMinutes,
      ],
    );
  }

  Future<List<MedEntry>> medEntriesSince(DateTime from) async => _db
      .select(
        'SELECT * FROM med_entries WHERE taken_at >= ? ORDER BY taken_at DESC',
        [from.millisecondsSinceEpoch],
      )
      .map((r) => MedEntry(
            id: r['id'] as String,
            label: r['label'] as String,
            dose: r['dose'] as String?,
            takenAt:
                DateTime.fromMillisecondsSinceEpoch(r['taken_at'] as int),
            onset: Duration(minutes: r['onset_min'] as int),
            duration: Duration(minutes: r['dur_min'] as int),
          ))
      .toList();

  Future<void> deleteMedEntry(String id) async {
    _db.execute('DELETE FROM med_entries WHERE id = ?', [id]);
  }

  /// Zuletzt genutzte Bezeichnung und Fenster — als Vorbelegung beim
  /// nächsten Eintrag. Wiederholtes Tippen derselben Angaben ist genau die
  /// Reibung, an der die Erfassung stirbt.
  Future<MedEntry?> lastMedEntry() async {
    final rows = _db.select(
      'SELECT * FROM med_entries ORDER BY taken_at DESC LIMIT 1',
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return MedEntry(
      id: r['id'] as String,
      label: r['label'] as String,
      dose: r['dose'] as String?,
      takenAt: DateTime.fromMillisecondsSinceEpoch(r['taken_at'] as int),
      onset: Duration(minutes: r['onset_min'] as int),
      duration: Duration(minutes: r['dur_min'] as int),
    );
  }
}
