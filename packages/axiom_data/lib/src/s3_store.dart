/// Persistenz für Stufe 3: Fokus, Reizkanäle, Impuls-Trigger, Load-Zustand.
///
/// Als Erweiterung des EventStore, damit alles in einer Datenbank und einer
/// Transaktionsgrenze bleibt. Die Trennung ist nur eine der Datei.
library;

import 'dart:convert';

import 'package:axiom_core/axiom_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'sqlite_event_store.dart';

extension S3Store on SqliteEventStore {
  Database get _db => rawDatabase;

  // ── M4 Fokus ──────────────────────────────────────────────────────────

  Future<void> startFocus(FocusSession session) async {
    _db.execute(
      'INSERT INTO focus_sessions (id, started_at, anchor_task_id, '
      'anchor_title, planned_min) VALUES (?,?,?,?,?)',
      [
        session.id,
        session.startedAt.millisecondsSinceEpoch,
        session.anchorTaskId,
        session.anchorTitle,
        session.planned.inMinutes,
      ],
    );
  }

  Future<void> endFocus(
    String id, {
    required DateTime at,
    String? breadcrumb,
    String exitKind = 'planned',
  }) async {
    _db.execute(
      'UPDATE focus_sessions SET ended_at = ?, breadcrumb = ?, exit_kind = ? '
      'WHERE id = ?',
      [at.millisecondsSinceEpoch, breadcrumb, exitKind, id],
    );
  }

  /// Die laufende Sitzung, falls es eine gibt.
  Future<FocusSession?> activeFocus() async {
    final rows = _db.select(
      'SELECT * FROM focus_sessions WHERE ended_at IS NULL '
      'ORDER BY started_at DESC LIMIT 1',
    );
    return rows.isEmpty ? null : _toSession(rows.first);
  }

  /// Fokusminuten des lokalen Tages — Grundlage des Reiz-Guthabens.
  ///
  /// Gezählt wird die **Überschneidung** mit dem Tag, nicht die Sitzung nach
  /// ihrem Beginn. Vorher stand hier `WHERE started_at >= dayStart` und die
  /// volle Sitzungsdauer: Eine Sitzung von 23:30 bis 01:00 zählte mit
  /// neunzig Minuten auf den Vortag und mit null auf den Tag, an dem
  /// sechzig davon lagen. Für einen Nachtarbeiter war das Reiz-Guthaben
  /// damit systematisch am falschen Tag [D8] — und ausgerechnet die
  /// Sitzungen, die über Mitternacht gehen, sind die, nach denen es gebraucht
  /// wird.
  Future<int> focusMinutesToday(DateTime localNow) async {
    final dayStart =
        DateTime(localNow.year, localNow.month, localNow.day)
            .millisecondsSinceEpoch;
    final dayEnd = DateTime(localNow.year, localNow.month, localNow.day + 1)
        .millisecondsSinceEpoch;
    // Alles, was den Tag berührt: vor Tagesende begonnen und nach
    // Tagesbeginn beendet — oder noch offen.
    final rows = _db.select(
      'SELECT started_at, ended_at FROM focus_sessions '
      'WHERE started_at < ? AND (ended_at IS NULL OR ended_at > ?)',
      [dayEnd, dayStart],
    );
    var total = 0;
    for (final row in rows) {
      final started = row['started_at'] as int;
      // Eine offene Sitzung zählt bis jetzt, nicht bis Tagesende: Was noch
      // nicht passiert ist, ist kein Guthaben.
      final ended = (row['ended_at'] as int?) ?? localNow.millisecondsSinceEpoch;
      final from = started < dayStart ? dayStart : started;
      final to = ended > dayEnd ? dayEnd : ended;
      if (to > from) total += ((to - from) / 60000).round();
    }
    return total;
  }

  /// Wiedereinstiegsnotiz der letzten beendeten Sitzung [D11].
  Future<String?> lastBreadcrumb() async {
    final rows = _db.select(
      'SELECT breadcrumb FROM focus_sessions WHERE breadcrumb IS NOT NULL '
      'AND ended_at IS NOT NULL ORDER BY ended_at DESC LIMIT 1',
    );
    return rows.isEmpty ? null : rows.first['breadcrumb'] as String?;
  }

