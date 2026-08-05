/// Expertenmodus — ein lokaler Server, der die Rohdaten am großen Bildschirm
/// zugänglich macht.
///
/// **Was er ist.** Regeln schreiben, die Aufgabenliste mit allen Feldern
/// überblicken, den Ereignisstrom lesen: Tätigkeiten, die Fläche brauchen.
/// Der Browser am Rechner arbeitet dabei auf den **echten** Daten des
/// Telefons, nicht auf einer Kopie — genau das trennt ihn vom
/// Desktop-Build, der eine eigene Datenbank hat.
///
/// **Was er nicht ist.** Kein zweiter Client. Er zeigt bewusst, was das
/// Telefon bewusst nicht zeigt — Listen, Rohwerte, Felder. Die Entscheidung
/// im Moment bleibt dort genau eine Handlung (G1).
///
/// **Der Preis, ausgeschrieben.** Er kostet `INTERNET` und damit die
/// strukturelle Garantie aus ADR-0002. Was an ihre Stelle tritt, steht in
/// ADR-0005: AXIOM **lauscht**, ruft aber nichts von sich aus auf. Und weil
/// hier Gesundheitsdaten auf einem Port liegen, ist die Absicherung kein
/// Beiwerk:
///
///   * aus, bis er eingeschaltet wird — kein Autostart
///   * sechsstellige PIN, bei jedem Start neu, nur in der App sichtbar
///   * Sitzungscookie statt PIN in der URL
///   * nach fünf Fehlversuchen stoppt er sich selbst
///   * nach 30 Minuten Leerlauf ebenso
///
/// **TLS mit selbst signiertem Zertifikat.** Ohne läge alles im Klartext im
/// Netz, und passives Mitlesen ist trivial. Die Browser-Warnung kommt genau
/// einmal: Das Zertifikat bleibt über Neustarts dasselbe, und sein
/// Fingerabdruck steht in der App — wer ihn mit dem vergleicht, den der
/// Browser zeigt, hat die Verbindung wirklich geprüft statt eine Warnung
/// weggeklickt. Fällt TLS aus, startet der Server **nicht**; ein stiller
/// Rückfall auf Klartext wäre das Schlechteste von beidem.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../state/runtime.dart';
import 'mdns_responder.dart';
import 'expert_certificate.dart';

/// Was der Server gerade tut — für die Anzeige in der App.
final class ExpertStatus {
  final bool running;
  final String? address;

  /// Der Weg über die IP. Steht neben dem Namen, weil Multicast in manchen
  /// Netzen gesperrt ist — dann löst `axiom.local` nicht auf, und eine
  /// Adresse, die nicht funktioniert, wäre schlimmer als zwei.
  final String? fallbackAddress;

  /// Zahl einer offenen Freigabeanfrage. Null heißt: keine.
  final String? pendingNumber;

  final String? pin;

  /// SHA-256 des Zertifikats. Der Wert, den auch der Browser anzeigt.
  final String? fingerprint;

  /// Wann er sich von selbst abschaltet, wenn nichts passiert.
  final DateTime? idleStopAt;

  const ExpertStatus({
    this.running = false,
    this.address,
    this.fallbackAddress,
    this.pendingNumber,
    this.pin,
    this.fingerprint,
    this.idleStopAt,
  });

  static const off = ExpertStatus();
}

/// Eine offene Freigabeanfrage aus dem Browser.
///
/// Kurzlebig mit Absicht: Neunzig Sekunden reichen, um vom Bildschirm zum
/// Telefon zu sehen. Alles darüber ist eine Zahl, die irgendwo steht und
/// auf jemanden wartet.
final class _AuthRequest {
  final String id;
  final String number;
  final DateTime at;
  bool approved = false;
  bool denied = false;

  _AuthRequest({required this.id, required this.number, required this.at});

  bool isExpired(DateTime now) =>
      now.difference(at) > const Duration(seconds: 90);
}

/// Wie lange der Server ohne Anfrage weiterläuft.
const Duration kExpertIdleTimeout = Duration(minutes: 30);

/// Nach so vielen falschen PINs schaltet er sich ab.
const int kExpertMaxAttempts = 5;

const int kExpertPort = 8787;

typedef RuntimeResolver = Future<AxiomRuntime> Function();

final class ExpertServer {
  ExpertServer({required this.resolveRuntime, required this.onChanged});

  /// Wird bei jeder Anfrage neu aufgelöst.
  ///
  /// Nicht einmal beim Start festgehalten: Nach einer Regeländerung baut die
  /// App die Laufzeit neu auf, und der Server muss danach die neue sehen —
  /// sonst zeigt er ein Regelwerk, das nicht mehr gilt.
  final RuntimeResolver resolveRuntime;

