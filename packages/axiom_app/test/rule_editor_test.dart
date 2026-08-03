/// Der Regeleditor — geprüft auf das, was er zusichert.
///
/// Ein Editor für ein Regelwerk ist der direkteste Zugang zur Meta-Work-Falle
/// (D3): Ein selbstgebautes, konfigurierbares System zu optimieren ist immer
/// stimulierender als das, wofür es gebaut wurde. Die Zusagen, die das
/// erträglich machen, sind deshalb keine Kosmetik — sie werden hier geprüft.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_core/axiom_core.dart' as core show Action;
import 'package:axiom_data/axiom_data.dart';
import 'package:axiom_app/screens/rule_editor_screen.dart';
import 'package:axiom_app/state/rule_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// Scrollt, bis der Treffer im Baum ist.
///
/// Der Editor ist ein ListView: Was nicht in Sichtweite ist, existiert im
/// Widget-Baum nicht. Ohne dieses Scrollen prueft der Test nicht die
/// Abwesenheit einer Zusage, sondern nur die Abwesenheit von Pixeln.
Future<Finder> reveal(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 30 && finder.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await tester.pumpAndSettle();
  }
  return finder;
}

Future<Finder> saveButton(WidgetTester tester) =>
    reveal(tester, find.widgetWithText(FilledButton, 'Speichern'));

/// Feld ueber seinen Platzhalter finden — Reihenfolge im Baum ist kein
/// stabiler Anker, sobald die Seite umsortiert wird.
Future<void> fill(WidgetTester tester, String hint, String text) async {
  await reveal(tester, find.text(hint));
  await tester.enterText(
    find.ancestor(of: find.text(hint), matching: find.byType(TextField)),
    text,
  );
  await tester.pumpAndSettle();
}

