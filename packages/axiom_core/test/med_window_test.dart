import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

void main() {
  const module = MedWindow();
  final morning = DateTime(2026, 8, 10, 8);

  MedEntry entryOf({
    Duration onset = const Duration(minutes: 30),
    Duration duration = const Duration(hours: 6),
  }) =>
      MedEntry(
        id: 'm1',
        label: 'Morgens',
        takenAt: morning,
        onset: onset,
        duration: duration,
      );

  group('Abgrenzung ist Teil des Moduls (R10)', () {
    test('standardmaessig aus', () {
      const state = MedWindowState();
      expect(state.enabled, isFalse);
      expect(state.hasActiveWindow, isFalse);
    });

    test('ausgeschaltet gibt es keinen Kapazitaetsbonus', () {
      expect(
        module.capacityBonusAt(
          state: MedWindowState(enabled: false, active: entryOf()),
          at: morning.add(const Duration(hours: 2)),
        ),
        0,
      );
    });

    test('der Hinweistext nennt die Grenze ausdruecklich', () {
      expect(kMedDisclaimer, contains('protokolliert nur'));
      expect(kMedDisclaimer, contains('keine Dosis'));
      expect(kMedDisclaimer, contains('Arzt'));
    });

    test('kein Text des Moduls enthaelt eine Empfehlung', () {
      final texts = [
        kMedDisclaimer,
        module.describe(const MedWindowState(), morning),
        module.describe(
            MedWindowState(enabled: true, active: entryOf()), morning),
        module.describe(
          MedWindowState(enabled: true, active: entryOf()),
          morning.add(const Duration(hours: 2)),
        ),
      ];
      for (final text in texts) {
        for (final word in ['nimm', 'solltest', 'empfohlen', 'erhöhe', 'dosis von']) {
          expect(text.toLowerCase(), isNot(contains(word)), reason: text);
        }
      }
    });
  });

  group('Fenster', () {
    test('beginnt nach der Anlaufzeit', () {
      final entry = entryOf();
      expect(entry.isInWindow(morning), isFalse);
      expect(entry.isInWindow(morning.add(const Duration(minutes: 45))), isTrue);
    });

    test('endet nach der eingetragenen Dauer', () {
      final entry = entryOf();
      expect(entry.isInWindow(morning.add(const Duration(hours: 6))), isTrue);
      expect(entry.isInWindow(morning.add(const Duration(hours: 7))), isFalse);
    });

    test('ohne eingetragene Dauer gibt es kein Fenster', () {
      final entry = entryOf(duration: Duration.zero);
      expect(entry.hasWindow, isFalse);
      expect(entry.isInWindow(morning.add(const Duration(hours: 1))), isFalse);
    });

    test('Restzeit wird nie negativ', () {
      expect(entryOf().remaining(morning.add(const Duration(hours: 20))),
          Duration.zero);
    });

    test('findet den aktiven Eintrag unter mehreren', () {
      final entries = [
        MedEntry(
          id: 'frueh',
          label: 'Morgens',
          takenAt: morning,
          onset: const Duration(minutes: 30),
          duration: const Duration(hours: 4),
        ),
        MedEntry(
          id: 'mittag',
          label: 'Mittags',
          takenAt: morning.add(const Duration(hours: 6)),
          onset: const Duration(minutes: 30),
          duration: const Duration(hours: 4),
        ),
      ];
      expect(
        module.activeAt(entries, morning.add(const Duration(hours: 2)))?.id,
        'frueh',
      );
      expect(
        module.activeAt(entries, morning.add(const Duration(hours: 8)))?.id,
        'mittag',
      );
      expect(
        module.activeAt(entries, morning.add(const Duration(hours: 20))),
        isNull,
      );
    });
  });

  group('Kapazitaetsbonus bleibt klein', () {
    test('im Fenster wirkt er, ausserhalb nicht', () {
      final state = MedWindowState(enabled: true, active: entryOf());
      expect(
        module.capacityBonusAt(
            state: state, at: morning.add(const Duration(hours: 2))),
        kMedWindowBonus,
      );
      expect(
        module.capacityBonusAt(
            state: state, at: morning.add(const Duration(hours: 9))),
        0,
      );
    });

    test('er ist bewusst klein — keine vorgetaeuschte Genauigkeit', () {
      // Ein grosser Bonus wuerde die Kapazitaetsformel von einer Einnahme
      // abhaengig machen statt von gemessenen Signalen.
      expect(kMedWindowBonus, lessThanOrEqualTo(10));
    });
  });

  group('Beschreibung ist sachlich', () {
    test('nennt die Restzeit ohne Wertung', () {
      final text = module.describe(
        MedWindowState(enabled: true, active: entryOf()),
        morning.add(const Duration(hours: 5)),
      );
      expect(text, contains('läuft noch'));
    });

    test('unterscheidet aus, kein Fenster und ausserhalb', () {
      expect(module.describe(const MedWindowState(), morning), contains('aus'));
      expect(
        module.describe(const MedWindowState(enabled: true), morning),
        contains('Kein Fenster'),
      );
      expect(
        module.describe(
          MedWindowState(enabled: true, active: entryOf()),
          morning.add(const Duration(hours: 12)),
        ),
        contains('Außerhalb'),
      );
    });
  });
}
