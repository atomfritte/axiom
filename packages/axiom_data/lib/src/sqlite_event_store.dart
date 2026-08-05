/// SQLite-EventStore. Append-only, optional verschluesselt.
///
/// Die Projektionstabellen sind jederzeit verwerfbar: `rebuildProjections()`
/// baut sie vollstaendig aus `events` neu auf. Das ist ein Testfall, keine
/// Absichtserklaerung (docs/03-DATENMODELL.md §6).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:axiom_core/axiom_core.dart';
import 'package:sqlite3/sqlite3.dart';

/// Aktuelle Schemaversion. Migrationen sind vorwaertsgerichtet.
///
/// v2: `events.seq` als monotone Einfuegereihenfolge. Ohne sie war die
///     Rueckgabereihenfolge zweier Events mit identischem Zeitstempel durch
///     den Zufallsanteil der ULID bestimmt — beim Rebuild konnte
///     `task_completed` vor `task_created` einsortiert werden und der
///     wiederhergestellte Zustand wich vom Original ab.
/// v3: `anchors` — Zeitanker mit Rückwärtsverkettung (M3).
/// v4: `focus_sessions`, `sensation_channels`, `intercept_triggers`,
///     `intercept_runs`, `load_state` — Stufe 3.
/// v5: `post_mortems`, `med_entries` — Stufe 4. Vorfaelle selbst liegen
///     als Events, die Nachbetrachtung braucht eine eigene Tabelle, weil
///     sie spaeter entsteht und ergaenzt wird.
/// v6: `rule_overrides` — im Geraet bearbeitete Regeln.
/// v7: `tasks.place` — Ortsbindung als frei vergebener Name. Der aktuelle
///     Ort selbst braucht keine Spalte: Er ist die Projektion des letzten
///     `place_entered`-Events.
/// v8: `trusted_browsers` — von Hand freigegebene Browser, als Hash.
/// v9: `task_links` — „A blockiert B". Eigene Tabelle statt Spalte in
///     `tasks`: Die Beziehung gehoert keiner der beiden Aufgaben, und ein
///     Listenfeld muesste jede Abfrage mitladen.
const int kSchemaVersion = 9;

/// Die Datei ist da, laesst sich aber nicht lesen.
///
/// Bedeutet fast immer: Der Schluessel passt nicht. Entweder liegt dort noch
/// eine unverschluesselte Datenbank aus einer frueheren Fassung, oder der
/// Schluessel im Geraetespeicher ist ein anderer geworden — nach geloeschten
/// App-Daten, einem zurueckgespielten Backup, einem Geraetewechsel.
///
/// Absichtlich ein eigener Typ und keine `SqliteException`: Der Aufrufer soll
/// genau diesen Fall behandeln koennen, ohne jede Datenbankstoerung
/// mitzufangen.
final class DatabaseUnreadable implements Exception {
  final String path;
  final Object cause;

  const DatabaseUnreadable(this.path, this.cause);

  @override
  String toString() => 'DatabaseUnreadable($path): $cause';
}

final class SqliteEventStore implements EventStore {
  final Database _db;
  final Clock _clock;

  /// Wo die Datei liegt, oder `null` bei einer Datenbank im Arbeitsspeicher.
  /// Gebraucht von [isEncrypted], das die Datei selbst befragt.
  final String? _path;

  SqliteEventStore._(this._db, this._clock, this._path);

