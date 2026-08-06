/// Was dieses Werkzeug vorschlaegt, landet in `rules/core/weights.yaml` und
/// damit in der Kapazitaetsformel. Ein Werkzeug, das eine Zahl zum Eichen
/// einer Formel nennt, muss selbst geeicht sein.
///
/// Der teuerste Fehler war kein Rechenfehler, sondern ein Namensfehler: Die
/// Abfrage filterte auf `sleep_window`, gespeichert wird `sleepWindow`. Die
/// Auswertung war korrekt und bekam nie Daten zu sehen. Die ersten beiden
/// Tests halten genau diese Naht fest.
library;

import 'dart:convert';
import 'dart:io';

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import '../bin/calibrate.dart';
import 'tool_process.dart';

void main() {
  group('Abfrage', () {
    test('jeder abgefragte Typname existiert als EventType', () {
      final quoted = RegExp("'([A-Za-z_]+)'")
          .allMatches(eventQuery())
          .map((m) => m.group(1)!)
          .toList();
      expect(quoted, isNotEmpty);

      final known = EventType.values.map((t) => t.name).toSet();
      for (final name in quoted) {
        expect(
          known,
          contains(name),
          reason: '"$name" wird nie in events.type stehen — der Store '
              'schreibt event.type.name. Dieser Abschnitt der Kalibrierung '
              'bekaeme nie Daten zu sehen.',
        );
      }
    });

    test('die Abfrage nennt den Schlaftyp so, wie der Store ihn schreibt', () {
      expect(eventQuery(), contains("'${EventType.sleepWindow.name}'"));
      expect(eventQuery(), isNot(contains("'sleep_window'")));
    });
  });

  group('Auswertung', () {
    test('ohne Ereignisse sagt der Bericht genau das', () {
      expect(
        calibrationReport(const []),
        ['Keine auswertbaren Ereignisse gefunden.'],
      );
      expect(decodeEvents('   '), isEmpty);
    });

    test('erfasste Naechte ergeben einen Vorschlag fuer capacity.sleep_debt',
        () {
      final report = calibrationReport(_baselineEvents()).join('\n');

      expect(report, contains('Vorschlag  capacity.sleep_debt'));
      expect(report, isNot(contains('Nur 0 Nächte erfasst')));
      // Schlafschuld hoch, Energie niedrig — der erwartete Zusammenhang.
      expect(report, contains('Korrelation Schlafschuld ↔ Energie: -1.00'));
      expect(report, contains('(n=10)'));
    });

    test('ohne Naechte bleibt der Startwert stehen', () {
      final onlyCheckins =
          _baselineEvents().where((e) => e.type == EventType.checkin.name);
      final report = calibrationReport(onlyCheckins.toList()).join('\n');

      expect(report, contains('Nur 0 Nächte erfasst'));
      expect(report, contains('Startwert 0.30'));
      expect(report, isNot(contains('Vorschlag  capacity.sleep_debt')));
    });

    test('der Zeitraum wird aus dem ersten und letzten Ereignis gelesen', () {
      expect(
        calibrationReport(_baselineEvents()),
        contains('Zeitraum:   20 Tage'),
      );
    });

    test('unter 14 Tagen wird der Vorschlag als nicht tragfaehig markiert',
        () {
      final short = _baselineEvents()
          .where((e) => e.at.isBefore(DateTime(2026, 1, 15)))
          .toList();
      expect(
        calibrationReport(short).join('\n'),
        contains('Weniger als $kMinimumDays Tage'),
      );
    });

    test('unter 20 Check-ins wird nicht ausgewertet', () {
      final few = _baselineEvents()
          .where((e) => e.type == EventType.checkin.name)
          .take(19)
          .toList();
      final report = calibrationReport(few).join('\n');

      expect(report, contains('Zu wenige Check-ins (19)'));
      expect(report, isNot(contains('Leistungsfenster')));
    });

    test('der Bericht schlaegt vor und schreibt nichts', () {
      expect(
        calibrationReport(_baselineEvents()).join('\n'),
        contains('Nichts davon wurde geschrieben'),
      );
    });
  });

  group('Ende zu Ende gegen eine echte Datenbank', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('axiom_calibrate');
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('20 erfasste Naechte erscheinen im Bericht', () {
      final db = '${tmp.path}/axiom.db';
      _writeDatabase(db, _baselineEvents());

      final result = runTool('calibrate.dart', [db]);
      final out = result.stdout as String;

      expect(result.exitCode, 0, reason: result.stderr as String);
      expect(out, isNot(contains('Nur 0 Nächte erfasst')));
      expect(out, contains('Vorschlag  capacity.sleep_debt'));
    }, skip: hasSqlite3 ? null : 'sqlite3 nicht vorhanden');

    test('ohne Argument nennt es den adb-Weg und bricht ab', () {
      final result = runTool('calibrate.dart', const []);

      expect(result.exitCode, 2);
      expect(result.stderr as String, contains('adb exec-out run-as'));
    });

    test('eine fehlende Datei ist ein Abbruch, kein leerer Bericht', () {
      final result = runTool('calibrate.dart', ['${tmp.path}/gibtsnicht.db']);

      expect(result.exitCode, 2);
      expect(result.stderr as String, contains('Datei nicht gefunden'));
    });
  });
}

/// 20 Tage à 3 Check-ins, davon 10 Tage mit erfasster Nacht.
///
/// Lokale Zeitstempel, absichtlich: Die Tagesrhythmus-Auswertung fragt nach
/// der Stunde auf der Uhr des Nutzers, und die Zuordnung Nacht → Tag
/// vergleicht Kalendertage. Mit UTC-Zeitstempeln haenge das Ergebnis an der
/// Zeitzone des Rechners, auf dem der Test laeuft.
List<CalibrationEvent> _baselineEvents() {
  final events = <CalibrationEvent>[];
  for (var day = 0; day < 20; day++) {
    final energy = (5.0 - day * 0.2).clamp(1.0, 5.0);
    for (final hour in [9, 13, 19]) {
      events.add((
        at: DateTime(2026, 1, 5 + day, hour),
        type: EventType.checkin.name,
        payload: {'energy': energy, 'stim_need': 3},
      ));
    }
    if (day < 10) {
      events.add((
        at: DateTime(2026, 1, 5 + day, 7),
        type: EventType.sleepWindow.name,
        payload: {'est_debt_min': day * 10},
      ));
    }
  }
  events.sort((a, b) => a.at.compareTo(b.at));
  return events;
}

/// Legt eine Datenbank an, die dem entspricht, was `SqliteEventStore`
/// schreibt — insbesondere `type` als `EventType.name`.
void _writeDatabase(String path, List<CalibrationEvent> events) {
  final sql = StringBuffer(
    'CREATE TABLE events (id TEXT PRIMARY KEY, seq INTEGER, at INTEGER, '
    'type TEXT, source TEXT, payload TEXT, correction_of TEXT);',
  );
  var seq = 0;
  for (final e in events) {
    seq++;
    // Einfache Anfuehrungszeichen sind sicher: JSON kennt nur doppelte.
    sql.write("INSERT INTO events VALUES ('e$seq', $seq, "
        '${e.at.millisecondsSinceEpoch}, '
        "'${e.type}', 'user', '${jsonEncode(e.payload)}', NULL);");
  }
  final result = Process.runSync('sqlite3', [path, sql.toString()]);
  if (result.exitCode != 0) {
    throw StateError('sqlite3: ${result.stderr}');
  }
}
