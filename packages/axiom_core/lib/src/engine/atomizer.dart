/// Atomizer — zerlegt Aufgaben, bis ein Schritt startbar ist. M2.
///
/// Der übliche Fehlermodus: Eine wichtige Aufgabe steht seit Wochen oben auf
/// der Liste, wird bei jedem Blick gesehen, nie gestartet — und erzeugt jedes
/// Mal Schuld. Schuld senkt die Regulationsreserve und macht den Start noch
/// unwahrscheinlicher. Die Aufgabe wird nicht wichtiger, nur teurer. [D2]
///
/// **Der Atomizer erfindet keine Teilschritte.** Er kann nicht wissen, was
/// „Steuererklärung" konkret bedeutet, und Raten wäre hier schlimmer als
/// Schweigen (G2, ADR-0003). Was er tut: Er erzwingt die Zerlegung, stellt
/// die richtige Frage und bietet eine feste, sichtbare Liste von
/// Startschritt-Formen an.
///
/// Die richtige Frage lautet nicht „In welche Teile zerfällt das?" —
/// darauf antwortet ein Systemizer mit einem vollständigen Projektplan, und
/// der ist selbst wieder eine Aufgabe mit hoher Aktivierungsenergie.
/// Sie lautet: **„Was ist die allererste körperliche Handlung?"**
library;

import 'package:meta/meta.dart';

import '../domain/task.dart';

/// Formen, die ein erster Schritt annehmen kann.
///
/// Keine Vorschläge im Sinne von „mach das" — ein Formenkatalog, an dem
/// entlang der Nutzer seinen eigenen ersten Schritt findet. Bewusst
/// körperlich und beobachtbar: „Ordner auf den Tisch legen" ist überprüfbar,
/// „mich damit beschäftigen" nicht.
enum StepShape {
  fetch('Etwas holen', 'Ordner auf den Tisch legen, Unterlagen rausholen'),
  open('Etwas öffnen', 'Datei öffnen, Formular aufrufen, Seite laden'),
  find('Etwas nachschlagen', 'Nummer suchen, Adresse raussuchen, Termin prüfen'),
  write('Einen Satz schreiben', 'Betreff tippen, erste Zeile, Notiz anfangen'),
  ask('Eine Frage stellen', 'Kurz anrufen, Nachricht schicken, nachfragen'),
  decide('Eine Sache festlegen', 'Datum wählen, Betrag festlegen, ja oder nein'),
  timebox('Zwei Minuten dranbleiben', 'Wecker stellen, anfangen, aufhören dürfen');

  const StepShape(this.label, this.examples);

  final String label;

  /// Beispiele. Bewusst konkret und körperlich.
  final String examples;
}

/// Warum eine Aufgabe zerlegt werden sollte.
enum AtomizeReason {
  /// Wichtig, Frist nah, aber außerhalb der Reichweite.
  urgentButUnreachable,

  /// Liegt lange unangetastet — der klassische Schuld-Erzeuger.
  stale,

  /// Aktivierungsenergie am oberen Ende, unabhängig von Kapazität.
  inherentlyHeavy,
}

@immutable
final class AtomizeCandidate {
  final Task task;
  final AtomizeReason reason;

  /// Zielwert für den ersten Teilschritt.
  final int targetEnergy;

  const AtomizeCandidate({
    required this.task,
    required this.reason,
    required this.targetEnergy,
  });

  /// Text für die Oberfläche. Beschreibt den Zustand, urteilt nicht.
  String get explanation => switch (reason) {
        AtomizeReason.urgentButUnreachable =>
          'Wichtig und bald fällig, aber heute außerhalb deiner Reichweite. '
              'Ein kleiner erster Schritt bringt mehr als ein großer Anlauf.',
        AtomizeReason.stale =>
          'Liegt seit einer Weile unangetastet. Das ist kein Versäumnis — '
              'meist ist der Einstieg zu groß geraten.',
        AtomizeReason.inherentlyHeavy =>
          'Der Einstieg ist schwer. Das lässt sich aufteilen.',
      };
}

