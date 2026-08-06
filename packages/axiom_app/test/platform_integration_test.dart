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

import 'package:axiom_app/platform/android_bridge.dart';
import 'package:axiom_app/platform/health_sync.dart';

void main() {
  group('Ohne Android bleibt alles bedienbar', () {
    test('Systemaufrufe sind stille No-ops, keine Ausnahmen', () async {
      // Der Desktop-Companion laeuft auf demselben Code. Wuerde ein
      // Systemaufruf dort werfen, waere die App auf dem Rechner unbrauchbar.
      expect(AndroidBridge.isSupported, isFalse);
      expect(await AndroidBridge.startLiveSlot(
        kind: 'focus',
        title: 'Test',
        detail: '',
        startedAt: DateTime(2026, 1, 1),
        planned: const Duration(minutes: 50),
      ), isFalse);
      expect(await AndroidBridge.stopLiveSlot(), isFalse);
      expect(await AndroidBridge.liveSlotRunning(), isFalse);
      expect(await AndroidBridge.liveSlotPromotable(), isFalse);
      expect(await AndroidBridge.healthStatus(), isEmpty);
      expect(await AndroidBridge.healthRead(DateTime(2026)), isEmpty);
    });

    test('Health Connect meldet sich als nicht verfügbar, nicht als Fehler',
        () async {
      expect(await HealthSync.availability(), HealthAvailability.unavailable);
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
      final source = code(
          File('lib/platform/android_bridge.dart').readAsStringSync());
      final invocations = RegExp(r'invoke(Method|MapMethod|ListMethod)<')
          .allMatches(source)
          .length;
      final timeouts = '.timeout('.allMatches(source).length;
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

    test('jede Benachrichtigung führt an ihr Ziel, nicht nur in die App',
        () {
      // Ein Anstoß, der auf der Übersicht endet, ist kein Anstoß: Der Weg
      // zur eigentlichen Handlung beginnt dann von vorn [D2].
      final receiver =
          android('kotlin/de/atomfritte/axiom/AlarmReceiver.kt');
      expect(receiver, contains('getStringExtra("route")'));
      expect(receiver, contains('.setAction(route'));

      // Jedes Ziel, das gesendet wird, muss auch angenommen werden. Eine
      // Route, die die Whitelist nicht kennt, landet stumm auf der
      // Übersicht — funktionierend genug, um nicht aufzufallen.
      final bridge =
          code(File('lib/platform/android_bridge.dart').readAsStringSync());
      // Das Praefix wird aus dem Manifest gelesen, nicht hier
      // hineingeschrieben: Beim Wechsel der Paketkennung waere ein fest
      // verdrahtetes Muster still leer geworden — der Test haette dann
      // nichts mehr geprueft und trotzdem gruen gemeldet.
      final pkg = RegExp(r'applicationId = "([a-z.]+)"')
              .firstMatch(File('android/app/build.gradle.kts').readAsStringSync())
              ?.group(1) ??
          'de.atomfritte.axiom';
      // Nur die Konstanten aus `AxiomRoute` — nicht jede Zeichenkette, die
      // so aussieht.
      //
      // Vorher schoepfte das Muster die ganze Datei ab. Das fiel nicht auf,
      // solange die ausgehenden Broadcasts anders hiessen (`axiom.FOCUS_START`
      // ohne Praefix); seit sie dieselbe Form haben, verlangte der Test, dass
      // ein Broadcast an eine Routine in der Start-Whitelist steht. Er tut
      // dort nichts zu suchen: Das eine sagt „AXIOM oeffnen und dorthin",
      // das andere sagt einem fremden System „bei mir ist gerade etwas
      // passiert".
      final routeBlock = bridge.substring(
        bridge.indexOf('abstract final class AxiomRoute'),
      );
      final routes = RegExp("'(${RegExp.escape(pkg)}\\.[A-Z_]+)'")
          .allMatches(routeBlock.substring(0, routeBlock.indexOf('}')))
          .map((m) => m.group(1)!)
          .toSet();
      expect(routes, isNotEmpty);
      final main = android('kotlin/de/atomfritte/axiom/MainActivity.kt');
      final whitelist = main.substring(main.indexOf('fun consumeLaunchAction'));
      for (final route in routes) {
        expect(whitelist, contains('"$route"'), reason: route);
      }

      // Und die Dart-Seite muss wissen, was sie damit tut.
      final handler =
          code(File('lib/platform/intent_handler.dart').readAsStringSync());
      expect(handler, contains('AxiomRoute.checkin'));
      expect(handler, contains('AxiomRoute.anchors'));
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
