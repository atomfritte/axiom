/// Export und Import — verschlüsselt, dateibasiert, ohne Netzwerk.
///
/// Die Roadmap sah für Stufe 4 einen selbst gehosteten Sync vor. Der bräuchte
/// die `INTERNET`-Berechtigung und würde damit die stärkste Zusicherung des
/// Projekts aufheben: dass Gesundheitsdaten das Gerät auf Betriebssystemebene
/// nicht verlassen können (ADR-0002).
///
/// Für den tatsächlichen Zweck — Telefon und Linux-Rechner abgleichen, ein
/// Backup halten — braucht es keinen Server. Eine verschlüsselte Datei über
/// USB, adb oder einen Ordner tut dasselbe, und der Angriffsfläche wegen ist
/// sie die bessere Lösung.
///
/// Format: NDJSON im Klartext, dann verschlüsselt. NDJSON, weil ein Export,
/// den man nur mit AXIOM lesen kann, keine Datenhoheit ist — mit dem Schlüssel
/// lässt er sich mit Bordmitteln entpacken und lesen.
///
/// **Was mitwandert.** Bis Format 1 enthielt die Datei ausschließlich
/// `events`. Alles, was der Nutzer selbst angelegt hat und was kein Ereignis
/// erzeugt — Anker (M3), Reizkanäle (M5), Impuls-Trigger samt Checklisten
/// (M6), Nachbetrachtungen (M10), Wirkfenster-Einträge (M13), Einstellungen
/// und im Gerät bearbeitete Regeln — war nach einem Umzug weg, obwohl der
/// Bildschirm „beide haben danach alles" zusagt und der Export der einzige
/// dokumentierte Sicherungsweg ist. Seit Format 2 stehen diese Tabellen als
/// eigene Zeilen hinter den Ereignissen ([kVaultTables]).
///
/// **Zur Verschlüsselung:** XSalsa20/ChaCha20 wären erste Wahl, brauchen aber
/// eine zusätzliche Abhängigkeit im Kern. Hier läuft ein HMAC-basierter
/// Stromchiffre-Aufbau über SHA-256 (Schlüsselableitung nach PBKDF2-Muster,
/// Gegenstrom über HMAC im Zählermodus, Authentifizierung über HMAC danach).
/// Das ist konservativ konstruiert und für den Zweck angemessen: Es schützt
/// eine Datei, die ohnehin nur zwischen zwei eigenen Geräten wandert.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:axiom_core/axiom_core.dart';
import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

import 'sqlite_event_store.dart';

/// Dateikennung, damit ein falscher Dateityp früh auffällt.
const String kVaultMagic = 'AXIOMVAULT1';

/// Aufbau der Datei.
///
/// 1: Manifest, dann ein Ereignis je Zeile.
/// 2: zusätzlich Tabellenzeilen der Form `{"table": …, "row": {…}}`.
///
/// Die Tabellenzeilen stehen **hinter** den Ereignissen. Eine ältere Fassung
/// liest damit alle Ereignisse vollständig und zählt nur den Rest als
/// unlesbar — statt an Zeile drei auszusteigen.
const int kVaultFormat = 2;

/// Tabellen, die zeilenweise mitwandern.
///
/// Alles hier ist Zustand, den der Nutzer selbst angelegt hat und den kein
/// Ereignis trägt. Wer eine Tabelle hinzufügt, muss sie hier oder in
/// [kVaultExcludedTables] eintragen — `vault_test.dart` vergleicht beide
/// Listen mit dem tatsächlichen Schema und schlägt sonst fehl. Genau dieser
/// Abgleich hat gefehlt: Neun Tabellen sind über Jahre stillschweigend aus
/// dem einzigen Sicherungsweg herausgewachsen.
const List<String> kVaultTables = [
  'anchors',
  'focus_sessions',
  'sensation_channels',
  'intercept_triggers',
  'intercept_runs',
  'load_state',
  'post_mortems',
  'med_entries',
  'rule_overrides',
  'settings',
];

