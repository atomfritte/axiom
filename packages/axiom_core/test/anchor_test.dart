import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

void main() {
  Anchor anchorAt(
    int hour,
    int minute, {
    Duration travel = const Duration(minutes: 25),
    Duration prepare = kDefaultPrepare,
    Duration buffer = kDefaultBuffer,
    Duration contextSwitch = kDefaultContextSwitch,
  }) =>
      Anchor(
        id: 'a1',
        title: 'Zahnarzt',
        arriveBy: DateTime(2026, 8, 3, hour, minute),
        travel: travel,
        prepare: prepare,
        buffer: buffer,
        contextSwitch: contextSwitch,
        location: 'Praxis',
      );

  group('Rückwärtsverkettung [D4]', () {
    test('rechnet die Kette vom Termin zurück', () {
      final chain = anchorAt(14, 0).chain;

      expect(chain.map((s) => s.kind), [
        AnchorStepKind.leaveContext,
        AnchorStepKind.prepare,
        AnchorStepKind.depart,
        AnchorStepKind.arrive,
      ]);

      // 14:00 ankommen − 25 Fahrt − 10 Puffer = 13:25 losgehen
      // − 15 fertigmachen = 13:10  − 10 Kontextwechsel = 13:00
      expect(chain[3].at, DateTime(2026, 8, 3, 14, 0));
      expect(chain[2].at, DateTime(2026, 8, 3, 13, 25));
      expect(chain[1].at, DateTime(2026, 8, 3, 13, 10));
      expect(chain[0].at, DateTime(2026, 8, 3, 13, 0));
    });

    test('Schritte sind chronologisch sortiert', () {
      final chain = anchorAt(9, 30).chain;
      for (var i = 1; i < chain.length; i++) {
        expect(chain[i].at.isAfter(chain[i - 1].at), isTrue);
      }
    });

    test('lässt Schritte weg, die keine Zeit kosten', () {
      final chain = anchorAt(
        14,
        0,
        travel: Duration.zero,
        buffer: Duration.zero,
        prepare: Duration.zero,
        contextSwitch: Duration.zero,
      ).chain;
      expect(chain, hasLength(1));
      expect(chain.single.kind, AnchorStepKind.arrive);
    });

    test('nennt den Zielort, wenn bekannt', () {
      expect(anchorAt(14, 0).chain[2].label, contains('Praxis'));
    });
  });

  group('Vorlaufzeit — die versteckten Kosten sichtbar machen', () {
    test('summiert alles, was im Kalender nicht steht', () {
      // 25 Fahrt + 10 Puffer + 15 fertigmachen + 10 Kontextwechsel
      expect(anchorAt(14, 0).leadTime, const Duration(minutes: 60));
    });

    test('startsAt liegt eine Vorlaufzeit vor dem Termin', () {
      final anchor = anchorAt(14, 0);
      expect(anchor.startsAt, DateTime(2026, 8, 3, 13, 0));
    });
  });

  group('Nächster Schritt', () {
    test('liefert den ersten noch bevorstehenden', () {
      final anchor = anchorAt(14, 0);
      expect(
        anchor.nextStep(DateTime(2026, 8, 3, 12, 0))!.kind,
        AnchorStepKind.leaveContext,
      );
      expect(
        anchor.nextStep(DateTime(2026, 8, 3, 13, 5))!.kind,
        AnchorStepKind.prepare,
      );
      expect(
        anchor.nextStep(DateTime(2026, 8, 3, 13, 30))!.kind,
        AnchorStepKind.arrive,
      );
    });

    test('liefert null, wenn alles vorbei ist', () {
      expect(anchorAt(14, 0).nextStep(DateTime(2026, 8, 3, 15, 0)), isNull);
    });
  });

  group('Zustand', () {
    test('ist aktiv zwischen Vorlaufbeginn und Termin', () {
      final anchor = anchorAt(14, 0);
      expect(anchor.isActive(DateTime(2026, 8, 3, 12, 30)), isFalse);
      expect(anchor.isActive(DateTime(2026, 8, 3, 13, 15)), isTrue);
      expect(anchor.isActive(DateTime(2026, 8, 3, 14, 30)), isFalse);
    });

    test('ohne Erledigt-Vermerk zählt jeder vergangene Schritt als offen',
        () {
      final anchor = anchorAt(14, 0);
      // 13:20 — "Laufendes abschließen" (13:00) und "Fertigmachen" (13:10)
      // liegen beide zurück, und nichts ist quittiert.
      expect(anchor.isBehind(DateTime(2026, 8, 3, 13, 20)), isTrue);
      // Kurz nach einem Schritt noch kein Rückstand — fünf Minuten Toleranz.
      expect(anchor.isBehind(DateTime(2026, 8, 3, 13, 2)), isFalse);
    });

    test('mit Erledigt-Vermerk unterscheidet sich „im Zeitplan" von '
        "„hinterher\"", () {
      // Der Punkt der Methode. Um 13:20 sieht die Uhr in beiden Fällen
      // dasselbe: Zwei Schrittzeiten liegen zurück. Ob das Rückstand ist,
      // entscheidet allein, was quittiert wurde.
      final anchor = anchorAt(14, 0);
      final at = DateTime(2026, 8, 3, 13, 20);

      // Kontext verlassen (13:00) und Fertigmachen (13:10) sind erledigt,
      // als Nächstes steht Losgehen um 13:25 an — pünktlich.
      expect(anchor.isBehind(at, lastDone: AnchorStepKind.prepare), isFalse);

      // Nur der Kontextwechsel ist erledigt: Fertigmachen war um 13:10
      // dran und hat noch nicht begonnen.
      expect(anchor.isBehind(at, lastDone: AnchorStepKind.leaveContext),
          isTrue);
    });

    test('nennt den Schritt, um den es geht — nicht nur, dass es einen gibt',
        () {
      // Eine Meldung „hinterher" ohne Gegenstand ist eine Bewertung. Mit
      // Gegenstand ist sie eine Information (R7).
      final overdue = anchorAt(14, 0).overdueStep(
        DateTime(2026, 8, 3, 13, 20),
        lastDone: AnchorStepKind.leaveContext,
      );
      expect(overdue?.kind, AnchorStepKind.prepare);
      expect(overdue?.at, DateTime(2026, 8, 3, 13, 10));
    });

    test('ist alles quittiert, gibt es keinen Rückstand', () {
      expect(
        anchorAt(14, 0)
            .isBehind(DateTime(2026, 8, 3, 13, 50), lastDone: AnchorStepKind.depart),
        isFalse,
      );
    });

    test('nach dem Termin bleibt es still — auch ohne Vermerk', () {
      expect(anchorAt(14, 0).isBehind(DateTime(2026, 8, 3, 15, 0)), isFalse);
    });
  });

  group('Erinnerungsvorlauf', () {
    test('Kontextwechsel bekommt den längsten Vorlauf', () {
      // Aus dem Fokus auszusteigen dauert — deshalb früher wecken.
      expect(
        reminderLeadFor(AnchorStepKind.leaveContext),
        greaterThan(reminderLeadFor(AnchorStepKind.prepare)),
      );
    });

    test('die Ankunft selbst braucht keine Erinnerung mehr', () {
      expect(reminderLeadFor(AnchorStepKind.arrive), Duration.zero);
    });
  });

  test('Determinismus: gleiche Eingabe, gleiche Kette', () {
    final a = anchorAt(14, 0).chain.map((s) => s.at).toList();
    final b = anchorAt(14, 0).chain.map((s) => s.at).toList();
    expect(a, b);
  });
}
