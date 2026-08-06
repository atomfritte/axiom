/// Sammelt die Rohwerte für das Review — M11.
///
/// Die Berechnung selbst liegt in `axiom_core` (ReviewEngine) und ist eine
/// reine Funktion. Hier wird nur gezählt, damit die Kennzahlen ohne Datenbank
/// testbar bleiben.
library;

import 'package:axiom_core/axiom_core.dart';

import 'sqlite_event_store.dart';

final class ReviewAggregator {
  final SqliteEventStore store;
  final Clock clock;

  const ReviewAggregator({required this.store, required this.clock});

  /// Rohwerte für den Zeitraum, plus Vergleich mit dem Vorzeitraum.
  ///
  /// [knownRuleIds] sind die aktuell geladenen Regeln. Ohne sie ließe sich
  /// „hat nie gefeuert" nicht von „gibt es nicht mehr" unterscheiden — die
  /// Entscheidungstabelle kennt nur Regeln, die mindestens einmal etwas
  /// getan haben.
  Future<ReviewInputs> collect(
    ReviewScope scope, {
    List<String> knownRuleIds = const [],
  }) async {
    final now = clock.nowUtc();
    final span = _spanOf(scope);
    final from = now.subtract(span);
    final previousFrom = from.subtract(span);

    final events = await store.query(from: from);
    final previous = await store.query(from: previousFrom, to: from);

    final checkins = _count(events, EventType.checkin);
    final expected = _expectedCheckins(scope);

    final slots = events.where((e) => e.type == EventType.sensationSlot);
    final planned = slots.where((e) => e.payload['planned'] == true).length;

    // Jeder Abfang schreibt zwei Ereignisse: eines beim Start mit
    // `outcome: 'pending'` und eines beim Aufloesen mit dem Ergebnis. Vorher
    // stand hier `intercepts.length` ueber beide — zwei durchgezogene
    // Abfaenge wurden zu „2 von 4 gehalten", drei abgebrochene zu „6 von 6
    // gehalten", ein noch laufender zu „1 von 1 gehalten". Die Quote lag
    // damit unabhaengig vom Verhalten bei mindestens 50 %, und der Review
    // ist der einzige Ort, an dem ueber einen Trigger entschieden wird.
    // Gezaehlt wird deshalb nur die Aufloesung: Ein Abfang ohne Ergebnis
    // gehoert in keine Haltequote. [D6]
    final intercepts = events.where(
      (e) =>
          e.type == EventType.impulseIntercepted &&
          e.payload['outcome'] is String &&
          e.payload['outcome'] != InterceptOutcome.pending.name,
    );

    final stats = await store.ruleStats(since: from);
    final shadow = await _shadowCounts(from);

    return ReviewInputs(
      checkinRate: expected == 0 ? 0 : (checkins / expected).clamp(0.0, 1.0),
      loadIndex: await _averageLoad(events),
      loadIndexBefore: previous.isEmpty ? null : await _averageLoad(previous),
      metaMinutes: (await store.usageToday(clock.nowLocal())).inMinutes,
      savedMinutesEstimate: await _savedEstimate(events, from, now),
      captures: _count(events, EventType.capture),
      tasksCreated: _count(events, EventType.taskCreated),
      tasksCompleted: _count(events, EventType.taskCompleted),
      plannedSlots: planned,
      unplannedSlots: slots.length - planned,
      impulsesIntercepted: intercepts.length,
      impulsesProceeded:
          intercepts.where((e) => e.payload['outcome'] == 'proceeded').length,
      weakRules: stats
          .where((s) => s.responses >= 3 && (s.followRate ?? 1) < 0.4)
          .map((s) => s.ruleId)
          .toList(),
      silentRules: _silentRules(stats, knownRuleIds),
      suppressedRules: stats
          .where((s) {
            // Nur echte Konflikte, nicht die Schattenzeit — siehe
            // [_shadowCounts].
            final conflicts = s.suppressed - (shadow[s.ruleId] ?? 0);
            return conflicts >= 5 && conflicts > s.fires * 2;
          })
          .map((s) => s.ruleId)
          .toList(),
    );
  }

