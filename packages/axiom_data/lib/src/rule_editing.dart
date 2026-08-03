/// Regeln bearbeiten, speichern und wieder als YAML herausgeben.
///
/// **Warum die Datenbank und nicht die Datei.** Auf dem Telefon liegen
/// `rules/core/*.yaml` als Assets im Paket — sie sind nur lesbar. Eine im
/// Gerät bearbeitete Regel muss deshalb woanders landen. Sie kommt in eine
/// eigene Tabelle und wird beim Laden **über** das mitgelieferte Regelwerk
/// gelegt: gleiche `id` ersetzt vollständig, neue `id` kommt dazu — dieselbe
/// Overlay-Semantik wie `rules/personal/`.
///
/// **Warum YAML als Speicherform und nicht eine Spalte je Feld.** Damit eine
/// bearbeitete Regel unverändert nach `rules/` zurückkopiert werden kann. Ein
/// Editor, aus dem nichts mehr in die Versionskontrolle zurückfindet, würde
/// das Regelwerk in zwei Wahrheiten aufspalten — und G2 hängt daran, dass es
/// genau eine gibt.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'sqlite_event_store.dart';

/// Eine im Gerät bearbeitete Regel.
final class RuleOverride {
  final String id;
  final String yaml;
  final DateTime updatedAt;

  /// Bis wann sie stumm mitläuft. Null heißt: läuft bereits live.
  final DateTime? shadowUntil;

  /// Ob sie eine mitgelieferte Regel ersetzt (dann ist Zurücksetzen möglich)
  /// oder ganz neu ist (dann ist Zurücksetzen ein Löschen).
  final bool overridesShipped;

  const RuleOverride({
    required this.id,
    required this.yaml,
    required this.updatedAt,
    required this.overridesShipped,
    this.shadowUntil,
  });

  bool isShadowed(DateTime now) =>
      shadowUntil != null && now.isBefore(shadowUntil!);

  int shadowDaysLeft(DateTime now) => shadowUntil == null
      ? 0
      : shadowUntil!.difference(now).inHours ~/ 24 + 1;
}

/// Wie lange eine neue oder geänderte Regel stumm mitläuft.
///
/// Steht so in CLAUDE.md und ist keine Höflichkeit: Eine Regel, die sofort
/// spricht, wird an dem Tag beurteilt, an dem man sie geschrieben hat — und
/// an dem Tag hält man sie für richtig. Sieben Tage später sieht man, wie oft
/// sie *gefeuert hätte* und ob das jeweils gepasst hätte.
const Duration kShadowPeriod = Duration(days: 7);

extension RuleOverrideStore on SqliteEventStore {
  Database get _db => rawDatabase;

  List<RuleOverride> ruleOverrides() => _db
      .select('SELECT * FROM rule_overrides ORDER BY id')
      .map(_toOverride)
      .toList();

  RuleOverride? ruleOverride(String id) {
    final rows =
        _db.select('SELECT * FROM rule_overrides WHERE id = ?', [id]);
    return rows.isEmpty ? null : _toOverride(rows.first);
  }

  void saveRuleOverride({
    required String id,
    required String yaml,
    required bool overridesShipped,
    required DateTime updatedAt,
    DateTime? shadowUntil,
  }) {
    _db.execute(
      'INSERT INTO rule_overrides (id, yaml, updated_at, shadow_until, overrides) '
      'VALUES (?, ?, ?, ?, ?) '
      'ON CONFLICT(id) DO UPDATE SET yaml = excluded.yaml, '
      'updated_at = excluded.updated_at, shadow_until = excluded.shadow_until, '
      'overrides = excluded.overrides',
      [
        id,
        yaml,
        updatedAt.toUtc().millisecondsSinceEpoch,
        shadowUntil?.toUtc().millisecondsSinceEpoch,
        overridesShipped ? 1 : 0,
      ],
    );
  }

  void deleteRuleOverride(String id) =>
      _db.execute('DELETE FROM rule_overrides WHERE id = ?', [id]);

  /// Alle Overlays als ein YAML-Dokument, so wie `YamlRuleSource` es erwartet.
  ///
  /// Regeln, deren Schattenzeit noch läuft, werden auf `log_only` gesetzt:
  /// Sie laufen mit und werden protokolliert, aber sie sprechen nicht.
  String overrideDocument(DateTime now) {
    final parts = <String>[];
    for (final override in ruleOverrides()) {
      parts.add(override.isShadowed(now)
          ? _forceShadow(override.yaml)
          : override.yaml);
    }
    return parts.isEmpty ? '' : parts.join('\n');
  }

  RuleOverride _toOverride(Row row) => RuleOverride(
        id: row['id'] as String,
        yaml: row['yaml'] as String,
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int,
                    isUtc: true)
                .toLocal(),
        shadowUntil: row['shadow_until'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row['shadow_until'] as int,
                    isUtc: true)
                .toLocal(),
        overridesShipped: (row['overrides'] as int) == 1,
      );
}

