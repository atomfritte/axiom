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
/// Kein TLS: Ein selbst signiertes Zertifikat erzeugt eine Browser-Warnung,
/// die man wegklickt, und die Gewöhnung daran ist gefährlicher als der
/// Klartext im eigenen Netz. Die Oberfläche sagt das offen.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:axiom_core/axiom_core.dart';
import 'package:axiom_data/axiom_data.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../state/runtime.dart';

/// Was der Server gerade tut — für die Anzeige in der App.
final class ExpertStatus {
  final bool running;
  final String? address;
  final String? pin;

  /// Wann er sich von selbst abschaltet, wenn nichts passiert.
  final DateTime? idleStopAt;

  const ExpertStatus({
    this.running = false,
    this.address,
    this.pin,
    this.idleStopAt,
  });

  static const off = ExpertStatus();
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
  String? _pin;
  final Set<String> _sessions = {};
  int _failedAttempts = 0;
  Timer? _idleTimer;
  DateTime? _idleStopAt;
  String? _address;

  bool get isRunning => _server != null;

  ExpertStatus get status => isRunning
      ? ExpertStatus(
          running: true,
          address: _address,
          pin: _pin,
          idleStopAt: _idleStopAt,
        )
      : ExpertStatus.off;

  Future<ExpertStatus> start({int port = kExpertPort}) async {
    if (isRunning) return status;

    final random = Random.secure();
    _pin = List.generate(6, (_) => random.nextInt(10)).join();
    _sessions.clear();
    _failedAttempts = 0;

    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    // Den tatsaechlich vergebenen Port nehmen, nicht den gewuenschten: Bei
    // Port 0 waehlt ihn das System, und die angezeigte Adresse zeigte sonst
    // auf einen Port, an dem nichts lauscht.
    _address = 'http://${await _localIp() ?? 'localhost'}:${_server!.port}';
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
            "script-src 'self' 'unsafe-inline'; connect-src 'self'")
        ..headers.set('X-Content-Type-Options', 'nosniff')
        ..headers.set('Referrer-Policy', 'no-referrer')
        ..write(html);
      return;
    }

    if (path == '/api/login' && request.method == 'POST') {
      return _login(request);
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
          activationEnergy: _int(body['activationEnergy'], 5),
          salience: _int(body['salience'], 3),
          stakes: _int(body['stakes'], 3),
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
        'axiom_session=$token; HttpOnly; SameSite=Strict; Path=/',
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
      'decision': snapshot.decisionRule == null
          ? null
          : {
              'ruleId': snapshot.decisionRule!.id,
              'title': snapshot.decisionRule!.title,
            },
      'metaMinutesToday': snapshot.metaUsedToday.inMinutes,
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
