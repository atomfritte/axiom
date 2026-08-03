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
      expect(shortcuts, contains('de.axiom.category.CAPTURE'));
      // Die Kategorie muss beidseitig stimmen, sonst erscheint das Ziel nie.
      expect(
        android('kotlin/de/axiom/axiom_app/ShareTargets.kt'),
        contains('de.axiom.category.CAPTURE'),
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
        android('kotlin/de/axiom/axiom_app/HealthBridge.kt'),
        contains('isBefore(today)'),
      );
    });

    test('Health Connect blockiert den Hauptthread nicht', () {
      // Der Aufruf geht ueber eine Prozessgrenze. runBlocking im
      // MethodChannel-Handler ist ein ANR beim Start.
      expect(
        code(android('kotlin/de/axiom/axiom_app/HealthBridge.kt')),
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
          android('kotlin/de/axiom/axiom_app/MainActivity.kt'));
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
          android('kotlin/de/axiom/axiom_app/PresenceService.kt');
      expect(service, contains('activeNotifications'));
      expect(service, contains('IMPORTANCE_NONE'),
          reason: 'Ein einzeln abgeschalteter Kanal ist der häufigste Grund, '
              'aus dem alles „an" aussieht und trotzdem nichts erscheint');
    });

    test('die Notiz-Rolle führt in keine Sackgasse', () {
      // Ohne die Rolle gibt es in den Standard-Apps keinen Eintrag
      // „Notizen". Sie trotzdem zu öffnen heißt, in einem Menü nach etwas
      // zu suchen, das es dort nicht gibt.
      final source = android('kotlin/de/axiom/axiom_app/MainActivity.kt');
      final block = source.substring(source.indexOf('fun requestNotesRole'));
      final guard = block.indexOf('isRoleAvailable');
      final next = block.indexOf('fun ', 4);
      expect(
        block.substring(guard, next == -1 ? block.length : next),
        isNot(contains('openDefaultApps')),
      );
    });

    test('der Expertenmodus startet nicht von selbst', () {
      final service = android('kotlin/de/axiom/axiom_app/ExpertService.kt');
      expect(service, contains('START_NOT_STICKY'));
      expect(android('AndroidManifest.xml'),
          isNot(contains('EXPERT_START" />')),
          reason: 'Kein Intent-Filter, über den ihn etwas anderes starten '
              'könnte als die App selbst');
    });
  });
}
