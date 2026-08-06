/// Verhaltenstests für Blocker-Beziehungen: A blockiert B.
///
/// Geprüft wird, was der Nutzer merkt — was vorgeschlagen wird, was wartet,
/// was wieder frei ist —, nicht welche Methode dabei läuft.
library;

import 'package:axiom_app/screens/now_screen.dart';
import 'package:axiom_app/screens/tasks_screen.dart';
import 'package:axiom_core/axiom_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  late TestHarness h;
  setUp(() {
    // 12:15 liegt bewusst in keinem Regelfenster — sonst gewinnt eine
    // zeitgetriggerte Regel gegen den Vorschlag, den der Test prüft.
    h = TestHarness.create(at: DateTime(2026, 8, 3, 12, 15));
    h.completeOnboarding();
  });
  tearDown(() => h.dispose());

  Future<Task> task(String title, {int ae = 2, int stakes = 5}) =>
      h.runtime.createTask(
        title: title,
        activationEnergy: ae,
        salience: 5,
        stakes: stakes,
      );

  group('Auswahl (G1)', () {
    test('eine Aufgabe mit offenem Blocker wird nicht vorgeschlagen',
        () async {
      final blocker = await task('Ordner holen');
      final blockiert = await task('Steuerunterlagen sortieren');
      await h.runtime.linkBlocker(
          blockerId: blocker.id, blockedId: blockiert.id);

      final snapshot = await h.runtime.evaluate();

      expect(snapshot.startable.map((t) => t.id), isNot(contains(blockiert.id)));
      expect(snapshot.startable.map((t) => t.id), contains(blocker.id));
      expect(snapshot.isWaiting(blockiert.id), isTrue);
      // Ein Vorschlag, den man nicht ausführen kann, ist keiner: Vorn steht
      // das, was den Weg frei macht.
      expect(snapshot.startable.first.id, blocker.id);
    });

    test('der letzte erledigte Blocker macht sie wieder startbar', () async {
      final a = await task('Ordner holen');
      final b = await task('Belege sortieren');
      final ziel = await task('Steuererklärung abschicken');
      await h.runtime.linkBlocker(blockerId: a.id, blockedId: ziel.id);
      await h.runtime.linkBlocker(blockerId: b.id, blockedId: ziel.id);

      expect((await h.runtime.evaluate()).isWaiting(ziel.id), isTrue);

      // Einer erledigt — sie wartet weiter, ohne dass etwas nachgezogen
      // werden musste.
      await h.runtime.completeTask(a);
      expect((await h.runtime.evaluate()).isWaiting(ziel.id), isTrue);

      await h.runtime.completeTask(b);
      final frei = await h.runtime.evaluate();
      expect(frei.isWaiting(ziel.id), isFalse);
      expect(frei.startable.map((t) => t.id), contains(ziel.id));
    });

    test('ein verworfener Blocker hält ebenfalls nichts mehr auf', () async {
      final blocker = await task('Rückruf abwarten');
      final ziel = await task('Termin bestätigen');
      await h.runtime
          .linkBlocker(blockerId: blocker.id, blockedId: ziel.id);

      await h.runtime.dropTask(blocker);
      expect((await h.runtime.evaluate()).isWaiting(ziel.id), isFalse);
    });

    test('eine wartende Aufgabe wird nicht zum Zerlegen angeboten', () async {
      // Sie zu zerlegen löst nichts — der Blocker hält auch die Teilschritte
      // auf. Angeboten gehört, was die Kette aufhält.
      final blocker = await task('Antrag ausdrucken', ae: 9, stakes: 9);
      final ziel = await task('Antrag abgeben', ae: 9, stakes: 9);
      await h.runtime
          .linkBlocker(blockerId: blocker.id, blockedId: ziel.id);

      final snapshot = await h.runtime.evaluate();
      final ids = snapshot.atomizeCandidates.map((c) => c.task.id);
      expect(ids, contains(blocker.id));
      expect(ids, isNot(contains(ziel.id)));
    });
  });

  group('Hebel (G2)', () {
    test('ein Blocker zieht an einer sonst stärkeren Aufgabe vorbei',
        () async {
      final blocker = await task('Ordner holen', ae: 1, stakes: 3);
      final andere = await task('Rechnung prüfen', ae: 1, stakes: 5);
      for (final titel in ['Belege', 'Formular', 'Abgabe']) {
        final wartend = await task(titel, ae: 1);
        await h.runtime
            .linkBlocker(blockerId: blocker.id, blockedId: wartend.id);
      }

      final snapshot = await h.runtime.evaluate();
      expect(snapshot.links.unblocks(blocker.id), 3);
      expect(snapshot.scoreOf(blocker),
          greaterThan(snapshot.scoreOf(andere)));
      // Aber nicht dreimal so viel: Der Hebel wächst logarithmisch.
      expect(snapshot.scoreOf(blocker),
          lessThan(snapshot.scoreOf(andere) * 2));
      expect(snapshot.startable.first.id, blocker.id);
    });

    test('der Hebel zählt transitiv, nicht nur direkt', () async {
      final a = await task('A');
      final b = await task('B');
      final c = await task('C');
      await h.runtime.linkBlocker(blockerId: a.id, blockedId: b.id);
      await h.runtime.linkBlocker(blockerId: b.id, blockedId: c.id);

      final snapshot = await h.runtime.evaluate();
      expect(snapshot.links.unblocks(a.id), 2);
      expect(snapshot.links.unblocks(b.id), 1);
    });
  });

  group('Zyklen', () {
    test('ein Kreis über drei Ecken wird abgelehnt — mit Grund', () async {
      final a = await task('A');
      final b = await task('B');
      final c = await task('C');
      await h.runtime.linkBlocker(blockerId: a.id, blockedId: b.id);
      await h.runtime.linkBlocker(blockerId: b.id, blockedId: c.id);

      try {
        await h.runtime.linkBlocker(blockerId: c.id, blockedId: a.id);
        fail('Der Kreis wurde nicht abgelehnt');
      } on TaskLinkCycleError catch (e) {
        expect(e.path, [c.id, a.id, b.id, c.id]);
      }

      // Und nichts davon ist hängen geblieben: kein halber Kreis, kein
      // Ereignis für eine Beziehung, die es nicht gibt.
      expect(await h.runtime.taskLinks(), hasLength(2));
      expect(
        await h.store.countSince(EventType.taskLinked, DateTime.utc(2000)),
        2,
      );
    });

    test('eine Beziehung auf eine unbekannte Aufgabe wird abgelehnt',
        () async {
      final a = await task('A');
      expect(
        () => h.runtime.linkBlocker(blockerId: a.id, blockedId: 'gibt-es-nicht'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('dieselbe Beziehung zweimal erzeugt kein zweites Ereignis', () async {
      final a = await task('A');
      final b = await task('B');
      await h.runtime.linkBlocker(blockerId: a.id, blockedId: b.id);
      await h.runtime.linkBlocker(blockerId: a.id, blockedId: b.id);

      expect(await h.runtime.taskLinks(), hasLength(1));
      expect(
        await h.store.countSince(EventType.taskLinked, DateTime.utc(2000)),
        1,
      );
    });
  });

  group('Lösen', () {
    test('ohne Blocker ist die Aufgabe sofort wieder startbar', () async {
      final blocker = await task('Ordner holen');
      final ziel = await task('Sortieren');
      await h.runtime
          .linkBlocker(blockerId: blocker.id, blockedId: ziel.id);
      expect((await h.runtime.evaluate()).isWaiting(ziel.id), isTrue);

      await h.runtime
          .unlinkBlocker(blockerId: blocker.id, blockedId: ziel.id);
      expect((await h.runtime.evaluate()).isWaiting(ziel.id), isFalse);
    });

    test('eine Beziehung übersteht den Wiederaufbau aus dem Ereignisstrom',
        () async {
      final blocker = await task('Ordner holen');
      final ziel = await task('Sortieren');
      await h.runtime
          .linkBlocker(blockerId: blocker.id, blockedId: ziel.id);

      await h.store.rebuildProjections();

      final snapshot = await h.runtime.evaluate();
      expect(snapshot.isWaiting(ziel.id), isTrue);
      expect(snapshot.blockersOf(ziel.id), [blocker.id]);
    });
  });

  group('Auf dem Telefon', () {
    /// Scrollt, bis [target] im Bild ist. Eine Liste baut nur, was sichtbar
    /// ist — ohne das prueft der Test die Bildschirmhoehe, nicht die Ansicht.
    Future<void> scrollTo(WidgetTester tester, Finder target) async {
      await tester.scrollUntilVisible(
        target,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('die Aufgabenliste zeigt „Wartet" mit dem Grund',
        (tester) async {
      final blocker = await task('Ordner holen');
      final ziel = await task('Steuerunterlagen sortieren');
      await h.runtime
          .linkBlocker(blockerId: blocker.id, blockedId: ziel.id);

      await pumpPhone(tester, h.wrap(const TasksScreen()));

      expect(find.text('Wartet · 1'), findsOneWidget);
      expect(find.text('wartet auf: Ordner holen'), findsOneWidget);
      // Der Blocker zeigt seinen Hebel — die Zahl, aus der die Formel
      // rechnet, steht sichtbar da (G2).
      expect(find.text('HÄLT 1 AUF · HEBEL ×1.35'), findsOneWidget);
      // Und die Formel selbst steht einmal in der Ansicht.
      expect(find.textContaining('log2(1 + aufgehaltene)'), findsOneWidget);
    });

    testWidgets('eine wartende Aufgabe hat keinen „Anfangen"-Knopf',
        (tester) async {
      // Der Blocker läuft bereits — an ihm steht deshalb „Erledigt" statt
      // „Anfangen". Bleibt der Knopf trotzdem irgendwo stehen, kommt er von
      // der wartenden Aufgabe, und genau das darf nicht sein (G1).
      final blocker = await task('Ordner holen');
      final ziel = await task('Sortieren');
      await h.runtime
          .linkBlocker(blockerId: blocker.id, blockedId: ziel.id);
      await h.runtime.startTask(blocker);

      await pumpPhone(tester, h.wrap(const TasksScreen()));

      expect(find.text('wartet auf: Ordner holen'), findsOneWidget);
      expect(find.text('Anfangen'), findsNothing);
      // „Erledigt" bleibt: Was auf anderem Weg erledigt wurde, muss sich
      // eintragen lassen.
      expect(find.text('Erledigt'), findsWidgets);
    });

    testWidgets('mehrere Blocker nennen den ersten und zählen den Rest',
        (tester) async {
      final ziel = await task('Abgeben');
      for (final titel in ['Ordner holen', 'Belege prüfen', 'Formular']) {
        final blocker = await task(titel);
        await h.runtime
            .linkBlocker(blockerId: blocker.id, blockedId: ziel.id);
      }

      await pumpPhone(tester, h.wrap(const TasksScreen()));
      await scrollTo(tester, find.textContaining('wartet auf:'));

      // Drei Titel nebeneinander wären wieder eine Liste zur Auswahl — und
      // zu tun ist hier ohnehin nichts.
      expect(find.textContaining('und 2 weitere'), findsOneWidget);
    });

    testWidgets('wartet alles Offene, nennt die Hauptansicht den echten Grund',
        (tester) async {
      // „Zu groß für heute" wäre hier falsch: Die Startenergie hat damit
      // nichts zu tun. Einen falschen Grund zu nennen ist schlimmer als
      // keinen (G2).
      final blocker = await h.runtime.createTask(
        title: 'Rückruf abwarten',
        activationEnergy: 2,
        salience: 5,
        stakes: 5,
        state: TaskState.inbox,
      );
      final ziel = await task('Termin bestätigen');
      await h.runtime
          .linkBlocker(blockerId: blocker.id, blockedId: ziel.id);

      await pumpPhone(tester, h.wrap(const NowScreen()));

      expect(find.text('ALLES WARTET'), findsOneWidget);
      expect(find.textContaining('hängt an etwas anderem'), findsOneWidget);
      expect(find.textContaining('mehr Anlauf'), findsNothing);
      await unmount(tester);
    });

    testWidgets('ein zu großer Blocker wird zum Zerlegen angeboten',
        (tester) async {
      // Der Grund muss stimmen: „zu groß für heute" wäre hier falsch.
      final blocker = await task('Rückruf abwarten', ae: 2);
      final ziel = await task('Termin bestätigen');
      await h.runtime
          .linkBlocker(blockerId: blocker.id, blockedId: ziel.id);
      await h.runtime.startTask(blocker);
      await h.runtime.completeTask(blocker);
      // Jetzt ist das Ziel frei — Gegenprobe, dass der Zustand echt ist.
      expect((await h.runtime.evaluate()).startable, isNotEmpty);

      // Und nun der Fall, in dem alles Offene wartet.
      final b2 = await task('Antrag drucken', ae: 9);
      final z2 = await task('Antrag abgeben');
      await h.runtime.linkBlocker(blockerId: b2.id, blockedId: z2.id);
      await h.runtime.completeTask(ziel);

      await pumpPhone(tester, h.wrap(const NowScreen()));
      // Der Blocker ist zu groß — also bietet AXIOM ihn zum Zerlegen an,
      // statt das Warten zu vermelden. Auch das ist eine ausführbare
      // Handlung, und genau darum geht es (G1).
      expect(find.text('ZU GROSS FÜR HEUTE'), findsOneWidget);
      expect(find.text('Antrag drucken'), findsOneWidget);
      expect(find.textContaining('Antrag abgeben'), findsNothing);
      await unmount(tester);
    });
  });
}
