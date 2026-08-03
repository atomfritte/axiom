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

  const VaultManifest({
    required this.schemaVersion,
    required this.createdAt,
    required this.eventCount,
    this.from,
    this.to,
  });

  Map<String, Object?> toJson() => {
        'schema': schemaVersion,
        'created_at': createdAt.toIso8601String(),
        'events': eventCount,
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

  /// Erzeugt den Klartext-Inhalt: Kopfzeile mit Manifest, dann ein Event
  /// je Zeile.
  Future<String> buildPlaintext({DateTime? from, DateTime? to}) async {
    final events = await store.query(from: from, to: to);
    final manifest = VaultManifest(
      schemaVersion: '$kSchemaVersion',
      createdAt: clock.nowUtc(),
      eventCount: events.length,
      from: from,
      to: to,
    );

    final buffer = StringBuffer()
      ..writeln(jsonEncode(manifest.toJson()));
    for (final event in events) {
      buffer.writeln(jsonEncode(event.toJson()));
    }
    return buffer.toString();
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

    final plaintext = utf8.encode(await buildPlaintext(from: from, to: to));
    final salt = _randomBytes(16);
    final nonce = _randomBytes(16);
    final keys = _deriveKeys(passphrase, salt, kdfRounds);

    final ciphertext = _xorStream(plaintext, keys.cipher, nonce);

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

  /// Liest einen Export und spielt fehlende Events ein.
  ///
  /// **Append-only bleibt append-only:** Vorhandene Events werden nicht
  /// überschrieben, sondern übersprungen. Damit ist der Import wiederholbar
  /// und zwei Geräte konvergieren, ohne dass etwas verlorengeht — Events
  /// sind unveränderlich, ihre Vereinigung ist konfliktfrei.
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

    for (final line in lines.skip(1)) {
      try {
        final event = Event.fromJson(
          jsonDecode(line) as Map<String, Object?>,
        );
        final existing = await store.query(
          from: event.at,
          to: event.at.add(const Duration(milliseconds: 1)),
        );
        if (existing.any((e) => e.id == event.id)) {
          skipped++;
          continue;
        }
        if (!dryRun) await store.append(event);
        imported++;
      } on Object {
        // Ein unlesbares Event darf den ganzen Import nicht kippen —
        // es wird gezählt und gemeldet.
        rejected++;
      }
    }

    if (!dryRun && imported > 0) await store.rebuildProjections();

    return VaultImportResult(
      manifest: manifest,
      imported: imported,
      skipped: skipped,
      rejected: rejected,
      dryRun: dryRun,
    );
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

@immutable
final class VaultImportResult {
  final VaultManifest manifest;
  final int imported;
  final int skipped;
  final int rejected;
  final bool dryRun;

  const VaultImportResult({
    required this.manifest,
    required this.imported,
    required this.skipped,
    required this.rejected,
    required this.dryRun,
  });

  String get summary {
    final parts = <String>[
      '$imported übernommen',
      if (skipped > 0) '$skipped bereits vorhanden',
      if (rejected > 0) '$rejected unlesbar',
    ];
    return '${parts.join(" · ")}${dryRun ? "  (Probelauf)" : ""}';
  }
}
