/// Fokus-Governor an den Raendern.
///
/// Der Governor ist die einzige Stelle, an der AXIOM in einen laufenden
/// Zustand hineinredet. Die vorhandenen Tests pruefen den Weg durch die
/// Mitte; hier stehen die Kanten: die Schwellen auf die Minute, die
/// Rangfolge der sechs Zweige gegeneinander, und der Fall, in dem ein
/// frueherer Zweig einen spaeteren verdeckt.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

final DateTime _start = DateTime(2026, 8, 3, 10);

FocusSession _session({
  String? anchorTaskId = 't1',
  Duration planned = const Duration(minutes: 50),
}) =>
    FocusSession(
      id: 'f1',
      startedAt: _start,
      anchorTaskId: anchorTaskId,
      anchorTitle: anchorTaskId == null ? null : 'Steuerunterlagen',
      planned: planned,
    );

StateVector _state({int loadIndex = 20}) => StateVector(
      at: _start.toUtc(),
      capacity: 60,
      focusDebt: 30,
      sensationNeed: 40,
      loadIndex: loadIndex,
      regulation: 80,
      sleepDebt: 10,
    );

({Anchor anchor, AnchorStep step}) _anchorIn(Duration until) {
  final anchor = Anchor(
    id: 'a1',
    title: 'Zahnarzt',
    arriveBy: _start.add(const Duration(hours: 6)),
  );
  return (
    anchor: anchor,
    step: AnchorStep(
      kind: AnchorStepKind.leaveContext,
      at: _start.add(until),
      label: 'Laufendes abschließen',
    ),
  );
}

FocusVerdict _assess({
  FocusSession? session,
  required Duration after,
  StateVector? state,
  ({Anchor anchor, AnchorStep step})? anchor,
  Duration? sinceBody,
}) =>
    const FocusGovernor().assess(
      session: session ?? _session(),
      now: _start.add(after),
      state: state ?? _state(),
      nextAnchorStep: anchor,
      sinceBodyPrompt: sinceBody,
    );

