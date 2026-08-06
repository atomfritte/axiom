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
///
/// Die Reihenfolge ist die Dringlichkeit: `candidates` sortiert nach dem
/// Index. Neue Gründe gehören ans Ende, sonst verschiebt sich still, was
/// zuerst angeboten wird.
enum AtomizeReason {
  /// Wichtig, Frist nah, aber außerhalb der Reichweite.
  urgentButUnreachable,

  /// Liegt lange unangetastet — der klassische Schuld-Erzeuger.
  stale,

  /// Aktivierungsenergie am oberen Ende, unabhängig von Kapazität.
  inherentlyHeavy,

  /// Startenergie über der heutigen Kapazität — sonst nichts Besonderes.
  ///
  /// Der häufigste Fall, und lange der übersehene: Eine Aufgabe, die nicht
  /// startbar ist, war nur dann ein Kandidat, wenn zusätzlich eine Frist
  /// drückte, sie lange lag oder ihre Energie im oberen Bereich war. Alles
  /// dazwischen fiel durch — insbesondere jeder Teilschritt, der nach einer
  /// Zerlegung immer noch zu groß geraten war. Er stand dann außer
  /// Reichweite und ließ sich nicht weiter zerlegen, und genau dort bleibt
  /// der Kaltstart hängen [D2].
  outOfReach,

  /// Vom Nutzer angestoßen — ohne dass eine der Bedingungen zutrifft.
  ///
  /// Zerlegen ist nie verboten. Wer einen Schritt für zu groß hält, hat
  /// recht, auch wenn die Formel ihn für erreichbar hält (G3).
  chosen,
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
        AtomizeReason.outOfReach =>
          'Die Startenergie liegt über dem, was heute trägt. Das ist eine '
              'Messung, kein Urteil — ein kleinerer erster Schritt bringt '
              'sie in Reichweite.',
        AtomizeReason.chosen =>
          'Auch ein kleiner Schritt lässt sich teilen. Was ist die erste '
              'Handlung darin?',
      };
}

/// Hat die Aufgabe noch offene Teilschritte?
///
/// Nur offene zählen. Wären erledigte Kinder mitgezählt, bliebe eine
/// Aufgabe für immer „schon zerlegt" — auch dann, wenn von der Zerlegung
/// nichts mehr übrig ist und der Rest erneut zerlegt werden müsste.
bool hasOpenSteps(List<Task> tasks, String parentId) =>
    tasks.any((t) => t.parentId == parentId && isTaskOpen(t));

/// Wie lange eine Aufgabe unangetastet liegen darf, bevor sie als
/// Zerlegungskandidat gilt.
const Duration kStaleAfter = Duration(days: 10);

final class Atomizer {
  const Atomizer();

  /// Findet Aufgaben, die von sich aus zum Zerlegen angeboten werden.
  ///
  /// Sortiert nach Dringlichkeit. Die Oberfläche zeigt immer nur die erste —
  /// eine Liste von Zerlegungsaufträgen wäre selbst wieder eine Hürde (G1).
  ///
  /// **Das ist der Vorschlag, nicht die Erlaubnis.** Was hier nicht steht,
  /// lässt sich trotzdem zerlegen — dafür gibt es [candidateFor]. Eine
  /// laufende oder bereits zerlegte Aufgabe von sich aus anzubieten wäre
  /// falsch (sie ist in Arbeit, bzw. ihre Schritte sind der Weg hinein),
  /// sie deshalb für unzerlegbar zu halten aber auch.
  List<AtomizeCandidate> candidates({
    required List<Task> tasks,
    required int capacity,
    required DateTime now,
    required Map<String, DateTime> createdAt,
  }) {
    final result = <AtomizeCandidate>[];

    for (final task in tasks) {
      if (task.state != TaskState.ready) continue;
      // Zerlegte Aufgaben nicht erneut anbieten, solange Schritte offen
      // sind: Sonst steht die Klammer neben ihren eigenen Teilen.
      if (hasOpenSteps(tasks, task.id)) continue;
      // Bewusst ohne `atPlace`: Der Ort entscheidet, was man *tun* kann,
      // nicht, was man *planen* kann. Den ersten Schritt einer
      // Baumarkt-Aufgabe aufzuschreiben geht am Schreibtisch — und wenn hier
      // gerade nichts startbar ist, ist genau das die nuetzlichste Handlung.
      // Unterdrueckt wird der Ort deshalb nur in der Auswahl (`isStartable`).
      if (task.isStartable(capacity)) continue;

      result.add(AtomizeCandidate(
        task: task,
        reason: _reasonFor(task, capacity, now, createdAt[task.id]),
        targetEnergy: _targetEnergy(capacity),
      ));
    }

    result.sort((a, b) {
      final byReason = a.reason.index.compareTo(b.reason.index);
      if (byReason != 0) return byReason;
      final byStakes = b.task.stakes.compareTo(a.task.stakes);
      if (byStakes != 0) return byStakes;
      // Zuletzt die Kennung. Die Oberflaeche zeigt genau den ersten
      // Kandidaten (G1) — welcher das ist, darf nicht davon abhaengen, in
      // welcher Reihenfolge der Bestand aus der Datenbank kommt. `List.sort`
      // ist in Dart ab 32 Elementen nicht stabil, gleichrangige Kandidaten
      // wechselten also tatsaechlich die Plaetze.
      return a.task.id.compareTo(b.task.id);
    });
    return result;
  }

