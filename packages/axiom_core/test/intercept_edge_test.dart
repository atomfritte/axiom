/// Impuls-Abfang an den Raendern.
///
/// Der Abfang ist ein Vertrag mit dem Vergangenheits-Ich: eine Wartezeit,
/// die der Nutzer im ruhigen Zustand selbst gesetzt hat. Er darf deshalb
/// weder zu frueh freigeben (dann traegt er nicht) noch haengen bleiben
/// (dann wird er umgangen und danach nicht mehr benutzt). Hier stehen die
/// Kanten der Freigabe, die Faelle mit unbrauchbarer Uhrzeit und die
/// Statistik an ihren Schwellen.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

const Interceptor _interceptor = Interceptor();
final DateTime _abend = DateTime(2026, 8, 3, 22, 30);

InterceptTrigger _trigger({
  Duration cooldown = const Duration(minutes: 30),
  String? releaseAt,
  List<String> checklist = const ['Kannte ich das vor heute?'],
  bool authorized = true,
}) =>
    InterceptTrigger(
      id: 't1',
      label: 'Nachts etwas bestellen',
      cooldown: cooldown,
      releaseAt: releaseAt,
      checklist: checklist,
      authorized: authorized,
    );

InterceptRun _start({
  Duration cooldown = const Duration(minutes: 30),
  String? releaseAt,
  DateTime? now,
}) =>
    _interceptor.start(
      trigger: _trigger(cooldown: cooldown, releaseAt: releaseAt),
      now: now ?? _abend,
      id: 'r1',
    );

