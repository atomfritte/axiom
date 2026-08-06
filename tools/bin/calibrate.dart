/// Kalibrierung nach der Baseline.
///
///   dart run tools/bin/calibrate.dart <pfad/zu/axiom.db>
///
/// Wertet die 14 Tage Baseline-Daten aus und schlägt Gewichte für
/// `rules/core/weights.yaml` vor. **Es schreibt nichts.** Die Vorschläge
/// werden im Wochen-Review geprüft und von Hand übernommen — eine
/// Automatik, die still an den Formeln dreht, wäre genau die Blackbox,
/// die dieses System vermeiden soll (G2).
///
/// Was hier passiert, ist bewusst simple Statistik: Mittelwerte,
/// Korrelationen, Perzentile. Kein Modell, kein Lernen. Bei einem Nutzer
/// und 14 Tagen wäre alles andere Zahlenmystik — und ein Systemizer merkt
/// das sofort.
///
/// Aufbau: `main()` macht ausschliesslich I/O, die Auswertung ist eine
/// reine Funktion (`calibrationReport`). Nur so laesst sich pruefen, dass
/// ein Werkzeug, das Zahlen zum Eichen einer Formel vorschlaegt, die
/// richtigen Zahlen vorschlaegt (tools/test/calibrate_test.dart).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:axiom_core/axiom_core.dart';

/// Mindestanzahl Tage, bevor eine Aussage tragfähig ist.
const int kMinimumDays = 14;

/// Welche Ereignisse die Kalibrierung liest.
///
/// Als `EventType`, nicht als Zeichenkette: Der Store schreibt
/// `event.type.name` (`sqlite_event_store.dart`, `INSERT INTO events`), also
/// `sleepWindow` und nicht `sleep_window`. Vorher standen hier von Hand
/// getippte Namen in Schlangenschrift; drei der sechs trafen deshalb nie zu,
/// und der Abschnitt „Schlaf und Kapazität" — der Vorschlag fuer den
/// groessten Einzelfaktor der Kapazitaetsformel — meldete auch nach Jahren
/// „Nur 0 Nächte erfasst". Ueber das Enum kann derselbe Fehler nicht
/// wiederkommen: ein falscher Name uebersetzt nicht mehr.
///
/// `sensationSlot`, `focusEnd` und `taskCompleted` werden nicht ausgewertet,
/// aber mitgelesen: Sie tragen den gemessenen Zeitraum (`Zeitraum: n Tage`)
/// auch dann, wenn an einem Tag nur gearbeitet und nicht eingecheckt wurde.
const Set<EventType> kAnalysedTypes = {
  EventType.checkin,
  EventType.sleepWindow,
  EventType.sensationSlot,
  EventType.focusEnd,
  EventType.capture,
  EventType.taskCompleted,
};

/// Ein Ereignis in der Form, die die Auswertung braucht.
///
/// `at` ist lokale Zeit — die Tagesrhythmus-Auswertung fragt nach der
/// Stunde, und die Stunde, die zaehlt, ist die auf der Uhr des Nutzers.
typedef CalibrationEvent = ({
  DateTime at,
  String type,
  Map<String, Object?> payload,
});

/// Die Abfrage, mit der die Ereignisse geholt werden.
String eventQuery() {
  final types = kAnalysedTypes.map((t) => "'${t.name}'").join(',');
  return 'SELECT at, type, payload FROM events '
      'WHERE type IN ($types) ORDER BY at ASC';
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Aufruf: dart run tools/bin/calibrate.dart <axiom.db>');
    stderr.writeln('');
    stderr.writeln('Die Datenbank liegt auf dem Gerät unter');
    stderr.writeln('  /data/data/de.atomfritte.axiom/files/axiom.db');
    stderr.writeln('Holen mit:');
    stderr.writeln('  adb exec-out run-as de.atomfritte.axiom '
        'cat files/axiom.db > axiom.db');
    exit(2);
  }

  final path = args.first;
  if (!File(path).existsSync()) {
    stderr.writeln('Datei nicht gefunden: $path');
    exit(2);
  }

  // sqlite3 als Kommandozeilenwerkzeug — spart dem Tool eine Abhängigkeit,
  // die nur hier gebraucht würde.
  final result = Process.runSync('sqlite3', [path, '-json', eventQuery()]);
  if (result.exitCode != 0) {
    stderr.writeln('sqlite3 fehlgeschlagen: ${result.stderr}');
    exit(1);
  }

  for (final line in calibrationReport(decodeEvents(result.stdout as String))) {
    stdout.writeln(line);
  }
}

