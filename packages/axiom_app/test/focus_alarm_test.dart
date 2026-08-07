/// Das Ende eines Fokusblocks meldet sich (M4, D6).
///
/// **Warum diese Datei mit einer Attrappe arbeitet.** `AndroidBridge` ist auf
/// dem Rechner ein No-op: `isSupported` ist falsch, und jeder Aufruf endet
/// vor dem Kanal. Die Zusage, um die es hier geht — „beim Start steht ein
/// Wecker auf dem Ende, beim vorzeitigen Beenden ist er wieder weg" — waere
/// damit nur auf dem Geraet nachsehbar, und was nur auf dem Geraet geprueft
/// wird, wird nicht geprueft. Deshalb: `debugAsIfAndroid` schaltet die
/// Bruecke scharf, ein Attrappen-Handler schreibt mit, was ueber den Kanal
/// geht. Geprueft wird der echte Weg, mit ID, Kanal, Ziel und Text.
///
/// Was hier nicht geprueft werden kann, ist Android selbst: ob der
/// `AlarmManager` puenktlich weckt und ob der Kanal wirklich klingt. Das
/// haelt `SystemSync.alarmDrift` im Betrieb nach (R4).
library;

import 'package:axiom_app/i18n/i18n.dart';
import 'package:axiom_app/platform/android_bridge.dart';
import 'package:axiom_app/screens/body_sheet.dart';
import 'package:axiom_app/screens/focus_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('de.atomfritte.axiom/system');
  final calls = <MethodCall>[];

  /// Alle Aufrufe von [method], in der Reihenfolge, in der sie kamen.
  ///
  /// [id] grenzt auf einen Wecker ein. Noetig, seit nicht mehr nur der
  /// Fokusblock ueber diesen Kanal geht: Eine Auswertung stellt auch den
  /// Eingangs-Wecker (R-150) oder bestellt ihn ab. Ohne die Eingrenzung
  /// bricht dieser Test an einer Aenderung, die ihn gar nicht betrifft — und
  /// das ist die Sorte Test, die man irgendwann entnervt loescht.
  List<Map<Object?, Object?>> sent(String method, {int? id}) => calls
      .where((c) => c.method == method)
      .map((c) => (c.arguments as Map).cast<Object?, Object?>())
      .where((a) => id == null || a['id'] == id)
      .toList();

  /// Die Aufrufe, die dem Fokus-Wecker gelten.
  List<Map<Object?, Object?>> focusCalls(String method) =>
      sent(method, id: FocusEndAlarm.alarmId);

  late TestHarness h;

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      // Nur die beiden Alarmaufrufe antworten. Alles andere bleibt `null`
      // und wird von den Huellen zu „hat nicht geklappt" — genau wie auf
      // einem Geraet, dem die Funktion fehlt.
      return switch (call.method) {
        'scheduleExact' || 'cancelAlarm' => true,
        _ => null,
      };
    });
    AndroidBridge.debugAsIfAndroid = true;
    h = TestHarness.create(at: DateTime(2026, 8, 3, 12, 15));
    h.completeOnboarding();
  });

  tearDown(() {
    AndroidBridge.debugAsIfAndroid = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    h.dispose();
  });

  group('Ein Fokusblock endet nicht mehr lautlos (M4, D6)', () {
    test('der Start stellt einen Wecker auf das geplante Ende', () async {
      final session = await h.runtime.startFocus(
        taskId: 't1',
        taskTitle: 'Steuerunterlagen',
        planned: const Duration(minutes: 50),
      );

      final alarms = focusCalls('scheduleExact');
      expect(alarms, hasLength(1));
      expect(
        DateTime.fromMillisecondsSinceEpoch(alarms.single['atMillis'] as int),
        session.startedAt.add(const Duration(minutes: 50)),
      );
    });

    test('auch der Block, der aus „Anfangen" entsteht', () async {
      // Der haeufigere Weg: Auf der Hauptansicht eine Aufgabe anfangen.
      // Haenge der Wecker am Fokusschirm, endete genau dieser Block wieder
      // lautlos — und es ist der, den man am ehesten vergisst.
      final task = await h.runtime.createTask(
        title: 'Rückruf Werkstatt',
        activationEnergy: 2,
        salience: 5,
        stakes: 6,
      );
      calls.clear();
      await h.runtime.startTask(task, planned: const Duration(minutes: 25));

      expect(focusCalls('scheduleExact'), hasLength(1));
    });

    test('der Wecker fuehrt auf den Fokusschirm, nicht auf die Uebersicht',
        () async {
      await h.runtime.startFocus(taskId: 't1', taskTitle: 'Ziel');
      expect(focusCalls('scheduleExact').single['route'], AxiomRoute.focus);
    });

    test('er ist hoerbar — eine Unterbrechung, die man nicht hoert, ist keine',
        () async {
      // `axiom_info` (MIN) und `axiom_nudge` (LOW) machen keinen Ton.
      // `axiom_enforce` (HIGH) blendet sich ueber das laufende Bild und
      // gehoert dem Notfall. Bleibt DEFAULT.
      await h.runtime.startFocus(taskId: 't1', taskTitle: 'Ziel');
      expect(focusCalls('scheduleExact').single['channel'], 'axiom_intervene');
    });

    test('ein Ende, das schon vorbei ist, weckt niemanden mehr', () async {
      final at = DateTime(2026, 8, 3, 12, 15);
      final ok = await FocusEndAlarm.arm(
        startedAt: at,
        planned: const Duration(minutes: 50),
        now: at.add(const Duration(minutes: 90)),
        anchorTitle: 'Ziel',
      );

      expect(ok, isTrue);
      expect(focusCalls('scheduleExact'), isEmpty);
      // Statt dessen abbestellt: Ein Rest aus einer frueheren Sitzung darf
      // nicht stehenbleiben.
      expect(focusCalls('cancelAlarm'), hasLength(1));
    });
  });

  group('Vorzeitiges Beenden nimmt den Wecker zurueck', () {
    test('mit Wiedereinstiegsnotiz', () async {
      final session = await h.runtime.startFocus(
        taskId: 't1',
        taskTitle: 'Steuerunterlagen',
        planned: const Duration(minutes: 50),
      );
      h.clock.advance(const Duration(minutes: 12));
      calls.clear();
      await h.runtime.endFocus(session, breadcrumb: 'Bei Anlage KAP, Zeile 7');

      expect(focusCalls('cancelAlarm'), hasLength(1));
      expect(focusCalls('scheduleExact'), isEmpty);
    });

    test('und auch, wenn die Aufgabe darunter erledigt wird', () async {
      // Dann schliesst `completeTask` das Fokusfenster. Der Wecker haengt an
      // der Sitzung, nicht am Knopf, der sie beendet hat.
      final task = await h.runtime.createTask(
        title: 'Rückruf Werkstatt',
        activationEnergy: 2,
        salience: 5,
        stakes: 6,
      );
      await h.runtime.startTask(task, planned: const Duration(minutes: 25));
      calls.clear();
      await h.runtime.completeTask(task);

      expect(focusCalls('cancelAlarm'), hasLength(1));
    });

    testWidgets('„Abbrechen, ohne Notiz" auf dem Fokusschirm', (tester) async {
      await h.runtime.startFocus(
        taskId: 't1',
        taskTitle: 'Steuerunterlagen',
        planned: const Duration(minutes: 50),
      );
      h.clock.advance(const Duration(minutes: 8));
      await pumpPhone(tester, h.wrap(const FocusScreen()));

      calls.clear();
      await tester.tap(find.text('Abbrechen, ohne Notiz'));
      await tester.pumpAndSettle();

      expect(focusCalls('cancelAlarm'), hasLength(1));
      await unmount(tester);
    });
  });

  group('Die Meldung ist eine Ablesung, keine Mahnung (R7, G3)', () {
    test('Ueberschrift ist der Messwert, Text die naechste Handlung', () {
      final (title, body) = FocusEndAlarm.describe(
        const Duration(minutes: 50),
        'Steuerunterlagen',
        AppLanguage.de,
      );

      expect(title, '50 von 50 min');
      // Genau die Frage, die der Fokusschirm beim Beenden ohnehin stellt —
      // die Notiz zum Wiedereinstieg ist der Zweck des Ausstiegs [D11].
      expect(body, 'Wo genau bist du bei „Steuerunterlagen" stehengeblieben?');
    });

    test('ohne gesetztes Ziel fragt sie offener', () {
      final (title, body) = FocusEndAlarm.describe(
        const Duration(minutes: 25),
        null,
        AppLanguage.de,
      );

      expect(title, '25 von 25 min');
      expect(body, contains('nächste Handgriff'));
    });

    test('kein Platzhalter bleibt stehen, auch auf Englisch', () {
      for (final language in AppLanguage.values) {
        for (final anchor in <String?>['Steuerunterlagen', null]) {
          final (title, body) =
              FocusEndAlarm.describe(const Duration(minutes: 50), anchor, language);
          expect('$title $body', isNot(contains('{')),
              reason: '${language.code} / $anchor');
          expect(title, isNotEmpty);
          expect(body, isNotEmpty);
        }
      }
    });

    test('keine Wertung, keine Frist, kein Ausrufezeichen', () {
      // Der Kanal ist hoerbar; der Satz muss es deshalb nicht sein. „Zeit
      // abgelaufen!" waere ein Urteil ueber einen Zustand, den AXIOM nur
      // misst (R7) — und Schuldsprache erzeugt Vermeidung statt Handlung.
      const forbidden = [
        '!',
        'abgelaufen',
        'überzogen',
        'endlich',
        'Schluss',
        'zu lange',
        'solltest',
        'musst',
        'wieder',
        'expired',
        'over time',
        'should',
        'must',
        'finally',
        'again',
      ];
      for (final language in AppLanguage.values) {
        for (final anchor in <String?>['Steuerunterlagen', null]) {
          final (title, body) =
              FocusEndAlarm.describe(const Duration(minutes: 50), anchor, language);
          final text = '$title $body';
          for (final word in forbidden) {
            expect(text.toLowerCase(), isNot(contains(word.toLowerCase())),
                reason: '„$word" in „$text"');
          }
        }
      }
    });
  });

  group('Die ID ist frei gewaehlt und bleibt es', () {
    test('sie kollidiert mit keiner vergebenen', () {
      // `AlarmManager` kennt nur Zahlen: Zwei Stellen mit derselben ID
      // ueberschreiben einander stumm. Die Vergabe steht als Tabelle in
      // `android_bridge.dart`; das hier haelt sie ehrlich.
      expect(FocusEndAlarm.alarmId, greaterThan(3),
          reason: '1–3 gehoeren den taeglichen Check-ins');
      expect(FocusEndAlarm.alarmId, isNot(SleepGate.alarmWindDown));
      expect(FocusEndAlarm.alarmId, isNot(SleepGate.alarmSleepLog));
      expect(FocusEndAlarm.alarmId, lessThan(1000),
          reason: 'ab 1000 liegen die Ankerschritte');
    });
  });
}
