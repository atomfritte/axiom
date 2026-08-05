/// Append-only Ereignis. Die einzige Quelle der Wahrheit.
///
/// Events werden nie geaendert und nie geloescht. Eine Korrektur ist ein neues
/// Event mit `correctionOf`. Das ist die Voraussetzung dafuer, dass Regeln
/// rueckwirkend gegen historische Zustaende ausgewertet werden koennen
/// (siehe ADR-0002) — ohne das waere das Regelwerk nicht empirisch
/// verbesserbar, sondern nur gefuehlt.
library;

import 'package:meta/meta.dart';

/// Wer hat das Event erzeugt.
enum EventSource { user, timer, health, device, rule, system, import }

/// Registrierte Event-Typen. Ein unbekannter Typ wird abgelehnt, nicht
/// ignoriert (Fail-Fast) — siehe CLAUDE.md.
enum EventType {
  // M1 Capture
  capture,

  // M0 State Engine
  checkin,
  decisionEmitted,
  decisionFeedback,

  // M2 Task Kernel
  taskCreated,
  taskStarted,
  taskCompleted,
  taskAbandoned,
  taskSplit,

  /// „A blockiert B" wurde angelegt. Payload: `blocker_id`, `blocked_id`.
  ///
  /// Append-only wie alles: Eine Beziehung ist ein Ereignis, kein Feld, das
  /// ueberschrieben wird. Ohne diese beiden Typen ueberlebte eine Beziehung
  /// keinen Wiederaufbau der Projektionen — und genau das ist die Zusage,
  /// die dieses System traegt (docs/03-DATENMODELL.md §6).
  taskLinked,

  /// Die Beziehung wurde wieder geloest. Gleiche Payload.
  taskUnlinked,

  /// Ortswechsel. `payload['place']` traegt den Namen; fehlt er oder ist er
  /// leer, heisst das „kein Ort mehr gesetzt".
  ///
  /// Der aktuelle Ort ist damit ein abgeleiteter Zustand und kein Feld, das
  /// ueberschrieben wird — wie alles hier. Quelle ist entweder der Nutzer
  /// (`EventSource.user`) oder eine Geraeteroutine (`EventSource.device`),
  /// und im Ereignisstrom bleibt unterscheidbar, welches von beidem.
  placeEntered,

  // M4 Focus Governor
  focusStart,
  focusEnd,

  // M5 Sensation Budget
  sensationSlot,

  // M6 Impulse Interceptor
  impulseIntercepted,

  // M7 Body Loop
  bodyPrompt,
  healthSample,

  // M8 Sleep Gate
  sleepWindow,

  // M10 Signal Log
  signalIncident,
  signalPostmortem,

  // M11 Review Cadence
  reviewCompleted,

  // M12 Meta-Guard
  metaUsage,

  // M13 Med Window (opt-in, Default aus)
  medIntake,
}

@immutable
final class Event {
  /// ULID — zeitsortierbar und offline kollisionsfrei.
  final String id;

  /// Immer UTC. Erzeugt ueber den Clock-Port, nie ueber DateTime.now().
  final DateTime at;

  final EventType type;
  final EventSource source;

  /// Typspezifisch, streng JSON-serialisierbar.
  final Map<String, Object?> payload;

  /// Verweis auf ein korrigiertes Event. Korrektur statt Mutation.
  final String? correctionOf;

  Event({
    required this.id,
    required DateTime at,
    required this.type,
    required this.source,
    this.payload = const {},
    this.correctionOf,
  })  : at = at.toUtc(),
        assert(at.isUtc || true, 'Zeitstempel werden intern auf UTC normalisiert');

  Map<String, Object?> toJson() => {
        'id': id,
        'at': at.toIso8601String(),
        'type': type.name,
        'source': source.name,
        'payload': payload,
        if (correctionOf != null) 'correction_of': correctionOf,
      };

  /// Wirft [FormatException] bei unbekanntem Typ — bewusst Fail-Fast.
  /// Ein stillschweigend uebersprungenes Event wuerde den StateVector
  /// unbemerkt verfaelschen.
  static Event fromJson(Map<String, Object?> json) {
    final typeName = json['type'] as String?;
    final type = EventType.values.where((e) => e.name == typeName).firstOrNull;
    if (type == null) {
      throw FormatException('Unbekannter EventType: $typeName');
    }
    final sourceName = json['source'] as String?;
    final source =
        EventSource.values.where((e) => e.name == sourceName).firstOrNull;
    if (source == null) {
      throw FormatException('Unbekannte EventSource: $sourceName');
    }
    return Event(
      id: json['id']! as String,
      at: DateTime.parse(json['at']! as String),
      type: type,
      source: source,
      payload: (json['payload'] as Map?)?.cast<String, Object?>() ?? const {},
      correctionOf: json['correction_of'] as String?,
    );
  }

  @override
  String toString() => 'Event(${type.name} @ ${at.toIso8601String()})';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
