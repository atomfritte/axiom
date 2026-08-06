/// Signal-Log an den Raendern.
///
/// Zwei Zahlen entscheiden hier ueber das Verhalten: **wann** eine
/// Nachbetrachtung angeboten wird und **wie stark** ein Vorfall die
/// Regulationsreserve noch belastet. Zu frueh gefragt verlaengert das
/// Ereignis, statt es abzuschliessen; zu lange belastet heisst, dass ein
/// alter Streit heute noch Regeln ausloest. Beide Kurven werden hier an
/// ihren Kanten festgehalten.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

const SignalLog _log = SignalLog();
final DateTime _now = DateTime(2026, 8, 5, 12);

SignalIncident _incident(
  String id, {
  required Duration vor,
  int intensity = 3,
  TriggerClass triggerClass = TriggerClass.unclear,
}) =>
    SignalIncident(
      id: id,
      at: _now.subtract(vor),
      intensity: intensity,
      triggerClass: triggerClass,
    );

List<String> _due(List<SignalIncident> incidents,
        {Set<String> reviewed = const {}}) =>
    _log
        .awaitingPostMortem(
            incidents: incidents, reviewedIds: reviewed, now: _now)
        .map((i) => i.id)
        .toList();

void main() {
  group('Die Nachbetrachtung hat ein Fenster, keinen Zeitpunkt [D10]', () {
    test('genau nach zwoelf Stunden wird gefragt, keine Minute frueher', () {
      expect(
        _due([
          _incident('a', vor: kPostMortemDelay - const Duration(minutes: 1))
        ]),
        isEmpty,
      );
      expect(_due([_incident('a', vor: kPostMortemDelay)]), ['a']);
    });

    test('genau nach vier Tagen wird nicht mehr gefragt', () {
      // Danach ist die Erinnerung zu ungenau, und Nachfragen zu alten
      // Vorfaellen ist selbst eine Belastung.
      expect(_due([_incident('a', vor: kPostMortemWindow)]), ['a']);
      expect(
        _due([
          _incident('a', vor: kPostMortemWindow + const Duration(minutes: 1))
        ]),
        isEmpty,
      );
    });

    test('ein bereits betrachteter Vorfall verschwindet', () {
      final incidents = [
        _incident('a', vor: const Duration(days: 1)),
        _incident('b', vor: const Duration(days: 2)),
      ];
      expect(_due(incidents, reviewed: {'a'}), ['b']);
      expect(_due(incidents, reviewed: {'a', 'b'}), isEmpty);
    });

    test('ein Vorfall in der Zukunft wird nicht angeboten', () {
      // Uhr umgestellt oder Import. „In zwei Stunden" ist kein Alter.
      expect(_due([_incident('a', vor: const Duration(hours: -2))]), isEmpty);
    });

    test('aus einer leeren Liste kommt nichts', () {
      expect(_due(const []), isEmpty);
    });

    test('der staerkste zuerst, bei gleicher Staerke der aeltere', () {
      final incidents = [
        _incident('mittel', vor: const Duration(days: 1), intensity: 3),
        _incident('stark', vor: const Duration(days: 2), intensity: 5),
        _incident('mittel_alt', vor: const Duration(days: 3), intensity: 3),
      ];
      expect(_due(incidents), ['stark', 'mittel_alt', 'mittel']);
    });

    test('die Schwellen stehen als benannte Konstanten da', () {
      expect(kPostMortemDelay, const Duration(hours: 12));
      expect(kPostMortemWindow, const Duration(days: 4));
      expect(kPostMortemDelay, lessThan(kPostMortemWindow));
    });
  });

  group('Die Belastung klingt ab', () {
    double pressure(List<SignalIncident> incidents) =>
        _log.pressure(incidents: incidents, now: _now);

    test('ohne Vorfaelle ist sie null', () {
      expect(pressure(const []), 0);
    });

    test('sie faellt monoton mit dem Alter', () {
      var vorher = double.infinity;
      for (final stunden in [0, 6, 24, 48, 71, 72, 100]) {
        final jetzt =
            pressure([_incident('a', vor: Duration(hours: stunden), intensity: 5)]);
        expect(jetzt, lessThanOrEqualTo(vorher), reason: '$stunden h');
        vorher = jetzt;
      }
      expect(vorher, 0);
    });

    test('nach genau 72 Stunden zaehlt ein Vorfall nicht mehr', () {
      expect(
        pressure([_incident('a', vor: const Duration(hours: 72), intensity: 5)]),
        0,
      );
      expect(
        pressure([
          _incident('a',
              vor: const Duration(hours: 71, minutes: 59), intensity: 5)
        ]),
        greaterThan(0),
      );
    });

    test('ein Vorfall in der Zukunft belastet nicht', () {
      expect(
        pressure([_incident('a', vor: const Duration(hours: -1), intensity: 5)]),
        0,
      );
    });

    test('mehrere Vorfaelle summieren sich, aber nie ueber hundert', () {
      final viele = [
        for (var i = 0; i < 20; i++)
          _incident('i$i', vor: const Duration(hours: 1), intensity: 5),
      ];
      expect(pressure(viele), 100);
    });

    test('sie bleibt in 0..100, egal was hereinkommt', () {
      for (final intensity in [1, 3, 5]) {
        final wert =
            pressure([_incident('a', vor: Duration.zero, intensity: intensity)]);
        expect(wert, inInclusiveRange(0, 100), reason: 'Staerke $intensity');
      }
    });

    test('staerker getroffen heisst mehr Belastung', () {
      final schwach = pressure(
          [_incident('a', vor: const Duration(hours: 1), intensity: 1)]);
      final stark = pressure(
          [_incident('a', vor: const Duration(hours: 1), intensity: 5)]);
      expect(stark, greaterThan(schwach));
    });
  });

  group('Muster nach Ausloeserklasse', () {
    test('die haeufigste steht vorn, bei Gleichstand die Reihenfolge des '
        'Katalogs', () {
      final incidents = [
        _incident('a', vor: Duration.zero, triggerClass: TriggerClass.rejection),
        _incident('b', vor: Duration.zero, triggerClass: TriggerClass.rejection),
        _incident('c', vor: Duration.zero, triggerClass: TriggerClass.criticism),
        _incident('d', vor: Duration.zero, triggerClass: TriggerClass.ownError),
      ];
      final muster = _log.patterns(incidents);
      expect(muster.keys.first, TriggerClass.rejection);
      expect(muster[TriggerClass.rejection], 2);
      // criticism steht im Katalog vor ownError — bei gleicher Anzahl
      // entscheidet das, nicht die Reihenfolge der Eingabe.
      expect(muster.keys.toList().sublist(1),
          [TriggerClass.criticism, TriggerClass.ownError]);
    });

    test('die Reihenfolge haengt nicht an der Eingabe', () {
      final incidents = [
        _incident('a', vor: Duration.zero, triggerClass: TriggerClass.overload),
        _incident('b', vor: Duration.zero, triggerClass: TriggerClass.criticism),
      ];
      expect(_log.patterns(incidents).keys.toList(),
          _log.patterns(incidents.reversed.toList()).keys.toList());
    });

    test('ohne Vorfaelle ist die Aufstellung leer, nicht null', () {
      expect(_log.patterns(const []), isEmpty);
    });

    test('nicht vorgekommene Klassen tauchen nicht mit null auf', () {
      // Eine Klasse mit „0" laese sich wie eine Aussage — sie ist keine.
      final muster = _log.patterns(
          [_incident('a', vor: Duration.zero, triggerClass: TriggerClass.overload)]);
      expect(muster.keys, [TriggerClass.overload]);
    });

    test('jede Klasse hat Bezeichnung und Erlaeuterung, ohne Diagnosesprache',
        () {
      for (final klasse in TriggerClass.values) {
        expect(klasse.label, isNotEmpty, reason: klasse.name);
        expect(klasse.description, isNotEmpty, reason: klasse.name);
        expect(klasse.label, isNot(contains('!')), reason: klasse.name);
      }
      expect(TriggerClass.values.map((k) => k.label).toSet(),
          hasLength(TriggerClass.values.length));
    });
  });

  group('Rueckblick-Differenz — erst ab drei Faellen', () {
    PostMortem review(String incidentId, {int? hindsight}) => PostMortem(
          incidentId: incidentId,
          at: _now,
          rootCause: 'Ursache',
          intensityInHindsight: hindsight,
        );

    List<SignalIncident> incidents(int n, {int intensity = 5}) => [
          for (var i = 0; i < n; i++)
            _incident('i$i', vor: const Duration(days: 1), intensity: intensity),
        ];

    test('zwei Faelle ergeben noch keine Zahl', () {
      expect(
        _log.hindsightDelta(
          incidents: incidents(2),
          reviews: [review('i0', hindsight: 2), review('i1', hindsight: 3)],
        ),
        isNull,
      );
    });

    test('drei Faelle ergeben den Mittelwert', () {
      expect(
        _log.hindsightDelta(
          incidents: incidents(3),
          reviews: [
            review('i0', hindsight: 2),
            review('i1', hindsight: 3),
            review('i2', hindsight: 1),
          ],
        ),
        closeTo((3 + 2 + 4) / 3, 0.0001),
      );
    });

    test('Nachbetrachtungen ohne Rueckblickwert zaehlen nicht mit', () {
      expect(
        _log.hindsightDelta(
          incidents: incidents(4),
          reviews: [
            review('i0', hindsight: 2),
            review('i1', hindsight: 3),
            review('i2'),
            review('i3'),
          ],
        ),
        isNull,
      );
    });

    test('eine Nachbetrachtung ohne zugehoerigen Vorfall zaehlt nicht mit', () {
      // Kann nach einem Teilimport vorkommen. Sie darf den Mittelwert nicht
      // verschieben und schon gar nicht werfen.
      expect(
        _log.hindsightDelta(
          incidents: incidents(2),
          reviews: [
            review('i0', hindsight: 2),
            review('i1', hindsight: 2),
            review('gibt_es_nicht', hindsight: 1),
          ],
        ),
        isNull,
      );
    });

    test('ohne Vorfaelle und ohne Nachbetrachtungen kommt null', () {
      expect(
        _log.hindsightDelta(incidents: const [], reviews: const []),
        isNull,
      );
    });

    test('eine hoehere Bewertung im Rueckblick ergibt eine negative Zahl', () {
      // Kommt selten vor, ist aber moeglich — und wird nicht weggerundet.
      expect(
        _log.hindsightDelta(
          incidents: incidents(3, intensity: 1),
          reviews: [
            review('i0', hindsight: 3),
            review('i1', hindsight: 3),
            review('i2', hindsight: 3),
          ],
        ),
        -2,
      );
    });
  });

  group('Nachbetrachtung', () {
    test('gilt erst mit benannter Ursache als vollstaendig', () {
      expect(PostMortem(incidentId: 'i', at: _now).isComplete, isFalse);
      expect(PostMortem(incidentId: 'i', at: _now, rootCause: '   ').isComplete,
          isFalse);
      expect(
        PostMortem(incidentId: 'i', at: _now, rootCause: 'Zu wenig Schlaf')
            .isComplete,
        isTrue,
      );
    });

    test('die Gegenmassnahme ist optional — sie faellt oft erst spaeter ein',
        () {
      expect(
        PostMortem(incidentId: 'i', at: _now, rootCause: 'x').countermeasure,
        isNull,
      );
    });
  });

  test('Determinismus: gleiche Vorfaelle, gleiche Zahlen', () {
    final incidents = [
      _incident('a', vor: const Duration(hours: 20), intensity: 4),
      _incident('b', vor: const Duration(hours: 40), intensity: 2),
    ];
    expect(_log.pressure(incidents: incidents, now: _now),
        _log.pressure(incidents: incidents, now: _now));
    expect(_due(incidents), _due(incidents));
    expect(_log.patterns(incidents).keys.toList(),
        _log.patterns(incidents).keys.toList());
  });
}
