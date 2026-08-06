/// Fokus-Sitzung und Governor — M4.
///
/// Hyperfokus ist kein Aufmerksamkeitsdefizit, sondern ein Allokationsdefizit:
/// Aufmerksamkeit ist reichlich da, nur nicht steuerbar. Zwei Fehlermodi
/// [D6]:
///
///   1. **Falsches Ziel** — sechs Stunden auf ein irrelevantes Detail,
///      während die Frist verstreicht.
///   2. **Kein Ausstieg** — auch beim richtigen Ziel wird das Ende verpasst:
///      Essen, Trinken, Termine, Schlaf.
///
/// Der Governor ist deshalb bewusst asymmetrisch: Er **schützt** den Fokus,
/// wenn er auf dem gesetzten Anker liegt, und unterbricht nur, wenn es einen
/// belegbaren Grund gibt. Eine falsch getimte Unterbrechung zerstört den
/// wertvollsten kognitiven Zustand, den dieses Profil hat — sie kostet mehr,
/// als jede verpasste Unterbrechung einbringt (Risiko R5).
library;

import 'package:meta/meta.dart';

import 'anchor.dart';
import 'phrase.dart';
import 'state_vector.dart';

@immutable
final class FocusSession {
  final String id;
  final DateTime startedAt;

  /// Worauf der Fokus liegen *sollte*. Ohne Anker kann der Governor nicht
  /// unterscheiden, ob die Vertiefung die richtige ist.
  final String? anchorTaskId;
  final String? anchorTitle;

  /// Selbst gesetzte Dauer. Kein Timer, der abläuft — ein Bezugspunkt.
  final Duration planned;

  /// Wiedereinstiegsnotiz beim Verlassen [D11].
  final String? breadcrumb;

  const FocusSession({
    required this.id,
    required this.startedAt,
    this.anchorTaskId,
    this.anchorTitle,
    this.planned = const Duration(minutes: 50),
    this.breadcrumb,
  });

  Duration elapsed(DateTime now) => now.difference(startedAt);

  /// Wie weit über die geplante Dauer hinaus.
  Duration overrun(DateTime now) {
    final over = elapsed(now) - planned;
    return over.isNegative ? Duration.zero : over;
  }

  bool get hasAnchor => anchorTaskId != null;

  FocusSession copyWith({String? breadcrumb, Duration? planned}) =>
      FocusSession(
        id: id,
        startedAt: startedAt,
        anchorTaskId: anchorTaskId,
        anchorTitle: anchorTitle,
        planned: planned ?? this.planned,
        breadcrumb: breadcrumb ?? this.breadcrumb,
      );
}

/// Was der Governor mit einer laufenden Sitzung tut.
enum FocusAction {
  /// Nicht stören. Benachrichtigungen unterdrücken, Gerät ruhig halten.
  protect,

  /// Leiser Hinweis. Wegwischbar, kein Ton.
  gentleNudge,

  /// Deutliche Unterbrechung. Verlangt eine Antwort.
  clearInterrupt,

  /// Harte Unterbrechung. Nur bei Terminen und im Erhaltungsmodus.
  hardStop,
}

@immutable
final class FocusVerdict {
  final FocusAction action;

  /// Warum — in Nutzersprache, ohne Vorwurf.
  ///
  /// Quelltext und Werte getrennt, damit die Oberflaeche uebersetzen kann,
  /// ohne die Zahlen aus einem fertigen Satz zurueckrechnen zu muessen.
  final Phrase reason;

  /// Nach welcher Zeit erneut prüfen.
  final Duration recheckAfter;

  const FocusVerdict({
    required this.action,
    required this.reason,
    this.recheckAfter = const Duration(minutes: 10),
  });

  /// Der fertige deutsche Satz.
  String get reasonText => reason.text;
}

/// Schwellen der Eskalation. Bewusst großzügig: Lieber eine Unterbrechung
/// zu spät als eine zu früh (R5).
const Duration kGentleAfterOverrun = Duration(minutes: 25);
const Duration kClearAfterOverrun = Duration(minutes: 60);
const Duration kBodyNeglectAfter = Duration(minutes: 100);

/// Vorlauf, ab dem ein Ankerschritt den Fokus schlägt.
///
/// Ein Termin ist der einzige Grund, der ohne Abwägung gewinnt: Er ist
/// terminiert, unumkehrbar und die Kompensation dafür ist teuer [D4].
const Duration kAnchorBeatsFocus = Duration(minutes: 15);

/// Wie lang ein Fokusfenster geplant wird — als Funktion der Kapazität.
///
/// **Warum keine feste Länge.** Ein starres Intervall — 25 Minuten für
/// jeden, an jedem Tag — misst nichts und passt sich an nichts an. An einem
/// Tag mit Kapazität 30 ist es zu viel und wird abgebrochen; das Abbrechen
/// selbst ist die Erfahrung, die das Anfangen beim nächsten Mal teurer
/// macht [D2]. Ein kurzes Fenster, das hält, ist mehr wert als ein langes,
/// das reißt.
///
/// Die Schwellen sind grob und sollen es sein: Genauigkeit würde hier eine
/// Messgenauigkeit vortäuschen, die es nicht gibt. Sichtbar ist die Formel
/// trotzdem — kein Wert ohne Herleitung (G2).
Duration plannedFocusFor(int capacity) => switch (capacity) {
      < 35 => const Duration(minutes: 15),
      < 70 => const Duration(minutes: 25),
      _ => const Duration(minutes: 45),
    };