void main() {
  group('Ohne gesetztes Ziel bleibt die Eskalation erhalten [D6]', () {
    test('starke Ueberziehung unterbricht auch ohne gesetztes Ziel', () {
      // Der eigentliche Fehlermodus des Hyperfokus ist nicht das falsche
      // Ziel, sondern der fehlende Ausstieg — und der trifft eine Sitzung
      // *ohne* Ziel genauso, eher haerter. Die frueher gestellte leise
      // Frage ist als Zusatz gedacht, nicht als Deckel: Wer ohne Ziel weit
      // ueber die Zeit laeuft, muss dieselbe deutliche Unterbrechung
      // bekommen wie mit Ziel.
      final verdict = _assess(
        session: _session(anchorTaskId: null, planned: const Duration(minutes: 25)),
        after: const Duration(minutes: 90), // 65 min ueber der Zeit
      );
      expect(verdict.action, FocusAction.clearInterrupt);
      expect(verdict.reasonText, contains('über der geplanten Zeit'));
    });

    test('ohne Ziel wird trotzdem frueher gefragt als mit Ziel', () {
      // Die leise Nachfrage bleibt: Nach 45 min ohne Ziel meldet sich der
      // Governor, mit Ziel schweigt er noch.
      final ohne = _assess(
        session: _session(anchorTaskId: null),
        after: const Duration(minutes: 46),
      );
      final mit = _assess(after: const Duration(minutes: 46));
      expect(ohne.action, FocusAction.gentleNudge);
      expect(ohne.reasonText, contains('ohne gesetztes Ziel'));
      expect(mit.action, FocusAction.protect);
    });

    test('eine Sitzung ohne Ziel kommt nie ueber den leisen Hinweis hinaus — '
        'ausser die Zeit ist deutlich ueberzogen', () {
      // Sechs Stunden vertieft duerfen nicht dieselbe Antwort bekommen wie
      // sechsundvierzig Minuten.
      final kurz = _assess(
        session: _session(anchorTaskId: null),
        after: const Duration(minutes: 46),
      );
      final lang = _assess(
        session: _session(anchorTaskId: null),
        after: const Duration(minutes: 360),
      );
      expect(kurz.action.index, lessThan(lang.action.index));
    });

    test('genau bei 45 min ohne Ziel meldet sich der Governor', () {
      expect(
        _assess(
          session: _session(anchorTaskId: null),
          after: const Duration(minutes: 45),
        ).action,
        FocusAction.gentleNudge,
      );
      expect(
        _assess(
          session: _session(anchorTaskId: null),
          after: const Duration(minutes: 44),
        ).action,
        FocusAction.protect,
      );
    });
  });

  group('Schwellen auf die Minute', () {
    test('leiser Hinweis genau ab 25 min Ueberzug', () {
      expect(_assess(after: const Duration(minutes: 74)).action,
          FocusAction.protect);
      expect(_assess(after: const Duration(minutes: 75)).action,
          FocusAction.gentleNudge);
    });

    test('deutliche Unterbrechung genau ab 60 min Ueberzug', () {
      expect(_assess(after: const Duration(minutes: 109)).action,
          FocusAction.gentleNudge);
      expect(_assess(after: const Duration(minutes: 110)).action,
          FocusAction.clearInterrupt);
    });

    test('Koerperhinweis genau ab 100 min ohne Quittung [D7]', () {
      expect(
        _assess(
          after: const Duration(minutes: 20),
          sinceBody: const Duration(minutes: 99),
        ).action,
        FocusAction.protect,
      );
      final verdict = _assess(
        after: const Duration(minutes: 20),
        sinceBody: const Duration(minutes: 100),
      );
      expect(verdict.action, FocusAction.gentleNudge);
      expect(verdict.reasonText, contains('aufstehen'));
    });

    test('ein Ankerschritt schlaegt genau ab 15 min Vorlauf', () {
      expect(
        _assess(
          after: const Duration(minutes: 20),
          anchor: _anchorIn(const Duration(minutes: 36)), // 16 min entfernt
        ).action,
        FocusAction.protect,
      );
      expect(
        _assess(
          after: const Duration(minutes: 20),
          anchor: _anchorIn(const Duration(minutes: 35)), // 15 min entfernt
        ).action,
        FocusAction.hardStop,
      );
    });
  });

  group('Rangfolge der Gruende', () {
    test('der Termin schlaegt den Erhaltungsmodus', () {
      // Beide fuehren zu hardStop — der Text muss aber sagen, welcher Grund
      // gilt, sonst ist die Ausgabe nicht erklaerbar (G2).
      final verdict = _assess(
        after: const Duration(minutes: 20),
        state: _state(loadIndex: 90),
        anchor: _anchorIn(const Duration(minutes: 30)),
      );
      expect(verdict.action, FocusAction.hardStop);
      expect(verdict.reasonText, contains('Zahnarzt'));
      expect(verdict.recheckAfter, const Duration(minutes: 2));
    });

    test('der Erhaltungsmodus schlaegt jede Ueberziehung', () {
      final verdict = _assess(
        after: const Duration(minutes: 400),
        state: _state(loadIndex: 90),
      );
      expect(verdict.action, FocusAction.hardStop);
      expect(verdict.reasonText, contains('Erhaltungsmodus'));
    });

    test('die deutliche Ueberziehung schlaegt den Koerperhinweis', () {
      // Beide treffen zu; gemeldet wird der schwerere Eingriff, nicht der
      // zuerst gefundene.
      final verdict = _assess(
        after: const Duration(minutes: 115),
        sinceBody: const Duration(minutes: 115),
      );
      expect(verdict.action, FocusAction.clearInterrupt);
    });
  });

  group('Grenzfaelle der Sitzung', () {
    test('Ueberzug ist nie negativ', () {
      expect(_session().overrun(_start), Duration.zero);
      expect(_session().overrun(_start.subtract(const Duration(hours: 1))),
          Duration.zero);
    });

    test('eine gerade begonnene Sitzung wird geschuetzt', () {
      final verdict = _assess(after: Duration.zero);
      expect(verdict.action, FocusAction.protect);
      expect(verdict.recheckAfter, const Duration(minutes: 10));
    });

    test('ein bereits vergangener Ankerschritt haelt nicht dauerhaft an', () {
      // Sonst staende der Governor nach einem verpassten Schritt fuer immer
      // auf hardStop und waere danach nicht mehr glaubwuerdig.
      expect(
        _assess(
          after: const Duration(minutes: 60),
          anchor: _anchorIn(const Duration(minutes: 30)), // 30 min vorbei
        ).action,
        isNot(FocusAction.hardStop),
      );
    });

    test('die Wiedereinstiegsfrage nennt das Ziel oder fragt danach [D11]', () {
      expect(FocusGovernor.breadcrumbPrompt(_session()),
          contains('Steuerunterlagen'));
      expect(FocusGovernor.breadcrumbPrompt(_session(anchorTaskId: null)),
          contains('nächste Handgriff'));
    });

    test('copyWith haelt Start, Kennung und Ziel fest', () {
      final geaendert = _session().copyWith(
        breadcrumb: 'Bei Anlage KAP stehengeblieben',
        planned: const Duration(minutes: 25),
      );
      expect(geaendert.id, 'f1');
      expect(geaendert.startedAt, _start);
      expect(geaendert.anchorTaskId, 't1');
      expect(geaendert.anchorTitle, 'Steuerunterlagen');
      expect(geaendert.planned, const Duration(minutes: 25));
      expect(geaendert.breadcrumb, 'Bei Anlage KAP stehengeblieben');
    });
  });

  group('Fokusdauer folgt der Kapazitaet — Schwellen genau', () {
    test('unter 35 sind es 15 min, ab 35 sind es 25', () {
      expect(plannedFocusFor(34), const Duration(minutes: 15));
      expect(plannedFocusFor(35), const Duration(minutes: 25));
    });

    test('unter 70 sind es 25 min, ab 70 sind es 45', () {
      expect(plannedFocusFor(69), const Duration(minutes: 25));
      expect(plannedFocusFor(70), const Duration(minutes: 45));
    });

    test('auch bei Kapazitaet 0 kommt ein nutzbares Fenster heraus', () {
      // Ein Fenster von null Minuten waere kein Fenster, sondern ein Fehler
      // auf dem Bildschirm.
      expect(plannedFocusFor(0).inMinutes, greaterThan(0));
      expect(plannedFocusFor(100), const Duration(minutes: 45));
    });
  });

  test('kein Text des Governors enthaelt Schuld oder Ausrufezeichen (G3)', () {
    final texte = [
      for (final after in [
        const Duration(minutes: 5),
        const Duration(minutes: 80),
        const Duration(minutes: 115),
      ])
        _assess(after: after).reasonText,
      _assess(
        after: const Duration(minutes: 50),
        session: _session(anchorTaskId: null),
      ).reasonText,
      _assess(
        after: const Duration(minutes: 20),
        sinceBody: const Duration(minutes: 120),
      ).reasonText,
      _assess(after: const Duration(minutes: 20), state: _state(loadIndex: 90))
          .reasonText,
      _assess(
        after: const Duration(minutes: 20),
        anchor: _anchorIn(const Duration(minutes: 30)),
      ).reasonText,
    ];

    for (final text in texte) {
      expect(text, isNot(contains('!')), reason: text);
      for (final wort in ['endlich', 'schon wieder', 'solltest', 'versäumt']) {
        expect(text.toLowerCase(), isNot(contains(wort)), reason: text);
      }
    }
  });
}
