/// Was passiert, wenn der Schlüssel fehlt, die Datenbank neu geöffnet wird
/// und ein Regel-Asset dazukommt.
///
/// Drei Fragen, ein Testfile, weil sie denselben Weg teilen: den Start.
/// Alle drei kosten, wenn sie falsch beantwortet werden, entweder den
/// gesamten Ereignisstrom (B5), die laufende Sitzung (B4) oder eine Regel,
/// von der niemand erfährt (B27).
library;

import 'dart:io';

import 'package:axiom_app/design/tokens.dart';
import 'package:axiom_app/i18n/i18n.dart';
import 'package:axiom_app/platform/android_bridge.dart';
import 'package:axiom_app/state/providers.dart';
import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ein Asset-Bundle, dessen Inhalt der Test bestimmt.
///
/// Nötig, weil die Frage „findet die App eine Regeldatei, die es beim
/// Schreiben dieses Tests noch nicht gab" mit dem echten Bundle nicht zu
/// stellen ist — dort liegen genau die fünf Dateien, die auch in der festen
/// Liste standen.
final class _FakeBundle extends CachingAssetBundle {
  /// Was das Manifest aufzählt.
  final List<String> listed;

  /// Was sich davon tatsächlich lesen lässt.
  final Map<String, String> readable;

  _FakeBundle({required this.listed, required this.readable});

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, Object>{
        for (final asset in listed) asset: const <Object>[],
      })!;
    }
    final content = readable[key];
    if (content == null) {
      throw FlutterError('Asset nicht im Paket: $key');
    }
    final bytes = Uint8List.fromList(content.codeUnits);
    return ByteData.view(bytes.buffer);
  }
}

