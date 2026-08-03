/// Entscheidung — die einzige Ausgabeform von AXIOM.
///
/// Immer genau eine Handlung, immer mit rule_id und Begruendung (G1 + G2).
/// Jede Entscheidung wird protokolliert; das Log ist die Grundlage der
/// Regelqualitaets-Metriken im Wochenreview.
library;

import 'package:meta/meta.dart';

import 'rule.dart';

/// Reaktion des Nutzers. Speist die Regelqualitaet — ohne dieses Feedback
/// laesst sich nicht messen, ob eine Regel hilft oder nur nervt.
enum DecisionResponse { followed, deferred, rejected }

@immutable
final class Decision {
  final String id;
  final DateTime at;
  final String ruleId;
  final Action action;

  /// Menschenlesbar, erzeugt aus rule.rationale + konkreten Zustandswerten.
  final String explanation;

  final String stateSnapshotId;

  /// True, wenn die Regel gefeuert hat, aber von einer hoeherrangigen
  /// verdraengt wurde. Nicht verworfen, sondern protokolliert: chronisch
  /// unterdrueckte Regeln sind ein starkes Signal fuer einen Regelkonflikt,
  /// den man sonst nie bemerkt.
  final bool suppressed;

  final DecisionResponse? response;

  const Decision({
    required this.id,
    required this.at,
    required this.ruleId,
    required this.action,
    required this.explanation,
    required this.stateSnapshotId,
    this.suppressed = false,
    this.response,
  });

  Decision copyWith({DecisionResponse? response, bool? suppressed}) => Decision(
        id: id,
        at: at,
        ruleId: ruleId,
        action: action,
        explanation: explanation,
        stateSnapshotId: stateSnapshotId,
        suppressed: suppressed ?? this.suppressed,
        response: response ?? this.response,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'at': at.toIso8601String(),
        'rule_id': ruleId,
        'action': action.type.token,
        'explanation': explanation,
        'state_snapshot_id': stateSnapshotId,
        'suppressed': suppressed,
        'response': response?.name,
      };

  @override
  String toString() =>
      'Decision($ruleId -> ${action.type.token}${suppressed ? " [suppressed]" : ""})';
}