  /// Wie oft eine Regel im Zeitraum nur ihre Schattenzeit protokolliert hat.
  ///
  /// **Warum das eine eigene Abfrage braucht.** `decisions.suppressed` traegt
  /// zwei Bedeutungen: „hat die Konfliktaufloesung verloren" und „laeuft als
  /// SHADOW mit". [SqliteEventStore.ruleStats] summiert beide in eine Spalte.
  /// Weil eine `log_only`-Regel an der Konfliktaufloesung gar nicht teilnimmt,
  /// sind ihre `fires` konstruktiv 0 — die Bedingung unten reduzierte sich
  /// damit auf „fuenfmal unterdrueckt" und meldete jede neue Regel als
  /// staendig verdraengt. Es gab keinen Konflikt: Die Regel lief die sieben
  /// Tage ab, die CLAUDE.md vorschreibt. Geflutet wurde damit genau die
  /// Auswertung, fuer die die Schattenzeit da ist.
  ///
  /// Unterscheidbar sind die beiden Faelle an der Aktion: Eine
  /// SHADOW-Entscheidung traegt `log_only`, Verlierer der Konfliktaufloesung
  /// tragen ihre echte Aktion — `log_only`-Regeln kommen im Resolver nicht
  /// vor. Die Abfrage gehoert langfristig neben `ruleStats`; hier steht sie,
  /// weil sie sonst dieselbe Verbindung ein zweites Mal aufmachen muesste.
  Future<Map<String, int>> _shadowCounts(DateTime since) async {
    final rows = store.rawDatabase.select(
      'SELECT rule_id, COUNT(*) AS shadow FROM decisions '
      'WHERE at >= ? AND suppressed = 1 AND action = ? GROUP BY rule_id',
      [since.toUtc().millisecondsSinceEpoch, ActionType.logOnly.token],
    );
    return {
      for (final row in rows) row['rule_id'] as String: row['shadow'] as int,
    };
  }

  static Duration _spanOf(ReviewScope scope) => switch (scope) {
        ReviewScope.day => const Duration(days: 1),
        ReviewScope.week => const Duration(days: 7),
        ReviewScope.month => const Duration(days: 30),
        ReviewScope.quarter => const Duration(days: 90),
      };

  /// Drei Check-ins pro Tag sind vorgesehen.
  static int _expectedCheckins(ReviewScope scope) =>
      _spanOf(scope).inDays * 3;

  static int _count(List<Event> events, EventType type) =>
      events.where((e) => e.type == type).length;

  /// Mittlerer `load_index` aus den Zustandsschnappschüssen der Entscheidungen.
  ///
  /// Liegen keine vor, wird nicht geschätzt — eine erfundene Zahl im Review
  /// wäre schlimmer als eine fehlende.
  Future<int> _averageLoad(List<Event> events) async {
    final values = events
        .where((e) => e.type == EventType.checkin)
        .map((e) => (e.payload['compensation'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    if (values.isEmpty) return 0;
    final avg = values.reduce((a, b) => a + b) / values.length;
    return ((avg - 1) / 4 * 100).round().clamp(0, 100);
  }

  /// Grobe Schätzung der ersparten Zeit.
  ///
  /// Bewusst grob und konservativ: Für K6 zählt die Größenordnung, nicht die
  /// Nachkommastelle. Eine Scheingenauigkeit würde das Abbruchkriterium
  /// unbrauchbar machen, weil man ihr nicht traut.
  Future<int> _savedEstimate(
    List<Event> events,
    DateTime from,
    DateTime to,
  ) async {
    // Jede erfasste Notiz spart das Wiederfinden eines verlorenen Gedankens,
    // jeder Zeitanker das wiederholte Nachrechnen im Kopf.
    const perCapture = 3;
    const perAnchorStep = 4;
    const perAtomized = 10;

    // Vorher stand hier `_count(events, EventType.decisionEmitted)`. Diesen
    // Ereignistyp schreibt keine Stelle des Projekts — der Summand war
    // konstant null, obwohl der Kommentar daneben die Zeitanker meint.
    // Ankerschritte stehen ueberhaupt nicht im Ereignisstrom, sondern in der
    // Ankertabelle; von dort kommen sie jetzt. Das ist nicht kosmetisch:
    // `savedMinutesEstimate` ist der Nenner von K6, dem Abbruchkriterium des
    // Projekts. Ein systematisch zu kleiner Nenner treibt den Quotienten
    // ueber 1,0 und loest den Rueckbau funktionierender Module aus. [D4]
    final anchors = await store.anchors(from: from, to: to);
    final anchorSteps = anchors.fold<int>(
      0,
      // Der Ankunftsschritt ist der Termin selbst — gerechnet und
      // wachgehalten hat AXIOM nur die Schritte davor.
      (sum, a) =>
          sum +
          a.chain.where((s) => s.kind != AnchorStepKind.arrive).length,
    );

    return _count(events, EventType.capture) * perCapture +
        _count(events, EventType.bodyPrompt) * 1 +
        _count(events, EventType.taskSplit) * perAtomized +
        anchorSteps * perAnchorStep;
  }

  /// Regeln, die im Zeitraum kein einziges Mal aktiv wurden.
  ///
  /// Zwei Fälle: Die Regel steht in der Statistik mit null Feuerungen, oder
  /// sie taucht dort gar nicht auf. Der zweite ist der häufigere und ohne
  /// [knownRuleIds] unsichtbar.
  static List<String> _silentRules(
    List<RuleStats> stats,
    List<String> knownRuleIds,
  ) {
    final active = {
      for (final s in stats)
        if (s.fires > 0 || s.suppressed > 0) s.ruleId,
    };
    final silent = knownRuleIds.where((id) => !active.contains(id)).toList()
      ..sort();
    return silent;
  }
}
