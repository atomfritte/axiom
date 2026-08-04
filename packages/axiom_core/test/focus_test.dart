import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

void main() {
  _plannedFocus();
  const governor = FocusGovernor();
  final start = DateTime(2026, 8, 3, 10);

  FocusSession sessionOf({
    String? anchorTaskId = 't1',
    Duration planned = const Duration(minutes: 50),
  }) =>
      FocusSession(
        id: 'f1',
        startedAt: start,
        anchorTaskId: anchorTaskId,
        anchorTitle: anchorTaskId == null ? null : 'Steuerunterlagen',
        planned: planned,
      );

  StateVector stateOf({int loadIndex = 20, int capacity = 60}) => StateVector(
        at: start.toUtc(),
        capacity: capacity,
        focusDebt: 30,
        sensationNeed: 40,
        loadIndex: loadIndex,
        regulation: 80,
        sleepDebt: 10,
      );

  FocusVerdict assess({
    FocusSession? session,
    Duration after = const Duration(minutes: 20),
    StateVector? state,
    ({Anchor anchor, AnchorStep step})? anchor,
    Duration? sinceBody,
  }) =>
      governor.assess(
        session: session ?? sessionOf(),
        now: start.add(after),
        state: state ?? stateOf(),
        nextAnchorStep: anchor,
        sinceBodyPrompt: sinceBody,
      );

  group('Schutz ist der Normalfall [D6, R5]', () {
    test('läuft auf dem gesetzten Ziel und in der Zeit — nicht stören', () {
      final verdict = assess();
      expect(verdict.action, FocusAction.protect);
      expect(verdict.reasonText, contains('stumm'));
    });

    test('leichte Überziehung stört noch nicht', () {
      final verdict = assess(after: const Duration(minutes: 65));
      expect(verdict.action, FocusAction.protect);
    });
  });

  group('Gestufte Eskalation', () {
    test('deutliche Überziehung: leiser Hinweis', () {
      final verdict = assess(after: const Duration(minutes: 80));
      expect(verdict.action, FocusAction.gentleNudge);
      expect(verdict.reasonText, contains('über der geplanten Zeit'));
    });

    test('starke Überziehung: sichtbare Unterbrechung', () {
      final verdict = assess(after: const Duration(minutes: 115));
      expect(verdict.action, FocusAction.clearInterrupt);
      // Bewusst erlaubend formuliert — Weitermachen bleibt eine Option.
      expect(verdict.reasonText, contains('in Ordnung'));
    });

    test('die Eskalation überspringt keine Stufe', () {
      final gentle = assess(after: const Duration(minutes: 80)).action;
      final clear = assess(after: const Duration(minutes: 115)).action;
      expect(gentle.index, lessThan(clear.index));
    });
  });

  group('Ohne gesetztes Ziel wird früher gefragt', () {
    test('nach 45 min leise nachfragen', () {
      final verdict = assess(
        session: sessionOf(anchorTaskId: null),
        after: const Duration(minutes: 50),
      );
      expect(verdict.action, FocusAction.gentleNudge);
      expect(verdict.reasonText, contains('ohne gesetztes Ziel'));
    });

    test('mit Ziel wird zu diesem Zeitpunkt nicht gestört', () {
      expect(
        assess(after: const Duration(minutes: 50)).action,
        FocusAction.protect,
      );
    });
  });

  group('Termin schlägt Fokus [D4]', () {
    /// Baut einen Anker, dessen ERSTER Kettenschritt in [until] ab
    /// Auswertungszeit faellt. Die Kette liegt vor dem Termin — der Termin
    /// selbst muss also um die volle Vorlaufzeit spaeter liegen.
    ({Anchor anchor, AnchorStep step}) anchorStepIn(
      Duration until, {
      Duration evaluatedAfter = const Duration(minutes: 10),
    }) {
      const travel = Duration(minutes: 25);
      final leadTime =
          travel + kDefaultBuffer + kDefaultPrepare + kDefaultContextSwitch;
      final anchor = Anchor(
        id: 'a1',
        title: 'Zahnarzt',
        arriveBy: start.add(evaluatedAfter).add(until).add(leadTime),
        travel: travel,
      );
      return (anchor: anchor, step: anchor.chain.first);
    }

    test('naher Ankerschritt unterbricht hart, auch bei perfektem Lauf', () {
      final verdict = assess(
        after: const Duration(minutes: 10),
        anchor: anchorStepIn(const Duration(minutes: 10)),
      );
      expect(verdict.action, FocusAction.hardStop);
      expect(verdict.reasonText, contains('Zahnarzt'));
    });

    test('ferner Termin stört nicht', () {
      final verdict = assess(
        after: const Duration(minutes: 10),
        anchor: anchorStepIn(const Duration(hours: 4)),
      );
      expect(verdict.action, FocusAction.protect);
    });

    test('ein bereits verpasster Schritt loest keinen Dauerstop aus', () {
      // Sonst haenge der Fokus dauerhaft im hardStop fest, obwohl der
      // Moment vorbei ist.
      final verdict = assess(
        after: const Duration(minutes: 10),
        anchor: anchorStepIn(const Duration(minutes: -30)),
      );
      expect(verdict.action, isNot(FocusAction.hardStop));
    });

    test('bei nahem Termin wird häufiger nachgeprüft', () {
      final verdict = assess(
        after: const Duration(minutes: 10),
        anchor: anchorStepIn(const Duration(minutes: 8)),
      );
      expect(verdict.recheckAfter, lessThan(const Duration(minutes: 5)));
    });
  });

  group('Erhaltungsmodus [D1]', () {
    test('L3 beendet auch einen gut laufenden Fokus', () {
      final verdict = assess(state: stateOf(loadIndex: 90));
      expect(verdict.action, FocusAction.hardStop);
      expect(verdict.reasonText, contains('Erhaltungsmodus'));
    });

    test('formuliert ohne Vorwurf', () {
      final verdict = assess(state: stateOf(loadIndex: 90));
      for (final blame in ['versagt', 'zu viel gemacht', 'endlich']) {
        expect(verdict.reasonText.toLowerCase(), isNot(contains(blame)));
      }
    });
  });

  group('Körper wird übergangen [D7]', () {
    test('nach langer Zeit ohne Pause leiser Hinweis', () {
      final verdict = assess(
        after: const Duration(minutes: 40),
        sinceBody: const Duration(minutes: 120),
      );
      expect(verdict.action, FocusAction.gentleNudge);
      expect(verdict.reasonText, contains('getrunken'));
    });

    test('kürzlich quittiert — kein Hinweis', () {
      final verdict = assess(
        after: const Duration(minutes: 40),
        sinceBody: const Duration(minutes: 20),
      );
      expect(verdict.action, FocusAction.protect);
    });
  });

  group('Sitzung', () {
    test('rechnet Überziehung erst ab der geplanten Dauer', () {
      final session = sessionOf();
      expect(session.overrun(start.add(const Duration(minutes: 30))),
          Duration.zero);
      expect(session.overrun(start.add(const Duration(minutes: 70))),
          const Duration(minutes: 20));
    });

    test('Wiedereinstiegsfrage nennt das Ziel, wenn es eines gibt [D11]', () {
      expect(
        FocusGovernor.breadcrumbPrompt(sessionOf()),
        contains('Steuerunterlagen'),
      );
      expect(
        FocusGovernor.breadcrumbPrompt(sessionOf(anchorTaskId: null)),
        contains('nächste Handgriff'),
      );
    });
  });

  test('Determinismus: gleiche Lage, gleiches Urteil', () {
    final a = assess(after: const Duration(minutes: 80));
    final b = assess(after: const Duration(minutes: 80));
    expect(a.action, b.action);
    expect(a.reason, b.reason);
  });
}

void _plannedFocus() {
  group('Fokusdauer folgt der Kapazität', () {
    test('an knappen Tagen kürzer, an guten länger', () {
      // Ein starres Intervall misst nichts. An einem Tag mit Kapazität 30
      // wird das lange Fenster abgebrochen — und das Abbrechen selbst macht
      // das Anfangen beim naechsten Mal teurer [D2].
      expect(plannedFocusFor(20), const Duration(minutes: 15));
      expect(plannedFocusFor(50), const Duration(minutes: 25));
      expect(plannedFocusFor(90), const Duration(minutes: 45));
    });

    test('monoton: mehr Kapazität heisst nie weniger Zeit', () {
      var previous = Duration.zero;
      for (var capacity = 0; capacity <= 100; capacity++) {
        final planned = plannedFocusFor(capacity);
        expect(planned >= previous, isTrue, reason: 'bei $capacity');
        previous = planned;
      }
    });
  });
}
