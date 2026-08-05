/// R-150 — „Etwas liegt seit Tagen im Eingang".
///
/// Die Regel beantwortet eine Frage, die vorher niemand gestellt hat: Wer
/// erinnert daran, in den Eingang zu sehen? Bisher niemand — er war eine
/// Holschuld, und was nicht sichtbar ist, ist bei diesem Profil nicht da
/// [D9]. Eine Notiz, die drei Wochen liegt, entwertet den ganzen
/// Erfassungskanal: Wer einmal erlebt hat, dass Erfasstes versandet, greift
/// beim naechsten Einfall wieder zum Zettel.
///
/// Geprueft wird das Verhalten der Bedingung, nicht ihre Schreibweise — der
/// Baum wird hier so aufgebaut, wie der YAML-Parser ihn aufbaut.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Der Bedingungsbaum aus rules/core/s2-live.yaml, Wort fuer Wort.
Condition r150() => Condition.fromMap({
      'all': [
        {
          'inbox_oldest_hours': {'gte': 72},
        },
        {
          'time_between': ['09:00', '20:00'],
        },
        {
          'meta_minutes_today': {'lt': 12},
        },
      ],
    });

EvalContext contextWith({
  required num oldestHours,
  int hour = 11,
  int metaMinutes = 0,
}) =>
    StateEvalContext(
      state: stateOf(),
      clock: FakeClock(DateTime(2026, 8, 6, hour)),
      runtime: RuntimeContext(
        inboxOldestHours: oldestHours,
        metaMinutesToday: metaMinutes,
      ),
    );

void main() {
  group('R-150 misst das Alter, nicht die Menge', () {
    test('leerer Eingang — kein Anlass', () {
      // Der Test, der beim Schreiben einen Entwurfsfehler gefunden hat.
      //
      // Zuerst stand fuer „keine Notiz" derselbe Platzhalter wie bei
      // Fristen: eine sehr grosse Zahl. Bei einer Frist heisst „keine"
      // unendlich weit weg — beim Alter heisst „keine" aber null. Mit der
      // grossen Zahl haette die Regel ausgerechnet dann gefeuert, wenn der
      // Eingang leer ist.
      expect(
        r150().eval(StateEvalContext(
          state: stateOf(),
          clock: FakeClock(DateTime(2026, 8, 6, 11)),
          // Voreinstellung, also der leere Eingang.
          runtime: const RuntimeContext(),
        )),
        isFalse,
        reason: 'Ein leerer Eingang ist kein Befund',
      );
    });

    test('frisch erfasst — kein Anlass', () {
      expect(
        r150().eval(contextWith(oldestHours: 4)),
        isFalse,
        reason: 'Vier Stunden sind ein Vormittag, kein Befund',
      );
    });

    test('zwei Tage — noch kein Anlass', () {
      expect(r150().eval(contextWith(oldestHours: 48)), isFalse);
    });

    test('drei Tage — Anlass', () {
      expect(
        r150().eval(contextWith(oldestHours: 72)),
        isTrue,
        reason: 'Ab hier ist nicht mehr plausibel, dass es noch kommt',
      );
    });

    test('drei Wochen — erst recht', () {
      expect(r150().eval(contextWith(oldestHours: 24 * 21)), isTrue);
    });
  });

  group('R-150 meldet sich nicht zur Unzeit', () {
    test('nachts nicht', () {
      expect(
        r150().eval(contextWith(oldestHours: 200, hour: 3)),
        isFalse,
        reason: 'Um drei Uhr nachts ist ein Eingang niemandes Problem — und '
            'ein Hinweis um diese Zeit arbeitet gegen das Sleep Gate [D8]',
      );
    });

    test('nach zwanzig Uhr nicht mehr', () {
      expect(r150().eval(contextWith(oldestHours: 200, hour: 21)), isFalse);
    });

    test('am Vormittag schon', () {
      expect(r150().eval(contextWith(oldestHours: 200, hour: 9)), isTrue);
    });
  });

  group('R-150 respektiert den Meta-Deckel', () {
    test('bei aufgebrauchtem Budget still', () {
      // Sonst waere sie ein Weg, das eigene Limit zu umgehen: „schau mal in
      // den Eingang" ist eine Einladung, weitere Zeit im System zu
      // verbringen — an dem Tag, an dem das Budget schon weg ist, genau die
      // falsche (G4).
      expect(
        r150().eval(contextWith(oldestHours: 200, metaMinutes: 12)),
        isFalse,
      );
    });

    test('bei offenem Budget nicht still', () {
      expect(
        r150().eval(contextWith(oldestHours: 200, metaMinutes: 5)),
        isTrue,
      );
    });
  });
}
