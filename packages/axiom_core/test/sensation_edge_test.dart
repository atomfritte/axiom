/// Reiz-Haushalt an den Raendern.
///
/// Der Vorschlag ist die einzige Stelle, an der AXIOM einen Kanal nennt —
/// und der Kommentar an `suggest` sagt zu, dass er ohne Zufall zustande
/// kommt (G2). Hier stehen die Schwellen der Bedarfshoehe auf den Punkt, das
/// Zeitfenster an seiner Kante und das Guthaben an seinen beiden Enden.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

const SensationLedger _ledger = SensationLedger();

SensationChannel _channel(
  String id, {
  required int intensity,
  Duration typical = const Duration(minutes: 20),
  bool hasCost = false,
}) =>
    SensationChannel(
      id: id,
      label: 'Kanal $id',
      intensity: intensity,
      typical: typical,
      hasCost: hasCost,
    );

/// Ein Kanal je Intensitaetsstufe, alle gleich lang und alle unbedenklich.
final List<SensationChannel> _leiter = [
  for (var i = 1; i <= 5; i++) _channel('i$i', intensity: i),
];

String? _suggest(int need, {Duration available = const Duration(hours: 2)}) =>
    _ledger
        .suggest(
          sensationNeed: need,
          channels: _leiter,
          available: available,
        )
        ?.id;

