/// Load Monitor — M9.
///
/// Das wichtigste Modul für dieses Profil in diesem Alter. Hochkompensiert
/// heißt: Die Leistung stimmt, der Preis ist unsichtbar. Nach Jahrzehnten
/// läuft das System dauerhaft am Limit, ohne dass ein einzelner Tag
/// auffällig wäre — und ein Systemizer merkt den Absturz zuletzt, weil nach
/// außen bis kurz vor dem Bruch alles fehlerfrei läuft [D1].
///
/// Deshalb hat der Load Monitor **reale Konsequenzen im System**, nicht nur
/// eine Farbe. L3 ist bewusst unbequem: der externe Notaus, den der Nutzer
/// im ruhigen Zustand selbst autorisiert hat.
///
/// Sprachregel: **L3 ist ein Erfolg des Systems, kein Versagen des
/// Nutzers.** Wer im Erhaltungsmodus landet, hat nichts falsch gemacht —
/// die Messung hat funktioniert (R7).
library;

import 'package:meta/meta.dart';

import '../domain/state_vector.dart';

/// Was eine Load-Stufe im System verändert.
@immutable
final class LoadRegime {
  final LoadLevel level;

  /// Kurzform für die Oberfläche.
  final String headline;

  /// Was gerade gilt.
  final String description;

  /// Optionales ausblenden — im Erhaltungsmodus bleibt nur Pflicht.
  final bool hideOptional;

  /// Neue Verpflichtungen brauchen eine bewusste Bestätigung.
  final bool confirmNewCommitments;

  /// Obergrenze für Fokusblöcke. Null = keine.
  final Duration? maxFocusBlock;

  /// Obergrenze für Aufgaben-Aktivierungsenergie, die noch vorgeschlagen
  /// wird. Null = keine.
  final int? maxSuggestedEnergy;

  /// Wie lange die Stufe mindestens gilt, bevor sie zurückfallen darf.
  ///
  /// Ohne Haltezeit würde der Modus bei jedem guten Messwert flackern —
  /// und ein flackernder Notaus ist keiner.
  final Duration minimumHold;

  const LoadRegime({
    required this.level,
    required this.headline,
    required this.description,
    this.hideOptional = false,
    this.confirmNewCommitments = false,
    this.maxFocusBlock,
    this.maxSuggestedEnergy,
    this.minimumHold = Duration.zero,
  });
}

const LoadRegime _l0 = LoadRegime(
  level: LoadLevel.l0,
  headline: 'Normalbetrieb',
  description: 'Die Kompensationslast liegt im gewohnten Bereich.',
);

const LoadRegime _l1 = LoadRegime(
  level: LoadLevel.l1,
  headline: 'Last erhöht',
  description: 'Die Last steigt seit einigen Tagen. Nach außen noch '
      'unauffällig — genau deshalb steht es hier.',
  maxFocusBlock: Duration(minutes: 75),
  minimumHold: Duration(hours: 12),
);

const LoadRegime _l2 = LoadRegime(
  level: LoadLevel.l2,
  headline: 'Last kritisch',
  description: 'Jetzt nichts Neues zusätzlich aufnehmen. Bestehendes eher '
      'abgeben als erweitern.',
  confirmNewCommitments: true,
  maxFocusBlock: Duration(minutes: 50),
  maxSuggestedEnergy: 6,
  minimumHold: Duration(hours: 24),
);

const LoadRegime _l3 = LoadRegime(
  level: LoadLevel.l3,
  headline: 'Erhaltungsmodus',
  description: 'Für die nächsten Tage nur Pflicht und Erholung. Dass dieser '
      'Modus greift, ist der Zweck des Systems — nicht dein Versagen.',
  hideOptional: true,
  confirmNewCommitments: true,
  maxFocusBlock: Duration(minutes: 30),
  maxSuggestedEnergy: 4,
  minimumHold: Duration(hours: 72),
);

/// Ab wie vielen Tagen in L3 auf professionelle Abklärung hingewiesen wird.
///
/// AXIOM diagnostiziert nichts und darf das auch nicht. Aber anhaltend hohe
/// Last kann klinisch relevant sein, und darüber zu schweigen wäre der
/// falsche Umgang mit einer Messung, die man selbst erhebt (R10).
const int kL3DaysBeforeReferral = 14;

final class LoadMonitor {
  const LoadMonitor();

  LoadRegime regimeFor(LoadLevel level) => switch (level) {
        LoadLevel.l0 => _l0,
        LoadLevel.l1 => _l1,
        LoadLevel.l2 => _l2,
        LoadLevel.l3 => _l3,
      };

  /// Bestimmt die geltende Stufe unter Berücksichtigung der Haltezeit.
  ///
  /// Hoch geht es sofort, runter erst nach der Mindesthaltezeit. Ein
  /// einzelner guter Tag beendet keinen Erhaltungsmodus — sonst wäre er
  /// nach der ersten durchgeschlafenen Nacht wieder weg, und genau dann
  /// ist die Erschöpfung noch da.
  LoadLevel effectiveLevel({
    required LoadLevel measured,
    required LoadLevel? current,
    required DateTime now,
    required DateTime? since,
  }) {
    if (current == null || since == null) return measured;
    if (measured.index >= current.index) return measured;

    final held = now.difference(since);
    final required = regimeFor(current).minimumHold;
    return held >= required ? measured : current;
  }

  /// Soll auf professionelle Abklärung hingewiesen werden?
  bool suggestsReferral({
    required LoadLevel level,
    required DateTime? since,
    required DateTime now,
  }) =>
      level == LoadLevel.l3 &&
      since != null &&
      now.difference(since).inDays >= kL3DaysBeforeReferral;

  /// Text für den Übergang in eine höhere Stufe.
  ///
  /// Beschreibt den Zustand und die Konsequenz — ohne Ausrufezeichen, ohne
  /// Dringlichkeitsrhetorik. Wer ohnehin am Limit läuft, braucht keinen
  /// weiteren Reiz, sondern eine klare Ansage.
  String escalationText(LoadRegime from, LoadRegime to) {
    if (to.level == LoadLevel.l3) {
      return 'Erhaltungsmodus für die nächsten 72 Stunden. Optionales wird '
          'ausgeblendet, Fokusblöcke sind kürzer. Das ist unbequem und soll '
          'es sein.';
    }
    return '${to.headline}. ${to.description}';
  }

  /// Text für den Rückgang.
  String deescalationText(LoadRegime to) =>
      to.level == LoadLevel.l0
          ? 'Zurück im Normalbereich. Volle Funktion.'
          : '${to.headline}. ${to.description}';
}
