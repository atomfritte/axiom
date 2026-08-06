/// Aggregiert den Event-Strom zu [Signals] fuer den StateDeriver.
///
/// Hier faellt auch die Konfidenz an: Je aelter die zugrunde liegenden Daten,
/// desto niedriger. Regeln unterhalb der Schwelle feuern nicht — lieber
/// schweigen als raten (Risiko R8).
library;

import 'package:axiom_core/axiom_core.dart';

import 'sqlite_event_store.dart';

/// Wie schnell die Konfidenz mit dem Datenalter faellt.
const Duration kCheckinFreshness = Duration(hours: 8);
const Duration kSleepFreshness = Duration(hours: 30);

/// Wie viele Minuten Schlaf eine Nacht haben soll.
///
/// Dieselbe Annahme wie bei der Handeingabe, damit importierte und getippte
/// Naechte vergleichbar bleiben. Nach der Eichung tritt das persoenliche
/// Soll an diese Stelle.
const int kSleepTargetMinutes = 7 * 60;

final class SignalAggregator {
  final SqliteEventStore store;
  final Clock clock;

  const SignalAggregator({required this.store, required this.clock});

  Future<Signals> aggregate() async {
    final nowUtc = clock.nowUtc();
    final nowLocal = clock.nowLocal();
    final dayStart = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final weekAgo = nowUtc.subtract(const Duration(days: 7));

    final checkins = await store.query(
      from: weekAgo,
      types: {EventType.checkin},
    );
    final sleep = await store.query(
      from: nowUtc.subtract(const Duration(days: 7)),
      types: {EventType.sleepWindow},
    );
    final slots = await store.query(
      from: nowUtc.subtract(const Duration(hours: 24)),
      types: {EventType.sensationSlot},
    );
    final focus = await store.query(
      from: dayStart.toUtc(),
      types: {EventType.focusEnd},
    );
    final incidents = await store.query(
      from: nowUtc.subtract(const Duration(hours: 72)),
      types: {EventType.signalIncident},
    );

    final latestCheckin = checkins.isEmpty ? null : checkins.last;
    final todaysCheckins = checkins
        .where((e) => !e.at.toLocal().isBefore(dayStart))
        .toList();

    // ── Schlafschuld ────────────────────────────────────────────────────
    final sleepDebtNorm = _sleepDebtNorm(sleep);

    // ── Fokuslast heute ─────────────────────────────────────────────────
    final focusMinutes = focus.fold<double>(
      0,
      (sum, e) => sum + ((e.payload['actual_min'] as num?)?.toDouble() ?? 0),
    );
    final focusDebt = (focusMinutes / 300 * 100).clamp(0, 100);

    // ── Aus Check-ins abgeleitet (Skala 1..5 -> 0..100) ─────────────────
    double? avgOrNull(String key, List<Event> from) {
      final values = from
          .map((e) => (e.payload[key] as num?)?.toDouble())
          .whereType<double>()
          .toList();
      if (values.isEmpty) return null;
      return values.reduce((a, b) => a + b) / values.length;
    }

    double avgOf(String key, List<Event> from, double fallback) =>
        avgOrNull(key, from) ?? fallback;

    final recovery = _scale(avgOf('recovery', checkins, 3.5));
    final compensation = _scale(avgOf('compensation', checkins, 2.5));
    final irritability = _irritability(checkins);

    // Vorher stand hier `_scale(avgOf('withdrawal', checkins, 1.5))`. Den
    // Schluessel `withdrawal` schreibt kein Check-in — der Rueckfallwert war
    // damit kein Rueckfall, sondern der einzige je benutzte Wert:
    // `socialWithdrawal` lag konstant bei 12,5 und in der Herleitung von
    // `load_index` stand dauerhaft „Sozialer Rückzug +1.3", als waere er
    // gemessen. Eine erfundene Zahl in einer sichtbaren Herleitung ist
    // genau das, was G2 ausschliesst. Ohne Messung traegt der Term deshalb
    // nichts bei; sobald ein Check-in den Wert liefert, rechnet er mit.
    final measuredWithdrawal = avgOrNull('withdrawal', checkins);
    final withdrawal =
        measuredWithdrawal == null ? 0.0 : _scale(measuredWithdrawal);

    // ── Reizbedarf ──────────────────────────────────────────────────────
    final relief = slots.fold<double>(0, (sum, e) {
      final intensity = (e.payload['intensity'] as num?)?.toDouble() ?? 3;
      final minutes = (e.payload['duration_min'] as num?)?.toDouble() ?? 30;
      return sum + intensity * minutes / 30;
    });
    // Niedrigreiz-Zeit zaehlt ab dem Aufwachen, nicht ab Mitternacht —
    // sonst waere der Reizbedarf schon beim Fruehstueck am Anschlag.
    final wokeAt = _wakeTime(sleep, nowLocal);
    final lastSlot = slots.isEmpty ? null : slots.last.at;
    final since = lastSlot ?? wokeAt.toUtc();
    final lowStimulusMinutes =
        nowUtc.difference(since).inMinutes.clamp(0, 16 * 60).toDouble();

    // ── Emotionale Regulation ───────────────────────────────────────────
    final incidentPressure = incidents.fold<double>(0, (sum, e) {
      final intensity = (e.payload['intensity'] as num?)?.toDouble() ?? 3;
      final ageHours = nowUtc.difference(e.at).inMinutes / 60;
      final decay = (1 - ageHours / 72).clamp(0.0, 1.0);
      return sum + intensity * 8 * decay;
    });

    // ── Konfidenz ───────────────────────────────────────────────────────
    final checkinAge = latestCheckin == null
        ? const Duration(days: 99)
        : nowUtc.difference(latestCheckin.at);
    final checkinConfidence = _freshness(checkinAge, kCheckinFreshness);
    final sleepAge = sleep.isEmpty
        ? const Duration(days: 99)
        : nowUtc.difference(sleep.last.at);
    final sleepConfidence = _freshness(sleepAge, kSleepFreshness);

    return Signals(
      sleepDebtNorm: sleepDebtNorm,
      focusDebt: focusDebt.toDouble(),
      recoveryQuality: recovery,
      compensationEffort: compensation,
      irritabilityTrend: irritability,
      socialWithdrawal: withdrawal,
      minutesInLowStimulus: lowStimulusMinutes,
      sensationReliefLast24h: relief,
      incidentPressure: incidentPressure,
      circadianBonus: _circadian(nowLocal, todaysCheckins),
      confidence: {
        'capacity': (checkinConfidence + sleepConfidence) / 2,
        'focus_debt': 1.0,
        'sensation_need': checkinConfidence,
        'load_index': checkinConfidence,
        'regulation': checkinConfidence,
        'sleep_debt': sleepConfidence,
      },
    );
  }