void main() {
  group('Freigabe nach einer Dauer', () {
    test('genau zur Freigabezeit ist die Wartezeit vorbei', () {
      final run = _start(cooldown: const Duration(minutes: 30));
      final freigabe = _abend.add(const Duration(minutes: 30));

      expect(run.isActive(freigabe.subtract(const Duration(seconds: 1))),
          isTrue);
      expect(run.isActive(freigabe), isFalse);
      expect(run.remaining(freigabe), Duration.zero);
    });

    test('eine Wartezeit von null gibt sofort frei', () {
      // Kann aus einem Trigger kommen, den der Nutzer auf null gestellt hat.
      // Ein Abfang, der nie endet, waere hier der schlimmere Fehler.
      final run = _start(cooldown: Duration.zero);
      expect(run.isActive(_abend), isFalse);
      expect(run.remaining(_abend), Duration.zero);
    });

    test('die Restzeit wird nie negativ', () {
      final run = _start(cooldown: const Duration(minutes: 30));
      expect(run.remaining(_abend.add(const Duration(days: 5))), Duration.zero);
    });

    test('ein entschiedener Abfang ist nicht mehr aktiv, auch wenn die Zeit '
        'noch laeuft', () {
      final run = _start(cooldown: const Duration(hours: 5));
      for (final outcome in InterceptOutcome.values) {
        final entschieden = InterceptRun(
          id: run.id,
          triggerId: run.triggerId,
          triggerLabel: run.triggerLabel,
          startedAt: run.startedAt,
          releasesAt: run.releasesAt,
          outcome: outcome,
        );
        expect(entschieden.isActive(_abend),
            outcome == InterceptOutcome.pending,
            reason: outcome.name);
      }
    });
  });

  group('Freigabe zu einer Uhrzeit — fuer Nachtentscheidungen', () {
    test('abends gesetzt gibt sie am naechsten Morgen frei', () {
      final run = _start(releaseAt: '09:00');
      expect(run.releasesAt, DateTime(2026, 8, 4, 9));
    });

    test('vormittags gesetzt bleibt sie am selben Tag', () {
      final run = _start(releaseAt: '18:00', now: DateTime(2026, 8, 3, 10));
      expect(run.releasesAt, DateTime(2026, 8, 3, 18));
    });

    test('genau zur Uhrzeit gesetzt schiebt auf den naechsten Tag', () {
      // Sonst waere der Abfang in der Sekunde vorbei, in der er beginnt.
      final run = _start(releaseAt: '09:00', now: DateTime(2026, 8, 3, 9));
      expect(run.releasesAt, DateTime(2026, 8, 4, 9));
      expect(run.isActive(DateTime(2026, 8, 3, 9)), isTrue);
    });

    test('die Uhrzeit schlaegt die Dauer', () {
      final run = _start(cooldown: const Duration(minutes: 5), releaseAt: '09:00');
      expect(run.releasesAt, DateTime(2026, 8, 4, 9));
    });

    test('eine Uhrzeit ohne Minuten wird als volle Stunde gelesen', () {
      expect(_start(releaseAt: '7').releasesAt, DateTime(2026, 8, 4, 7));
    });

    test('eine unlesbare Uhrzeit gibt trotzdem irgendwann frei', () {
      // Ein Abfang, der wegen eines Tippfehlers nie endet, waere ein
      // Verbot — und Verbote gibt es hier nicht (G3).
      for (final eingabe in ['abends', '::', 'neun uhr']) {
        final run = _start(releaseAt: eingabe);
        expect(run.releasesAt.isAfter(_abend), isTrue, reason: eingabe);
        expect(
            run.releasesAt.difference(_abend), lessThan(const Duration(days: 2)),
            reason: eingabe);
      }
    });
  });

  group('Der Wartetext beschreibt, ohne zu belehren (G3)', () {
    test('unter zwei Stunden nennt er die Minuten', () {
      final run = _start(cooldown: const Duration(minutes: 45));
      final phrase = _interceptor.waitingPhrase(run, _abend);
      expect(phrase.args, [45]);
      expect(phrase.text, contains('45'));
    });

    test('ab zwei Stunden nennt er die Uhrzeit statt der Minuten', () {
      final run = _start(cooldown: const Duration(hours: 2));
      final phrase = _interceptor.waitingPhrase(run, _abend);
      expect(phrase.args, ['00:30']);
      expect(phrase.text, contains('00:30'));
    });

    test('genau an der Grenze gilt die Uhrzeit-Form', () {
      final knappDarunter = _interceptor.waitingPhrase(
          _start(cooldown: const Duration(hours: 1, minutes: 59)), _abend);
      final genau = _interceptor.waitingPhrase(
          _start(cooldown: const Duration(hours: 2)), _abend);
      expect(knappDarunter.args.single, isA<int>());
      expect(genau.args.single, isA<String>());
    });

    test('nach Ablauf gehoert die Entscheidung dem Nutzer', () {
      final run = _start(cooldown: const Duration(minutes: 30));
      final text = _interceptor
          .waitingText(run, _abend.add(const Duration(hours: 1)));
      expect(text, contains('Deine Entscheidung'));
    });

    test('die Uhrzeit wird zweistellig geschrieben', () {
      // „Freigabe um 9:5" waere schlicht falsch zu lesen.
      final run = _start(cooldown: const Duration(hours: 3), now: DateTime(2026, 8, 3, 6, 2));
      expect(_interceptor.waitingPhrase(run, DateTime(2026, 8, 3, 6, 2)).args,
          ['09:02']);
    });

    test('kein Wartetext enthaelt Verbot, Moral oder Ausrufezeichen', () {
      final texte = [
        for (final cooldown in [
          Duration.zero,
          const Duration(minutes: 45),
          const Duration(hours: 5),
        ])
          _interceptor.waitingText(_start(cooldown: cooldown), _abend),
      ];
      for (final text in texte) {
        expect(text, isNot(contains('!')), reason: text);
        for (final wort in ['darfst nicht', 'verboten', 'solltest', 'schwach']) {
          expect(text.toLowerCase(), isNot(contains(wort)), reason: text);
        }
      }
    });
  });

  group('Ein Trigger ohne Prueffragen ist kein Vertrag', () {
    test('ohne Checkliste ungueltig', () {
      expect(_trigger(checklist: const []).isValid, isFalse);
    });

    test('ohne Bezeichnung ungueltig', () {
      expect(
        const InterceptTrigger(
                id: 't',
                label: '   ',
                cooldown: Duration(minutes: 10),
                checklist: ['Frage?'])
            .isValid,
        isFalse,
      );
    });

    test('mit beidem gueltig', () {
      expect(_trigger().isValid, isTrue);
    });

    test('die Vorlagen sind Fragen, keine Anweisungen', () {
      // Eine fremde Frage wird weggeklickt, die eigene beantwortet — die
      // Vorlagen duerfen deshalb nicht wie Vorschriften klingen.
      expect(kChecklistSeeds, isNotEmpty);
      for (final seed in kChecklistSeeds) {
        expect(seed, endsWith('?'), reason: seed);
        expect(seed, isNot(contains('!')), reason: seed);
      }
    });

    test('nicht autorisiert ist der Ausgangszustand', () {
      // Ohne ausdrueckliche Freigabe im ruhigen Zustand darf ein Trigger
      // nicht verbindlich laufen.
      const trigger = InterceptTrigger(
          id: 't', label: 'x', cooldown: Duration(minutes: 10));
      expect(trigger.authorized, isFalse);
    });
  });

  group('Statistik zaehlt, ohne zu werten', () {
    InterceptStats stats({int aborted = 0, int proceeded = 0}) =>
        InterceptStats(
            triggerId: 't', started: aborted + proceeded, aborted: aborted, proceeded: proceeded);

    test('ohne Entscheidung keine erfundene Quote', () {
      expect(stats().holdRate, isNull);
      expect(stats().decided, 0);
      expect(stats().needsReview, isFalse);
    });

    test('die Quote ist der Anteil der gehaltenen an den entschiedenen', () {
      expect(stats(aborted: 3, proceeded: 1).holdRate, 0.75);
      expect(stats(aborted: 0, proceeded: 4).holdRate, 0.0);
    });

    test('ins Review erst ab vier Entscheidungen', () {
      // Drei Faelle sind kein Muster.
      expect(stats(aborted: 0, proceeded: 3).needsReview, isFalse);
      expect(stats(aborted: 0, proceeded: 4).needsReview, isTrue);
    });

    test('und erst unter dreissig Prozent Haltequote', () {
      // Genau 0.3 zaehlt noch nicht — die Grenze liegt darunter.
      expect(stats(aborted: 3, proceeded: 7).holdRate, 0.3);
      expect(stats(aborted: 3, proceeded: 7).needsReview, isFalse);
      expect(stats(aborted: 2, proceeded: 8).needsReview, isTrue);
    });

    test('ein Trigger, der immer haelt, kommt nie ins Review', () {
      expect(stats(aborted: 20).needsReview, isFalse);
    });
  });

  group('Beantwortete Fragen', () {
    test('gezaehlt werden nur die bejahten', () {
      final run = InterceptRun(
        id: 'r',
        triggerId: 't',
        triggerLabel: 'x',
        startedAt: _abend,
        releasesAt: _abend.add(const Duration(minutes: 30)),
        answers: const [true, false, true],
      );
      expect(run.answered, 2);
    });

    test('mehr Antworten als Fragen brechen nicht', () {
      // Kann aus einem Import kommen, in dem die Checkliste inzwischen
      // kuerzer ist. Eine Ausnahme beim Anzeigen waere die teuerste Antwort.
      final run = InterceptRun(
        id: 'r',
        triggerId: 't',
        triggerLabel: 'x',
        startedAt: _abend,
        releasesAt: _abend,
        answers: const [true, true, true, true, true],
      );
      expect(run.answered, 5);
    });

    test('ohne Antworten null — ohne Wertung', () {
      expect(_start().answered, 0);
      expect(_start().note, isNull);
      expect(_start().outcome, InterceptOutcome.pending);
    });
  });

  test('Determinismus: gleicher Start, gleiche Freigabe', () {
    expect(_start().releasesAt, _start().releasesAt);
    expect(_start(releaseAt: '09:00').releasesAt,
        _start(releaseAt: '09:00').releasesAt);
  });
}
