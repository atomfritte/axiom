import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

void main() {
  const monitor = LoadMonitor();
  final now = DateTime(2026, 8, 10, 12);

  group('Stufen haben reale Konsequenzen, nicht nur Farben [D1]', () {
    test('L0 lässt alles zu', () {
      final regime = monitor.regimeFor(LoadLevel.l0);
      expect(regime.hideOptional, isFalse);
      expect(regime.confirmNewCommitments, isFalse);
      expect(regime.maxFocusBlock, isNull);
    });

    test('L1 kürzt Fokusblöcke', () {
      expect(monitor.regimeFor(LoadLevel.l1).maxFocusBlock, isNotNull);
    });

    test('L2 verlangt Bestätigung für Neues', () {
      final regime = monitor.regimeFor(LoadLevel.l2);
      expect(regime.confirmNewCommitments, isTrue);
      expect(regime.maxSuggestedEnergy, isNotNull);
    });

    test('L3 blendet Optionales aus — bewusst unbequem', () {
      final regime = monitor.regimeFor(LoadLevel.l3);
      expect(regime.hideOptional, isTrue);
      expect(regime.maxSuggestedEnergy, lessThanOrEqualTo(4));
      expect(regime.minimumHold, const Duration(hours: 72));
    });

    test('die Einschränkungen verschärfen sich monoton', () {
      final energies = [
        LoadLevel.l1,
        LoadLevel.l2,
        LoadLevel.l3,
      ].map((l) => monitor.regimeFor(l).maxFocusBlock!).toList();
      for (var i = 1; i < energies.length; i++) {
        expect(energies[i], lessThan(energies[i - 1]));
      }
    });
  });

  group('Haltezeit verhindert Flackern', () {
    test('nach oben wird sofort eskaliert', () {
      final level = monitor.effectiveLevel(
        measured: LoadLevel.l3,
        current: LoadLevel.l0,
        now: now,
        since: now.subtract(const Duration(minutes: 5)),
      );
      expect(level, LoadLevel.l3);
    });

    test('ein guter Tag beendet den Erhaltungsmodus nicht', () {
      final level = monitor.effectiveLevel(
        measured: LoadLevel.l0,
        current: LoadLevel.l3,
        now: now,
        since: now.subtract(const Duration(hours: 20)),
      );
      // Nach einer durchgeschlafenen Nacht ist die Erschöpfung noch da.
      expect(level, LoadLevel.l3);
    });

    test('nach abgelaufener Haltezeit darf er zurückfallen', () {
      final level = monitor.effectiveLevel(
        measured: LoadLevel.l0,
        current: LoadLevel.l3,
        now: now,
        since: now.subtract(const Duration(hours: 80)),
      );
      expect(level, LoadLevel.l0);
    });

    test('ohne Vorgeschichte gilt die Messung', () {
      expect(
        monitor.effectiveLevel(
          measured: LoadLevel.l2,
          current: null,
          now: now,
          since: null,
        ),
        LoadLevel.l2,
      );
    });
  });

  group('Abgrenzung zur Diagnostik (R10)', () {
    test('anhaltendes L3 legt professionelle Abklärung nahe', () {
      expect(
        monitor.suggestsReferral(
          level: LoadLevel.l3,
          since: now.subtract(const Duration(days: 20)),
          now: now,
        ),
        isTrue,
      );
    });

    test('kurzes L3 noch nicht', () {
      expect(
        monitor.suggestsReferral(
          level: LoadLevel.l3,
          since: now.subtract(const Duration(days: 3)),
          now: now,
        ),
        isFalse,
      );
    });

    test('niedrigere Stufen nie', () {
      expect(
        monitor.suggestsReferral(
          level: LoadLevel.l2,
          since: now.subtract(const Duration(days: 60)),
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('Sprache: Messung, kein Urteil (R7)', () {
    test('L3 wird als Systemerfolg formuliert', () {
      final text = monitor.regimeFor(LoadLevel.l3).description;
      expect(text, contains('nicht dein Versagen'));
    });

    test('kein Text enthält Schuldzuweisung oder Ausrufezeichen', () {
      for (final level in LoadLevel.values) {
        final regime = monitor.regimeFor(level);
        final combined = '${regime.headline} ${regime.description}';
        expect(combined, isNot(contains('!')));
        for (final blame in ['versagt', 'zu viel gemacht', 'schuld', 'faul']) {
          expect(combined.toLowerCase(), isNot(contains(blame)),
              reason: '${level.name}: $blame');
        }
      }
    });

    test('Eskalationstext nennt die konkrete Konsequenz', () {
      final text = monitor.escalationText(
        monitor.regimeFor(LoadLevel.l2),
        monitor.regimeFor(LoadLevel.l3),
      );
      expect(text, contains('72 Stunden'));
      expect(text, contains('soll es sein'));
    });

    test('Rückkehr in den Normalbereich wird schlicht gemeldet', () {
      expect(
        monitor.deescalationText(monitor.regimeFor(LoadLevel.l0)),
        contains('Normalbereich'),
      );
    });
  });
}
