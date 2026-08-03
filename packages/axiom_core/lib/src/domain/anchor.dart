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

  /// Ist ein Schritt überfällig?
  ///
  /// Bewusst ohne Alarmton in der Benennung: Der Zustand wird gemeldet,
  /// nicht bewertet. Ein verpasster Schritt ist eine Information, kein
  /// Vorwurf (R7).
  bool isBehind(DateTime now) {
    final next = nextStep(now);
    if (next == null) return false;
    return chain
        .takeWhile((s) => s != next)
        .any((s) => s.at.isBefore(now.subtract(const Duration(minutes: 5))));
  }

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