/// Wandelt die JSON-Ausgabe von `sqlite3 -json` in Ereignisse.
///
/// Fail-Fast wie im Kern: Eine Zeile, die nicht passt, wird nicht
/// uebersprungen. Eine stumm verworfene Nacht verschiebt den Vorschlag,
/// ohne dass jemand es sieht.
List<CalibrationEvent> decodeEvents(String json) {
  final raw = json.trim();
  if (raw.isEmpty) return const [];
  return (jsonDecode(raw) as List).cast<Map<String, Object?>>().map((row) {
    final payload = jsonDecode(row['payload']! as String) as Map;
    return (
      at: DateTime.fromMillisecondsSinceEpoch(
        row['at']! as int,
        isUtc: true,
      ).toLocal(),
      type: row['type']! as String,
      payload: payload.cast<String, Object?>(),
    );
  }).toList();
}

/// Die Auswertung. Rein: gleiche Ereignisse, gleiche Zeilen.
List<String> calibrationReport(List<CalibrationEvent> events) {
  final out = <String>[];
  if (events.isEmpty) {
    out.add('Keine auswertbaren Ereignisse gefunden.');
    return out;
  }

  final days = events.last.at.difference(events.first.at).inDays + 1;

  out.add('═══ AXIOM Kalibrierung ═══');
  out.add('');
  out.add('Zeitraum:   $days Tage');
  out.add('Ereignisse: ${events.length}');
  out.add('');

  if (days < kMinimumDays) {
    out.add('⚠  Weniger als $kMinimumDays Tage.');
    out.add('   Die Vorschläge unten sind noch nicht tragfähig.');
    out.add('   Weitermessen — geratene Regeln sind schlimmer als');
    out.add('   gar keine (Risiko R3).');
    out.add('');
  }

  final checkins =
      events.where((e) => e.type == EventType.checkin.name).toList();
  if (checkins.length < 20) {
    out.add('Zu wenige Check-ins (${checkins.length}) für eine '
        'Auswertung. Mindestens 20 nötig.');
    return out;
  }

  // ── 1. Tagesrhythmus ────────────────────────────────────────────────
  out.add('── Leistungsfenster ────────────────────────────────');
  final byHour = <int, List<double>>{};
  for (final e in checkins) {
    final energy = (e.payload['energy'] as num?)?.toDouble();
    if (energy == null) continue;
    byHour.putIfAbsent(e.at.hour, () => []).add(energy);
  }
  final hourly = byHour.entries
      .where((e) => e.value.length >= 3)
      .map((e) => (
            hour: e.key,
            avg: e.value.reduce((a, b) => a + b) / e.value.length,
            n: e.value.length,
          ))
      .toList()
    ..sort((a, b) => b.avg.compareTo(a.avg));

  if (hourly.isEmpty) {
    out.add('  Nicht genug Messpunkte je Tageszeit.');
  } else {
    // Stark und schwach dürfen sich nicht überlappen: Bei wenigen
    // Messzeitpunkten stünde dieselbe Stunde sonst in beiden Listen.
    final strongCount = (hourly.length / 2).floor().clamp(1, 3);
    final weakCount = (hourly.length - strongCount).clamp(0, 2);

    for (final h in hourly.take(strongCount)) {
      out.add('  ${_hh(h.hour)}  Energie ${h.avg.toStringAsFixed(2)}'
          '  (${h.n} Messungen)   ← stark');
    }
    for (final h in hourly.reversed.take(weakCount)) {
      out.add('  ${_hh(h.hour)}  Energie ${h.avg.toStringAsFixed(2)}'
          '  (${h.n} Messungen)   ← schwach');
    }

    final spread = hourly.first.avg - hourly.last.avg;
    out.add('');
    if (spread < 0.5) {
      out.add('  Der Unterschied ist gering (${spread.toStringAsFixed(2)}).');
      out.add('  → capacity.circadian eher senken als erhöhen.');
    } else {
      out.add('  → Hoch-Aktivierungsenergie-Aufgaben in die starken');
      out.add('    Fenster legen, nicht in die schwachen.');
    }
  }
  out.add('');

  // ── 2. Schlafkopplung ───────────────────────────────────────────────
  out.add('── Schlaf und Kapazität ────────────────────────────');
  final sleep =
      events.where((e) => e.type == EventType.sleepWindow.name).toList();
  if (sleep.length < 7) {
    out.add('  Nur ${sleep.length} Nächte erfasst — mindestens 7 nötig.');
    out.add('  Bis dahin bleibt sleep_debt auf dem Startwert 0.30.');
  } else {
    final pairs = <(double debt, double energy)>[];
    for (final night in sleep) {
      final debt = (night.payload['est_debt_min'] as num?)?.toDouble();
      if (debt == null) continue;
      final sameDay = checkins.where((c) =>
          c.at.year == night.at.year &&
          c.at.month == night.at.month &&
          c.at.day == night.at.day);
      final energies = sameDay
          .map((c) => (c.payload['energy'] as num?)?.toDouble())
          .whereType<double>();
      if (energies.isEmpty) continue;
      pairs.add((
        debt,
        energies.reduce((a, b) => a + b) / energies.length,
      ));
    }

    final r = _correlation(
      pairs.map((p) => p.$1).toList(),
      pairs.map((p) => p.$2).toList(),
    );
    if (r == null) {
      out.add('  Zu wenig Streuung für eine Aussage.');
    } else {
      out.add('  Korrelation Schlafschuld ↔ Energie: '
          '${r.toStringAsFixed(2)}  (n=${pairs.length})');
      // Negativ erwartet: mehr Schuld, weniger Energie.
      final suggested = (r.abs() * 0.6).clamp(0.15, 0.45);
      out.add('');
      out.add('  Vorschlag  capacity.sleep_debt: '
          '${suggested.toStringAsFixed(2)}   (bisher 0.30)');
      if (r > -0.2) {
        out.add('  Hinweis: Der Zusammenhang ist schwach. Entweder');
        out.add('  ist Schlaf hier weniger wirksam als angenommen,');
        out.add('  oder die Schätzungen streuen zu stark.');
      }
    }
  }
  out.add('');

  // ── 3. Reizzyklus ───────────────────────────────────────────────────
  out.add('── Reizbedarf ──────────────────────────────────────');
  final stim = checkins
      .map((e) => (e.payload['stim_need'] as num?)?.toDouble())
      .whereType<double>()
      .toList();
  if (stim.length < 15) {
    out.add('  Zu wenige Angaben (${stim.length}).');
  } else {
    final avg = stim.reduce((a, b) => a + b) / stim.length;
    final baseline = ((avg - 1) / 4 * 100).round();
    out.add('  Mittlerer Reizbedarf: ${avg.toStringAsFixed(2)} von 5');
    out.add('');
    out.add('  Vorschlag  sensation_need.baseline_drive: $baseline'
        '   (bisher 45)');

    // Ab welchem Wert brechen Impulse durch?
    final highHours = checkins
        .where((e) => ((e.payload['stim_need'] as num?) ?? 0) >= 4)
        .map((e) => e.at.hour)
        .toList();
    if (highHours.isNotEmpty) {
      final counts = <int, int>{};
      for (final h in highHours) {
        counts[h] = (counts[h] ?? 0) + 1;
      }
      final peak = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
      out.add('  Höchster Bedarf typischerweise um ${_hh(peak.key)}.');
      out.add('  → Reiz-Slot davor einplanen, nicht danach.');
    }
  }
  out.add('');

  // ── 4. Erfassungsquote ──────────────────────────────────────────────
  out.add('── Erfassung ───────────────────────────────────────');
  final expected = days * 3;
  final rate = expected == 0 ? 0.0 : checkins.length / expected;
  out.add('  ${checkins.length} von $expected Check-ins '
      '(${(rate * 100).round()} %)');
  if (rate < 0.8) {
    out.add('');
    out.add('  ⚠  Unter 80 %. Das Abbruchkriterium von Stufe 1 ist');
    out.add('     gerissen: Bevor Module dazukommen, muss die');
    out.add('     Erfassung leichter werden — nicht das System');
    out.add('     größer.');
  }

  final byChannel = <String, int>{};
  for (final e in events.where((e) => e.type == EventType.capture.name)) {
    final via = e.payload['via'] as String? ?? 'app';
    byChannel[via] = (byChannel[via] ?? 0) + 1;
  }
  if (byChannel.isNotEmpty) {
    out.add('');
    out.add('  Genutzte Erfassungswege:');
    final sorted = byChannel.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final c in sorted) {
      out.add('    ${c.key.padRight(12)} ${c.value}');
    }
    out.add('  → Auf den meistgenutzten Weg optimieren, die');
    out.add('    ungenutzten entfernen.');
  }

  out.add('');
  out.add('════════════════════════════════════════════════════');
  out.add('Nichts davon wurde geschrieben. Die Vorschläge gehören');
  out.add('ins Wochen-Review und von dort — geprüft — nach');
  out.add('rules/core/weights.yaml. Danach dort setzen:');
  out.add('  calibration.status: calibrated');
  out.add('  calibration.last_calibrated: <Datum>');
  return out;
}

String _hh(int hour) => '${hour.toString().padLeft(2, "0")}:00';

/// Pearson-Korrelation. Null, wenn eine Reihe keine Streuung hat.
double? _correlation(List<double> xs, List<double> ys) {
  if (xs.length < 5 || xs.length != ys.length) return null;
  final n = xs.length;
  final mx = xs.reduce((a, b) => a + b) / n;
  final my = ys.reduce((a, b) => a + b) / n;

  var num = 0.0;
  var dx = 0.0;
  var dy = 0.0;
  for (var i = 0; i < n; i++) {
    final a = xs[i] - mx;
    final b = ys[i] - my;
    num += a * b;
    dx += a * a;
    dy += b * b;
  }
  if (dx == 0 || dy == 0) return null;
  return num / math.sqrt(dx * dy);
}