  /// Meldet der App, dass sich etwas geändert hat.
  final void Function() onChanged;

  HttpServer? _server;

  /// Meldet den Namen im lokalen Netz an, solange der Server laeuft.
  final _mdns = MdnsResponder();
  String? _pin;
  final Set<String> _sessions = {};
  int _failedAttempts = 0;

  /// Die eine offene Freigabeanfrage. Mehr als eine gleichzeitig gibt es
  /// nicht: Zwei Zahlen auf dem Telefon waeren eine Auswahl, und wer
  /// auswaehlt, vergleicht nicht mehr.
  _AuthRequest? _pending;
  Timer? _idleTimer;
  DateTime? _idleStopAt;
  String? _address;

  /// Die Adresse ueber die IP. Steht daneben, wenn der Name nicht
  /// aufloest — in manchen Netzen ist Multicast gesperrt, und dann waere
  /// eine Adresse, die nicht funktioniert, schlimmer als zwei.
  String? _fallbackAddress;
  ExpertCertificate? _certificate;

  bool get isRunning => _server != null;

  ExpertStatus get status => isRunning
      ? ExpertStatus(
          running: true,
          address: _address,
          fallbackAddress:
              _fallbackAddress == _address ? null : _fallbackAddress,
          pendingNumber: pendingNumber,
          pin: _pin,
          fingerprint: _certificate?.readableFingerprint,
          idleStopAt: _idleStopAt,
        )
      : ExpertStatus.off;

  Future<ExpertStatus> start({int port = kExpertPort}) async {
    if (isRunning) return status;

    final random = Random.secure();
    _pin = List.generate(6, (_) => random.nextInt(10)).join();
    _sessions.clear();
    _failedAttempts = 0;

    // Das Zertifikat haengt an der Adresse: Ohne passenden Subject
    // Alternative Name lehnen aktuelle Browser rundheraus ab, statt eine
    // Ausnahme anzubieten.
    final host = await _localIp() ?? '127.0.0.1';
    _certificate =
        await ExpertCertificates.forAddress(await resolveRuntime(), host);

    // bindSecure, nicht bind. Schlaegt es fehl, startet der Server nicht —
    // ein stiller Rueckfall auf Klartext waere das Schlechteste von beidem.
    _server = await HttpServer.bindSecure(
      InternetAddress.anyIPv4,
      port,
      _certificate!.context,
    );
    // Den tatsaechlich vergebenen Port nehmen, nicht den gewuenschten: Bei
    // Port 0 waehlt ihn das System, und die angezeigte Adresse zeigte sonst
    // auf einen Port, an dem nichts lauscht.
    // Der Name zuerst, die IP als Rueckfallweg: Ein Name, der bleibt, ist
    // die Bedingung dafuer, dass der Fingerabdruck-Vergleich zur Gewohnheit
    // wird — bei wechselnder IP faengt man jedes Mal von vorn an.
    final named = await _mdns.start(host);
    _address = named
        ? 'https://$kAxiomHostname:${_server!.port}'
        : 'https://$host:${_server!.port}';
    _fallbackAddress = 'https://$host:${_server!.port}';
    _touch();

    unawaited(_serve());
    return status;
  }