/// Wie lange eine Aufgabe unangetastet liegen darf, bevor sie als
/// Zerlegungskandidat gilt.
const Duration kStaleAfter = Duration(days: 10);

final class Atomizer {
  const Atomizer();

  /// Findet Aufgaben, die zerlegt werden sollten.
  ///
  /// Sortiert nach Dringlichkeit. Die Oberfläche zeigt immer nur die erste —
  /// eine Liste von Zerlegungsaufträgen wäre selbst wieder eine Hürde (G1).
  List<AtomizeCandidate> candidates({
    required List<Task> tasks,
    required int capacity,
    required DateTime now,
    required Map<String, DateTime> createdAt,
  }) {
    final result = <AtomizeCandidate>[];

    for (final task in tasks) {
      if (task.state != TaskState.ready) continue;
      // Bereits zerlegte Aufgaben nicht erneut anbieten.
      if (tasks.any((t) => t.parentId == task.id)) continue;
      if (task.isStartable(capacity)) continue;

      final reason = _reasonFor(task, capacity, now, createdAt[task.id]);
      if (reason == null) continue;

      result.add(AtomizeCandidate(
        task: task,
        reason: reason,
        targetEnergy: _targetEnergy(capacity),
      ));
    }

    result.sort((a, b) {
      final byReason = a.reason.index.compareTo(b.reason.index);
      if (byReason != 0) return byReason;
      return b.task.stakes.compareTo(a.task.stakes);
    });
    return result;
  }

  AtomizeReason? _reasonFor(
    Task task,
    int capacity,
    DateTime now,
    DateTime? created,
  ) {
    if (needsAtomizing(task, capacity, now)) {
      return AtomizeReason.urgentButUnreachable;
    }
    if (created != null && now.difference(created) > kStaleAfter) {
      return AtomizeReason.stale;
    }
    if (task.activationEnergy >= 8) return AtomizeReason.inherentlyHeavy;
    return null;
  }

  /// Zielenergie für den ersten Teilschritt.
  ///
  /// Deutlich unter der aktuellen Kapazität, nicht knapp darunter: Ein
  /// Schritt, der gerade so passt, passt morgen nicht mehr — und dann
  /// beginnt das Ganze von vorn.
  int _targetEnergy(int capacity) =>
      ((capacity / 10) * 0.6).floor().clamp(1, 4);

  /// Baut die Teilaufgaben aus den Eingaben des Nutzers.
  ///
  /// Der erste Schritt erbt die Frist des Elternteils, damit er nicht
  /// seinerseits liegen bleibt. Die Stakes werden gedämpft: Ein Teilschritt
  /// trägt nicht die volle Konsequenz des Ganzen, sonst erzeugt er denselben
  /// Druck wie die Aufgabe, aus der er entstanden ist.
  List<Task> split({
    required Task parent,
    required List<({String title, int energy})> steps,
    required String Function() nextId,
  }) {
    final children = <Task>[];
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      children.add(Task(
        id: nextId(),
        title: step.title,
        activationEnergy: step.energy,
        // Der erste Schritt erbt den Zug des Ganzen; spätere weniger.
        salience: i == 0 ? parent.salience : (parent.salience - 1).clamp(1, 10),
        stakes: i == 0
            ? (parent.stakes - 1).clamp(1, 10)
            : (parent.stakes - 3).clamp(1, 10),
        decayAt: i == 0 ? parent.decayAt : null,
        parentId: parent.id,
        contexts: parent.contexts,
        state: TaskState.ready,
      ));
    }
    return children;
  }

  /// Ist die Zerlegung gelungen?
  ///
  /// Wenn kein Teilschritt unter die Kapazität fällt, war sie zu grob —
  /// dann wird erneut zerlegt, statt es dabei zu belassen.
  bool isSufficient(List<Task> children, int capacity) =>
      children.any((c) => c.isStartable(capacity));
}
