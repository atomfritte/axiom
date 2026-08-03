import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

void main() {
  const ledger = SensationLedger();
  final at = DateTime(2026, 8, 3, 14);

  SensationSlot slotOf({
    String id = 's1',
    int intensity = 4,
    int minutes = 30,
    bool planned = true,
  }) =>
      SensationSlot(
        id: id,
        channelId: 'sport',
        channelLabel: 'Sport, hart',
        intensity: intensity,
        at: at,
        duration: Duration(minutes: minutes),
        planned: planned,
      );

  group('Vorschlag passt zur Bedarfshöhe [D5]', () {
    test('sehr hoher Bedarf verlangt hohe Intensität', () {
      final channel = ledger.suggest(
        sensationNeed: 90,
        channels: kDefaultChannels,
        available: const Duration(hours: 2),
      );
      expect(channel, isNotNull);
      expect(channel!.intensity, greaterThanOrEqualTo(4));
    });

    test('mittlerer Bedarf bekommt keinen Wettkampf vorgesetzt', () {
      final channel = ledger.suggest(
        sensationNeed: 55,
        channels: kDefaultChannels,
        available: const Duration(hours: 2),
      );
      expect(channel!.intensity, lessThanOrEqualTo(4));
    });

    test('respektiert das verfügbare Zeitfenster', () {
      final channel = ledger.suggest(
        sensationNeed: 90,
        channels: kDefaultChannels,
        available: const Duration(minutes: 10),
      );
      expect(channel, isNotNull);
      expect(channel!.typical, lessThanOrEqualTo(const Duration(minutes: 10)));
    });

    test('ohne passendes Zeitfenster lieber nichts vorschlagen', () {
      final channel = ledger.suggest(
        sensationNeed: 90,
        channels: kDefaultChannels,
        available: const Duration(minutes: 2),
      );
      expect(channel, isNull);
    });

    test('kostspielige Kanäle bleiben außen vor, wenn nicht freigegeben', () {
      const risky = SensationChannel(
        id: 'shopping',
        label: 'Etwas Neues kaufen',
        intensity: 5,
        typical: Duration(minutes: 20),
        hasCost: true,
      );
      expect(
        ledger.suggest(
          sensationNeed: 95,
          channels: const [risky],
          available: const Duration(hours: 1),
        ),
        isNull,
      );
      expect(
        ledger.suggest(
          sensationNeed: 95,
          channels: const [risky],
          available: const Duration(hours: 1),
          allowCostly: true,
        ),
        isNotNull,
      );
    });

    test('deterministisch — gleicher Bedarf, gleicher Kanal (G2)', () {
      final a = ledger.suggest(
        sensationNeed: 75,
        channels: kDefaultChannels,
        available: const Duration(hours: 1),
      );
      final b = ledger.suggest(
        sensationNeed: 75,
        channels: kDefaultChannels,
        available: const Duration(hours: 1),
      );
      expect(a!.id, b!.id);
    });
  });

  group('Slot als Währung', () {
    test('Niedrigreiz-Arbeit verdient Hochreiz-Zeit', () {
      final budget = ledger.compute(focusMinutesToday: 90, slotsToday: []);
      expect(budget.earnedMinutes, 30);
      expect(budget.hasCredit, isTrue);
    });

    test('geplante Slots verbrauchen das Guthaben', () {
      final budget = ledger.compute(
        focusMinutesToday: 180,
        slotsToday: [slotOf(minutes: 45)],
      );
      expect(budget.earnedMinutes, 60);
      expect(budget.spentMinutes, 45);
      expect(budget.availableMinutes, 15);
    });

    test('ungeplante Slots kosten kein Guthaben', () {
      // Sie werden gezählt (K4), aber nicht bestraft — sonst wäre der
      // Haushalt ein Schuldenkonto, und das trifft genau die falsche Stelle.
      final budget = ledger.compute(
        focusMinutesToday: 90,
        slotsToday: [slotOf(minutes: 60, planned: false)],
      );
      expect(budget.spentMinutes, 0);
      expect(budget.availableMinutes, 30);
    });

    test('Guthaben wird nicht negativ', () {
      final budget = ledger.compute(
        focusMinutesToday: 0,
        slotsToday: [slotOf(minutes: 60)],
      );
      expect(budget.availableMinutes, 0);
      expect(budget.hasCredit, isFalse);
    });
  });

  group('Entlastung', () {
    test('intensiver und längerer Slot entlastet mehr', () {
      expect(slotOf(intensity: 5, minutes: 60).relief,
          greaterThan(slotOf(intensity: 2, minutes: 15).relief));
    });
  });

  group('Voreingestellte Kanäle', () {
    test('sind körperlich und sofort verfügbar', () {
      expect(kDefaultChannels, isNotEmpty);
      for (final channel in kDefaultChannels) {
        expect(channel.intensity, inInclusiveRange(1, 5));
        expect(channel.label, isNotEmpty);
      }
    });

    test('enthalten keinen riskanten Kanal ab Werk', () {
      // Riskante Kanäle trägt der Nutzer selbst ein — im ruhigen Zustand.
      expect(kDefaultChannels.any((c) => c.hasCost), isFalse);
    });
  });
}
