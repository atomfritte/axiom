/// Aufgabe — modelliert ueber Aktivierungsenergie statt Prioritaet.
///
/// Der zentrale Modellbruch mit klassischen To-do-Apps: Es gibt bewusst
/// KEIN `priority`-Feld. Das Problem dieses Profils ist nicht zu wissen, was
/// wichtig ist — sondern den Kaltstart zu schaffen. [D2]
library;

import 'package:meta/meta.dart';

enum TaskState { inbox, ready, active, blocked, done, dropped }

@immutable
final class Task {
  final String id;
  final String title;

  /// 1..10 — Wie schwer ist der KALTSTART?
  /// Nicht: wie lang. Nicht: wie wichtig. Nur der Start.
  final int activationEnergy;

  /// 1..10 — Wie viel intrinsischen Zug erzeugt die Aufgabe?
  final int salience;

  /// 1..10 — Was kostet das Nicht-Tun? (Konsequenz, nicht Wichtigkeit)
  final int stakes;

  /// Wann verfaellt oder eskaliert die Aufgabe?
  final DateTime? decayAt;

  final Duration? estimate;

  /// Atomizer-Hierarchie: Zerlegung, bis ein Teilschritt startbar ist.
  final String? parentId;

  final TaskState state;

  /// @home @phone @errand @deepwork
  final List<String> contexts;

  /// Wiedereinstiegsnotiz. Wird beim Verlassen automatisch gesetzt. [D11]
  final String? breadcrumb;

  /// Ortsbindung — ein frei gewaehlter Name, kein Koordinatenpaar.
  ///
  /// **Warum kein Geofence.** Ein Geofence beantwortet „wo bin ich", die
  /// eigentliche Frage ist aber „was geht hier". Er kostet
  /// `ACCESS_BACKGROUND_LOCATION` — die eingriffstiefste Berechtigung, die
  /// Android kennt —, verlangt entweder Play Services oder einen dauerhaft
  /// messenden Dienst, und legt in einer Datenbank mit Gesundheitsdaten ein
  /// Bewegungsprofil an. Der Gegenwert ist ein Kreis mit 200 m Radius, der
  /// nicht weiss, ob der Baumarkt offen hat.
  ///
  /// Der Ort steht deshalb als Name da, den der Nutzer selbst vergibt oder
  /// eine Geraeteroutine setzt. Kein Enum und keine Ortsverwaltung: Die
  /// Liste ergibt sich aus dem, was benutzt wird — jede weitere
  /// Pflegeoberflaeche waere Meta-Work (D3). [D2]
  final String? place;

  const Task({
    required this.id,
    required this.title,
    required this.activationEnergy,
    required this.salience,
    required this.stakes,
    this.decayAt,
    this.estimate,
    this.parentId,
    this.state = TaskState.inbox,
    this.contexts = const [],
    this.breadcrumb,
    this.place,
  })  : assert(activationEnergy >= 1 && activationEnergy <= 10),
        assert(salience >= 1 && salience <= 10),
        assert(stakes >= 1 && stakes <= 10);

  /// Startbar, wenn die Aktivierungsenergie unter die verfuegbare Kapazitaet
  /// faellt — und der Ort passt. `capacity` ist 0..100,
  /// `activationEnergy` ist 1..10.
  ///
  /// [atPlace] ist der gerade gesetzte Ort, `null` heisst „kein Ort gesetzt".
  bool isStartable(int capacity, {String? atPlace}) =>
      state == TaskState.ready &&
      activationEnergy <= capacity / 10 &&
      isHere(atPlace);

  /// Passt die Ortsbindung dieser Aufgabe zu [currentPlace]?
  ///
  /// Zwei Faelle sind bewusst wahr:
  ///
  ///  * Die Aufgabe ist ortsungebunden — sie geht ueberall.
  ///  * Es ist **kein** Ort gesetzt. Dann wird nichts unterdrueckt. Etwas zu
  ///    verstecken, das der Nutzer nie eingeschaltet hat, waere der
  ///    schlimmere Fehler: Eine Aufgabe, die aus einem unbemerkten Filter
  ///    heraus nicht mehr erscheint, ist faktisch geloescht — und danach
  ///    traut man dem Bestand nicht mehr [D9].
  bool isHere(String? currentPlace) {
    final mine = place?.trim();
    if (mine == null || mine.isEmpty) return true;
    final here = currentPlace?.trim();
    if (here == null || here.isEmpty) return true;
    return samePlace(mine, here);
  }

  Task copyWith({
    String? title,
    int? activationEnergy,
    int? salience,
    int? stakes,
    DateTime? decayAt,
    Duration? estimate,
    String? parentId,
    TaskState? state,
    List<String>? contexts,
    String? breadcrumb,
    String? place,
  }) =>
      Task(
        id: id,
        title: title ?? this.title,
        activationEnergy: activationEnergy ?? this.activationEnergy,
        salience: salience ?? this.salience,
        stakes: stakes ?? this.stakes,
        decayAt: decayAt ?? this.decayAt,
        estimate: estimate ?? this.estimate,
        parentId: parentId ?? this.parentId,
        state: state ?? this.state,
        contexts: contexts ?? this.contexts,
        breadcrumb: breadcrumb ?? this.breadcrumb,
        place: place ?? this.place,
      );

  @override
  String toString() => 'Task($title, ae=$activationEnergy, '
      'stakes=$stakes, ${state.name})';
}

/// Der Wert, den das Regelwerk fuer `place` sieht, solange kein Ort gesetzt
/// ist.
///
/// Bewusst ein Wert und kein `null`: Eine Bedingung, deren Variable nicht
/// aufloest, wirft (Fail-Fast, siehe [SymbolicCompare]). Eine Regel, die die
/// gesamte Auswertung abbricht, nur weil gerade kein Ort gesetzt ist, waere
/// ein Ausfall ohne Not.
const String kNoPlace = 'none';

