/// Bedingungsbaum der Regel-DSL.
///
/// Wird aus YAML geparst (docs/04-REGELWERK.md §2) und deterministisch
/// ausgewertet. Kein Zufall, keine Uhrzeit-Abfrage im Baum selbst — alles
/// kommt aus dem [EvalContext], damit Regeln mit einem FakeClock testbar sind.
library;

import 'package:meta/meta.dart';

/// Alles, was eine Bedingung zur Auswertung braucht.
/// Die Implementierung liefert die Werte; der Baum kennt keine Quellen.
abstract interface class EvalContext {
  /// Numerische Zustandsvariable (capacity, load_index, ...).
  /// Null bei unbekanntem Namen — fuehrt zu [ConditionError].
  num? numeric(String variable);

  /// Enum-artige Variable (load_level, active_slot, weekday).
  String? symbolic(String variable);

  /// Lokale Zeit (nicht UTC) — Regeln denken in Ortszeit.
  DateTime get localNow;

  /// Minuten seit dem letzten Event dieses Typs. Null, wenn nie eingetreten.
  int? minutesSince(String eventType);

  /// Anzahl Events dieses Typs seit lokalem Tagesbeginn.
  int countToday(String eventType);

  /// Konfidenz einer Dimension (0..1). Bei Datenluecken sinkt sie. (R8)
  double confidenceOf(String variable);
}

/// Regelwerk-Fehler. Fail-Fast: eine Bedingung, die nicht ausgewertet werden
/// kann, darf nicht still `false` liefern — man wuerde sich sonst auf eine
/// Regel verlassen, die es faktisch nicht gibt.
final class ConditionError extends Error {
  final String message;
  ConditionError(this.message);
  @override
  String toString() => 'ConditionError: $message';
}

enum CompareOp {
  eq('eq'),
  ne('ne'),
  lt('lt'),
  lte('lte'),
  gt('gt'),
  gte('gte');

  const CompareOp(this.token);
  final String token;

  static CompareOp parse(String token) => CompareOp.values.firstWhere(
        (o) => o.token == token,
        orElse: () => throw ConditionError('Unbekannter Operator: $token'),
      );

  bool apply(num left, num right) => switch (this) {
        CompareOp.eq => left == right,
        CompareOp.ne => left != right,
        CompareOp.lt => left < right,
        CompareOp.lte => left <= right,
        CompareOp.gt => left > right,
        CompareOp.gte => left >= right,
      };
}

@immutable
sealed class Condition {
  const Condition();

  bool eval(EvalContext ctx);

  /// Alle Variablennamen, die dieser Baum liest. Fuer den statischen
  /// Validator (unbekannte Variablen, Widerspruchspruefung).
  Set<String> get referencedVariables;

  /// Umkehrung von [Condition.fromMap].
  ///
  /// Noetig, damit eine im Editor geaenderte Regel wieder als YAML
  /// herauskommt — in genau der Form, die der Parser wieder einliest.
  /// `fromMap(toMap())` muss dieselbe Bedingung ergeben; ein Test haelt das
  /// fest. Ohne diese Garantie waere jede Bearbeitung ein Einbahnweg aus dem
  /// versionierten Regelwerk heraus.
  Map<String, Object?> toMap();

