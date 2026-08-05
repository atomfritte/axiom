/// Ortsgebundene Aufgaben — ohne GPS.
///
/// Der Ort ist ein Name, den der Nutzer vergibt, keine Koordinate. Geprueft
/// wird deshalb nicht „liegt der Punkt im Kreis", sondern das Verhalten, das
/// daran haengt: Was ist startbar, was wird unterdrueckt, und vor allem — was
/// wird NICHT unterdrueckt, solange niemand einen Ort gesetzt hat.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Task taskAt(String? place, {int ae = 3, TaskState state = TaskState.ready}) =>
    Task(
      id: 'task-${place ?? "überall"}',
      title: 'Aufgabe',
      activationEnergy: ae,
      salience: 5,
      stakes: 5,
      place: place,
      state: state,
    );

void main() {
  group('Ohne gesetzten Ort aendert sich nichts', () {
    test('eine ortsgebundene Aufgabe bleibt startbar', () {
      // Der wichtigste Fall dieses ganzen Features: Etwas zu verstecken, das
      // der Nutzer nie eingeschaltet hat, waere der schlimmere Fehler [D9].
      expect(taskAt('Baumarkt').isStartable(100), isTrue);
      expect(taskAt('Baumarkt').isStartable(100, atPlace: null), isTrue);
      expect(taskAt('Baumarkt').isHere(null), isTrue);
      expect(taskAt('Baumarkt').isHere('   '), isTrue);
    });

    test('das Regelwerk sieht einen Wert, keinen Fehler', () {
      // Eine unaufloesbare Variable bricht die gesamte Auswertung ab
      // (Fail-Fast). „Gerade kein Ort" ist aber kein Fehler, sondern der
      // Normalfall — die Bedingung muss antworten koennen.
      final ctx = StateEvalContext(
        state: stateOf(),
        clock: FakeClock(DateTime.utc(2026, 8, 3, 10)),
      );
      expect(ctx.symbolic('place'), kNoPlace);
      expect(
        const SymbolicCompare('place', CompareOp.eq, kNoPlace).eval(ctx),
        isTrue,
      );
    });
  });

  group('Mit gesetztem Ort', () {
    test('eine Aufgabe fuer einen anderen Ort ist nicht startbar', () {
      expect(taskAt('Baumarkt').isStartable(100, atPlace: 'Büro'), isFalse);
    });

    test('eine ortsungebundene Aufgabe geht ueberall', () {
      expect(taskAt(null).isStartable(100, atPlace: 'Büro'), isTrue);
    });

    test('am passenden Ort gilt wieder nur die Kapazitaet', () {
      expect(taskAt('Büro', ae: 3).isStartable(100, atPlace: 'Büro'), isTrue);
      expect(taskAt('Büro', ae: 9).isStartable(40, atPlace: 'Büro'), isFalse);
    });

    test('Gross- und Kleinschreibung sowie Leerzeichen trennen nicht', () {
      // Sonst waeren „Büro" und „büro" zweierlei — und das faellt niemandem
      // auf, es erscheint nur nichts.
      expect(taskAt('Büro').isHere(' büro '), isTrue);
      expect(samePlace('Zuhause', 'zuhause'), isTrue);
      expect(samePlace('Zuhause', 'Baumarkt'), isFalse);
    });

    test('eine Regel kann auf den Ort pruefen', () {
      final ctx = StateEvalContext(
        state: stateOf(),
        clock: FakeClock(DateTime.utc(2026, 8, 3, 10)),
        runtime: const RuntimeContext(place: 'Büro'),
      );
      expect(
        const SymbolicCompare('place', CompareOp.eq, 'Büro').eval(ctx),
        isTrue,
      );
      expect(
        const SymbolicCompare('place', CompareOp.eq, 'Baumarkt').eval(ctx),
        isFalse,
      );
      expect(
        const SymbolicCompare('place', CompareOp.ne, 'Baumarkt').eval(ctx),
        isTrue,
      );
    });

    test('place steht im Wortschatz und ist damit fuer den Validator bekannt',
        () {
      final place = RuleVocabulary.symbolic('place');
      expect(place, isNotNull);
      expect(place!.freeform, isTrue,
          reason: 'Die Werte entstehen im Gebrauch, eine feste Liste waere '
              'geraten');
      expect(place.values.keys, contains(kNoPlace));
    });
  });

  group('Zerlegen erbt den Ort', () {
    test('Teilschritte einer Baumarkt-Aufgabe bleiben im Baumarkt', () {
      // Ohne das faellt die Ortsbindung beim Zerlegen lautlos weg, und die
      // Schritte wuerden ueberall vorgeschlagen.
      var counter = 0;
      final children = const Atomizer().split(
        parent: taskAt('Baumarkt', ae: 8),
        steps: [
          (title: 'Zettel schreiben', energy: 2),
          (title: 'Hinfahren', energy: 4),
        ],
        nextId: () => 'child-${counter++}',
      );
      expect(children.every((c) => c.place == 'Baumarkt'), isTrue);
    });

    test('zerlegen wird trotzdem ueberall angeboten', () {
      // Der Ort entscheidet, was man TUN kann, nicht was man PLANEN kann.
      // Den ersten Schritt aufzuschreiben geht am Schreibtisch.
      final candidates = const Atomizer().candidates(
        tasks: [taskAt('Baumarkt', ae: 9)],
        capacity: 40,
        now: DateTime(2026, 8, 3, 10),
        createdAt: const {},
      );
      expect(candidates, hasLength(1));
    });
  });

  group('copyWith verliert den Ort nicht', () {
    test('ein Zustandswechsel behaelt die Ortsbindung', () {
      // Jeder Statuswechsel laeuft ueber copyWith. Faellt place dabei weg,
      // ist die Bindung nach dem ersten „Anfangen" verschwunden.
      final started = taskAt('Büro').copyWith(state: TaskState.active);
      expect(started.place, 'Büro');
    });
  });
}
