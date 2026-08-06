/// Zeitanker an den Raendern.
///
/// Der Nutzen des Moduls haengt an einer einzigen Zahl: dem Vorlauf, der im
/// Kalender nicht steht. Rechnet die Kette falsch, ist der Anker schlechter
/// als kein Anker — er erzeugt dann genau die Sicherheitspuffer im Kopf, die
/// er ersetzen soll [D4]. Hier stehen die Kanten: Schritte, die keine Zeit
/// kosten, der Uebergang von „steht noch bevor" zu „ist vorbei", und die
/// Toleranz, ab der ein Schritt als ueberfaellig gilt.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

final DateTime _termin = DateTime(2026, 8, 3, 14);

Anchor _anchor({
  Duration travel = const Duration(minutes: 25),
  Duration prepare = kDefaultPrepare,
  Duration buffer = kDefaultBuffer,
  Duration contextSwitch = kDefaultContextSwitch,
  String? location,
}) =>
    Anchor(
      id: 'a1',
      title: 'Zahnarzt',
      arriveBy: _termin,
      travel: travel,
      prepare: prepare,
      buffer: buffer,
      contextSwitch: contextSwitch,
      location: location,
    );

void main() {
  group('Die Kette wird rueckwaerts gerechnet, vorwaerts gelesen', () {
    test('jeder Schritt liegt vor dem naechsten', () {
      for (final anchor in [
        _anchor(),
        _anchor(travel: Duration.zero),
        _anchor(prepare: Duration.zero, contextSwitch: Duration.zero),
        _anchor(travel: const Duration(hours: 3), buffer: const Duration(hours: 1)),
      ]) {
        final zeiten = anchor.chain.map((s) => s.at).toList();
        for (var i = 1; i < zeiten.length; i++) {
          expect(zeiten[i].isAfter(zeiten[i - 1]), isTrue,
              reason: anchor.toString());
        }
      }
    });

    test('die Kette endet immer mit der Ankunft', () {
      for (final anchor in [
        _anchor(),
        _anchor(
            travel: Duration.zero,
            prepare: Duration.zero,
            buffer: Duration.zero,
            contextSwitch: Duration.zero),
      ]) {
        expect(anchor.chain.last.kind, AnchorStepKind.arrive);
        expect(anchor.chain.last.at, _termin);
        expect(anchor.chain.last.label, 'Zahnarzt');
      }
    });

    test('ein Schritt ohne Zeit steht nicht in der Kette', () {
      // Sonst stuenden in der Liste Schritte, die nichts kosten — und eine
      // Liste mit Fuellzeilen wird nicht gelesen (G1).
      expect(
        _anchor(contextSwitch: Duration.zero).chain.map((s) => s.kind),
        isNot(contains(AnchorStepKind.leaveContext)),
      );
      expect(
        _anchor(prepare: Duration.zero).chain.map((s) => s.kind),
        isNot(contains(AnchorStepKind.prepare)),
      );
    });

    test('Losgehen bleibt, solange Weg oder Puffer uebrig sind', () {
      expect(
        _anchor(travel: Duration.zero, buffer: const Duration(minutes: 10))
            .chain
            .map((s) => s.kind),
        contains(AnchorStepKind.depart),
      );
      expect(
        _anchor(travel: Duration.zero, buffer: Duration.zero)
            .chain
            .map((s) => s.kind),
        isNot(contains(AnchorStepKind.depart)),
      );
    });

    test('ein Termin ohne jeden Vorlauf ist nur er selbst', () {
      final ohne = _anchor(
        travel: Duration.zero,
        prepare: Duration.zero,
        buffer: Duration.zero,
        contextSwitch: Duration.zero,
      );
      expect(ohne.chain, hasLength(1));
      expect(ohne.leadTime, Duration.zero);
      expect(ohne.startsAt, _termin);
    });

    test('der Zielort steht im Schritt, wenn er bekannt ist', () {
      expect(
        _anchor(location: 'Praxis Nord')
            .chain
            .firstWhere((s) => s.kind == AnchorStepKind.depart)
            .label,
        'Los nach Praxis Nord',
      );
      expect(
        _anchor()
            .chain
            .firstWhere((s) => s.kind == AnchorStepKind.depart)
            .label,
        'Losgehen',
      );
    });
  });

  group('Vorlaufzeit — die versteckten Kosten', () {
    test('sie ist die Summe aller vier Posten', () {
      final anchor = _anchor(
        travel: const Duration(minutes: 25),
        prepare: const Duration(minutes: 15),
        buffer: const Duration(minutes: 10),
        contextSwitch: const Duration(minutes: 10),
      );
      expect(anchor.leadTime, const Duration(minutes: 60));
      expect(anchor.startsAt, _termin.subtract(const Duration(minutes: 60)));
      expect(anchor.chain.first.at, anchor.startsAt);
    });

    test('der Kontextwechsel ist der Posten, der im Kopf fehlt [D11]', () {
      // Er steht am Anfang der Kette und ist damit der frueheste Zeitpunkt.
      final anchor = _anchor(contextSwitch: const Duration(minutes: 20));
      expect(anchor.chain.first.kind, AnchorStepKind.leaveContext);
      expect(
        anchor.leadTime - _anchor(contextSwitch: Duration.zero).leadTime,
        const Duration(minutes: 20),
      );
    });

    test('die Voreinstellungen sind benannt, nicht eingestreut', () {
      expect(kDefaultPrepare, const Duration(minutes: 15));
      expect(kDefaultBuffer, const Duration(minutes: 10));
      expect(kDefaultContextSwitch, const Duration(minutes: 10));
    });
  });

  group('Der naechste Schritt', () {
    final anchor = _anchor();

    test('ein Schritt genau jetzt gilt nicht mehr als bevorstehend', () {
      // Er ist faellig, nicht kuenftig — der Hinweis dazu ist schon
      // gelaufen.
      final erster = anchor.chain.first;
      expect(anchor.nextStep(erster.at.subtract(const Duration(seconds: 1)))!.kind,
          erster.kind);
      expect(anchor.nextStep(erster.at)!.kind, isNot(erster.kind));
    });

    test('nach dem Termin gibt es keinen mehr', () {
      expect(anchor.nextStep(_termin), isNull);
      expect(anchor.nextStep(_termin.add(const Duration(hours: 1))), isNull);
    });

    test('lange vorher ist es der erste', () {
      expect(anchor.nextStep(_termin.subtract(const Duration(days: 1)))!.kind,
          AnchorStepKind.leaveContext);
    });
  });

  group('Zustand', () {
    final anchor = _anchor();

    test('aktiv genau ab dem Vorlaufbeginn bis zum Termin', () {
      expect(
          anchor.isActive(anchor.startsAt.subtract(const Duration(seconds: 1))),
          isFalse);
      expect(anchor.isActive(anchor.startsAt), isTrue);
      expect(anchor.isActive(_termin.subtract(const Duration(seconds: 1))),
          isTrue);
      expect(anchor.isActive(_termin), isFalse);
    });

    test('vor dem ersten Schritt gibt es keinen Rueckstand', () {
      expect(anchor.isBehind(anchor.startsAt.subtract(const Duration(hours: 1))),
          isFalse);
    });

    test('in den ersten fuenf Minuten der Kette ebenfalls nicht', () {
      expect(anchor.isBehind(anchor.startsAt.add(const Duration(minutes: 4))),
          isFalse);
    });

    test('nach dem Termin gibt es keinen Rueckstand mehr', () {
      // Der Termin ist vorbei; die Meldung waere ein Vorwurf ohne Nutzen
      // (R7).
      expect(anchor.isBehind(_termin.add(const Duration(hours: 2))), isFalse);
    });

    test('waehrend der Kette meldet isBehind durchgehend true — die Grenze '
        'der Methode', () {
      // **Diese Zusicherung ist bewusst so formuliert, wie sie ist.**
      //
      // `isBehind` kennt nur die Kette und die Uhr. Ob ein Schritt getan
      // wurde, steht nirgends — es gibt keinen Haken an einem Ankerschritt.
      // Damit kann die Methode „im Zeitplan" und „hinterher" gar nicht
      // unterscheiden: Sobald der erste Schritt mehr als fuenf Minuten
      // zurueckliegt, meldet sie Rueckstand, auch wenn alles nach Plan
      // laeuft.
      //
      // Solange das so ist, taugt sie nicht als Grundlage fuer eine
      // Benachrichtigung — und wird auch von niemandem so benutzt: Ausser
      // den Tests ruft sie im ganzen Projekt nichts auf. Dieser Test haelt
      // die Grenze fest, damit sie beim naechsten Anlauf nicht als
      // Ueberfaelligkeitsmelder eingebaut wird, ohne dass ein
      // Erledigt-Vermerk dazukommt.
      var immer = true;
      for (var min = 6; min < anchor.leadTime.inMinutes; min++) {
        immer &= anchor.isBehind(anchor.startsAt.add(Duration(minutes: min)));
      }
      expect(immer, isTrue);
    });
  });

  group('Erinnerungsvorlauf', () {
    test('jede Schrittart hat einen Wert', () {
      for (final kind in AnchorStepKind.values) {
        expect(() => reminderLeadFor(kind), returnsNormally, reason: kind.name);
      }
    });

    test('der Kontextwechsel bekommt den laengsten Vorlauf', () {
      // Aus dem Fokus auszusteigen dauert [D11].
      final vorlauf = {
        for (final kind in AnchorStepKind.values) kind: reminderLeadFor(kind),
      };
      for (final kind in AnchorStepKind.values) {
        if (kind == AnchorStepKind.leaveContext) continue;
        expect(vorlauf[AnchorStepKind.leaveContext]!,
            greaterThanOrEqualTo(vorlauf[kind]!),
            reason: kind.name);
      }
    });

    test('die Ankunft selbst braucht keine Erinnerung mehr', () {
      expect(reminderLeadFor(AnchorStepKind.arrive), Duration.zero);
    });
  });

  group('copyWith', () {
    test('behaelt die Kennung und alles Nichtgenannte', () {
      final vorher = _anchor(location: 'Praxis');
      final nachher = vorher.copyWith(travel: const Duration(hours: 1));
      expect(nachher.id, 'a1');
      expect(nachher.title, 'Zahnarzt');
      expect(nachher.arriveBy, _termin);
      expect(nachher.travel, const Duration(hours: 1));
      expect(nachher.prepare, vorher.prepare);
      expect(nachher.buffer, vorher.buffer);
      expect(nachher.contextSwitch, vorher.contextSwitch);
      expect(nachher.location, 'Praxis');
    });
  });

  test('Determinismus: gleicher Anker, gleiche Kette — ohne Uhr', () {
    // Die Kette ist eine reine Funktion ueber den Feldern. Sonst waere sie
    // ohne Geraet nicht pruefbar.
    final a = _anchor();
    final b = _anchor();
    expect(a.chain.map((s) => '${s.kind}@${s.at}').toList(),
        b.chain.map((s) => '${s.kind}@${s.at}').toList());
    expect(a.leadTime, b.leadTime);
  });
}