/// Setzt die Aktion auf `log_only`, ohne den Rest anzutasten.
///
/// Am Text und nicht am Objekt, damit die gespeicherte Fassung genau die
/// bleibt, die nach Ablauf der Schattenzeit live geht — sonst müsste man sich
/// merken, was die Regel „eigentlich" tun sollte.
String _forceShadow(String yaml) => yaml.replaceFirstMapped(
      RegExp(r'^(\s*)action:.*$', multiLine: true),
      // replaceFirst ersetzt Gruppen NICHT — mit der String-Fassung stand
      // hier woertlich "$1action: log_only" im YAML, und die Regel liess
      // sich nicht mehr laden. Eine Schattenregel, die dabei verschwindet,
      // ist das Gegenteil dessen, wofuer der Schatten da ist.
      (m) => '${m.group(1)}action: log_only',
    );

// ── Serialisierung ──────────────────────────────────────────────────────

/// Eine Regel als YAML — in genau der Form, die `rules/` verwendet.
String ruleToYaml(Rule rule) {
  final out = StringBuffer()
    ..writeln('- id: ${rule.id}')
    ..writeln('  title: ${_quoted(rule.title)}');

  for (final entry in rule.titleTranslations.entries) {
    out.writeln('  title_${entry.key}: ${_quoted(entry.value)}');
  }
  if (rule.deficit != null) out.writeln('  deficit: ${rule.deficit}');

  out.write(_folded('rationale', rule.rationale));
  for (final entry in rule.rationaleTranslations.entries) {
    out.write(_folded('rationale_${entry.key}', entry.value));
  }

  out.writeln('  when:');
  out.write(_condition(rule.when.toMap(), 4));

  out.writeln('  then:');
  out.writeln('    action: ${rule.then.type.token}');
  if (rule.then.params.isNotEmpty) {
    out.writeln('    params: ${_flow(rule.then.params)}');
  }

  out
    ..writeln('  priority: ${rule.priority}')
    ..writeln('  severity: ${rule.severity.name}');

  final cooldown = <String, Object?>{
    'minutes': rule.cooldown.minInterval.inMinutes,
    if (rule.cooldown.maxPerDay != null) 'max_per_day': rule.cooldown.maxPerDay,
    if (rule.cooldown.exponentialBackoff) 'backoff': 'exponential',
  };
  out
    ..writeln('  cooldown: ${_flow(cooldown)}')
    ..writeln('  enabled: ${rule.enabled}');

  return out.toString();
}

String rulesToYaml(Iterable<Rule> rules) => rules.map(ruleToYaml).join('\n');

/// Bedingungsbaum als YAML-Block.
///
/// Blätter stehen inline (`capacity: { lt: 40 }`), Verzweigungen als Liste.
/// Dieselbe Form wie im handgeschriebenen Regelwerk — ein Export soll sich
/// nicht daran erkennen lassen, dass er aus dem Editor kommt.
String _condition(Map<String, Object?> node, int indent) {
  final pad = ' ' * indent;
  final key = node.keys.first;
  final value = node.values.first;

  if (key == 'all' || key == 'any') {
    final out = StringBuffer('$pad$key:\n');
    for (final child in value! as List) {
      final rendered =
          _condition((child as Map).cast<String, Object?>(), indent + 4);
      // Das erste Zeichen des Kindes bekommt den Listenstrich.
      out.write('$pad  - ${rendered.trimLeft()}');
    }
    return out.toString();
  }

  if (key == 'not') {
    final child = _condition((value! as Map).cast<String, Object?>(), indent + 2);
    return '$pad$key:\n$child';
  }

  if (key == 'time_between') {
    final range = (value! as List).map(_scalar).join(', ');
    return '$pad$key: [$range]\n';
  }

  return '$pad$key: ${_flow((value! as Map).cast<String, Object?>())}\n';
}

/// Fliessender Block fuer laengeren Text — bricht bei 72 Zeichen um.
String _folded(String key, String text) {
  final words = text.replaceAll(RegExp(r'\s+'), ' ').trim().split(' ');
  // `>-` statt `>`: gefalteter Block ohne abschliessenden Zeilenumbruch.
  // Mit `>` kommt der Text mit einem \n zurueck, den niemand geschrieben
  // hat — Original und Reimport waeren dann nicht mehr vergleichbar.
  final out = StringBuffer('  $key: >-\n');
  var line = StringBuffer('   ');
  for (final word in words) {
    if (line.length + word.length + 1 > 72) {
      out.writeln(line);
      line = StringBuffer('   ');
    }
    line.write(' $word');
  }
  if (line.toString().trim().isNotEmpty) out.writeln(line);
  return out.toString();
}

String _flow(Map<String, Object?> map) =>
    '{ ${map.entries.map((e) => '${e.key}: ${_scalar(e.value)}').join(', ')} }';

String _scalar(Object? value) {
  if (value is num || value is bool) return '$value';
  final text = '$value';
  // Unquotiert nur, wo YAML es garantiert wieder als String liest.
  return RegExp(r'^[A-Za-z][A-Za-z0-9_.-]*$').hasMatch(text)
      ? text
      : _quoted(text);
}

String _quoted(String text) =>
    '"${text.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
