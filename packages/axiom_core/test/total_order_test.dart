/// Wo eine Reihenfolge sichtbar wird, muss sie total sein.
///
/// **Warum das kein Feinschliff ist.** G1 sagt: Die Ausgabe ist genau *eine*
/// Handlung. Damit entscheidet die Sortierung allein, was der Nutzer sieht —
/// alles hinter Platz eins existiert fuer ihn nicht. G2 sagt: Dieselbe
/// Eingabe ergibt dieselbe Ausgabe (ADR-0003). Beides zusammen heisst: Zwei
/// gleichwertige Kandidaten duerfen nicht nach Zufall geordnet werden.
///
/// „Zufall" ist hier woertlich zu nehmen. `List.sort` ist in Dart **nicht
/// stabil**: Ab 32 Elementen laeuft ein Introsort, der gleichrangige
/// Elemente umordnet. Der Bestand kommt aus SQLite (`ORDER BY created_at`),
/// und zwei in derselben Millisekunde angelegte Aufgaben — beim Zerlegen der
/// Normalfall — haben dort keine definierte Reihenfolge. Die Vergleichs-
/// funktion ist die einzige Stelle, an der sich das festhalten laesst.
///
/// Jeder Test hier vergleicht deshalb dieselbe Menge in zwei Eingabe-
/// reihenfolgen. Kommt zweimal dasselbe heraus, ist die Ordnung total.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

final DateTime _noon = DateTime(2026, 8, 3, 12);

/// Genug Elemente, dass Dart nicht mehr per Insertionsort sortiert. Mit
/// weniger als 32 waere der Test gruen, ohne dass die Ordnung total ist.
const int _enoughToShuffle = 40;

Task _task(
  String id, {
  int ae = 2,
  int salience = 5,
  int stakes = 5,
  DateTime? decayAt,
  TaskState state = TaskState.ready,
  Duration? estimate,
}) =>
    Task(
      id: id,
      title: 'Aufgabe $id',
      activationEnergy: ae,
      salience: salience,
      stakes: stakes,
      decayAt: decayAt,
      estimate: estimate,
      state: state,
    );

String _id(int i) => 't${i.toString().padLeft(2, '0')}';

