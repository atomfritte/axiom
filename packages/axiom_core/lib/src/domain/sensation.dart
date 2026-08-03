/// Reiz-Haushalt — M5.
///
/// Die zentrale Umdeutung: Reizhunger ist ein **Bedarf**, kein Fehler. Er
/// lässt sich nicht wegtrainieren; ungedeckt sucht er sich den schnellsten
/// Kanal, und der schnellste ist fast immer der teuerste — Impulskauf,
/// Substanz, Geschwindigkeit, Nachtstunden-Konsum [D5].
///
/// AXIOM moralisiert nicht und verbietet nicht (G3). Es plant den Bedarf ein,
/// bevor er sich selbst einen Weg sucht, und macht sichtbar, wann er steigt.
///
/// Zweite Idee: Der Slot ist gleichzeitig **Währung**. Niedrigreiz-Pflichten
/// verdienen Hochreiz-Zeit. Das ist kein Gamification-Zierrat, sondern der
/// einzige Tauschhandel, den dieses Belohnungssystem zuverlässig annimmt.
library;

import 'package:meta/meta.dart';

/// Ein Kanal, über den Reizbedarf gedeckt werden kann.
///
/// Die Liste ist Nutzersache. Voreingestellt sind nur unstrittige,
/// kalkulierbare Kanäle — die riskanten trägt der Nutzer selbst ein, im
/// ruhigen Zustand und mit offenen Augen.
@immutable
final class SensationChannel {
  final String id;
  final String label;

  /// 1..5 — wie stark der Reiz.
  final int intensity;

  /// Typische Dauer, als Vorschlag beim Planen.
  final Duration typical;

  /// Trägt dieser Kanal ein Folgerisiko? Kostet Geld, Schlaf, Gesundheit
  /// oder Beziehung. Wird nicht verboten, nur mitgezählt.
  final bool hasCost;

  const SensationChannel({
    required this.id,
    required this.label,
    required this.intensity,
    this.typical = const Duration(minutes: 30),
    this.hasCost = false,
  });
}

/// Voreinstellung. Bewusst körperlich und sofort verfügbar — ein Kanal, der
/// Planung braucht, deckt keinen akuten Bedarf.
const List<SensationChannel> kDefaultChannels = [
  SensationChannel(
    id: 'sport',
    label: 'Sport, hart',
    intensity: 5,
    typical: Duration(minutes: 45),
  ),
  SensationChannel(
    id: 'cold',
    label: 'Kalt duschen',
    intensity: 4,
    typical: Duration(minutes: 5),
  ),
  SensationChannel(
    id: 'music',
    label: 'Musik, laut',
    intensity: 3,
    typical: Duration(minutes: 20),
  ),
  SensationChannel(
    id: 'outdoor',
    label: 'Raus, schnell',
    intensity: 3,
    typical: Duration(minutes: 30),
  ),
  SensationChannel(
    id: 'contest',
    label: 'Wettkampf',
    intensity: 5,
    typical: Duration(minutes: 60),
  ),
];

/// Ein geplanter oder erfolgter Reiz-Slot.
@immutable
final class SensationSlot {
  final String id;
  final String channelId;
  final String channelLabel;
  final int intensity;
  final DateTime at;
  final Duration duration;

  /// Geplant heißt: vorher eingetragen, nicht hinterher protokolliert.
  /// Die Unterscheidung ist der ganze Punkt der Kennzahl (K4).
  final bool planned;

  const SensationSlot({
    required this.id,
    required this.channelId,
    required this.channelLabel,
    required this.intensity,
    required this.at,
    required this.duration,
    required this.planned,
  });

  /// Wie stark dieser Slot den Bedarf senkt.
  double get relief => intensity * duration.inMinutes / 30.0;
}

/// Der Tauschhandel: Niedrigreiz-Zeit verdient Hochreiz-Zeit.
@immutable
final class SensationBudget {
  /// Verdiente Minuten aus konzentrierter Niedrigreiz-Arbeit.
  final int earnedMinutes;

  /// Bereits eingelöst.
  final int spentMinutes;

  const SensationBudget({this.earnedMinutes = 0, this.spentMinutes = 0});

  int get availableMinutes => (earnedMinutes - spentMinutes).clamp(0, 999);

  bool get hasCredit => availableMinutes > 0;
}

/// Wie viele Minuten Hochreiz eine Minute Niedrigreiz-Arbeit verdient.
///
/// 1:3 — 90 Minuten Pflicht schalten 30 Minuten frei. Der Kurs ist bewusst
/// großzügig: Ein Budget, das man nie erreicht, motiviert niemanden, und ein
/// unerreichbares Budget ist schlimmer als gar keins.
const double kEarnRate = 1 / 3;

final class SensationLedger {
  const SensationLedger();

  /// Berechnet den Stand aus Fokusminuten und eingelösten Slots.
  SensationBudget compute({
    required int focusMinutesToday,
    required List<SensationSlot> slotsToday,
  }) =>
      SensationBudget(
        earnedMinutes: (focusMinutesToday * kEarnRate).round(),
        spentMinutes: slotsToday
            .where((s) => s.planned)
            .fold(0, (sum, s) => sum + s.duration.inMinutes),
      );

  /// Vorschlag bei hohem Bedarf.
  ///
  /// Kein Zufall: Der Kanal mit der passenden Intensität, der ins verfügbare
  /// Zeitfenster passt. Deterministisch, damit die Empfehlung erklärbar
  /// bleibt (G2).
  SensationChannel? suggest({
    required int sensationNeed,
    required List<SensationChannel> channels,
    required Duration available,
    bool allowCostly = false,
  }) {
    if (channels.isEmpty) return null;

    // Hoher Bedarf verlangt hohe Intensität — ein leiser Kanal deckt einen
    // lauten Bedarf nicht, und der Rest sucht sich dann doch seinen Weg.
    final wanted = switch (sensationNeed) {
      >= 85 => 5,
      >= 70 => 4,
      >= 50 => 3,
      _ => 2,
    };

    final eligible = channels
        .where((c) => allowCostly || !c.hasCost)
        .where((c) => c.typical <= available)
        .toList();
    if (eligible.isEmpty) return null;

    eligible.sort((a, b) {
      final byFit = (a.intensity - wanted).abs()
          .compareTo((b.intensity - wanted).abs());
      if (byFit != 0) return byFit;
      // Gleich passend? Der kürzere gewinnt — er ist eher machbar.
      return a.typical.compareTo(b.typical);
    });
    return eligible.first;
  }
}
