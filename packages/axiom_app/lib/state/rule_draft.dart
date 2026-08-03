/// Der bearbeitbare Zwischenstand einer Regel.
///
/// **Warum ein eigenes Modell und nicht direkt [Condition].** `Condition` ist
/// unveränderlich und vollständig — genau richtig für die Engine, unbrauchbar
/// beim Tippen. Halbfertige Zustände gehören dazu: eine Bedingung ohne
/// gewählte Variable, eine Gruppe mit einem Kind, ein Wert, der gerade
/// gelöscht wird. Ein Editor, der nur gültige Zwischenstände zulässt, zwingt
/// dazu, den Endzustand vorher zu kennen — und das ist genau die kognitive
/// Last, die hier wegsoll (G1).
///
/// Der Entwurf kennt deshalb zwei Richtungen: aus einer geladenen Regel
/// aufbauen, und in eine gültige Regel zurückrechnen. Das Zurückrechnen darf
/// scheitern; dann sagt der Editor, was fehlt.
library;

import 'package:axiom_core/axiom_core.dart';

/// Welche Art von Bedingung ein Blatt beschreibt.
enum LeafKind {
  /// `capacity: { lt: 40 }`
  number('Zahl'),

  /// `load_level: { eq: L3 }`
  choice('Auswahl'),

  /// `time_between: ["22:00", "05:00"]`
  timeRange('Uhrzeit'),

  /// `minutes_since: { event: checkin, gte: 240 }`
  minutesSince('Seit einem Ereignis'),

  /// `count_today: { event: checkin, lt: 3 }`
  countToday('Anzahl heute');

  const LeafKind(this.label);
  final String label;
}

sealed class DraftNode {
  /// Die Bedingung, die dieser Knoten beschreibt.
  /// Wirft [ConditionError], wenn der Entwurf noch unvollständig ist.
  Condition build();

  DraftNode copy();
}

/// Eine Verzweigung: alle Kinder, oder eines von ihnen.
final class DraftGroup extends DraftNode {
  /// `true` = *eine von* (`any`), `false` = *alle* (`all`).
  bool any;

  /// Kehrt die ganze Gruppe um.
  bool negated;

  final List<DraftNode> children;

  DraftGroup({this.any = false, this.negated = false, List<DraftNode>? children})
      : children = children ?? [];

  @override
  Condition build() {
    if (children.isEmpty) {
      throw ConditionError('Eine Gruppe braucht mindestens eine Bedingung.');
    }
    final built = children.map((c) => c.build()).toList();
    // Eine Gruppe mit einem Kind ist im YAML unnoetig — der Editor haelt sie
    // trotzdem, damit "eine zweite hinzufuegen" ein Tipp bleibt.
    final inner = built.length == 1
        ? built.single
        : (any ? AnyOf(built) : AllOf(built));
    return negated ? NotCond(inner) : inner;
  }

  @override
  DraftGroup copy() => DraftGroup(
        any: any,
        negated: negated,
        children: children.map((c) => c.copy()).toList(),
      );
}

/// Eine einzelne Bedingung.
final class DraftLeaf extends DraftNode {
  LeafKind kind;
  bool negated;

  /// Für [LeafKind.number] und [LeafKind.choice].
  String variable;

  /// Für [LeafKind.minutesSince] und [LeafKind.countToday].
  String event;

  CompareOp op;
  num number;
  String symbol;
  int fromMinutes;
  int toMinutes;

  DraftLeaf({
    this.kind = LeafKind.number,
    this.negated = false,
    this.variable = 'capacity',
    this.event = 'checkin',
    this.op = CompareOp.lt,
    this.number = 40,
    this.symbol = 'L2',
    this.fromMinutes = 22 * 60,
    this.toMinutes = 5 * 60,
  });

