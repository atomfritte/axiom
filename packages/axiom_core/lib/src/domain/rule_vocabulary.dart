/// Was in einer Regel ueberhaupt vorkommen darf.
///
/// **Warum das im Kern steht und nicht in der Oberflaeche.** Der Editor darf
/// nichts anbieten, was die Engine nicht versteht — sonst baut man sich eine
/// Regel, die beim Laden abgelehnt wird, und erfaehrt das erst hinterher.
/// Die Liste hier ist dieselbe, gegen die `EvalContext` aufloest; steht sie
/// woanders, laufen die beiden auseinander und niemand merkt es.
///
/// Zugleich ist das der Unterschied zwischen einem Texteditor und einem
/// Werkzeug: Wer die moeglichen Variablen, ihre Einheiten und ihre
/// Wertebereiche kennt, kann fuehren statt raten zu lassen.
library;

import 'package:meta/meta.dart';

import 'condition.dart';
import 'rule.dart';

/// Eine Zahl, gegen die eine Regel vergleichen kann.
@immutable
final class NumericVariable {
  final String id;
  final String label;

  /// Was die Zahl bedeutet — erscheint im Editor unter dem Regler.
  final String meaning;

  final num min;
  final num max;

  /// Gilt ein hoher Wert als angespannt? Nur fuer die Darstellung; die
  /// Engine kennt keine Wertung.
  final bool highIsTense;

  const NumericVariable({
    required this.id,
    required this.label,
    required this.meaning,
    this.min = 0,
    this.max = 100,
    this.highIsTense = false,
  });
}

/// Eine Variable mit festen Auspraegungen.
@immutable
final class SymbolicVariable {
  final String id;
  final String label;
  final String meaning;

  /// Wert -> Beschriftung. Die Werte sind das, was der EvalContext liefert.
  final Map<String, String> values;

  const SymbolicVariable({
    required this.id,
    required this.label,
    required this.meaning,
    required this.values,
  });
}

/// Ein Ereignistyp, auf den sich `minutes_since` und `count_today` beziehen.
@immutable
final class EventVariable {
  final String id;
  final String label;

  /// Wofuer das Ereignis steht. Ohne das steht im Editor eine Liste von
  /// Bezeichnern, und man waehlt nach Klang statt nach Bedeutung.
  final String meaning;

  const EventVariable(this.id, this.label, [this.meaning = '']);
}

/// Eingriffstiefe einer Regel — mit dem Satz, der erklaert, was sie tut.
@immutable
final class SeveritySpec {
  final Severity value;
  final String label;
  final String meaning;

  const SeveritySpec(this.value, this.label, this.meaning);
}

/// Ein Defizit aus docs/01-PROFIL-DEFIZITE.md.
@immutable
final class DeficitSpec {
  final String id;
  final String label;

  const DeficitSpec(this.id, this.label);
}

/// Was eine Regel ausloest, und welche Angaben sie dafuer braucht.
@immutable
final class ActionSpec {
  final ActionType type;
  final String label;
  final String meaning;

  /// Parametername -> Beschriftung. Bewusst knapp gehalten: Jeder weitere
  /// Parameter ist eine Entscheidung mehr im Editor (G1).
  final Map<String, String> params;

  const ActionSpec({
    required this.type,
    required this.label,
    required this.meaning,
    this.params = const {},
  });
}

/// Der vollstaendige Wortschatz des Regelwerks.
abstract final class RuleVocabulary {
  /// Zahlen aus dem Zustandsvektor. Alle 0..100 — bewusst dieselbe Skala,
  /// damit man sie ohne Umrechnen vergleichen kann.
  static const List<NumericVariable> numerics = [
    NumericVariable(
      id: 'meta_minutes_today',
      label: 'Zeit im System heute',
      meaning: 'Minuten in AXIOM selbst, ohne Erfassung. Die einzige Zahl '
          'hier, die nicht den Nutzer misst, sondern die App — G4.',
      highIsTense: true,
    ),
    NumericVariable(
      id: 'capacity',
      label: 'Kapazität',
      meaning: 'Wie viel exekutive Reserve heute da ist. Hoch heißt: es geht '
          'viel.',
    ),
    NumericVariable(
      id: 'regulation',
      label: 'Regulationsreserve',
      meaning: 'Puffer für emotionale Belastung. Niedrig heißt: Impulse '
          'kommen leichter durch.',
    ),
    NumericVariable(
      id: 'load_index',
      label: 'Kompensationslast',
      meaning: 'Kumulierter Aufwand, den Alltag zu strukturieren. Der Wert, '
          'der einen Absturz ankündigt, bevor er sichtbar wird.',
      highIsTense: true,
    ),
    NumericVariable(
      id: 'sensation_need',
      label: 'Reizbedarf',
      meaning: 'Ungedeckter Bedarf sucht sich den schnellsten Kanal.',
      highIsTense: true,
    ),
    NumericVariable(
      id: 'sleep_debt',
      label: 'Schlafschuld',
      meaning: 'Stärkster einzelner Modulator der Kapazität.',
      highIsTense: true,
    ),
    NumericVariable(
      id: 'focus_debt',
      label: 'Fokuslast heute',
      meaning: 'Verbrauchte Konzentrationszeit seit heute früh.',
      highIsTense: true,
    ),
  ];

