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

    test('INTERNET bleibt auch mit Health Connect draußen (ADR-0002)', () {
      expect(
        android('AndroidManifest.xml'),
        isNot(contains('android.permission.INTERNET')),
      );
    });
  });
}