/// Tabellen ohne eigenen Zeilenabschnitt — mit dem Grund daneben.
///
/// `events` steht hier, weil es seinen eigenen, älteren Abschnitt hat. Der
/// Rest bleibt bewusst am Gerät.
const Map<String, String> kVaultExcludedTables = {
  'events': 'eigener Abschnitt: eine Zeile je Ereignis',
  'tasks': 'Projektion, wird nach dem Import aus dem Ereignisstrom gebaut',
  'task_links': 'Projektion, wird nach dem Import aus dem Strom gebaut',
  'decisions': 'Protokoll der Auswertung dieses Geräts. Zwei Geräte werten '
      'unterschiedlich aus; eine zusammengemischte Historie würde '
      'Cooldowns und Tageslimits verfälschen',
  'usage_log': 'Das Meta-Budget (G4) deckelt die Zeit an diesem Gerät. '
      'Fremde Minuten mitzuzählen ergäbe keinen Sinn',
  'trusted_browsers': 'Eine Freigabe gilt einem Browser gegenüber genau '
      'diesem Gerät. Sie mitzunehmen hieße, sie ungefragt zu erweitern',
};

/// Einstellungen, die nicht mitwandern.
///
/// **Warum eine Sperrliste und keine Positivliste.** Eine neue Einstellung
/// soll im Zweifel mitkommen — das Gegenteil ist der Fehler, der diesen
/// Abschnitt nötig gemacht hat. Ausgenommen ist nur, was Geräteidentität
/// ist: Der private Schlüssel des Expertenmodus hat auf keinem zweiten Gerät
/// etwas zu suchen, und der Vermerk über einen Datenbankverlust gehört dem
/// Gerät, auf dem er passiert ist.
const Set<String> kVaultLocalSettings = {
  'expert_cert_pem',
  'expert_key_pem',
  'expert_cert_for',
  'db_reset_at',
};

/// Runden der Schlüsselableitung. Bewusst hoch: Der Schlüssel ist ein
/// menschliches Passwort, und Ableitungskosten sind die einzige Bremse
/// gegen Durchprobieren.
const int kKdfRounds = 120000;

final class VaultError implements Exception {
  final String message;
  VaultError(this.message);
  @override
  String toString() => 'VaultError: $message';
}

@immutable
final class VaultManifest {
  final String schemaVersion;
  final DateTime createdAt;
  final int eventCount;
  final DateTime? from;
  final DateTime? to;

  /// Aufbau der Datei, siehe [kVaultFormat]. Fehlt das Feld, stammt die
  /// Datei aus der Zeit, in der es nur Ereignisse gab.
  final int format;

  /// Welche Tabellen die Datei mitbringt. Leer bei einem Ausschnitt
  /// (`from`/`to` gesetzt) — eine Teilmenge des Stroms ist kein Umzug.
  final List<String> tables;

  const VaultManifest({
    required this.schemaVersion,
    required this.createdAt,
    required this.eventCount,
    this.from,
    this.to,
    this.format = kVaultFormat,
    this.tables = const [],
  });

  Map<String, Object?> toJson() => {
        'schema': schemaVersion,
        'format': format,
        'created_at': createdAt.toIso8601String(),
        'events': eventCount,
        'tables': tables,
        'from': from?.toIso8601String(),
        'to': to?.toIso8601String(),
      };

  static VaultManifest fromJson(Map<String, Object?> json) => VaultManifest(
        schemaVersion: json['schema'] as String? ?? '?',
        createdAt: DateTime.parse(json['created_at']! as String),
        eventCount: (json['events'] as num?)?.toInt() ?? 0,
        from: json['from'] == null
            ? null
            : DateTime.parse(json['from']! as String),
        to: json['to'] == null ? null : DateTime.parse(json['to']! as String),
        format: (json['format'] as num?)?.toInt() ?? 1,
        tables:
            (json['tables'] as List?)?.map((t) => '$t').toList() ?? const [],
      );
}

