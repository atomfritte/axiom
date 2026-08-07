/// Prüft die Systemanbindung von der Dart-Seite aus.
///
/// Was hier *nicht* geprüft werden kann, ist Android selbst — ob die Now Bar
/// die Benachrichtigung befördert, ob Health Connect Daten herausgibt. Was
/// geprüft werden kann und muss: dass die App ohne diese Systeme vollständig
/// bedienbar bleibt, dass ein zweiter Import keine Dubletten erzeugt, und
/// dass die Oberfläche nichts verspricht, was die Plattform nicht einlöst.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';

import 'package:axiom_app/i18n/i18n.dart';
import 'package:axiom_app/platform/android_bridge.dart';
import 'package:axiom_app/platform/health_sync.dart';
import 'package:axiom_app/platform/system_sync.dart';
import 'package:axiom_app/platform/system_texts.dart';
import 'package:axiom_app/state/runtime.dart';

import 'harness.dart';

void main() {
  group('Ohne Android bleibt alles bedienbar', () {
    // Der Desktop-Companion laeuft auf demselben Code. Ein Systemaufruf, der
    // dort wirft, macht die App auf dem Rechner unbrauchbar — und ein
    // Systemaufruf, der dort den *falschen* Wert liefert, ist schlimmer:
    // `databaseKey` entscheidet damit ueber Klartext oder gar nicht oeffnen.
    //
    // **Was hier nicht geprueft werden kann.** Die Pfade hinter der
    // `isSupported`-Sperre: Zeitueberschreitung, fehlender Kanal, eine
    // Antwort vom falschen Typ. Sie sind von hier aus unerreichbar, weil
    // `Platform.isAndroid` auf dem Rechner falsch ist und der Aufruf den
    // Kanal nie erreicht. Was sich statt dessen pruefen laesst, ist die Naht
    // selbst — welchen Typ jede Seite erwartet: `bridge_contract_test`.

    test('jede Systemfunktion ist hier ein bekannter Wert, keine Ausnahme',
        () async {
      expect(AndroidBridge.isSupported, isFalse);

      // Der Schluessel: „hier gab es nie einen" — und nur deshalb oeffnet der
      // Rechner die Klartextdatei. Waere es `unavailable`, startete die App
      // auf dem Rechner nie wieder.
      expect((await AndroidBridge.databaseKey()).state, DatabaseKeyState.none);
      expect((await AndroidBridge.databaseKey()).key, isNull);

      expect(await AndroidBridge.applySystemTexts(AppLanguage.de), isFalse);
      expect(await AndroidBridge.ping(), isFalse);

      expect(await AndroidBridge.requestExactAlarm(), isFalse);
      expect(await AndroidBridge.requestNotifications(), isFalse);
      expect(await AndroidBridge.requestIgnoreBatteryOptimizations(), isFalse);
      expect(await AndroidBridge.permissionStatus(), isEmpty);

      expect(
        await AndroidBridge.scheduleExact(
          id: 1,
          at: DateTime(2026, 1, 1),
          title: 'Test',
          body: '',
        ),
        isFalse,
      );
      expect(await AndroidBridge.cancelAlarm(1), isFalse);
      expect(await AndroidBridge.lastAlarmDrift(), isNull);

      expect(await AndroidBridge.presenceEnabled(), isFalse);
      expect(await AndroidBridge.presenceActive(), isFalse);
      expect(await AndroidBridge.updatePresence(headline: 'a', detail: 'b'),
          isFalse);
      expect(await AndroidBridge.stopPresence(), isFalse);
      expect(await AndroidBridge.openPresenceChannel(), isFalse);
      expect(await AndroidBridge.presenceDiagnosis(), isEmpty);
      expect(await AndroidBridge.multicastLock(hold: true), isFalse);

      expect(
          await AndroidBridge.startLiveSlot(
            kind: 'focus',
            title: 'Test',
            detail: '',
            startedAt: DateTime(2026, 1, 1),
            planned: const Duration(minutes: 50),
          ),
          isFalse);
      expect(await AndroidBridge.stopLiveSlot(), isFalse);
      expect(await AndroidBridge.liveSlotRunning(), isFalse);
      expect(await AndroidBridge.liveSlotPromotable(), isFalse);

      expect(await AndroidBridge.healthStatus(), isEmpty);
      expect(await AndroidBridge.healthRead(DateTime(2026)), isEmpty);
      expect(await AndroidBridge.healthOpenSettings(), isFalse);

      expect(await AndroidBridge.widgetCount(), 0);
      expect(await AndroidBridge.diagnostics(), isEmpty);
      expect(await AndroidBridge.listen(), isNull);
      expect(await AndroidBridge.speechAvailable(), isFalse);

      expect(await AndroidBridge.startExpertNotice(address: 'x'), isFalse);
      expect(await AndroidBridge.stopExpertNotice(), isFalse);

      expect(await AndroidBridge.peekPendingMemos(), isEmpty);
      expect(await AndroidBridge.peekPendingPlaces(), isEmpty);
      // Beide antworten mit einer Zahl, nicht mit einem `bool`: Die
      // Systemseite meldet, wie viele Einträge wirklich weg sind.
      expect(await AndroidBridge.ackPendingMemos(1), 0);
      expect(await AndroidBridge.ackPendingPlaces(1), 0);

      // Alles ohne Rueckgabewert darf hier ebenfalls nicht werfen.
      await AndroidBridge.updateWidget(headline: 'a', detail: 'b', capacity: 0);
      await AndroidBridge.scheduleDailyCheckins();
      await AndroidBridge.broadcast('de.atomfritte.axiom.TEST');
      await AndroidBridge.focusStart();
      await AndroidBridge.focusEnd();
      await AndroidBridge.windDown();
      await AndroidBridge.enterMaintenanceMode();
    });

    test('ein Fehlschlag hier sagt, warum — in der Sprache des Aufrufers',
        () async {
      // „passiert nichts" ist von aussen nicht diagnostizierbar. Deshalb gibt
      // es hier keinen stummen Knopf, sondern einen Satz — und der ist
      // uebersetzt, weil er auf dem Bildschirm steht.
      for (final call in <Future<PlatformOutcome> Function(AppLanguage)>[
        (l) => AndroidBridge.startPresence(
            headline: 'a', detail: 'b', language: l),
        (l) => AndroidBridge.healthRequestPermissions(language: l),
        (l) => AndroidBridge.requestPinWidget(language: l),
        (l) => AndroidBridge.requestNotesRole(language: l),
      ]) {
        final german = await call(AppLanguage.de);
        expect(german.ok, isFalse);
        expect(german.reason, isNotNull);
        expect(german.reason, isNot(startsWith('reason.')),
            reason: 'ein Schluessel statt eines Satzes');

        final english = await call(AppLanguage.en);
        expect(english.reason, isNot(german.reason),
            reason: 'unuebersetzt: "${german.reason}"');
      }
    });

    test('jede Systemfunktion steht in diesem Vertrag', () {
      // Ohne diesen Wächter entkommt jede neue Brückenfunktion der Prüfung
      // oben — und ihr Verhalten auf dem Rechner wäre wieder unbekannt.
      final source = File('lib/platform/android_bridge.dart').readAsStringSync();
      final block = source.substring(source.indexOf('abstract final class AndroidBridge'));
      final declared = RegExp(r'static [\w<>?, ]+ (\w+)\(')
          .allMatches(block)
          .map((m) => m.group(1)!)
          .where((name) => !name.startsWith('_'))
          .toSet();

      final covered = {
        'applySystemTexts', 'databaseKey', 'requestExactAlarm',
        'requestNotifications', 'requestIgnoreBatteryOptimizations',
        'permissionStatus', 'scheduleExact', 'cancelAlarm',
        'scheduleDailyCheckins', 'lastAlarmDrift', 'updateWidget',
        'startPresence', 'updatePresence', 'stopPresence', 'presenceEnabled',
        'presenceActive', 'multicastLock', 'openPresenceChannel',
        'presenceDiagnosis', 'startLiveSlot', 'stopLiveSlot',
        'liveSlotRunning', 'liveSlotPromotable', 'healthStatus',
        'healthRequestPermissions', 'ping', 'healthOpenSettings', 'healthRead',
        'requestPinWidget', 'widgetCount', 'requestNotesRole', 'diagnostics',
        'listen', 'speechAvailable', 'startExpertNotice', 'stopExpertNotice',
        'broadcast', 'focusStart', 'focusEnd', 'windDown',
        'enterMaintenanceMode', 'peekPendingMemos', 'ackPendingMemos',
        'peekPendingPlaces', 'ackPendingPlaces',
        'showApproval', 'hideApproval',
      };
      expect(declared.length, greaterThan(40));
      expect(declared.difference(covered), isEmpty,
          reason: 'neu und ohne bekanntes Verhalten auf dem Rechner');
      expect(covered.difference(declared), isEmpty,
          reason: 'steht in der Liste, aber nicht mehr im Quelltext');
    });

    test('die Freigabemeldung ist auf dem Rechner ein sauberes Nein', () async {
      // Der Expertenmodus laeuft auch auf dem Linux-Companion, aber dort gibt
      // es keine Benachrichtigungsleiste. Der Aufruf muss dann „hat nicht
      // geklappt" sagen, nicht werfen — der Freigabeschirm in der App ist
      // ohnehin der Weg, den die Meldung nur abkuerzt.
      expect(await AndroidBridge.showApproval('42'), isFalse);
      expect(await AndroidBridge.hideApproval(), isFalse);
    });

    test('Health Connect meldet sich als nicht verfügbar, nicht als Fehler',
        () async {
      expect(await HealthSync.availability(), HealthAvailability.unavailable);
      // Und ein Import laeuft ins Leere statt in eine Ausnahme: Der
      // Systemschirm ruft ihn auch auf dem Rechner auf.
      expect(const HealthImportResult().isEmpty, isTrue);
    });
  });

  group('Was die Systemseite meldet, wird zu einem Satz', () {
    test('ein bekannter Grund wird übersetzt und mit Werten gefüllt', () {
      // Kotlin schickt nur den Schluessel und die Rohwerte herauf — den Satz
      // baut diese Seite, weil nur sie die gewaehlte Sprache kennt.
      final german = SystemTexts.reason(
          AppLanguage.de, 'reason.widget.failed', ['SecurityException']);
      expect(german, contains('SecurityException'));
      expect(german, isNot(contains('{0}')));

      final english = SystemTexts.reason(
          AppLanguage.en, 'reason.widget.failed', ['SecurityException']);
      expect(english, contains('SecurityException'));
      expect(english, isNot(german));
    });

    test('ein unbekannter Grund wird durchgereicht, nicht verschluckt', () {
      // Sichtbar unfertig statt stumm: Ein technischer Name auf dem
      // Bildschirm ist haesslich und genau deshalb richtig — ein Knopf, der
      // kommentarlos nichts tut, ist nicht diagnostizierbar.
      expect(SystemTexts.reason(AppLanguage.de, 'reason.gibtesnicht'),
          'reason.gibtesnicht');
    });

    test('die Systemseite bekommt jeden Text, den sie anzeigen darf', () {
      // `forLanguage` ist das ganze Bündel. Fehlt darin ein Schlüssel, zeigt
      // Android an dieser Stelle den Rückfall aus `strings.xml` — also die
      // Gerätesprache statt der in der App gewählten, und niemand sieht,
      // warum.
      for (final language in AppLanguage.values) {
        final bundle = SystemTexts.forLanguage(language);
        expect(bundle.keys.toSet(), SystemTexts.sources.keys.toSet());
        expect(bundle.values.where((v) => v.trim().isEmpty), isEmpty);
      }
      expect(SystemTexts.forLanguage(AppLanguage.en)['presence.detail'],
          isNot(SystemTexts.sources['presence.detail']));
    });
  });

  group('Health-Import', () {
    test('Fenster deckt die Baseline mit Reserve ab', () {
      // 14 Tage Baseline. Ein knapperes Fenster wuerde beim ersten Import
      // genau die Naechte auslassen, auf die es ankommt.
      expect(HealthSync.window.inDays, greaterThanOrEqualTo(14));
    });

    test('leeres Ergebnis ist von einem übersprungenen unterscheidbar', () {
      const nothing = HealthImportResult();
      const skipped = HealthImportResult(skipped: 12);
      const fresh = HealthImportResult(sleepNights: 3, stepDays: 5);

      expect(nothing.isEmpty, isTrue);
      expect(skipped.isEmpty, isFalse, reason: 'zwoelf bekannte Nächte sind '
          'ein Ergebnis, kein Nichts');
      expect(skipped.imported, 0);
      expect(fresh.imported, 8);
    });
  });

  group('Was Android zeichnet, ist genau eine Sache', () {
    // Widget und dauerhafte Anzeige tragen zwei Zeilen — nicht zwei Zeilen
    // zur Auswahl, sondern eine Aussage und ihre Begründung (G1, G2). Diese
    // Ebene entsteht ohne Widget-Baum und fällt deshalb durch jeden
    // Widget-Test; geprüft war bisher nur ihre Sprache, nicht ihre Rangfolge.

    final now = DateTime.now();

    AxiomSnapshot snapshot({
      ({Anchor anchor, AnchorStep step})? nextStep,
      Rule? rule,
      List<Task> tasks = const [],
    }) =>
        AxiomSnapshot(
          at: now,
          state: StateVector(
            at: now,
            capacity: 60,
            focusDebt: 0,
            sensationNeed: 0,
            loadIndex: 0,
            regulation: 50,
            sleepDebt: 0,
          ),
          breakdown: const {},
          tasks: tasks,
          metaUsedToday: Duration.zero,
          decisionRule: rule,
          nextStep: nextStep,
        );

    ({Anchor anchor, AnchorStep step}) stepIn(Duration lead) {
      final anchor = Anchor(
        id: 'a1',
        title: 'Zahnarzt',
        arriveBy: now.add(lead + const Duration(minutes: 30)),
      );
      return (
        anchor: anchor,
        step: AnchorStep(
          kind: AnchorStepKind.depart,
          at: now.add(lead),
          label: 'Losgehen',
        ),
      );
    }

    // Eine echte Regel aus dem ausgelieferten Regelwerk, keine gebaute:
    // Was hier angezeigt wird, ist ihr Titel — und der kommt aus dem YAML.
    final rule = YamlRuleSource(loadRuleAssets()).parse().rules.first;

    final task = const Task(
      id: 't1',
      title: 'Steuerunterlagen sortieren',
      activationEnergy: 3,
      salience: 5,
      stakes: 5,
      state: TaskState.ready,
    );

    test('ein Ankerschritt in der nächsten Stunde schlägt alles andere', () {
      // Er hat eine Uhrzeit, und verpasste Uhrzeiten kosten am meisten [D4].
      final (headline, detail) = SystemSync.describe(
        snapshot(
            nextStep: stepIn(const Duration(minutes: 30)),
            rule: rule,
            tasks: [task]),
        AppLanguage.de,
      );
      expect(headline, 'Losgehen');
      expect(detail, contains('Zahnarzt'));
      expect(detail, isNot(contains(rule.title)));
    });

    test('ein Ankerschritt in vier Stunden nicht', () {
      // Sonst stünde den ganzen Tag ein Schritt da, der noch lange nicht
      // ansteht — und die Anzeige wäre wieder eine Liste im Kopf.
      final (headline, detail) = SystemSync.describe(
        snapshot(
            nextStep: stepIn(const Duration(hours: 4)),
            rule: rule,
            tasks: [task]),
        AppLanguage.de,
      );
      expect(headline, rule.title);
      expect(detail, 'Regel ${rule.id}');
    });

    test('ohne Regel steht die Aufgabe da, mit ihrer Startschwelle', () {
      final (headline, detail) =
          SystemSync.describe(snapshot(tasks: [task]), AppLanguage.de);
      expect(headline, 'Steuerunterlagen sortieren');
      expect(detail, 'Start 3/10');
    });

    test('nichts Startbares heißt „nichts in Reichweite", nicht „nichts"', () {
      // Der Unterschied ist der ganze Nutzen: Aufgaben sind da, sie sind nur
      // gerade zu schwer. „Nichts anliegend" wäre an dieser Stelle eine
      // falsche Aussage über den Bestand [D9].
      final tooHeavy = const Task(
        id: 't2',
        title: 'Steuererklärung',
        activationEnergy: 9,
        salience: 5,
        stakes: 8,
        state: TaskState.ready,
      );
      final (headline, detail) =
          SystemSync.describe(snapshot(tasks: [tooHeavy]), AppLanguage.de);
      expect(headline, 'Nichts in Reichweite');
      expect(detail, 'Zerlegen hilft');
    });

    test('ein leerer Bestand sagt das, ohne Vorwurf', () {
      final (headline, detail) =
          SystemSync.describe(snapshot(), AppLanguage.de);
      expect(headline, 'Nichts anliegend');
      expect(detail, 'Tippen zum Erfassen');
    });

    test('keine dieser Zeilen enthält eine Bewertung', () {
      // Was hier steht, steht auf dem Sperrbildschirm. Es ist ein Messwert
      // und keine Note (G3, R7).
      for (final s in [
        snapshot(),
        snapshot(tasks: [task]),
        snapshot(rule: rule),
        snapshot(nextStep: stepIn(const Duration(minutes: 10))),
      ]) {
        for (final language in AppLanguage.values) {
          final (headline, detail) = SystemSync.describe(s, language);
          for (final line in [headline, detail]) {
            expect(line, isNot(contains('!')));
            expect(line.trim(), isNotEmpty);
          }
        }
      }
    });
  });

  group('Kein Versprechen, das die Plattform nicht hält', () {
    /// Kotlin- und Manifest-Quellen. Diese Ebene faellt durch jeden
    /// Widget-Test durch — der Widget-Bug, der das Hinzufuegen verhindert
    /// hat, lag genau hier.
    String android(String path) =>
        File('android/app/src/main/$path').readAsStringSync();

    /// Quelltext ohne Kommentare.
    ///
    /// Noetig, weil die Kommentare hier genau die Begriffe nennen, die im
    /// Code nicht mehr vorkommen duerfen — sie erklaeren ja, warum. Ohne
    /// diesen Schritt verbietet der Test das Erklaeren des Fehlers.
    String code(String source) => source
        .split('\n')
        .where((l) {
          final t = l.trimLeft();
          return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
        })
        .join('\n');

    test('das Widget ist exportiert, sonst lässt es sich nicht hinzufügen',
        () {
      final manifest = android('AndroidManifest.xml');
      final provider = manifest.substring(
        manifest.indexOf('.AxiomWidgetProvider'),
      );
      expect(
        provider.substring(0, provider.indexOf('</receiver>')),
        contains('android:exported="true"'),
        reason: 'Der Launcher laeuft in einem anderen Prozess und muss '
            'APPWIDGET_UPDATE zustellen koennen.',
      );
    });

    test('Live Update ist als Dienst angemeldet', () {
      expect(android('AndroidManifest.xml'), contains('.LiveSlotService'));
    });

    test('Direct Share hat ein Ziel und eine passende Kategorie', () {
      final shortcuts = android('res/xml/shortcuts.xml');
      expect(shortcuts, contains('<share-target'));
      expect(shortcuts, contains('de.atomfritte.axiom.category.CAPTURE'));
      // Die Kategorie muss beidseitig stimmen, sonst erscheint das Ziel nie.
      expect(
        android('kotlin/de/atomfritte/axiom/ShareTargets.kt'),
        contains('de.atomfritte.axiom.category.CAPTURE'),
      );
    });

    test('Health Connect erklärt sich, sonst verweigert das System', () {
      final manifest = android('AndroidManifest.xml');
      expect(manifest, contains('ACTION_SHOW_PERMISSIONS_RATIONALE'));
      expect(manifest, contains('android.intent.action.VIEW_PERMISSION_USAGE'));
    });

    test('gelesen wird nur, was in eine Regel eingeht', () {
      final manifest = android('AndroidManifest.xml');
      expect(manifest, contains('permission.health.READ_SLEEP'));
      expect(manifest, contains('permission.health.READ_STEPS'));
      // Schreibende Health-Berechtigungen waeren ein Eingriff in fremde
      // Daten und in keiner Regel begruendbar.
      expect(manifest, isNot(contains('permission.health.WRITE')));

      // Und nichts, was nicht gelesen wird.
      //
      // READ_HEART_RATE stand hier, ohne dass der Code je einen Puls
      // abgefragt haette — waehrend das Onboarding dem Nutzer ausdruecklich
      // „kein Puls, kein Gewicht, kein Standort" zusagt. Eine Berechtigung,
      // die man nicht braucht, ist keine Kleinigkeit: Sie steht im
      // Systemdialog, der Nutzer erteilt sie, und die Zusage daneben ist
      // damit falsch.
      final declared = RegExp(r'android\.permission\.health\.READ_(\w+)')
          .allMatches(manifest)
          .map((m) => m.group(1)!)
          .toSet();
      final used = File(
              'android/app/src/main/kotlin/de/atomfritte/axiom/HealthBridge.kt')
          .readAsStringSync();
      for (final permission in declared) {
        final record = {
          'SLEEP': 'SleepSessionRecord',
          'STEPS': 'StepsRecord',
        }[permission];
        expect(record, isNotNull,
            reason: 'READ_$permission ist deklariert, aber diesem Test '
                'unbekannt — wird es überhaupt gelesen?');
        expect(used, contains(record!),
            reason: 'READ_$permission wird angefordert, aber nie gelesen');
      }
    });

    test('die Plattformerkennung kommt von Flutter, nicht von uns', () {
      // Eine selbstgebaute `kIsWeb`-Konstante war eine stille Wette darauf,
      // wie der Compiler `dart.library.js_util` fuer Android beantwortet.
      // Faellt sie falsch aus, ist *jede* Systemfunktion tot — ohne dass
      // irgendwo ein Fehler erscheint.
      final source = code(
          File('lib/platform/android_bridge.dart').readAsStringSync());
      expect(source, isNot(contains("bool.fromEnvironment('dart.library")));
      expect(source, contains('package:flutter/foundation.dart'));
    });

    test('der laufende Tag wird nicht als Tagessumme importiert', () {
      // Events sind append-only: Der heutige Schritte-Eimer waechst noch,
      // traegt aber schon eine Quell-ID. Einmal importiert, wuerde er beim
      // naechsten Lauf als "vorhanden" uebersprungen — und der Tag bliebe
      // fuer immer auf dem Stand des ersten Imports.
      expect(
        android('kotlin/de/atomfritte/axiom/HealthBridge.kt'),
        contains('isBefore(today)'),
      );
    });

    test('Health Connect blockiert den Hauptthread nicht', () {
      // Der Aufruf geht ueber eine Prozessgrenze. runBlocking im
      // MethodChannel-Handler ist ein ANR beim Start.
      expect(
        code(android('kotlin/de/atomfritte/axiom/HealthBridge.kt')),
        isNot(contains('runBlocking')),
      );
    });

    test('das Widget-Layout benutzt nur Klassen, die RemoteViews erlaubt', () {
      // RemoteViews inflatet nur Klassen mit @RemoteView. `android.view.View`
      // und `android.widget.Space` gehoeren nicht dazu — der Launcher bricht
      // ab und zeigt "Widget kann nicht angezeigt werden". Von aussen sieht
      // das nach einem kaputten Widget aus; es ist eine einzige Zeile.
      // XML-Kommentare entfernen: Sie erklaeren genau die Begriffe, die im
      // Markup nicht mehr vorkommen duerfen.
      final comments = RegExp(r'<!--.*?-->', dotAll: true);
      for (final file in ['axiom_widget', 'axiom_widget_preview']) {
        final layout =
            android('res/layout/$file.xml').replaceAll(comments, '');
        expect(layout, isNot(contains('<View')), reason: '$file: <View>');
        expect(layout, isNot(contains('<Space')), reason: '$file: <Space>');
      }
    });

    test('kein Systemaufruf wartet unbegrenzt', () {
      // Ein Aufruf ueber den MethodChannel landet auf dem
      // Android-Hauptthread. Blockiert der, bleibt auf der Dart-Seite ein
      // Future offen, das nie fertig wird — und die App steht auf einem
      // Ladekreisel, ohne dass irgendwo ein Fehler steht. Genau so ist sie
      // einmal nicht mehr gestartet.
      //
      // Geprueft wird das ganze Verzeichnis, nicht nur `android_bridge.dart`.
      // Vorher stand hier ein einzelner Dateiname, waehrend der Kanal an
      // zwei Stellen benutzt wird — und die zweite (`intent_handler`) wartete
      // ohne Grenze. Dort haengt zusaetzlich der Merker `_handling`: Kommt
      // die Antwort nie, sammelt diese Seite fuer die Prozesslebensdauer
      // nichts mehr ein, und jede Schnellerfassung bleibt liegen [D9].
      var invocations = 0;
      var timeouts = 0;
      final files = Directory('lib/platform')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      for (final file in files) {
        final source = code(file.readAsStringSync());
        invocations += RegExp(r'invoke(Method|MapMethod|ListMethod)<')
            .allMatches(source)
            .length;
        timeouts += '.timeout('.allMatches(source).length;
      }
      expect(invocations, greaterThan(10));
      expect(timeouts, greaterThanOrEqualTo(invocations),
          reason: '$invocations Aufrufe, aber nur $timeouts mit Zeitgrenze');
    });

    test('Health Connect laeuft nicht auf dem Hauptthread', () {
      // getOrCreate baut eine Binder-Verbindung auf. Auf dem Hauptthread
      // blockiert das die gesamte Oberflaeche.
      final source = code(
          android('kotlin/de/atomfritte/axiom/MainActivity.kt'));
      expect(source, contains('Dispatchers.IO'));
      expect(source, isNot(contains('SupervisorJob() + Dispatchers.Main')));
    });

    test('INTERNET ist deklariert und begründet (ADR-0005)', () {
      final manifest = android('AndroidManifest.xml');
      expect(manifest, contains('android.permission.INTERNET'));
      // Eine Berechtigung ohne Begründung im Manifest ist in einem halben
      // Jahr eine Berechtigung ohne bekannten Grund.
      expect(manifest, contains('ADR-0005'));
    });

    test('die dauerhafte Anzeige meldet, was hängt — nicht, was gewollt war',
        () {
      // Der gespeicherte Schalter wird gesetzt, bevor der Dienst startet.
      // Wer ihn abfragt, bekommt „an" auch dann, wenn nichts erscheint —
      // und wer dann trotzdem „aus" sieht, hat keinen Satz dazu. Genau so
      // sprang der Schalter kommentarlos zurück.
      final screen = code(File('lib/screens/channels_screen.dart')
          .readAsStringSync());
      expect(screen, contains('presenceActive'));
      expect(screen, isNot(contains('presenceEnabled')));

      final service =
          android('kotlin/de/atomfritte/axiom/PresenceService.kt');
      expect(service, contains('activeNotifications'));
      expect(service, contains('IMPORTANCE_NONE'),
          reason: 'Ein einzeln abgeschalteter Kanal ist der häufigste Grund, '
              'aus dem alles „an" aussieht und trotzdem nichts erscheint');
      expect(service, contains('last_error'),
          reason: 'Wirft startForeground, ist die Ausnahme die einzige '
              'Stelle, an der das System den Grund nennt');
    });

    test('die Präsenz erscheint sofort, nicht nach zehn Sekunden', () {
      // Android hält die Benachrichtigung eines Vordergrunddienstes mit
      // niedriger Wichtigkeit sonst bis zu zehn Sekunden zurück. Für eine
      // Präsenz ist das ein Fehler — und für jede Prüfung „hängt sie?"
      // innerhalb dieser zehn Sekunden ein falsches Nein.
      expect(
        android('kotlin/de/atomfritte/axiom/PresenceService.kt'),
        contains('FOREGROUND_SERVICE_IMMEDIATE'),
      );
    });

    test('die Notiz-Rolle führt in keine Sackgasse', () {
      // Ohne die Rolle gibt es in den Standard-Apps keinen Eintrag
      // „Notizen". Sie trotzdem zu öffnen heißt, in einem Menü nach etwas
      // zu suchen, das es dort nicht gibt.
      final source = android('kotlin/de/atomfritte/axiom/MainActivity.kt');
      final block = source.substring(source.indexOf('fun requestNotesRole'));
      final guard = block.indexOf('isRoleAvailable');
      final next = block.indexOf('fun ', 4);
      expect(
        block.substring(guard, next == -1 ? block.length : next),
        isNot(contains('openDefaultApps')),
      );
    });

    test('das Ziel wandert mit dem Alarm mit', () {
      // Ein Anstoß, der auf der Übersicht endet, ist kein Anstoß: Der Weg
      // zur eigentlichen Handlung beginnt dann von vorn [D2]. Der Empfänger
      // muss das Ziel also aus dem Alarm lesen und an die Activity
      // weiterreichen — es steht in keiner Tabelle, an die Kotlin herankommt.
      //
      // Ob jedes Ziel auf beiden Seiten bekannt ist, prüft
      // `bridge_contract_test` als Mengenvergleich: Die frühere Fassung an
      // dieser Stelle verglich nur in eine Richtung und kannte die Aktionen
      // nicht, die die Systemseite selbst schickt.
      final receiver =
          android('kotlin/de/atomfritte/axiom/AlarmReceiver.kt');
      expect(receiver, contains('getStringExtra("route")'));
      expect(receiver, contains('.setAction(route'));
    });

    test('R8 behält jede Klasse, die nur im Manifest steht', () {
      // Eine Activity oder ein Service wird nirgends im Code aufgerufen —
      // das System sucht sie ueber den Namen im Manifest. R8 sieht keine
      // Referenz und wirft sie weg. Der Fehler faellt beim Bauen nicht auf,
      // sondern auf dem Geraet, und dort als „passiert nichts".
      final manifest = android('AndroidManifest.xml');
      final rules =
          File('android/app/proguard-rules.pro').readAsStringSync();

      final components = RegExp(r'android:name="\.([A-Za-z]+)"')
          .allMatches(manifest)
          .map((m) => m.group(1)!)
          .toSet();
      expect(components, isNotEmpty);
      for (final name in components) {
        expect(rules, contains('de.atomfritte.axiom.$name'), reason: name);
      }
    });

    test('das Release ist nicht mit dem Debug-Schlüssel signiert', () {
      // Den Debug-Schluessel kennt jeder Rechner mit Flutter. Eine damit
      // signierte APK laesst sich von jedem als Aktualisierung ueberschreiben.
      final gradle =
          File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('key.properties'));
      expect(gradle, isNot(contains('TODO: Add your own signing config')));
      // Der Rueckfall auf den Debug-Schluessel darf bleiben — aber nur laut.
      expect(gradle, contains('logger.warn'));
    });

    test('die Bitte um die Pille ist auch erlaubt', () {
      // `setRequestPromotedOngoing` ohne diese Berechtigung ist ein
      // Aufruf ins Leere: Android 16 ignoriert ihn, die Benachrichtigung
      // bleibt eine gewoehnliche, und weder Statusleisten-Pille noch
      // Samsungs Now Bar zeigen sie. Genau so lief es seit S3.
      final manifest = android('AndroidManifest.xml');
      final live = android('kotlin/de/atomfritte/axiom/LiveSlotService.kt');
      final presence =
          android('kotlin/de/atomfritte/axiom/PresenceService.kt');

      for (final source in [live, presence]) {
        if (source.contains('setRequestPromotedOngoing')) {
          expect(manifest,
              contains('android.permission.POST_PROMOTED_NOTIFICATIONS'));
        }
      }
      expect(presence, contains('setRequestPromotedOngoing'));
    });

    test('die Pille meldet, was daraus wurde — nicht was möglich wäre', () {
      // `isPromotable` sagt nur, dass das Geraet Android 16 hat. Ob das
      // System die Bitte angenommen hat, steht allein an der geposteten
      // Benachrichtigung.
      expect(
        android('kotlin/de/atomfritte/axiom/LiveSlotService.kt'),
        contains('FLAG_PROMOTED_ONGOING'),
      );
      expect(
        code(File('lib/screens/check_screen.dart').readAsStringSync()),
        contains('presencePromoted'),
      );
    });

    test('mDNS bekommt die Multicast-Sperre, sonst hört es nichts', () {
      // Androids WLAN-Treiber verwirft eingehende Multicast-Pakete,
      // solange niemand die Sperre haelt. Ohne sie laege der Socket nur
      // herum: kein Fehler, kein Log, `axiom.local` loest nirgends auf.
      final manifest = android('AndroidManifest.xml');
      expect(manifest,
          contains('android.permission.CHANGE_WIFI_MULTICAST_STATE'));
      expect(
        android('kotlin/de/atomfritte/axiom/MainActivity.kt'),
        contains('createMulticastLock'),
      );
      expect(
        code(File('lib/server/mdns_responder.dart').readAsStringSync()),
        contains('multicastLock(hold: true)'),
      );
    });

    test('das Zertifikat kennt den Namen, unter dem es aufgerufen wird', () {
      // Ohne passenden Subject Alternative Name lehnt der Browser
      // `axiom.local` rundheraus ab — ohne die Ausnahme anzubieten, die
      // bei der IP noch da war.
      final cert = code(
          File('lib/server/expert_certificate.dart').readAsStringSync());
      expect(cert, contains('kAxiomHostname'));
      // Und ein alt gespeichertes Zertifikat darf nicht weiterverwendet
      // werden, nur weil die Adresse gleich geblieben ist.
      expect(cert, contains('_shape'));
    });

    test('Alarme überleben einen Neustart — alle, nicht nur drei', () {
      // Android verwirft beim Booten jeden Alarm. Der BootReceiver setzte
      // vorher drei fest verdrahtete Check-ins neu; Ankererinnerungen,
      // Abendgrenze und Schlafeintrag blieben weg. Ausgerechnet die
      // Rueckwaertsverkettung eines Termins (M3) — die Erinnerung mit der
      // hoechsten Folgewirkung — ueberlebte keinen Neustart, und zwar
      // lautlos.
      // Ohne Kommentare: Sie erklaeren genau die Begriffe, die im Code
      // nicht mehr vorkommen duerfen.
      final boot = code(android('kotlin/de/atomfritte/axiom/BootReceiver.kt'));
      expect(boot, contains('restoreAll'));
      // Keine fest verdrahteten Zeiten und keine deutschen Texte mehr:
      // Der Empfaenger kennt die Sprache des Nutzers nicht.
      expect(boot, isNot(contains('Check-in')));
      expect(boot, isNot(contains('Calendar')));

      final scheduler =
          code(android('kotlin/de/atomfritte/axiom/MainActivity.kt'));
      expect(scheduler, contains('fun restoreAll'));
      // Gespiegelt beim Planen, vergessen beim Abbestellen — sonst feuert
      // nach einem Neustart ein Alarm, den jemand laengst geloescht hat.
      expect(scheduler, contains('remember(context'));
      expect(scheduler, contains('forget(context, id)'));
    });

    test('die Uhr in der Oberfläche läuft wirklich', () {
      // `nowProvider` aktualisierte sich nur bei einer Nutzeraktion. Damit
      // stand jede Zeitanzeige still: Die Wartezeit der Bremse lief nie ab,
      // die Fokusuhr blieb stehen. Eine Uhr, die nicht laeuft, ist
      // schlimmer als keine — man glaubt ihr.
      final source =
          code(File('lib/state/providers.dart').readAsStringSync());
      final block = source.substring(source.indexOf('final nowProvider'));
      expect(block.substring(0, block.indexOf('});')),
          contains('Timer.periodic'));
    });

    test('der Ort kommt ohne Standortberechtigung aus', () {
      // Der Kern der Entscheidung gegen einen Geofence: Er kostet
      // ACCESS_BACKGROUND_LOCATION — die eingriffstiefste Berechtigung, die
      // Android kennt — und legt in einer Datenbank mit Gesundheitsdaten ein
      // Bewegungsprofil an. Der Gegenwert waere ein Kreis mit 200 m Radius.
      //
      // XML-Kommentare entfernen: Sie nennen genau die Berechtigungen, die
      // im Markup nicht vorkommen duerfen — sie begruenden ja, warum.
      final manifest = android('AndroidManifest.xml')
          .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
      expect(manifest, isNot(contains('ACCESS_FINE_LOCATION')));
      expect(manifest, isNot(contains('ACCESS_COARSE_LOCATION')));
      expect(manifest, isNot(contains('ACCESS_BACKGROUND_LOCATION')));
    });

    test('der Ortsempfänger ist exportiert und hört auf genau eine Aktion',
        () {
      // exported MUSS true sein: Die Routinen-App ist ein anderer Prozess.
      // Mit false kaeme der Broadcast stumm nie an — der haeufigste
      // Fehlermodus dieser Schnittstelle.
      final manifest = android('AndroidManifest.xml');
      final receiver =
          manifest.substring(manifest.indexOf('.PlaceReceiver'));
      final block = receiver.substring(0, receiver.indexOf('</receiver>'));
      expect(block, contains('android:exported="true"'));
      expect(block, contains('de.atomfritte.axiom.PLACE'));

      // Und ohne android:permission. Das prueft den *Sender*, und Samsungs
      // Routinen halten keine selbst definierte Berechtigung von AXIOM —
      // mit ihr waere die Funktion tot statt sicher.
      expect(block, isNot(contains('android:permission')));
    });

    test('der Ortsempfänger setzt einen Ort und tut sonst nichts', () {
      // Ein exportierter Empfaenger ist eine offene Tuer. Sie ist genau so
      // weit auf, wie sie sein muss: Er nimmt einen Namen entgegen, kuerzt
      // ihn und legt ihn ab. Kein Datenbankzugriff, keine Rueckgabe, kein
      // Start von irgendetwas.
      final source =
          code(android('kotlin/de/atomfritte/axiom/PlaceReceiver.kt'));
      expect(source, contains('if (intent.action != ACTION) return'),
          reason: 'Ein exportierter Empfaenger bekommt auch alles, was per '
              'Komponentennamen direkt an ihn geht');
      expect(source, contains('take(MAX_LENGTH)'));
      for (final forbidden in [
        'startActivity',
        'startService',
        'sendBroadcast',
        'SQLite',
        'setResult',
      ]) {
        expect(source, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    test('ein empfangener Ort geht nicht verloren, wenn die App nicht läuft',
        () {
      // Dasselbe Zweischrittmuster wie bei den Notizen: erst lesen, dann
      // speichern lassen, dann erst loeschen. Wer in einem Zug liest und
      // leert, verliert den Eintrag, sobald das Speichern danach scheitert.
      final inbox = android('kotlin/de/atomfritte/axiom/PlaceReceiver.kt');
      expect(inbox, contains('fun peek'));
      expect(inbox, contains('fun ack'));
      expect(inbox, contains('.commit()'),
          reason: 'apply() schreibt im Hintergrund — der Prozess eines '
              'Empfaengers darf vorher beendet werden');

      final handler =
          code(File('lib/platform/intent_handler.dart').readAsStringSync());
      expect(handler, contains('peekPendingPlaces'));
      expect(handler, contains('ackPendingPlaces'));
      // Mit dem Zeitstempel des Empfangs, nicht dem von jetzt: Sonst stuende
      // der Wechsel im Ereignisstrom an der falschen Stelle.
      expect(handler, contains('fromMillisecondsSinceEpoch'));
    });

    test('die Schriftlizenz geht mit den Schriften mit', () {
      // IBM Plex steht unter der SIL Open Font License, und die verlangt
      // beim Weitergeben, dass die Lizenz die Schriften begleitet. Flutter
      // bindet Schriften unter `fonts:` ein und nimmt eine Textdatei
      // daneben nicht mit — beim Verteilen der APK waere das eine
      // Verletzung, die niemandem auffaellt, weil die App laeuft.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('assets/fonts/IBMPlex-OFL.txt'));
      expect(File('assets/fonts/IBMPlex-OFL.txt').existsSync(), isTrue);
      // Und wenn eine Schrift dazukommt, muss auch ihre Lizenz mit.
      final fonts = Directory('assets/fonts')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.ttf'))
          .length;
      expect(fonts, greaterThan(0));
    });

    test('eine gebaute Release-APK trägt keinen x86_64-Maschinencode', () {
      // 24 MB für eine Architektur, auf der diese App nie läuft: x86_64 gibt
      // es unter Android praktisch nur im Emulator, und die Datei wird von
      // Hand installiert — jedes Megabyte trägt jemand über eine Leitung.
      //
      // Warum das ein Test ist und keine Zeile in build.gradle.kts: Ein
      // `abiFilters`-Block dort bleibt folgenlos, weil das Flutter-Plugin die
      // ABIs selbst setzt (nachgemessen — die APK war danach gleich groß).
      // Was wirkt, ist `--target-platform android-arm,android-arm64` am
      // Build. Ein Flag lässt sich vergessen; deshalb prüft das hier die
      // Datei statt die Absicht.
      //
      // Ohne gebaute APK ist der Test still: Er soll niemanden zwingen, vor
      // jedem `flutter test` zu bauen. Er greift beim nächsten Bauen — und
      // genau dann ist er nötig.
      final apk = File('build/app/outputs/flutter-apk/app-release.apk');
      if (!apk.existsSync()) return;

      // Ohne Entpacken: Die Pfadnamen stehen im Zentralverzeichnis der
      // ZIP-Datei im Klartext.
      final raw = String.fromCharCodes(apk.readAsBytesSync());
      expect(
        raw.contains('lib/x86_64/libflutter.so'),
        isFalse,
        reason: 'Die Release-APK enthält die Flutter-Engine für x86_64. '
            'Mit --target-platform android-arm,android-arm64 bauen '
            '(siehe CLAUDE.md → Befehle).',
      );
    });

    test('der Expertenmodus startet nicht von selbst', () {
      final service = android('kotlin/de/atomfritte/axiom/ExpertService.kt');
      expect(service, contains('START_NOT_STICKY'));
      expect(android('AndroidManifest.xml'),
          isNot(contains('EXPERT_START" />')),
          reason: 'Kein Intent-Filter, über den ihn etwas anderes starten '
              'könnte als die App selbst');
    });
  });
}