void main() {
  group('Die knappste Frist ist eindeutig, auch bei Gleichstand', () {
    test('zwei Aufgaben mit gleichem Rest ergeben dieselbe Antwort', () {
      // Zwei Aufgaben, identische Frist, identischer Anlauf: Der Rest ist
      // derselbe. Ohne Entscheidungsregel gewinnt die, die zufaellig vorn
      // stand — und auf dem Zustandsschirm steht dann mal der eine, mal der
      // andere Titel, bei unveraendertem Bestand.
      final tasks = [
        for (var i = 0; i < _enoughToShuffle; i++)
          _task(_id(i), decayAt: _noon.add(const Duration(hours: 5))),
      ];

      final vorwaerts = tightestDeadline(tasks, _noon)!.task.id;
      final rueckwaerts =
          tightestDeadline(tasks.reversed.toList(), _noon)!.task.id;

      expect(vorwaerts, rueckwaerts);
    });

    test('bei ungleichem Rest entscheidet weiter der Rest, nicht die Kennung',
        () {
      // Die Entscheidungsregel darf nur Gleichstaende aufloesen. Waere sie
      // staerker, entschiede die Kennung ueber die Dringlichkeit.
      final knapp = _task('zzz',
          decayAt: _noon.add(const Duration(hours: 2)), ae: 4);
      final locker = _task('aaa',
          decayAt: _noon.add(const Duration(hours: 40)), ae: 1);

      expect(tightestDeadline([knapp, locker], _noon)!.task.id, 'zzz');
      expect(tightestDeadline([locker, knapp], _noon)!.task.id, 'zzz');
    });
  });

  group('Der Zerlegungsvorschlag ist eindeutig', () {
    test('gleicher Grund und gleiche Konsequenz ergeben dieselbe Reihenfolge',
        () {
      // Die Oberflaeche zeigt genau den ersten Kandidaten (G1). Welcher das
      // ist, darf nicht davon abhaengen, in welcher Reihenfolge die Aufgaben
      // aus der Datenbank kommen.
      const atomizer = Atomizer();
      final tasks = [
        for (var i = 0; i < _enoughToShuffle; i++) _task(_id(i), ae: 9),
      ];

      List<String> ids(List<Task> input) => atomizer
          .candidates(
              tasks: input, capacity: 60, now: _noon, createdAt: const {})
          .map((c) => c.task.id)
          .toList();

      expect(ids(tasks), ids(tasks.reversed.toList()));
    });

    test('der Grund schlaegt weiterhin die Konsequenz und beide die Kennung',
        () {
      const atomizer = Atomizer();
      // „aussser Reichweite" (Index 3) gegen „von sich aus schwer" (Index 2):
      // Der Grund entscheidet, obwohl die Kennung anders sortieren wuerde.
      final schwer = _task('zzz', ae: 8, stakes: 3);
      final ausserReichweite = _task('aaa', ae: 7, stakes: 3);

      final result = atomizer.candidates(
        tasks: [ausserReichweite, schwer],
        capacity: 60,
        now: _noon,
        createdAt: const {},
      );
      expect(result.first.reason, AtomizeReason.inherentlyHeavy);
      expect(result.first.task.id, 'zzz');
    });
  });

  group('Der Reiz-Vorschlag ist eindeutig', () {
    test('zwei gleich passende Kanaele ergeben denselben Vorschlag', () {
      // Der Kommentar an `suggest` sagt zu: „Deterministisch, damit die
      // Empfehlung erklaerbar bleibt (G2)". Bei gleicher Intensitaet und
      // gleicher Dauer war das bisher die Reihenfolge der Kanalliste.
      const ledger = SensationLedger();
      final channels = [
        for (var i = 0; i < _enoughToShuffle; i++)
          SensationChannel(
            id: 'c${i.toString().padLeft(2, '0')}',
            label: 'Kanal $i',
            intensity: 3,
            typical: const Duration(minutes: 20),
          ),
      ];

      final vorwaerts = ledger.suggest(
        sensationNeed: 55,
        channels: channels,
        available: const Duration(minutes: 60),
      );
      final rueckwaerts = ledger.suggest(
        sensationNeed: 55,
        channels: channels.reversed.toList(),
        available: const Duration(minutes: 60),
      );

      expect(vorwaerts!.id, rueckwaerts!.id);
    });

    test('Passung schlaegt Dauer und beide die Kennung', () {
      const ledger = SensationLedger();
      const channels = [
        // Kennung vorn, Passung schlecht.
        SensationChannel(
            id: 'aaa', label: 'A', intensity: 2, typical: Duration(minutes: 5)),
        // Kennung hinten, Passung genau.
        SensationChannel(
            id: 'zzz', label: 'Z', intensity: 5, typical: Duration(minutes: 45)),
      ];
      expect(
        ledger
            .suggest(
              sensationNeed: 90,
              channels: channels,
              available: const Duration(minutes: 60),
            )!
            .id,
        'zzz',
      );
    });
  });

  group('Die Nachbetrachtung wird in fester Reihenfolge angeboten', () {
    test('gleiche Staerke und gleiche Zeit ergeben dieselbe Reihenfolge', () {
      // Auch hier zeigt die Oberflaeche nur den ersten Vorfall. Zwei
      // Vorfaelle derselben Minute sind keine Seltenheit — ein Streit
      // erzeugt selten genau einen Eintrag.
      const log = SignalLog();
      final at = _noon.subtract(const Duration(hours: 20));
      final incidents = [
        for (var i = 0; i < _enoughToShuffle; i++)
          SignalIncident(
            id: 'i${i.toString().padLeft(2, '0')}',
            at: at,
            intensity: 3,
            triggerClass: TriggerClass.unclear,
          ),
      ];

      List<String> ids(List<SignalIncident> input) => log
          .awaitingPostMortem(
              incidents: input, reviewedIds: const {}, now: _noon)
          .map((i) => i.id)
          .toList();

      expect(ids(incidents), ids(incidents.reversed.toList()));
    });

    test('die Staerke schlaegt weiterhin Zeit und Kennung', () {
      const log = SignalLog();
      final at = _noon.subtract(const Duration(hours: 20));
      final schwach = SignalIncident(
          id: 'aaa', at: at, intensity: 1, triggerClass: TriggerClass.unclear);
      final stark = SignalIncident(
          id: 'zzz',
          at: at.add(const Duration(minutes: 1)),
          intensity: 5,
          triggerClass: TriggerClass.unclear);

      expect(
        log
            .awaitingPostMortem(
                incidents: [schwach, stark],
                reviewedIds: const {},
                now: _noon)
            .first
            .id,
        'zzz',
      );
    });
  });

  group('Die Beziehungslisten sind sortiert, nicht eingesammelt', () {
    test('Blocker und Blockierte stehen in fester Reihenfolge', () {
      final tasks = [
        _task('ziel'),
        for (var i = 0; i < _enoughToShuffle; i++) _task(_id(i)),
      ];
      final links = [
        for (var i = 0; i < _enoughToShuffle; i++)
          TaskLink(blockerId: _id(i), blockedId: 'ziel'),
      ];

      final vorwaerts =
          TaskLinkGraph.from(tasks: tasks, links: links).blockersOf('ziel');
      final rueckwaerts =
          TaskLinkGraph.from(tasks: tasks, links: links.reversed.toList())
              .blockersOf('ziel');

      expect(vorwaerts, rueckwaerts);
      expect(vorwaerts, orderedEquals(List<String>.from(vorwaerts)..sort()));
    });

    test('der gemeldete Kreis ist bei mehreren Wegen immer derselbe', () {
      // Eine Fehlermeldung, die zwischen zwei Laeufen wechselt, ist keine.
      final links = [
        const TaskLink(blockerId: 'a', blockedId: 'm'),
        const TaskLink(blockerId: 'a', blockedId: 'b'),
        const TaskLink(blockerId: 'b', blockedId: 'z'),
        const TaskLink(blockerId: 'm', blockedId: 'z'),
      ];

      List<String> pathOf(List<TaskLink> existing) {
        try {
          ensureAcyclic(existing: existing, blockerId: 'z', blockedId: 'a');
          fail('Der Kreis wurde nicht erkannt');
        } on TaskLinkCycleError catch (e) {
          return e.path;
        }
      }

      expect(pathOf(links), pathOf(links.reversed.toList()));
    });
  });
}