  /// Schlafschuld je Nacht statt je Aufzeichnung.
  ///
  /// **Vorher** wurde hier `est_debt_min` ueber alle Schlaffenster der Woche
  /// summiert. Health Connect liefert aber je Schlafphase einen eigenen
  /// Datensatz, und der Schreiber rechnete jeden davon gegen sieben Stunden
  /// Soll: Ein halbstuendiges Nickerchen war damit eine eigene „Nacht" mit
  /// 390 Minuten Schuld. Sieben volle Naechte plus ein Mittagsschlaf ergaben
  /// Schlafschuld 46, die Kapazitaet fiel um knapp 14 Punkte und
  /// `load_index` stieg um denselben Betrag — wegen eines Mittagsschlafs.
  /// Schrieben zwei Apps dieselbe Nacht (Uhr und Herstellerapp haben
  /// verschiedene Quell-IDs), zaehlte sie doppelt.
  ///
  /// **Jetzt** wird erst gemessen, dann gerechnet: ueberlappende Fenster
  /// werden vereinigt (dieselbe Nacht aus zwei Quellen zaehlt einmal), alles
  /// was zum selben lokalen Aufwachtag gehoert wird addiert (das Nickerchen
  /// verkuerzt die Schuld, statt eine zu erfinden), und erst der Rest gegen
  /// das Soll ist Schuld. Schlafschuld ist mit Gewicht 0,30 der groesste
  /// Einzelfaktor der Kapazitaet — ein Messfehler wiegt hier schwerer als
  /// anderswo. [D7]
  static double _sleepDebtNorm(List<Event> sleep) {
    final windows = <({DateTime from, DateTime to})>[];
    // Fenster ohne verwertbare Zeiten: der mitgelieferte Schaetzwert bleibt
    // die einzige Quelle, sonst fiele die Nacht stumm unter den Tisch.
    final reported = <DateTime, double>{};

    for (final e in sleep) {
      final from = _parseUtc(e.payload['bed_at']);
      final to = _parseUtc(e.payload['wake_at']);
      if (from != null && to != null && to.isAfter(from)) {
        windows.add((from: from, to: to));
        continue;
      }
      final debt = (e.payload['est_debt_min'] as num?)?.toDouble();
      if (debt == null) continue;
      final day = _localDay(e.at);
      if (debt > (reported[day] ?? 0)) reported[day] = debt;
    }

    windows.sort((a, b) => a.from.compareTo(b.from));
    final sleptPerDay = <DateTime, double>{};
    void account(({DateTime from, DateTime to}) window) {
      final day = _localDay(window.to);
      sleptPerDay[day] = (sleptPerDay[day] ?? 0) +
          window.to.difference(window.from).inMinutes;
    }

    ({DateTime from, DateTime to})? open;
    for (final window in windows) {
      if (open == null) {
        open = window;
        continue;
      }
      if (!window.from.isAfter(open.to)) {
        // Ueberlappt oder schliesst nahtlos an: dieselbe Schlafphase, egal
        // aus wie vielen Quellen sie gemeldet wurde.
        open = (
          from: open.from,
          to: window.to.isAfter(open.to) ? window.to : open.to,
        );
      } else {
        account(open);
        open = window;
      }
    }
    if (open != null) account(open);

    var total = 0.0;
    for (final day in {...sleptPerDay.keys, ...reported.keys}) {
      final slept = sleptPerDay[day];
      total += slept == null
          ? reported[day]!
          : (kSleepTargetMinutes - slept).clamp(0.0, 600.0);
    }
    // Sieben Naechte im Mittel; zwei Stunden mittlere Schuld sind der
    // Anschlag. Nicht erfasste Naechte zaehlen als schuldfrei — geraten
    // wird hier nichts, dafuer gibt es die Konfidenz.
    return (total / 7 / 120 * 100).clamp(0, 100).toDouble();
  }

