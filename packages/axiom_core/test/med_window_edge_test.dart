/// Wirkfenster an den Raendern.
///
/// Das Modul protokolliert und empfiehlt nichts (R10). Umso wichtiger, dass
/// die eine Zahl, die es liefert — liegt dieser Zeitpunkt im eingetragenen
/// Fenster? — an ihren Kanten stimmt. Hier stehen der Anfang und das Ende
/// des Fensters auf die Sekunde, die Faelle ohne oder mit unsinniger Dauer
/// und die Frage, ob UTC und Ortszeit dasselbe Ergebnis liefern.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

const MedWindow _med = MedWindow();
final DateTime _taken = DateTime(2026, 8, 3, 8);

MedEntry _entry({
  String id = 'm1',
  DateTime? takenAt,
  Duration onset = const Duration(minutes: 30),
  Duration duration = const Duration(hours: 4),
}) =>
    MedEntry(
      id: id,
      label: 'Eintrag',
      takenAt: takenAt ?? _taken,
      onset: onset,
      duration: duration,
    );

void main() {
  group('Das Fenster hat einen Anfang und ein Ende', () {
    final entry = _entry();

    test('es beginnt genau nach der Anlaufzeit', () {
      expect(entry.windowStart, _taken.add(const Duration(minutes: 30)));
      expect(entry.isInWindow(entry.windowStart.subtract(const Duration(seconds: 1))),
          isFalse);
      expect(entry.isInWindow(entry.windowStart), isTrue);
    });

    test('es endet genau nach Anlauf plus Dauer — das Ende gehoert nicht dazu',
        () {
      expect(entry.windowEnd, _taken.add(const Duration(hours: 4, minutes: 30)));
      expect(entry.isInWindow(entry.windowEnd.subtract(const Duration(seconds: 1))),
          isTrue);
      expect(entry.isInWindow(entry.windowEnd), isFalse);
    });

    test('vor der Einnahme liegt nie ein Fenster', () {
      expect(entry.isInWindow(_taken.subtract(const Duration(hours: 1))),
          isFalse);
    });

    test('ohne Anlaufzeit beginnt es mit der Einnahme', () {
      final sofort = _entry(onset: Duration.zero);
      expect(sofort.windowStart, _taken);
      expect(sofort.isInWindow(_taken), isTrue);
    });

    test('ohne Dauer gibt es kein Fenster', () {
      // Der Nutzer hat dann nur die Einnahme notiert — das ist der
      // Normalfall und kein Fehler.
      final ohne = _entry(duration: Duration.zero);
      expect(ohne.hasWindow, isFalse);
      expect(ohne.isInWindow(_taken), isFalse);
      expect(ohne.isInWindow(ohne.windowStart), isFalse);
      expect(ohne.remaining(_taken), Duration.zero);
    });

    test('eine negative Dauer ergibt ebenfalls kein Fenster', () {
      // Kann nur aus einem Import kommen. Ein Fenster, das rueckwaerts
      // laeuft, darf nicht als laufend gelten.
      final falsch = _entry(duration: const Duration(hours: -2));
      expect(falsch.hasWindow, isFalse);
      expect(falsch.isInWindow(_taken), isFalse);
    });

    test('die Restzeit zaehlt herunter und wird nie negativ', () {
      final mitte = _taken.add(const Duration(hours: 2, minutes: 30));
      expect(entry.remaining(mitte), const Duration(hours: 2));
      expect(entry.remaining(entry.windowEnd), Duration.zero);
      expect(entry.remaining(_taken.add(const Duration(days: 1))), Duration.zero);
      expect(entry.remaining(_taken.subtract(const Duration(hours: 1))),
          Duration.zero);
    });

    test('UTC und Ortszeit meinen denselben Augenblick', () {
      // Der Eintrag wird in UTC gespeichert, gefragt wird mit der Ortszeit.
      // Verglichen wird der Zeitpunkt, nicht die Schreibweise — sonst
      // haenge das Fenster an der Zeitzone des Geraets.
      final utc = MedEntry(
        id: 'm',
        label: 'x',
        takenAt: DateTime.utc(2026, 8, 3, 8),
        onset: const Duration(minutes: 30),
        duration: const Duration(hours: 4),
      );
      final drin = DateTime.utc(2026, 8, 3, 10);
      expect(utc.isInWindow(drin), isTrue);
      expect(utc.isInWindow(drin.toLocal()), isTrue);
      expect(utc.remaining(drin), utc.remaining(drin.toLocal()));
    });
  });

  group('Der aktive Eintrag', () {
    test('aus mehreren wird der genommen, dessen Fenster laeuft', () {
      final entries = [
        _entry(id: 'alt', takenAt: _taken.subtract(const Duration(hours: 12))),
        _entry(id: 'jetzt'),
      ];
      expect(
        _med.activeAt(entries, _taken.add(const Duration(hours: 2)))!.id,
        'jetzt',
      );
    });

    test('laeuft keines, kommt null', () {
      expect(
        _med.activeAt([_entry()], _taken.add(const Duration(days: 1))),
        isNull,
      );
    });

    test('aus einer leeren Liste kommt null', () {
      expect(_med.activeAt(const [], _taken), isNull);
    });

    test('bei ueberlappenden Fenstern gewinnt der erste der Liste', () {
      // Zwei Einnahmen dicht hintereinander sind moeglich. Der Aufrufer
      // liefert die Liste nach Einnahmezeit absteigend — damit ist der
      // erste Treffer der juengste. Dieser Test haelt fest, dass die
      // Auswahl an der Reihenfolge haengt und nicht an einer stillen
      // Zweitregel.
      final entries = [
        _entry(id: 'zuerst'),
        _entry(id: 'danach', takenAt: _taken.add(const Duration(hours: 1))),
      ];
      expect(_med.activeAt(entries, _taken.add(const Duration(hours: 2)))!.id,
          'zuerst');
      expect(
        _med
            .activeAt(entries.reversed.toList(),
                _taken.add(const Duration(hours: 2)))!
            .id,
        'danach',
      );
    });
  });

  group('Der Kapazitaetsbonus bleibt klein und an das Fenster gebunden', () {
    MedWindowState state({bool enabled = true, MedEntry? active}) =>
        MedWindowState(enabled: enabled, active: active);

    test('ausgeschaltet gibt es keinen Bonus', () {
      expect(
        _med.capacityBonusAt(
            state: state(enabled: false, active: _entry()),
            at: _taken.add(const Duration(hours: 2))),
        0,
      );
    });

    test('ohne Eintrag gibt es keinen Bonus', () {
      expect(_med.capacityBonusAt(state: state(), at: _taken), 0);
    });

    test('ausserhalb des Fensters gibt es keinen Bonus', () {
      // Auch dann nicht, wenn ein Eintrag gesetzt ist: Der Zustand kann aus
      // einer frueheren Abfrage stammen.
      expect(
        _med.capacityBonusAt(
            state: state(active: _entry()),
            at: _taken.add(const Duration(days: 1))),
        0,
      );
    });

    test('im Fenster wirkt er, und zwar pauschal', () {
      expect(
        _med.capacityBonusAt(
            state: state(active: _entry()),
            at: _taken.add(const Duration(hours: 2))),
        kMedWindowBonus,
      );
    });

    test('er ist klein genug, um keine Genauigkeit vorzutaeuschen', () {
      // Eine grosse Zahl machte die Kapazitaetsformel von einer Einnahme
      // abhaengig statt von gemessenen Signalen.
      expect(kMedWindowBonus, lessThanOrEqualTo(10));
      expect(kMedWindowBonus, greaterThan(0));
    });

    test('das Modul ist ab Werk aus', () {
      const aus = MedWindowState();
      expect(aus.enabled, isFalse);
      expect(aus.active, isNull);
      expect(aus.isInWindow, isFalse);
    });
  });

  group('Die Beschreibung ist sachlich und nennt keinen Rat', () {
    test('die vier Faelle sind unterscheidbar', () {
      final saetze = <String>{
        _med.describe(const MedWindowState(), _taken),
        _med.describe(const MedWindowState(enabled: true), _taken),
        _med.describe(MedWindowState(enabled: true, active: _entry()),
            _taken.add(const Duration(days: 1))),
        _med.describe(MedWindowState(enabled: true, active: _entry()),
            _taken.add(const Duration(hours: 2))),
      };
      expect(saetze, hasLength(4));
    });

    test('unter einer Stunde in Minuten, ab einer Stunde in Stunden', () {
      final state = MedWindowState(enabled: true, active: _entry());
      // Restzeit genau 60 min.
      expect(
        _med.describe(state, _taken.add(const Duration(hours: 3, minutes: 30))),
        contains('h.'),
      );
      // Restzeit 59 min.
      expect(
        _med.describe(state, _taken.add(const Duration(hours: 3, minutes: 31))),
        contains('min.'),
      );
    });

    test('kein Text des Moduls nennt Dosis, Zeitpunkt oder Wirkung', () {
      final texte = [
        kMedDisclaimer,
        _med.describe(const MedWindowState(), _taken),
        _med.describe(const MedWindowState(enabled: true), _taken),
        _med.describe(MedWindowState(enabled: true, active: _entry()),
            _taken.add(const Duration(hours: 2))),
        _med.describe(MedWindowState(enabled: true, active: _entry()),
            _taken.add(const Duration(days: 1))),
      ];
      for (final text in texte) {
        final klein = text.toLowerCase();
        for (final wort in [
          'nimm',
          'einnehmen',
          'dosis erhöhen',
          'empfehlen',
          'wirkt gut',
          'zu wenig',
        ]) {
          expect(klein, isNot(contains(wort)), reason: text);
        }
        expect(text, isNot(contains('!')), reason: text);
      }
    });

    test('der Abgrenzungstext verweist ausdruecklich auf die Behandlung', () {
      expect(kMedDisclaimer, contains('protokolliert'));
      expect(kMedDisclaimer, contains('Ärztin'));
      expect(kMedDisclaimer, contains('keine Dosis'));
    });
  });

  test('Determinismus: gleicher Eintrag, gleiche Antwort', () {
    final entry = _entry();
    final at = _taken.add(const Duration(hours: 2));
    expect(entry.isInWindow(at), entry.isInWindow(at));
    expect(entry.remaining(at), entry.remaining(at));
    expect(_med.describe(MedWindowState(enabled: true, active: entry), at),
        _med.describe(MedWindowState(enabled: true, active: entry), at));
  });
}
