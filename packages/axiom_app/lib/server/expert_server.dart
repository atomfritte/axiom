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

/// Eine Eingabe aus dem Netz, die sich nicht übernehmen lässt.
///
/// **Warum abgelehnt und nicht repariert.** Ein unbekannter Zustandsname,
/// ein unlesbares Datum, ein Schritt ohne Titel — nichts davon lässt sich
/// raten. Es stillschweigend zu übergehen ist die teuerste Variante: Der
/// Aufrufer glaubt dann, seine Angabe sei angekommen, und die Datenbank
/// enthält etwas anderes als der Bildschirm zeigt.
///
/// Zahlen sind der Sonderfall: Ein Regler, der über seinen Bereich hinaus
/// gerutscht ist, lässt sich zurückholen (`_clamp`) — ein Name, den es
/// nicht gibt, nicht.
final class _Invalid implements Exception {
  final String message;
  _Invalid(this.message);
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
      } on _Invalid catch (e) {
        // Eine abgelehnte Eingabe ist ein Ergebnis, kein Serverfehler: Sie
        // nennt ihren Grund und hat nichts geändert.
        _json(request, 400, {'error': e.message});
      } on Object catch (e) {
        // Ein Fehler in einer Anfrage darf den Server nicht mitnehmen —
        // sonst ist der Expertenmodus nach dem ersten Tippfehler weg.
        //
        // Den Wortlaut bekommt nur eine angemeldete Sitzung. Hier liegen
        // Gesundheitsdaten, und eine Ausnahmemeldung führt gern den Wert
        // mit, an dem sie scheiterte — ohne Anmeldung gibt es deshalb nur,
        // *dass* etwas schiefging.
        _json(request, 500,
            {'error': _authorised(request) ? '$e' : 'Verarbeitungsfehler'});
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

  // ── Nutzerdokumentation: drei feste Listen statt drei Pfadbauten ─────
  //
  // Kapitelnummer, Sprache und Bildname kommen aus dem Netz. Aus keinem
  // von ihnen wird ein Asset-Pfad zusammengesetzt — jeder ist ein
  // Schlüssel in eine `const`-Liste, und was dort nicht steht, gibt es
  // nicht. Ein aus der Anfrage gebauter Pfad ist die Stelle, an der ein
  // lokaler Server unbemerkt zum Dateiserver für das ganze Bündel wird;
  // `../` wäre dann kein Angriff mehr, sondern nur eine Anfrage.

  /// Nummer → Dateiname. Die Nummer ist zugleich das Ziel von `kapitel:NN`
  /// in der Doku: Ein Querverweis zeigt damit auf ein Kapitel und nicht auf
  /// einen Dateinamen, der sich beim Umbenennen ändert.
  static const _helpChapters = <String, String>{
    '00': '00-index',
    '01': '01-was-das-ist',
    '02': '02-erster-tag',
    '03': '03-erfassen',
    '04': '04-eine-handlung',
    '05': '05-zustand',
    '06': '06-aufgaben',
    '07': '07-zeitanker',
    '08': '08-fokus',
    '09': '09-regelwerk',
    '10': '10-rueckblick',
    '11': '11-expertenmodus',
    '12': '12-daten',
    '13': '13-grenzen',
  };

  /// Auch die Sprache wählt ein Verzeichnis — ein ungeprüfter
  /// Verzeichnisname ist dieselbe Lücke wie ein ungeprüfter Dateiname.
  static const _helpDirs = <String, String>{
    'de': 'assets/help/de/',
    'en': 'assets/help/en/',
  };

  static const _helpImages = <String, String>{
    '/help/img/anker.webp': 'assets/help/img/anker.webp',
    '/help/img/aufgaben.webp': 'assets/help/img/aufgaben.webp',
    '/help/img/bremse.webp': 'assets/help/img/bremse.webp',
    '/help/img/eichung.webp': 'assets/help/img/eichung.webp',
    '/help/img/fokus.webp': 'assets/help/img/fokus.webp',
    '/help/img/health.webp': 'assets/help/img/health.webp',
    '/help/img/jetzt.webp': 'assets/help/img/jetzt.webp',
    '/help/img/reiz.webp': 'assets/help/img/reiz.webp',
    '/help/img/review.webp': 'assets/help/img/review.webp',
    '/help/img/system.webp': 'assets/help/img/system.webp',
    '/help/img/zerlegen.webp': 'assets/help/img/zerlegen.webp',
    '/help/img/zustand.webp': 'assets/help/img/zustand.webp',
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
        final tasks = await runtime.store.tasks();
        final counts = _childCounts(tasks);
        return _json(request, 200, {
          'tasks': [for (final task in tasks) _task(task, counts)],
        });

      case ('POST', ['api', 'tasks']):
        final body = await _body(request);
        final task = await runtime.createTask(
          // Ohne Titel entstand bisher eine namenlose Aufgabe, die in jeder
          // Liste steht und in keiner erkennbar ist.
          title: _requiredText(body, 'title', max: 500),
          activationEnergy: _clamp(body['activationEnergy'], 1, 10, 5),
          salience: _clamp(body['salience'], 1, 10, 3),
          stakes: _clamp(body['stakes'], 1, 10, 3),
          decayAt: _date(body, 'decayAt'),
        );
        onChanged();
        return _json(request, 200, _task(task));

      case ('PATCH', ['api', 'tasks', final id]):
        return _patchTask(request, runtime, id);

      case ('GET', ['api', 'rules']):
        return _json(request, 200, await _rules(runtime));

      // ── Der Wortschatz, aus dem eine Regel besteht ───────────────────
      //
      // Damit der Browser führen kann statt raten zu lassen: Welche
      // Variablen es gibt, was sie bedeuten, welche Operatoren zu ihnen
      // passen. Alles daraus ist aus `RuleVocabulary` abgeleitet, nichts
      // abgeschrieben — eine zweite, handgepflegte Liste driftet ab, und
      // genau dieser Fehler stand schon einmal im Regelvalidator: Eine im
      // Wortschatz ergänzte Variable galt dort als unbekannt, und die
      // Regel, die sie benutzte, wurde nicht geladen.
      case ('GET', ['api', 'vocabulary']):
        return _json(request, 200, _vocabulary());

      // Steht vor dem allgemeinen Regelzweig: „preview" ist ein fester
      // Pfad, keine Regel-ID. Ein POST auf eine ID gibt es nicht — sonst
      // müsste diese Reihenfolge zusätzlich geprüft werden.
      case ('POST', ['api', 'rules', 'preview']):
        final body = await _body(request);
        return _json(request, 200,
            await _preview(runtime, _requiredText(body, 'yaml', max: 20000)));

      case ('PUT', ['api', 'rules', final id]):
        return _putRule(request, runtime, id);

      case ('DELETE', ['api', 'rules', final id]):
        runtime.store.deleteRuleOverride(id);
        onChanged();
        return _json(request, 200, {'ok': true});

      case ('GET', ['api', 'events']):
        // Gedeckelt, nicht ungeprüft übernommen: `take(-1)` wirft, und eine
        // Million angeforderter Zeilen wäre eine Anfrage, die das Telefon
        // beschäftigt, bis der Browser aufgibt.
        final limit =
            _clamp(request.uri.queryParameters['limit'], 1, 1000, 200);
        final events = await runtime.store.query();
        return _json(request, 200, {
          'events': events.reversed.take(limit).map(_event).toList(),
        });

      case ('POST', ['api', 'capture']):
        final body = await _body(request);
        await runtime.capture(_requiredText(body, 'text', max: 4000),
            via: 'expert');
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
        // Eine Zerlegung in mehr als zwanzig Schritte ist ein Projektplan,
        // und der ist selbst wieder eine Aufgabe mit hoher
        // Aktivierungsenergie (M2, D2).
        if (raw.length > 20) {
          throw _Invalid('Höchstens 20 Schritte je Zerlegung, '
              'angefragt: ${raw.length}');
        }
        final steps = <({String title, int energy})>[];
        for (var i = 0; i < raw.length; i++) {
          // Ein übersprungener Schritt wäre der schlimmste Ausgang: Die
          // Aufgabe gilt danach als zerlegt, und der Teil, den es wirklich
          // braucht, fehlt — ohne dass irgendwo etwas steht.
          final entry = raw[i];
          if (entry is! Map) {
            throw _Invalid('Schritt ${i + 1} ist kein Eintrag mit "title"');
          }
          final title = entry['title'];
          if (title is! String || title.trim().isEmpty) {
            throw _Invalid('Schritt ${i + 1} hat keinen Titel');
          }
          steps.add((
            title: title.trim(),
            energy: _clamp(entry['energy'], 1, 10, 2),
          ));
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
        // Eine Rueckmeldung auf eine Phantom-ID verzerrt die
        // Befolgungsquote im Wochenreview — still, und genau deshalb teuer.
        if (!await runtime.store.hasDecision(id)) {
          return _json(request, 404, {'error': 'Entscheidung nicht gefunden'});
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
          slot: _text(body, 'slot', max: 40) ?? 'expert',
        );
        onChanged();
        return _json(request, 200, {'ok': true});

      // ── Fokus ────────────────────────────────────────────────────────
      case ('POST', ['api', 'focus']):
        final body = await _body(request);
        final minutes = _clamp(body['minutes'], 5, 180, 25);
        final anchorId = _text(body, 'taskId', max: 64);
        // Ein Fokusfenster an einer Aufgabe, die es nicht gibt, laesst sich
        // spaeter niemandem zuordnen: Es zaehlt Zeit auf einen Anker, den
        // keine Auswertung wiederfindet.
        if (anchorId != null &&
            !(await runtime.store.tasks()).any((t) => t.id == anchorId)) {
          return _json(request, 404, {'error': 'Aufgabe nicht gefunden'});
        }
        final session = await runtime.startFocus(
          taskId: anchorId,
          taskTitle: _text(body, 'title', max: 500),
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
          breadcrumb: _text(body, 'breadcrumb', max: 2000),
        );
        onChanged();
        return _json(request, 200, {'ok': true});

      // ── Eingang ──────────────────────────────────────────────────────
      case ('GET', ['api', 'inbox']):
        final notes = await runtime.store.query(types: {EventType.capture});
        final all = await runtime.store.tasks();
        final inboxCounts = _childCounts(all);
        final sorted = [
          for (final task in all)
            if (task.state == TaskState.inbox) _task(task, inboxCounts),
        ];
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

      // ── Nutzerdokumentation ──────────────────────────────────────────
      //
      // Sie enthält keine Nutzerdaten — sie erklärt die App. Trotzdem
      // hinter der Sitzungsprüfung: Eine Route, die daran vorbeigeht, ist
      // eine, die man beim nächsten Zusatz vergisst, und der Unterschied
      // zwischen „erklärt die Oberfläche" und „zeigt, was drinsteht" ist
      // eine Zeile Code weit. Der Preis ist null — wer die Hilfe liest,
      // ist ohnehin angemeldet.
      case ('GET', ['api', 'help']):
        return _json(request, 200, await _helpIndex(_helpLang(request)));

      case ('GET', ['api', 'help', final id]):
        return _helpChapter(request, id, _helpLang(request));

      case ('GET', ['help', 'img', _]):
        return _helpImage(request, path);

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
    final state = _text(body, 'state', max: 20);

    // Zustandswechsel gehen über die Laufzeit, nicht über den Speicher:
    // Sie erzeugen Events, und die Events sind die Wahrheit.
    if (state != null && state != task.state.name) {
      // Ein unbekannter Name wurde bisher stumm zum bisherigen Zustand.
      // Der Aufrufer sah eine 200 und glaubte, der Wechsel sei passiert.
      final target = TaskState.values.where((s) => s.name == state).firstOrNull;
      if (target == null) {
        throw _Invalid('Unbekannter Zustand: $state. Möglich sind '
            '${TaskState.values.map((s) => s.name).join(", ")}');
      }
      switch (target) {
        case TaskState.done:
          await runtime.completeTask(task);
        case TaskState.dropped:
          await runtime.dropTask(task);
        case TaskState.active:
          await runtime.startTask(task);
        case TaskState.ready:
          // Zurück in den Bestand — über die Laufzeit, damit auch dieser
          // Weg ein Ereignis hinterlässt und ein daran hängendes
          // Fokusfenster mitgeschlossen wird.
          await runtime.releaseTask(task);
        case TaskState.inbox || TaskState.blocked:
          // Für diese beiden gibt es keinen Laufzeitweg. Sie sind
          // Ablagezustände ohne Folgewirkung.
          await runtime.store.upsertTask(task.copyWith(state: target));
      }
    }

    final updated = (await runtime.store.tasks()).firstWhere((t) => t.id == id);
    await runtime.store.upsertTask(updated.copyWith(
      // Ein leerer Titel wäre kein „unverändert", sondern eine Aufgabe
      // ohne Namen — `copyWith` unterscheidet nur gegen null.
      title: _text(body, 'title', max: 500),
      // Hier stand `_int` ohne Bereichsgrenze. Die Domänentypen sichern
      // 1..10 per `assert`, und `assert` ist im Release-Build aus: Eine
      // Aktivierungsenergie von 999 lief bis in die Datenbank durch und
      // verzerrte jeden Auswahl-Score, ohne dass irgendwo ein Fehler stand.
      activationEnergy: body.containsKey('activationEnergy')
          ? _clamp(body['activationEnergy'], 1, 10, updated.activationEnergy)
          : null,
      salience: body.containsKey('salience')
          ? _clamp(body['salience'], 1, 10, updated.salience)
          : null,
      stakes: body.containsKey('stakes')
          ? _clamp(body['stakes'], 1, 10, updated.stakes)
          : null,
      decayAt: _date(body, 'decayAt'),
    ));
    onChanged();

    final after = await runtime.store.tasks();
    final result = after.firstWhere((t) => t.id == id);
    return _json(request, 200, _task(result, _childCounts(after)));
  }

  Future<void> _putRule(
    HttpRequest request,
    AxiomRuntime runtime,
    String id,
  ) async {
    final body = await _body(request);
    final yaml = _requiredText(body, 'yaml', max: 20000);

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
    // Dieselbe Prüfung wie in der Vorschau. Was dort ohne Fehler dasteht,
    // muss hier durchgehen — und was dort einen Fehler nennt, darf hier
    // nicht gespeichert werden. Zwei verschiedene Urteile über dieselbe
    // Regel wären schlimmer als gar keine Vorschau.
    final checked = _check(rule);
    if (checked.errors.isNotEmpty) {
      return _json(request, 400, {
        'error': 'Regel ungültig',
        'issues': checked.errors,
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

  // ── Wortschatz ────────────────────────────────────────────────────────

  /// Alles, was in einer Regel vorkommen darf — abgeleitet, nicht getippt.
  ///
  /// Jeder Eintrag hier stammt aus [RuleVocabulary]. Eine zweite Liste im
  /// Server würde beim nächsten Zusatz im Kern auseinanderlaufen, und der
  /// Editor böte dann entweder etwas an, das die Engine nicht kennt, oder
  /// verschwiege etwas, das sie kann. Beides fällt erst auf, wenn eine
  /// Regel nicht lädt.
  static Map<String, Object?> _vocabulary() => {
        'numerics': [
          for (final v in RuleVocabulary.numerics)
            {
              'id': v.id,
              'label': v.label,
              'meaning': v.meaning,
              'highIsTense': v.highIsTense,
              // Der Regler im Browser braucht die Grenzen. Ohne sie rät er
              // 0..100 und liegt bei jeder anderen Skala daneben.
              'min': v.min,
              'max': v.max,
            },
        ],
        'symbolics': [
          for (final v in RuleVocabulary.symbolics)
            {
              'id': v.id,
              'label': v.label,
              'meaning': v.meaning,
              'values': v.values,
            },
        ],
        'events': [
          for (final e in RuleVocabulary.events)
            {
              'id': e.id,
              'label': e.label,
              // Der Wortschatz führt zu Ereignissen keinen eigenen
              // Erklärtext. Der eine Satz, der hier zählt, gilt für alle
              // gleich und steht in der DSL-Dokumentation.
              'meaning': 'Zählt für „seit einem Ereignis" und „Anzahl heute".',
            },
        ],
        'actions': [
          for (final a in RuleVocabulary.actions)
            {
              // Der Token, nicht der Dart-Name: So steht die Aktion im YAML,
              // und nur so lässt sich das, was der Editor auswählt, wieder
              // einlesen.
              'type': a.type.token,
              'label': a.label,
              'meaning': a.meaning,
              'params': a.params,
            },
        ],
        'severities': [
          for (final spec in RuleVocabulary.severities)
            {
              'id': spec.value.name,
              'label': spec.label,
              'meaning': spec.meaning,
            },
        ],
        'deficits': [
          for (final spec in RuleVocabulary.deficits)
            {'id': spec.id, 'label': spec.label},
        ],
        'operators': {
          'numeric': [
            for (final op in RuleVocabulary.operatorLabels.keys) op.token,
          ],
          'symbolic': [
            for (final op in RuleVocabulary.symbolicOperators) op.token,
          ],
        },
        // Die Beschriftungen dazu, damit der Browser „mindestens" nicht
        // selbst erfindet.
        'operatorLabels': {
          for (final entry in RuleVocabulary.operatorLabels.entries)
            entry.key.token: entry.value,
        },
      };



  /// Variablennamen, die die Engine auflösen kann.
  ///
  /// Abgeleitet aus [RuleVocabulary], wie im Regelvalidator. Dort stand
  /// einmal eine handgepflegte Zweitliste — sie driftete ab, und eine
  /// gültige Regel galt als ungültig, mit einer Meldung, die nach einem
  /// Tippfehler aussah statt nach einer Lücke im Werkzeug.
  static final Set<String> _knownVariables = {
    for (final v in RuleVocabulary.numerics) v.id,
    for (final v in RuleVocabulary.symbolics) v.id,
    // Kein Variablenname, sondern ein eigener Knotentyp — der
    // Bedingungsbaum meldet ihn trotzdem als referenziert.
    'time_between',
  };

  // ── Vorschau ──────────────────────────────────────────────────────────

  /// Dieselbe Aussage, die der Editor auf dem Telefon beim Tippen gibt.
  ///
  /// Lädt sie? Was fehlt noch? Träfe sie mit dem Zustand von *jetzt* zu —
  /// und woran scheitert sie sonst? Das ist der Unterschied zwischen einem
  /// Texteingabefeld und einem Werkzeug: Wer nachrechnen kann, muss nicht
  /// glauben (G2).
  ///
  /// Antwortet mit 200, auch wenn die Regel nicht lädt. Die Ungültigkeit
  /// ist hier das Ergebnis, nicht der Fehler — gespeichert wird ohnehin
  /// nichts, das passiert erst beim PUT.
  Future<Map<String, Object?>> _preview(
    AxiomRuntime runtime,
    String yaml,
  ) async {
    final errors = <String>[];
    final warnings = <String>[];

    final parsed = YamlRuleSource({'vorschau': yaml}).parse();
    for (final issue in parsed.issues) {
      errors.add('${issue.ruleId}: ${issue.message}');
    }
    if (parsed.rules.isEmpty && errors.isEmpty) {
      errors.add('Kein Regeleintrag gefunden. Erwartet wird eine Liste mit '
          'genau einer Regel.');
    }
    if (parsed.rules.length > 1) {
      errors.add('Genau eine Regel je Vorschau, gefunden: '
          '${parsed.rules.length}');
    }

    final rule = parsed.rules.length == 1 ? parsed.rules.single : null;
    if (rule != null) {
      final checked = _check(rule);
      errors.addAll(checked.errors);
      warnings.addAll(checked.warnings);
    }

    if (rule == null || errors.isNotEmpty) {
      return {
        'ok': false,
        'errors': errors,
        'warnings': warnings,
        'firesNow': false,
        'failedAt': null,
        'explanation': 'Die Regel lädt so noch nicht: ${errors.first}',
      };
    }

    final ctx = await runtime.currentContext();
    final bool fires;
    final String? failedAt;
    try {
      fires = rule.when.eval(ctx);
      failedAt = fires ? null : _failingPart(rule.when, ctx);
    } on ConditionError catch (e) {
      // Sollte nach der Prüfung oben nicht mehr vorkommen. Falls doch, ist
      // die Meldung der Bedingung selbst die beste, die es gibt.
      return {
        'ok': false,
        'errors': [e.message],
        'warnings': warnings,
        'firesNow': false,
        'failedAt': null,
        'explanation': 'Die Bedingung lässt sich nicht auswerten: ${e.message}',
      };
    }

    final action = RuleVocabulary.action(rule.then.type)?.label ??
        rule.then.type.token;
    return {
      'ok': true,
      'errors': const <String>[],
      'warnings': warnings,
      'firesNow': fires,
      'failedAt': failedAt,
      'explanation': fires
          ? 'Trifft mit dem Zustand von jetzt zu und würde auslösen: $action.'
          : 'Trifft mit dem Zustand von jetzt nicht zu — es fehlt: '
              '${failedAt ?? "unklar"}.',
    };
  }

  /// Was an einer geladenen Regel noch nicht stimmt.
  ///
  /// Getrennt nach Fehler und Hinweis, und die Trennlinie ist immer
  /// dieselbe: Ein **Fehler** heißt, die Regel würde später stumm nicht
  /// funktionieren — eine unbekannte Variable wirft erst in dem Moment, in
  /// dem die Regel hätte feuern sollen. Ein **Hinweis** heißt, sie
  /// funktioniert, ist aber unfertig. Sichtbar unfertig ist besser als
  /// stumm fehlend (CLAUDE.md).
  static ({List<String> errors, List<String> warnings}) _check(Rule rule) {
    final errors = <String>[];
    final warnings = <String>[];

    for (final name in rule.when.referencedVariables) {
      if (name.startsWith('event:')) {
        final event = name.substring('event:'.length);
        if (RuleVocabulary.event(event) == null) {
          warnings.add('Das Ereignis „$event" steht nicht im Wortschatz. '
              'Gibt es den Typ nicht, wird es nie gezählt.');
        }
        continue;
      }
      if (!_knownVariables.contains(name)) {
        errors.add('Unbekannte Variable: $name');
      }
    }

    // Ohne Abstand entsteht Benachrichtigungsflut — der häufigste Grund,
    // warum solche Apps wieder gelöscht werden (R2). Der Editor auf dem
    // Telefon lässt sie deshalb ebenfalls nicht speichern.
    if (rule.cooldown.minInterval.inMinutes < 1) {
      errors.add('Ohne Mindestabstand meldet sich die Regel beliebig oft.');
    }
    if (rule.rationale.trim().length < 40) {
      warnings.add('Die Begründung ist kurz. Sie erscheint im '
          'Systeminspektor und muss in einem halben Jahr noch erklären, '
          'warum es diese Regel gibt.');
    }
    if (rule.deficit == null) {
      warnings.add('Kein Bezug auf D1 bis D12. Eine Regel ohne '
          'Defizitbezug ist verdächtig.');
    } else if (!RuleVocabulary.deficits.any((d) => d.id == rule.deficit)) {
      errors.add('Unbekanntes Defizit: ${rule.deficit}');
    }
    if (!rule.translatedLanguages.contains('en')) {
      warnings.add('Keine englische Fassung (title_en, rationale_en). In '
          'der englischen Oberfläche erscheint der deutsche Text.');
    }
    if (rule.severity == Severity.enforce) {
      warnings.add(RuleVocabulary.severities
          .firstWhere((s) => s.value == Severity.enforce)
          .meaning);
    }
    if (!rule.isShadow) {
      warnings.add('Gespeichert läuft die Regel zuerst sieben Tage stumm '
          'mit, unabhängig von der gewählten Aktion.');
    }
    return (errors: errors, warnings: warnings);
  }

  /// Der Teil der Bedingung, an dem es gerade scheitert.
  ///
  /// Bei `all` der erste Zweig, der nicht hält — er ist der, den man ändern
  /// müsste. Bei `any` hält keiner, also werden alle genannt: Einer allein
  /// wäre eine willkürliche Auswahl.
  static String? _failingPart(Condition condition, EvalContext ctx) {
    if (condition.eval(ctx)) return null;
    if (condition is AllOf) {
      for (final child in condition.children) {
        final failing = _failingPart(child, ctx);
        if (failing != null) return failing;
      }
    }
    if (condition is AnyOf) {
      return 'keins davon: '
          '${condition.children.map((c) => _describe(c, ctx)).join(" / ")}';
    }
    return _describe(condition, ctx);
  }

  /// Eine Bedingung mit ihrem Istwert daneben — in Worten des Wortschatzes.
  ///
  /// „capacity lt 40" sagt nichts, „Kapazität kleiner als 40 (jetzt 62)"
  /// sagt alles. Die Beschriftungen kommen aus [RuleVocabulary], damit im
  /// Browser dasselbe steht wie im Editor auf dem Telefon.
  static String _describe(Condition condition, EvalContext ctx) {
    String label(CompareOp o) => RuleVocabulary.operatorLabels[o] ?? o.token;

    switch (condition) {
      case NumericCompare(:final variable, :final op, :final value):
        return '${RuleVocabulary.labelFor(variable)} ${label(op)} $value '
            '(jetzt ${ctx.numeric(variable) ?? "unbekannt"})';
      case SymbolicCompare(:final variable, :final op, :final value):
        final now = ctx.symbolic(variable);
        return '${RuleVocabulary.labelFor(variable)} '
            '${op == CompareOp.eq ? "ist" : "ist nicht"} '
            '${_symbolLabel(variable, value)} '
            '(jetzt ${now == null ? "unbekannt" : _symbolLabel(variable, now)})';
      case TimeBetween(:final fromMinutes, :final toMinutes):
        final now = ctx.localNow;
        return 'Uhrzeit zwischen ${_hhmm(fromMinutes)} und '
            '${_hhmm(toMinutes)} (jetzt ${_hhmm(now.hour * 60 + now.minute)})';
      case MinutesSince(:final eventType, :final op, :final minutes):
        final since = ctx.minutesSince(eventType);
        return 'Minuten seit „${RuleVocabulary.labelFor(eventType)}" '
            '${label(op)} $minutes (jetzt ${since ?? "noch nie"})';
      case CountToday(:final eventType, :final op, :final count):
        return '„${RuleVocabulary.labelFor(eventType)}" heute ${label(op)} '
            '$count (jetzt ${ctx.countToday(eventType)})';
      case NotCond(:final child):
        return 'nicht (${_describe(child, ctx)})';
      case AllOf(:final children):
        return children.map((c) => _describe(c, ctx)).join(' und ');
      case AnyOf(:final children):
        return children.map((c) => _describe(c, ctx)).join(' oder ');
    }
  }

  /// Beschriftung eines symbolischen Werts, sonst der Wert selbst.
  static String _symbolLabel(String variable, String value) {
    final symbolic = RuleVocabulary.symbolic(variable);
    if (symbolic == null) return value;
    // Der EvalContext liefert die Laststufe in Grossbuchstaben, der
    // Wortschatz fuehrt sie so, wie sie im YAML steht.
    for (final entry in symbolic.values.entries) {
      if (entry.key.toLowerCase() == value.toLowerCase()) return entry.value;
    }
    return value;
  }

  static String _hhmm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  // ── Abbildung nach JSON ───────────────────────────────────────────────

  Future<Map<String, Object?>> _state(AxiomRuntime runtime) async {
    final snapshot = await runtime.evaluate();
    final state = snapshot.state;
    final counts = _childCounts(snapshot.tasks);
    // Die Werte kommen aus dem Auswertungskontext, nicht aus dem
    // Zustandsvektor allein: `meta_minutes_today` gehoert zum
    // RuntimeContext (G4) und steht nicht im Vektor. Ueber `state.numeric`
    // kam dafuer `null` heraus — eine Zahl ohne Zahl, die die Oberflaeche
    // trotzdem rendert. Der Kontext kennt beide Quellen, und was er nicht
    // aufloesen kann, faellt hier ganz heraus: Ein fehlender Eintrag ist
    // ehrlicher als ein leerer.
    final ctx = await runtime.currentContext();
    return {
      'at': snapshot.at.toIso8601String(),
      'values': {
        for (final variable in RuleVocabulary.numerics)
          if (ctx.numeric(variable.id) != null)
            variable.id: {
              'label': variable.label,
              'value': ctx.numeric(variable.id),
              'confidence': ctx.confidenceOf(variable.id),
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
      'running': [
        for (final task in snapshot.tasks)
          if (task.state == TaskState.active) _task(task, counts),
      ],
      'startable': [
        for (final task in snapshot.startable) _task(task, counts),
      ],
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

  // ── Nutzerdokumentation ───────────────────────────────────────────────

  /// Die angefragte Sprache, oder ein Fehler.
  ///
  /// Kein stilles Zurückfallen auf Deutsch bei `lang=fr`: Der Aufrufer
  /// bekäme sonst eine Antwort, die aussieht wie die gewünschte, und merkte
  /// den Tippfehler nie.
  static String _helpLang(HttpRequest request) {
    final lang = request.uri.queryParameters['lang'] ?? 'de';
    if (!_helpDirs.containsKey(lang)) {
      throw _Invalid('Diese Sprache gibt es nicht. Erlaubt sind '
          '${_helpDirs.keys.join(", ")}.');
    }
    return lang;
  }

  /// Ein Kapitel im Klartext, oder null, wenn es das nicht gibt.
  ///
  /// Fehlt die englische Fassung, kommt die deutsche mit gesetztem
  /// `fallback` — sichtbar unfertig ist besser als stumm fehlend, und ein
  /// leeres Kapitel wäre beides zugleich.
  ///
  /// Der Pfad entsteht aus zwei `const`-Listen, nicht aus der Anfrage:
  /// [_helpDirs] steuert das Verzeichnis, [_helpChapters] die Datei.
  static Future<({String markdown, bool fallback})?> _helpSource(
    String id,
    String lang,
  ) async {
    final file = _helpChapters[id];
    if (file == null) return null;
    for (final (candidate, fallback) in [
      (lang, false),
      if (lang != 'de') ('de', true),
    ]) {
      try {
        final text = await rootBundle.loadString('${_helpDirs[candidate]!}$file.md');
        return (markdown: text, fallback: fallback);
      } on Object {
        // Nicht im Bündel. Die nächste Sprache versuchen; bleibt auch die
        // leer, entscheidet der Aufrufer, was er meldet.
      }
    }
    return null;
  }

  /// Die Kapitelliste, wie `00-index.md` sie ordnet.
  ///
  /// Die Reihenfolge steht in der Doku, nicht hier: Wer ein Kapitel
  /// verschiebt, verschiebt es an einer Stelle. Nennt der Index nichts
  /// Lesbares — weil er fehlt oder anders geschrieben ist —, wird
  /// stattdessen jedes vorhandene Kapitel aufgeführt. Eine leere Hilfe wäre
  /// die schlechteste Antwort: Die Kapitel sind da, nur ihre Ordnung nicht.
  static Future<Map<String, Object?>> _helpIndex(String lang) async {
    final chapters = <Map<String, Object?>>[];
    final seen = <String>{};
    var fallback = false;

    final index = await _helpSource('00', lang);
    if (index != null) {
      fallback = index.fallback;
      for (final match in _helpLinkPattern.allMatches(index.markdown)) {
        final id = match.group(2)!;
        // Der Index selbst ist kein Kapitel — er ist die Liste.
        if (id == '00' || !_helpChapters.containsKey(id)) continue;
        if (!seen.add(id)) continue;
        chapters.add({'id': id, 'title': match.group(1)!.trim()});
      }
    }

    if (chapters.isEmpty) {
      for (final id in _helpChapters.keys) {
        if (id == '00') continue;
        final source = await _helpSource(id, lang);
        if (source == null) continue;
        if (source.fallback) fallback = true;
        chapters.add({'id': id, 'title': _helpTitle(source.markdown, id)});
      }
    }
    return {'chapters': chapters, 'fallback': fallback};
  }

  /// Ein Verweis auf ein Kapitel: `[Titel](kapitel:06)` oder
  /// `[Titel](06-aufgaben.md)`. Beides kommt in Handschriften vor, und der
  /// Index ist Text, kein Datenformat.
  static final RegExp _helpLinkPattern =
      RegExp(r'\[([^\]\n]+)\]\(\s*(?:kapitel:)?(\d{2})[^)]*\)');

  Future<void> _helpChapter(
    HttpRequest request,
    String id,
    String lang,
  ) async {
    // Die Nummer aus der Anfrage wird nachgeschlagen, nie eingesetzt. Was
    // nicht in der Liste steht, ist unbekannt — „../" ebenso wie „99".
    if (!_helpChapters.containsKey(id) || id == '00') {
      return _json(request, 404, {
        'error': 'Dieses Kapitel gibt es nicht. Vorhanden sind: '
            '${_helpChapters.keys.where((k) => k != '00').join(", ")}.',
      });
    }
    final source = await _helpSource(id, lang);
    if (source == null) {
      return _json(request, 404, {
        'error': 'Dieses Kapitel liegt nicht im App-Bündel. Die Hilfe wird '
            'aus assets/help/ ausgeliefert; fehlt der Eintrag in '
            'pubspec.yaml, ist der Text geschrieben, aber nicht dabei.',
      });
    }
    return _json(request, 200, {
      'id': id,
      'title': _helpTitle(source.markdown, id),
      'markdown': source.markdown,
      'fallback': source.fallback,
    });
  }

  Future<void> _helpImage(HttpRequest request, String path) async {
    final asset = _helpImages[path];
    if (asset == null) {
      return _json(request, 404, {'error': 'Dieses Bild gibt es nicht.'});
    }
    final List<int> bytes;
    try {
      bytes = (await rootBundle.load(asset)).buffer.asUint8List();
    } on Object {
      return _json(request, 404, {
        'error': 'Dieses Bild liegt nicht im App-Bündel.',
      });
    }
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType('image', 'webp')
      // `private`, nicht `public`: Die Antwort hängt an einer Sitzung, und
      // ein Zwischenspeicher, der sie weitergibt, wäre einer zu viel.
      ..headers.set('Cache-Control', 'private, max-age=604800')
      ..headers.set('X-Content-Type-Options', 'nosniff')
      ..add(bytes);
    await request.response.close();
  }

  /// Die Überschrift eines Kapitels — aus dem Text, nicht aus einer zweiten
  /// Liste. Eine gepflegte Titelliste im Server driftete von der Doku ab,
  /// und dann hieße dasselbe Kapitel an zwei Stellen verschieden.
  static String _helpTitle(String markdown, String id) {
    for (final line in const LineSplitter().convert(markdown)) {
      final text = line.trim();
      if (text.startsWith('# ')) return text.substring(2).trim();
    }
    // Ohne Überschrift der Dateiname: lesbar genug, um das Kapitel zu
    // finden, und sichtbar unfertig.
    return (_helpChapters[id] ?? id)
        .replaceFirst(RegExp(r'^\d+-'), '')
        .replaceAll('-', ' ');
  }

  /// Teilschritte je Elternaufgabe.
  ///
  /// Der Browser soll den Fortschritt einer zerlegten Aufgabe zeigen
  /// können, ohne die Liste selbst zu durchsuchen — zweimal dieselbe
  /// Zählung ist zweimal die Gelegenheit, sie unterschiedlich zu machen.
  static Map<String, ({int total, int done})> _childCounts(List<Task> tasks) {
    final counts = <String, ({int total, int done})>{};
    for (final task in tasks) {
      final parent = task.parentId;
      if (parent == null) continue;
      final current = counts[parent] ?? (total: 0, done: 0);
      counts[parent] = (
        total: current.total + 1,
        done: current.done + (task.state == TaskState.done ? 1 : 0),
      );
    }
    return counts;
  }

  /// [counts] aus [_childCounts]. Fehlt es, sind die Zahlen 0 — nie `null`:
  /// Ein Feld, das mal da ist und mal nicht, muss im Browser jedes Mal
  /// geprüft werden.
  Map<String, Object?> _task(
    Task task, [
    Map<String, ({int total, int done})> counts = const {},
  ]) =>
      {
        'id': task.id,
        'title': task.title,
        'activationEnergy': task.activationEnergy,
        'salience': task.salience,
        'stakes': task.stakes,
        'state': task.state.name,
        'decayAt': task.decayAt?.toIso8601String(),
        'parentId': task.parentId,
        'breadcrumb': task.breadcrumb,
        // Nur lesend: Der Ort wird am Geraet gesetzt, wo man auch tatsaechlich
        // ist. Ein Ortsschalter am Rechner waere eine Angabe ins Blaue.
        'place': task.place,
        'childCount': counts[task.id]?.total ?? 0,
        'doneCount': counts[task.id]?.done ?? 0,
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

  /// Pflichttext aus dem Rumpf.
  ///
  /// Fehlt er, ist er leer oder ist er gar kein Text, wird die Anfrage
  /// abgelehnt. Der Grund steht dabei: Eine Aufgabe ohne Titel steht in
  /// jeder Liste und ist in keiner wiederzuerkennen, und ein stumm auf
  /// „" gesetzter Titel löscht den vorhandenen.
  static String _requiredText(
    Map<String, Object?> body,
    String field, {
    required int max,
  }) {
    final value = body[field];
    if (value is! String) {
      throw _Invalid('Feld "$field" fehlt oder ist kein Text');
    }
    final text = value.trim();
    if (text.isEmpty) throw _Invalid('Feld "$field" ist leer');
    if (text.length > max) {
      throw _Invalid('Feld "$field" ist zu lang: ${text.length} Zeichen, '
          'erlaubt sind $max');
    }
    return text;
  }

  /// Wie [_requiredText], nur darf das Feld fehlen. Steht es da, gelten
  /// dieselben Bedingungen — „vorhanden, aber leer" ist keine Auslassung,
  /// sondern eine Eingabe, und eine ungültige.
  static String? _text(
    Map<String, Object?> body,
    String field, {
    required int max,
  }) =>
      body[field] == null ? null : _requiredText(body, field, max: max);

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

  /// Ein Datum aus dem Netz. Fehlt das Feld, bleibt es leer.
  ///
  /// **Warum ein unlesbares Datum abgelehnt wird.** Bisher wurde es still
  /// verworfen. Die Aufgabe stand danach ohne Frist da, der Auswahl-Score
  /// rechnete mit dem halben Druck (`_decayPressure` liefert 0.5 statt bis
  /// zu 2.0) — und nirgends stand ein Fehler. Ein Tippfehler im Datum
  /// verschob damit lautlos die Reihenfolge des ganzen Tages.
  static DateTime? _date(Map<String, Object?> body, String field) {
    final value = body[field];
    if (value == null) return null;
    if (value is! String) {
      throw _Invalid('"$field" erwartet ein Datum als Text');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw _Invalid('"$field" ist kein lesbares Datum: $value');
    }
    return parsed;
  }

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