final class Vault {
  final SqliteEventStore store;
  final Clock clock;

  /// Runden der Schluesselableitung.
  ///
  /// Produktiv immer [kKdfRounds]. Tests duerfen heruntersetzen, damit die
  /// Suite nicht an der absichtlichen Langsamkeit haengt — die Korrektheit
  /// des Verfahrens haengt nicht an der Rundenzahl, nur seine Kosten.
  final int kdfRounds;

  const Vault({
    required this.store,
    required this.clock,
    this.kdfRounds = kKdfRounds,
  });

  // ── Export ────────────────────────────────────────────────────────────

  /// Erzeugt den Klartext-Inhalt: Kopfzeile mit Manifest, ein Event je
  /// Zeile, danach die Tabellen aus [kVaultTables].
  ///
  /// Ein Ausschnitt (`from`/`to` gesetzt) bekommt keine Tabellen: Diese
  /// Zeilen tragen keinen Zeitbezug, den man sinnvoll beschneiden könnte —
  /// ein halber Reizkanal wäre schlimmer als keiner.
  Future<String> buildPlaintext({DateTime? from, DateTime? to}) async {
    final events = await store.query(from: from, to: to);
    final complete = from == null && to == null;
    final manifest = VaultManifest(
      schemaVersion: '$kSchemaVersion',
      createdAt: clock.nowUtc(),
      eventCount: events.length,
      from: from,
      to: to,
      tables: complete ? kVaultTables : const [],
    );

    final buffer = StringBuffer()
      ..writeln(jsonEncode(manifest.toJson()));
    for (final event in events) {
      buffer.writeln(jsonEncode(event.toJson()));
    }
    if (complete) {
      for (final table in kVaultTables) {
        for (final row in _tableRows(table)) {
          buffer.writeln(jsonEncode({'table': table, 'row': row}));
        }
      }
    }
    return buffer.toString();
  }

  /// Alle Zeilen einer Tabelle, als JSON-taugliche Abbildung.
  List<Map<String, Object?>> _tableRows(String table) {
    final rows = store.rawDatabase.select('SELECT * FROM $table ORDER BY rowid');
    final out = <Map<String, Object?>>[];
    for (final row in rows) {
      if (table == 'settings' && kVaultLocalSettings.contains(row['key'])) {
        continue;
      }
      final map = <String, Object?>{};
      for (final column in row.keys) {
        map[column] = _jsonValue(table, column, row[column]);
      }
      out.add(map);
    }
    return out;
  }

  /// Fail-fast statt stiller Umdeutung: Eine Spalte, die sich nicht als
  /// JSON schreiben lässt (heute gibt es keine), würde beim Import etwas
  /// anderes bedeuten als beim Export. Lieber ein Abbruch mit Namen.
  static Object? _jsonValue(String table, String column, Object? value) {
    if (value == null || value is num || value is String || value is bool) {
      return value;
    }
    throw VaultError(
      'Spalte $table.$column lässt sich nicht exportieren '
      '(${value.runtimeType}).',
    );
  }

  /// Verschlüsselter Export.
  ///
  /// Aufbau: `AXIOMVAULT1` + Salz (16) + Nonce (16) + Chiffrat + HMAC (32).
  /// Die Prüfsumme steht am Ende und deckt Salz, Nonce und Chiffrat ab —
  /// eine veränderte Datei fällt beim Import auf, statt stillen Datenmüll
  /// zu erzeugen.
  Future<Uint8List> export({
    required String passphrase,
    DateTime? from,
    DateTime? to,
  }) async {
    if (passphrase.length < 8) {
      throw VaultError(
        'Kennwort zu kurz. Mindestens acht Zeichen — die Datei enthält '
        'Gesundheitsdaten.',
      );
    }

    return seal(await buildPlaintext(from: from, to: to), passphrase);
  }

