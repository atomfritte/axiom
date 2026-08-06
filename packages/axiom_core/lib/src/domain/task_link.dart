/// Blocker-Beziehungen: **A blockiert B.** Genau eine Beziehungsart.
///
/// Kein „haengt zusammen mit", kein „Duplikat von", kein „folgt auf". Ein
/// Beziehungsgeflecht ist die Sorte System, die zu pflegen befriedigender ist
/// als die Arbeit, fuer die es gebaut wurde — jede weitere Art kostet Pflege
/// ohne Gegenwert [D3]. Das ist entschieden, nicht zu erweitern.
///
/// **Namensfalle.** [TaskState.blocked] heisst in AXIOM „zerlegt": Die
/// Aufgabe ist durch ihre Teilschritte vertreten. Eine Aufgabe mit offenen
/// Blockern **wartet** — und das ist kein Zustand, sondern eine Rechnung aus
/// den Beziehungen (siehe [TaskLinkGraph.isWaiting]). Weniger Zustaende sind
/// besser als mehr: Ein gespeicherter Wartezustand muesste bei jedem
/// erledigten Blocker nachgezogen werden, und genau dort entstehen die
/// stummen Fehler.
library;

import 'package:meta/meta.dart';

import 'task.dart';

/// „[blockerId] blockiert [blockedId]." Mehr Bedeutung hat die Kante nicht.
@immutable
final class TaskLink {
  /// Die Aufgabe, die im Weg steht.
  final String blockerId;

  /// Die Aufgabe, die deshalb wartet.
  final String blockedId;

  const TaskLink({required this.blockerId, required this.blockedId});

  @override
  bool operator ==(Object other) =>
      other is TaskLink &&
      other.blockerId == blockerId &&
      other.blockedId == blockedId;

  @override
  int get hashCode => Object.hash(blockerId, blockedId);

  @override
  String toString() => 'TaskLink($blockerId -> $blockedId)';
}

/// Die neue Beziehung schloesse einen Kreis.
///
/// **Warum das ein Fehler ist und kein Sonderfall.** A blockiert B blockiert A
/// legt die Auswahl lahm: Beide warten fuer immer, keine ist je startbar, und
/// nichts sagt warum. Das ist der teuerste Zustand, den dieses System kennt —
/// ein Bestand, aus dem etwas unbemerkt herausfaellt, wird nicht mehr
/// geglaubt [D9]. Deshalb Fail-Fast beim Anlegen statt Ausweichen beim Lesen.
///
/// [path] traegt den geschlossenen Kreis von der ersten Aufgabe ueber alle
/// Zwischenschritte zurueck zu ihr selbst, damit die Oberflaeche zeigen kann,
/// **wo** er sich schliesst — eine Fehlermeldung ohne Ort waere hier so gut
/// wie keine.
@immutable
final class TaskLinkCycleError implements Exception {
  final List<String> path;

  const TaskLinkCycleError(this.path);

  // Echte Umlaute: Der Text kann im Regeleditor am grossen Bildschirm
  // erscheinen und ist damit ein Nutzertext (`language_test.dart`).
  @override
  String toString() => 'TaskLinkCycleError: Diese Beziehung schlösse einen '
      'Kreis (${path.join(" → ")}). Alle beteiligten Aufgaben würden dauerhaft '
      'warten.';
}

/// Prueft, ob [blockerId] -> [blockedId] einen Kreis schliessen wuerde.
///
/// Reine Funktion: gleiche Eingabe, gleiche Ausgabe, keine Uhr, kein Zufall
/// (ADR-0003). Wirft [TaskLinkCycleError] mit dem gefundenen Weg, sonst
/// nichts.
///
/// Gesucht wird ein bestehender Weg von [blockedId] zurueck zu [blockerId]:
/// Existiert er, waere die neue Kante der Schluss des Kreises. Die Suche
/// laeuft in Breite, damit der **kuerzeste** Kreis gemeldet wird — der lange
/// erklaert dasselbe, nur unleserlicher.
void ensureAcyclic({
  required Iterable<TaskLink> existing,
  required String blockerId,
  required String blockedId,
}) {
  // Eine Aufgabe, die sich selbst blockiert, ist der kuerzeste Kreis. Sie
  // hier durchzulassen hiesse, sie unten in der Suche nie zu finden.
  if (blockerId == blockedId) {
    throw TaskLinkCycleError([blockerId, blockedId]);
  }

  final outgoing = <String, List<String>>{};
  for (final link in existing) {
    (outgoing[link.blockerId] ??= <String>[]).add(link.blockedId);
  }
  // Sortiert, damit bei mehreren moeglichen Wegen immer derselbe gemeldet
  // wird. Eine Fehlermeldung, die zwischen zwei Laeufen wechselt, ist keine.
  for (final list in outgoing.values) {
    list.sort();
  }

  final cameFrom = <String, String>{};
  final seen = <String>{blockedId};
  final queue = <String>[blockedId];

  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    for (final next in outgoing[current] ?? const <String>[]) {
      if (next == blockerId) {
        // Weg zurueckverfolgen: current, dessen Vorgaenger, ... bis blockedId.
        final back = <String>[current];
        var step = current;
        while (step != blockedId) {
          step = cameFrom[step]!;
          back.add(step);
        }
        throw TaskLinkCycleError([blockerId, ...back.reversed, blockerId]);
      }
      if (seen.add(next)) {
        cameFrom[next] = current;
        queue.add(next);
      }
    }
  }
}

