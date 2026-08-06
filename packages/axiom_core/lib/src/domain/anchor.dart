/// Zeitanker mit Rückwärtsverkettung — M3.
///
/// Das eigentliche Problem ist nicht Unpünktlichkeit. Bei diesem Profil ist
/// Pünktlichkeit erfolgreich kompensiert — und genau das ist teuer: massive
/// Sicherheitspuffer, ständiges Nachrechnen im Kopf, Wartezeitverluste und
/// eine Dauerspannung vor jedem Termin. Ein Termin kostet nicht 60 Minuten,
/// sondern 150 plus Regulationsreserve. [D4]
///
/// AXIOM übernimmt das Rechnen und das Wachehalten. Aus einem Termin wird
/// eine Kette rückwärts:
///
///   ankommen 14:00
///     ← losfahren 13:22   (Fahrzeit + Puffer)
///     ← fertigmachen 13:07
///     ← Kontext verlassen 12:57   (der Schritt, den alle vergessen)
///
/// Der letzte Punkt ist der wichtigste: Der Ausstieg aus dem Vorherigen
/// kostet Zeit, und genau die fehlt im Kopfmodell. Wer im Fokus sitzt,
/// ist nicht in dem Moment startbereit, in dem er aufsteht.
library;

import 'package:meta/meta.dart';

enum AnchorStepKind {
  /// Laufendes verlassen, Kontext sichern. Wird typischerweise vergessen.
  leaveContext,

  /// Fertigmachen, Sachen zusammensuchen.
  prepare,

  /// Losgehen oder losfahren.
  depart,

  /// Ankunft — der eigentliche Termin.
  arrive,
}

@immutable
final class AnchorStep {
  final AnchorStepKind kind;
  final DateTime at;
  final String label;

  const AnchorStep({
    required this.kind,
    required this.at,
    required this.label,
  });

  @override
  String toString() => '$label @ ${at.hour}:'
      '${at.minute.toString().padLeft(2, "0")}';
}

/// Ein Termin mit allem, was davor passieren muss.
@immutable
final class Anchor {
  final String id;
  final String title;

  /// Wann man dort sein muss. Lokale Zeit.
  final DateTime arriveBy;

  /// Reine Wegzeit.
  final Duration travel;

  /// Fertigmachen: anziehen, Sachen suchen, Tasche packen.
  final Duration prepare;

  /// Sicherheitspuffer. Wird nach der Baseline aus realen Daten kalibriert
  /// (Metrik K3) — bis dahin die Voreinstellung unten.
  final Duration buffer;

  /// Kosten des Kontextwechsels. Aus dem Fokus auszusteigen dauert. [D11]
  final Duration contextSwitch;

  final String? location;

  const Anchor({
    required this.id,
    required this.title,
    required this.arriveBy,
    this.travel = Duration.zero,
    this.prepare = kDefaultPrepare,
    this.buffer = kDefaultBuffer,
    this.contextSwitch = kDefaultContextSwitch,
    this.location,
  });

  /// Die Kette, rückwärts gerechnet, vorwärts sortiert.
  ///
  /// Reine Funktion über den Feldern — deshalb ohne Uhr testbar.
  List<AnchorStep> get chain {
    final depart = arriveBy.subtract(travel + buffer);
    final ready = depart.subtract(prepare);
    final leave = ready.subtract(contextSwitch);

    return [
      if (contextSwitch > Duration.zero)
        AnchorStep(
          kind: AnchorStepKind.leaveContext,
          at: leave,
          label: 'Laufendes abschließen',
        ),
      if (prepare > Duration.zero)
        AnchorStep(
          kind: AnchorStepKind.prepare,
          at: ready,
          label: 'Fertigmachen',
        ),
      if (travel > Duration.zero || buffer > Duration.zero)
        AnchorStep(
          kind: AnchorStepKind.depart,
          at: depart,
          label: location == null ? 'Losgehen' : 'Los nach $location',
        ),
      AnchorStep(
        kind: AnchorStepKind.arrive,
        at: arriveBy,
        label: title,
      ),
    ];
  }

  /// Der erste Schritt, der noch bevorsteht. Null, wenn alles vorbei ist.
  AnchorStep? nextStep(DateTime now) {
    for (final step in chain) {
      if (step.at.isAfter(now)) return step;
    }
    return null;
  }

  /// Gesamte Vorlaufzeit — das, was im Kalender nicht steht.
  ///
  /// Diese Zahl sichtbar zu machen ist der halbe Nutzen des Moduls: Sie
  /// erklärt, warum ein einstündiger Termin einen Nachmittag kostet.
  Duration get leadTime => travel + buffer + prepare + contextSwitch;