  /// Verschlüsselt einen fertigen Klartext.
  ///
  /// Eigener Schritt, damit ein Test eine Datei im alten Format bauen und
  /// prüfen kann, dass der Import sie weiterhin liest — ohne die Krypto
  /// nachzubauen.
  @visibleForTesting
  Uint8List seal(String plaintext, String passphrase) {
    final bytes = utf8.encode(plaintext);
    final salt = _randomBytes(16);
    final nonce = _randomBytes(16);
    final keys = _deriveKeys(passphrase, salt, kdfRounds);

    final ciphertext = _xorStream(bytes, keys.cipher, nonce);

    final body = Uint8List.fromList([
      ...utf8.encode(kVaultMagic),
      ...salt,
      ...nonce,
      ...ciphertext,
    ]);
    final tag = Hmac(sha256, keys.mac).convert(body).bytes;

    return Uint8List.fromList([...body, ...tag]);
  }

  // ── Import ────────────────────────────────────────────────────────────

  /// Liest einen Export und spielt fehlende Events und Tabellenzeilen ein.
  ///
  /// **Append-only bleibt append-only:** Vorhandene Events werden nicht
  /// überschrieben, sondern übersprungen. Damit ist der Import wiederholbar
  /// und zwei Geräte konvergieren, ohne dass etwas verlorengeht — Events
  /// sind unveränderlich, ihre Vereinigung ist konfliktfrei.
  ///
  /// **Für Tabellenzeilen gilt dieselbe Richtung:** Was am Zielgerät schon
  /// unter derselben ID steht, bleibt stehen; ergänzt wird nur, was fehlt.
  /// Ein Import kann damit nichts überschreiben — die Frage „welche Fassung
  /// des Ankers gilt jetzt" stellt sich gar nicht erst.
  Future<VaultImportResult> import({
    required Uint8List data,
    required String passphrase,
    bool dryRun = false,
  }) async {
    final magic = utf8.encode(kVaultMagic);
    if (data.length < magic.length + 16 + 16 + 32) {
      throw VaultError('Datei zu kurz oder beschädigt.');
    }
    if (!_constantTimeEquals(
        data.sublist(0, magic.length), Uint8List.fromList(magic))) {
      throw VaultError('Keine AXIOM-Exportdatei.');
    }

    final bodyEnd = data.length - 32;
    final body = data.sublist(0, bodyEnd);
    final tag = data.sublist(bodyEnd);

    final salt = data.sublist(magic.length, magic.length + 16);
    final nonce = data.sublist(magic.length + 16, magic.length + 32);
    final ciphertext = data.sublist(magic.length + 32, bodyEnd);

    final keys = _deriveKeys(passphrase, salt, kdfRounds);
    final expected = Hmac(sha256, keys.mac).convert(body).bytes;
    if (!_constantTimeEquals(
        Uint8List.fromList(expected), Uint8List.fromList(tag))) {
      // Ein falsches Kennwort und eine veraenderte Datei sind hier nicht
      // unterscheidbar — und das ist richtig so.
      throw VaultError(
        'Kennwort falsch oder Datei verändert. Es wurde nichts eingespielt.',
      );
    }

    final plaintext = utf8.decode(_xorStream(ciphertext, keys.cipher, nonce));
    final lines =
        plaintext.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) throw VaultError('Datei enthält keine Daten.');

    final manifest = VaultManifest.fromJson(
      jsonDecode(lines.first) as Map<String, Object?>,
    );

    var imported = 0;
    var skipped = 0;
    var rejected = 0;
    var rowsImported = 0;
    var rowsSkipped = 0;

