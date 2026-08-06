/// Wirkfenster — M13. **Standardmäßig aus.**
///
/// ⚠️ **Dieses Modul protokolliert. Es empfiehlt nichts.**
///
/// AXIOM ist kein Medizinprodukt. Es nennt keine Dosis, schlägt keine
/// Einnahmezeit vor, bewertet keine Wirkung und rät zu keiner Änderung.
/// Was es tut: Es hält fest, wann etwas eingenommen wurde, und legt Aufgaben
/// mit hoher Aktivierungsenergie in den Zeitraum, in dem die Kapazität
/// erfahrungsgemäß am höchsten ist.
///
/// Der Unterschied ist wesentlich: *„Die schwere Aufgabe passt in dieses
/// Zeitfenster"* ist Planung. *„Nimm jetzt etwas"* wäre eine Behandlung —
/// und die gehört in die Hand von Ärztinnen und Ärzten, nicht in eine App
/// (R10).
///
/// Das Modul ist deshalb opt-in, und die Wirkfenster trägt der Nutzer selbst
/// ein — sie kommen aus seiner Beobachtung, nicht aus einer Tabelle.
library;

import 'package:meta/meta.dart';

/// Ein selbst eingetragener Eintrag. Kein Wirkstoffkatalog, keine
/// Plausibilitätsprüfung — nur das, was der Nutzer notiert.
@immutable
final class MedEntry {
  final String id;

  /// Bezeichnung, wie der Nutzer sie führt.
  final String label;

  /// Freitext. AXIOM interpretiert das nicht.
  final String? dose;

  final DateTime takenAt;

  /// Vom Nutzer beobachtetes Wirkfenster, relativ zur Einnahme.
  ///
  /// Kommt aus seiner eigenen Erfahrung. AXIOM schlägt hier nichts vor —
  /// Wirkdauern hängen von Präparat, Person und Tag ab, und eine geratene
  /// Zahl wäre hier gefährlicher als keine.
  final Duration onset;
  final Duration duration;

  const MedEntry({
    required this.id,
    required this.label,
    required this.takenAt,
    this.dose,
    this.onset = Duration.zero,
    this.duration = Duration.zero,
  });

  /// Beginn und Ende des eingetragenen Fensters.
  DateTime get windowStart => takenAt.add(onset);
  DateTime get windowEnd => takenAt.add(onset + duration);

  bool get hasWindow => duration > Duration.zero;

  bool isInWindow(DateTime at) =>
      hasWindow && !at.isBefore(windowStart) && at.isBefore(windowEnd);

  /// Wie viel vom Fenster noch übrig ist.
  Duration remaining(DateTime at) {
    if (!isInWindow(at)) return Duration.zero;
    return windowEnd.difference(at);
  }
}

@immutable
final class MedWindowState {
  /// Ist das Modul überhaupt eingeschaltet?
  final bool enabled;

  /// Der Eintrag, dessen Fenster gerade läuft.
  final MedEntry? active;

  const MedWindowState({this.enabled = false, this.active});

  /// Läuft in DIESEM Zyklus ein Fenster?
  ///
  /// **Warum das keine Zeit prüft — und warum es trotzdem stimmt.** Der
  /// Zustand ist eine Momentaufnahme: [active] wird von
  /// [MedWindow.activeAt] bereits gegen den Auswertungszeitpunkt gefiltert.
  /// Hier noch einmal gegen eine Uhr zu prüfen hieße, gegen eine *andere*
  /// Uhr zu prüfen als die, mit der die Aufnahme entstanden ist — genau der
  /// Fehler, den `nowProvider` an anderer Stelle verhindert.
  ///
  /// Der Getter hieß `isInWindow` und war damit von [MedEntry.isInWindow]
  /// nicht zu unterscheiden, das eine Zeit *nimmt* und eine prüft. Ein Name,
  /// der eine Prüfung verspricht, die nicht stattfindet, ist die Sorte
  /// Zusage, an der dieses Projekt schon mehrfach hängengeblieben ist —
  /// deshalb sagt er jetzt, was er tut.
  bool get hasActiveWindow => enabled && active != null;
}

final class MedWindow {
  const MedWindow();

  /// Findet den Eintrag, dessen Fenster [at] enthält.
  MedEntry? activeAt(List<MedEntry> entries, DateTime at) {
    for (final entry in entries) {
      if (entry.isInWindow(at)) return entry;
    }
    return null;
  }

  /// Anhebung der Kapazität während des Fensters.
  ///
  /// Bewusst klein und pauschal. Eine große oder differenzierte Zahl würde
  /// eine Genauigkeit vortäuschen, die es nicht gibt — und sie würde die
  /// Kapazitätsformel von einer Einnahme abhängig machen, statt von
  /// gemessenen Signalen.
  ///
  /// Der eigentliche Nutzen liegt nicht in dieser Zahl, sondern darin, dass
  /// die Planung weiß, wann das Fenster ist.
  double capacityBonusAt({
    required MedWindowState state,
    required DateTime at,
  }) {
    if (!state.enabled || state.active == null) return 0;
    return state.active!.isInWindow(at) ? kMedWindowBonus : 0;
  }

  /// Beschreibt den Stand — sachlich, ohne Wertung und ohne Rat.
  String describe(MedWindowState state, DateTime at) {
    if (!state.enabled) return 'Modul ist aus.';
    final active = state.active;
    if (active == null) return 'Kein Fenster eingetragen.';
    if (!active.isInWindow(at)) return 'Außerhalb des Fensters.';

    final left = active.remaining(at);
    return left.inMinutes < 60
        ? 'Fenster läuft noch ${left.inMinutes} min.'
        : 'Fenster läuft noch ${(left.inMinutes / 60).toStringAsFixed(1)} h.';
  }
}

/// Anhebung der Kapazität im eingetragenen Fenster.
const double kMedWindowBonus = 8;

/// Text, der überall dort steht, wo das Modul sichtbar wird.
///
/// Nicht verhandelbar: Ohne diese Abgrenzung liest sich ein Protokoll
/// schnell wie eine Empfehlung (R10).
const String kMedDisclaimer =
    'AXIOM protokolliert nur. Es nennt keine Dosis, schlägt keine '
    'Einnahmezeit vor und bewertet keine Wirkung. Alles, was die Behandlung '
    'betrifft, gehört zu deiner Ärztin oder deinem Arzt.';