  static const List<SymbolicVariable> symbolics = [
    SymbolicVariable(
      id: 'load_level',
      label: 'Laststufe',
      meaning: 'Die Stufe, die aus der Kompensationslast folgt.',
      values: {
        'L0': 'Normalbetrieb',
        'L1': 'erhöht',
        'L2': 'kritisch',
        'L3': 'Erhaltungsmodus',
      },
    ),
    SymbolicVariable(
      id: 'active_slot',
      label: 'Was gerade läuft',
      meaning: 'Ob ein Fokus- oder Reiz-Slot aktiv ist.',
      values: {
        'focus': 'Fokus',
        'sensation': 'Reiz-Slot',
        'none': 'nichts',
      },
    ),
    SymbolicVariable(
      id: 'weekday',
      label: 'Wochentag',
      meaning: 'Für Regeln, die nur werktags oder nur am Wochenende gelten.',
      values: {
        'mon': 'Montag',
        'tue': 'Dienstag',
        'wed': 'Mittwoch',
        'thu': 'Donnerstag',
        'fri': 'Freitag',
        'sat': 'Samstag',
        'sun': 'Sonntag',
      },
    ),
  ];

  /// Ereignisse, auf die sich eine Regel sinnvoll beziehen kann.
  ///
  /// Nicht alle Event-Typen stehen hier: Interne Buchungen wie
  /// `decision_emitted` oder `meta_usage` wuerden nur Rauschen anbieten.
  static const List<EventVariable> events = [
    EventVariable('checkin', 'Check-in',
        'Vier Regler von Hand eingetragen.'),
    EventVariable('capture', 'Erfassung',
        'Etwas festgehalten, egal über welchen Weg.'),
    EventVariable('task_completed', 'Aufgabe erledigt',
        'Eine Aufgabe abgeschlossen.'),
    EventVariable('task_started', 'Aufgabe begonnen',
        'Eine Aufgabe begonnen.'),
    EventVariable('focus_start', 'Fokus gestartet',
        'Ein Fokusfenster geöffnet.'),
    EventVariable('focus_end', 'Fokus beendet',
        'Ein Fokusfenster geschlossen — geplant oder abgebrochen.'),
    EventVariable('sensation_slot', 'Reiz-Slot',
        'Ein Reiz-Slot eingelöst.'),
    EventVariable('impulse_intercepted', 'Impuls abgefangen',
        'Eine Wartezeit vor einem Impuls durchgehalten.'),
    EventVariable('body_prompt', 'Körpersignal quittiert',
        'Ein Körpersignal quittiert — getrunken, bewegt, gegessen.'),
    EventVariable('sleep_window', 'Schlaf eingetragen',
        'Eine Nacht eingetragen oder aus Health Connect übernommen.'),
    EventVariable('signal_incident', 'Vorfall',
        'Ein emotionaler Vorfall festgehalten.'),
    EventVariable('review_completed', 'Review abgeschlossen',
        'Ein Rückblick abgeschlossen.'),
    EventVariable('med_intake', 'Einnahme',
        'Eine Einnahme protokolliert. Nur Protokoll, nie Empfehlung.'),
  ];

  /// Die vier Eingriffstiefen.
  ///
  /// Standen bis hierher doppelt: privat im Regeleditor der App und noch
  /// einmal im Expertenmodus. Genau die Drift, gegen die dieser Wortschatz
  /// gebaut ist — eine Bedeutung, die an zwei Stellen gepflegt wird, ist
  /// nach dem zweiten Nachdenken an einer Stelle falsch.
  static const List<SeveritySpec> severities = [
    SeveritySpec(Severity.info, 'Info', 'Erscheint nur im Rückblick.'),
    SeveritySpec(Severity.nudge, 'Anstoß', 'Still, wegwischbar.'),
    SeveritySpec(Severity.intervene, 'Intervention',
        'Sichtbar, erwartet eine Antwort.'),
    SeveritySpec(Severity.enforce, 'Verbindlich',
        'Verändert Systemverhalten. Nur für Regeln, die du im ruhigen '
        'Zustand selbst verbindlich gesetzt hast.'),
  ];