  @override
  Condition build() {
    final inner = switch (kind) {
      LeafKind.number => NumericCompare(variable, op, number),
      LeafKind.choice => SymbolicCompare(variable, op, symbol),
      LeafKind.timeRange => TimeBetween(fromMinutes, toMinutes),
      LeafKind.minutesSince => MinutesSince(event, op, number.toInt()),
      LeafKind.countToday => CountToday(event, op, number.toInt()),
    };
    return negated ? NotCond(inner) : inner;
  }

  /// Wechselt die Art und setzt dabei sinnvolle Voreinstellungen.
  ///
  /// Ohne das steht nach einem Wechsel ein Operator da, den die neue Art
  /// nicht kennt — und die Regel liesse sich erst nach einem weiteren,
  /// unerklaerten Schritt speichern.
  void switchTo(LeafKind next) {
    kind = next;
    switch (next) {
      case LeafKind.number:
        variable = RuleVocabulary.numerics.first.id;
        op = CompareOp.lt;
        number = 40;
      case LeafKind.choice:
        final first = RuleVocabulary.symbolics.first;
        variable = first.id;
        symbol = first.values.keys.first;
        op = CompareOp.eq;
      case LeafKind.timeRange:
        break;
      case LeafKind.minutesSince:
        event = RuleVocabulary.events.first.id;
        op = CompareOp.gte;
        number = 120;
      case LeafKind.countToday:
        event = RuleVocabulary.events.first.id;
        op = CompareOp.lt;
        number = 1;
    }
  }

  @override
  DraftLeaf copy() => DraftLeaf(
        kind: kind,
        negated: negated,
        variable: variable,
        event: event,
        op: op,
        number: number,
        symbol: symbol,
        fromMinutes: fromMinutes,
        toMinutes: toMinutes,
      );
}

/// Baut den Entwurf aus einer geladenen Bedingung.
///
/// Verschachtelte `not`-Knoten werden dabei auf das Kind gelegt, statt eine
/// eigene Ebene zu bekommen: „nicht" ist im Editor ein Schalter an der
/// Bedingung, keine dritte Sorte Knoten. Eine Ebene weniger im Baum ist eine
/// Entscheidung weniger beim Lesen.
DraftNode draftFrom(Condition condition, {bool negated = false}) =>
    switch (condition) {
      NotCond(:final child) => draftFrom(child, negated: !negated),
      AllOf(:final children) => DraftGroup(
          any: false,
          negated: negated,
          children: children.map((c) => draftFrom(c)).toList(),
        ),
      AnyOf(:final children) => DraftGroup(
          any: true,
          negated: negated,
          children: children.map((c) => draftFrom(c)).toList(),
        ),
      NumericCompare(:final variable, :final op, :final value) => DraftLeaf(
          kind: LeafKind.number,
          negated: negated,
          variable: variable,
          op: op,
          number: value,
        ),
      SymbolicCompare(:final variable, :final op, :final value) => DraftLeaf(
          kind: LeafKind.choice,
          negated: negated,
          variable: variable,
          op: op,
          symbol: value,
        ),
      TimeBetween(:final fromMinutes, :final toMinutes) => DraftLeaf(
          kind: LeafKind.timeRange,
          negated: negated,
          fromMinutes: fromMinutes,
          toMinutes: toMinutes,
        ),
      MinutesSince(:final eventType, :final op, :final minutes) => DraftLeaf(
          kind: LeafKind.minutesSince,
          negated: negated,
          event: eventType,
          op: op,
          number: minutes,
        ),
      CountToday(:final eventType, :final op, :final count) => DraftLeaf(
          kind: LeafKind.countToday,
          negated: negated,
          event: eventType,
          op: op,
          number: count,
        ),
    };

/// Der Wurzelknoten ist immer eine Gruppe.
///
/// Auch bei einer einzelnen Bedingung: So ist „eine zweite hinzufügen" ein
/// Tipp und kein Umbau.
DraftGroup rootDraft(Condition condition) {
  final node = draftFrom(condition);
  return node is DraftGroup ? node : DraftGroup(children: [node]);
}