    // **Ganz oder gar nicht.** Vorher lief der Import ohne Klammer: Warf der
    // Wiederaufbau am Ende, waren die Ereignisse trotzdem da — und weil ein
    // Wiederaufbau nur bei `imported > 0` ausgelöst wird, meldete jeder
    // weitere Versuch Erfolg, ohne die Projektion je wieder aufzubauen.
    //
    // Der Probelauf ist derselbe Weg mit Rücknahme am Ende: So sagt er
    // genau das voraus, was ein echter Lauf tut, statt es zu schätzen.
    final db = store.rawDatabase;
    final shapes = <String, _TableShape>{};
    db.execute('SAVEPOINT axiom_import');
    try {
      for (final line in lines.skip(1)) {
        try {
          final decoded = jsonDecode(line) as Map<String, Object?>;

          // Tabellenzeile (Format 2) oder Ereignis? Ereignisse tragen kein
          // `table`-Feld, die Unterscheidung braucht keine Version.
          final table = decoded['table'];
          if (table is String) {
            if (_importRow(table, decoded['row'], shapes)) {
              rowsImported++;
            } else {
              rowsSkipped++;
            }
            continue;
          }

          final event = Event.fromJson(decoded);
          final existing = await store.query(
            from: event.at,
            to: event.at.add(const Duration(milliseconds: 1)),
          );
          if (existing.any((e) => e.id == event.id)) {
            skipped++;
            continue;
          }
          await store.append(event);
          imported++;
        } on Object {
          // Eine unlesbare Zeile darf den ganzen Import nicht kippen —
          // sie wird gezählt und gemeldet.
          rejected++;
        }
      }

      if (imported > 0) await store.rebuildProjections();

      if (dryRun) db.execute('ROLLBACK TO axiom_import');
    } on Object {
      db.execute('ROLLBACK TO axiom_import');
      rethrow;
    } finally {
      db.execute('RELEASE axiom_import');
    }

