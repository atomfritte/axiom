/// Blocker-Geflecht an den Raendern.
///
/// Der vorhandene Test deckt den geraden Weg ab: eine Kette, ein Kreis, ein
/// erledigter Blocker. Hier stehen die Faelle, an denen ein Graph
/// erfahrungsgemaess bricht — Kreise ueber viele Ecken, Kanten ins Leere
/// mitten in der Kette, doppelte Kanten, ein aus einer fremden Datei
/// importierter Kreis, und die Frage, ob beide Blickrichtungen dasselbe
/// sagen.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

Task _task(String id, {TaskState state = TaskState.ready}) => Task(
      id: id,
      title: 'Aufgabe $id',
      activationEnergy: 2,
      salience: 5,
      stakes: 5,
      state: state,
    );

TaskLink _link(String blocker, String blocked) =>
    TaskLink(blockerId: blocker, blockedId: blocked);

void main() {
  group('Kreise werden beim Anlegen abgelehnt, nicht beim Lesen', () {
    test('auch ueber fuenf Ecken', () {
      final existing = [
        _link('a', 'b'),
        _link('b', 'c'),
        _link('c', 'd'),
        _link('d', 'e'),
      ];
      try {
        ensureAcyclic(existing: existing, blockerId: 'e', blockedId: 'a');
        fail('Der Kreis wurde nicht erkannt');
      } on TaskLinkCycleError catch (e) {
        expect(e.path, ['e', 'a', 'b', 'c', 'd', 'e']);
      }
    });

    test('gemeldet wird der kuerzeste Kreis, nicht der erstbeste', () {
      // a -> b -> z  und  a -> z direkt. Die neue Kante z -> a schliesst
      // beide; erklaerbar ist nur der kurze.
      final existing = [_link('a', 'b'), _link('b', 'z'), _link('a', 'z')];
      try {
        ensureAcyclic(existing: existing, blockerId: 'z', blockedId: 'a');
        fail('Der Kreis wurde nicht erkannt');
      } on TaskLinkCycleError catch (e) {
        expect(e.path, ['z', 'a', 'z']);
      }
    });

    test('doppelte Kanten aendern nichts', () {
      // Der Bestand kann dieselbe Kante zweimal enthalten — eine
      // Verdopplung darf weder einen Kreis erfinden noch die Suche
      // aufhaengen.
      final existing = [_link('a', 'b'), _link('a', 'b'), _link('b', 'c')];
      expect(
        () => ensureAcyclic(existing: existing, blockerId: 'c', blockedId: 'a'),
        throwsA(isA<TaskLinkCycleError>()),
      );
      expect(
        () => ensureAcyclic(existing: existing, blockerId: 'x', blockedId: 'a'),
        returnsNormally,
      );
    });

    test('eine bereits vorhandene Selbstblockade haengt die Suche nicht auf',
        () {
      // Kann nur aus einem Import kommen — beim Anlegen wird sie abgelehnt.
      // Ein Absturz waere hier die teuerste aller Antworten.
      final existing = [_link('x', 'x'), _link('a', 'b')];
      expect(
        () => ensureAcyclic(existing: existing, blockerId: 'x', blockedId: 'a'),
        returnsNormally,
      );
    });

    test('ein bereits vorhandener Kreis haengt die Suche nicht auf', () {
      final existing = [_link('a', 'b'), _link('b', 'a')];
      expect(
        () => ensureAcyclic(existing: existing, blockerId: 'c', blockedId: 'd'),
        returnsNormally,
      );
    });

    test('eine Kante neben dem Kreis geht durch', () {
      final existing = [_link('a', 'b'), _link('b', 'c')];
      expect(
        () => ensureAcyclic(existing: existing, blockerId: 'a', blockedId: 'c'),
        returnsNormally,
      );
    });

    test('die Selbstblockade nennt beide Enden — sonst zeigt die Meldung '
        'ins Leere', () {
      try {
        ensureAcyclic(existing: const [], blockerId: 'a', blockedId: 'a');
        fail('Selbstblockade wurde nicht erkannt');
      } on TaskLinkCycleError catch (e) {
        expect(e.path, ['a', 'a']);
        expect(e.toString(), contains('a → a'));
        // Nutzertext: echte Umlaute, kein Vorwurf.
        expect(e.toString(), contains('schlösse'));
        expect(e.toString(), isNot(contains('!')));
      }
    });
  });

  group('Beide Blickrichtungen sagen dasselbe', () {
    test('ein erledigter Blocker haelt in keiner Richtung mehr etwas auf', () {
      // „Was fertig ist, haelt nichts mehr auf" — das galt bisher nur beim
      // Blick von der wartenden Aufgabe aus. Von der erledigten Aufgabe aus
      // stand dieselbe Kante weiter da: `blockedBy` meldete die wartende
      // Aufgabe, und `unblocks` zaehlte sie als Hebel. Dieselbe Kante darf
      // nicht in einer Richtung zaehlen und in der anderen nicht.
      final graph = TaskLinkGraph.from(
        tasks: [_task('fertig', state: TaskState.done), _task('wartet')],
        links: [_link('fertig', 'wartet')],
      );

      expect(graph.blockersOf('wartet'), isEmpty);
      expect(graph.blockedBy('fertig'), isEmpty);
      expect(graph.unblocks('fertig'), 0);
      expect(graph.isWaiting('wartet'), isFalse);
    });

    test('ein verworfener Blocker ebenso', () {
      final graph = TaskLinkGraph.from(
        tasks: [_task('weg', state: TaskState.dropped), _task('wartet')],
        links: [_link('weg', 'wartet')],
      );
      expect(graph.blockedBy('weg'), isEmpty);
      expect(graph.unblocks('weg'), 0);
    });

    test('wer blockiert, wird auch von der Gegenseite genannt', () {
      final graph = TaskLinkGraph.from(
        tasks: [_task('a'), _task('b')],
        links: [_link('a', 'b')],
      );
      expect(graph.blockersOf('b'), ['a']);
      expect(graph.blockedBy('a'), ['b']);
    });

    test('eine Kante ins Leere zaehlt in keiner Richtung', () {
      final graph = TaskLinkGraph.from(
        tasks: [_task('b')],
        links: [_link('geloescht', 'b')],
      );
      expect(graph.blockersOf('b'), isEmpty);
      expect(graph.blockedBy('geloescht'), isEmpty);
      expect(graph.unblocks('geloescht'), 0);
    });
  });

  group('Hebel an den Raendern', () {
    test('eine geloeschte Aufgabe mitten in der Kette trennt sie', () {
      // a -> b -> c, aber b existiert nicht mehr. Dann haelt a nichts mehr
      // auf, und c ist frei — nicht auf ewig wartend [D9].
      final graph = TaskLinkGraph.from(
        tasks: [_task('a'), _task('c')],
        links: [_link('a', 'b'), _link('b', 'c')],
      );
      expect(graph.unblocks('a'), 0);
      expect(graph.isWaiting('c'), isFalse);
    });

    test('ein importierter Kreis fuehrt nicht in eine Endlosschleife', () {
      // Beim Anlegen abgelehnt, im Import trotzdem moeglich. Jede
      // Auswertung darf hier hoechstens einen falschen Zahlenwert liefern,
      // niemals haengen.
      final graph = TaskLinkGraph.from(
        tasks: [_task('a'), _task('b'), _task('c')],
        links: [_link('a', 'b'), _link('b', 'c'), _link('c', 'a')],
      );
      expect(graph.unblocks('a'), 2);
      expect(graph.unblocks('b'), 2);
    });

    test('eine Aufgabe zaehlt sich selbst nie mit', () {
      final graph = TaskLinkGraph.from(
        tasks: [_task('a'), _task('b')],
        links: [_link('a', 'b'), _link('b', 'a')],
      );
      expect(graph.unblocks('a'), 1);
    });

    test('eine zerlegte Aufgabe haelt weiter auf — sie ist nicht erledigt',
        () {
      final graph = TaskLinkGraph.from(
        tasks: [_task('klammer', state: TaskState.blocked), _task('b')],
        links: [_link('klammer', 'b')],
      );
      expect(graph.blockersOf('b'), ['klammer']);
      expect(graph.unblocks('klammer'), 1);
    });

    test('eine Aufgabe im Eingang haelt auch auf', () {
      // `inbox` ist offen. Alles andere hiesse, dass eine Beziehung erst
      // wirkt, nachdem jemand die Aufgabe einsortiert hat.
      final graph = TaskLinkGraph.from(
        tasks: [_task('notiz', state: TaskState.inbox), _task('b')],
        links: [_link('notiz', 'b')],
      );
      expect(graph.blockersOf('b'), ['notiz']);
    });

    test('der leere Graph antwortet auf jede Frage, ohne zu werfen', () {
      const graph = TaskLinkGraph.empty;
      expect(graph.blockersOf('irgendwas'), isEmpty);
      expect(graph.blockedBy('irgendwas'), isEmpty);
      expect(graph.unblocks('irgendwas'), 0);
      expect(graph.isWaiting('irgendwas'), isFalse);
      expect(graph.all, isEmpty);
    });

    test('alle Kanten bleiben ungefiltert erhalten — Editor und Export '
        'brauchen sie', () {
      final links = [_link('fertig', 'b'), _link('geloescht', 'b')];
      final graph = TaskLinkGraph.from(
        tasks: [_task('fertig', state: TaskState.done), _task('b')],
        links: links,
      );
      expect(graph.all, links);
    });
  });
}