  /// Parst einen Knoten der Regel-DSL.
  ///
  /// Erlaubte Formen:
  ///   { all: [ ... ] }
  ///   { any: [ ... ] }
  ///   { not: { ... } }
  ///   { time_between: ["07:00", "21:00"] }
  ///   { minutes_since: { event: focus_start, gte: 90 } }
  ///   { count_today: { event: body_prompt, lt: 3 } }
  ///   { capacity: { gte: 30 } }              numerisch
  ///   { load_level: { eq: L3 } }             symbolisch
  factory Condition.fromMap(Map<Object?, Object?> map) {
    if (map.length != 1) {
      throw ConditionError(
        'Bedingungsknoten braucht genau einen Schluessel, hat ${map.length}: '
        '${map.keys.join(", ")}',
      );
    }
    final key = map.keys.first as String;
    final value = map.values.first;

    switch (key) {
      case 'all':
        return AllOf(_parseList(value, key));
      case 'any':
        return AnyOf(_parseList(value, key));
      case 'not':
        if (value is! Map) {
          throw ConditionError('"not" erwartet eine Map, hat ${value.runtimeType}');
        }
        return NotCond(Condition.fromMap(value));
      case 'time_between':
        if (value is! List || value.length != 2) {
          throw ConditionError('"time_between" erwartet ["HH:MM", "HH:MM"]');
        }
        return TimeBetween(
          _parseHhMm(value[0] as String),
          _parseHhMm(value[1] as String),
        );
      case 'minutes_since':
      case 'count_today':
        if (value is! Map) {
          throw ConditionError('"$key" erwartet eine Map mit event + Operator');
        }
        final event = value['event'] as String?;
        if (event == null) {
          throw ConditionError('"$key" braucht das Feld "event"');
        }
        final (op, operand) = _singleOp(value, exclude: 'event', context: key);
        return key == 'minutes_since'
            ? MinutesSince(event, op, operand.toInt())
            : CountToday(event, op, operand.toInt());
      default:
        // Variablenvergleich: numerisch oder symbolisch.
        if (value is! Map) {
          throw ConditionError(
            'Variable "$key" erwartet { <op>: <wert> }, hat ${value.runtimeType}',
          );
        }
        final entry = _singleEntry(value, context: key);
        final op = CompareOp.parse(entry.key as String);
        final operand = entry.value;
        if (operand is num) return NumericCompare(key, op, operand);
        if (operand is String) {
          if (op != CompareOp.eq && op != CompareOp.ne) {
            throw ConditionError(
              'Symbolischer Vergleich "$key" erlaubt nur eq/ne, hat ${op.token}',
            );
          }
          return SymbolicCompare(key, op, operand);
        }
        throw ConditionError(
          'Vergleichswert fuer "$key" muss Zahl oder String sein',
        );
    }
  }

  static List<Condition> _parseList(Object? value, String key) {
    if (value is! List) {
      throw ConditionError('"$key" erwartet eine Liste');
    }
    if (value.isEmpty) {
      throw ConditionError('"$key" darf nicht leer sein');
    }
    return value
        .map((e) => Condition.fromMap(e as Map<Object?, Object?>))
        .toList(growable: false);
  }

  static MapEntry<Object?, Object?> _singleEntry(
    Map<Object?, Object?> map, {
    required String context,
  }) {
    if (map.length != 1) {
      throw ConditionError(
        '"$context" erwartet genau einen Operator, hat ${map.length}',
      );
    }
    return map.entries.first;
  }

  static (CompareOp, num) _singleOp(
    Map<Object?, Object?> map, {
    required String exclude,
    required String context,
  }) {
    final rest = Map<Object?, Object?>.from(map)..remove(exclude);
    final entry = _singleEntry(rest, context: context);
    final operand = entry.value;
    if (operand is! num) {
      throw ConditionError('"$context" erwartet einen numerischen Wert');
    }
    return (CompareOp.parse(entry.key as String), operand);
  }

  static int _parseHhMm(String s) {
    final parts = s.split(':');
    if (parts.length != 2) throw ConditionError('Ungueltige Zeit: $s');
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      throw ConditionError('Ungueltige Zeit: $s');
    }
    return h * 60 + m;
  }
}

final class AllOf extends Condition {
  final List<Condition> children;
  const AllOf(this.children);

  @override
  bool eval(EvalContext ctx) => children.every((c) => c.eval(ctx));

  @override
  Set<String> get referencedVariables =>
      children.expand((c) => c.referencedVariables).toSet();

  @override
  Map<String, Object?> toMap() =>
      {'all': children.map((c) => c.toMap()).toList()};
}

final class AnyOf extends Condition {
  final List<Condition> children;
  const AnyOf(this.children);

  @override
  bool eval(EvalContext ctx) => children.any((c) => c.eval(ctx));

  @override
  Set<String> get referencedVariables =>
      children.expand((c) => c.referencedVariables).toSet();

  @override
  Map<String, Object?> toMap() =>
      {'any': children.map((c) => c.toMap()).toList()};
}

final class NotCond extends Condition {
  final Condition child;
  const NotCond(this.child);

  @override
  bool eval(EvalContext ctx) => !child.eval(ctx);

  @override
  Set<String> get referencedVariables => child.referencedVariables;

  @override
  Map<String, Object?> toMap() => {'not': child.toMap()};
}

final class NumericCompare extends Condition {
  final String variable;
  final CompareOp op;
  final num value;
  const NumericCompare(this.variable, this.op, this.value);

