/// Kommt eine Datenbank von Schema v1 wirklich auf v10?
///
/// Geprueft wurde das nie. `s3_store_test.dart` haelt unter „Bestandsdaten
/// ueberleben die Migration" eine frisch angelegte Datenbank fest — also
/// genau den Fall, in dem alle zehn Bloecke ohnehin durchlaufen. Der Fall,
/// der auf einem Geraet passiert, ist der andere: Die Datei ist da, sie
/// steht auf einem alten Stand, und die neue Fassung muss sie einholen.
///
/// Genau daran ist es hier schon einmal gescheitert — `rule_overrides` stand
/// im `current < 5`-Zweig, waehrend die Version auf 6 stand; eine
/// Bestandsdatenbank auf Stand 5 bekam die Tabelle nie und wurde trotzdem
/// als 6 markiert (Kommentar in `sqlite_event_store.dart`). Der Fehler war
/// auf einer frischen Installation unsichtbar.
///
/// Deshalb baut diese Datei fuer **jeden** alten Stand eine Datei so, wie
/// die Fassung von damals sie hinterlassen haette, laesst sie durch
/// `SqliteEventStore.open` laufen und vergleicht das Ergebnis mit einer
/// frischen Installation — Tabellen, Spalten, Indizes. Ein vergessener
/// Block hat danach keine Stelle mehr, an der er sich verstecken kann.
library;

import 'dart:io';

