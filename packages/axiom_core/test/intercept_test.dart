import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

void main() {
  const interceptor = Interceptor();
  final now = DateTime(2026, 8, 3, 23, 40);

  InterceptTrigger triggerOf({
    Duration cooldown = const Duration(minutes: 15),
    String? releaseAt,
    List<String> checklist = const ['Kannte ich das vor heute?'],
    bool authorized = true,
  }) =>
      InterceptTrigger(
        id: 'purchase',
        label: 'Anschaffung über 200 €',
        cooldown: cooldown,
        releaseAt: releaseAt,
        checklist: checklist,
        authorized: authorized,
      );

  group('Cooldown [D5]', () {
    test('läuft ab der eingestellten Dauer', () {
      final run = interceptor.start(
        trigger: triggerOf(),
        now: now,
        id: 'r1',
      );
      expect(run.releasesAt, now.add(const Duration(minutes: 15)));
      expect(run.isActive(now), isTrue);
      expect(run.isActive(now.add(const Duration(minutes: 20))), isFalse);
    });

    test('Uhrzeit-Freigabe schiebt auf den nächsten Morgen', () {
      // Um 23:40 gestartet, Freigabe 09:00 — das ist morgen.
      final run = interceptor.start(
        trigger: triggerOf(releaseAt: '09:00'),
        now: now,
        id: 'r1',
      );
      expect(run.releasesAt.day, now.day + 1);
      expect(run.releasesAt.hour, 9);
    });

    test('Uhrzeit-Freigabe bleibt heute, wenn sie noch bevorsteht', () {
      final morning = DateTime(2026, 8, 3, 7, 30);
      final run = interceptor.start(
        trigger: triggerOf(releaseAt: '09:00'),
        now: morning,
        id: 'r1',
      );
      expect(run.releasesAt.day, morning.day);
    });

    test('Restzeit wird nie negativ', () {
      final run = interceptor.start(trigger: triggerOf(), now: now, id: 'r1');
      expect(run.remaining(now.add(const Duration(hours: 5))), Duration.zero);
    });
  });

  group('Wartetext beschreibt, ohne zu belehren (G3)', () {
    test('kurze Wartezeit nennt die Minuten', () {
      final run = interceptor.start(trigger: triggerOf(), now: now, id: 'r1');
      final text = interceptor.waitingText(
        run,
        now.add(const Duration(minutes: 5)),
      );
      expect(text, contains('10 min'));
    });

    test('lange Wartezeit nennt die Uhrzeit', () {
      final run = interceptor.start(
        trigger: triggerOf(releaseAt: '09:00'),
        now: now,
        id: 'r1',
      );
      expect(interceptor.waitingText(run, now), contains('09:00'));
    });

    test('nach Ablauf gehört die Entscheidung dem Nutzer', () {
      final run = interceptor.start(trigger: triggerOf(), now: now, id: 'r1');
      final text = interceptor.waitingText(
        run,
        now.add(const Duration(hours: 1)),
      );
      expect(text, contains('Deine Entscheidung'));
    });

    test('enthält keine Moral und kein Verbot', () {
      final run = interceptor.start(trigger: triggerOf(), now: now, id: 'r1');
      for (final moment in [now, now.add(const Duration(minutes: 10))]) {
        final text = interceptor.waitingText(run, moment).toLowerCase();
        for (final word in ['darfst nicht', 'verboten', 'solltest', 'falsch']) {
          expect(text, isNot(contains(word)));
        }
      }
    });
  });

  group('Trigger-Gültigkeit', () {
    test('ohne Prüffragen ungültig — die Checkliste ist der Vertrag', () {
      expect(triggerOf(checklist: const []).isValid, isFalse);
      expect(triggerOf().isValid, isTrue);
    });

    test('Vorlagen stehen bereit, sind aber keine Vorgabe', () {
      expect(kChecklistSeeds, isNotEmpty);
      for (final seed in kChecklistSeeds) {
        expect(seed.endsWith('?'), isTrue, reason: seed);
      }
    });
  });

  group('Statistik zählt, ohne zu werten', () {
    test('Haltequote aus entschiedenen Fällen', () {
      const stats = InterceptStats(
        triggerId: 'purchase',
        started: 10,
        aborted: 7,
        proceeded: 3,
      );
      expect(stats.holdRate, closeTo(0.7, 0.001));
      expect(stats.needsReview, isFalse);
    });

    test('ein Trigger, der fast nie hält, gehört ins Review', () {
      const stats = InterceptStats(
        triggerId: 'purchase',
        started: 8,
        aborted: 1,
        proceeded: 6,
      );
      // Kein Urteil über den Nutzer — der Trigger ist falsch geschnitten.
      expect(stats.needsReview, isTrue);
    });

    test('zu wenige Fälle ergeben noch kein Urteil', () {
      const stats = InterceptStats(
        triggerId: 'purchase',
        started: 2,
        aborted: 0,
        proceeded: 2,
      );
      expect(stats.needsReview, isFalse);
    });

    test('ohne Entscheidungen keine erfundene Quote', () {
      const stats = InterceptStats(triggerId: 'purchase', started: 3);
      expect(stats.holdRate, isNull);
    });
  });

  test('Determinismus: gleicher Start, gleiche Freigabe', () {
    final a = interceptor.start(trigger: triggerOf(), now: now, id: 'r1');
    final b = interceptor.start(trigger: triggerOf(), now: now, id: 'r2');
    expect(a.releasesAt, b.releasesAt);
  });
}