void main() {
  group('Die Bedarfshoehe waehlt die Intensitaet — Schwellen genau', () {
    test('ab 85 die hoechste', () {
      expect(_suggest(84), 'i4');
      expect(_suggest(85), 'i5');
      expect(_suggest(100), 'i5');
    });

    test('ab 70 die vierte', () {
      expect(_suggest(69), 'i3');
      expect(_suggest(70), 'i4');
    });

    test('ab 50 die dritte', () {
      expect(_suggest(49), 'i2');
      expect(_suggest(50), 'i3');
    });

    test('darunter die zweite', () {
      expect(_suggest(0), 'i2');
      expect(_suggest(49), 'i2');
    });

    test('gibt es die gewuenschte Stufe nicht, kommt die naechstliegende', () {
      // Ein leiser Kanal deckt keinen lauten Bedarf — aber gar kein
      // Vorschlag deckt ihn erst recht nicht.
      final nurLeise = [_channel('a', intensity: 1), _channel('b', intensity: 2)];
      expect(
        _ledger
            .suggest(
              sensationNeed: 95,
              channels: nurLeise,
              available: const Duration(hours: 2),
            )!
            .id,
        'b',
      );
    });

    test('die Wahl ist monoton: mehr Bedarf, nie weniger Intensitaet', () {
      var vorher = 0;
      for (var need = 0; need <= 100; need += 5) {
        final gewaehlt = _leiter
            .firstWhere((c) => c.id == _suggest(need))
            .intensity;
        expect(gewaehlt, greaterThanOrEqualTo(vorher), reason: 'Bedarf $need');
        vorher = gewaehlt;
      }
    });
  });

  group('Das Zeitfenster begrenzt hart', () {
    test('ein Kanal, der genau hineinpasst, zaehlt noch', () {
      final channels = [_channel('a', intensity: 3, typical: const Duration(minutes: 30))];
      expect(
        _ledger.suggest(
            sensationNeed: 55,
            channels: channels,
            available: const Duration(minutes: 30)),
        isNotNull,
      );
      expect(
        _ledger.suggest(
            sensationNeed: 55,
            channels: channels,
            available: const Duration(minutes: 29)),
        isNull,
      );
    });

    test('passt nichts, wird nichts vorgeschlagen', () {
      // Lieber schweigen als etwas anbieten, das gerade nicht geht.
      expect(_suggest(90, available: Duration.zero), isNull);
    });

    test('ohne Kanaele gibt es nichts vorzuschlagen', () {
      expect(
        _ledger.suggest(
            sensationNeed: 90,
            channels: const [],
            available: const Duration(hours: 2)),
        isNull,
      );
    });

    test('bei gleicher Passung gewinnt der kuerzere — er ist eher machbar',
        () {
      final channels = [
        _channel('lang', intensity: 3, typical: const Duration(minutes: 60)),
        _channel('kurz', intensity: 3, typical: const Duration(minutes: 10)),
      ];
      expect(
        _ledger
            .suggest(
                sensationNeed: 55,
                channels: channels,
                available: const Duration(hours: 2))!
            .id,
        'kurz',
      );
    });
  });

  group('Kostspielige Kanaele bleiben aussen vor, solange nichts anderes gilt',
      () {
    final channels = [
      _channel('teuer', intensity: 5, hasCost: true),
      _channel('harmlos', intensity: 2),
    ];

    test('ohne Freigabe wird der harmlose genommen, auch wenn er schlechter '
        'passt', () {
      expect(
        _ledger
            .suggest(
                sensationNeed: 95,
                channels: channels,
                available: const Duration(hours: 2))!
            .id,
        'harmlos',
      );
    });

    test('mit Freigabe zaehlt wieder die Passung', () {
      expect(
        _ledger
            .suggest(
                sensationNeed: 95,
                channels: channels,
                available: const Duration(hours: 2),
                allowCostly: true)!
            .id,
        'teuer',
      );
    });

    test('gibt es nur kostspielige und keine Freigabe, kommt nichts', () {
      expect(
        _ledger.suggest(
            sensationNeed: 95,
            channels: [_channel('teuer', intensity: 5, hasCost: true)],
            available: const Duration(hours: 2)),
        isNull,
      );
    });
  });

  group('Guthaben — der Tauschhandel', () {
    test('drei Minuten Pflicht verdienen eine Minute Hochreiz', () {
      final budget = _ledger.compute(focusMinutesToday: 90, slotsToday: const []);
      expect(budget.earnedMinutes, 30);
      expect(budget.availableMinutes, 30);
      expect(budget.hasCredit, isTrue);
    });

    test('ohne Fokuszeit gibt es kein Guthaben', () {
      final budget = _ledger.compute(focusMinutesToday: 0, slotsToday: const []);
      expect(budget.earnedMinutes, 0);
      expect(budget.hasCredit, isFalse);
    });

    test('nur geplante Slots verbrauchen — ungeplante kosten nichts', () {
      // Sonst wuerde ein ungeplanter Ausbruch zusaetzlich bestraft, und
      // Bestrafung ist hier ausdruecklich nicht das Mittel (G3).
      SensationSlot slot(String id, {required bool planned}) => SensationSlot(
            id: id,
            channelId: 'sport',
            channelLabel: 'Sport',
            intensity: 5,
            at: DateTime(2026, 8, 3, 18),
            duration: const Duration(minutes: 20),
            planned: planned,
          );

      final budget = _ledger.compute(
        focusMinutesToday: 180,
        slotsToday: [slot('a', planned: true), slot('b', planned: false)],
      );
      expect(budget.earnedMinutes, 60);
      expect(budget.spentMinutes, 20);
      expect(budget.availableMinutes, 40);
    });

    test('das Guthaben wird nie negativ', () {
      const budget = SensationBudget(earnedMinutes: 10, spentMinutes: 100);
      expect(budget.availableMinutes, 0);
      expect(budget.hasCredit, isFalse);
    });

    test('genau aufgebraucht heisst kein Guthaben mehr', () {
      const budget = SensationBudget(earnedMinutes: 30, spentMinutes: 30);
      expect(budget.availableMinutes, 0);
      expect(budget.hasCredit, isFalse);
    });

    test('der Kurs steht als benannte Konstante da', () {
      expect(kEarnRate, closeTo(1 / 3, 0.0001));
    });
  });

  group('Entlastung', () {
    SensationSlot slot({required int intensity, required Duration duration}) =>
        SensationSlot(
          id: 's',
          channelId: 'c',
          channelLabel: 'C',
          intensity: intensity,
          at: DateTime(2026, 8, 3, 18),
          duration: duration,
          planned: true,
        );

    test('halbe Stunde bei Intensitaet 1 ist die Einheit', () {
      expect(
          slot(intensity: 1, duration: const Duration(minutes: 30)).relief, 1.0);
    });

    test('doppelt so intensiv oder doppelt so lang entlastet doppelt', () {
      final basis =
          slot(intensity: 2, duration: const Duration(minutes: 30)).relief;
      expect(slot(intensity: 4, duration: const Duration(minutes: 30)).relief,
          basis * 2);
      expect(slot(intensity: 2, duration: const Duration(minutes: 60)).relief,
          basis * 2);
    });

    test('ein Slot ohne Dauer entlastet nicht', () {
      expect(slot(intensity: 5, duration: Duration.zero).relief, 0.0);
    });
  });

  group('Voreingestellte Kanaele', () {
    test('keiner traegt ab Werk ein Folgerisiko', () {
      // Die riskanten traegt der Nutzer selbst ein, im ruhigen Zustand.
      for (final channel in kDefaultChannels) {
        expect(channel.hasCost, isFalse, reason: channel.id);
      }
    });

    test('jeder ist sofort verfuegbar und kurz genug fuer einen Abend', () {
      for (final channel in kDefaultChannels) {
        expect(channel.typical, lessThanOrEqualTo(const Duration(hours: 1)),
            reason: channel.id);
        expect(channel.intensity, inInclusiveRange(1, 5), reason: channel.id);
      }
    });

    test('die Kennungen sind eindeutig', () {
      expect(kDefaultChannels.map((c) => c.id).toSet(),
          hasLength(kDefaultChannels.length));
    });

    test('sie decken die obere Haelfte der Skala ab', () {
      // Ein Bedarf von 90 braucht einen Kanal, der ihn deckt — sonst sucht
      // er sich den schnellsten [D5].
      final vorschlag = _ledger.suggest(
        sensationNeed: 95,
        channels: kDefaultChannels,
        available: const Duration(hours: 2),
      );
      expect(vorschlag, isNotNull);
      expect(vorschlag!.intensity, 5);
    });
  });
}