import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late FakeClock clock;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('axiom_migration');
    clock = FakeClock(DateTime(2026, 8, 3, 10));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Legt eine Datei an, wie die Fassung mit Schema [version] sie
  /// hinterlassen haette, und gibt den Pfad zurueck.
  String oldDatabase(int version, {void Function(Database db)? fill}) {
    final path = '${tmp.path}/v$version.db';
    final db = sqlite3.open(path);
    for (final sql in _schemaUpTo(version)) {
      db.execute(sql);
    }
    fill?.call(db);
    db.execute('PRAGMA user_version = $version;');
    db.close();
    return path;
  }

  /// Tabellen, Spalten und Indizes — die Form, auf die es ankommt.
  ///
  /// Verglichen wird als Menge, nicht als Text: Eine per `ALTER TABLE`
  /// nachgeruestete Spalte steht am Ende der Tabelle, in einer frischen
  /// Datei steht dieselbe Spalte mitten drin. Das ist folgenlos — jede
  /// Abfrage im Paket nennt ihre Spalten beim Namen.
  Map<String, Object> shapeOf(SqliteEventStore store) {
    final db = store.rawDatabase;
    final tables = db
        .select("SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%' ORDER BY name")
        .map((r) => r['name'] as String)
        .toList();
    return {
      'tables': tables.toSet(),
      'indexes': db
          .select("SELECT name FROM sqlite_master WHERE type = 'index' "
              "AND name NOT LIKE 'sqlite_%'")
          .map((r) => r['name'] as String)
          .toSet(),
      // Nicht nur die Namen: Typ, Pflichtfeld, Vorbelegung und
      // Schluesselstellung gehoeren dazu. Eine Spalte, die frisch
      // `NOT NULL DEFAULT 0` ist und nachgeruestet nullbar, waere derselbe
      // Fehler in leiser.
      'columns': {
        for (final table in tables)
          table: db
              .select('PRAGMA table_info($table)')
              .map((r) => '${r['name']} ${r['type']} '
                  'notnull=${r['notnull']} default=${r['dflt_value']} '
                  'pk=${r['pk']}')
              .toSet(),
      },
    };
  }

  SqliteEventStore openFresh() =>
      SqliteEventStore.open('${tmp.path}/fresh.db', clock: clock);

  group('Von jedem alten Stand auf den aktuellen', () {
    for (var version = 1; version < kSchemaVersion; version++) {
      test('Schema v$version bekommt dieselbe Form wie eine frische Datei',
          () {
        final alt = SqliteEventStore.open(oldDatabase(version), clock: clock);
        final neu = openFresh();
        addTearDown(alt.close);
        addTearDown(neu.close);

        expect(shapeOf(alt), shapeOf(neu),
            reason: 'Eine Datenbank auf Stand v$version erreicht nicht die '
                'Form einer frischen Installation. Ein Migrationsblock '
                'fehlt oder haengt am falschen Zweig.');
      });
    }

    test('am Ende steht die aktuelle Versionsnummer in der Datei', () {
      final store = SqliteEventStore.open(oldDatabase(1), clock: clock);
      addTearDown(store.close);

      expect(
        store.rawDatabase.select('PRAGMA user_version;').first.values.first,
        kSchemaVersion,
      );
    });

    test('ein zweites Öffnen ändert nichts mehr', () {
      final path = oldDatabase(1);
      final erst = SqliteEventStore.open(path, clock: clock);
      final form = shapeOf(erst);
      erst.close();

      final zweit = SqliteEventStore.open(path, clock: clock);
      addTearDown(zweit.close);
      expect(shapeOf(zweit), form);
    });

    test('jede Tabelle des Exports gibt es auch in einer migrierten Datei',
        () async {
      // Sonst wandert von einem alten Gerät weniger mit als von einem neu
      // aufgesetzten — und zwar unbemerkt, weil der Export nur schreibt,
      // was er findet.
      final store = SqliteEventStore.open(oldDatabase(1), clock: clock);
      addTearDown(store.close);

      final vorhanden = (shapeOf(store)['tables']! as Set<String>);
      expect(vorhanden, containsAll(kVaultTables));
    });
  });

  group('Was in der alten Datei stand', () {
    test('Ereignisse und Aufgaben überleben den Weg von v1 nach v10',
        () async {
      final path = oldDatabase(1, fill: (db) {
        db.execute(
          "INSERT INTO events (id, at, type, source, payload, correction_of) "
          "VALUES ('e1', ${DateTime.utc(2020, 3, 1).millisecondsSinceEpoch}, "
          "'capture', 'user', '{\"text\":\"aus dem ersten Jahr\"}', NULL)",
        );
        db.execute(
          "INSERT INTO tasks (id, title, ae, salience, stakes, decay_at, "
          "state, parent_id, contexts, breadcrumb, created_at) "
          "VALUES ('t1', 'Steuerunterlagen', 7, 5, 8, NULL, 'ready', NULL, "
          "'', NULL, ${DateTime.utc(2020, 3, 1).millisecondsSinceEpoch})",
        );
      });

      final store = SqliteEventStore.open(path, clock: clock);
      addTearDown(store.close);

      expect((await store.query()).single.payload['text'],
          'aus dem ersten Jahr');
      final task = (await store.tasks()).single;
      expect(task.title, 'Steuerunterlagen');
      // Die Ortsbindung kam erst mit v7 — eine alte Aufgabe hat keine.
      expect(task.place, isNull);
    });

    test('Ereignisse ohne Sequenz bekommen die Einfügereihenfolge nachgereicht',
        () async {
      // Der Grund für v2: Bei gleichem Zeitstempel entschied vorher der
      // Zufallsanteil der ULID über die Reihenfolge, und beim Wiederaufbau
      // konnte „erledigt" vor „angelegt" landen. Die Nachrüstung setzt
      // `seq = rowid` — also genau die Reihenfolge, in der eingefügt wurde.
      final at = DateTime.utc(2020, 3, 1).millisecondsSinceEpoch;
      final path = oldDatabase(1, fill: (db) {
        // Absichtlich absteigende Kennungen: Nach Kennung sortiert käme
        // genau die umgekehrte Reihenfolge heraus.
        for (final id in ['ccc', 'bbb', 'aaa']) {
          db.execute(
            "INSERT INTO events (id, at, type, source, payload, correction_of) "
            "VALUES ('$id', $at, 'capture', 'user', '{}', NULL)",
          );
        }
      });

      final store = SqliteEventStore.open(path, clock: clock);
      addTearDown(store.close);

      expect((await store.query()).map((e) => e.id), ['ccc', 'bbb', 'aaa']);
    });

    test('ein danach angehängtes Ereignis steht hinter dem Bestand', () async {
      // Die Sequenz muss über die Migration hinweg weiterzählen, sonst
      // bekäme das erste neue Ereignis dieselbe Nummer wie ein altes.
      final at = DateTime.utc(2020, 3, 1).millisecondsSinceEpoch;
      final path = oldDatabase(1, fill: (db) {
        db.execute(
          "INSERT INTO events (id, at, type, source, payload, correction_of) "
          "VALUES ('alt', $at, 'capture', 'user', '{}', NULL)",
        );
      });

      final store = SqliteEventStore.open(path, clock: clock);
      addTearDown(store.close);
      await store.append(Event(
        id: 'neu',
        at: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
        type: EventType.capture,
        source: EventSource.user,
        payload: const {},
      ));

      expect((await store.query()).map((e) => e.id), ['alt', 'neu']);
    });
  });

  group('Nach der Migration läuft alles, was die App braucht', () {
    test('jedes Modul schreibt und liest in der migrierten Datei', () async {
      final store = SqliteEventStore.open(oldDatabase(1), clock: clock);
      addTearDown(store.close);

      // M1/M2 — Strom und Projektion samt Ortsbindung (v7).
      await store.append(Event(
        id: newUlid(clock.nowUtc()),
        at: clock.nowUtc(),
        type: EventType.taskCreated,
        source: EventSource.user,
        payload: const {
          'task_id': 't9',
          'title': 'Paket abholen',
          'place': 'Postfiliale',
        },
      ));
      await store.rebuildProjections();
      expect((await store.tasks()).single.place, 'Postfiliale');

      // M3 (v3), Stufe 3 (v4), Stufe 4 (v5).
      await store.upsertAnchor(Anchor(
        id: 'a1',
        title: 'Zahnarzt',
        arriveBy: DateTime(2026, 8, 10, 14),
      ));
      await store.upsertChannel(const SensationChannel(
        id: 'sport',
        label: 'Sport',
        intensity: 4,
        typical: Duration(minutes: 45),
      ));
      await store.upsertTrigger(const InterceptTrigger(
        id: 'kauf',
        label: 'Anschaffung',
        cooldown: Duration(minutes: 15),
        checklist: ['Morgen noch?'],
      ));
      store.setLoadState(LoadLevel.l1, clock.nowLocal());
      await store.savePostMortem(PostMortem(
        incidentId: 'i1',
        at: clock.nowLocal(),
        rootCause: 'Zu wenig Schlaf',
      ));
      await store.saveMedEntry(MedEntry(
        id: 'm1',
        label: 'Praeparat',
        takenAt: clock.nowLocal(),
      ));

      // v6 — Regel-Overlay.
      store.rawDatabase.execute(
        'INSERT INTO rule_overrides (id, yaml, updated_at, shadow_until, '
        'overrides) VALUES (?,?,?,?,?)',
        ['R-900', 'id: R-900', 1, 2, 0],
      );

      // v8 — freigegebene Browser.
      await store.trustBrowser('hash',
          until: clock.nowLocal().add(const Duration(days: 3)),
          now: clock.nowLocal());

      // v9 — Blocker-Beziehungen.
      await store.addTaskLink('t9', 't10');

      expect((await store.anchors()).single.title, 'Zahnarzt');
      expect((await store.channels()).single.id, 'sport');
      expect((await store.triggers()).single.id, 'kauf');
      expect(store.loadState()!.level, LoadLevel.l1);
      expect((await store.postMortems()).single.rootCause, 'Zu wenig Schlaf');
      expect((await store.medEntriesSince(DateTime(2026))).single.id, 'm1');
      expect(await store.isTrustedBrowser('hash', clock.nowLocal()), isTrue);
      expect((await store.taskLinks()).single.blockedId, 't10');
    });

    test('der Teilindex aus v10 wird auch nachgerüstet', () {
      // Er ist der Unterschied zwischen „liest die offenen Entscheidungen"
      // und „liest bei jedem Zyklus das ganze Schattenprotokoll".
      final store = SqliteEventStore.open(oldDatabase(9), clock: clock);
      addTearDown(store.close);

      final plan = store.rawDatabase
          .select('EXPLAIN QUERY PLAN ${SqliteEventStore.historyQuery}')
          .map((r) => r['detail'] as String)
          .join(' ');
      expect(plan, contains('idx_decisions_open'));
    });

    test('eine migrierte Datei lässt sich exportieren und einspielen',
        () async {
      final store = SqliteEventStore.open(oldDatabase(1), clock: clock);
      addTearDown(store.close);
      await store.append(Event(
        id: newUlid(clock.nowUtc()),
        at: clock.nowUtc(),
        type: EventType.capture,
        source: EventSource.user,
        payload: const {'text': 'Umzug'},
      ));
      await store.upsertAnchor(Anchor(
        id: 'a1',
        title: 'Zahnarzt',
        arriveBy: DateTime(2026, 8, 10, 14),
      ));

      final blob = await Vault(store: store, clock: clock, kdfRounds: 200)
          .export(passphrase: 'ein-langes-kennwort');

      final ziel = SqliteEventStore.inMemory(clock: clock);
      addTearDown(ziel.close);
      final ergebnis = await Vault(store: ziel, clock: clock, kdfRounds: 200)
          .import(data: blob, passphrase: 'ein-langes-kennwort');

      expect(ergebnis.imported, 1);
      expect(ergebnis.rejected, 0);
      expect((await ziel.anchors()).single.title, 'Zahnarzt');
    });
  });

  group('Eine Datei aus einer neueren Fassung', () {
    test('wird abgelehnt, statt gegen ein unbekanntes Schema zu rechnen', () {
      final path = '${tmp.path}/zukunft.db';
      final db = sqlite3.open(path);
      for (final sql in _schemaUpTo(kSchemaVersion)) {
        db.execute(sql);
      }
      db.execute('PRAGMA user_version = ${kSchemaVersion + 1};');
      db.close();

      expect(
        () => SqliteEventStore.open(path, clock: clock),
        throwsA(isA<StateError>()),
      );
    });
  });
}

