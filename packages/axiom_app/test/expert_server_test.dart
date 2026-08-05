/// Der Expertenmodus — geprüft auf das, was ihn vertretbar macht.
///
/// Hier liegen Gesundheitsdaten auf einem Port. Die Zusagen aus ADR-0005 sind
/// deshalb keine Absichtserklärung, sondern das, was diesen Server von einem
/// offenen Scheunentor unterscheidet. Genau die stehen hier.
library;

import 'dart:convert';
import 'dart:io';

import 'package:axiom_core/axiom_core.dart'
    show CompareOp, RuleVocabulary, Severity;
import 'package:axiom_data/axiom_data.dart';
import 'package:crypto/crypto.dart';

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
    // Selbst signiert: Der Test akzeptiert genau dieses eine Zertifikat —
    // deshalb wird der Fingerabdruck geprueft, nicht blind alles erlaubt.
    final client = HttpClient()
      ..badCertificateCallback = (cert, host, port) =>
          _fingerprint(cert) == server.status.fingerprint;
    final request = await client.openUrl(
        method, Uri.parse('https://127.0.0.1:$port$path'));
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

    test('es gibt immer nur eine offene Anfrage', () async {
      // Zwei Zahlen auf dem Telefon waeren eine Auswahl — und wer
      // auswaehlt, vergleicht nicht mehr.
      final first = await json(await call('POST', '/api/auth/request'));
      await Future<void>.delayed(const Duration(seconds: 4));
      final second = await json(await call('POST', '/api/auth/request'));
      expect(second['id'], isNot(first['id']));
      expect((await call('GET', '/api/auth/poll?id=${first['id']}')).statusCode,
          410);
    }, timeout: const Timeout(Duration(seconds: 30)));
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
}
