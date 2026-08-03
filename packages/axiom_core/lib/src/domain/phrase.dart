/// Nutzertext, der noch nicht zusammengesetzt ist.
///
/// **Warum das ueberhaupt existiert.** Der Kern erzeugt Saetze, die der
/// Nutzer liest — „37 min ueber der geplanten Zeit." Steht so ein Satz
/// einmal fertig da, ist er nicht mehr uebersetzbar: Man muesste die Zahl
/// aus dem Text zurueckrechnen, um ihn in einer anderen Sprache neu zu
/// bauen. Deshalb liefert der Kern Quelltext und Werte getrennt.
///
/// Der Kern kennt weiterhin **keine Sprachen**. Er liefert Deutsch und
/// die eingesetzten Werte; welche Sprache daraus wird, entscheidet allein
/// die Oberflaeche. Damit bleibt `evaluate` deterministisch: Die Sprache
/// aendert die Anzeige, nie ein Regelurteil (ADR-0003).
library;

import 'package:meta/meta.dart';

@immutable
final class Phrase {
  /// Deutscher Quelltext mit Platzhaltern `{0}`, `{1}`, …
  final String source;

  /// Werte in der Reihenfolge der Platzhalter.
  final List<Object?> args;

  const Phrase(this.source, [this.args = const []]);

  /// Der fertige deutsche Satz.
  String get text => interpolate(source, args);

  @override
  String toString() => text;

  @override
  bool operator ==(Object other) =>
      other is Phrase &&
      other.source == source &&
      other.args.length == args.length &&
      List.generate(args.length, (i) => args[i] == other.args[i])
          .every((x) => x);

  @override
  int get hashCode => Object.hash(source, Object.hashAll(args));
}

/// Setzt `{0}`, `{1}`, … durch die Werte.
///
/// Platzhalter statt fester Reihenfolge, damit eine Uebersetzung die
/// Wortfolge aendern darf — im Englischen steht die Zahl oft woanders.
String interpolate(String source, List<Object?> args) {
  if (args.isEmpty) return source;
  var result = source;
  for (var i = 0; i < args.length; i++) {
    result = result.replaceAll('{$i}', '${args[i]}');
  }
  return result;
}
