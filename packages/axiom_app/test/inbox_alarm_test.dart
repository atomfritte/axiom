/// Der Eingang meldet sich auch, wenn die App zu ist (R-150, D9).
///
/// **Warum es diesen Weg ueberhaupt gibt.** Eine gefeuerte Regel wird in
/// AXIOM zu einer Zeile auf dem Bildschirm und zu nichts sonst; die vier
/// Benachrichtigungskanaele benutzen ausschliesslich geplante Alarme. R-150
/// existiert aber genau fuer den Fall, dass man die App eben nicht oeffnet.
/// Sie war damit auf dem einzigen Weg stumm, auf dem sie haette sprechen
/// muessen.
///
/// Die Attrappe folgt `focus_alarm_test.dart`: `debugAsIfAndroid` schaltet
/// die Bruecke scharf, ein Handler schreibt mit, was ueber den Kanal geht.
library;

import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
import 'package:axiom_app/i18n/i18n.dart';
import 'package:axiom_app/platform/android_bridge.dart';
import 'package:axiom_app/screens/body_sheet.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('de.atomfritte.axiom/system');
  final calls = <MethodCall>[];

  List<Map<Object?, Object?>> sent(String method) => calls
      .where((c) => c.method == method)
      .map((c) => (c.arguments as Map).cast<Object?, Object?>())
      .toList();

  /// Der Zeitpunkt, auf den gestellt wurde — oder `null`, wenn abbestellt
  /// wurde. Beides zugleich waere ein Fehler und faellt hier auf.
  Future<DateTime?> arm({required DateTime? oldest, required DateTime now}) async {
    calls.clear();
    await InboxAgeAlarm.arm(oldestUnanswered: oldest, now: now);

    final gestellt = sent('scheduleExact');
    final abbestellt = sent('cancelAlarm');
    expect(gestellt.length + abbestellt.length, 1,
        reason: 'Entweder stellen oder abbestellen, nie beides und nie nichts');
    if (gestellt.isEmpty) {
      expect(abbestellt.single['id'], InboxAgeAlarm.alarmId);
      return null;
    }
    expect(gestellt.single['id'], InboxAgeAlarm.alarmId);
    return DateTime.fromMillisecondsSinceEpoch(gestellt.single['atMillis'] as int);
  }

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'scheduleExact' || 'cancelAlarm' => true,
        _ => null,
      };
    });
    AndroidBridge.debugAsIfAndroid = true;
  });

  tearDown(() {
    AndroidBridge.debugAsIfAndroid = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  // Ein Donnerstag, 11:00 — mitten im Fenster, in dem R-150 spricht.
  final jetzt = DateTime(2026, 8, 6, 11);

  group('Wann der Wecker steht', () {
    test('leerer Eingang: gar nicht', () async {
      expect(await arm(oldest: null, now: jetzt), isNull);
    });

    test('frische Notiz: auf den Moment, in dem sie alt genug wird', () async {
      // Vor zwei Stunden erfasst, also reif in 70 Stunden. Das ist der
      // 9. August um 09:00 und liegt im Fenster — nichts zu verschieben.
      final at = await arm(
        oldest: jetzt.subtract(const Duration(hours: 2)),
        now: jetzt,
      );

      expect(at, DateTime(2026, 8, 9, 9));
    });

    test('laengst reife Notiz: der naechste Morgen, nicht sofort', () async {
      // Fuenf Tage alt. „Sofort" hiesse: Der Alarm feuert in derselben
      // Minute, in der die App ohnehin laeuft — Laerm neben einer Ansicht,
      // die es schon zeigt.
      final at = await arm(
        oldest: jetzt.subtract(const Duration(days: 5)),
        now: jetzt,
      );

      expect(at, DateTime(2026, 8, 7, 9));
    });

    test('nie ausserhalb des Fensters, in dem die Regel spricht', () async {
      // Ein Wecker um 04:00 weckte fuer etwas, das die App beim Oeffnen gar
      // nicht anzeigt — und nachts ist ein Eingang niemandes Problem [D8].
      for (final stunde in [0, 3, 6, 8, 9, 12, 19, 20, 21, 23]) {
        final now = DateTime(2026, 8, 6, stunde);
        final at = await arm(oldest: now.subtract(const Duration(days: 4)), now: now);

        expect(at, isNotNull, reason: 'Stunde $stunde');
        expect(at!.isAfter(now), isTrue, reason: 'Stunde $stunde: in der Vergangenheit');
        expect(
          at.hour,
          allOf(greaterThanOrEqualTo(InboxAgeAlarm.windowStartHour),
              lessThan(InboxAgeAlarm.windowEndHour)),
          reason: 'Stunde $stunde ergab ${at.hour}:00',
        );
      }
    });

    test('sichtbar und still, und er fuehrt in den Eingang', () async {
      // `axiom_intervene` weckt mit Ton; das gehoert zum Unterbrechen von
      // Vertiefung, nicht zu einer drei Tage alten Notiz (G3).
      await arm(oldest: jetzt.subtract(const Duration(days: 4)), now: jetzt);

      expect(sent('scheduleExact').single['channel'], 'axiom_nudge');
      expect(sent('scheduleExact').single['route'], AxiomRoute.inbox);
    });
  });

  group('Was der Wecker sagt (R7, G3)', () {
    test('die Zahl ist das Alter, nicht die Menge', () {
      // „7 Notizen" waere eine Bilanz und traefe Rejection Sensitivity
      // frontal [D10]. „Seit vier Tagen" ist eine Ablesung.
      final (titel, text) = InboxAgeAlarm.describe(4, AppLanguage.de);

      expect(titel, 'Seit 4 Tagen im Eingang');
      expect(text, isNot(contains('{')));
      expect('$titel $text'.toLowerCase(), isNot(contains('notiz')));
    });

    test('keine Wertung, keine Frist, kein Ausrufezeichen', () {
      const verboten = [
        '!', 'schon wieder', 'immer noch', 'endlich', 'solltest', 'musst',
        'vergessen', 'liegen geblieben', 'versaeumt',
        'still', 'again', 'should', 'must', 'finally', 'forgot', 'overdue',
      ];
      for (final language in AppLanguage.values) {
        for (final tage in [3, 4, 11]) {
          final (titel, text) = InboxAgeAlarm.describe(tage, language);
          final satz = '$titel $text'.toLowerCase();
          expect(titel, isNotEmpty);
          expect(text, isNotEmpty);
          expect(satz, isNot(contains('{')), reason: language.code);
          for (final wort in verboten) {
            expect(satz, isNot(contains(wort)), reason: '„$wort" in „$satz"');
          }
        }
      }
    });

    test('die englische Fassung ist wirklich uebersetzt', () {
      final (titel, text) = InboxAgeAlarm.describe(4, AppLanguage.en);
      expect(titel, contains('4'));
      expect('$titel $text', isNot(matches(RegExp('[äöüÄÖÜß]'))));
    });
  });

  group('Die Schwelle steht an zwei Stellen — und sie stimmen ueberein', () {
    /// R-150 aus dem ausgelieferten Regelwerk. `parity_test.dart` haelt
    /// `assets/rules/` und `rules/core/` deckungsgleich, also ist das hier
    /// zugleich die Datei, die im Repo liegt.
    Rule loadR150() =>
        YamlRuleSource(loadRuleAssets()).parse().rules.firstWhere((r) => r.id == 'R-150');

    /// Alle Blaetter des Bedingungsbaums — `all`/`any`/`not` aufgeloest.
    List<Condition> leaves(Condition c) => switch (c) {
          AllOf(:final children) || AnyOf(:final children) =>
            children.expand(leaves).toList(),
          NotCond(:final child) => leaves(child),
          _ => [c],
        };

    test('der Wecker rechnet mit derselben Zahl wie die Regel', () {
      // Die Doppelung ist beabsichtigt: Der Wecker muss den Zeitpunkt im
      // Voraus kennen, die Regel wertet rueckblickend aus. Laufen sie
      // auseinander, meldet sich der Wecker fuer etwas, das die App dann
      // nicht anzeigt — oder er schweigt, waehrend die Regel feuert.
      final schwelle = leaves(loadR150().when)
          .whereType<NumericCompare>()
          .where((c) => c.variable == 'inbox_oldest_hours')
          .toList();

      expect(schwelle, hasLength(1),
          reason: 'R-150 prueft nicht mehr genau einmal auf das Alter des '
              'Eingangs — dann ist diese Doppelung hinfaellig und der Wecker '
              'gehoert ueberdacht');
      expect(schwelle.single.op, CompareOp.gte);
      expect(schwelle.single.value, InboxAgeAlarm.threshold.inHours,
          reason: 'R-150 und InboxAgeAlarm.threshold sind auseinandergelaufen');
    });

    test('und mit demselben Zeitfenster', () {
      final fenster = leaves(loadR150().when).whereType<TimeBetween>().toList();

      expect(fenster, hasLength(1));
      expect(fenster.single.fromMinutes, InboxAgeAlarm.windowStartHour * 60);
      expect(fenster.single.toMinutes, InboxAgeAlarm.windowEndHour * 60);
    });

    test('und die Regel ist scharf — sonst weckt der Wecker fuer nichts', () {
      final r150 = loadR150();

      expect(r150.then.type, ActionType.notify,
          reason: 'R-150 im Schatten, aber der Wecker klingelt: Dann kaeme '
              'eine Meldung fuer eine Regel, die in der App nichts zeigt');
      expect(r150.severity, Severity.nudge,
          reason: '`info` ist IMPORTANCE_MIN und in der Statusleiste '
              'unsichtbar; `intervene` macht einen Ton');
    });
  });

  group('Die ID ist frei gewaehlt und bleibt es', () {
    test('sie kollidiert mit keiner vergebenen', () {
      // `AlarmManager` kennt nur Zahlen: Zwei Stellen mit derselben ID
      // ueberschreiben einander stumm.
      expect(InboxAgeAlarm.alarmId, greaterThan(3),
          reason: '1–3 gehoeren den taeglichen Check-ins');
      expect(InboxAgeAlarm.alarmId, isNot(SleepGate.alarmWindDown));
      expect(InboxAgeAlarm.alarmId, isNot(SleepGate.alarmSleepLog));
      expect(InboxAgeAlarm.alarmId, isNot(FocusEndAlarm.alarmId));
      expect(InboxAgeAlarm.alarmId, lessThan(1000),
          reason: 'ab 1000 liegen die Ankerschritte');
    });
  });
}
