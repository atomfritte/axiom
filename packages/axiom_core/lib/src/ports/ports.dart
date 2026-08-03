/// Ports — der Core definiert, die Infrastruktur implementiert.
///
/// Abhaengigkeiten zeigen immer nach innen. `axiom_core` kennt weder
/// `axiom_data` noch `axiom_app`. Tests nutzen In-Memory-Fakes.
library;

import '../domain/decision.dart';
import '../domain/event.dart';
import '../domain/rule.dart';

/// JEDE Zeitabfrage laeuft hierueber.
///
/// Nicht optional: ohne injizierte Zeit sind zeitabhaengige Regeln — also
/// fast alle — nicht deterministisch testbar, und Determinismus ist die
/// Grundlage von G2. Ein direkter `DateTime.now()`-Aufruf im Core ist ein
/// CI-Fehler.
abstract interface class Clock {
  /// Aktuelle Zeit in UTC.
  DateTime nowUtc();

  /// Aktuelle Zeit in lokaler Zone. Regeln denken in Ortszeit.
  DateTime nowLocal();
}

/// Systemzeit. Die einzige Stelle im Projekt, die `DateTime.now()` aufrufen darf.
final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();

  @override
  DateTime nowLocal() => DateTime.now();
}

/// Fixierte Zeit fuer Tests und Golden-Szenarien.
final class FakeClock implements Clock {
  DateTime _local;
  FakeClock(this._local);

  @override
  DateTime nowUtc() => _local.toUtc();

  @override
  DateTime nowLocal() => _local;

  void advance(Duration d) => _local = _local.add(d);
  void set(DateTime local) => _local = local;
}

/// Zufall — ebenfalls injiziert, damit Szenarien reproduzierbar bleiben.
/// Wird derzeit nirgends in der Entscheidungsschleife verwendet (ADR-0003)
/// und existiert nur, damit ein spaeterer Bedarf nicht zu einem direkten
/// `Random()`-Aufruf verleitet.
abstract interface class Rng {
  int nextInt(int max);
}

/// Append-only Ereignisspeicher.
abstract interface class EventStore {
  /// Haengt an. Nie UPDATE, nie DELETE.
  Future<void> append(Event event);

  /// Events im Zeitfenster [from, to), optional nach Typ gefiltert.
  Future<List<Event>> query({
    DateTime? from,
    DateTime? to,
    Set<EventType>? types,
  });

  /// Letztes Event eines Typs, oder null.
  Future<Event?> last(EventType type);

  /// Anzahl Events eines Typs seit lokalem Tagesbeginn.
  Future<int> countSince(EventType type, DateTime since);
}

/// Laedt und validiert das Regelwerk aus `rules/`.
abstract interface class RuleSource {
  /// Wirft bei ungueltigem Regelwerk. Eine ungueltige Regel wird NICHT
  /// geladen und die App startet mit sichtbarem Fehler — kein stilles
  /// Ueberspringen. In einem regelbasierten System ist eine stumm ignorierte
  /// Regel schlimmer als ein Absturz.
  Future<List<Rule>> load();
}

/// Historie fuer Cooldown-Pruefung und Backoff.
abstract interface class DecisionHistory {
  /// Zeitpunkt der letzten nicht unterdrueckten Feuerung.
  DateTime? lastFired(String ruleId);

  /// Feuerungen seit lokalem Tagesbeginn.
  int firedToday(String ruleId);

  /// Ablehnungen in Folge — Grundlage des exponentiellen Backoff.
  int consecutiveRejections(String ruleId);

  /// Feuerungen aller Regeln seit lokalem Tagesbeginn (globales Limit).
  int totalInterventionsToday();
}

/// Spielt Interventionen aus. Implementierung in `axiom_app`.
abstract interface class InterventionNotifier {
  Future<void> emit(Decision decision, Severity severity);
}
