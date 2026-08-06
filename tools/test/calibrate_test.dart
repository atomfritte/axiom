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

  // ── Die vorgeschlagenen Zahlen ──────────────────────────────────────
  //
  // Bis hierher war geprueft, *dass* ein Vorschlag entsteht. Was in ihm
  // steht, landet in `rules/core/weights.yaml` und damit in der
  // Kapazitaetsformel. Ab hier stehen bekannte Eingaben gegen die
  // erwarteten Gewichte.

  group('Vorschlag fuer capacity.sleep_debt', () {
    test('vollstaendige Gegenlaeufigkeit ergibt das Hoechstgewicht 0.45', () {
      // Schlafschuld hoch, Energie niedrig, ohne Ausnahme: r = -1.00.
      // Gedeckelt wird bei 0.45 — mehr als 45 % der Kapazitaet auf eine
      // einzige Groesse zu legen waere eine Formel mit einem Faktor.
      final report = calibrationReport(_baselineEvents()).join('\n');

      expect(report, contains('Korrelation Schlafschuld ↔ Energie: -1.00'));
      expect(report, contains('Vorschlag  capacity.sleep_debt: 0.45'));
    });

    test('ein mittlerer Zusammenhang ergibt ein mittleres Gewicht', () {
      // r = -0.57 → 0.6 · 0.57 = 0.34. Weder gedeckelt noch als schwach
      // markiert.
      final report = calibrationReport(
        _series(
          energy: const [4, 5, 3, 4, 5, 3, 4, 2, 3, 3],
          sleepDebt: const [0, 10, 20, 30, 40, 50, 60, 70, 80, 90],
        ),
      ).join('\n');

      expect(report, contains('Vorschlag  capacity.sleep_debt: 0.34'));
      expect(report, isNot(contains('Der Zusammenhang ist schwach')));
    });

    test('ein schwacher Zusammenhang wird nach unten gedeckelt und benannt',
        () {
      // r = -0.09 → 0.05, gedeckelt auf 0.15. Der Hinweis muss dabeistehen:
      // Ein Vorschlag ohne die Angabe, wie duenn er ist, waere eine Zahl
      // mit dem Anschein einer Messung.
      final report = calibrationReport(
        _series(
          energy: const [5, 1, 4, 5, 4, 2, 3, 4, 5, 2],
          sleepDebt: const [0, 10, 20, 30, 40, 50, 60, 70, 80, 90],
        ),
      ).join('\n');

      expect(report, contains('Vorschlag  capacity.sleep_debt: 0.15'));
      expect(report, contains('Der Zusammenhang ist schwach'));
    });

    test('eine gleichlaeufige Messung bekommt gar keinen Vorschlag', () {
      // Der teuerste Befund an dieser Datei: Hier stand `r.abs()`. Bei
      // r = +1.00 — mehr Schlafschuld ging mit *mehr* Energie einher —
      // schlug das Werkzeug 0.45 vor, das Hoechstgewicht fuer den
      // groessten Einzelfaktor der Kapazitaetsformel, und nannte den
      // Zusammenhang dabei „schwach". Ein Vorschlag, der dem Messwert
      // widerspricht, ist schlimmer als keiner.
      final report = calibrationReport(
        _series(
          energy: const [1, 1.4, 1.8, 2.2, 2.6, 3, 3.4, 3.8, 4.2, 4.6],
          sleepDebt: const [0, 10, 20, 30, 40, 50, 60, 70, 80, 90],
        ),
      ).join('\n');

      expect(report, contains('Korrelation Schlafschuld ↔ Energie: 1.00'));
      expect(report, isNot(contains('Vorschlag  capacity.sleep_debt')));
      expect(report, isNot(contains('Der Zusammenhang ist schwach')));
      expect(report, contains('capacity.sleep_debt bleibt'));
    });

    test('ohne Streuung in den Naechten gibt es keine Aussage', () {
      final report = calibrationReport(
        _series(
          energy: const [3, 4, 3, 4, 3, 4, 3, 4, 3, 4],
          sleepDebt: const [30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
        ),
      ).join('\n');

      expect(report, contains('Zu wenig Streuung'));
      expect(report, isNot(contains('Vorschlag  capacity.sleep_debt')));
    });

    test('eine Nacht ohne Check-in am selben Tag bildet kein Paar', () {
      // Die Zuordnung laeuft ueber den Kalendertag. Eine Nacht ohne
      // Tagesmessung darf nicht mit der Energie eines anderen Tages
      // verrechnet werden.
      final mitLuecke = _series(
        energy: const [5, 4.8, 4.6, 4.4, 4.2, 4, 3.8, 3.6, 3.4, 3.2],
        sleepDebt: const [0, 10, 20, 30, 40, 50, 60, 70, 80, 90],
      ).where((e) =>
          e.type != EventType.checkin.name || e.at.day != 5 + 3).toList();

      expect(calibrationReport(mitLuecke).join('\n'), contains('(n=9)'));
    });
  });

  group('Vorschlag fuer sensation_need.baseline_drive', () {
    test('der Reizbedarf wird linear von 1..5 auf 0..100 abgebildet', () {
      for (final (bedarf, erwartet) in [(1, 0), (2, 25), (3, 50), (5, 100)]) {
        final report = calibrationReport(
          _series(energy: const [3, 3, 3, 3, 3, 3, 3, 3, 3, 3], stim: bedarf),
        ).join('\n');
        expect(report,
            contains('sensation_need.baseline_drive: $erwartet'),
            reason: 'Reizbedarf $bedarf von 5');
      }
    });

    test('die Stunde mit dem hoechsten Bedarf wird genannt', () {
      // Nur abends hoher Bedarf. Der Reiz-Slot gehoert davor, nicht danach.
      final report = calibrationReport(
        _series(
          energy: const [3, 3, 3, 3, 3, 3, 3, 3, 3, 3],
          stimByHour: const {9: 2, 13: 2, 19: 5},
        ),
      ).join('\n');

      expect(report, contains('Mittlerer Reizbedarf: 3.00 von 5'));
      expect(report, contains('sensation_need.baseline_drive: 50'));
      expect(report, contains('Höchster Bedarf typischerweise um 19:00'));
    });

    test('ohne genug Angaben wird nichts vorgeschlagen', () {
      final wenige = _series(
        energy: const [3, 3, 3, 3, 3, 3, 3, 3, 3, 3],
      ).map((e) => e.type == EventType.checkin.name
          ? (at: e.at, type: e.type, payload: {'energy': e.payload['energy']})
          : e).toList();

      final report = calibrationReport(wenige).join('\n');
      expect(report, contains('Zu wenige Angaben (0)'));
      expect(report, isNot(contains('baseline_drive')));
    });
  });

  group('Leistungsfenster', () {
    test('stark und schwach nennen nie dieselbe Stunde', () {
      for (final stunden in [
        {9: 4.5, 19: 2.0},
        {9: 4.5, 13: 3.0, 19: 2.0},
        {6: 5.0, 9: 4.5, 12: 4.0, 15: 3.5, 18: 3.0, 21: 2.0},
      ]) {
        final report = calibrationReport(_hourly(stunden));
        final stark = _hoursMarked(report, 'stark');
        final schwach = _hoursMarked(report, 'schwach');

        expect(stark, isNotEmpty, reason: '$stunden');
        expect(schwach, isNotEmpty, reason: '$stunden');
        expect(stark.intersection(schwach), isEmpty,
            reason: 'Dieselbe Stunde stand in beiden Listen: $stunden');
      }
    });

    test('das staerkste Fenster steht oben, das schwaechste unten', () {
      final report = calibrationReport(
        _hourly(const {9: 4.5, 13: 3.0, 19: 2.0}),
      );
      expect(_hoursMarked(report, 'stark'), {'09:00'});
      expect(_hoursMarked(report, 'schwach'), {'19:00', '13:00'});
      expect(report.join('\n'), contains('in die starken'));
    });

    test('ein flacher Tag schlaegt vor, circadian zu senken', () {
      // Wer ueber den Tag gleich stark ist, braucht keinen Faktor dafuer.
      final report = calibrationReport(
        _hourly(const {9: 3.0, 13: 3.2, 19: 3.1}),
      ).join('\n');

      expect(report, contains('Der Unterschied ist gering (0.20)'));
      expect(report, contains('capacity.circadian eher senken'));
    });

    test('eine Stunde mit weniger als drei Messungen zaehlt nicht', () {
      final events = _hourly(const {9: 4.5, 19: 2.0});
      // Zwei einzelne Messungen um 03:00 — zu wenig fuer eine Aussage.
      events.addAll([
        (
          at: DateTime(2026, 1, 5, 3),
          type: EventType.checkin.name,
          payload: {'energy': 5.0, 'stim_need': 3}
        ),
        (
          at: DateTime(2026, 1, 6, 3),
          type: EventType.checkin.name,
          payload: {'energy': 5.0, 'stim_need': 3}
        ),
      ]);
      events.sort((a, b) => a.at.compareTo(b.at));

      final report = calibrationReport(events).join('\n');
      expect(report, isNot(contains('03:00')));
    });
  });

  group('Erfassungsquote', () {
    test('gemessen wird gegen drei Check-ins am Tag', () {
      final report = calibrationReport(
        _series(energy: const [3, 3, 3, 3, 3, 3, 3, 3, 3, 3]),
      ).join('\n');

      expect(report, contains('30 von 30 Check-ins (100 %)'));
      expect(report, isNot(contains('Abbruchkriterium')));
    });

    test('unter 80 % nennt es das Abbruchkriterium von Stufe 1', () {
      final report = calibrationReport(
        _series(
          energy: const [3, 3, 3, 3, 3, 3, 3, 3, 3, 3],
          hours: const [9, 19],
        ),
      ).join('\n');

      expect(report, contains('20 von 30 Check-ins (67 %)'));
      expect(report, contains('Abbruchkriterium von Stufe 1'));
      // Kein Vorwurf, sondern eine Folge: erst leichter erfassen, dann
      // weiterbauen.
      expect(report, contains('muss die'));
      expect(report, isNot(contains('!')));
    });

    test('die Erfassungswege stehen nach Haeufigkeit', () {
      final events = _series(energy: const [3, 3, 3, 3, 3, 3, 3, 3, 3, 3]);
      for (final (weg, anzahl) in [('widget', 5), ('share', 9), ('app', 2)]) {
        for (var i = 0; i < anzahl; i++) {
          events.add((
            at: DateTime(2026, 1, 6, 8, i),
            type: EventType.capture.name,
            payload: {'via': weg},
          ));
        }
      }
      events.sort((a, b) => a.at.compareTo(b.at));

      final zeilen = calibrationReport(events)
          .where((l) => RegExp(r'^\s{4}\w+\s+\d+$').hasMatch(l))
          .map((l) => l.trim().split(RegExp(r'\s+')).first)
          .toList();
      expect(zeilen, ['share', 'widget', 'app']);
    });
  });

  group('Einlesen', () {
    test('eine Zeile ohne Nutzlast bricht ab, statt still zu fehlen', () {
      // Fail-Fast wie im Kern: Eine stumm verworfene Nacht verschiebt den
      // Vorschlag, ohne dass jemand es sieht.
      expect(
        () => decodeEvents('[{"at": 0, "type": "checkin"}]'),
        throwsA(anything),
      );
    });

    test('der Zeitstempel wird als UTC gelesen und in Ortszeit gewandelt', () {
      // Die Tagesrhythmus-Auswertung fragt nach der Stunde auf der Uhr des
      // Nutzers — nicht nach der in Greenwich.
      final ms = DateTime.utc(2026, 1, 5, 8).millisecondsSinceEpoch;
      final gelesen = decodeEvents(
        '[{"at": $ms, "type": "checkin", "payload": "{\\"energy\\": 4}"}]',
      ).single;

      expect(gelesen.at,
          DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal());
      expect(gelesen.at.isUtc, isFalse);
      expect(gelesen.payload['energy'], 4);
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

/// Eine Tagesreihe: je Tag drei Check-ins mit derselben Energie, dazu — wo
/// [sleepDebt] eine Zahl nennt — eine erfasste Nacht.
///
/// Alle Check-ins eines Tages tragen denselben Wert, damit der Tagesmittel
/// wert genau dieser Wert ist. Sonst haengt die Korrelation an der
/// Mittelbildung statt an der Reihe, die der Test vorgibt.
///
/// Lokale Zeitstempel, wie bei [_baselineEvents]: Die Auswertung fragt nach
/// dem Kalendertag und der Stunde auf der Uhr des Nutzers.
List<CalibrationEvent> _series({
  required List<double> energy,
  List<int>? sleepDebt,
  int stim = 3,
  Map<int, int>? stimByHour,
  List<int> hours = const [9, 13, 19],
}) {
  final events = <CalibrationEvent>[];
  for (var day = 0; day < energy.length; day++) {
    for (final hour in hours) {
      events.add((
        at: DateTime(2026, 1, 5 + day, hour),
        type: EventType.checkin.name,
        payload: {
          'energy': energy[day],
          'stim_need': stimByHour?[hour] ?? stim,
        },
      ));
    }
    if (sleepDebt != null && day < sleepDebt.length) {
      events.add((
        at: DateTime(2026, 1, 5 + day, 7),
        type: EventType.sleepWindow.name,
        payload: {'est_debt_min': sleepDebt[day]},
      ));
    }
  }
  events.sort((a, b) => a.at.compareTo(b.at));
  return events;
}

/// Zehn Tage, je Stunde aus [energyPerHour] ein Check-in mit genau diesem
/// Wert — damit der Stundenmittelwert vorhersagbar ist.
List<CalibrationEvent> _hourly(Map<int, double> energyPerHour,
    {int days = 10}) {
  final events = <CalibrationEvent>[];
  for (var day = 0; day < days; day++) {
    for (final entry in energyPerHour.entries) {
      events.add((
        at: DateTime(2026, 1, 5 + day, entry.key),
        type: EventType.checkin.name,
        payload: {'energy': entry.value, 'stim_need': 3},
      ));
    }
  }
  events.sort((a, b) => a.at.compareTo(b.at));
  return events;
}

/// Die Stunden, die im Bericht mit [mark] ausgezeichnet sind.
Set<String> _hoursMarked(List<String> report, String mark) => report
    .where((l) => l.contains('← $mark'))
    .map((l) => l.trim().split(RegExp(r'\s+')).first)
    .toSet();

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
