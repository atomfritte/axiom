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
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// Mindestanzahl Tage, bevor eine Aussage tragfähig ist.
const int kMinimumDays = 14;

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
  final result = Process.runSync('sqlite3', [
    path,
    '-json',
    "SELECT at, type, payload FROM events "
        "WHERE type IN ('checkin','sleep_window','sensation_slot',"
        "'focus_end','capture','task_completed') ORDER BY at ASC",
  ]);
  if (result.exitCode != 0) {
    stderr.writeln('sqlite3 fehlgeschlagen: ${result.stderr}');
    exit(1);
  }

  final raw = (result.stdout as String).trim();
  if (raw.isEmpty) {
    stdout.writeln('Keine auswertbaren Ereignisse gefunden.');
    exit(0);
  }

  final events = (jsonDecode(raw) as List)
      .cast<Map<String, Object?>>()
      .map((row) => (
            at: DateTime.fromMillisecondsSinceEpoch(row['at']! as int,
                isUtc: true).toLocal(),
            type: row['type']! as String,
            payload: (jsonDecode(row['payload']! as String) as Map)
                .cast<String, Object?>(),
          ))
      .toList();

  final days = events.isEmpty
      ? 0
      : events.last.at.difference(events.first.at).inDays + 1;

  stdout.writeln('═══ AXIOM Kalibrierung ═══');
  stdout.writeln('');
  stdout.writeln('Zeitraum:   $days Tage');
  stdout.writeln('Ereignisse: ${events.length}');
  stdout.writeln('');

  if (days < kMinimumDays) {
    stdout.writeln('⚠  Weniger als $kMinimumDays Tage.');
    stdout.writeln('   Die Vorschläge unten sind noch nicht tragfähig.');
    stdout.writeln('   Weitermessen — geratene Regeln sind schlimmer als');
    stdout.writeln('   gar keine (Risiko R3).');
    stdout.writeln('');
  }

  final checkins = events.where((e) => e.type == 'checkin').toList();
  if (checkins.length < 20) {
    stdout.writeln('Zu wenige Check-ins (${checkins.length}) für eine '
        'Auswertung. Mindestens 20 nötig.');
    exit(0);
  }

  // ── 1. Tagesrhythmus ────────────────────────────────────────────────
  stdout.writeln('── Leistungsfenster ────────────────────────────────');
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
    stdout.writeln('  Nicht genug Messpunkte je Tageszeit.');
  } else {
    // Stark und schwach dürfen sich nicht überlappen: Bei wenigen
    // Messzeitpunkten stünde dieselbe Stunde sonst in beiden Listen.
    final strongCount = (hourly.length / 2).floor().clamp(1, 3);
    final weakCount = (hourly.length - strongCount).clamp(0, 2);

    for (final h in hourly.take(strongCount)) {
      stdout.writeln('  ${_hh(h.hour)}  Energie ${h.avg.toStringAsFixed(2)}'
          '  (${h.n} Messungen)   ← stark');
    }
    for (final h in hourly.reversed.take(weakCount)) {
      stdout.writeln('  ${_hh(h.hour)}  Energie ${h.avg.toStringAsFixed(2)}'
          '  (${h.n} Messungen)   ← schwach');
    }

    final spread = hourly.first.avg - hourly.last.avg;
    stdout.writeln('');
    if (spread < 0.5) {
      stdout.writeln('  Der Unterschied ist gering (${spread.toStringAsFixed(2)}).');
      stdout.writeln('  → capacity.circadian eher senken als erhöhen.');
    } else {
      stdout.writeln('  → Hoch-Aktivierungsenergie-Aufgaben in die starken');
      stdout.writeln('    Fenster legen, nicht in die schwachen.');
    }
  }
  stdout.writeln('');

  // ── 2. Schlafkopplung ───────────────────────────────────────────────
  stdout.writeln('── Schlaf und Kapazität ────────────────────────────');
  final sleep = events.where((e) => e.type == 'sleep_window').toList();
  if (sleep.length < 7) {
    stdout.writeln('  Nur ${sleep.length} Nächte erfasst — mindestens 7 nötig.');
    stdout.writeln('  Bis dahin bleibt sleep_debt auf dem Startwert 0.30.');
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
      stdout.writeln('  Zu wenig Streuung für eine Aussage.');
    } else {
      stdout.writeln('  Korrelation Schlafschuld ↔ Energie: '
          '${r.toStringAsFixed(2)}  (n=${pairs.length})');
      // Negativ erwartet: mehr Schuld, weniger Energie.
      final suggested = (r.abs() * 0.6).clamp(0.15, 0.45);
      stdout.writeln('');
      stdout.writeln('  Vorschlag  capacity.sleep_debt: '
          '${suggested.toStringAsFixed(2)}   (bisher 0.30)');
      if (r > -0.2) {
        stdout.writeln('  Hinweis: Der Zusammenhang ist schwach. Entweder');
        stdout.writeln('  ist Schlaf hier weniger wirksam als angenommen,');
        stdout.writeln('  oder die Schätzungen streuen zu stark.');
      }
    }
  }
  stdout.writeln('');

  // ── 3. Reizzyklus ───────────────────────────────────────────────────
  stdout.writeln('── Reizbedarf ──────────────────────────────────────');
  final stim = checkins
      .map((e) => (e.payload['stim_need'] as num?)?.toDouble())
      .whereType<double>()
      .toList();
  if (stim.length < 15) {
    stdout.writeln('  Zu wenige Angaben (${stim.length}).');
  } else {
    final avg = stim.reduce((a, b) => a + b) / stim.length;
    final baseline = ((avg - 1) / 4 * 100).round();
    stdout.writeln('  Mittlerer Reizbedarf: ${avg.toStringAsFixed(2)} von 5');
    stdout.writeln('');
    stdout.writeln('  Vorschlag  sensation_need.baseline_drive: $baseline'
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
      final peak =
          counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
      stdout.writeln('  Höchster Bedarf typischerweise um ${_hh(peak.key)}.');
      stdout.writeln('  → Reiz-Slot davor einplanen, nicht danach.');
    }
  }
  stdout.writeln('');

  // ── 4. Erfassungsquote ──────────────────────────────────────────────
  stdout.writeln('── Erfassung ───────────────────────────────────────');
  final expected = days * 3;
  final rate = expected == 0 ? 0.0 : checkins.length / expected;
  stdout.writeln('  ${checkins.length} von $expected Check-ins '
      '(${(rate * 100).round()} %)');
  if (rate < 0.8) {
    stdout.writeln('');
    stdout.writeln('  ⚠  Unter 80 %. Das Abbruchkriterium von Stufe 1 ist');
    stdout.writeln('     gerissen: Bevor Module dazukommen, muss die');
    stdout.writeln('     Erfassung leichter werden — nicht das System');
    stdout.writeln('     größer.');
  }

  final byChannel = <String, int>{};
  for (final e in events.where((e) => e.type == 'capture')) {
    final via = e.payload['via'] as String? ?? 'app';
    byChannel[via] = (byChannel[via] ?? 0) + 1;
  }
  if (byChannel.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('  Genutzte Erfassungswege:');
    final sorted = byChannel.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final c in sorted) {
      stdout.writeln('    ${c.key.padRight(12)} ${c.value}');
    }
    stdout.writeln('  → Auf den meistgenutzten Weg optimieren, die');
    stdout.writeln('    ungenutzten entfernen.');
  }

  stdout.writeln('');
  stdout.writeln('════════════════════════════════════════════════════');
  stdout.writeln('Nichts davon wurde geschrieben. Die Vorschläge gehören');
  stdout.writeln('ins Wochen-Review und von dort — geprüft — nach');
  stdout.writeln('rules/core/weights.yaml. Danach dort setzen:');
  stdout.writeln('  calibration.status: calibrated');
  stdout.writeln('  calibration.last_calibrated: <Datum>');
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