  FocusSession _toSession(Row r) => FocusSession(
        id: r['id'] as String,
        startedAt:
            DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int),
        anchorTaskId: r['anchor_task_id'] as String?,
        anchorTitle: r['anchor_title'] as String?,
        planned: Duration(minutes: r['planned_min'] as int),
        breadcrumb: r['breadcrumb'] as String?,
      );

  // ── M5 Reizkanäle ─────────────────────────────────────────────────────

  Future<void> upsertChannel(SensationChannel channel, {int order = 0}) async {
    _db.execute(
      'INSERT INTO sensation_channels (id, label, intensity, typical_min, '
      'has_cost, sort_order) VALUES (?,?,?,?,?,?) '
      'ON CONFLICT(id) DO UPDATE SET label=excluded.label, '
      'intensity=excluded.intensity, typical_min=excluded.typical_min, '
      'has_cost=excluded.has_cost',
      [
        channel.id,
        channel.label,
        channel.intensity,
        channel.typical.inMinutes,
        channel.hasCost ? 1 : 0,
        order,
      ],
    );
  }

  Future<List<SensationChannel>> channels() async {
    final rows = _db.select(
      'SELECT * FROM sensation_channels ORDER BY sort_order, intensity DESC',
    );
    return rows
        .map((r) => SensationChannel(
              id: r['id'] as String,
              label: r['label'] as String,
              intensity: r['intensity'] as int,
              typical: Duration(minutes: r['typical_min'] as int),
              hasCost: (r['has_cost'] as int) == 1,
            ))
        .toList();
  }

  Future<void> deleteChannel(String id) async {
    _db.execute('DELETE FROM sensation_channels WHERE id = ?', [id]);
  }

  /// Legt die Voreinstellung an — nur beim ersten Start.
  Future<void> seedChannelsIfEmpty() async {
    if ((await channels()).isNotEmpty) return;
    for (final (index, channel) in kDefaultChannels.indexed) {
      await upsertChannel(channel, order: index);
    }
  }

  /// Reiz-Slots aus dem Ereignisstrom, für den Haushalt.
  Future<List<SensationSlot>> slotsSince(DateTime from) async {
    final events = await query(from: from, types: {EventType.sensationSlot});
    return events
        .map((e) => SensationSlot(
              id: e.id,
              channelId: e.payload['channel'] as String? ?? 'unknown',
              channelLabel: e.payload['label'] as String? ?? 'Slot',
              intensity: (e.payload['intensity'] as num?)?.toInt() ?? 3,
              at: e.at.toLocal(),
              duration:
                  Duration(minutes: (e.payload['duration_min'] as num?)?.toInt() ?? 30),
              planned: e.payload['planned'] == true,
            ))
        .toList();
  }

  // ── M6 Impuls-Trigger ─────────────────────────────────────────────────

  Future<void> upsertTrigger(InterceptTrigger trigger) async {
    _db.execute(
      'INSERT INTO intercept_triggers (id, label, cooldown_min, release_at, '
      'checklist, authorized) VALUES (?,?,?,?,?,?) '
      'ON CONFLICT(id) DO UPDATE SET label=excluded.label, '
      'cooldown_min=excluded.cooldown_min, release_at=excluded.release_at, '
      'checklist=excluded.checklist, authorized=excluded.authorized',
      [
        trigger.id,
        trigger.label,
        trigger.cooldown.inMinutes,
        trigger.releaseAt,
        jsonEncode(trigger.checklist),
        trigger.authorized ? 1 : 0,
      ],
    );
  }

  Future<List<InterceptTrigger>> triggers() async {
    final rows = _db.select(
      'SELECT * FROM intercept_triggers WHERE archived = 0 ORDER BY label',
    );
    return rows
        .map((r) => InterceptTrigger(
              id: r['id'] as String,
              label: r['label'] as String,
              cooldown: Duration(minutes: r['cooldown_min'] as int),
              releaseAt: r['release_at'] as String?,
              checklist: (jsonDecode(r['checklist'] as String) as List)
                  .cast<String>(),
              authorized: (r['authorized'] as int) == 1,
            ))
        .toList();
  }

  Future<void> archiveTrigger(String id) async {
    _db.execute('UPDATE intercept_triggers SET archived = 1 WHERE id = ?', [id]);
  }

  Future<void> saveRun(InterceptRun run) async {
    _db.execute(
      'INSERT INTO intercept_runs (id, trigger_id, trigger_label, started_at, '
      'releases_at, answers, outcome, note) VALUES (?,?,?,?,?,?,?,?) '
      'ON CONFLICT(id) DO UPDATE SET answers=excluded.answers, '
      'outcome=excluded.outcome, note=excluded.note',
      [
        run.id,
        run.triggerId,
        run.triggerLabel,
        run.startedAt.millisecondsSinceEpoch,
        run.releasesAt.millisecondsSinceEpoch,
        jsonEncode(run.answers),
        run.outcome.name,
        run.note,
      ],
    );
  }

  Future<InterceptRun?> activeRun(DateTime now) async {
    final rows = _db.select(
      "SELECT * FROM intercept_runs WHERE outcome = 'pending' "
      'ORDER BY started_at DESC LIMIT 1',
    );
    return rows.isEmpty ? null : _toRun(rows.first);
  }

  Future<List<InterceptRun>> runsSince(DateTime from) async {
    final rows = _db.select(
      'SELECT * FROM intercept_runs WHERE started_at >= ? '
      'ORDER BY started_at DESC',
      [from.millisecondsSinceEpoch],
    );
    return rows.map(_toRun).toList();
  }

  Future<List<InterceptStats>> interceptStats({required DateTime since}) async {
    final rows = _db.select('''
      SELECT trigger_id,
             COUNT(*) AS started,
             SUM(CASE WHEN outcome = 'aborted'   THEN 1 ELSE 0 END) AS aborted,
             SUM(CASE WHEN outcome = 'proceeded' THEN 1 ELSE 0 END) AS proceeded
      FROM intercept_runs WHERE started_at >= ?
      GROUP BY trigger_id ORDER BY trigger_id
    ''', [since.millisecondsSinceEpoch]);
    return rows
        .map((r) => InterceptStats(
              triggerId: r['trigger_id'] as String,
              started: r['started'] as int,
              aborted: r['aborted'] as int,
              proceeded: r['proceeded'] as int,
            ))
        .toList();
  }

  InterceptRun _toRun(Row r) => InterceptRun(
        id: r['id'] as String,
        triggerId: r['trigger_id'] as String,
        triggerLabel: r['trigger_label'] as String,
        startedAt:
            DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int),
        releasesAt:
            DateTime.fromMillisecondsSinceEpoch(r['releases_at'] as int),
        answers: (jsonDecode(r['answers'] as String) as List).cast<bool>(),
        outcome: InterceptOutcome.values
            .firstWhere((o) => o.name == r['outcome'],
                orElse: () => InterceptOutcome.pending),
        note: r['note'] as String?,
      );

  // ── M9 Load-Zustand ───────────────────────────────────────────────────

  /// Die geltende Stufe und seit wann.
  ///
  /// Wird persistiert, weil die Haltezeit sonst bei jedem App-Start neu
  /// beginnen würde — und ein Erhaltungsmodus, den ein Neustart beendet,
  /// ist keiner.
  ({LoadLevel level, DateTime since})? loadState() {
    final rows = _db.select('SELECT level, since FROM load_state WHERE id = 1');
    if (rows.isEmpty) return null;
    final name = rows.first['level'] as String;
    return (
      level: LoadLevel.values.firstWhere((l) => l.name == name,
          orElse: () => LoadLevel.l0),
      since: DateTime.fromMillisecondsSinceEpoch(rows.first['since'] as int),
    );
  }

  void setLoadState(LoadLevel level, DateTime since) {
    _db.execute(
      'INSERT INTO load_state (id, level, since) VALUES (1, ?, ?) '
      'ON CONFLICT(id) DO UPDATE SET level = excluded.level, '
      'since = excluded.since',
      [level.name, since.millisecondsSinceEpoch],
    );
  }
}