  /// Der lokale Tag, zu dem ein Zeitpunkt gehoert.
  ///
  /// Eine Nacht gehoert zu dem Tag, an dem sie endet — und ein Nickerchen am
  /// Nachmittag zu demselben. Nur so landen beide im selben Topf.
  static DateTime _localDay(DateTime utc) {
    final local = utc.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static DateTime? _parseUtc(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;

  /// Aufwachzeit aus dem letzten Schlaffenster, sonst 07:00 als Annahme.
  static DateTime _wakeTime(List<Event> sleep, DateTime nowLocal) {
    final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    if (sleep.isNotEmpty) {
      final wake = sleep.last.payload['wake_at'];
      if (wake is String) {
        final parsed = DateTime.tryParse(wake)?.toLocal();
        if (parsed != null && !parsed.isBefore(today)) return parsed;
      }
    }
    final assumed = today.add(const Duration(hours: 7));
    return assumed.isAfter(nowLocal) ? today : assumed;
  }

  /// 1..5 auf 0..100.
  static double _scale(double v) => ((v - 1) / 4 * 100).clamp(0, 100);

  /// Reizbarkeit aus der Varianz der Stimmungswerte — nicht aus dem
  /// Mittelwert. Schwankung ist das Signal, nicht das Niveau.
  static double _irritability(List<Event> checkins) {
    final moods = checkins
        .map((e) => (e.payload['mood'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    if (moods.length < 3) return 0;
    final mean = moods.reduce((a, b) => a + b) / moods.length;
    final variance =
        moods.map((m) => (m - mean) * (m - mean)).reduce((a, b) => a + b) /
            moods.length;
    return (variance / 2 * 100).clamp(0, 100);
  }

  /// Vorlaeufiges circadianes Profil. Wird nach der Baseline-Phase durch das
  /// gemessene persoenliche Leistungsfenster ersetzt.
  static double _circadian(DateTime local, List<Event> todaysCheckins) {
    if (todaysCheckins.isEmpty) {
      final h = local.hour;
      if (h >= 9 && h < 12) return 40;
      if (h >= 16 && h < 20) return 20;
      if (h >= 13 && h < 15) return -20;
      if (h >= 22 || h < 6) return -40;
      return 0;
    }
    final energy = todaysCheckins
        .map((e) => (e.payload['energy'] as num?)?.toDouble())
        .whereType<double>();
    if (energy.isEmpty) return 0;
    final avg = energy.reduce((a, b) => a + b) / energy.length;
    return ((avg - 3) * 30).clamp(-50, 50);
  }

  static double _freshness(Duration age, Duration window) {
    if (age <= window) return 1.0;
    final overdue = age.inMinutes - window.inMinutes;
    return (1.0 - overdue / (window.inMinutes * 3)).clamp(0.0, 1.0);
  }
}