  @override
  bool eval(EvalContext ctx) {
    final actual = ctx.numeric(variable);
    if (actual == null) {
      throw ConditionError('Unbekannte numerische Variable: $variable');
    }
    return op.apply(actual, value);
  }

  @override
  Set<String> get referencedVariables => {variable};

  @override
  Map<String, Object?> toMap() => {
        variable: {op.token: value},
      };

  @override
  String toString() => '$variable ${op.token} $value';
}

final class SymbolicCompare extends Condition {
  final String variable;
  final CompareOp op;
  final String value;
  const SymbolicCompare(this.variable, this.op, this.value);

  @override
  bool eval(EvalContext ctx) {
    final actual = ctx.symbolic(variable);
    if (actual == null) {
      throw ConditionError('Unbekannte symbolische Variable: $variable');
    }
    final equal = actual.toLowerCase() == value.toLowerCase();
    return op == CompareOp.eq ? equal : !equal;
  }

  @override
  Set<String> get referencedVariables => {variable};

  @override
  Map<String, Object?> toMap() => {
        variable: {op.token: value},
      };

  @override
  String toString() => '$variable ${op.token} $value';
}

/// Lokale Uhrzeit im Intervall. Ueber Mitternacht hinweg gueltig
/// (z. B. 22:00–05:00 fuer die Nacht-Kaskade, D8).
final class TimeBetween extends Condition {
  final int fromMinutes;
  final int toMinutes;
  const TimeBetween(this.fromMinutes, this.toMinutes);

  @override
  bool eval(EvalContext ctx) {
    final now = ctx.localNow;
    final m = now.hour * 60 + now.minute;
    return fromMinutes <= toMinutes
        ? m >= fromMinutes && m <= toMinutes
        : m >= fromMinutes || m <= toMinutes;
  }

  @override
  Set<String> get referencedVariables => const {'time_between'};

  @override
  Map<String, Object?> toMap() => {
        'time_between': [_fmt(fromMinutes), _fmt(toMinutes)],
      };

  @override
  String toString() =>
      'time_between(${_fmt(fromMinutes)}, ${_fmt(toMinutes)})';

  static String _fmt(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:'
      '${(m % 60).toString().padLeft(2, '0')}';
}

/// Minuten seit dem letzten Ereignis dieses Typs.
///
/// **Achtung, haeufige Fehlerquelle:** Ein nie eingetretenes Ereignis gilt
/// als "unendlich lange her". Das ist richtig fuer Bedingungen der Form
/// *"seit X nichts getrunken"* — wer noch nie getrunken hat, hat erst recht
/// lange nicht getrunken.
///
/// Es ist **falsch** fuer Bedingungen der Form *"laeuft seit X"*. Eine Regel
/// wie `minutes_since(focus_start) >= 90` bedeutet nicht "der Fokus laeuft
/// seit 90 Minuten", sondern "der letzte Fokus begann vor mindestens 90
/// Minuten oder es gab nie einen". Wer das meint, muss zusaetzlich pruefen,
/// dass ueberhaupt etwas laeuft:
///
///     all:
///       - active_slot: { eq: focus }
///       - minutes_since: { event: focus_start, gte: 90 }
final class MinutesSince extends Condition {
  final String eventType;
  final CompareOp op;
  final int minutes;
  const MinutesSince(this.eventType, this.op, this.minutes);

  @override
  bool eval(EvalContext ctx) {
    final since = ctx.minutesSince(eventType);
    if (since == null) {
      return op == CompareOp.gt || op == CompareOp.gte || op == CompareOp.ne;
    }
    return op.apply(since, minutes);
  }

  @override
  Set<String> get referencedVariables => {'event:$eventType'};

  @override
  Map<String, Object?> toMap() => {
        'minutes_since': {'event': eventType, op.token: minutes},
      };

  @override
  String toString() => 'minutes_since($eventType) ${op.token} $minutes';
}

final class CountToday extends Condition {
  final String eventType;
  final CompareOp op;
  final int count;
  const CountToday(this.eventType, this.op, this.count);

  @override
  bool eval(EvalContext ctx) => op.apply(ctx.countToday(eventType), count);

  @override
  Set<String> get referencedVariables => {'event:$eventType'};

  @override
  Map<String, Object?> toMap() => {
        'count_today': {'event': eventType, op.token: count},
      };

  @override
  String toString() => 'count_today($eventType) ${op.token} $count';
}