    return VaultImportResult(
      manifest: manifest,
      imported: imported,
      skipped: skipped,
      rejected: rejected,
      rowsImported: rowsImported,
      rowsSkipped: rowsSkipped,
      dryRun: dryRun,
    );
  }

  /// Spielt eine Tabellenzeile ein. Gibt zurück, ob sie neu war.
  ///
  /// Wirft bei allem, was nicht passt — der Aufrufer zählt das als unlesbar.
  bool _importRow(
    String table,
    Object? row,
    Map<String, _TableShape> shapes,
  ) {
    // Ein Tabellenname aus einer fremden Datei geht nie ungeprüft in SQL.
    if (!kVaultTables.contains(table)) {
      throw VaultError('Unbekannter Abschnitt in der Datei: $table');
    }
    if (row is! Map) throw VaultError('Zeile ohne Inhalt in $table.');
    final data = row.cast<String, Object?>();

    // Auch beim Lesen: Ein fremder privater Schlüssel hat auf diesem Gerät
    // nichts zu suchen, egal wer die Datei geschrieben hat.
    if (table == 'settings' && kVaultLocalSettings.contains(data['key'])) {
      return false;
    }

    final shape = shapes.putIfAbsent(table, () => _TableShape.of(store, table));
    final columns = data.keys.where(shape.columns.contains).toList();
    if (columns.isEmpty) {
      throw VaultError('Zeile in $table passt zu keiner Spalte.');
    }

    // Vorhandenes bleibt vorhanden. Ohne Primärschlüssel — den gibt es in
    // keiner exportierten Tabelle — bliebe nur einfügen.
    if (shape.primaryKey.isNotEmpty) {
      final where = shape.primaryKey.map((c) => '$c IS ?').join(' AND ');
      final found = store.rawDatabase.select(
        'SELECT 1 FROM $table WHERE $where LIMIT 1',
        [for (final c in shape.primaryKey) data[c]],
      );
      if (found.isNotEmpty) return false;
    }

    store.rawDatabase.execute(
      'INSERT INTO $table (${columns.join(', ')}) '
      'VALUES (${List.filled(columns.length, '?').join(', ')})',
      [for (final c in columns) data[c]],
    );
    return true;
  }

  // ── Kryptografie ──────────────────────────────────────────────────────

  static ({List<int> cipher, List<int> mac}) _deriveKeys(
    String passphrase,
    List<int> salt,
    int rounds,
  ) {
    // Iterierte Ableitung nach PBKDF2-Muster. Die Rundenzahl ist der einzige
    // Schutz gegen Durchprobieren eines menschlichen Kennworts.
    var block = Hmac(sha256, utf8.encode(passphrase))
        .convert([...salt, 0, 0, 0, 1])
        .bytes;
    var result = List<int>.from(block);
    for (var i = 1; i < rounds; i++) {
      block = Hmac(sha256, utf8.encode(passphrase)).convert(block).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= block[j];
      }
    }
    // Getrennte Schlüssel für Chiffrat und Prüfsumme — denselben Schlüssel
    // für beides zu nehmen ist ein klassischer Fehler.
    return (
      cipher: Hmac(sha256, result).convert(utf8.encode('cipher')).bytes,
      mac: Hmac(sha256, result).convert(utf8.encode('mac')).bytes,
    );
  }

  /// Gegenstrom im Zählermodus: Für jeden Block wird aus Schlüssel, Nonce
  /// und Zähler ein Schlüsselstrom erzeugt und mit dem Klartext verrechnet.
  static Uint8List _xorStream(List<int> data, List<int> key, List<int> nonce) {
    final out = Uint8List(data.length);
    var offset = 0;
    var counter = 0;
    while (offset < data.length) {
      final block = Hmac(sha256, key)
          .convert([...nonce, ..._counterBytes(counter)])
          .bytes;
      for (var i = 0; i < block.length && offset < data.length; i++, offset++) {
        out[offset] = data[offset] ^ block[i];
      }
      counter++;
    }
    return out;
  }

  static List<int> _counterBytes(int counter) => [
        (counter >> 24) & 0xFF,
        (counter >> 16) & 0xFF,
        (counter >> 8) & 0xFF,
        counter & 0xFF,
      ];

  static final _rng = math.Random.secure();

  static Uint8List _randomBytes(int length) =>
      Uint8List.fromList(List.generate(length, (_) => _rng.nextInt(256)));

  /// Vergleich ohne frühen Abbruch — verrät nicht über die Laufzeit, an
  /// welcher Stelle zwei Prüfsummen auseinandergehen.
  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// Spalten und Primärschlüssel einer Tabelle, einmal gelesen.
@immutable
final class _TableShape {
  final Set<String> columns;
  final List<String> primaryKey;

  const _TableShape(this.columns, this.primaryKey);

  static _TableShape of(SqliteEventStore store, String table) {
    final info = store.rawDatabase.select('PRAGMA table_info($table)');
    final key = info.where((r) => (r['pk'] as int) > 0).toList()
      ..sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int));
    return _TableShape(
      info.map((r) => r['name'] as String).toSet(),
      key.map((r) => r['name'] as String).toList(),
    );
  }
}

@immutable
final class VaultImportResult {
  final VaultManifest manifest;
  final int imported;
  final int skipped;
  final int rejected;

  /// Zeilen aus den Tabellen neben dem Ereignisstrom — Anker, Reizkanäle,
  /// Trigger, Einstellungen und der Rest aus [kVaultTables].
  final int rowsImported;
  final int rowsSkipped;

  final bool dryRun;

  const VaultImportResult({
    required this.manifest,
    required this.imported,
    required this.skipped,
    required this.rejected,
    required this.dryRun,
    this.rowsImported = 0,
    this.rowsSkipped = 0,
  });

  String get summary {
    final parts = <String>[
      '$imported übernommen',
      if (rowsImported > 0) '$rowsImported Einträge ergänzt',
      if (skipped > 0) '$skipped bereits vorhanden',
      if (rejected > 0) '$rejected unlesbar',
    ];
    return '${parts.join(" · ")}${dryRun ? "  (Probelauf)" : ""}';
  }
}