  /// Die Defizite, auf die eine Regel einzahlen kann.
  static const List<DeficitSpec> deficits = [
    DeficitSpec('D1', 'Kompensationskosten'),
    DeficitSpec('D2', 'Startbarriere'),
    DeficitSpec('D3', 'Meta-Work-Falle'),
    DeficitSpec('D4', 'Zeitwahrnehmung'),
    DeficitSpec('D5', 'Reizhunger'),
    DeficitSpec('D6', 'Hyperfokus'),
    DeficitSpec('D7', 'Körperwahrnehmung'),
    DeficitSpec('D8', 'Schlaf'),
    DeficitSpec('D9', 'Erfassungslücke'),
    DeficitSpec('D10', 'Emotionale Spitzen'),
    DeficitSpec('D11', 'Kontextwechsel'),
    DeficitSpec('D12', 'Langfristziele'),
  ];

  static const List<ActionSpec> actions = [
    ActionSpec(
      type: ActionType.notify,
      label: 'Hinweis zeigen',
      meaning: 'Ein Satz, mehr nicht. Die häufigste und harmloseste Aktion.',
      params: {'text': 'Was dort stehen soll'},
    ),
    ActionSpec(
      type: ActionType.promptCheckin,
      label: 'Check-in anstoßen',
      meaning: 'Fragt die vier Regler ab.',
      params: {'slot': 'Bezeichnung des Messpunkts'},
    ),
    ActionSpec(
      type: ActionType.suggestTask,
      label: 'Aufgabe vorschlagen',
      meaning: 'Schlägt die passendste startbare Aufgabe vor.',
    ),
    ActionSpec(
      type: ActionType.forceAtomize,
      label: 'Zum Zerlegen auffordern',
      meaning: 'Wenn etwas Wichtiges außer Reichweite liegt: zerlegen statt '
          'anmahnen.',
    ),
    ActionSpec(
      type: ActionType.suggestSlot,
      label: 'Reiz-Slot vorschlagen',
      meaning: 'Deckt den Bedarf geplant, bevor er sich den schnellsten '
          'Kanal sucht.',
    ),
    ActionSpec(
      type: ActionType.startCooldown,
      label: 'Wartezeit setzen',
      meaning: 'Kein Verbot — nur Latenz zwischen Impuls und Handlung.',
      params: {'cooldown_min': 'Minuten'},
    ),
    ActionSpec(
      type: ActionType.protectFocus,
      label: 'Fokus schützen',
      meaning: 'Unterdrückt Benachrichtigungen, solange der Block läuft.',
    ),
    ActionSpec(
      type: ActionType.escalateInterrupt,
      label: 'Deutlich unterbrechen',
      meaning: 'Nur mit belegbarem Grund. Eine falsch getimte Unterbrechung '
          'zerstört den wertvollsten Zustand, den dieses Profil hat.',
    ),
    ActionSpec(
      type: ActionType.setAnchor,
      label: 'Zeitanker setzen',
      meaning: 'Legt einen Ankerschritt an.',
    ),
    ActionSpec(
      type: ActionType.setLoadLevel,
      label: 'Laststufe setzen',
      meaning: 'Hebt oder senkt die Stufe, aus der die Konsequenzen folgen.',
      params: {'level': 'L0 bis L3'},
    ),
    ActionSpec(
      type: ActionType.restrictMode,
      label: 'Erhaltungsmodus',
      meaning: 'Nur Pflicht und Erholung. Ein Erfolg des Systems, kein '
          'Scheitern.',
    ),
    ActionSpec(
      type: ActionType.lockConfig,
      label: 'Konfiguration sperren',
      meaning: 'Der Meta-Guard gegen sich selbst (M12).',
    ),
    ActionSpec(
      type: ActionType.logOnly,
      label: 'Nur mitschreiben (SHADOW)',
      meaning: 'Läuft stumm mit und wird protokolliert. Der Zustand, in dem '
          'jede neue Regel beginnt.',
    ),
  ];

  /// Operatoren mit lesbarer Beschriftung.
  static const Map<CompareOp, String> operatorLabels = {
    CompareOp.lt: 'kleiner als',
    CompareOp.lte: 'höchstens',
    CompareOp.gte: 'mindestens',
    CompareOp.gt: 'größer als',
    CompareOp.eq: 'genau',
    CompareOp.ne: 'nicht',
  };

  /// Operatoren, die fuer symbolische Vergleiche erlaubt sind.
  static const List<CompareOp> symbolicOperators = [CompareOp.eq, CompareOp.ne];

  static NumericVariable? numeric(String id) =>
      numerics.where((v) => v.id == id).firstOrNull;

  static SymbolicVariable? symbolic(String id) =>
      symbolics.where((v) => v.id == id).firstOrNull;

  static EventVariable? event(String id) =>
      events.where((e) => e.id == id).firstOrNull;

  static ActionSpec? action(ActionType type) =>
      actions.where((a) => a.type == type).firstOrNull;

  /// Beschriftung fuer eine Variable, egal welcher Art.
  static String labelFor(String id) =>
      numeric(id)?.label ?? symbolic(id)?.label ?? event(id)?.label ?? id;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