  Future<void> stop() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    _idleStopAt = null;
    _sessions.clear();
    _pin = null;
    final server = _server;
    _server = null;
    _address = null;
    _fallbackAddress = null;
    _certificate = null;
    await _mdns.stop();
    await server?.close(force: true);
    onChanged();
  }

  Future<void> _serve() async {
    final server = _server;
    if (server == null) return;
    await for (final request in server) {
      try {
        await _handle(request);
      } on Object catch (e) {
        // Ein Fehler in einer Anfrage darf den Server nicht mitnehmen —
        // sonst ist der Expertenmodus nach dem ersten Tippfehler weg.
        _json(request, 500, {'error': '$e'});
      }
      await request.response.close().catchError((_) {});
    }
  }

  /// Setzt die Leerlaufuhr zurück.
  void _touch() {
    _idleTimer?.cancel();
    _idleStopAt = DateTime.now().add(kExpertIdleTimeout);
    _idleTimer = Timer(kExpertIdleTimeout, stop);
  }

  // ── Anfragen ──────────────────────────────────────────────────────────

  /// Ausgeliefert werden genau diese vier Schnitte — nicht das ganze
  /// Verzeichnis. Ein Pfad, der aus einer Anfrage gebaut wird, waere ein
  /// Weg in fremde Assets.
  static const _fonts = <String, String>{
    '/font/sans-400.ttf': 'assets/fonts/IBMPlexSans-Regular.ttf',
    '/font/sans-500.ttf': 'assets/fonts/IBMPlexSans-Medium.ttf',
    '/font/mono-400.ttf': 'assets/fonts/IBMPlexMono-Regular.ttf',
    '/font/mono-500.ttf': 'assets/fonts/IBMPlexMono-Medium.ttf',
  };

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;

    // Die Oberfläche selbst ist nicht geheim — die Daten sind es.
    if (path == '/' || path == '/index.html') {
      _touch();
      final html = await rootBundle.loadString('assets/expert/index.html');
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        // Kein fremder Code, keine fremden Ziele. Die Seite ist
        // vollstaendig eigenstaendig; alles andere waere ein Weg nach
        // draussen, den ADR-0005 ausschliesst.
        ..headers.set('Content-Security-Policy',
            "default-src 'self'; style-src 'self' 'unsafe-inline'; "
            "script-src 'self' 'unsafe-inline'; connect-src 'self'; "
            "font-src 'self'; img-src 'self' data:; "
            // Nichts einbetten, nirgends eingebettet werden, kein Ziel
            // ausserhalb der Seite.
            "object-src 'none'; frame-ancestors 'none'; base-uri 'none'")
        ..headers.set('X-Content-Type-Options', 'nosniff')
        ..headers.set('Referrer-Policy', 'no-referrer')
        ..write(html);
      return;
    }

    // Dieselben Schriften wie auf dem Telefon.
    //
    // Nicht Kosmetik: IBM Plex Mono traegt hier jede Messgroesse, und eine
    // Systemschrift statt dessen macht aus einem abgelesenen Wert einen
    // gemeinten. Von aussen nachladen geht ohnehin nicht — die
    // Sicherheitsrichtlinie der Seite laesst kein fremdes Ziel zu, und
    // ADR-0005 auch nicht.
    if (_fonts.containsKey(path)) {
      _touch();
      final bytes = await rootBundle.load(_fonts[path]!);
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType('font', 'ttf')
        ..headers.set('Cache-Control', 'public, max-age=604800')
        ..add(bytes.buffer.asUint8List());
      await request.response.close();
      return;
    }

    if (path == '/api/login' && request.method == 'POST') {
      return _login(request);
    }

    if (path == '/api/auth/request' && request.method == 'POST') {
      return _requestApproval(request);
    }
    if (path == '/api/auth/poll' && request.method == 'GET') {
      return _pollApproval(request);
    }

    if (!_authorised(request)) {
      return _json(request, 401, {'error': 'PIN erforderlich'});
    }
    _touch();

    final segments = request.uri.pathSegments;
    final runtime = await resolveRuntime();

    switch ((request.method, segments)) {
      case ('GET', ['api', 'state']):
        return _json(request, 200, await _state(runtime));

      case ('GET', ['api', 'tasks']):
        return _json(request, 200, {
          'tasks': (await runtime.store.tasks()).map(_task).toList(),
        });

      case ('POST', ['api', 'tasks']):
        final body = await _body(request);
        final task = await runtime.createTask(
          title: (body['title'] as String?)?.trim() ?? '',
          activationEnergy: _clamp(body['activationEnergy'], 1, 10, 5),
          salience: _clamp(body['salience'], 1, 10, 3),
          stakes: _clamp(body['stakes'], 1, 10, 3),
          decayAt: _date(body['decayAt']),
        );
        onChanged();
        return _json(request, 200, _task(task));

      case ('PATCH', ['api', 'tasks', final id]):
        return _patchTask(request, runtime, id);

      case ('GET', ['api', 'rules']):
        return _json(request, 200, await _rules(runtime));

      case ('PUT', ['api', 'rules', final id]):
        return _putRule(request, runtime, id);

      case ('DELETE', ['api', 'rules', final id]):
        runtime.store.deleteRuleOverride(id);
        onChanged();
        return _json(request, 200, {'ok': true});

      case ('GET', ['api', 'events']):
        final limit =
            int.tryParse(request.uri.queryParameters['limit'] ?? '') ?? 200;
        final events = await runtime.store.query();
        return _json(request, 200, {
          'events': events.reversed.take(limit).map(_event).toList(),
        });

      case ('POST', ['api', 'capture']):
        final body = await _body(request);
        final text = (body['text'] as String?)?.trim() ?? '';
        if (text.isEmpty) {
          return _json(request, 400, {'error': 'Kein Text'});
        }
        await runtime.capture(text, via: 'expert');
        onChanged();
        return _json(request, 200, {'ok': true});

      // ── Die eine Handlung, im Browser bedienbar ──────────────────────
      //
      // ADR-0005 sagte, die Entscheidung im Moment bleibe auf dem Telefon.
      // Das galt fuer ein Geraet, das man dabei hat. Am Arbeitsplatz liegt
      // es in der Tasche, und ein Vorschlag, den man nicht annehmen kann,
      // ist keiner. G1 bleibt gewahrt: Es ist genau eine Handlung, keine
      // Liste zur Auswahl — die Liste steht weiterhin daneben, als das,
      // was der Expertenmodus ohnehin zeigt.
      case ('POST', ['api', 'tasks', final id, final verb])
          when const ['start', 'complete', 'release', 'drop'].contains(verb):
        final task = (await runtime.store.tasks())
            .where((t) => t.id == id)
            .firstOrNull;
        if (task == null) {
          return _json(request, 404, {'error': 'Aufgabe nicht gefunden'});
        }
        switch (verb) {
          case 'start':
            await runtime.startTask(task);
          case 'complete':
            await runtime.completeTask(task);
          case 'release':
            await runtime.releaseTask(task);
          case 'drop':
            await runtime.dropTask(task);
        }
        onChanged();
        return _json(request, 200, {'ok': true});

      case ('POST', ['api', 'tasks', final id, 'atomize']):
        final body = await _body(request);
        final task = (await runtime.store.tasks())
            .where((t) => t.id == id)
            .firstOrNull;
        if (task == null) {
          return _json(request, 404, {'error': 'Aufgabe nicht gefunden'});
        }
        final raw = body['steps'];
        if (raw is! List || raw.isEmpty) {
          return _json(request, 400, {'error': 'Keine Schritte'});
        }
        final steps = <({String title, int energy})>[];
        for (final entry in raw) {
          if (entry is! Map) continue;
          final title = (entry['title'] as String?)?.trim() ?? '';
          if (title.isEmpty) continue;
          steps.add((title: title, energy: _clamp(entry['energy'], 1, 10, 2)));
        }
        if (steps.isEmpty) {
          return _json(request, 400, {'error': 'Keine gültigen Schritte'});
        }
        final children = await runtime.atomize(parent: task, steps: steps);
        onChanged();
        return _json(request, 200, {
          'children': children.map(_task).toList(),
        });

      // ── Rückmeldung zur Entscheidung ─────────────────────────────────
      //
      // Ohne sie waere die Karte im Browser eine Anzeige und keine
      // Handlung: Was der Nutzer mit einem Vorschlag macht, ist die einzige
      // Zahl, an der sich eine Regel messen laesst (Befolgungsquote im
      // Wochenreview). Fehlte sie hier, waere jede Nutzung am Arbeitsplatz
      // aus Sicht der Auswertung ein Vorschlag ohne Antwort.
      case ('POST', ['api', 'decisions', final id]):
        final body = await _body(request);
        final name = body['response'] as String?;
        final response = DecisionResponse.values
            .where((r) => r.name == name)
            .firstOrNull;
        if (response == null) {
          return _json(request, 400, {'error': 'Unbekannte Antwort: $name'});
        }
        await runtime.store.setDecisionResponse(id, response);
        await runtime.record(EventType.decisionFeedback,
            payload: {'decision_id': id, 'response': response.name});
        onChanged();
        return _json(request, 200, {'ok': true});

      // ── Check-in: die vier Regler ────────────────────────────────────
      case ('POST', ['api', 'checkin']):
        final body = await _body(request);
        await runtime.checkIn(
          energy: _clamp(body['energy'], 1, 5, 3),
          focus: _clamp(body['focus'], 1, 5, 3),
          mood: _clamp(body['mood'], 1, 5, 3),
          stimNeed: _clamp(body['stimNeed'], 1, 5, 3),
          compensation: body['compensation'] == null
              ? null
              : _clamp(body['compensation'], 1, 5, 3),
          recovery:
              body['recovery'] == null ? null : _clamp(body['recovery'], 1, 5, 3),
          slot: (body['slot'] as String?) ?? 'expert',
        );
        onChanged();
        return _json(request, 200, {'ok': true});

      // ── Fokus ────────────────────────────────────────────────────────
      case ('POST', ['api', 'focus']):
        final body = await _body(request);
        final minutes = _clamp(body['minutes'], 5, 180, 25);
        final session = await runtime.startFocus(
          taskId: body['taskId'] as String?,
          taskTitle: (body['title'] as String?)?.trim(),
          planned: Duration(minutes: minutes),
        );
        onChanged();
        return _json(request, 200, {'id': session.id});

      case ('DELETE', ['api', 'focus']):
        final running = await runtime.store.activeFocus();
        if (running == null) {
          return _json(request, 404, {'error': 'Kein Fokus läuft'});
        }
        final body = await _body(request);
        await runtime.endFocus(
          running,
          breadcrumb: (body['breadcrumb'] as String?)?.trim(),
        );
        onChanged();
        return _json(request, 200, {'ok': true});

      // ── Eingang ──────────────────────────────────────────────────────
      case ('GET', ['api', 'inbox']):
        final notes = await runtime.store.query(types: {EventType.capture});
        final sorted = (await runtime.store.tasks())
            .where((t) => t.state == TaskState.inbox)
            .map(_task)
            .toList();
        return _json(request, 200, {
          'notes': notes.reversed
              .take(100)
              .map((e) => {
                    'id': e.id,
                    'at': e.at.toLocal().toIso8601String(),
                    'text': e.payload['text'],
                    'via': e.payload['via'],
                  })
              .toList(),
          'tasks': sorted,
        });

      // ── Review ───────────────────────────────────────────────────────
      case ('GET', ['api', 'review']):
        final name = request.uri.queryParameters['scope'] ?? 'day';
        final scope = ReviewScope.values
            .where((s) => s.name == name)
            .firstOrNull;
        if (scope == null) {
          return _json(request, 400, {'error': 'Unbekannter Umfang: $name'});
        }
        final result = await runtime.review(scope);
        return _json(request, 200, {
          'scope': scope.name,
          'metrics': [
            for (final m in result.metrics)
              {
                'id': m.id,
                'label': m.label,
                'value': m.valueSource.text,
                // Ohne die Herleitung ist die Zahl nicht ueberpruefbar (G2).
                'derivation': m.derivation,
              },
          ],
          'verdicts': [
            for (final v in result.verdicts)
              {
                'ruleId': v.ruleId,
                'verdict': v.verdict.name,
                'reason': v.reason,
              },
          ],
        });

      case ('POST', ['api', 'stop']):
        unawaited(stop());
        return _json(request, 200, {'ok': true});

      default:
        return _json(request, 404, {'error': 'Unbekannt: $path'});
    }
  }

  // ── Anmeldung ─────────────────────────────────────────────────────────

  Future<void> _login(HttpRequest request) async {
    final body = await _body(request);
    final given = (body['pin'] as String?)?.trim();

    if (given != null && given == _pin) {
      _failedAttempts = 0;
      final token = _token();
      _sessions.add(token);
      _touch();
      request.response.headers.add(
        HttpHeaders.setCookieHeader,
        // `Secure`, weil die Verbindung TLS spricht: Das Cookie darf eine
        // Klartextverbindung nie erreichen, auch nicht versehentlich.
        'axiom_session=$token; HttpOnly; Secure; SameSite=Strict; Path=/',
      );
      return _json(request, 200, {'ok': true});
    }

    _failedAttempts++;
    if (_failedAttempts >= kExpertMaxAttempts) {
      // Kein Zählwerk, das man aussitzen kann: Der Server geht aus, und die
      // naechste PIN ist eine andere.
      _json(request, 403, {'error': 'Zu viele Fehlversuche. Server gestoppt.'});
      await request.response.close().catchError((_) {});
      await stop();
      return;
    }
    return _json(request, 401, {
      'error': 'Falsche PIN',
      'attemptsLeft': kExpertMaxAttempts - _failedAttempts,
    });
  }

  /// Fragt eine Freigabe an und gibt die Zahl zurueck, die verglichen wird.
  ///
  /// **Warum das sicherer ist als ein Knopf.** Eine Benachrichtigung mit
  /// „Anmeldung zulassen?" wird weggedrueckt wie jede andere. Der Schutz
  /// liegt nicht in der Bestaetigung, sondern im Abgleich: Fragt jemand
  /// anders im selben Moment an, zeigt das Telefon dessen Zahl — und die
  /// steht nicht auf dem Bildschirm, vor dem der Nutzer sitzt. Wer nur
  /// bestaetigt, was uebereinstimmt, laesst niemand anderen herein.
  ///
  /// Genau deshalb gibt es immer nur **eine** offene Anfrage: Zwei Zahlen
  /// zur Auswahl waeren wieder ein Knopf.
  Future<void> _requestApproval(HttpRequest request) async {
    _touch();
    final now = DateTime.now();
    final open = _pending;
    if (open != null &&
        !open.isExpired(now) &&
        now.difference(open.at) < const Duration(seconds: 3)) {
      // Zu schnell hintereinander: Sonst laesst sich die Zahl erraten,
      // indem man sie oft genug neu wuerfelt, bis eine passt, die gerade
      // auf dem Telefon steht.
      return _json(request, 429, {'error': 'Zu schnell. Kurz warten.'});
    }
    final random = Random.secure();
    _pending = _AuthRequest(
      id: _token(),
      // Zweistellig: lang genug, dass Zufall nicht traegt, kurz genug, dass
      // man es in einem Blick vergleicht statt abzulesen.
      number: (10 + random.nextInt(90)).toString(),
      at: now,
    );
    onChanged();
    return _json(request, 200, {
      'id': _pending!.id,
      'number': _pending!.number,
    });
  }

  Future<void> _pollApproval(HttpRequest request) async {
    final id = request.uri.queryParameters['id'];
    final open = _pending;
    if (open == null || open.id != id || open.isExpired(DateTime.now())) {
      return _json(request, 410, {'error': 'Abgelaufen'});
    }
    if (open.denied) {
      _pending = null;
      onChanged();
      return _json(request, 403, {'error': 'Abgelehnt'});
    }
    if (!open.approved) {
      _touch();
      return _json(request, 202, {'pending': true});
    }
    _pending = null;
    _failedAttempts = 0;
    final token = _token();
    _sessions.add(token);
    _touch();
    onChanged();
    request.response.headers.add(
      HttpHeaders.setCookieHeader,
      'axiom_session=$token; HttpOnly; Secure; SameSite=Strict; Path=/',
    );
    return _json(request, 200, {'ok': true});
  }

  /// Die offene Anfrage, wie die App sie anzeigt. Null heisst: keine.
  String? get pendingNumber {
    final open = _pending;
    if (open == null || open.isExpired(DateTime.now())) return null;
    return open.approved || open.denied ? null : open.number;
  }

  /// Aus der App heraus: freigeben oder ablehnen.
  void resolvePending({required bool approve}) {
    final open = _pending;
    if (open == null || open.isExpired(DateTime.now())) return;
    if (approve) {
      open.approved = true;
    } else {
      open.denied = true;
      // Eine Ablehnung zaehlt wie ein Fehlversuch: Wer wiederholt anfragt,
      // bringt den Server dazu, sich abzuschalten.
      _failedAttempts++;
      if (_failedAttempts >= kExpertMaxAttempts) unawaited(stop());
    }
    onChanged();
  }

  bool _authorised(HttpRequest request) {
    for (final cookie in request.cookies) {
      if (cookie.name == 'axiom_session' && _sessions.contains(cookie.value)) {
        return true;
      }
    }
    return false;
  }

  String _token() {
    final random = Random.secure();
    return List.generate(32, (_) => random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  // ── Einzelne Zugriffe ─────────────────────────────────────────────────

  Future<void> _patchTask(
    HttpRequest request,
    AxiomRuntime runtime,
    String id,
  ) async {
    final tasks = await runtime.store.tasks();
    final task = tasks.where((t) => t.id == id).firstOrNull;
    if (task == null) return _json(request, 404, {'error': 'Unbekannt: $id'});

    final body = await _body(request);
    final state = body['state'] as String?;

    // Zustandswechsel gehen über die Laufzeit, nicht über den Speicher:
    // Sie erzeugen Events, und die Events sind die Wahrheit.
    if (state != null && state != task.state.name) {
      switch (state) {
        case 'done':
          await runtime.completeTask(task);
        case 'dropped':
          await runtime.dropTask(task);
        case 'active':
          await runtime.startTask(task);
        default:
          await runtime.store.upsertTask(task.copyWith(
            state: TaskState.values.firstWhere((s) => s.name == state,
                orElse: () => task.state),
          ));
      }
    }

    final updated = (await runtime.store.tasks()).firstWhere((t) => t.id == id);
    await runtime.store.upsertTask(updated.copyWith(
      title: (body['title'] as String?)?.trim(),
      activationEnergy: body.containsKey('activationEnergy')
          ? _int(body['activationEnergy'], updated.activationEnergy)
          : null,
      salience: body.containsKey('salience')
          ? _int(body['salience'], updated.salience)
          : null,
      stakes: body.containsKey('stakes')
          ? _int(body['stakes'], updated.stakes)
          : null,
      decayAt: _date(body['decayAt']),
    ));
    onChanged();

    final result = (await runtime.store.tasks()).firstWhere((t) => t.id == id);
    return _json(request, 200, _task(result));
  }

  Future<void> _putRule(
    HttpRequest request,
    AxiomRuntime runtime,
    String id,
  ) async {
    final body = await _body(request);
    final yaml = (body['yaml'] as String?) ?? '';

    // Erst prüfen, dann speichern. Eine ungültige Regel abzulehnen ist der
    // ganze Punkt: Eine stumm übersprungene wäre schlimmer als ein Fehler.
    final parsed = YamlRuleSource({'entwurf': yaml}).parse();
    if (parsed.issues.isNotEmpty) {
      return _json(request, 400, {
        'error': 'Regel ungültig',
        'issues': parsed.issues.map((i) => '${i.ruleId}: ${i.message}').toList(),
      });
    }
    if (parsed.rules.length != 1) {
      return _json(request, 400, {
        'error': 'Genau eine Regel je Eintrag, gefunden: ${parsed.rules.length}',
      });
    }
    final rule = parsed.rules.single;
    if (rule.id != id) {
      return _json(request, 400, {
        'error': 'Die ID darf sich nicht ändern ($id → ${rule.id}). '
            'IDs werden nie wiederverwendet.',
      });
    }

    final existing = runtime.store.ruleOverride(id);
    final now = runtime.clock.nowLocal();
    runtime.store.saveRuleOverride(
      id: id,
      yaml: yaml,
      overridesShipped:
          existing?.overridesShipped ?? runtime.rules.any((r) => r.id == id),
      updatedAt: now,
      // Dieselbe Zusage wie im Editor auf dem Telefon: Geändert ist neu, und
      // Neues läuft sieben Tage stumm mit.
      shadowUntil: now.add(kShadowPeriod),
    );
    onChanged();
    return _json(request, 200, {
      'ok': true,
      'shadowUntil': now.add(kShadowPeriod).toIso8601String(),
    });
  }

  // ── Abbildung nach JSON ───────────────────────────────────────────────

  Future<Map<String, Object?>> _state(AxiomRuntime runtime) async {
    final snapshot = await runtime.evaluate();
    final state = snapshot.state;
    return {
      'at': snapshot.at.toIso8601String(),
      'values': {
        for (final variable in RuleVocabulary.numerics)
          variable.id: {
            'label': variable.label,
            'value': state.numeric(variable.id),
            'confidence': state.confidenceOf(variable.id),
          },
      },
      'loadLevel': state.loadLevel.name.toUpperCase(),
      'regime': snapshot.regime.headline,
      'breakdown': {
        for (final entry in snapshot.breakdown.entries)
          entry.key: entry.value
              .map((t) => {'label': t.label, 'contribution': t.contribution})
              .toList(),
      },
      // Die eine Handlung — mit Begruendung, wie ueberall (G2).
      'decision': snapshot.decision == null || snapshot.decisionRule == null
          ? null
          : {
              'id': snapshot.decision!.id,
              'ruleId': snapshot.decisionRule!.id,
              'title': snapshot.decisionRule!.title,
              'rationale': snapshot.decisionRule!.rationale,
              'action': snapshot.decisionRule!.then.type.name,
              'deficit': snapshot.decisionRule!.deficit,
            },
      // Damit der Browser dieselbe Mechanik anbieten kann wie das Telefon:
      // erst das Laufende, sonst der Vorschlag.
      'running': snapshot.tasks
          .where((t) => t.state == TaskState.active)
          .map(_task)
          .toList(),
      'startable': snapshot.startable.map(_task).toList(),
      'atomize': snapshot.atomizeCandidates
          .map((c) => {
                'taskId': c.task.id,
                'title': c.task.title,
                'activationEnergy': c.task.activationEnergy,
                'reason': c.explanation,
                'targetEnergy': c.targetEnergy,
              })
          .toList(),
      'focus': snapshot.focus == null
          ? null
          : {
              'id': snapshot.focus!.id,
              'title': snapshot.focus!.anchorTitle,
              'taskId': snapshot.focus!.anchorTaskId,
              'startedAt': snapshot.focus!.startedAt.toIso8601String(),
              'plannedMinutes': snapshot.focus!.planned.inMinutes,
              'elapsedMinutes':
                  snapshot.focus!.elapsed(snapshot.at).inMinutes,
              'verdict': snapshot.focusVerdict == null
                  ? null
                  : {
                      'action': snapshot.focusVerdict!.action.name,
                      'reason': snapshot.focusVerdict!.reason.text,
                    },
            },
      'nextStep': snapshot.nextStep == null
          ? null
          : {
              'anchor': snapshot.nextStep!.anchor.title,
              'label': snapshot.nextStep!.step.label,
              'at': snapshot.nextStep!.step.at.toIso8601String(),
              'kind': snapshot.nextStep!.step.kind.name,
            },
      'anchors': [
        for (final anchor in snapshot.anchors)
          {
            'id': anchor.id,
            'title': anchor.title,
            'arriveBy': anchor.arriveBy.toIso8601String(),
            'location': anchor.location,
            'steps': [
              for (final step in anchor.chain)
                {
                  'label': step.label,
                  'at': step.at.toIso8601String(),
                  'kind': step.kind.name,
                },
            ],
          },
      ],
      'sensation': {
        'availableMinutes': snapshot.sensationBudget.availableMinutes,
        'hasCredit': snapshot.sensationBudget.hasCredit,
      },
      'inboxCount': snapshot.inbox.length,
      'regimeLevel': snapshot.regime.level.name.toUpperCase(),
      'regimeDescription': snapshot.regime.description,
      'suggestsReferral': snapshot.suggestsReferral,
      'metaMinutesToday': snapshot.metaUsedToday.inMinutes,
      'metaBudgetMinutes': kMetaBudget.inMinutes,
      'configLocked': await runtime.isConfigLocked(),
      'weightsCalibrated': runtime.weightsCalibrated,
    };
  }

  Future<Map<String, Object?>> _rules(AxiomRuntime runtime) async {
    final overrides = {
      for (final o in runtime.store.ruleOverrides()) o.id: o,
    };
    final now = runtime.clock.nowLocal();
    return {
      'rules': [
        for (final rule in runtime.rules)
          {
            'id': rule.id,
            'title': rule.title,
            'deficit': rule.deficit,
            'severity': rule.severity.name,
            'priority': rule.priority,
            'action': rule.then.type.token,
            'enabled': rule.enabled,
            'shadow': rule.isShadow,
            'condition': rule.when.toString(),
            'edited': overrides.containsKey(rule.id),
            'shadowDaysLeft': overrides[rule.id]?.isShadowed(now) == true
                ? overrides[rule.id]!.shadowDaysLeft(now)
                : 0,
            'yaml': overrides[rule.id]?.yaml ?? ruleToYaml(rule),
          },
      ],
      'issues': runtime.ruleIssues.map((i) => '$i').toList(),
    };
  }

  Map<String, Object?> _task(Task task) => {
        'id': task.id,
        'title': task.title,
        'activationEnergy': task.activationEnergy,
        'salience': task.salience,
        'stakes': task.stakes,
        'state': task.state.name,
        'decayAt': task.decayAt?.toIso8601String(),
        'parentId': task.parentId,
        'breadcrumb': task.breadcrumb,
      };

  Map<String, Object?> _event(Event event) => {
        'id': event.id,
        'at': event.at.toLocal().toIso8601String(),
        'type': event.type.name,
        'source': event.source.name,
        'payload': event.payload,
      };

  // ── Kleinkram ─────────────────────────────────────────────────────────

  Future<Map<String, Object?>> _body(HttpRequest request) async {
    final text = await utf8.decoder.bind(request).join();
    if (text.trim().isEmpty) return {};
    final decoded = jsonDecode(text);
    return decoded is Map<String, Object?> ? decoded : {};
  }

  void _json(HttpRequest request, int status, Map<String, Object?> body) {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..headers.set('X-Content-Type-Options', 'nosniff')
      ..write(jsonEncode(body));
  }

  static int _int(Object? value, int fallback) =>
      value is num ? value.toInt() : fallback;

  /// Eine Zahl aus dem Netz, auf den erlaubten Bereich gebracht.
  ///
  /// **Warum das nicht optional ist.** Die Domaenentypen sichern ihre
  /// Wertebereiche per `assert` ab — und `assert` ist im Release-Build
  /// abgeschaltet. Ein leeres Zahlenfeld oder ein per Hand abgeschickter
  /// Wert wie 999 landete damit ungeprueft in der Datenbank und verzerrte
  /// jede Auswahl, ohne dass irgendwo ein Fehler stand. Ein Wert, der
  /// stumm falsch ist, ist teurer als eine abgelehnte Anfrage.
  static int _clamp(Object? value, int min, int max, int fallback) {
    final n = value is num
        ? value.toInt()
        : value is String
            ? int.tryParse(value.trim())
            : null;
    if (n == null) return fallback;
    return n < min ? min : (n > max ? max : n);
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  /// Die Adresse im eigenen Netz — ohne sie müsste man sie am Telefon
  /// nachschlagen, und dann benutzt es niemand.
  static Future<String?> _localIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback) return address.address;
        }
      }
    } on Object {
      // Kein Netz: Dann bleibt localhost, was ueber adb forward reicht.
    }
    return null;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