  /// Der Zerlegungsauftrag für **diese** Aufgabe, ohne Bedingung.
  ///
  /// Ein Teilschritt, der immer noch zu groß ist, muss sich weiter zerlegen
  /// lassen — beliebig tief. Die Hürde liegt am Anfang, und wenn der erste
  /// Schritt nicht klein genug ist, passiert nichts; eine Grenze bei einer
  /// Ebene wäre willkürlich [D2]. Deshalb prüft diese Methode weder Zustand
  /// noch Reichweite: Sie beantwortet nicht „soll das zerlegt werden?",
  /// sondern „der Nutzer will zerlegen — womit fängt er an?".
  AtomizeCandidate candidateFor({
    required Task task,
    required int capacity,
    required DateTime now,
    DateTime? createdAt,
  }) =>
      AtomizeCandidate(
        task: task,
        reason: _reasonFor(task, capacity, now, createdAt),
        targetEnergy: _targetEnergy(capacity),
      );

  AtomizeReason _reasonFor(
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
    // Außer Reichweite ist Grund genug. Vorher endete die Prüfung hier mit
    // „kein Grund", und damit blieb jeder zu groß geratene Teilschritt
    // liegen, ohne je zum Zerlegen angeboten zu werden [D2].
    //
    // Gemessen wird Energie gegen Kapazität, nicht `isStartable`: Das
    // zieht den Zustand mit hinein, und eine laufende Aufgabe wäre dann
    // „über der Kapazität", obwohl sie gerade bearbeitet wird.
    if (task.activationEnergy > capacity / 10) return AtomizeReason.outOfReach;
    return AtomizeReason.chosen;
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
  ///
  /// Die Energie wird auf 1..10 geklemmt statt abgelehnt. Aufrufer leiten
  /// sie ab („eins unter dem Ganzen"), und bei einer Aufgabe mit Energie 1
  /// kommt dabei 0 heraus — der Wertebereich von [Task] verbietet das. Ein
  /// Abbruch an dieser Stelle würde den gerade eingetippten ersten Schritt
  /// verwerfen, und das ist der teuerste Moment, um etwas zu verlieren [D2].
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
        activationEnergy: step.energy.clamp(1, 10),
        // Der erste Schritt erbt den Zug des Ganzen; spätere weniger.
        salience: i == 0 ? parent.salience : (parent.salience - 1).clamp(1, 10),
        stakes: i == 0
            ? (parent.stakes - 1).clamp(1, 10)
            : (parent.stakes - 3).clamp(1, 10),
        decayAt: i == 0 ? parent.decayAt : null,
        parentId: parent.id,
        contexts: parent.contexts,
        // Ein Teilschritt einer Baumarkt-Aufgabe ist auch im Baumarkt. Ohne
        // das Erben faellt die Ortsbindung beim Zerlegen lautlos weg — und
        // die Schritte wuerden ueberall vorgeschlagen. [D2]
        place: parent.place,
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
