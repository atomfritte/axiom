/// Der Expertenmodus — geprüft auf das, was ihn vertretbar macht.
///
/// Hier liegen Gesundheitsdaten auf einem Port. Die Zusagen aus ADR-0005 sind
/// deshalb keine Absichtserklärung, sondern das, was diesen Server von einem
/// offenen Scheunentor unterscheidet. Genau die stehen hier.
///
/// **Warum diese Datei mehr Zeit bekommt.** Sie startet in jedem `setUp`
/// einen echten HTTPS-Server, und der erzeugt sich ein Zertifikat samt
/// frischem RSA-Schlüssel — die Testdatenbank liegt im Speicher, also
/// greift der Zwischenspeicher in `ExpertCertificates.forAddress` nicht.
/// Bei rund hundert Fällen sind das rund hundert Schlüssel. Allein läuft die
/// Datei in gut vier Minuten durch; im vollen Lauf, neben allen anderen
/// Dateien, rissen einzelne Fälle die voreingestellten 30 Sekunden — und
/// was danach kam, war Folgeschaden: „This database has already been
/// closed", weil der abgebrochene Fall sein Gerüst mitnahm.
///
/// Das ist eine ehrliche Kosten-, keine Fehlerursache. Geprüft wird der
/// echte Weg durch TLS, und genau deshalb fängt diese Datei Fehler, die eine
/// Attrappe durchließe. Angehoben wird deshalb die Grenze, nicht die
/// Prüfung verdünnt.
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:axiom_core/axiom_core.dart'
    show CompareOp, EventType, RuleVocabulary, Severity;
