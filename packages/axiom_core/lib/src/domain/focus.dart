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
  final String reason;

  /// Nach welcher Zeit erneut prüfen.
  final Duration recheckAfter;

  const FocusVerdict({
    required this.action,
    required this.reason,
    this.recheckAfter = const Duration(minutes: 10),
  });
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
          reason: '${nextAnchorStep.step.label} in ${until.inMinutes} min — '
              '${nextAnchorStep.anchor.title}.',
          recheckAfter: const Duration(minutes: 2),
        );
      }
    }

    // 2. Erhaltungsmodus. Der Nutzer hat das im ruhigen Zustand autorisiert.
    if (state.loadLevel == LoadLevel.l3) {
      return const FocusVerdict(
        action: FocusAction.hardStop,
        reason: 'Erhaltungsmodus. Für die nächsten Tage nur Pflicht und '
            'Erholung — auch wenn es gerade läuft.',
        recheckAfter: Duration(minutes: 30),
      );
    }

    final elapsed = session.elapsed(now);
    final overrun = session.overrun(now);

    // 3. Ohne gesetztes Ziel ist nicht unterscheidbar, ob die Vertiefung
    //    die richtige ist. Dann wird früher nachgefragt — aber leise.
    if (!session.hasAnchor && elapsed >= const Duration(minutes: 45)) {
      return FocusVerdict(
        action: FocusAction.gentleNudge,
        reason: 'Seit ${elapsed.inMinutes} min vertieft, ohne gesetztes Ziel. '
            'Ist das noch das, was du wolltest?',
        recheckAfter: const Duration(minutes: 20),
      );
    }

    // 4. Körper seit langem übergangen. Der stärkste Modulator der
    //    Exekutivfunktion sitzt nicht im Kopf [D7].
    if (sinceBodyPrompt != null && sinceBodyPrompt >= kBodyNeglectAfter) {
      return FocusVerdict(
        action: FocusAction.gentleNudge,
        reason: 'Seit ${sinceBodyPrompt.inMinutes} min nichts getrunken oder '
            'bewegt. Kurz aufstehen kostet zwei Minuten.',
        recheckAfter: const Duration(minutes: 30),
      );
    }

    // 5. Deutliche Überziehung.
    if (overrun >= kClearAfterOverrun) {
      return FocusVerdict(
        action: FocusAction.clearInterrupt,
        reason: '${overrun.inMinutes} min über der geplanten Zeit. '
            'Weitermachen ist in Ordnung — bewusst weitermachen auch.',
        recheckAfter: const Duration(minutes: 30),
      );
    }
    if (overrun >= kGentleAfterOverrun) {
      return FocusVerdict(
        action: FocusAction.gentleNudge,
        reason: '${overrun.inMinutes} min über der geplanten Zeit.',
        recheckAfter: const Duration(minutes: 20),
      );
    }

    // 6. Alles in Ordnung: schützen.
    return const FocusVerdict(
      action: FocusAction.protect,
      reason: 'Läuft. Benachrichtigungen sind stumm.',
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