  /// Oeffnet oder erstellt die Datenbank.
  ///
  /// [encryptionKey] setzt `PRAGMA key`. Die ausgelieferte SQLite-Fassung ist
  /// SQLite3MultipleCiphers (siehe `pubspec.yaml`), Standardchiffre
  /// ChaCha20-Poly1305.
  ///
  /// **Passt der Schluessel nicht, fliegt [DatabaseUnreadable].** Das ist der
  /// Fall bei einer unverschluesselten Altdatei, bei einem verlorenen
  /// Keystore-Schluessel und bei einer fremden Datei. Weiterlaufen liesse sich
  /// hier nicht sinnvoll: Die Datei ist da und ist unlesbar. Was daraus folgt
  /// — neu anlegen oder abbrechen — entscheidet der Aufrufer, nicht diese
  /// Schicht. Eine Speicherschicht, die von sich aus Daten wegwirft, waere
  /// das Letzte, was man ihr zutrauen moechte.
  factory SqliteEventStore.open(
    String path, {
    required Clock clock,
    String? encryptionKey,
  }) {
    final db = sqlite3.open(path);
    if (encryptionKey != null && encryptionKey.isNotEmpty) {
      db.execute("PRAGMA key = '${encryptionKey.replaceAll("'", "''")}';");
    }

    // Der erste echte Zugriff. Vorher steht nur fest, dass sich eine Datei
    // oeffnen liess — ob sie sich auch *lesen* laesst, zeigt sich erst hier:
    // Bei falschem Schluessel ist schon die Kopfzeile Rauschen.
    try {
      db.select('PRAGMA user_version;');
    } on SqliteException catch (e) {
      db.close();
      throw DatabaseUnreadable(path, e);
    }

    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA foreign_keys = ON;');
    final store = SqliteEventStore._(db, clock, path == ':memory:' ? null : path);
    store._migrate();
    return store;
  }

  factory SqliteEventStore.inMemory({required Clock clock}) =>
      SqliteEventStore.open(':memory:', clock: clock);

  /// Zugriff fuer Erweiterungen in dieser Bibliothek (s3_store.dart).
  ///
  /// Bewusst nicht oeffentlich gedacht: Der EventStore bleibt die
  /// Schnittstelle, die Erweiterung teilt sich nur seine Verbindung, damit
  /// alles in einer Transaktionsgrenze liegt.
  Database get rawDatabase => _db;

  /// Ob die Datei auf der Platte ohne Schluessel lesbar waere.
  ///
  /// **Gefragt wird die Datei, nicht die Verbindung.** Zwei Anlaeufe davor
  /// waren falsch: `PRAGMA cipher_version` kennt nur SQLCipher und antwortet
  /// unter SQLite3MultipleCiphers gar nicht; `PRAGMA cipher` antwortet immer
  /// mit `chacha20`, weil es die *voreingestellte* Chiffre nennt und nicht den
  /// Zustand dieser Datei. Beide haetten im Systeminspektor eine Zusicherung
  /// angezeigt, die von der Wirklichkeit unabhaengig war — schlimmer als gar
  /// keine Anzeige.
  ///
  /// Eine unverschluesselte SQLite-Datei beginnt mit `SQLite format 3\0`. Das
  /// steht so im Dateiformat und gilt unabhaengig davon, welche Bibliothek
  /// gerade eingebunden ist. Fehlt die Kennung, ist der Anfang der Datei
  /// Chiffrat.
  ///
  /// Eine Datenbank im Arbeitsspeicher meldet `false`: Sie liegt nirgends,
  /// also ist auch nichts geschuetzt.
  bool get isEncrypted {
    final path = _path;
    if (path == null) return false;
    try {
      final handle = File(path).openSync();
      try {
        final head = handle.readSync(_plainHeader.length);
        if (head.length < _plainHeader.length) return false;
        for (var i = 0; i < _plainHeader.length; i++) {
          if (head[i] != _plainHeader[i]) return true;
        }
        return false;
      } finally {
        handle.closeSync();
      }
    } on FileSystemException {
      return false;
    }
  }

  static const _plainHeader = <int>[
    0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66, //
    0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00, // "SQLite format 3\0"
  ];

  void _migrate() {
    final current = _db.select('PRAGMA user_version;').first.values.first as int;

    // Eine Datei aus einer neueren Fassung. Das passiert beim Zurueckspielen
    // eines Backups oder nach einer Installation der vorherigen APK.
    //
    // Weiterlaufen waere hier der teurere Weg: Die Projektionen wuerden
    // gegen ein Schema rechnen, das sie nicht kennen, und das Ergebnis waere
    // still falsch statt laut kaputt. In einem regelbasierten System ist
    // eine stumm falsche Zahl schlimmer als ein Abbruch (CLAUDE.md).
    if (current > kSchemaVersion) {
      throw StateError(
        'Diese Datenbank stammt aus einer neueren Fassung von AXIOM '
        '(Schema $current, diese Fassung kennt $kSchemaVersion). '
        'Aktualisiere die App, statt die Daten zu riskieren.',
      );
    }

    if (current == kSchemaVersion) return;

    if (current < 1) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS events (
          id            TEXT PRIMARY KEY,
          seq           INTEGER,
          at            INTEGER NOT NULL,
          type          TEXT    NOT NULL,
          source        TEXT    NOT NULL,
          payload       TEXT    NOT NULL,
          correction_of TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_events_at   ON events(at);
        CREATE INDEX IF NOT EXISTS idx_events_type ON events(type, at);

        CREATE TABLE IF NOT EXISTS tasks (
          id        TEXT PRIMARY KEY,
          title     TEXT    NOT NULL,
          ae        INTEGER NOT NULL,
          salience  INTEGER NOT NULL,
          stakes    INTEGER NOT NULL,
          decay_at  INTEGER,
          state     TEXT    NOT NULL,
          parent_id TEXT,
          contexts  TEXT    NOT NULL DEFAULT '',
          breadcrumb TEXT,
          created_at INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_tasks_state ON tasks(state);

        CREATE TABLE IF NOT EXISTS decisions (
          id                TEXT PRIMARY KEY,
          at                INTEGER NOT NULL,
          rule_id           TEXT    NOT NULL,
          action            TEXT    NOT NULL,
          explanation       TEXT    NOT NULL,
          state_snapshot_id TEXT    NOT NULL,
          suppressed        INTEGER NOT NULL DEFAULT 0,
          response          TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_decisions_rule ON decisions(rule_id, at);

        CREATE TABLE IF NOT EXISTS usage_log (
          id         TEXT PRIMARY KEY,
          at         INTEGER NOT NULL,
          screen     TEXT    NOT NULL,
          duration_s INTEGER NOT NULL,
          counts     INTEGER NOT NULL DEFAULT 1
        );
        CREATE INDEX IF NOT EXISTS idx_usage_at ON usage_log(at);

        CREATE TABLE IF NOT EXISTS settings (
          key   TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
      ''');
    }

    if (current < 2) {
      // Bestandsdatenbanken nachruesten. Vorhandene Zeilen bekommen ihre
      // bisherige rowid als Sequenz — das ist genau die Einfuegereihenfolge.
      final columns = _db
          .select('PRAGMA table_info(events);')
          .map((r) => r['name'] as String)
          .toSet();
      if (!columns.contains('seq')) {
        _db.execute('ALTER TABLE events ADD COLUMN seq INTEGER;');
      }
      _db.execute('UPDATE events SET seq = rowid WHERE seq IS NULL;');
      _db.execute(
          'CREATE INDEX IF NOT EXISTS idx_events_seq ON events(at, seq);');
    }

    if (current < 3) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS anchors (
          id             TEXT PRIMARY KEY,
          title          TEXT    NOT NULL,
          arrive_by      INTEGER NOT NULL,
          travel_min     INTEGER NOT NULL DEFAULT 0,
          prepare_min    INTEGER NOT NULL DEFAULT 15,
          buffer_min     INTEGER NOT NULL DEFAULT 10,
          context_min    INTEGER NOT NULL DEFAULT 10,
          location       TEXT,
          source         TEXT    NOT NULL DEFAULT 'manual',
          external_id    TEXT,
          dismissed      INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_anchors_at ON anchors(arrive_by);
        CREATE UNIQUE INDEX IF NOT EXISTS idx_anchors_ext
          ON anchors(external_id) WHERE external_id IS NOT NULL;
      ''');
    }

    if (current < 4) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS focus_sessions (
          id            TEXT PRIMARY KEY,
          started_at    INTEGER NOT NULL,
          ended_at      INTEGER,
          anchor_task_id TEXT,
          anchor_title  TEXT,
          planned_min   INTEGER NOT NULL DEFAULT 50,
          breadcrumb    TEXT,
          exit_kind     TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_focus_started
          ON focus_sessions(started_at);

        CREATE TABLE IF NOT EXISTS sensation_channels (
          id          TEXT PRIMARY KEY,
          label       TEXT    NOT NULL,
          intensity   INTEGER NOT NULL,
          typical_min INTEGER NOT NULL DEFAULT 30,
          has_cost    INTEGER NOT NULL DEFAULT 0,
          sort_order  INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS intercept_triggers (
          id           TEXT PRIMARY KEY,
          label        TEXT    NOT NULL,
          cooldown_min INTEGER NOT NULL DEFAULT 15,
          release_at   TEXT,
          checklist    TEXT    NOT NULL DEFAULT '[]',
          authorized   INTEGER NOT NULL DEFAULT 0,
          archived     INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS intercept_runs (
          id            TEXT PRIMARY KEY,
          trigger_id    TEXT    NOT NULL,
          trigger_label TEXT    NOT NULL,
          started_at    INTEGER NOT NULL,
          releases_at   INTEGER NOT NULL,
          answers       TEXT    NOT NULL DEFAULT '[]',
          outcome       TEXT    NOT NULL DEFAULT 'pending',
          note          TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_runs_trigger
          ON intercept_runs(trigger_id, started_at);

        CREATE TABLE IF NOT EXISTS load_state (
          id    INTEGER PRIMARY KEY CHECK (id = 1),
          level TEXT    NOT NULL,
          since INTEGER NOT NULL
        );
      ''');
    }

    if (current < 5) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS post_mortems (
          incident_id TEXT PRIMARY KEY,
          at          INTEGER NOT NULL,
          root_cause  TEXT,
          counter     TEXT,
          hindsight   INTEGER
        );

        CREATE TABLE IF NOT EXISTS med_entries (
          id        TEXT PRIMARY KEY,
          label     TEXT    NOT NULL,
          dose      TEXT,
          taken_at  INTEGER NOT NULL,
          onset_min INTEGER NOT NULL DEFAULT 0,
          dur_min   INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_med_taken ON med_entries(taken_at);
      ''');
    }

    // Eigener Block, nicht am Ende von v5 angehaengt.
    //
    // Genau daran ist es schon einmal gescheitert: Die Tabelle stand im
    // `current < 5`-Zweig, `kSchemaVersion` stand aber auf 6. Eine
    // Bestandsdatenbank auf Stand 5 lief an dem Zweig vorbei, bekam die
    // Tabelle nie — und wurde anschliessend als Stand 6 markiert. Der
    // Regeleditor brach dann auf einem Geraet, auf dem alles frisch
    // installiert funktionierte.
    if (current < 6) {
      _db.execute('''
        -- Im Geraet bearbeitete Regeln.
        --
        -- Overlay-Semantik wie rules/personal: gleiche ID ueberschreibt die
        -- mitgelieferte Regel vollstaendig, neue ID kommt additiv dazu. Die
        -- Assets bleiben unberuehrt — auf dem Telefon sind sie ohnehin nur
        -- lesbar, und ein Regelwerk, das sich selbst ueberschreibt, waere
        -- nicht mehr mit dem Stand in Git vergleichbar.
        --
        -- `yaml` ist die Wahrheit, nicht eine Spalte je Feld: So laesst sich
        -- eine bearbeitete Regel unveraendert nach rules/ zurueckkopieren.
        CREATE TABLE IF NOT EXISTS rule_overrides (
          id           TEXT PRIMARY KEY,
          yaml         TEXT    NOT NULL,
          updated_at   INTEGER NOT NULL,
          -- Bis wann die Regel stumm mitlaeuft. Jede neue oder inhaltlich
          -- geaenderte Regel bekommt sieben Tage (CLAUDE.md).
          shadow_until INTEGER,
          -- Ob es eine mitgelieferte Regel ueberschreibt. Bestimmt, ob
          -- "zuruecksetzen" etwas wiederherstellt oder loescht.
          overrides    INTEGER NOT NULL DEFAULT 0
        );
      ''');
    }

    // Ortsbindung. Eigener Block, wie jede Version davor.
    //
    // `ALTER TABLE` statt Neuanlage: Eine Bestandsdatenbank hat `tasks`
    // laengst, und die Spaltenpruefung davor ist noetig, weil ein frisch
    // erstelltes Schema den Block ebenfalls durchlaeuft (current = 0).
    if (current < 7) {
      final columns = _db
          .select('PRAGMA table_info(tasks);')
          .map((r) => r['name'] as String)
          .toSet();
      if (!columns.contains('place')) {
        _db.execute('ALTER TABLE tasks ADD COLUMN place TEXT;');
      }
    }

    if (current < 8) {
      // Browser, die einmal von Hand freigegeben wurden.
      //
      // **Warum nur der Hash.** Wer diese Datei in die Hand bekommt, hat
      // ohnehin die Gesundheitsdaten — aber er soll damit nicht auch noch
      // den Schluessel bekommen, mit dem sich ein Browser kuenftig
      // anmeldet. Gespeichert wird deshalb SHA-256 des Merkzeichens; das
      // Original steht nur im Cookie des Browsers und existiert auf dem
      // Geraet nirgends.
      //
      // **Warum mit Ablauf.** Eine Freigabe ohne Ende waere eine
      // Entscheidung, an die sich niemand erinnert. Drei Tage sind lang
      // genug fuer eine Arbeitswoche mit Wochenende dazwischen und kurz
      // genug, dass ein vergessener Rechner im Buero von selbst zufaellt.
      _db.execute('''
        CREATE TABLE IF NOT EXISTS trusted_browsers (
          token_hash  TEXT    PRIMARY KEY,
          label       TEXT,
          approved_at INTEGER NOT NULL,
          expires_at  INTEGER NOT NULL,
          last_seen   INTEGER
        );
      ''');
    }

    // Blocker-Beziehungen. Eigener Block, wie jede Version davor.
    //
    // **Warum ohne Fremdschluessel.** `PRAGMA foreign_keys` steht auf ON, und
    // eine Fremdschluesselbedingung waere hier zwar formal richtig, wuerde
    // aber den Wiederaufbau aus dem Ereignisstrom brechen: Dort kommen die
    // Kanten in Ereignisreihenfolge, und beim selektiven Neuaufbau einzelner
    // Projektionen steht `tasks` nicht zwangslaeufig schon. Der Graph
    // uebergeht Verweise ins Leere ohnehin (`TaskLinkGraph.from`) — eine
    // Aufgabe wegen einer verwaisten Kante fuer immer warten zu lassen waere
    // der schlimmere Fehler [D9].
    if (current < 9) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS task_links (
          blocker_id TEXT NOT NULL,
          blocked_id TEXT NOT NULL,
          PRIMARY KEY (blocker_id, blocked_id)
        );
        CREATE INDEX IF NOT EXISTS idx_links_blocked
          ON task_links(blocked_id);
      ''');
    }

    _db.execute('PRAGMA user_version = $kSchemaVersion;');
  }

  // ── Freigegebene Browser ──────────────────────────────────────────────

  /// Merkt sich einen freigegebenen Browser — als Hash, nie im Klartext.
  ///
  /// Der Aufrufer hasht selbst und uebergibt nur [tokenHash]. Der Name des
  /// Parameters ist Absicht: Wer hier versehentlich das Merkzeichen
  /// hineingibt, soll es beim Lesen sehen.
  Future<void> trustBrowser(
    String tokenHash, {
    required DateTime until,
    required DateTime now,
    String? label,
  }) async {
    _db.execute(
      'INSERT INTO trusted_browsers '
      '(token_hash, label, approved_at, expires_at, last_seen) '
      'VALUES (?, ?, ?, ?, ?) '
      'ON CONFLICT(token_hash) DO UPDATE SET '
      'expires_at = excluded.expires_at, last_seen = excluded.last_seen',
      [
        tokenHash,
        label,
        now.toUtc().millisecondsSinceEpoch,
        until.toUtc().millisecondsSinceEpoch,
        now.toUtc().millisecondsSinceEpoch,
      ],
    );
  }

  /// Ist dieser Browser noch freigegeben? Raeumt dabei Abgelaufenes weg.
  ///
  /// Das Aufraeumen haengt bewusst an der Abfrage und nicht an einem
  /// Zeitgeber: Ein Eintrag, der abgelaufen ist, darf nie den Ausschlag
  /// geben — auch dann nicht, wenn seit Wochen niemand aufgeraeumt hat.
  Future<bool> isTrustedBrowser(String tokenHash, DateTime now) async {
    final millis = now.toUtc().millisecondsSinceEpoch;
    _db.execute('DELETE FROM trusted_browsers WHERE expires_at <= ?', [millis]);
    final rows = _db.select(
      'SELECT 1 FROM trusted_browsers WHERE token_hash = ? LIMIT 1',
      [tokenHash],
    );
    if (rows.isEmpty) return false;
    _db.execute(
      'UPDATE trusted_browsers SET last_seen = ? WHERE token_hash = ?',
      [millis, tokenHash],
    );
    return true;
  }

  /// Alle Freigaben zuruecknehmen. Gibt zurueck, wie viele es waren.
  Future<int> forgetTrustedBrowsers() async {
    final count = _db
        .select('SELECT COUNT(*) AS n FROM trusted_browsers')
        .first['n'] as int;
    _db.execute('DELETE FROM trusted_browsers');
    return count;
  }

  /// Wie viele Browser gerade freigegeben sind — fuer die Anzeige.
  Future<int> trustedBrowserCount(DateTime now) async {
    final rows = _db.select(
      'SELECT COUNT(*) AS n FROM trusted_browsers WHERE expires_at > ?',
      [now.toUtc().millisecondsSinceEpoch],
    );
    return rows.first['n'] as int;
  }

  /// Naechste Sequenznummer. Monoton, unabhaengig vom Zeitstempel.
  int _nextSeq() =>
      ((_db.select('SELECT COALESCE(MAX(seq), 0) AS m FROM events').first['m']
              as int) +
          1);

  // ── EventStore ────────────────────────────────────────────────────────

  @override
  Future<void> append(Event event) async {
    _db.execute(
      'INSERT INTO events (id, seq, at, type, source, payload, correction_of) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        event.id,
        _nextSeq(),
        event.at.millisecondsSinceEpoch,
        event.type.name,
        event.source.name,
        jsonEncode(event.payload),
        event.correctionOf,
      ],
    );
  }

  @override
  Future<List<Event>> query({
    DateTime? from,
    DateTime? to,
    Set<EventType>? types,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('at >= ?');
      args.add(from.toUtc().millisecondsSinceEpoch);
    }
    if (to != null) {
      where.add('at < ?');
      args.add(to.toUtc().millisecondsSinceEpoch);
    }
    if (types != null && types.isNotEmpty) {
      where.add('type IN (${List.filled(types.length, '?').join(',')})');
      args.addAll(types.map((t) => t.name));
    }
    final sql = 'SELECT * FROM events'
        '${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'}'
        ' ORDER BY at ASC, seq ASC';
    return _db.select(sql, args).map(_rowToEvent).toList();
  }

  @override
  Future<Event?> last(EventType type) async {
    final rows = _db.select(
      'SELECT * FROM events WHERE type = ? ORDER BY at DESC, seq DESC LIMIT 1',
      [type.name],
    );
    return rows.isEmpty ? null : _rowToEvent(rows.first);
  }

  @override
  Future<int> countSince(EventType type, DateTime since) async {
    final rows = _db.select(
      'SELECT COUNT(*) AS c FROM events WHERE type = ? AND at >= ?',
      [type.name, since.toUtc().millisecondsSinceEpoch],
    );
    return rows.first['c'] as int;
  }

  Event _rowToEvent(Row row) => Event(
        id: row['id'] as String,
        at: DateTime.fromMillisecondsSinceEpoch(row['at'] as int, isUtc: true),
        type: EventType.values.firstWhere((e) => e.name == row['type']),
        source: EventSource.values.firstWhere((e) => e.name == row['source']),
        payload: (jsonDecode(row['payload'] as String) as Map)
            .cast<String, Object?>(),
        correctionOf: row['correction_of'] as String?,
      );

  // ── Tasks (Projektion) ────────────────────────────────────────────────

  Future<void> upsertTask(Task task) async {
    _db.execute(
      'INSERT INTO tasks (id, title, ae, salience, stakes, decay_at, state, '
      'parent_id, contexts, breadcrumb, place, created_at) '
      'VALUES (?,?,?,?,?,?,?,?,?,?,?,?) '
      'ON CONFLICT(id) DO UPDATE SET title=excluded.title, ae=excluded.ae, '
      'salience=excluded.salience, stakes=excluded.stakes, '
      'decay_at=excluded.decay_at, state=excluded.state, '
      'parent_id=excluded.parent_id, contexts=excluded.contexts, '
      'breadcrumb=excluded.breadcrumb, place=excluded.place',
      [
        task.id,
        task.title,
        task.activationEnergy,
        task.salience,
        task.stakes,
        task.decayAt?.toUtc().millisecondsSinceEpoch,
        task.state.name,
        task.parentId,
        task.contexts.join(','),
        task.breadcrumb,
        task.place,
        _clock.nowUtc().millisecondsSinceEpoch,
      ],
    );
  }

  Future<List<Task>> tasks({Set<TaskState>? states}) async {
    final sql = states == null || states.isEmpty
        ? 'SELECT * FROM tasks ORDER BY created_at DESC'
        : 'SELECT * FROM tasks WHERE state IN '
            '(${List.filled(states.length, '?').join(',')}) '
            'ORDER BY created_at DESC';
    final rows = _db.select(sql, states?.map((s) => s.name).toList() ?? const []);
    return rows.map((r) {
      final contexts = (r['contexts'] as String?) ?? '';
      final decay = r['decay_at'] as int?;
      return Task(
        id: r['id'] as String,
        title: r['title'] as String,
        activationEnergy: r['ae'] as int,
        salience: r['salience'] as int,
        stakes: r['stakes'] as int,
        decayAt: decay == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(decay, isUtc: true).toLocal(),
        state: TaskState.values.firstWhere((s) => s.name == r['state']),
        parentId: r['parent_id'] as String?,
        contexts: contexts.isEmpty ? const [] : contexts.split(','),
        breadcrumb: r['breadcrumb'] as String?,
        place: r['place'] as String?,
      );
    }).toList();
  }

  Future<void> deleteTask(String id) async {
    _db.execute('DELETE FROM tasks WHERE id = ?', [id]);
  }

  // ── Blocker-Beziehungen ───────────────────────────────────────────────
  //
  // Projektion wie `tasks`: Die Wahrheit steht im Ereignisstrom
  // (`task_linked` / `task_unlinked`), diese Tabelle ist nur die schnelle
  // Sicht darauf und wird von `rebuildProjections` vollstaendig neu gebaut.

  /// Legt „[blockerId] blockiert [blockedId]" an. Doppelt schadet nicht.
  ///
  /// Die Kreispruefung liegt bewusst nicht hier, sondern im Kern
  /// (`ensureAcyclic`): Sie ist eine reine Funktion und muss ohne Datenbank
  /// testbar bleiben.
  Future<void> addTaskLink(String blockerId, String blockedId) async {
    _db.execute(
      'INSERT INTO task_links (blocker_id, blocked_id) VALUES (?, ?) '
      'ON CONFLICT(blocker_id, blocked_id) DO NOTHING',
      [blockerId, blockedId],
    );
  }

  /// Loest die Beziehung. Gibt zurueck, ob es sie ueberhaupt gab — der
  /// Aufrufer schreibt sonst ein Ereignis fuer nichts.
  Future<bool> removeTaskLink(String blockerId, String blockedId) async {
    _db.execute(
      'DELETE FROM task_links WHERE blocker_id = ? AND blocked_id = ?',
      [blockerId, blockedId],
    );
    return _db.updatedRows > 0;
  }

  /// Alle Beziehungen, stabil sortiert.
  Future<List<TaskLink>> taskLinks() async => _db
      .select('SELECT blocker_id, blocked_id FROM task_links '
          'ORDER BY blocker_id, blocked_id')
      .map((r) => TaskLink(
            blockerId: r['blocker_id'] as String,
            blockedId: r['blocked_id'] as String,
          ))
      .toList();

  /// Anlagezeitpunkt je Aufgabe — der Atomizer braucht ihn, um liegen
  /// gebliebene Aufgaben zu erkennen.
  Future<Map<String, DateTime>> taskCreationTimes() async {
    final rows = _db.select('SELECT id, created_at FROM tasks');
    return {
      for (final r in rows)
        r['id'] as String: DateTime.fromMillisecondsSinceEpoch(
          r['created_at'] as int,
          isUtc: true,
        ).toLocal(),
    };
  }

  // ── Zeitanker (M3) ────────────────────────────────────────────────────

  Future<void> upsertAnchor(
    Anchor anchor, {
    String source = 'manual',
    String? externalId,
  }) async {
    _db.execute(
      'INSERT INTO anchors (id, title, arrive_by, travel_min, prepare_min, '
      'buffer_min, context_min, location, source, external_id) '
      'VALUES (?,?,?,?,?,?,?,?,?,?) '
      'ON CONFLICT(id) DO UPDATE SET title=excluded.title, '
      'arrive_by=excluded.arrive_by, travel_min=excluded.travel_min, '
      'prepare_min=excluded.prepare_min, buffer_min=excluded.buffer_min, '
      'context_min=excluded.context_min, location=excluded.location',
      [
        anchor.id,
        anchor.title,
        anchor.arriveBy.millisecondsSinceEpoch,
        anchor.travel.inMinutes,
        anchor.prepare.inMinutes,
        anchor.buffer.inMinutes,
        anchor.contextSwitch.inMinutes,
        anchor.location,
        source,
        externalId,
      ],
    );
  }

  /// Anker ab [from], aufsteigend. Verworfene bleiben außen vor.
  Future<List<Anchor>> anchors({DateTime? from, DateTime? to}) async {
    final where = <String>['dismissed = 0'];
    final args = <Object?>[];
    if (from != null) {
      where.add('arrive_by >= ?');
      args.add(from.millisecondsSinceEpoch);
    }
    if (to != null) {
      where.add('arrive_by < ?');
      args.add(to.millisecondsSinceEpoch);
    }
    final rows = _db.select(
      'SELECT * FROM anchors WHERE ${where.join(' AND ')} ORDER BY arrive_by ASC',
      args,
    );
    return rows.map(_rowToAnchor).toList();
  }

  /// Ist dieser Kalendereintrag schon übernommen?
  Future<bool> hasAnchorFor(String externalId) async => _db
      .select('SELECT 1 FROM anchors WHERE external_id = ? LIMIT 1',
          [externalId])
      .isNotEmpty;

  /// Verwirft einen Anker, ohne ihn zu löschen — ein erneuter Kalenderimport
  /// soll ihn nicht wieder hereinholen.
  Future<void> dismissAnchor(String id) async {
    _db.execute('UPDATE anchors SET dismissed = 1 WHERE id = ?', [id]);
  }

  Anchor _rowToAnchor(Row r) => Anchor(
        id: r['id'] as String,
        title: r['title'] as String,
        arriveBy: DateTime.fromMillisecondsSinceEpoch(r['arrive_by'] as int),
        travel: Duration(minutes: r['travel_min'] as int),
        prepare: Duration(minutes: r['prepare_min'] as int),
        buffer: Duration(minutes: r['buffer_min'] as int),
        contextSwitch: Duration(minutes: r['context_min'] as int),
        location: r['location'] as String?,
      );

  // ── Decisions ─────────────────────────────────────────────────────────

  Future<void> saveDecision(Decision decision) async {
    _db.execute(
      'INSERT OR REPLACE INTO decisions (id, at, rule_id, action, explanation, '
      'state_snapshot_id, suppressed, response) VALUES (?,?,?,?,?,?,?,?)',
      [
        decision.id,
        decision.at.toUtc().millisecondsSinceEpoch,
        decision.ruleId,
        decision.action.type.token,
        decision.explanation,
        decision.stateSnapshotId,
        decision.suppressed ? 1 : 0,
        decision.response?.name,
      ],
    );
  }

  /// Gibt es diese Entscheidung ueberhaupt?
  ///
  /// **Warum das gebraucht wird.** Eine Rueckmeldung ist die einzige Zahl,
  /// an der sich eine Regel messen laesst — die Befolgungsquote im
  /// Wochenreview haengt daran. Kommt sie auf eine ID, die es nie gab,
  /// zaehlt der Rueckblick eine Antwort auf einen Vorschlag, den niemand
  /// bekommen hat. Das ist kein Absturz, sondern eine still falsche Zahl,
  /// und die ist teurer.
  Future<bool> hasDecision(String id) async {
    final rows = _db.select('SELECT 1 FROM decisions WHERE id = ? LIMIT 1', [id]);
    return rows.isNotEmpty;
  }

  Future<void> setDecisionResponse(String id, DecisionResponse response) async {
    _db.execute('UPDATE decisions SET response = ? WHERE id = ?',
        [response.name, id]);
  }

  /// Statistik je Regel fuer das Wochenreview (docs/06-METRIKEN.md §3).
  Future<List<RuleStats>> ruleStats({required DateTime since}) async {
    final rows = _db.select('''
      SELECT rule_id,
             SUM(CASE WHEN suppressed = 0 THEN 1 ELSE 0 END) AS fires,
             SUM(CASE WHEN suppressed = 1 THEN 1 ELSE 0 END) AS suppressed,
             SUM(CASE WHEN response = 'followed' THEN 1 ELSE 0 END) AS followed,
             SUM(CASE WHEN response = 'deferred' THEN 1 ELSE 0 END) AS deferred,
             SUM(CASE WHEN response = 'rejected' THEN 1 ELSE 0 END) AS rejected
      FROM decisions WHERE at >= ? GROUP BY rule_id ORDER BY rule_id
    ''', [since.toUtc().millisecondsSinceEpoch]);
    return rows
        .map((r) => RuleStats(
              ruleId: r['rule_id'] as String,
              fires: r['fires'] as int,
              suppressed: r['suppressed'] as int,
              followed: r['followed'] as int,
              deferred: r['deferred'] as int,
              rejected: r['rejected'] as int,
            ))
        .toList();
  }

  // ── DecisionHistory-Port ──────────────────────────────────────────────

  DecisionHistory historyAt(DateTime localNow) {
    final dayStart =
        DateTime(localNow.year, localNow.month, localNow.day).toUtc();
    final last = <String, DateTime>{};
    final today = <String, int>{};
    final rejections = <String, int>{};
    var total = 0;

    for (final row in _db.select(
      'SELECT rule_id, at, response, suppressed FROM decisions '
      'ORDER BY at ASC',
    )) {
      final ruleId = row['rule_id'] as String;
      final at = DateTime.fromMillisecondsSinceEpoch(row['at'] as int,
              isUtc: true)
          .toLocal();
      if ((row['suppressed'] as int) == 1) continue;
      last[ruleId] = at;
      if (row['response'] == 'rejected') {
        rejections[ruleId] = (rejections[ruleId] ?? 0) + 1;
      } else if (row['response'] != null) {
        rejections[ruleId] = 0;
      }
      if (!at.toUtc().isBefore(dayStart)) {
        today[ruleId] = (today[ruleId] ?? 0) + 1;
        total++;
      }
    }
    return _StoredHistory(last, today, rejections, total);
  }

  // ── Usage / Meta-Guard ────────────────────────────────────────────────

  Future<void> logUsage(String screen, Duration duration,
      {bool countsToBudget = true}) async {
    _db.execute(
      'INSERT INTO usage_log (id, at, screen, duration_s, counts) '
      'VALUES (?,?,?,?,?)',
      [
        newUlid(_clock.nowUtc()),
        _clock.nowUtc().millisecondsSinceEpoch,
        screen,
        duration.inSeconds,
        countsToBudget ? 1 : 0,
      ],
    );
  }

  /// Verbrauchtes Meta-Work-Budget seit lokalem Tagesbeginn.
  /// Erfassung zaehlt nicht mit — nur Konfiguration und Auswertung. (M12)
  Future<Duration> usageToday(DateTime localNow) async {
    final dayStart =
        DateTime(localNow.year, localNow.month, localNow.day).toUtc();
    final rows = _db.select(
      'SELECT COALESCE(SUM(duration_s), 0) AS s FROM usage_log '
      'WHERE at >= ? AND counts = 1',
      [dayStart.millisecondsSinceEpoch],
    );
    return Duration(seconds: rows.first['s'] as int);
  }

  // ── Settings ──────────────────────────────────────────────────────────

  String? setting(String key) {
    final rows = _db.select('SELECT value FROM settings WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void setSetting(String key, String value) {
    _db.execute(
      'INSERT INTO settings (key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key, value],
    );
  }

  // ── Wartung ───────────────────────────────────────────────────────────

  /// Verwirft alle Projektionen und baut sie aus `events` neu auf.
  /// Muss denselben Zustand erzeugen — siehe Rebuild-Test.
  Future<void> rebuildProjections() async {
    _db.execute('DELETE FROM tasks');
    _db.execute('DELETE FROM task_links');
    final events = await query(types: {
      EventType.taskCreated,
      EventType.taskStarted,
      EventType.taskCompleted,
      EventType.taskAbandoned,
      // Ohne das kommt eine zerlegte Aufgabe als startbar zurueck, obwohl
      // ihre Teilschritte offen sind — und steht dann doppelt zur Wahl.
      EventType.taskSplit,
      // Ohne die beiden ueberlebt eine Blocker-Beziehung keinen
      // Wiederaufbau: Die wartende Aufgabe kaeme als startbar zurueck und
      // wuerde vorgeschlagen, obwohl sie nicht geht.
      EventType.taskLinked,
      EventType.taskUnlinked,
    });
    final byId = <String, Task>{};
    for (final e in events) {
      // Beziehungen tragen `blocker_id`/`blocked_id` statt `task_id` — die
      // Waechterzeile weiter unten haette sie sonst stumm verworfen.
      if (e.type == EventType.taskLinked || e.type == EventType.taskUnlinked) {
        final blocker = e.payload['blocker_id'] as String?;
        final blocked = e.payload['blocked_id'] as String?;
        if (blocker == null || blocked == null) continue;
        if (e.type == EventType.taskLinked) {
          await addTaskLink(blocker, blocked);
        } else {
          await removeTaskLink(blocker, blocked);
        }
        continue;
      }
      // taskSplit traegt kein `task_id`, sondern `parent_id` — die
      // Waechterzeile darunter haette es sonst stumm verworfen.
      if (e.type == EventType.taskSplit) {
        final parent = e.payload['parent_id'] as String?;
        if (parent != null && byId[parent] != null) {
          byId[parent] = byId[parent]!.copyWith(state: TaskState.blocked);
        }
        continue;
      }
      final id = e.payload['task_id'] as String?;
      if (id == null) continue;
      switch (e.type) {
        case EventType.taskCreated:
          byId[id] = Task(
            id: id,
            title: e.payload['title'] as String? ?? '(ohne Titel)',
            activationEnergy: (e.payload['ae'] as num?)?.toInt() ?? 5,
            salience: (e.payload['salience'] as num?)?.toInt() ?? 5,
            stakes: (e.payload['stakes'] as num?)?.toInt() ?? 5,
            decayAt: e.payload['decay_at'] == null
                ? null
                : DateTime.parse(e.payload['decay_at']! as String),
            state: TaskState.values.firstWhere(
              (s) => s.name == e.payload['state'],
              orElse: () => TaskState.inbox,
            ),
            // Ohne den Eltern-Bezug verlieren zerlegte Teilschritte ihre
            // Zugehoerigkeit: Sie stehen dann als lose Aufgaben da, und die
            // Elternaufgabe wirkt unerledigt ohne erkennbaren Grund.
            parentId: e.payload['parent_id'] as String?,
            // Ohne das ueberlebt die Ortsbindung keinen Wiederaufbau: Die
            // Aufgabe kaeme ortsungebunden zurueck und wuerde ueberall
            // vorgeschlagen. Ein Wiederaufbau, der den Zustand veraendert,
            // ist die teuerste Art von Fehler in einem System, dessen
            // Projektionen aus dem Ereignisstrom entstehen.
            place: e.payload['place'] as String?,
          );
        case EventType.taskStarted:
          byId[id] = byId[id]?.copyWith(state: TaskState.active) ?? byId[id]!;
        case EventType.taskCompleted:
          byId[id] = byId[id]?.copyWith(state: TaskState.done) ?? byId[id]!;
        case EventType.taskAbandoned:
          // Nicht jedes „abandoned" ist ein Verwerfen. Zuruecklegen und
          // Verdraengen sind Rueckwege in den Bestand — sie als verworfen
          // wiederherzustellen loescht die Aufgabe faktisch, und zwar
          // stumm beim naechsten Wiederaufbau.
          final reason = e.payload['reason'] as String?;
          // `steps_done` gehoert dazu: Eine Aufgabe, deren Teilschritte
          // alle erledigt sind, geht in den Bestand zurueck. Ohne den
          // Eintrag hier musste die Laufzeit sie als `released` tarnen —
          // und der Ereignisstrom behauptete dann, sie sei aufgegeben
          // worden. Ein Strom, der etwas anderes erzaehlt als das, was
          // passiert ist, ist die teuerste Art von Fehler in einem System,
          // dessen Projektionen aus ihm entstehen.
          const back = {'released', 'superseded', 'steps_done'};
          byId[id] = byId[id]?.copyWith(
                state: back.contains(reason)
                    ? TaskState.ready
                    : TaskState.dropped,
              ) ??
              byId[id]!;
        default:
          break;
      }
    }
    for (final task in byId.values) {
      await upsertTask(task);
    }
  }

  Future<int> eventCount() async =>
      _db.select('SELECT COUNT(*) AS c FROM events').first['c'] as int;

  void close() => _db.close();
}

final class _StoredHistory implements DecisionHistory {
  final Map<String, DateTime> _last;
  final Map<String, int> _today;
  final Map<String, int> _rejections;
  final int _total;
  const _StoredHistory(this._last, this._today, this._rejections, this._total);

  @override
  DateTime? lastFired(String ruleId) => _last[ruleId];
  @override
  int firedToday(String ruleId) => _today[ruleId] ?? 0;
  @override
  int consecutiveRejections(String ruleId) => _rejections[ruleId] ?? 0;
  @override
  int totalInterventionsToday() => _total;
}

final class RuleStats {
  final String ruleId;
  final int fires;
  final int suppressed;
  final int followed;
  final int deferred;
  final int rejected;

  const RuleStats({
    required this.ruleId,
    required this.fires,
    required this.suppressed,
    required this.followed,
    required this.deferred,
    required this.rejected,
  });

  int get responses => followed + deferred + rejected;

  /// Anteil befolgter Empfehlungen. Unter 40 % ist die Regel ein
  /// Streichkandidat (docs/06-METRIKEN.md §3).
  double? get followRate => responses == 0 ? null : followed / responses;
}

// ── ULID ────────────────────────────────────────────────────────────────

const _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
final _rng = math.Random.secure();

/// Zeitsortierbare, offline kollisionsfreie ID.
///
/// Zeit wird uebergeben (Clock-Port), Zufall bleibt lokal — IDs sind
/// bewusst nicht Teil der deterministischen Entscheidungsschleife.
String newUlid(DateTime at) {
  var ms = at.millisecondsSinceEpoch;
  final time = List<String>.filled(10, '0');
  for (var i = 9; i >= 0; i--) {
    time[i] = _crockford[ms % 32];
    ms ~/= 32;
  }
  final random = List<String>.generate(16, (_) => _crockford[_rng.nextInt(32)]);
  return time.join() + random.join();
}
