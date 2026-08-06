/// Load Monitor an den Raendern.
///
/// Der Monitor ist das einzige Modul mit realen Konsequenzen im System —
/// er blendet aus, kuerzt Fokusbloecke und deckelt die Aktivierungsenergie.
/// Eine Stufe, die zur falschen Zeit greift oder zur falschen Zeit
/// zurueckfaellt, ist deshalb kein Anzeigefehler. Der vorhandene Test prueft
/// die Mitte; hier stehen die Uebergaenge auf die Stunde, die Faelle mit
/// mehreren Stufen auf einmal und die Zeit, die rueckwaerts laeuft.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

void main() {
  const monitor = LoadMonitor();
  final now = DateTime(2026, 8, 20, 12);

  LoadLevel effective({
    required LoadLevel measured,
    LoadLevel? current,
    Duration? held,
  }) =>
      monitor.effectiveLevel(
        measured: measured,
        current: current,
        now: now,
        since: held == null ? null : now.subtract(held),
      );

  group('Haltezeit — die Stunde entscheidet', () {
    test('L3 faellt genau nach 72 Stunden zurueck, keine Minute frueher', () {
      expect(
        effective(
            measured: LoadLevel.l0,
            current: LoadLevel.l3,
            held: const Duration(hours: 71, minutes: 59)),
        LoadLevel.l3,
      );
      expect(
        effective(
            measured: LoadLevel.l0,
            current: LoadLevel.l3,
            held: const Duration(hours: 72)),
        LoadLevel.l0,
      );
    });

    test('L2 haelt 24 Stunden', () {
      expect(
        effective(
            measured: LoadLevel.l0,
            current: LoadLevel.l2,
            held: const Duration(hours: 23, minutes: 59)),
        LoadLevel.l2,
      );
      expect(
        effective(
            measured: LoadLevel.l0,
            current: LoadLevel.l2,
            held: const Duration(hours: 24)),
        LoadLevel.l0,
      );
    });

    test('L1 haelt 12 Stunden', () {
      expect(
        effective(
            measured: LoadLevel.l0,
            current: LoadLevel.l1,
            held: const Duration(hours: 11, minutes: 59)),
        LoadLevel.l1,
      );
      expect(
        effective(
            measured: LoadLevel.l0,
            current: LoadLevel.l1,
            held: const Duration(hours: 12)),
        LoadLevel.l0,
      );
    });

    test('L0 haelt gar nicht — der Normalbetrieb sperrt nichts', () {
      expect(
        effective(
            measured: LoadLevel.l0, current: LoadLevel.l0, held: Duration.zero),
        LoadLevel.l0,
      );
      expect(monitor.regimeFor(LoadLevel.l0).minimumHold, Duration.zero);
    });

    test('die Haltezeit gilt fuer die geltende Stufe, nicht fuer die gemessene',
        () {
      // Von L3 auf L1 herunter: Es zaehlt die Haltezeit von L3 (72 h), nicht
      // die von L1 (12 h). Sonst waere der Erhaltungsmodus nach einem halben
      // Tag beendet, sobald die Messung nur auf L1 faellt.
      expect(
        effective(
            measured: LoadLevel.l1,
            current: LoadLevel.l3,
            held: const Duration(hours: 20)),
        LoadLevel.l3,
      );
    });

    test('gleich hoch gemessen heisst weiterlaufen, nicht neu anfangen', () {
      expect(
        effective(
            measured: LoadLevel.l2,
            current: LoadLevel.l2,
            held: const Duration(minutes: 1)),
        LoadLevel.l2,
      );
    });

    test('nach oben gibt es keine Haltezeit — auch nicht ueber zwei Stufen',
        () {
      expect(
        effective(
            measured: LoadLevel.l3,
            current: LoadLevel.l1,
            held: const Duration(minutes: 1)),
        LoadLevel.l3,
      );
    });

    test('ohne Zeitpunkt gilt die Messung, auch bei gesetzter Stufe', () {
      // Kann nach einem Import passieren. Die Messung ist dann die einzige
      // Angabe, der man trauen kann.
      expect(
        effective(measured: LoadLevel.l0, current: LoadLevel.l3),
        LoadLevel.l0,
      );
    });

    test('eine in der Zukunft gesetzte Stufe faellt nicht sofort zurueck', () {
      // Uhr umgestellt, Geraet gewechselt: Die Differenz wird negativ. Die
      // Stufe muss dann bleiben, nicht verschwinden — sie ist die
      // vorsichtigere Antwort.
      expect(
        monitor.effectiveLevel(
          measured: LoadLevel.l0,
          current: LoadLevel.l3,
          now: now,
          since: now.add(const Duration(days: 2)),
        ),
        LoadLevel.l3,
      );
    });
  });

  group('Konsequenzen verschaerfen sich monoton', () {
    test('jede Stufe ist mindestens so streng wie die darunter', () {
      final regimes = LoadLevel.values.map(monitor.regimeFor).toList();
      for (var i = 1; i < regimes.length; i++) {
        final vorher = regimes[i - 1];
        final jetzt = regimes[i];
        expect(jetzt.minimumHold, greaterThanOrEqualTo(vorher.minimumHold),
            reason: jetzt.level.name);
        if (vorher.maxFocusBlock != null) {
          expect(jetzt.maxFocusBlock, isNotNull, reason: jetzt.level.name);
          expect(jetzt.maxFocusBlock!, lessThanOrEqualTo(vorher.maxFocusBlock!),
              reason: jetzt.level.name);
        }
        if (vorher.maxSuggestedEnergy != null) {
          expect(jetzt.maxSuggestedEnergy, isNotNull, reason: jetzt.level.name);
          expect(jetzt.maxSuggestedEnergy!,
              lessThanOrEqualTo(vorher.maxSuggestedEnergy!),
              reason: jetzt.level.name);
        }
        if (vorher.hideOptional) {
          expect(jetzt.hideOptional, isTrue, reason: jetzt.level.name);
        }
        if (vorher.confirmNewCommitments) {
          expect(jetzt.confirmNewCommitments, isTrue,
              reason: jetzt.level.name);
        }
      }
    });

    test('der Normalbetrieb schraenkt nichts ein', () {
      final l0 = monitor.regimeFor(LoadLevel.l0);
      expect(l0.hideOptional, isFalse);
      expect(l0.confirmNewCommitments, isFalse);
      expect(l0.maxFocusBlock, isNull);
      expect(l0.maxSuggestedEnergy, isNull);
    });

    test('jede Stufe hat ihre eigene Beschreibung', () {
      final texte = LoadLevel.values
          .map((l) => monitor.regimeFor(l).headline)
          .toSet();
      expect(texte, hasLength(LoadLevel.values.length));
      for (final level in LoadLevel.values) {
        expect(monitor.regimeFor(level).level, level);
        expect(monitor.regimeFor(level).description, isNotEmpty);
      }
    });
  });

  group('Hinweis auf Abklaerung — genau ab 14 Tagen (R10)', () {
    bool referral(LoadLevel level, Duration held) => monitor.suggestsReferral(
          level: level,
          since: now.subtract(held),
          now: now,
        );

    test('am 13. Tag noch nicht, am 14. schon', () {
      expect(referral(LoadLevel.l3, const Duration(days: 13, hours: 23)),
          isFalse);
      expect(referral(LoadLevel.l3, const Duration(days: 14)), isTrue);
      expect(referral(LoadLevel.l3, const Duration(days: 100)), isTrue);
    });

    test('nur im Erhaltungsmodus, nie darunter', () {
      for (final level in [LoadLevel.l0, LoadLevel.l1, LoadLevel.l2]) {
        expect(referral(level, const Duration(days: 100)), isFalse,
            reason: level.name);
      }
    });

    test('ohne Zeitpunkt kein Hinweis — geraten wird hier nicht', () {
      expect(
        monitor.suggestsReferral(
            level: LoadLevel.l3, since: null, now: now),
        isFalse,
      );
    });

    test('die Schwelle steht als benannte Konstante da', () {
      // Sie steht in CLAUDE.md und in docs/. Eine Zahl im Quelltext waere
      // dieselbe Angabe an zweiter Stelle.
      expect(kL3DaysBeforeReferral, 14);
    });
  });

  group('Sprache — Messung, kein Urteil (R7)', () {
    test('kein Text nennt Schuld, Vergleich oder Ausrufezeichen', () {
      final texte = <String>[
        for (final level in LoadLevel.values) ...[
          monitor.regimeFor(level).headline,
          monitor.regimeFor(level).description,
          monitor.deescalationText(monitor.regimeFor(level)),
          monitor.escalationText(
              monitor.regimeFor(LoadLevel.l0), monitor.regimeFor(level)),
        ],
      ];
      for (final text in texte) {
        expect(text, isNot(contains('!')), reason: text);
        for (final wort in [
          'versagt',
          'schuld',
          'schon wieder',
          'endlich',
          'besser als',
          'schlechter als',
        ]) {
          expect(text.toLowerCase(), isNot(contains(wort)), reason: text);
        }
      }
    });

    test('der Erhaltungsmodus sagt ausdruecklich, dass er kein Versagen ist',
        () {
      final text = monitor.regimeFor(LoadLevel.l3).description;
      expect(text, contains('nicht dein Versagen'));
    });

    test('die Eskalation nach L3 nennt die Dauer und die Konsequenz', () {
      final text = monitor.escalationText(
          monitor.regimeFor(LoadLevel.l1), monitor.regimeFor(LoadLevel.l3));
      expect(text, contains('72'));
      expect(text, contains('Fokusblöcke'));
      // Unbequem und offen dazu — nicht dramatisiert.
      expect(text, contains('soll'));
    });

    test('die Eskalation auf L1 und L2 beschreibt den Zustand', () {
      for (final level in [LoadLevel.l1, LoadLevel.l2]) {
        final text = monitor.escalationText(
            monitor.regimeFor(LoadLevel.l0), monitor.regimeFor(level));
        expect(text, contains(monitor.regimeFor(level).headline));
        expect(text, contains(monitor.regimeFor(level).description));
      }
    });

    test('die Rueckkehr in den Normalbereich wird schlicht gemeldet', () {
      expect(monitor.deescalationText(monitor.regimeFor(LoadLevel.l0)),
          contains('Normalbereich'));
      expect(monitor.deescalationText(monitor.regimeFor(LoadLevel.l1)),
          contains('Last erhöht'));
    });
  });

  test('Determinismus: dieselbe Lage, dieselbe Stufe und derselbe Text', () {
    for (final level in LoadLevel.values) {
      expect(
        effective(
            measured: LoadLevel.l0, current: level, held: const Duration(hours: 20)),
        effective(
            measured: LoadLevel.l0, current: level, held: const Duration(hours: 20)),
        reason: level.name,
      );
      expect(monitor.deescalationText(monitor.regimeFor(level)),
          monitor.deescalationText(monitor.regimeFor(level)));
    }
  });
}