  /// Wann alles beginnt.
  DateTime get startsAt => arriveBy.subtract(leadTime);

  /// Läuft die Vorbereitung gerade?
  bool isActive(DateTime now) =>
      !now.isBefore(startsAt) && now.isBefore(arriveBy);

  /// Der erste noch offene Schritt, dessen Zeit mehr als
  /// [kBehindTolerance] zurückliegt. Null, wenn keiner überfällig ist.
  ///
  /// **[lastDone] ist der entscheidende Teil.** Aus Kette und Uhr allein
  /// lässt sich „im Zeitplan" und „hinterher" nicht unterscheiden: Dass die
  /// Zeit eines Schrittes vorbei ist, heißt nicht, dass er nicht getan
  /// wurde. Wer um 13:00 den Kontext verlässt und um 13:20 beim
  /// Fertigmachen ist, liegt exakt im Plan — ohne Erledigt-Vermerk meldete
  /// diese Methode trotzdem Rückstand, und zwar durchgehend von fünf
  /// Minuten nach dem ersten Kettenschritt bis zum Termin. Ein Wert, der in
  /// der halben Kette dasselbe sagt, trägt keine Information.
  ///
  /// [lastDone] nennt den letzten Schritt, den der Nutzer quittiert hat.
  /// Gezählt wird nur, was danach kommt. Ohne Angabe gilt nichts als
  /// erledigt — dann ist die Antwort so gut wie die Datenlage, und die
  /// Benennung sagt hier, worauf sie beruht.
  ///
  /// Bewusst ohne Alarmton: Der Zustand wird gemeldet, nicht bewertet. Ein
  /// verpasster Schritt ist eine Information, kein Vorwurf (R7).
  AnchorStep? overdueStep(DateTime now, {AnchorStepKind? lastDone}) {
    final steps = chain;
    // Nach dem Termin gibt es keinen Rückstand mehr — die Meldung wäre ein
    // Vorwurf ohne Nutzen (R7).
    if (!steps.last.at.isAfter(now)) return null;

    final limit = now.subtract(kBehindTolerance);
    for (final step in steps) {
      // Die Reihenfolge der Aufzählung ist die Reihenfolge der Kette; über
      // den Index statt über die Listenposition, weil Schritte ohne Dauer
      // gar nicht in der Kette stehen.
      if (lastDone != null && step.kind.index <= lastDone.index) continue;
      if (step.at.isBefore(limit)) return step;
    }
    return null;
  }

  /// Ist ein Schritt überfällig? Siehe [overdueStep] — insbesondere dazu,
  /// was [lastDone] beantwortet und was die Frage ohne ihn wert ist.
  bool isBehind(DateTime now, {AnchorStepKind? lastDone}) =>
      overdueStep(now, lastDone: lastDone) != null;

  Anchor copyWith({
    String? title,
    DateTime? arriveBy,
    Duration? travel,
    Duration? prepare,
    Duration? buffer,
    Duration? contextSwitch,
    String? location,
  }) =>
      Anchor(
        id: id,
        title: title ?? this.title,
        arriveBy: arriveBy ?? this.arriveBy,
        travel: travel ?? this.travel,
        prepare: prepare ?? this.prepare,
        buffer: buffer ?? this.buffer,
        contextSwitch: contextSwitch ?? this.contextSwitch,
        location: location ?? this.location,
      );

  @override
  String toString() => 'Anchor($title @ $arriveBy, Vorlauf ${leadTime.inMinutes}min)';
}

/// Ab wann ein offener Schritt als überfällig gilt.
///
/// Stand als `Duration(minutes: 5)` mitten in `isBehind` und war damit die
/// einzige Zahl der Kette, die man nicht nachschlagen konnte.
const Duration kBehindTolerance = Duration(minutes: 5);

/// Voreinstellungen. Nach der Baseline aus realen Terminkosten ersetzen.
const Duration kDefaultPrepare = Duration(minutes: 15);
const Duration kDefaultBuffer = Duration(minutes: 10);
const Duration kDefaultContextSwitch = Duration(minutes: 10);

/// Wie viele Minuten vor einem Schritt erinnert wird.
///
/// Gestuft: Der Kontextwechsel bekommt Vorlauf, weil das Aussteigen aus dem
/// Fokus Zeit braucht. Die Ankunft selbst braucht keine Erinnerung mehr —
/// da sitzt man schon im Auto.
Duration reminderLeadFor(AnchorStepKind kind) => switch (kind) {
      AnchorStepKind.leaveContext => const Duration(minutes: 5),
      AnchorStepKind.prepare => const Duration(minutes: 2),
      AnchorStepKind.depart => const Duration(minutes: 2),
      AnchorStepKind.arrive => Duration.zero,
    };
