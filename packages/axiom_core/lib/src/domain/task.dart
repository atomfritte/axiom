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
  })  : assert(activationEnergy >= 1 && activationEnergy <= 10),
        assert(salience >= 1 && salience <= 10),
        assert(stakes >= 1 && stakes <= 10);

  /// Startbar, wenn die Aktivierungsenergie unter die verfuegbare Kapazitaet
  /// faellt. `capacity` ist 0..100, `activationEnergy` ist 1..10.
  bool isStartable(int capacity) =>
      state == TaskState.ready && activationEnergy <= capacity / 10;

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
      );

  @override
  String toString() => 'Task($title, ae=$activationEnergy, '
      'stakes=$stakes, ${state.name})';
}

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