/// Das Schema, wie es die Fassung mit Stand [version] hinterlassen haette.
///
/// Bewusst als Abschrift und nicht aus `_migrate()` erzeugt: Ein Fixture,
/// das sich aus dem Prueflings-Code speist, prueft nichts. Was hier steht,
/// ist der Stand von damals — bis auf die Spalten, die eine spaetere Version
/// per `ALTER TABLE` nachreicht (`events.seq` ab v2, `tasks.place` ab v7);
/// die fehlen hier absichtlich, denn genau ihr Nachreichen ist der Prueffall.
List<String> _schemaUpTo(int version) {
  final sql = <String>[];

  sql.add('''
    CREATE TABLE events (
      id            TEXT PRIMARY KEY,
      at            INTEGER NOT NULL,
      type          TEXT    NOT NULL,
      source        TEXT    NOT NULL,
      payload       TEXT    NOT NULL,
      correction_of TEXT
    );
    CREATE INDEX idx_events_at   ON events(at);
    CREATE INDEX idx_events_type ON events(type, at);

    CREATE TABLE tasks (
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
    CREATE INDEX idx_tasks_state ON tasks(state);

    CREATE TABLE decisions (
      id                TEXT PRIMARY KEY,
      at                INTEGER NOT NULL,
      rule_id           TEXT    NOT NULL,
      action            TEXT    NOT NULL,
      explanation       TEXT    NOT NULL,
      state_snapshot_id TEXT    NOT NULL,
      suppressed        INTEGER NOT NULL DEFAULT 0,
      response          TEXT
    );
    CREATE INDEX idx_decisions_rule ON decisions(rule_id, at);

    CREATE TABLE usage_log (
      id         TEXT PRIMARY KEY,
      at         INTEGER NOT NULL,
      screen     TEXT    NOT NULL,
      duration_s INTEGER NOT NULL,
      counts     INTEGER NOT NULL DEFAULT 1
    );
    CREATE INDEX idx_usage_at ON usage_log(at);

    CREATE TABLE settings (
      key   TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );
  ''');

  if (version >= 2) {
    sql.add('ALTER TABLE events ADD COLUMN seq INTEGER;');
    sql.add('CREATE INDEX idx_events_seq ON events(at, seq);');
  }

  if (version >= 3) {
    sql.add('''
      CREATE TABLE anchors (
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
      CREATE INDEX idx_anchors_at ON anchors(arrive_by);
      CREATE UNIQUE INDEX idx_anchors_ext
        ON anchors(external_id) WHERE external_id IS NOT NULL;
    ''');
  }

  if (version >= 4) {
    sql.add('''
      CREATE TABLE focus_sessions (
        id            TEXT PRIMARY KEY,
        started_at    INTEGER NOT NULL,
        ended_at      INTEGER,
        anchor_task_id TEXT,
        anchor_title  TEXT,
        planned_min   INTEGER NOT NULL DEFAULT 50,
        breadcrumb    TEXT,
        exit_kind     TEXT
      );
      CREATE INDEX idx_focus_started ON focus_sessions(started_at);

      CREATE TABLE sensation_channels (
        id          TEXT PRIMARY KEY,
        label       TEXT    NOT NULL,
        intensity   INTEGER NOT NULL,
        typical_min INTEGER NOT NULL DEFAULT 30,
        has_cost    INTEGER NOT NULL DEFAULT 0,
        sort_order  INTEGER NOT NULL DEFAULT 0
      );

      CREATE TABLE intercept_triggers (
        id           TEXT PRIMARY KEY,
        label        TEXT    NOT NULL,
        cooldown_min INTEGER NOT NULL DEFAULT 15,
        release_at   TEXT,
        checklist    TEXT    NOT NULL DEFAULT '[]',
        authorized   INTEGER NOT NULL DEFAULT 0,
        archived     INTEGER NOT NULL DEFAULT 0
      );

      CREATE TABLE intercept_runs (
        id            TEXT PRIMARY KEY,
        trigger_id    TEXT    NOT NULL,
        trigger_label TEXT    NOT NULL,
        started_at    INTEGER NOT NULL,
        releases_at   INTEGER NOT NULL,
        answers       TEXT    NOT NULL DEFAULT '[]',
        outcome       TEXT    NOT NULL DEFAULT 'pending',
        note          TEXT
      );
      CREATE INDEX idx_runs_trigger ON intercept_runs(trigger_id, started_at);

      CREATE TABLE load_state (
        id    INTEGER PRIMARY KEY CHECK (id = 1),
        level TEXT    NOT NULL,
        since INTEGER NOT NULL
      );
    ''');
  }

  if (version >= 5) {
    sql.add('''
      CREATE TABLE post_mortems (
        incident_id TEXT PRIMARY KEY,
        at          INTEGER NOT NULL,
        root_cause  TEXT,
        counter     TEXT,
        hindsight   INTEGER
      );

      CREATE TABLE med_entries (
        id        TEXT PRIMARY KEY,
        label     TEXT    NOT NULL,
        dose      TEXT,
        taken_at  INTEGER NOT NULL,
        onset_min INTEGER NOT NULL DEFAULT 0,
        dur_min   INTEGER NOT NULL DEFAULT 0
      );
      CREATE INDEX idx_med_taken ON med_entries(taken_at);
    ''');
  }

  if (version >= 6) {
    sql.add('''
      CREATE TABLE rule_overrides (
        id           TEXT PRIMARY KEY,
        yaml         TEXT    NOT NULL,
        updated_at   INTEGER NOT NULL,
        shadow_until INTEGER,
        overrides    INTEGER NOT NULL DEFAULT 0
      );
    ''');
  }

  if (version >= 7) {
    sql.add('ALTER TABLE tasks ADD COLUMN place TEXT;');
  }

  if (version >= 8) {
    sql.add('''
      CREATE TABLE trusted_browsers (
        token_hash  TEXT    PRIMARY KEY,
        label       TEXT,
        approved_at INTEGER NOT NULL,
        expires_at  INTEGER NOT NULL,
        last_seen   INTEGER
      );
    ''');
  }

  if (version >= 9) {
    sql.add('''
      CREATE TABLE task_links (
        blocker_id TEXT NOT NULL,
        blocked_id TEXT NOT NULL,
        PRIMARY KEY (blocker_id, blocked_id)
      );
      CREATE INDEX idx_links_blocked ON task_links(blocked_id);
    ''');
  }

  if (version >= 10) {
    sql.add('CREATE INDEX idx_decisions_open '
        'ON decisions(at) WHERE suppressed = 0;');
  }

  return sql;
}