import 'package:axiom_data/axiom_data.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:axiom_app/server/expert_certificate.dart';
import 'package:axiom_app/server/expert_server.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// Fingerabdruck wie ihn die App anzeigt — in Vierergruppen.
String _fingerprint(X509Certificate cert) {
  final hex = sha256
      .convert(cert.der)
      .bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
  final buffer = StringBuffer();
  for (var i = 0; i < hex.length; i += 4) {
    if (i > 0) buffer.write(i % 16 == 0 ? '\n' : ' ');
    buffer.write(hex.substring(i, i + 4));
  }
  return buffer.toString();
}

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
      // Dieselbe gestellte Uhr wie die Laufzeit. Ohne sie liesse sich die
      // Neunzig-Sekunden-Frist nicht ueberspringen — und genau deshalb hat
      // sie bis zu dieser Runde kein Test geprueft.
      clock: h.clock,
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
    Map<String, String> headers = const {},
  }) async {
    // Selbst signiert: Der Test akzeptiert genau dieses eine Zertifikat —
    // deshalb wird der Fingerabdruck geprueft, nicht blind alles erlaubt.
    final client = HttpClient()
      ..badCertificateCallback = (cert, host, port) =>
          _fingerprint(cert) == server.status.fingerprint;
    final request = await client.openUrl(
        method, Uri.parse('https://127.0.0.1:$port$path'));
    if (cookie != null) request.headers.add('cookie', cookie);
    headers.forEach(request.headers.add);
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

  group('Zeit im System wird gemessen, nicht geschätzt (G4, M12)', () {
    // Gebucht wird der Abstand zwischen zwei angemeldeten Anfragen. Die
    // Weboberfläche fragt aber von selbst weiter, auch aus einem Reiter, den
    // seit Stunden niemand ansieht — gemessen wurde damit Laufzeit statt
    // Nutzung, und der Deckel meldete 115 von 12 Minuten an einem Tag ohne
    // einen einzigen Blick. Ein Deckel, der falsch misst, ist schlimmer als
    // keiner: Er gewöhnt einen daran, die eine Zahl zu übergehen, die G4
    // durchsetzen soll.
    late String cookie;

    setUp(() async => cookie = await login(server.status.pin!));

    /// Eine Anfrage, die sich als beachtet oder unbeachtet ausweist.
    Future<void> ping({required bool attended}) async {
      final res = await call('GET', '/api/state',
          cookie: cookie,
          headers: {'X-Axiom-Attended': attended ? '1' : '0'});
      // Die Antwort muss gelesen werden, sonst bleibt die Verbindung offen
      // und der `tearDown` haengt.
      await json(res);
    }

    Future<Duration> gebucht() => h.store.usageToday(h.clock.nowLocal());

    test('zwei beachtete Anfragen buchen den Abstand dazwischen', () async {
      await ping(attended: true);
      h.clock.advance(const Duration(seconds: 60));
      await ping(attended: true);

      expect(await gebucht(), const Duration(seconds: 60));
    });

    test('derselbe Abstand aus dem Hintergrund bucht nichts', () async {
      await ping(attended: false);
      h.clock.advance(const Duration(seconds: 60));
      await ping(attended: false);

      expect(await gebucht(), Duration.zero);
    });

    test('die Zeit im Hintergrund faellt auch dazwischen heraus', () async {
      // Der Fall, um den es geht: kurz gearbeitet, Reiter weggelegt, eine
      // halbe Stunde später wieder hingesehen. Gebucht gehören die zwei
      // Minuten Arbeit, nicht die halbe Stunde.
      await ping(attended: true);
      h.clock.advance(const Duration(seconds: 45));
      await ping(attended: true);

      for (var i = 0; i < 30; i++) {
        h.clock.advance(const Duration(minutes: 1));
        await ping(attended: false);
      }
      h.clock.advance(const Duration(seconds: 30));
      await ping(attended: true);

      expect(await gebucht(), const Duration(seconds: 45),
          reason: 'Die halbe Stunde Hintergrund ist mitgebucht worden');
    });

    test('ohne den Kopf wird gezählt, nicht geschwiegen', () async {
      // Ein Deckel, den man durch das WEGLASSEN eines Kopfes abschaltet,
      // wäre keiner. Der Fehlerfall muss zu viel buchen, nicht zu wenig.
      await json(await call('GET', '/api/state', cookie: cookie));
      h.clock.advance(const Duration(seconds: 60));
      await json(await call('GET', '/api/state', cookie: cookie));

      expect(await gebucht(), const Duration(seconds: 60));
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

    test('die Sprache der App kommt mit', () async {
      // Die Weboberfläche richtet sich danach, nicht nach dem Browser: Wer
      // vom englischen Arbeitsrechner auf ein deutsches Telefon sieht, soll
      // nicht denselben Satz zweimal verschieden lesen. Ein Quelltextver-
      // gleich reicht dafür nicht — hier wird abgerufen.
      final cookie = await login(server.status.pin!);

      h.runtime.language = 'en';
      expect((await json(await call('GET', '/api/state', cookie: cookie)))
          ['language'], 'en');

      h.runtime.language = 'de';
      expect((await json(await call('GET', '/api/state', cookie: cookie)))
          ['language'], 'de');
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

    test('eine Änderung im Browser überlebt den Wiederaufbau', () async {
      // Der Befund, den drei Prüfer unabhängig gefunden haben: PATCH schrieb
      // nur die Projektion (`store.upsertTask`), ohne Ereignis. `tasks` baut
      // `rebuildProjections()` aber allein aus dem Strom — nach dem nächsten
      // Vault-Import standen Titel, Anlaufenergie, Salienz, Stakes und Frist
      // wieder auf dem Stand der Anlage. Es war der einzige upsertTask-Aufruf
      // der App ohne passendes Ereignis, und er verlor Daten stillschweigend.
      //
      // Dieser Test prüft nicht, DASS ein Ereignis geschrieben wird — das
      // wäre die Implementierung. Er prüft die Wirkung: Wirf die Projektion
      // weg und bau sie aus dem Strom neu. Was der Browser geändert hat,
      // muss danach noch da sein.
      final cookie = await login(server.status.pin!);
      final created = await json(await call('POST', '/api/tasks',
          cookie: cookie,
          body: {'title': 'Steuerunterlagen sortieren', 'activationEnergy': 8}));

      final frist = DateTime.utc(2026, 9, 1, 12);
      await call('PATCH', '/api/tasks/${created['id']}', cookie: cookie, body: {
        'title': 'Steuerunterlagen für 2025 sortieren',
        'activationEnergy': 3,
        'salience': 9,
        'stakes': 7,
        'decayAt': frist.toIso8601String(),
      });

      await h.store.rebuildProjections();

      final rebuilt =
          (await h.store.tasks()).firstWhere((t) => t.id == created['id']);
      expect(rebuilt.title, 'Steuerunterlagen für 2025 sortieren');
      expect(rebuilt.activationEnergy, 3);
      expect(rebuilt.salience, 9);
      expect(rebuilt.stakes, 7);
      expect(rebuilt.decayAt?.toUtc(), frist);
    });

    test('ein reiner Zustandswechsel erzählt keine zusätzliche Änderung',
        () async {
      // Die Gegenprobe. Ein PATCH, der nur den Zustand wechselt, hat seinen
      // Weg über completeTask/dropTask schon gemacht — eine zusätzliche
      // Korrektur daneben behauptete eine Änderung, die es nicht gab, und
      // stünde für immer im Ereignisstrom.
      final cookie = await login(server.status.pin!);
      final created = await json(await call('POST', '/api/tasks',
          cookie: cookie, body: {'title': 'Wohnung lüften'}));

      final vorher = (await h.store.query()).length;
      await call('PATCH', '/api/tasks/${created['id']}',
          cookie: cookie, body: {'state': 'done'});
      final nachher = await h.store.query();

      expect(nachher.length, vorher + 1,
          reason: 'Genau ein Ereignis: der Abschluss. Keine Korrektur daneben');
      expect(nachher.last.type, EventType.taskCompleted);
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

  group('Die Oberfläche und der Server passen zusammen', () {
    test('jede Route, die die Seite ruft, gibt es auch', () async {
      // Der Fall, der sonst erst auf dem Schreibtisch auffaellt: ein Knopf,
      // der eine Route ruft, die es nicht gibt. Im Browser sieht das aus
      // wie „passiert nichts" — dieselbe Fehlerklasse, die uns auf Android
      // eine Woche gekostet hat.
      final page = File('assets/expert/index.html').readAsStringSync();
      final server = File('lib/server/expert_server.dart').readAsStringSync();
      final routes = RegExp(r'''['"](/api/[a-z/]+)''')
          .allMatches(page)
          .map((m) => m.group(1)!)
          .toSet();
      expect(routes, isNotEmpty);
      for (final route in routes) {
        final segments = route.split('/').where((s) => s.isNotEmpty);
        final pattern = "'${segments.join("', '")}'";
        expect(server.contains(pattern) || server.contains(route), isTrue,
            reason: 'Die Seite ruft $route — der Server kennt sie nicht');
      }
    });

    test('die Seite lädt nichts von außen', () {
      // ADR-0005: AXIOM ruft nichts von sich aus auf. Eine Schriftart oder
      // ein Skript von einem fremden Server waere genau das — und die
      // Sicherheitsrichtlinie der Seite waere dann nur noch Zierde.
      final page = File('assets/expert/index.html').readAsStringSync();
      for (final forbidden in ['http://', 'https://', '//cdn', 'integrity=']) {
        expect(page, isNot(contains(forbidden)), reason: forbidden);
      }
      // Die Schriften kommen vom Server selbst.
      expect(page, contains('url(/font/'));
    });

    test('kein Web Push — der liefe über einen fremden Zustelldienst', () {
      // Die Standard-API für Push meldet den Browser bei Mozilla oder
      // Google an und lässt die Meldung von dort zustellen. Das wäre eine
      // ausgehende Verbindung und ADR-0005 damit hinfällig — unabhängig
      // davon, wie wenig im Paket steht. Erlaubt ist genau die andere
      // Bauform: `new Notification(…)`, vom Browser selbst gezeigt, ohne
      // Netz, und nur solange die Seite offen ist.
      final page = File('assets/expert/index.html').readAsStringSync();
      for (final forbidden in [
        'PushManager',
        'pushManager',
        'applicationServerKey',
        'serviceWorker',
        'ServiceWorker',
      ]) {
        expect(page, isNot(contains(forbidden)),
            reason: '„$forbidden" führt aus dem Gerät heraus (ADR-0005)');
      }
      expect(page, contains('new Notification('),
          reason: 'Der erlaubte Weg soll auch benutzt werden');
    });

    test('die Meldung kennt die Schwere der Regel', () {
      // Ohne dieses Feld müsste die Seite raten, ob eine Regel überhaupt zu
      // melden ist — und geraten würde sie in Richtung „melden". `info`
      // steht auf dem Telefon auf IMPORTANCE_MIN und erscheint dort gar
      // nicht; im Browser darf es dann auch nicht aufpoppen.
      final page = File('assets/expert/index.html').readAsStringSync();
      final server = File('lib/server/expert_server.dart').readAsStringSync();

      expect(server, contains("'severity': snapshot.decisionRule!.severity.name"),
          reason: 'Der Server schickt die Schwere nicht mehr mit');
      expect(page, contains("d.severity==='info'"),
          reason: 'Die Seite zieht die Grenze nicht mehr');
      expect(page, contains("d.severity==='nudge'"),
          reason: 'Ein Ton gehört zum Unterbrechen, nicht zum Hinweisen');
    });

    test('dieselben Paletten wie in der App', () {
      // Zwei Oberflaechen, die sich aehnlich sehen wollen, driften
      // auseinander, sobald die Farben zweimal getippt sind. Geprueft wird
      // deshalb gegen tokens.dart, nicht gegen eine Erwartung.
      final page = File('assets/expert/index.html').readAsStringSync();
      final tokens = File('lib/design/tokens.dart').readAsStringSync();
      for (final key in ['signal', 'calm', 'caution', 'info', 'base']) {
        final hex = RegExp('$key: Color\\(0xFF([0-9A-Fa-f]{6})\\)')
            .firstMatch(tokens)
            ?.group(1);
        expect(hex, isNotNull, reason: key);
        expect(page.toUpperCase(), contains('#${hex!.toUpperCase()}'),
            reason: '$key weicht ab');
      }
    });

    test('keine Farbe, die der Kern nicht kennt', () {
      // Die Gegenrichtung des Tests darüber — und die wichtigere.
      //
      // Oben wird geprüft, dass die Palette ankommt. Hier, dass nichts
      // dazukommt: `--on-signal` stand in drei dunklen Schemata als siebte
      // Farbe, die in tokens.dart nirgends steht. Eine Farbe, die nur an
      // einer Stelle existiert, altert dort still weiter — und zwei
      // Oberflächen, die dasselbe Instrument sein wollen, sehen nach einem
      // halben Jahr verschieden aus, ohne dass jemand etwas geändert hätte.
      final page = File('assets/expert/index.html').readAsStringSync();
      final tokens = File('lib/design/tokens.dart').readAsStringSync();
      final known = RegExp(r'Color\(0xFF([0-9A-Fa-f]{6})\)')
          .allMatches(tokens)
          .map((m) => m.group(1)!.toUpperCase())
          .toSet();
      final used = RegExp(r'#([0-9A-Fa-f]{6})')
          .allMatches(page)
          .map((m) => m.group(1)!.toUpperCase())
          .toSet();
      expect(used.difference(known), isEmpty,
          reason: 'Diese Farben stehen nur in der Weboberfläche. Entweder '
              'gehören sie in tokens.dart, oder sie sind überflüssig.');
    });
  });

  group('Freigabe per Zahlenabgleich', () {
    test('die Zahl steht auf beiden Seiten', () async {
      final res = await call('POST', '/api/auth/request');
      expect(res.statusCode, 200);
      final body = await json(res);
      // Zweistellig: lang genug, dass Zufall nicht traegt, kurz genug, um
      // sie in einem Blick zu vergleichen statt abzulesen.
      expect(body['number'], matches(RegExp(r'^\d{2}$')));
      expect(server.pendingNumber, body['number']);
    });

    test('vor der Freigabe kommt niemand hinein', () async {
      final body = await json(await call('POST', '/api/auth/request'));
      final poll = await call('GET', '/api/auth/poll?id=${body['id']}');
      expect(poll.statusCode, 202);
      expect(poll.headers.value('set-cookie'), isNull);
      // Und die Daten bleiben zu.
      expect((await call('GET', '/api/state')).statusCode, 401);
    });

    test('nach der Freigabe kommt die Sitzung', () async {
      final body = await json(await call('POST', '/api/auth/request'));
      server.resolvePending(approve: true);
      final poll = await call('GET', '/api/auth/poll?id=${body['id']}');
      expect(poll.statusCode, 200);
      final cookie = poll.headers.value('set-cookie')!;
      expect(cookie, contains('HttpOnly'));
      expect(cookie, contains('Secure'));
      expect(cookie, contains('SameSite=Strict'));

      final state = await call('GET', '/api/state',
          cookie: cookie.split(';').first);
      expect(state.statusCode, 200);
    });

    test('ablehnen sperrt genau diese Anfrage', () async {
      final body = await json(await call('POST', '/api/auth/request'));
      server.resolvePending(approve: false);
      final poll = await call('GET', '/api/auth/poll?id=${body['id']}');
      expect(poll.statusCode, 403);
      expect(poll.headers.value('set-cookie'), isNull);
    });

    test('eine fremde Kennung bekommt keine Sitzung', () async {
      // Sonst waere der Zahlenabgleich wertlos: Wer irgendeine Anfrage
      // freigeben laesst, duerfte sonst jede andere abholen.
      await call('POST', '/api/auth/request');
      server.resolvePending(approve: true);
      final poll = await call('GET', '/api/auth/poll?id=fremd');
      expect(poll.statusCode, 410);
    });

    test('eine offene Anfrage wird nicht verdraengt', () async {
      // Zwei Zahlen auf dem Telefon waeren eine Auswahl — und wer
      // auswaehlt, vergleicht nicht mehr.
      //
      // Frueher stand hier das Gegenteil: Nach drei Sekunden ersetzte jeder
      // unangemeldete Aufrufer die offene Anfrage. Wer im selben Netz
      // mitpollte, konnte sie damit gegen die eigene austauschen, waehrend
      // der Nutzer die Zahl vom Bildschirm zum Telefon trug — sein Tap auf
      // „Freigeben" gab dann die fremde Anfrage frei. Der Zahlenabgleich ist
      // die einzige Anmeldung fuer Gesundheitsdaten; er traegt nur, wenn die
      // Anfrage bis zur Antwort dieselbe bleibt.
      final first = await json(await call('POST', '/api/auth/request'));

      final second = await call('POST', '/api/auth/request');
      expect(second.statusCode, 429,
          reason: 'Die zweite Anfrage darf die erste nicht ersetzen');

      final poll = await call('GET', '/api/auth/poll?id=${first['id']}');
      expect(poll.statusCode, 202,
          reason: 'Die Anfrage des Nutzers laeuft weiter — genau die, deren '
              'Zahl er gerade vergleicht');
    });

    test('eine fremde Kennung gibt nichts frei', () async {
      // Der Riegel, der vorher toter Code war: `resolvePending` prueft die
      // Kennung, aber kein Aufrufer gab sie je mit. Solange nur der
      // Bildschirm antwortete, trug das nicht — er zeigt immer die lebende
      // Anfrage. Eine Benachrichtigung ueberlebt den Moment.
      final open = await json(await call('POST', '/api/auth/request'));

      server.resolvePending(approve: true, id: 'aus-einer-anderen-anfrage');
      expect((await call('GET', '/api/auth/poll?id=${open['id']}')).statusCode,
          202,
          reason: 'Freigegeben wird, was verglichen wurde');

      server.resolvePending(approve: true, id: server.pendingId);
      expect((await call('GET', '/api/auth/poll?id=${open['id']}')).statusCode,
          200);
    });

    test('die Nachfolgerin einer verfallenen Anfrage bleibt zu', () async {
      // Anfrage A verfaellt, waehrend die Meldung dazu noch in der Leiste
      // liegt; ein Fremder stellt Anfrage B. Ein spaeter Tipp darf B nicht
      // freigeben. Ueber die Zahl allein waere das eins zu neunzig.
      final a = await json(await call('POST', '/api/auth/request'));
      final aId = server.pendingId;
      expect(aId, isNotNull);

      h.clock.advance(const Duration(seconds: 91));
      expect(server.pendingNumber, isNull, reason: 'A ist verfallen');
      expect((await call('GET', '/api/auth/poll?id=${a['id']}')).statusCode, 410);

      final b = await json(await call('POST', '/api/auth/request'));
      server.resolvePending(approve: true, id: aId);

      expect((await call('GET', '/api/auth/poll?id=${b['id']}')).statusCode, 202,
          reason: 'Die Antwort auf A hat B freigegeben');
    });

    test('nach dem Verfall gibt es nichts mehr zu melden', () async {
      // Kein Timer meldet den Ablauf — die Begruendung steht am Feld
      // `_pending`. Was hier gilt: Wer danach fragt, bekommt nichts, und
      // genau davon haengt die Benachrichtigung ab (`state.pendingId`).
      await call('POST', '/api/auth/request');
      expect(server.pendingNumber, isNotNull);

      h.clock.advance(const Duration(seconds: 91));

      expect(server.pendingNumber, isNull);
      expect(server.pendingId, isNull);
      expect(server.status.pendingId, isNull,
          reason: 'Sonst bliebe die Meldung in der Leiste stehen');
    });

    test('ein beendeter Server nimmt die offene Anfrage mit', () async {
      // Sonst stuende ihre Zahl nach dem Wiederanschalten wieder da — und
      // antwortete auf einen Server, den es zwischendurch nicht gab.
      await call('POST', '/api/auth/request');
      await server.stop();

      expect(server.pendingNumber, isNull);
      expect(server.status.pendingId, isNull);
    });

    test('eine verfallene Anfrage laesst sich nicht mehr freigeben', () async {
      final open = await json(await call('POST', '/api/auth/request'));
      final id = server.pendingId;

      h.clock.advance(const Duration(seconds: 91));
      server.resolvePending(approve: true, id: id);

      expect((await call('GET', '/api/auth/poll?id=${open['id']}')).statusCode,
          410);
    });

    test('nach der Antwort ist wieder Platz', () async {
      // Die Gegenprobe: Ein Sperren, das sich nicht loest, waere kein Schutz,
      // sondern ein Riegel. Nach Freigabe oder Ablehnung geht es weiter.
      final first = await json(await call('POST', '/api/auth/request'));
      server.resolvePending(approve: false);
      expect((await call('GET', '/api/auth/poll?id=${first['id']}')).statusCode,
          403);

      final second = await call('POST', '/api/auth/request');
      expect(second.statusCode, 200);
    });
  });

  group('Die Verbindung ist verschlüsselt', () {
    test('Klartext wird nicht bedient', () async {
      // Ein HTTP-Aufruf auf den TLS-Port darf nicht irgendwie doch
      // funktionieren — ein stiller Rueckfall waere das Schlechteste von
      // beidem.
      final client = HttpClient();
      // Erst `close()` spricht wirklich mit dem Port — `openUrl` baut nur
      // die Anfrage.
      await expectLater(
        client
            .openUrl('GET', Uri.parse('http://127.0.0.1:$port/api/state'))
            .then((r) => r.close()),
        throwsA(anything),
      );
    });

    test('der Fingerabdruck der App ist der des Zertifikats', () async {
      // Der ganze Sinn der Anzeige: Wer die beiden vergleicht, hat die
      // Verbindung geprueft statt eine Warnung weggeklickt.
      late String seen;
      final client = HttpClient()
        ..badCertificateCallback = (cert, _, _) {
          seen = _fingerprint(cert);
          return true;
        };
      final request = await client.openUrl(
          'GET', Uri.parse('https://127.0.0.1:$port/api/state'));
      await request.close();
      expect(seen, server.status.fingerprint);
    });

    test('dasselbe Zertifikat über Neustarts hinweg', () async {
      // Sonst kaeme bei jedem Start eine neue Warnung — und genau das
      // erzeugt die Gewoehnung, die gefaehrlich ist.
      final before = server.status.fingerprint;
      await server.stop();
      await server.start(port: 0);
      expect(server.status.fingerprint, before);
    });

    test('bei einer neuen Adresse ein neues Zertifikat', () async {
      // Ohne passenden Subject Alternative Name lehnt der Browser rundheraus
      // ab, statt eine Ausnahme anzubieten.
      final before = server.status.fingerprint;
      ExpertCertificates.forget(h.runtime);
      await server.stop();
      await server.start(port: 0);
      expect(server.status.fingerprint, isNot(before));
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
      final client = HttpClient()
        ..badCertificateCallback = (_, _, _) => true;
      final request = await client.openUrl(
          'GET', Uri.parse('https://127.0.0.1:$newPort/api/state'));
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
      final source = android('kotlin/de/atomfritte/axiom/ExpertService.kt');
      expect(source, contains('START_NOT_STICKY'));
      expect(source, isNot(contains('return START_STICKY')));
    });

    test('kein Autostart beim Hochfahren', () {
      // BootReceiver stellt Alarme wieder her. Einen Server wiederherzustellen
      // waere etwas voellig anderes.
      expect(android('kotlin/de/atomfritte/axiom/BootReceiver.kt'),
          isNot(contains('Expert')));
    });

    test('der Modus beginnt ausgeschaltet', () {
      expect(ExpertStatus.off.running, isFalse);
      expect(ExpertStatus.off.pin, isNull);
      expect(ExpertStatus.off.address, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // Der geführte Regeleditor im Browser steht auf zwei Zusagen: Der
  // Wortschatz, den er anbietet, ist der der Engine — und die Vorschau
  // sagt dasselbe wie der Editor auf dem Telefon.
  // ──────────────────────────────────────────────────────────────────────

  /// Eine ladbare Regel in genau der Form, die `rules/` verwendet.
  String ruleYaml({
    String id = 'R-900',
    String when = 'capacity: { gte: 0 }',
    String action = 'log_only',
    int cooldown = 120,
    bool english = true,
  }) =>
      '''
- id: $id
  title: "Vorschau"
${english ? '  title_en: "Preview"\n' : ''}  deficit: D2
  rationale: >
    Diese Regel dient der Vorschau und trägt eine Begründung, die lang genug
    ist, um in einem halben Jahr noch zu erklären, warum es sie gibt.
${english ? '''  rationale_en: >
    This rule exists for the preview and carries a rationale long enough to
    still explain in half a year why it is here.
''' : ''}  when:
    $when
  then:
    action: $action
  priority: 50
  severity: nudge
  cooldown: { minutes: $cooldown }
  enabled: true
''';

  Future<Map<String, Object?>> preview(String cookie, String yaml) async =>
      json(await call('POST', '/api/rules/preview',
          cookie: cookie, body: {'yaml': yaml}));

  group('Der Wortschatz kommt aus dem Kern', () {
    test('ohne Sitzung gibt es ihn nicht', () async {
      // Er verrät für sich genommen keine Messwerte — aber jede Route, die
      // an der Sitzungsprüfung vorbeiginge, wäre eine, die man vergisst.
      expect((await call('GET', '/api/vocabulary')).statusCode, 401);
      expect(
        (await call('POST', '/api/rules/preview',
                body: {'yaml': ruleYaml()}))
            .statusCode,
        401,
      );
    });

    test('er enthält genau das, was die Engine kennt', () async {
      // Der eigentliche Punkt dieses Tests: Eine zweite, handgepflegte
      // Liste im Server würde beim nächsten Zusatz im Kern auseinander
      // laufen — und der Editor böte etwas an, das keine Regel versteht.
      final cookie = await login(server.status.pin!);
      final vocab = await json(await call('GET', '/api/vocabulary',
          cookie: cookie));

      Set<Object?> ids(String key, String field) =>
          (vocab[key]! as List).map((e) => (e as Map)[field]).toSet();

      expect(ids('numerics', 'id'),
          RuleVocabulary.numerics.map((v) => v.id).toSet());
      expect(ids('symbolics', 'id'),
          RuleVocabulary.symbolics.map((v) => v.id).toSet());
      expect(ids('events', 'id'),
          RuleVocabulary.events.map((e) => e.id).toSet());
      expect(ids('actions', 'type'),
          RuleVocabulary.actions.map((a) => a.type.token).toSet());
      expect(ids('severities', 'id'),
          Severity.values.map((s) => s.name).toSet());
    });

    test('jeder Eintrag trägt seine Bedeutung', () async {
      // Ohne sie ist der Editor eine Liste von Bezeichnern, und der Nutzer
      // muss wissen, was `regulation` heißt, bevor er es auswählen kann.
      final cookie = await login(server.status.pin!);
      final vocab = await json(await call('GET', '/api/vocabulary',
          cookie: cookie));
      for (final key in ['numerics', 'symbolics', 'actions', 'severities']) {
        for (final entry in vocab[key]! as List) {
          expect((entry as Map)['meaning'], isNotEmpty,
              reason: '$key: ${entry['id'] ?? entry['type']}');
        }
      }
    });

    test('symbolische Vergleiche kennen nur ist und ist nicht', () async {
      // Alles andere wäre eine Auswahl, die beim Speichern scheitert:
      // `Condition.fromMap` lehnt lt/gt auf einem Textwert ab.
      final cookie = await login(server.status.pin!);
      final vocab = await json(await call('GET', '/api/vocabulary',
          cookie: cookie));
      final operators = vocab['operators']! as Map<String, Object?>;
      expect(operators['symbolic'],
          RuleVocabulary.symbolicOperators.map((o) => o.token).toList());
      expect(operators['numeric'],
          containsAll(CompareOp.values.map((o) => o.token)));
    });

    test('die Defizite stehen mit Kurzfassung darin', () async {
      // Eine Regel ohne Bezug auf D1–D12 ist verdächtig — der Editor kann
      // die Zuordnung nur anbieten, wenn er die Namen kennt.
      final cookie = await login(server.status.pin!);
      final vocab = await json(await call('GET', '/api/vocabulary',
          cookie: cookie));
      final deficits = vocab['deficits']! as List;
      expect(deficits.length, 12);
      expect((deficits.first as Map)['id'], 'D1');
      expect((deficits.first as Map)['label'], isNotEmpty);
    });
  });

  group('Die Vorschau sagt, was passieren würde', () {
    test('eine Regel, die jetzt zutrifft, sagt das', () async {
      final cookie = await login(server.status.pin!);
      final result = await preview(cookie, ruleYaml());
      expect(result['ok'], isTrue);
      expect(result['errors'], isEmpty);
      expect(result['firesNow'], isTrue);
      expect(result['failedAt'], isNull);
      expect(result['explanation'], isNotEmpty);
    });

    test('und eine, die nicht zutrifft, woran es liegt', () async {
      // Der halbe Nutzen des Editors: nicht „trifft nicht zu", sondern
      // welcher Teil nicht hält und was gerade anliegt.
      final cookie = await login(server.status.pin!);
      final result =
          await preview(cookie, ruleYaml(when: 'capacity: { gte: 200 }'));
      expect(result['ok'], isTrue);
      expect(result['firesNow'], isFalse);
      expect(result['failedAt'], contains('Kapazität'));
      expect(result['failedAt'], contains('jetzt'));
    });

    test('eine unbekannte Variable ist ein Fehler, keine Warnung', () async {
      // Der Parser lässt sie durch; die Engine wirft erst in dem Moment, in
      // dem die Regel hätte feuern sollen. Genau dann fällt sie niemandem
      // mehr auf.
      final cookie = await login(server.status.pin!);
      final result =
          await preview(cookie, ruleYaml(when: 'gluecksgefuehl: { gte: 10 }'));
      expect(result['ok'], isFalse);
      expect((result['errors']! as List).join(), contains('gluecksgefuehl'));
      expect(result['firesNow'], isFalse);
    });

    test('was die Vorschau ablehnt, speichert auch das PUT nicht', () async {
      // Zwei verschiedene Urteile über dieselbe Regel wären schlimmer als
      // gar keine Vorschau.
      final cookie = await login(server.status.pin!);
      final yaml = ruleYaml(id: 'R-901', when: 'gluecksgefuehl: { gte: 10 }');
      expect((await preview(cookie, yaml))['ok'], isFalse);

      final res = await call('PUT', '/api/rules/R-901',
          cookie: cookie, body: {'yaml': yaml});
      expect(res.statusCode, 400);
      expect(h.store.ruleOverrides(), isEmpty);
    });

    test('eine fehlende englische Fassung hält die Regel nicht auf', () async {
      // Sichtbar unfertig ist besser als stumm fehlend: Die Regel lädt, der
      // Hinweis steht daneben.
      final cookie = await login(server.status.pin!);
      final result = await preview(cookie, ruleYaml(english: false));
      expect(result['ok'], isTrue);
      expect((result['warnings']! as List).join(), contains('englische'));
    });

    test('ohne Mindestabstand lädt sie nicht', () async {
      // Ohne Cooldown entsteht Benachrichtigungsflut (R2) — der häufigste
      // Grund, warum solche Apps wieder gelöscht werden.
      final cookie = await login(server.status.pin!);
      final result = await preview(cookie, ruleYaml(cooldown: 0));
      expect(result['ok'], isFalse);
      expect((result['errors']! as List).join(), contains('Mindestabstand'));
    });

    test('die Schattenzeit steht als Hinweis dabei', () async {
      final cookie = await login(server.status.pin!);
      final result = await preview(cookie, ruleYaml(action: 'notify'));
      expect((result['warnings']! as List).join(), contains('sieben Tage'));
    });

    test('eine Vorschau schreibt nichts', () async {
      // Sonst wäre sie ein Speichern mit anderem Namen — und die
      // Schattenzeit ließe sich damit umgehen.
      final cookie = await login(server.status.pin!);
      await preview(cookie, ruleYaml(id: 'R-902'));
      expect(h.store.ruleOverrides(), isEmpty);
      expect(h.runtime.rules.any((r) => r.id == 'R-902'), isFalse);
    });

    test('unlesbares YAML wird benannt, nicht verschwiegen', () async {
      final cookie = await login(server.status.pin!);
      final result = await preview(cookie, 'kein: [ regelwerk');
      expect(result['ok'], isFalse);
      expect(result['errors'], isNotEmpty);
      expect(result['explanation'], isNotEmpty);
    });

    test('ohne YAML-Feld ist es eine schlechte Anfrage', () async {
      final cookie = await login(server.status.pin!);
      final res = await call('POST', '/api/rules/preview',
          cookie: cookie, body: <String, Object?>{});
      expect(res.statusCode, 400);
    });
  });

  group('Werte aus dem Netz kommen geprüft an', () {
    test('eine Aktivierungsenergie von 999 landet nicht in der Datenbank',
        () async {
      // Die Domänentypen sichern 1..10 per `assert`, und `assert` ist im
      // Release-Build abgeschaltet. Ein Wert, der stumm falsch ist,
      // verzerrt jeden Auswahl-Score.
      final cookie = await login(server.status.pin!);
      final created = await json(await call('POST', '/api/tasks',
          cookie: cookie, body: {'title': 'Steuerunterlagen sortieren'}));
      final patched = await json(await call(
          'PATCH', '/api/tasks/${created['id']}',
          cookie: cookie, body: {'activationEnergy': 999, 'stakes': -4}));
      expect(patched['activationEnergy'], 10);
      expect(patched['stakes'], 1);

      final stored = (await h.store.tasks()).single;
      expect(stored.activationEnergy, 10);
      expect(stored.stakes, 1);
    });

    test('eine Aufgabe ohne Titel wird abgelehnt', () async {
      final cookie = await login(server.status.pin!);
      final res = await call('POST', '/api/tasks',
          cookie: cookie, body: {'title': '   '});
      expect(res.statusCode, 400);
      expect(await h.store.tasks(), isEmpty,
          reason: 'Eine namenlose Aufgabe steht in jeder Liste und ist in '
              'keiner wiederzuerkennen');
    });

    test('ein unbekannter Zustand wird abgelehnt, nicht übergangen', () async {
      final cookie = await login(server.status.pin!);
      final created = await json(await call('POST', '/api/tasks',
          cookie: cookie, body: {'title': 'Ordner holen'}));
      final res = await call('PATCH', '/api/tasks/${created['id']}',
          cookie: cookie, body: {'state': 'erledigt'});
      expect(res.statusCode, 400);
      expect((await h.store.tasks()).single.state.name, created['state']);
    });

    test('ein unlesbares Datum wird abgelehnt', () async {
      // Still verworfen stand die Aufgabe danach ohne Frist da, und der
      // Auswahl-Score rechnete mit dem halben Druck.
      final cookie = await login(server.status.pin!);
      final res = await call('POST', '/api/tasks',
          cookie: cookie,
          body: {'title': 'Antrag abgeben', 'decayAt': 'morgen früh'});
      expect(res.statusCode, 400);
      expect(await h.store.tasks(), isEmpty);
    });

    test('ein Schritt ohne Titel bricht die Zerlegung ab', () async {
      // Sonst gilt die Aufgabe als zerlegt, und der Teil, den es wirklich
      // gebraucht hätte, fehlt — ohne dass irgendwo etwas steht.
      final cookie = await login(server.status.pin!);
      final created = await json(await call('POST', '/api/tasks',
          cookie: cookie,
          body: {'title': 'Steuererklärung', 'activationEnergy': 9}));
      final res = await call('POST', '/api/tasks/${created['id']}/atomize',
          cookie: cookie,
          body: {
            'steps': [
              {'title': 'Ordner holen', 'energy': 2},
              {'title': '  '},
            ],
          });
      expect(res.statusCode, 400);
      expect((await h.store.tasks()).length, 1,
          reason: 'Halb zerlegt ist schlechter als gar nicht zerlegt');
    });

    test('eine unsinnige Grenze im Ereignisstrom stürzt nicht ab', () async {
      final cookie = await login(server.status.pin!);
      await h.runtime.capture('Testgedanke');
      final res = await call('GET', '/api/events?limit=-5', cookie: cookie);
      expect(res.statusCode, 200);
      expect((await json(res))['events'], isNotEmpty);
    });

    group('Der Eingang leert sich wieder', () {
      // Der Fehler, der diese Gruppe ausgeloest hat: Der Server lieferte
      // schlicht die letzten hundert Erfassungen. Man sortierte eine Notiz,
      // sie blieb stehen — und nach zwei Wochen war nicht mehr zu erkennen,
      // was beantwortet war. Ein Eingang, der nie leer wird, ist kein
      // Eingang, sondern ein Archiv, das man nicht mehr ansieht [D9].

      Future<List<Object?>> notes(String cookie) async =>
          ((await json(await call('GET', '/api/inbox', cookie: cookie)))
              ['notes'] as List)
              .cast<Object?>();

      String idOf(Object? note) => (note! as Map)['id'] as String;

      test('eine uebernommene Notiz verschwindet', () async {
        final cookie = await login(server.status.pin!);
        await h.runtime.capture('Steuerunterlagen sortieren');
        final before = await notes(cookie);
        expect(before, hasLength(1));

        final res = await call('POST', '/api/tasks', cookie: cookie, body: {
          'title': 'Steuerunterlagen sortieren',
          'activationEnergy': 5,
          'salience': 5,
          'stakes': 5,
          'fromCapture': idOf(before.single),
        });
        expect(res.statusCode, 200);

        expect(await notes(cookie), isEmpty,
            reason: 'Die Notiz ist beantwortet — sie gehoert nicht mehr dahin');
        expect((await h.store.tasks()).map((t) => t.title),
            contains('Steuerunterlagen sortieren'));
      });

      test('eine verworfene Notiz verschwindet auch', () async {
        // Ohne diesen Weg gaebe es nur einen: alles zur Aufgabe machen.
        // Dann sammelt sich im Bestand, was nie eine Aufgabe war.
        final cookie = await login(server.status.pin!);
        await h.runtime.capture('Adresse von der Werkstatt');
        final before = await notes(cookie);

        final res = await call('POST',
            '/api/inbox/${idOf(before.single)}/dismiss', cookie: cookie);
        expect(res.statusCode, 200);

        expect(await notes(cookie), isEmpty);
        expect(await h.store.tasks(), isEmpty,
            reason: 'Verworfen heisst: keine Aufgabe daraus');
      });

      test('ohne Bezug bleibt die Notiz stehen', () async {
        // Die Gegenprobe. Eine Aufgabe, die zufaellig denselben Text hat,
        // beantwortet die Notiz nicht — sonst raeumte ein gleichlautender
        // Titel etwas weg, das niemand angesehen hat.
        final cookie = await login(server.status.pin!);
        await h.runtime.capture('Steuerunterlagen sortieren');

        await call('POST', '/api/tasks', cookie: cookie, body: {
          'title': 'Steuerunterlagen sortieren',
          'activationEnergy': 5,
          'salience': 5,
          'stakes': 5,
        });

        expect(await notes(cookie), hasLength(1));
      });
    });

    test('ein Fokus auf eine unbekannte Aufgabe wird abgelehnt', () async {
      // Er zählte sonst Zeit auf einen Anker, den keine Auswertung
      // wiederfindet.
      final cookie = await login(server.status.pin!);
      final res = await call('POST', '/api/focus',
          cookie: cookie, body: {'taskId': 'gibtesnicht', 'minutes': 25});
      expect(res.statusCode, 404);
      expect(await h.store.activeFocus(), isNull);
    });
  });

  group('Die Aufgabenliste zeigt den Fortschritt einer Zerlegung', () {
    test('childCount und doneCount stehen an der Elternaufgabe', () async {
      // Ohne die beiden Zahlen müsste der Browser die ganze Liste
      // durchsuchen — zweimal dieselbe Zählung ist zweimal die
      // Gelegenheit, sie unterschiedlich zu machen.
      final cookie = await login(server.status.pin!);
      final parent = await json(await call('POST', '/api/tasks',
          cookie: cookie,
          body: {'title': 'Steuererklärung', 'activationEnergy': 9}));
      final split = await json(await call(
          'POST', '/api/tasks/${parent['id']}/atomize',
          cookie: cookie,
          body: {
            'steps': [
              {'title': 'Ordner auf den Tisch legen', 'energy': 1},
              {'title': 'Belege sortieren', 'energy': 3},
            ],
          }));
      final firstChild =
          (split['children']! as List).first as Map<String, Object?>;
      await call('POST', '/api/tasks/${firstChild['id']}/complete',
          cookie: cookie);

      final tasks = (await json(await call('GET', '/api/tasks', cookie: cookie)))
          ['tasks']! as List;
      final stored = tasks.firstWhere(
          (t) => (t as Map)['id'] == parent['id']) as Map<String, Object?>;
      expect(stored['childCount'], 2);
      expect(stored['doneCount'], 1);

      // Und ein Teilschritt hat selbst keine — nie `null`, sonst muss der
      // Browser jedes Feld einzeln prüfen.
      final child = tasks.firstWhere(
          (t) => (t as Map)['id'] == firstChild['id']) as Map<String, Object?>;
      expect(child['childCount'], 0);
      expect(child['doneCount'], 0);
    });
  });

  group('Kein Messwert ohne Zahl', () {
    test('/api/state liefert keinen Eintrag mit null', () async {
      // `meta_minutes_today` steht im RuntimeContext, nicht im
      // Zustandsvektor. Über den Vektor allein kam eine Zahl ohne Zahl
      // heraus — und die Oberfläche rendert sie trotzdem.
      final cookie = await login(server.status.pin!);
      final state = await json(await call('GET', '/api/state', cookie: cookie));
      final values = state['values']! as Map<String, Object?>;
      expect(values, isNotEmpty);
      for (final entry in values.entries) {
        expect((entry.value! as Map)['value'], isNotNull,
            reason: entry.key);
        expect((entry.value! as Map)['confidence'], isNotNull,
            reason: entry.key);
      }
      expect(values.containsKey('meta_minutes_today'), isTrue,
          reason: 'G4 misst die App selbst — der Wert gehört sichtbar dazu');
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // Die Nutzerdokumentation. Sie ist der erste Inhalt dieses Servers, der
  // nicht aus der Datenbank kommt, sondern aus dem App-Bündel — und damit
  // die erste Route, bei der eine Zeichenkette aus dem Netz einen
  // Dateinamen bezeichnet. Genau dort liegt die Gefahr, und genau die
  // steht hier.
  //
  // Die Kapitel entstehen parallel. Fehlen sie beim Testlauf, ist das kein
  // Testfehler: Der Server muss es dann sagen statt zu werfen, und das ist
  // hier ebenso festgehalten wie der Fall, dass sie da sind.
  // ──────────────────────────────────────────────────────────────────────

  group('Die Hilfe kommt aus einer Liste, nicht aus einem Pfad', () {
    /// Die erste Kapitelnummer, die der Server nennt — oder null, solange
    /// die Doku noch nicht im Bündel liegt.
    Future<String?> firstChapter(String cookie) async {
      final list = await json(await call('GET', '/api/help', cookie: cookie));
      final chapters = list['chapters']! as List;
      return chapters.isEmpty ? null : (chapters.first as Map)['id'] as String;
    }

    test('ohne Sitzung gibt es auch die Hilfe nicht', () async {
      // Sie enthält keine Nutzerdaten — sie erklärt die Oberfläche. Aber
      // eine Route, die an der Sitzungsprüfung vorbeigeht, ist eine, die
      // man beim nächsten Zusatz vergisst, und der Weg von „erklärt die
      // Oberfläche" zu „zeigt, was drinsteht" ist eine Zeile weit.
      for (final path in ['/api/help', '/api/help/01', '/help/img/jetzt.webp']) {
        expect((await call('GET', path)).statusCode, 401, reason: path);
      }
    });

    test('kein Weg aus der Kapitelliste heraus', () async {
      // Die Kapitelnummer kommt aus dem Netz. Würde daraus ein Pfad
      // gebaut, stünde hinter dieser Route das ganze App-Bündel — samt
      // Regelwerk, Zertifikat und allem, was sonst noch mitgeliefert wird.
      final cookie = await login(server.status.pin!);
      for (final id in [
        '..',
        '../../pubspec.yaml',
        '%2e%2e%2f%2e%2e%2fpubspec.yaml',
        '..%2F..%2Flib%2Fmain.dart',
        '01/../../expert/index.html',
        // Der Dateiname ist keine gültige Kennung: Ausgeliefert wird nach
        // Nummer, damit ein Umbenennen keinen Verweis bricht.
        '01-was-das-ist',
        // Der Index ist die Liste, kein Kapitel.
        '00',
        '99',
      ]) {
        final res = await call('GET', '/api/help/$id', cookie: cookie);
        expect(res.statusCode, isNot(200), reason: 'Kapitel "$id"');
        final body = await res.transform(utf8.decoder).join();
        expect(body, isNot(contains('uses-material-design')),
            reason: 'Kapitel "$id" hat pubspec.yaml ausgeliefert');
        expect(body, isNot(contains('<!--')),
            reason: 'Kapitel "$id" hat eine Datei aus dem Bündel ausgeliefert');
      }
    });

    test('kein Weg aus der Bildliste heraus', () async {
      final cookie = await login(server.status.pin!);
      for (final name in [
        '../../../pubspec.yaml',
        '%2e%2e%2fexpert%2findex.html',
        'jetzt.webp/../../expert/index.html',
        'gibtesnicht.webp',
        'jetzt.png',
      ]) {
        final res = await call('GET', '/help/img/$name', cookie: cookie);
        expect(res.statusCode, isNot(200), reason: name);
        expect(res.headers.contentType?.mimeType, isNot('image/webp'),
            reason: name);
      }
    });

    test('eine unbekannte Sprache ist ein Fehler, kein stiller Rückfall',
        () async {
      // Sonst bekäme der Aufrufer bei `lang=fr` eine Antwort, die aussieht
      // wie die gewünschte, und merkte den Tippfehler nie.
      final cookie = await login(server.status.pin!);
      for (final path in ['/api/help?lang=fr', '/api/help/01?lang=../de']) {
        final res = await call('GET', path, cookie: cookie);
        expect(res.statusCode, 400, reason: path);
        expect((await json(res))['error'], isNotEmpty, reason: path);
      }
    });

    test('die Liste nennt nur Kapitel, die sich auch abrufen lassen',
        () async {
      // Ein Eintrag im Inhaltsverzeichnis, der ins Leere zeigt, ist
      // schlimmer als ein fehlender: Man sucht dann den Fehler bei sich.
      final cookie = await login(server.status.pin!);
      final res = await call('GET', '/api/help', cookie: cookie);
      expect(res.statusCode, 200);
      for (final entry in (await json(res))['chapters']! as List) {
        final chapter = entry as Map<String, Object?>;
        expect(chapter['id'], matches(RegExp(r'^\d{2}$')), reason: '$chapter');
        expect(chapter['id'], isNot('00'), reason: 'Der Index ist die Liste');
        expect(chapter['title'], isNotEmpty, reason: '$chapter');
        expect(
            (await call('GET', '/api/help/${chapter['id']}', cookie: cookie))
                .statusCode,
            200,
            reason: 'Kapitel ${chapter['id']} steht in der Liste, fehlt aber');
      }
    });

    test('ein Kapitel bringt seinen Text mit — oder seinen Grund', () async {
      final cookie = await login(server.status.pin!);
      final id = await firstChapter(cookie);
      if (id == null) {
        // Noch nicht im Bündel. Dann muss der Server das sagen, und zwar
        // so, dass man weiß, wo man nachsieht.
        final res = await call('GET', '/api/help/01', cookie: cookie);
        expect(res.statusCode, 404);
        expect((await json(res))['error'], contains('assets/help/'));
        return;
      }
      final chapter =
          await json(await call('GET', '/api/help/$id', cookie: cookie));
      expect(chapter['id'], id);
      expect(chapter['title'], isNotEmpty);
      expect(chapter['markdown'], isNotEmpty);
      expect(chapter['fallback'], isFalse);
    });

    test('fehlt die englische Fassung, kommt die deutsche — nie nichts',
        () async {
      // Sichtbar unfertig ist besser als stumm fehlend (CLAUDE.md). Was
      // auf Deutsch da ist, muss auf Englisch erreichbar sein, notfalls im
      // deutschen Wortlaut mit gesetzter Marke.
      final cookie = await login(server.status.pin!);
      final id = await firstChapter(cookie);
      if (id == null) return;
      final res = await call('GET', '/api/help/$id?lang=en', cookie: cookie);
      expect(res.statusCode, 200);
      final chapter = await json(res);
      expect(chapter['markdown'], isNotEmpty);
      expect(chapter['fallback'], isA<bool>());
    });

    test('ein Bild kommt als Bild und darf liegen bleiben', () async {
      final cookie = await login(server.status.pin!);
      final res = await call('GET', '/help/img/jetzt.webp', cookie: cookie);
      if (res.statusCode == 404) {
        expect((await json(res))['error'], isNotEmpty,
            reason: 'Fehlt es im Bündel, wird das gesagt und nicht geworfen');
        return;
      }
      expect(res.statusCode, 200);
      expect(res.headers.contentType?.mimeType, 'image/webp');
      // `private`: Die Antwort hängt an einer Sitzung, und ein
      // Zwischenspeicher, der sie weitergibt, wäre einer zu viel.
      expect(res.headers.value('cache-control'), contains('private'));
      expect(res.headers.value('cache-control'), contains('max-age'));
      expect(await res.fold<int>(0, (sum, chunk) => sum + chunk.length),
          greaterThan(0));
    });
  });

  // Die Kapitel entstehen parallel zu diesem Server. Ohne sie bliebe die
  // Hälfte der Auswertung ungeprüft — die Reihenfolge aus dem Index, der
  // Titel aus der Überschrift, der Rückfall auf Deutsch. Genau das sind
  // die Stellen, an denen man sich vertut. Deshalb wird hier ein Bündel
  // vorgetäuscht: geprüft wird die Auswertung, nicht das Vorhandensein.
  group('Mit einer Doku im Bündel', () {
    const index = '''
# Hilfe

- [Was das ist](kapitel:01)
- [Aufgaben](kapitel:06)
- [Gibt es nicht](kapitel:77)
- [Der Index selbst](kapitel:00)
- [Ein Bild](img/jetzt.webp)
''';
    const chapters = {
      'assets/help/de/00-index.md': index,
      'assets/help/de/01-was-das-ist.md': '# Was das ist\n\nEin Satz.',
      'assets/help/de/06-aufgaben.md': '# Aufgaben\n\nNoch ein Satz.',
      'assets/help/en/06-aufgaben.md': '# Tasks\n\nOne sentence.',
      'assets/help/img/jetzt.webp': 'kein echtes Bild, aber Bytes',
    };

    /// Legt dem Bündel genau diese Dateien unter. Alles andere gibt es
    /// dann nicht — mehr braucht keiner dieser Tests.
    void bundle(Map<String, String> assets) {
      rootBundle.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (ByteData? message) async {
        final key = utf8.decode(message!.buffer
            .asUint8List(message.offsetInBytes, message.lengthInBytes));
        final text = assets[key];
        if (text == null) return null;
        return ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
      });
    }

    setUp(() => bundle(chapters));
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', null);
      rootBundle.clear();
    });

    test('die Reihenfolge steht im Index, nicht im Server', () async {
      // Wer ein Kapitel verschiebt, verschiebt es an einer Stelle. Und was
      // der Index nennt, das es nicht gibt, wird übergangen statt
      // angeboten — ein Eintrag ins Leere ist schlimmer als kein Eintrag.
      final cookie = await login(server.status.pin!);
      final list = await json(await call('GET', '/api/help', cookie: cookie));
      expect(list['chapters'], [
        {'id': '01', 'title': 'Was das ist'},
        {'id': '06', 'title': 'Aufgaben'},
      ]);
    });

    test('ein Kapitel bringt Überschrift und Text mit', () async {
      final cookie = await login(server.status.pin!);
      final chapter =
          await json(await call('GET', '/api/help/06', cookie: cookie));
      expect(chapter['title'], 'Aufgaben');
      expect(chapter['markdown'], contains('Noch ein Satz.'));
      expect(chapter['fallback'], isFalse);
    });

    test('ohne englische Fassung kommt die deutsche mit Marke', () async {
      // Sichtbar unfertig ist besser als stumm fehlend: Die Marke sagt der
      // Oberfläche, dass sie einen Hinweis darüberschreiben muss.
      final cookie = await login(server.status.pin!);
      final missing =
          await json(await call('GET', '/api/help/01?lang=en', cookie: cookie));
      expect(missing['fallback'], isTrue);
      expect(missing['markdown'], contains('Ein Satz.'));

      final present =
          await json(await call('GET', '/api/help/06?lang=en', cookie: cookie));
      expect(present['fallback'], isFalse);
      expect(present['title'], 'Tasks');
    });

    test('ohne lesbaren Index stehen trotzdem alle Kapitel da', () async {
      // Eine leere Hilfe wäre die schlechteste Antwort: Die Kapitel sind
      // da, nur ihre Ordnung fehlt. Dann zählt der Server sie selbst auf
      // und nimmt die Überschrift als Titel.
      bundle({
        'assets/help/de/01-was-das-ist.md': '# Was das ist\n\nEin Satz.',
        'assets/help/de/06-aufgaben.md': 'Ohne Überschrift.',
      });
      final cookie = await login(server.status.pin!);
      final list = await json(await call('GET', '/api/help', cookie: cookie));
      expect(list['chapters'], [
        {'id': '01', 'title': 'Was das ist'},
        // Ohne Überschrift der Dateiname: lesbar genug, um das Kapitel zu
        // finden, und sichtbar unfertig.
        {'id': '06', 'title': 'aufgaben'},
      ]);
    });

    test('ein Bild kommt als Bild', () async {
      final cookie = await login(server.status.pin!);
      final res = await call('GET', '/help/img/jetzt.webp', cookie: cookie);
      expect(res.statusCode, 200);
      expect(res.headers.contentType?.mimeType, 'image/webp');
      expect(res.headers.value('cache-control'), contains('private'));
      expect(await res.transform(utf8.decoder).join(), isNotEmpty);
    });

    test('auch mit Doku im Bündel führt kein Pfad hinaus', () async {
      // Die Bilder liegen jetzt wirklich da — die Frage ist, ob man von
      // ihnen aus weiterkommt.
      final cookie = await login(server.status.pin!);
      for (final path in [
        '/help/img/%2e%2e%2fde%2f01-was-das-ist.md',
        '/help/img/../de/01-was-das-ist.md',
        '/api/help/%2e%2e%2f%2e%2e%2fexpert%2findex.html',
      ]) {
        final res = await call('GET', path, cookie: cookie);
        expect(res.statusCode, isNot(200), reason: path);
        expect(await res.transform(utf8.decoder).join(),
            isNot(contains('Ein Satz.')),
            reason: path);
      }
    });
  });

  group('Die Hilfe im Browser', () {
    String page() => File('assets/expert/index.html').readAsStringSync();

    test('der Darsteller baut Knoten, kein Markup', () {
      // Die Doku ist Text, den ein Mensch geschrieben hat — aber ihr Weg in
      // diese Seite führt über das Netz. Ein Darsteller, der Markup aus der
      // Antwort zusammensetzt, macht aus jeder spitzen Klammer in einem
      // Kapitel eine Anweisung an den Browser.
      final source = page();
      final start = source.indexOf('Hilfe: Darsteller — Anfang');
      final end = source.indexOf('Hilfe: Darsteller — Ende');
      expect(start, greaterThan(0), reason: 'Die Anfangsmarke fehlt');
      expect(end, greaterThan(start), reason: 'Die Endmarke fehlt');
      final renderer = source.substring(start, end);
      for (final forbidden in [
        'innerHTML',
        'outerHTML',
        'insertAdjacentHTML',
        'document.write',
        'eval(',
      ]) {
        expect(renderer, isNot(contains(forbidden)), reason: forbidden);
      }
      expect(renderer, contains('el('), reason: 'Gebaut wird mit el()');
    });

    test('der Bildpfad entsteht nur aus einem erkannten Namen', () {
      // Genau eine Stelle setzt einen Bildpfad zusammen, und unmittelbar
      // davor steht die Erkennung. Zwei Stellen hieße: eine davon prüft
      // nicht, und man sieht es keiner von beiden an.
      final source = page();
      const needle = "'/help/img/'";
      expect(needle.allMatches(source).length, 1);
      final at = source.indexOf(needle);
      expect(source.substring(at - 220, at), contains('MD_IMG.exec'));
    });

    test('der Reiter und sein Kürzel stehen beide da', () {
      // Ein Kürzel, das in der Übersicht fehlt, gibt es für den Nutzer
      // nicht — und `?` war schon belegt.
      final source = page();
      expect(source, contains('data-tab="help"'));
      expect(source, contains("case 'h':"));
      // Seit die Oberfläche übersetzt wird, steht der Text in `tr()` — die
      // Zusage bleibt dieselbe: Das Kürzel ist in der Übersicht aufgeführt.
      expect(source, contains("['h',tr('Hilfe')]"));
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // Blocker-Beziehungen: genau eine Art — A blockiert B. Der Kern prüft den
  // Zyklus (`ensureAcyclic`), dieser Server reicht ihn nur durch. Was hier
  // steht, ist deshalb nicht die Graphlogik selbst, sondern das, was ein
  // Netzzugriff daraus macht: Existenz, Selbstbezug, Sitzung, schlanke
  // Übersicht.
  // ──────────────────────────────────────────────────────────────────────

  group('Blocker-Beziehungen zwischen Aufgaben', () {
    Future<Map<String, Object?>> makeTask(String cookie, String title) async =>
        json(await call('POST', '/api/tasks', cookie: cookie,
            body: {'title': title}));

    Future<HttpClientResponse> link(
      String? cookie,
      String blockedId,
      String blockerId,
    ) =>
        call('POST', '/api/tasks/$blockedId/blockers',
            cookie: cookie, body: {'blockerId': blockerId});

    test('ohne Sitzung kommt niemand an eine Blocker-Route', () async {
      // Dieselbe Zentralstelle wie überall: `_authorised` sitzt vor dem
      // Verteiler, nicht vor jeder Route einzeln — aber genau deshalb muss
      // hier stehen, dass keine der drei neuen Routen daran vorbeigeht.
      expect((await link(null, 'a', 'b')).statusCode, 401);
      expect((await call('DELETE', '/api/tasks/a/blockers/b')).statusCode, 401);
      expect((await call('GET', '/api/tasks/a')).statusCode, 401);
    });

    test('eine Beziehung auf sich selbst wird abgelehnt', () async {
      final cookie = await login(server.status.pin!);
      final a = await makeTask(cookie, 'Antrag stellen');

      final res = await link(cookie, a['id']! as String, a['id']! as String);
      expect(res.statusCode, 400);
      expect(await h.store.taskLinks(), isEmpty,
          reason: 'Abgelehnt heißt: nichts gespeichert');
    });

    test('eine fehlende Aufgabe gibt 404 — auf beiden Seiten', () async {
      final cookie = await login(server.status.pin!);
      final a = await makeTask(cookie, 'Antrag stellen');

      final missingBlocker =
          await link(cookie, a['id']! as String, 'gibtesnicht');
      expect(missingBlocker.statusCode, 404);

      final missingBlocked =
          await link(cookie, 'gibtesnicht', a['id']! as String);
      expect(missingBlocked.statusCode, 404);
      expect(await h.store.taskLinks(), isEmpty);
    });

    test('ein Zyklus wird abgelehnt und nennt den Pfad', () async {
      // A blockiert B, B blockiert C — C soll jetzt A blockieren und damit
      // den Kreis schließen. Alle drei würden dauerhaft aufeinander warten,
      // und genau deshalb ist ein „geht nicht" ohne Grund hier der
      // teuerste Fehlermodus.
      final cookie = await login(server.status.pin!);
      final a = await makeTask(cookie, 'A');
      final b = await makeTask(cookie, 'B');
      final c = await makeTask(cookie, 'C');

      expect((await link(cookie, b['id']! as String, a['id']! as String))
          .statusCode, 200);
      expect((await link(cookie, c['id']! as String, b['id']! as String))
          .statusCode, 200);

      final res = await link(cookie, a['id']! as String, c['id']! as String);
      expect(res.statusCode, 409);
      final body = await json(res);
      expect(body['error'], isNotEmpty);
      final path = (body['path']! as List).cast<String>();
      // Der Pfad ist der eigentliche Nutzen dieses Fehlers: Er muss
      // tatsächlich zeigen, wo sich der Kreis schließt — nicht nur
      // irgendeine Liste sein.
      expect(path.first, path.last,
          reason: 'ein Kreis beginnt und endet an derselben Aufgabe');
      expect(path, containsAll([a['id'], b['id'], c['id']]));

      // Und die versuchte Kante wurde nicht trotzdem gespeichert.
      final links = await h.store.taskLinks();
      expect(links.length, 2, reason: 'nur die beiden gültigen Kanten');
    });

    test('eine gelöste Beziehung lässt sich wieder trennen', () async {
      final cookie = await login(server.status.pin!);
      final a = await makeTask(cookie, 'A');
      final b = await makeTask(cookie, 'B');
      await link(cookie, b['id']! as String, a['id']! as String);

      final res = await call(
          'DELETE', '/api/tasks/${b['id']}/blockers/${a['id']}',
          cookie: cookie);
      expect(res.statusCode, 200);
      expect(await h.store.taskLinks(), isEmpty);
      expect(changes, greaterThan(0));
    });

    test('eine Beziehung, die es nicht gibt, kann man nicht lösen', () async {
      // Kein stilles Nichtstun: Sonst glaubt der Aufrufer, es sei etwas
      // geschehen, das nie stattfand.
      final cookie = await login(server.status.pin!);
      final a = await makeTask(cookie, 'A');
      final b = await makeTask(cookie, 'B');

      final res = await call(
          'DELETE', '/api/tasks/${b['id']}/blockers/${a['id']}',
          cookie: cookie);
      expect(res.statusCode, 404);
    });

    test('eine unbekannte Aufgabe in der Detailansicht gibt 404', () async {
      final cookie = await login(server.status.pin!);
      final res = await call('GET', '/api/tasks/gibtesnicht', cookie: cookie);
      expect(res.statusCode, 404);
    });

    test('/api/tasks/:id liefert Eltern, Kinder und beide Richtungen',
        () async {
      final cookie = await login(server.status.pin!);

      // Eltern und Kinder aus einer Zerlegung.
      final parent = await makeTask(cookie, 'Steuererklärung');
      final split = await json(await call(
          'POST', '/api/tasks/${parent['id']}/atomize',
          cookie: cookie,
          body: {
            'steps': [
              {'title': 'Ordner auf den Tisch legen', 'energy': 1},
            ],
          }));
      final child =
          (split['children']! as List).first as Map<String, Object?>;

      // Blocker-Beziehung zwischen zwei eigenständigen Aufgaben.
      final blocker = await makeTask(cookie, 'Unterlagen anfordern');
      final waiting = await makeTask(cookie, 'Antrag einreichen');
      await link(cookie, waiting['id']! as String, blocker['id']! as String);

      final parentDetail = await json(
          await call('GET', '/api/tasks/${parent['id']}', cookie: cookie));
      expect(parentDetail['parents'], isEmpty);
      expect((parentDetail['children']! as List).single, {
        'id': child['id'],
        'title': child['title'],
        'state': child['state'],
        'activationEnergy': child['activationEnergy'],
      });
      expect(parentDetail['blockedBy'], isEmpty);
      expect(parentDetail['blocks'], isEmpty);
      expect(parentDetail['waiting'], isFalse);
      expect(parentDetail['events'], isNotEmpty,
          reason: 'mindestens die eigene Erzeugung und die Zerlegung');

      final childDetail = await json(
          await call('GET', '/api/tasks/${child['id']}', cookie: cookie));
      expect(childDetail['parents'], [
        {'id': parent['id'], 'title': parent['title']},
      ]);
      expect(childDetail['children'], isEmpty);

      final waitingDetail = await json(
          await call('GET', '/api/tasks/${waiting['id']}', cookie: cookie));
      expect(waitingDetail['waiting'], isTrue);
      expect((waitingDetail['blockedBy']! as List).single, {
        'id': blocker['id'],
        'title': blocker['title'],
        'state': blocker['state'],
        'done': false,
      });
      expect(waitingDetail['blocks'], isEmpty);

      final blockerDetail = await json(
          await call('GET', '/api/tasks/${blocker['id']}', cookie: cookie));
      expect(blockerDetail['waiting'], isFalse);
      expect((blockerDetail['blocks']! as List).single, {
        'id': waiting['id'],
        'title': waiting['title'],
        'state': waiting['state'],
        'done': false,
      });
      expect(blockerDetail['blockedBy'], isEmpty);
    });

    test('/api/tasks bleibt schlank — Zahlen statt Listen', () async {
      final cookie = await login(server.status.pin!);
      final blocker = await makeTask(cookie, 'Unterlagen anfordern');
      final waiting = await makeTask(cookie, 'Antrag einreichen');
      await link(cookie, waiting['id']! as String, blocker['id']! as String);

      final tasks = (await json(await call('GET', '/api/tasks', cookie: cookie)))
          ['tasks']! as List;
      final waitingRow = tasks.firstWhere(
          (t) => (t as Map)['id'] == waiting['id']) as Map<String, Object?>;
      final blockerRow = tasks.firstWhere(
          (t) => (t as Map)['id'] == blocker['id']) as Map<String, Object?>;

      expect(waitingRow['waiting'], isTrue);
      expect(waitingRow['blockedByCount'], 1);
      expect(waitingRow['blocksCount'], 0);
      expect(blockerRow['waiting'], isFalse);
      expect(blockerRow['blockedByCount'], 0);
      expect(blockerRow['blocksCount'], 1);

      // Und keine der beiden trägt die vollen Listen mit sich herum — die
      // Übersicht soll nicht den ganzen Graphen laden.
      for (final row in [waitingRow, blockerRow]) {
        expect(row.containsKey('blockedBy'), isFalse);
        expect(row.containsKey('blocks'), isFalse);
        expect(row.containsKey('parents'), isFalse);
        expect(row.containsKey('children'), isFalse);
        expect(row.containsKey('events'), isFalse);
      }
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // Der Kanal, über den die Seite merkt, dass es den Server noch gibt.
  //
  // Die Richtung ist der ganze Punkt: Der Browser verbindet sich hierher,
  // AXIOM ruft nichts auf (ADR-0005). Und eine bestehende Verbindung ist
  // keine Nutzung — sonst hielte ein vergessener Reiter den Port mit
  // Gesundheitsdaten offen, bis jemand das Telefon ausschaltet.
  // ──────────────────────────────────────────────────────────────────────

  /// Was der Browser tut: eine Aufwertung anfragen. Das Zertifikat wird
  /// dabei geprüft wie bei jedem anderen Aufruf auch.
  Future<WebSocket> connect({String? cookie}) {
    final client = HttpClient()
      ..badCertificateCallback = (cert, host, port) =>
          _fingerprint(cert) == server.status.fingerprint;
    return WebSocket.connect(
      'wss://127.0.0.1:$port/ws',
      headers: {'cookie': ?cookie},
      customClient: client,
    );
  }

  group('Der Kanal für Änderungen', () {
    test('ohne Sitzung gibt es ihn nicht', () async {
      // Ein Kanal, der Zustandsänderungen meldet, ist ein Datenkanal — auch
      // wenn über ihn nur ein Wort geht. Wer mithört, weiß, wann jemand
      // etwas erfasst hat.
      await expectLater(connect(), throwsA(anything));
      expect((await call('GET', '/ws')).statusCode, 401);
    });

    test('ohne Aufwertung ist der Weg keine Abfrage', () async {
      // Sonst wäre eine 200 mit leerem Rumpf die Antwort, und im Browser
      // sähe eine nicht zustande gekommene Verbindung aus wie eine.
      final cookie = await login(server.status.pin!);
      expect((await call('GET', '/ws', cookie: cookie)).statusCode, 400);
    });

    test('eine Änderung meldet sich als Signal, nicht als Inhalt', () async {
      final cookie = await login(server.status.pin!);
      final socket = await connect(cookie: cookie);
      final messages = <Object?>[];
      socket.listen(messages.add);

      await call('POST', '/api/capture',
          cookie: cookie, body: {'text': 'Steuerunterlagen sortieren'});
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(messages, ['changed']);
      // Kein Wort aus der Erfassung geht diesen Weg. Die Daten holt die
      // Seite über die geprüften Routen; ein zweiter Weg an dieselben Daten
      // wäre eine zweite Stelle, an der eine Prüfung fehlen kann.
      expect(messages.join(), isNot(contains('Steuer')));
      await socket.close();
    });

    test('eine offene Verbindung verlängert den Leerlauf nicht', () async {
      // Die eigentliche Falle. Zählte die Verbindung als Aktivität, hielte
      // ein Reiter, den jemand am Freitag offen gelassen hat, den Port bis
      // Montag offen — genau das, wogegen die dreißig Minuten gebaut sind.
      final cookie = await login(server.status.pin!);
      final before = server.status.idleStopAt;
      expect(before, isNotNull);

      final socket = await connect(cookie: cookie);
      // Auch nicht, was über die Verbindung hereinkommt.
      socket.add('hallo');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(server.status.idleStopAt, before,
          reason: 'Eine bestehende Verbindung ist keine Nutzung');

      // Gegenprobe: Eine echte Anfrage verschiebt die Grenze sehr wohl —
      // sonst prüfte der Test nur, dass gar nichts passiert.
      //
      // Die Uhr muss dafür weiterlaufen. Seit der Server sie über einen Port
      // liest statt direkt, steht sie im Test still — ohne diesen Sprung
      // ergäbe eine Anfrage denselben Zeitpunkt, und die Gegenprobe könnte
      // „verschoben" nicht mehr von „nicht verschoben" unterscheiden.
      h.clock.advance(const Duration(minutes: 1));
      await call('GET', '/api/state', cookie: cookie);
      expect(server.status.idleStopAt, isNot(before));
      await socket.close();
    });

    test('beim Beenden kommt ein Abschied mit Grund', () async {
      // „Server beendet" ist etwas anderes als „Verbindung verloren": Das
      // eine ist Absicht, das andere ein Problem. Wer den Unterschied nicht
      // sieht, sucht einen Fehler, den es nicht gibt.
      final cookie = await login(server.status.pin!);
      final socket = await connect(cookie: cookie);
      final closed = Completer<void>();
      socket.listen((_) {}, onDone: closed.complete);

      await server.stop();
      await closed.future.timeout(const Duration(seconds: 5));

      expect(socket.closeCode, WebSocketStatus.goingAway);
      expect(socket.closeReason, 'Server beendet');
    });
  });

  group('Das Symbol im Reiter', () {
    test('kommt ohne Sitzung — sonst bliebe dort ein leeres Blatt', () async {
      // Der Browser holt es, bevor sich jemand angemeldet hat. Zu verbergen
      // gibt es nichts: zwei Striche, keine Daten.
      final res = await call('GET', '/favicon.svg');
      expect(res.statusCode, 200);
      expect(res.headers.contentType?.mimeType, 'image/svg+xml');
      expect(await res.transform(utf8.decoder).join(), contains('<svg'));
    });

    test('und verschiebt die Leerlaufgrenze nicht', () async {
      // Ein Reiter, der beim Wiederherstellen sein Symbol nachlädt, hat
      // niemanden davorsitzen.
      final before = server.status.idleStopAt;
      await call('GET', '/favicon.svg');
      expect(server.status.idleStopAt, before);
    });

    test('die Seite verweist darauf', () {
      final page = File('assets/expert/index.html').readAsStringSync();
      expect(page, contains('rel="icon"'));
      expect(page, contains('/favicon.svg'));
    });

    test('auch im Symbol keine Farbe, die der Kern nicht kennt', () {
      // Dieselbe Zusage wie für die Palette der Seite. Das Symbol liegt im
      // Server statt in tokens.dart, und genau solche Stellen altern still
      // weiter, wenn niemand hinsieht.
      final source = File('lib/server/expert_server.dart').readAsStringSync();
      final svg = RegExp(r"static const _favicon = '''(.*?)'''", dotAll: true)
          .firstMatch(source)
          ?.group(1);
      expect(svg, isNotNull);

      final tokens = File('lib/design/tokens.dart').readAsStringSync();
      final known = RegExp(r'Color\(0xFF([0-9A-Fa-f]{6})\)')
          .allMatches(tokens)
          .map((m) => m.group(1)!.toUpperCase())
          .toSet();
      final used = RegExp(r'#([0-9A-Fa-f]{6})')
          .allMatches(svg!)
          .map((m) => m.group(1)!.toUpperCase())
          .toSet();
      expect(used, isNotEmpty);
      expect(used.difference(known), isEmpty,
          reason: 'Diese Farben stehen nur im Symbol');
      // Beide Fassungen: Der Reiter kann hell oder dunkel sein, und welches
      // von beidem gilt, weiß die Seite nicht.
      expect(svg, contains('prefers-color-scheme: dark'));
    });
  });
}