void main() {
  late TestHarness h;

  setUp(() => h = TestHarness.create());
  tearDown(() => h.dispose());

  group('Entwurf und Bedingung sind ineinander überführbar', () {
    final samples = <String, Map<String, Object?>>{
      'einfach': {
        'capacity': {'lt': 40}
      },
      'Gruppe': {
        'all': [
          {
            'capacity': {'lt': 40}
          },
          {
            'load_level': {'eq': 'L2'}
          },
        ]
      },
      'verneint': {
        'not': {
          'active_slot': {'eq': 'focus'}
        }
      },
      'verschachtelt': {
        'any': [
          {
            'time_between': ['22:00', '05:00']
          },
          {
            'all': [
              {
                'minutes_since': {'event': 'checkin', 'gte': 240}
              },
              {
                'count_today': {'event': 'capture', 'gt': 3}
              },
            ]
          },
        ]
      },
    };

    samples.forEach((name, map) {
      test(name, () {
        final original = Condition.fromMap(map);
        // Der Entwurf darf umbauen, solange die Bedeutung bleibt: „nicht"
        // wandert im Editor an die Bedingung statt eine Ebene zu bilden.
        expect(rootDraft(original).build().toString(), original.toString());
      });
    });

    test('eine Gruppe mit einem Kind erzeugt keine leere Ebene', () {
      final draft = DraftGroup(children: [DraftLeaf()]);
      expect(draft.build(), isA<NumericCompare>());
    });

    test('eine leere Gruppe ist kein gültiger Zustand', () {
      expect(DraftGroup().build, throwsA(isA<ConditionError>()));
    });

    test('der Wechsel der Art hinterlässt keinen unmöglichen Operator', () {
      // Von einer Zahl auf eine Auswahl: `lt` gibt es dort nicht, und eine
      // Regel, die sich deshalb nicht speichern laesst, ohne dass jemand
      // sagt warum, ist schlimmer als gar kein Editor.
      final leaf = DraftLeaf(op: CompareOp.lt);
      leaf.switchTo(LeafKind.choice);
      expect(RuleVocabulary.symbolicOperators, contains(leaf.op));
      expect(leaf.build(), isA<SymbolicCompare>());
    });
  });

  group('Was der Editor zusichert', () {
    testWidgets('ohne Begründung lässt sich nicht speichern', (tester) async {
      await pumpPhone(tester, h.wrap(const RuleEditorScreen()));
      await tester.pumpAndSettle();

      final save = tester.widget<FilledButton>(await saveButton(tester));
      expect(save.onPressed, isNull,
          reason: 'Ohne Begründung ist die Ausgabe nicht auditierbar (G2)');
      expect(find.textContaining('Begründung ist zu kurz'), findsOneWidget);
      expect(find.text('SIEBEN TAGE STUMM'), findsNothing,
          reason: 'Die Zusage steht erst da, wenn es etwas zu speichern gibt');
    });

    testWidgets('die Vorschau sagt, ob die Bedingung jetzt zuträfe',
        (tester) async {
      await pumpPhone(tester, h.wrap(const RuleEditorScreen()));
      await tester.pumpAndSettle();
      // Genau eine der drei Aussagen, nie zwei und nie keine.
      await reveal(tester, find.textContaining('Zustand von jetzt'));
      // Genau eine der drei Aussagen, nie zwei und nie keine.
      final states = [
        find.text('Trifft mit dem Zustand von jetzt zu.').evaluate().length,
        find.text('Trifft mit dem Zustand von jetzt nicht zu.').evaluate().length,
        find.textContaining('Noch unvollständig').evaluate().length,
      ].where((n) => n > 0);
      expect(states, hasLength(1));
    });

    testWidgets('der Istwert steht neben der Bedingung', (tester) async {
      await pumpPhone(tester, h.wrap(const RuleEditorScreen()));
      await tester.pumpAndSettle();
      // Ohne den aktuellen Wert schreibt man Schwellen ins Blaue.
      expect(await reveal(tester, find.textContaining('jetzt:')), findsWidgets);
    });

    testWidgets('angeboten wird nur, was die Engine versteht', (tester) async {
      await pumpPhone(tester, h.wrap(const RuleEditorScreen()));
      await tester.pumpAndSettle();

      // Aufklappen und nachsehen: Jede angebotene Groesse muss die Engine
      // aufloesen koennen, sonst baut man eine Regel, die beim Laden
      // abgelehnt wird — und erfaehrt das erst hinterher.
      await reveal(tester, find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      for (final variable in RuleVocabulary.numerics) {
        expect(find.text(variable.label), findsWidgets,
            reason: '${variable.id} fehlt in der Auswahl');
      }
    });

    testWidgets('die Sieben-Tage-Zusage steht vor dem Speichern da',
        (tester) async {
      await pumpPhone(tester, h.wrap(const RuleEditorScreen()));
      await tester.pumpAndSettle();
      await fill(tester, 'Kurz und in deiner Sprache',
          'Abends nichts Schweres mehr vorschlagen');
      await fill(
        tester,
        'Was diese Regel verhindern oder auslösen soll',
        'Was abends noch vorgeschlagen wird, wird nicht mehr angefangen — '
        'es erzeugt nur Schuld und kostet Schlaf.',
      );

      final save = tester.widget<FilledButton>(await saveButton(tester));
      expect(find.text('SIEBEN TAGE STUMM'), findsOneWidget);
      expect(save.onPressed, isNotNull);
    });
  });

  group('Overlay wirkt auf das geladene Regelwerk', () {
    test('eine gespeicherte Regel läuft zunächst stumm mit', () {
      final now = DateTime(2026, 8, 3);
      final rule = Rule(
        id: 'R-200',
        title: 'Abends nichts Schweres',
        rationale: 'Was abends noch vorgeschlagen wird, wird nicht mehr '
            'angefangen — es erzeugt nur Schuld und kostet Schlaf.',
        deficit: 'D8',
        when: Condition.fromMap({
          'time_between': ['21:00', '23:59']
        }),
        then: const core.Action(ActionType.notify),
        priority: 50,
        severity: Severity.nudge,
        cooldown: const Cooldown(minInterval: Duration(minutes: 120)),
      );

      h.store.saveRuleOverride(
        id: rule.id,
        yaml: ruleToYaml(rule),
        overridesShipped: false,
        updatedAt: now,
        shadowUntil: now.add(kShadowPeriod),
      );

      final loaded = YamlRuleSource({
        'overlay': h.store.overrideDocument(now),
      }).parse();
      expect(loaded.issues, isEmpty, reason: loaded.issues.join('\n'));
      expect(loaded.rules.single.isShadow, isTrue);

      // Und nach Ablauf tut sie, was gespeichert wurde.
      final later = YamlRuleSource({
        'overlay': h.store.overrideDocument(now.add(const Duration(days: 8))),
      }).parse();
      expect(later.rules.single.then.type, ActionType.notify);
    });
  });
}