Event _capture(Clock clock, String id, String text) => Event(
      id: id,
      at: clock.nowUtc(),
      type: EventType.capture,
      source: EventSource.user,
      payload: {'text': text},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Schlüsselzustand (B5)', () {
    test('drei Zustände, nicht zwei', () {
      expect(
        DatabaseKeyResult.fromMessage(
          const {'state': 'ready', 'key': 'cGFzc3dvcnQ='},
        ).state,
        DatabaseKeyState.ready,
      );
      expect(
        DatabaseKeyResult.fromMessage(
          const {'state': 'ready', 'key': 'cGFzc3dvcnQ='},
        ).key,
        'cGFzc3dvcnQ=',
      );
      expect(
        DatabaseKeyResult.fromMessage(const {'state': 'none', 'key': null})
            .state,
        DatabaseKeyState.none,
      );
      expect(
        DatabaseKeyResult.fromMessage(
          const {'state': 'unavailable', 'key': null},
        ).state,
        DatabaseKeyState.unavailable,
      );
    });

    test('eine unklare Antwort gilt nie als „hier gibt es keinen"', () {
      // Der teure Fehler war, dass jeder Fehlschlag wie „unverschlüsselt"
      // aussah. Eine ausgebliebene, halbe oder unbekannte Antwort muss
      // deshalb in die andere Richtung fallen: nichts anfassen.
      for (final message in <Map<String, Object?>?>[
        null,
        const {},
        const {'state': 'ready'}, // Zustand ja, Schlüssel nein
        const {'state': 'ready', 'key': ''},
        const {'state': 'irgendwas'},
      ]) {
        expect(
          DatabaseKeyResult.fromMessage(message).state,
          DatabaseKeyState.unavailable,
          reason: '$message',
        );
      }
    });

    test('die Systemseite meldet denselben Zustand zurück', () {
      // Widget-Tests fallen durch die Kotlin-Ebene hindurch — geprüft wird
      // deshalb der Quelltext, wie in platform_integration_test.
      final source = File(
        'android/app/src/main/kotlin/de/atomfritte/axiom/DatabaseKey.kt',
      ).readAsStringSync();

      for (final state in ['"ready"', '"none"', '"unavailable"']) {
        expect(source, contains(state), reason: state);
      }

      // Und der eigentliche Punkt: Lässt sich ein vorhandener Schlüssel
      // nicht auswickeln, wird kein neuer erzeugt. Vorher fiel der Code
      // dort durch zur Schlüsselerzeugung — und die alte, mit dem alten
      // Schlüssel verschlüsselte Datei war damit endgültig verloren.
      final unwrapBranch = source.substring(
        source.indexOf('if (stored != null && iv != null)'),
        source.indexOf('val fresh = ByteArray(PASSPHRASE_BYTES)'),
      );
      expect(unwrapBranch, contains('return reply(STATE_UNAVAILABLE)'));
    });
  });

  group('Datenbank öffnen (B5)', () {
    late Directory dir;
    late FakeClock clock;
    late String path;

    setUp(() {
      clock = FakeClock(DateTime.utc(2026, 8, 6, 12));
      dir = Directory.systemTemp.createTempSync('axiom_db_test');
      path = '${dir.path}${Platform.pathSeparator}axiom.db';
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('eine lesbare Datei wird nicht weggeworfen, nur weil ein Schlüssel '
        'dazugekommen ist', () async {
      // Genau der Ablauf aus B5: Der Keystore antwortete beim ersten Start
      // nicht, die Datenbank entstand im Klartext, beim zweiten Start war
      // der Schlüssel da. Vorher waren an dieser Stelle alle Ereignisse weg.
      var store = openAxiomDatabase(path, clock, null);
      await store.append(_capture(clock, 'e1', 'Steuerunterlagen'));
      await store.append(_capture(clock, 'e2', 'Rückruf Werkstatt'));
      store.close();

      store = openAxiomDatabase(path, clock, 'c3BhZXRlciBrYW0gZWluIFNjaGx1ZXNzZWw=');
      addTearDown(store.close);

      expect((await store.query()).length, 2);
      expect(store.setting(kDatabaseResetSetting), isNull);
    });

    test('eine wirklich unlesbare Datei wird neu angelegt und das steht drin',
        () async {
      // Die Gegenprobe: verschlüsselt mit einem Schlüssel, geöffnet mit
      // einem anderen. Hier ist nichts mehr zu retten, und der Neuanfang
      // bleibt die dokumentierte Entscheidung — sichtbar gemacht statt
      // verschwiegen.
      var store = openAxiomDatabase(path, clock, 'ZXJzdGVyIFNjaGx1ZXNzZWw=');
      await store.append(_capture(clock, 'e1', 'Steuerunterlagen'));
      store.close();

      store = openAxiomDatabase(path, clock, 'endlZ2l0ZXIgU2NobHVlc3NlbA==');
      addTearDown(store.close);

      expect((await store.query()), isEmpty);
      expect(store.setting(kDatabaseResetSetting), isNotNull);
    });
  });

  group('Regelwerk aus dem Paket (B27)', () {
    test('jede Regeldatei im Paket wird geladen, auch eine neue', () async {
      final bundle = _FakeBundle(
        listed: const [
          'assets/rules/limits.yaml',
          'assets/rules/s4-signals.yaml',
          'assets/help/de/01-start.md',
        ],
        readable: const {
          'assets/rules/limits.yaml': 'global_limits:\n  '
              'max_interventions_per_day: 12\n',
          'assets/rules/s4-signals.yaml': '- id: R-160\n'
              '  title: Test\n'
              '  rationale: Test\n'
              '  when: { always: true }\n'
              '  then: { action: nudge }\n'
              '  cooldown: 1h\n',
        },
      );

      final bundled = await loadBundledRules(bundle);

      // Die feste Liste im Quelltext kannte s4-signals.yaml nicht — die
      // Regel darin wäre nie geladen worden, ohne dass irgendwo etwas steht.
      expect(bundled.sources.keys, containsAll(['limits.yaml', 's4-signals.yaml']));
      expect(bundled.issues, isEmpty);
      // Und nichts, was keine Regeldatei ist.
      expect(bundled.sources.keys, isNot(contains('01-start.md')));
    });

    test('ein Asset, das sich nicht lesen lässt, wird gemeldet', () async {
      final bundle = _FakeBundle(
        listed: const [
          'assets/rules/limits.yaml',
          'assets/rules/s2-live.yaml',
        ],
        readable: const {'assets/rules/limits.yaml': 'global_limits:\n'},
      );

      final bundled = await loadBundledRules(bundle);

      expect(bundled.sources.keys, ['limits.yaml']);
      expect(bundled.issues, hasLength(1));
      expect(bundled.issues.single.source, 'assets/rules/s2-live.yaml');
    });

    test('ein leeres Paket ist ein Befund, kein stiller Start', () async {
      final bundled = await loadBundledRules(
        _FakeBundle(listed: const [], readable: const {}),
      );
      expect(bundled.sources, isEmpty);
      expect(bundled.issues, hasLength(1));
    });

    test('im echten Paket liegt, was in assets/rules/ liegt', () async {
      final onDisk = Directory('assets/rules')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList()
        ..sort();
      final bundled = await loadBundledRules();
      expect(bundled.sources.keys.toList()..sort(), onDisk);
      expect(bundled.issues, isEmpty);
    });
  });

  group('Neuaufbau der Laufzeit (B4)', () {
    test('ein invalidate schließt die Datenbank nicht', () async {
      final clock = FakeClock(DateTime.utc(2026, 8, 6, 12));
      final store = SqliteEventStore.inMemory(clock: clock);
      addTearDown(store.close);
      store.setSetting('language', 'de');

      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(clock),
          // Die Verbindung gehört dem Test, nicht der Laufzeit — genau wie
          // in der App, wo sie dem storeProvider gehört. Schließt sie
          // trotzdem jemand, kann es nur runtimeProvider gewesen sein.
          storeProvider.overrideWith((ref) async => store),
        ],
      );
      addTearDown(container.dispose);

      final before = await container.read(runtimeProvider.future);
      expect(before.rules, isNotEmpty);

      // Das passiert nach jedem gespeicherten Regeleintrag und nach jeder
      // Änderung im Expertenmodus.
      container.invalidate(runtimeProvider);

      // Riverpod gibt während des Neuaufbaus weiterhin die alte Laufzeit
      // heraus. Wer sie liest, muss lesen können.
      final stale = container.read(runtimeProvider).value;
      expect(stale, isNotNull);
      expect(stale!.onboardingDone, isFalse);
      expect(container.read(themeModeProvider), 0);
      expect(container.read(textSizeProvider), TextSize.normal);
      expect(container.read(languageProvider), AppLanguage.de);

      // Und danach steht die neue Laufzeit auf derselben Datenbank.
      final after = await container.read(runtimeProvider.future);
      expect(after.onboardingDone, isFalse);
      expect(identical(after.store, store), isTrue);
    });
  });
}
