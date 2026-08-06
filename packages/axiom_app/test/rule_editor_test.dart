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
import 'package:axiom_app/design/widgets/instruments.dart';
import 'package:axiom_app/screens/rule_editor_screen.dart';
import 'package:axiom_app/state/rule_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// Der ganze Editor auf einmal, ohne Scrollen.
///
/// Ein `ListView` baut nur, was in Sichtweite ist — wer Positionen oder
/// Anzahlen prueft, prueft sonst den Ausschnitt und nicht den Schirm. Die
/// hohe Ansicht macht jede Abschnittsmarke und jede Karte gleichzeitig
/// vorhanden.
Future<void> pumpWholeEditor(WidgetTester tester, TestHarness h) => pumpScaled(
    tester, h.wrap(const RuleEditorScreen()),
    size: const Size(412, 4400));

/// Scrollt, bis der Treffer im Baum ist.
///
/// Der Editor ist ein ListView: Was nicht in Sichtweite ist, existiert im
/// Widget-Baum nicht. Ohne dieses Scrollen prueft der Test nicht die
/// Abwesenheit einer Zusage, sondern nur die Abwesenheit von Pixeln.
///
/// **Gezogen wird am linken Rand, nicht in der Mitte.** Hier stand
/// `tester.drag(find.byType(ListView).first, …)`, und das setzt den Finger in
/// die Mitte des Sichtfensters. Trifft er dort das mehrzeilige
/// Begruendungsfeld, scrollt dessen eigener Textbereich statt der Liste — die
/// Seite steht still, und der Test meldet ein fehlendes Widget statt eines
/// fehlgeschlagenen Scrollens. Der Sechs-Pixel-Streifen links liegt im
/// Innenabstand der Liste: dort ist nie ein Bedienelement.
Future<Finder> reveal(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
    await tester.dragFrom(const Offset(6, 600), const Offset(0, -400));
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
      expect(find.text('Sieben Tage stumm'), findsNothing,
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
      expect(find.text('Sieben Tage stumm'), findsOneWidget);
      expect(save.onPressed, isNotNull);
    });
  });

  group('Was der Schirm von sich aus zeigt', () {
    testWidgets('was fehlt, steht am Feld — nicht erst unten am Knopf',
        (tester) async {
      // Die Liste der Lücken stand am Seitenende, hinter allem. Wer sie
      // las, musste zurückscrollen und raten, welches Feld gemeint war.
      // `rationale` ist das Feld, an dem G2 hängt — dass es Pflicht ist,
      // darf man nicht erst beim gescheiterten Speichern erfahren.
      await pumpWholeEditor(tester, h);

      final atLabel = find.ancestor(
        of: find.text('Fehlt noch'),
        matching: find.byType(SectionLabel),
      );
      expect(atLabel, findsNWidgets(2),
          reason: 'Titel und Begründung sind leer — an beiden steht die '
              'Marke, und einmal steht die Liste unten.');

      await tester.enterText(
        find.ancestor(
          of: find.text('Kurz und in deiner Sprache'),
          matching: find.byType(TextField),
        ),
        'Abends nichts Schweres mehr vorschlagen',
      );
      await tester.pumpAndSettle();
      expect(atLabel, findsOneWidget, reason: 'Der Titel reicht jetzt.');

      await tester.enterText(
        find.ancestor(
          of: find.text('Was diese Regel verhindern oder auslösen soll'),
          matching: find.byType(TextField),
        ),
        'Was abends noch vorgeschlagen wird, wird nicht mehr angefangen — '
        'es erzeugt nur Schuld und kostet Schlaf.',
      );
      await tester.pumpAndSettle();
      expect(atLabel, findsNothing,
          reason: 'Eine geschlossene Lücke steht nicht mehr da — die Marke '
              'ist eine Messung, keine Rüge.');
      expect(find.text('Sieben Tage stumm'), findsOneWidget);
    });

    testWidgets('die Auswertung gehört zur Bedingung, nicht zur Überschrift',
        (tester) async {
      // Sie ist das Ergebnis dessen, was in der Karte gebaut wurde — der
      // halbe Nutzen dieses Editors (G2). Über der Karte sah sie aus wie
      // ein Hinweis zur Abschnittsmarke.
      await pumpWholeEditor(tester, h);

      final verdict = find.textContaining('Zustand von jetzt');
      final card =
          find.ancestor(of: find.text('Alle'), matching: find.byType(Panel));
      expect(card, findsOneWidget);
      expect(find.descendant(of: card, matching: verdict), findsOneWidget,
          reason: 'Die Auswertung steht in derselben Karte wie die '
              'Bedingung, die sie auswertet.');
      expect(tester.getTopLeft(verdict).dy,
          greaterThan(tester.getTopLeft(find.text('Alle')).dy),
          reason: 'und unter ihr, nicht darüber');
    });

    testWidgets('eine Untergruppe steht sichtbar in ihrer Übergruppe',
        (tester) async {
      // Ohne diesen Versatz sieht eine verschachtelte Bedingung genauso aus
      // wie eine gleichrangige — und dann liest niemand mehr, ob „Alle"
      // oder „Eine von" für sie gilt.
      await pumpWholeEditor(tester, h);
      await tester.tap(find.text('Gruppe').first);
      await tester.pumpAndSettle();

      final leaves = find.byType(DropdownButtonFormField<LeafKind>);
      expect(leaves, findsNWidgets(2));
      expect(tester.getTopLeft(leaves.at(1)).dx,
          greaterThan(tester.getTopLeft(leaves.at(0)).dx),
          reason: 'Die Bedingung in der Untergruppe liegt weiter innen als '
              'die daneben.');
    });

    testWidgets('bei sehr großer Schrift läuft nichts über', (tester) async {
      // Der dichteste Schirm der App bei der größten zugelassenen Schrift.
      // Feste Höhen um Text herum sind hier die häufigste Ursache für
      // abgeschnittene Werte — und ein abgeschnittener Wert ist im
      // Regeleditor eine falsch gelesene Schwelle. Der Schirm steht nicht in
      // `robustness_test`, weil er nur über einen Knopf erreichbar ist; also
      // wird er hier abgerollt.
      await pumpScaled(tester, h.wrap(const RuleEditorScreen()),
          textScale: 2.0);

      final errors = <String>[];
      // `takeException` haelt immer nur einen Fehler — nach jedem Schritt
      // gefragt, sonst landen alle weiteren als Konsolenausgabe im Nichts.
      void collect() {
        final Object? error = tester.takeException();
        if (error != null) errors.add('$error');
      }

      collect();
      for (var i = 0; i < 40; i++) {
        await tester.dragFrom(const Offset(6, 600), const Offset(0, -300));
        await tester.pumpAndSettle();
        collect();
      }
      expect(errors, isEmpty, reason: errors.join(' | '));
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