/// Zwei Ortsnamen meinen denselben Ort, wenn sie sich nur in Gross- und
/// Kleinschreibung oder Randleerzeichen unterscheiden.
///
/// Dieselbe Nachsicht wie im Regelwerk, wo `SymbolicCompare` kleingeschrieben
/// vergleicht. Ohne sie waeren „Büro" und „büro" zweierlei — und das faellt
/// niemandem auf, es erscheint nur nichts.
bool samePlace(String a, String b) =>
    a.trim().toLowerCase() == b.trim().toLowerCase();

// ── Fristdruck ──────────────────────────────────────────────────────────

/// Kaltstartkosten je Punkt Aktivierungsenergie.
const Duration kStartCostPerEnergy = Duration(minutes: 15);

/// Bearbeitungszeit, wenn keine geschaetzt ist.
const Duration kDefaultTaskWork = Duration(minutes: 30);

/// Stunden bis zur naechsten Frist, wenn es keine gibt.
///
/// Kein `null`: `numeric()` darf nicht leer zurueckkommen, sonst wirft die
/// Bedingung. Die Zahl ist so gross gewaehlt, dass keine sinnvolle Regel sie
/// je unterschreitet — dieselbe Logik wie bei `minutes_since` fuer ein nie
/// eingetretenes Ereignis.
const num kNoDeadlineHours = 9999;

/// Anlauf einer Aufgabe: die Zeit, die sie von jetzt bis erledigt braucht.
///
///     anlauf = activationEnergy x 15 min  +  (estimate ?? 30 min)
///
/// Der Kaltstart steht vorn und wiegt schwer, weil er bei diesem Profil der
/// teure Teil ist — nicht die Bearbeitung [D2]. Die Formel ist grob und soll
/// es sein: Sie beantwortet nur die eine Frage „reicht die Zeit ueberhaupt
/// noch, um anzufangen?". Sichtbar bleibt sie trotzdem (G2) — die
/// Aufgabenliste zeigt den Anlauf, sobald er nicht mehr passt.
Duration taskRunway(Task task) =>
    kStartCostPerEnergy * task.activationEnergy +
    (task.estimate ?? kDefaultTaskWork);

/// Die offene Aufgabe mit dem knappsten Vorlauf, oder null.
///
/// Bewusst nicht „die naechste Frist": Eine Frist in vier Stunden mit zwanzig
/// Minuten Anlauf draengt weniger als eine in acht Stunden mit sechs Stunden
/// Anlauf. Verglichen wird deshalb der Rest — Zeit bis zur Frist minus
/// Anlauf. Genau diese Rechnung laeuft bei diesem Profil sonst im Kopf, und
/// zwar systematisch zu optimistisch [D4].
({Task task, Duration untilDue, Duration runway})? tightestDeadline(
  List<Task> tasks,
  DateTime now,
) {
  ({Task task, Duration untilDue, Duration runway})? best;
  for (final task in tasks) {
    final due = task.decayAt;
    if (due == null) continue;
    if (task.state != TaskState.ready && task.state != TaskState.active) {
      continue;
    }
    final candidate = (
      task: task,
      untilDue: due.difference(now),
      runway: taskRunway(task),
    );
    if (best == null ||
        candidate.untilDue - candidate.runway <
            best.untilDue - best.runway) {
      best = candidate;
    }
  }
  return best;
}

/// Stunden, auf eine Nachkommastelle gerundet.
///
/// Regeln vergleichen gegen ganze Stunden; ohne Rundung stuende im
/// Regelinspektor „jetzt: 5.983333333333333" und niemand liest das.
double hoursOf(Duration duration) =>
    (duration.inMinutes / 60 * 10).roundToDouble() / 10;

/// Auswahl-Score. Siehe docs/03-DATENMODELL.md §4.1.
///
///   urgency = stakes x decayPressure
///   pull    = salience
///   score   = (0.6 x urgency + 0.4 x pull) / activationEnergy
///
/// Die Division durch die Aktivierungsenergie ist der Kern: Eine wichtige,
/// aber unstartbare Aufgabe gewinnt nicht — sie wird stattdessen zerlegt
/// (siehe `needsAtomizing`).
double taskScore(Task task, DateTime now) {
  final urgency = task.stakes * _decayPressure(task.decayAt, now);
  final pull = task.salience.toDouble();
  return (0.6 * urgency + 0.4 * pull) / task.activationEnergy;
}

/// 0.5 (kein Termin) bis 2.0 (ueberfaellig).
double _decayPressure(DateTime? decayAt, DateTime now) {
  if (decayAt == null) return 0.5;
  final hoursLeft = decayAt.difference(now).inMinutes / 60.0;
  if (hoursLeft <= 0) return 2.0;
  if (hoursLeft >= 168) return 0.6; // > 1 Woche: kaum Zug [D12]
  return (2.0 - (hoursLeft / 168) * 1.4).clamp(0.6, 2.0);
}

/// Wichtig, dringend — aber nicht startbar.
///
/// Der uebliche Fehlermodus waere, die Aufgabe trotzdem anzuzeigen und damit
/// Schuld zu erzeugen. Stattdessen erzwingt M2 die Zerlegung, bis ein
/// Teilschritt unter die Kapazitaet faellt. [D2]
bool needsAtomizing(Task task, int capacity, DateTime now) =>
    task.state == TaskState.ready &&
    !task.isStartable(capacity) &&
    task.stakes >= 8 &&
    task.decayAt != null &&
    task.decayAt!.difference(now).inHours < 72;