final class FocusGovernor {
  const FocusGovernor();

  /// Entscheidet über eine laufende Sitzung.
  ///
  /// Reine Funktion — keine Uhr, kein Zufall, keine Seiteneffekte.
  FocusVerdict assess({
    required FocusSession session,
    required DateTime now,
    required StateVector state,
    ({Anchor anchor, AnchorStep step})? nextAnchorStep,
    Duration? sinceBodyPrompt,
  }) {
    // 1. Termin schlägt alles. Ohne Abwägung.
    if (nextAnchorStep != null) {
      final until = nextAnchorStep.step.at.difference(now);
      if (!until.isNegative && until <= kAnchorBeatsFocus) {
        return FocusVerdict(
          action: FocusAction.hardStop,
          reason: Phrase('{0} in {1} min — {2}.', [
            nextAnchorStep.step.label,
            until.inMinutes,
            nextAnchorStep.anchor.title,
          ]),
          recheckAfter: const Duration(minutes: 2),
        );
      }
    }

    // 2. Erhaltungsmodus. Der Nutzer hat das im ruhigen Zustand autorisiert.
    if (state.loadLevel == LoadLevel.l3) {
      return const FocusVerdict(
        action: FocusAction.hardStop,
        reason: Phrase('Erhaltungsmodus. Für die nächsten Tage nur Pflicht '
            'und Erholung — auch wenn es gerade läuft.'),
        recheckAfter: Duration(minutes: 30),
      );
    }

    final elapsed = session.elapsed(now);
    final overrun = session.overrun(now);

    // Die leisen Zweige 3 und 4 sind **Zusätze**, keine Deckel.
    //
    // Beide treffen dauerhaft zu, sobald sie einmal zutreffen: „ohne
    // gesetztes Ziel" ändert sich während einer Sitzung nicht mehr, und
    // `sinceBodyPrompt` wächst weiter, solange niemand quittiert. Standen
    // sie ohne diese Bedingung vor Zweig 5, verdeckten sie die deutliche
    // Unterbrechung nicht einmal, sondern dauerhaft: Eine Sitzung ohne Ziel
    // bekam nach sechs Stunden denselben leisen Hinweis wie nach
    // sechsundvierzig Minuten. Genau der fehlende Ausstieg ist aber der
    // Fehlermodus, um den es hier geht [D6].
    final overrunDemandsInterrupt = overrun >= kClearAfterOverrun;

    // 3. Ohne gesetztes Ziel ist nicht unterscheidbar, ob die Vertiefung
    //    die richtige ist. Dann wird früher nachgefragt — aber leise.
    if (!session.hasAnchor &&
        elapsed >= const Duration(minutes: 45) &&
        !overrunDemandsInterrupt) {
      return FocusVerdict(
        action: FocusAction.gentleNudge,
        reason: Phrase(
            'Seit {0} min vertieft, ohne gesetztes Ziel. '
            'Ist das noch das, was du wolltest?',
            [elapsed.inMinutes]),
        recheckAfter: const Duration(minutes: 20),
      );
    }

    // 4. Körper seit langem übergangen. Der stärkste Modulator der
    //    Exekutivfunktion sitzt nicht im Kopf [D7].
    if (sinceBodyPrompt != null &&
        sinceBodyPrompt >= kBodyNeglectAfter &&
        !overrunDemandsInterrupt) {
      return FocusVerdict(
        action: FocusAction.gentleNudge,
        reason: Phrase(
            'Seit {0} min nichts getrunken oder bewegt. '
            'Kurz aufstehen kostet zwei Minuten.',
            [sinceBodyPrompt.inMinutes]),
        recheckAfter: const Duration(minutes: 30),
      );
    }

    // 5. Deutliche Überziehung.
    if (overrunDemandsInterrupt) {
      return FocusVerdict(
        action: FocusAction.clearInterrupt,
        reason: Phrase(
            '{0} min über der geplanten Zeit. '
            'Weitermachen ist in Ordnung — bewusst weitermachen auch.',
            [overrun.inMinutes]),
        recheckAfter: const Duration(minutes: 30),
      );
    }
    if (overrun >= kGentleAfterOverrun) {
      return FocusVerdict(
        action: FocusAction.gentleNudge,
        reason: Phrase('{0} min über der geplanten Zeit.',
            [overrun.inMinutes]),
        recheckAfter: const Duration(minutes: 20),
      );
    }

    // 6. Alles in Ordnung: schützen.
    return const FocusVerdict(
      action: FocusAction.protect,
      reason: Phrase('Läuft. Benachrichtigungen sind stumm.'),
    );
  }

  /// Erzeugt die Wiedereinstiegsnotiz aus dem, was der Nutzer beim
  /// Verlassen angibt.
  ///
  /// Der Wiedereinstieg ist teurer als der Ausstieg: Ohne Notiz beginnt
  /// beim nächsten Mal das Laden des Kontexts von vorn [D11].
  static String breadcrumbPrompt(FocusSession session) => session.hasAnchor
      ? 'Wo genau bist du bei „${session.anchorTitle}" stehengeblieben?'
      : 'Woran warst du dran, und was wäre der nächste Handgriff?';
}
