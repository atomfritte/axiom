/// Der Expertenmodus — geprüft auf das, was ihn vertretbar macht.
///
/// Hier liegen Gesundheitsdaten auf einem Port. Die Zusagen aus ADR-0005 sind
/// deshalb keine Absichtserklärung, sondern das, was diesen Server von einem
/// offenen Scheunentor unterscheidet. Genau die stehen hier.
library;

import 'dart:convert';
import 'dart:io';

import 'package:axiom_data/axiom_data.dart';

import 'package:axiom_app/server/expert_server.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestHarness h;
  late ExpertServer server;
  late int port;
  var changes = 0;

  setUp(() async {
    // Das Test-Binding faengt HttpClient ab und antwortet pauschal mit 400.
    // Hier soll aber der echte Server geprueft werden, nicht die Attrappe.
    HttpOverrides.global = null;
    h = TestHarness.create();
    changes = 0;
    server = ExpertServer(
      resolveRuntime: () async => h.runtime,
      onChanged: () => changes++,
    );
    // Port 0 waehlt das System — sonst kollidieren parallele Testlaeufe.
    final status = await server.start(port: 0);
    port = int.parse(status.address!.split(':').last);
  });

  tearDown(() async {
    await server.stop();
    h.dispose();
  });

  Future<HttpClientResponse> call(
    String method,
    String path, {
    Object? body,
    String? cookie,
  }) async {
    final client = HttpClient();
    final request = await client.open(method, '127.0.0.1', port, path);
    if (cookie != null) request.headers.add('cookie', cookie);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    return request.close();
  }

  Future<Map<String, Object?>> json(HttpClientResponse res) async =>
      jsonDecode(await res.transform(utf8.decoder).join())
          as Map<String, Object?>;

  Future<String> login(String pin) async {
    final res = await call('POST', '/api/login', body: {'pin': pin});
    return res.headers.value('set-cookie')!.split(';').first;
  }

  group('Ohne PIN kommt niemand an Daten', () {
    test('jede Datenroute antwortet mit 401', () async {
      for (final path in [
        '/api/state',
        '/api/tasks',
        '/api/rules',
        '/api/events',
      ]) {
        expect((await call('GET', path)).statusCode, 401, reason: path);
      }
    });

    test('auch Schreibzugriffe', () async {
      final res = await call('POST', '/api/tasks', body: {'title': 'x'});
      expect(res.statusCode, 401);
      expect(await h.store.tasks(), isEmpty);
    });

    test('die Seite selbst ist nicht geheim, die Daten sind es', () async {
      // Sonst müsste man die PIN in die URL schreiben, und dann steht sie im
      // Verlauf des Browsers.
      final res = await call('GET', '/');
      expect(res.statusCode, 200);
    });

    test('eine falsche PIN sagt, wie viele Versuche bleiben', () async {
      final res = await call('POST', '/api/login', body: {'pin': '000000'});
      expect(res.statusCode, 401);
      expect((await json(res))['attemptsLeft'], kExpertMaxAttempts - 1);
    });

    test('nach fünf Fehlversuchen schaltet sich der Server ab', () async {
      for (var i = 0; i < kExpertMaxAttempts; i++) {
        await call('POST', '/api/login', body: {'pin': '000000'});
      }
      expect(server.isRunning, isFalse,
          reason: 'Ein Zählwerk, das man aussitzen kann, ist keines');
      expect(server.status.pin, isNull);
    });
  });

  group('Mit PIN', () {
    test('die Sitzung läuft über ein Cookie, nicht über die URL', () async {
      final cookie = await login(server.status.pin!);
      expect(cookie, startsWith('axiom_session='));

      final res = await call('GET', '/api/state', cookie: cookie);
      expect(res.statusCode, 200);
      expect((await json(res))['values'], isNotEmpty);
    });

    test('Aufgaben lassen sich anlegen und ändern', () async {
      final cookie = await login(server.status.pin!);

      final created = await json(await call('POST', '/api/tasks',
          cookie: cookie,
          body: {'title': 'Steuerunterlagen sortieren', 'activationEnergy': 8}));
      expect(created['title'], 'Steuerunterlagen sortieren');
      expect(created['activationEnergy'], 8);

      final patched = await json(await call(
          'PATCH', '/api/tasks/${created['id']}',
          cookie: cookie, body: {'activationEnergy': 3, 'state': 'done'}));
      expect(patched['activationEnergy'], 3);
      expect(patched['state'], 'done');
      expect(changes, greaterThan(0),
          reason: 'Was im Browser passiert, muss auf dem Telefon ankommen');
    });

    test('eine ungültige Regel wird abgelehnt, nicht übersprungen', () async {
      final cookie = await login(server.status.pin!);
      final res = await call('PUT', '/api/rules/R-001',
          cookie: cookie, body: {'yaml': '- id: R-001\n  title: "ohne alles"'});

      expect(res.statusCode, 400);
      expect((await json(res))['issues'], isNotEmpty);
      expect(h.store.ruleOverrides(), isEmpty,
          reason: 'Abgelehnt heißt: nichts gespeichert');
    });

    test('eine geänderte Regel läuft erst einmal stumm mit', () async {
      final cookie = await login(server.status.pin!);
      final rules = await json(await call('GET', '/api/rules', cookie: cookie));
      final first = (rules['rules']! as List).first as Map<String, Object?>;

      final res = await call('PUT', '/api/rules/${first['id']}',
          cookie: cookie, body: {'yaml': first['yaml']});
      expect(res.statusCode, 200);

      final saved = h.store.ruleOverrides().single;
      expect(saved.isShadowed(h.clock.nowLocal()), isTrue,
          reason: 'Dieselbe Zusage wie im Editor auf dem Telefon');
    });

    test('die ID einer Regel lässt sich nicht umbiegen', () async {
      // IDs werden nie wiederverwendet — auch nicht durch Umbenennen.
      final cookie = await login(server.status.pin!);
      final rules = await json(await call('GET', '/api/rules', cookie: cookie));
      final first = (rules['rules']! as List).first as Map<String, Object?>;
      final renamed =
          (first['yaml']! as String).replaceFirst(first['id']! as String, 'R-999');

      final res = await call('PUT', '/api/rules/${first['id']}',
          cookie: cookie, body: {'yaml': renamed});
      expect(res.statusCode, 400);
    });

    test('Ereignisse sind nur lesbar', () async {
      final cookie = await login(server.status.pin!);
      await h.runtime.capture('Testgedanke');
      final res = await json(await call('GET', '/api/events', cookie: cookie));
      expect(res['events'], isNotEmpty);

      // Es gibt keinen Weg, ein Ereignis zu ändern oder zu löschen.
      expect((await call('DELETE', '/api/events', cookie: cookie)).statusCode,
          404);
    });
  });

  group('Der Server geht von selbst wieder aus', () {
    test('Stopp beendet die Sitzung, nicht nur den Port', () async {
      final cookie = await login(server.status.pin!);
      await server.stop();
      expect(server.isRunning, isFalse);
      expect(server.status, ExpertStatus.off);

      // Und die alte PIN gilt nach einem Neustart nicht mehr.
      final before = server.status.pin;
      await server.start(port: 0);
      expect(server.status.pin, isNot(before));

      // Auch das alte Cookie nicht.
      final newPort = int.parse(server.status.address!.split(':').last);
      final client = HttpClient();
      final request =
          await client.open('GET', '127.0.0.1', newPort, '/api/state');
      request.headers.add('cookie', cookie);
      expect((await request.close()).statusCode, 401);
    });

    test('die Leerlaufgrenze ist gesetzt und nicht unendlich', () {
      expect(kExpertIdleTimeout.inMinutes, lessThanOrEqualTo(60));
      expect(server.status.idleStopAt, isNotNull);
    });
  });

  group('Der Dienst startet nur auf Kommando', () {
    String android(String path) =>
        File('android/app/src/main/$path').readAsStringSync();

    test('kein START_STICKY — ein Port geht nicht von selbst wieder auf', () {
      final source = android('kotlin/de/axiom/axiom_app/ExpertService.kt');
      expect(source, contains('START_NOT_STICKY'));
      expect(source, isNot(contains('return START_STICKY')));
    });

    test('kein Autostart beim Hochfahren', () {
      // BootReceiver stellt Alarme wieder her. Einen Server wiederherzustellen
      // waere etwas voellig anderes.
      expect(android('kotlin/de/axiom/axiom_app/BootReceiver.kt'),
          isNot(contains('Expert')));
    });

    test('der Modus beginnt ausgeschaltet', () {
      expect(ExpertStatus.off.running, isFalse);
      expect(ExpertStatus.off.pin, isNull);
      expect(ExpertStatus.off.address, isNull);
    });
  });
}