/// Die Beziehungen als auswertbare Form — einmal gebaut, oft gefragt.
///
/// Wird je Auswertungszyklus einmal aus Aufgaben und Kanten erzeugt und dann
/// von der Auswahl, der Sortierung und der Oberflaeche befragt. Der Grund
/// fuer die Vorberechnung ist nicht Geschwindigkeit, sondern Einheitlichkeit:
/// „offen" darf nicht an drei Stellen verschieden bedeuten.
@immutable
final class TaskLinkGraph {
  /// Alle gespeicherten Kanten, ungefiltert — fuer Editor und Export.
  final List<TaskLink> all;

  /// blockierte Aufgabe -> ihre **offenen** Blocker.
  final Map<String, List<String>> _blockers;

  /// blockierende Aufgabe -> die **offenen** Aufgaben, die sie direkt aufhaelt.
  final Map<String, List<String>> _blocks;

  /// blockierende Aufgabe -> wie viele offene Aufgaben transitiv freikommen.
  final Map<String, int> _reach;

  const TaskLinkGraph._(this.all, this._blockers, this._blocks, this._reach);

  /// Kein Geflecht. Der Normalfall, und der Grund, warum nichts von dieser
  /// Mechanik sichtbar wird, solange niemand eine Beziehung anlegt.
  static const TaskLinkGraph empty = TaskLinkGraph._(
    <TaskLink>[],
    <String, List<String>>{},
    <String, List<String>>{},
    <String, int>{},
  );

  /// Baut den Graphen aus dem Bestand.
  ///
  /// **Erledigte und verworfene Blocker zaehlen nicht.** Was fertig ist, haelt
  /// nichts mehr auf — und weil das hier gerechnet und nicht gespeichert wird,
  /// gibt der letzte erledigte Blocker die wartende Aufgabe von selbst frei.
  ///
  /// Eine Kante auf eine Aufgabe, die es nicht (mehr) gibt, wird uebergangen
  /// statt abgelehnt: Sie kann niemanden aufhalten, und eine Aufgabe wegen
  /// eines Verweises ins Leere dauerhaft warten zu lassen waere der
  /// schlimmere Fehler [D9].
  factory TaskLinkGraph.from({
    required List<Task> tasks,
    required List<TaskLink> links,
  }) {
    final open = <String>{
      for (final task in tasks)
        if (isTaskOpen(task)) task.id,
    };

    final blockers = <String, List<String>>{};
    final blocks = <String, List<String>>{};
    for (final link in links) {
      if (open.contains(link.blockerId)) {
        (blockers[link.blockedId] ??= <String>[]).add(link.blockerId);
      }
      // Beide Enden muessen offen sein — sonst sagen die zwei Blickrichtungen
      // Verschiedenes ueber dieselbe Kante. Vorher wurde hier nur das
      // blockierte Ende geprueft: `blockersOf` liess die wartende Aufgabe
      // richtig frei, sobald ihr Blocker erledigt war, `blockedBy` und
      // `unblocks` behaupteten aber weiter, die erledigte Aufgabe halte sie
      // auf. Der Hebel einer schon abgehakten Aufgabe ist null.
      if (open.contains(link.blockerId) && open.contains(link.blockedId)) {
        (blocks[link.blockerId] ??= <String>[]).add(link.blockedId);
      }
    }
    for (final list in blockers.values) {
      list.sort();
    }
    for (final list in blocks.values) {
      list.sort();
    }

    // Transitive Reichweite: Was kommt frei, wenn diese Aufgabe fertig ist?
    //
    // Nicht nur die direkt Blockierten — der Hebel einer Aufgabe ist die
    // ganze Kette, die an ihr haengt. Der `seen`-Satz ist zugleich der
    // Schutz gegen einen Kreis in Altdaten: Kreise werden beim Anlegen
    // abgelehnt, ein Import aus einer fremden Datei kann trotzdem einen
    // mitbringen, und ein Absturz bei jeder Auswertung waere dann die
    // teuerste aller Antworten.
    final reach = <String, int>{};
    for (final start in blocks.keys) {
      final seen = <String>{};
      final stack = <String>[...blocks[start]!];
      while (stack.isNotEmpty) {
        final next = stack.removeLast();
        if (next == start) continue;
        if (!seen.add(next)) continue;
        stack.addAll(blocks[next] ?? const <String>[]);
      }
      reach[start] = seen.length;
    }

    return TaskLinkGraph._(
      List.unmodifiable(links),
      blockers,
      blocks,
      reach,
    );
  }

  /// Die **offenen** Blocker dieser Aufgabe. Leer heisst: nichts haelt sie auf.
  List<String> blockersOf(String taskId) =>
      _blockers[taskId] ?? const <String>[];

  /// Die offenen Aufgaben, die **diese** Aufgabe direkt aufhaelt.
  List<String> blockedBy(String taskId) => _blocks[taskId] ?? const <String>[];

  /// Wartet diese Aufgabe auf etwas anderes?
  ///
  /// Kein Zustand in [TaskState], sondern eine Rechnung — deshalb stimmt sie
  /// immer, auch in der Sekunde, in der der letzte Blocker abgehakt wird.
  bool isWaiting(String taskId) => blockersOf(taskId).isNotEmpty;

  /// Wie viele offene Aufgaben werden frei, wenn diese fertig ist — transitiv.
  ///
  /// Das ist die Messung hinter dem Hebel in [taskScore]: kein Geschmack,
  /// sondern eine Zahl, die jeder nachzaehlen kann (G2).
  int unblocks(String taskId) => _reach[taskId] ?? 0;
}
