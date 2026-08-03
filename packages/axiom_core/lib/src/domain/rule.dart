/// Regel — die Benutzeroberflaeche fuer den Systemizing-Drive.
///
/// Regeln sind Daten (YAML unter Git), nicht Code. Eine Regelaenderung ist ein
/// Commit und ein Diff, kein Rebuild. Siehe docs/04-REGELWERK.md.
library;

import 'package:meta/meta.dart';

import 'condition.dart';

/// Eingriffstiefe. Bestimmt Konfliktrang und Benachrichtigungskanal.
enum Severity {
  /// Erscheint nur im Review.
  info(0),

  /// Stille Notification, wegwischbar.
  nudge(1),

  /// Sichtbare Notification, verlangt Antwort.
  intervene(2),

  /// Veraendert Systemverhalten (Sperre, Modus, Cooldown).
  /// Nur fuer Regeln, die der Nutzer im ruhigen Zustand selbst autorisiert
  /// hat — der "Vertrag mit dem Vergangenheits-Ich" (M6).
  enforce(3);

  const Severity(this.rank);
  final int rank;

  static Severity parse(String s) => Severity.values.firstWhere(
        (v) => v.name == s,
        orElse: () => throw ConditionError('Unbekannte Severity: $s'),
      );
}

enum ActionType {
  suggestTask('suggest_task'),
  forceAtomize('force_atomize'),
  setAnchor('set_anchor'),
  notify('notify'),
  startCooldown('start_cooldown'),
  suggestSlot('suggest_slot'),
  protectFocus('protect_focus'),
  escalateInterrupt('escalate_interrupt'),
  setLoadLevel('set_load_level'),
  restrictMode('restrict_mode'),
  lockConfig('lock_config'),
  promptCheckin('prompt_checkin'),

  /// SHADOW-Modus: Regel laeuft stumm mit und wird nur protokolliert.
  /// Jede neue Regel startet hier — mindestens 7 Tage, bevor sie sprechen darf.
  logOnly('log_only');

  const ActionType(this.token);
  final String token;

  static ActionType parse(String s) => ActionType.values.firstWhere(
        (v) => v.token == s,
        orElse: () => throw ConditionError('Unbekannte Aktion: $s'),
      );
}

@immutable
final class Action {
  final ActionType type;
  final Map<String, Object?> params;
  const Action(this.type, [this.params = const {}]);

  @override
  String toString() => type.token;
}

/// Spam-Schutz. Pflichtfeld — ohne Cooldown entsteht Benachrichtigungsflut,
/// der haeufigste Sterbeverlauf von ADHS-Apps (R2).
@immutable
final class Cooldown {
  final Duration minInterval;
  final int? maxPerDay;

  /// Bei wiederholter Ablehnung Abstand verdoppeln — eingebaute
  /// Selbstkorrektur einer nervenden Regel.
  final bool exponentialBackoff;

  const Cooldown({
    required this.minInterval,
    this.maxPerDay,
    this.exponentialBackoff = false,
  });

  /// Effektives Intervall nach [consecutiveRejections] Ablehnungen in Folge.
  /// Gedeckelt bei 8x, damit eine Regel nicht faktisch verschwindet, ohne
  /// im Review als Streichkandidat aufzutauchen.
  Duration effectiveInterval(int consecutiveRejections) {
    if (!exponentialBackoff || consecutiveRejections <= 0) return minInterval;
    final factor = 1 << consecutiveRejections.clamp(0, 3);
    return minInterval * factor;
  }
}

@immutable
final class Rule {
  /// "R-050" — stabil, wird nie wiederverwendet, auch nicht nach Loeschung.
  final String id;

  final String title;

  /// PFLICHT. Wird dem Nutzer als Begruendung angezeigt.
  /// Leer = Ladefehler. So wird G2 erzwungen statt erhofft.
  final String rationale;

  /// "D5" — Rueckbindung an docs/01-PROFIL-DEFIZITE.md.
  /// Regeln ohne Defizitbezug sind verdaechtig.
  final String? deficit;

  final Condition when;
  final Action then;

  /// 0..100, hoeher gewinnt bei gleicher Severity.
  final int priority;

  final Severity severity;
  final Cooldown cooldown;
  final bool enabled;

  Rule({
    required this.id,
    required this.title,
    required this.rationale,
    required this.when,
    required this.then,
    required this.priority,
    required this.severity,
    required this.cooldown,
    this.deficit,
    this.enabled = true,
  }) {
    if (rationale.trim().isEmpty) {
      throw ConditionError(
        'Regel $id ohne rationale. Jede Ausgabe muss begruendbar sein (G2).',
      );
    }
    if (priority < 0 || priority > 100) {
      throw ConditionError('Regel $id: priority muss 0..100 sein');
    }
  }

  /// SHADOW-Regeln beobachten nur — sie erzeugen nie eine Nutzerausgabe.
  bool get isShadow => then.type == ActionType.logOnly;

  @override
  String toString() => '$id (${severity.name}/$priority) $title';
}
