/// Brücke zu Android-Systemfunktionen.
///
/// Flutter deckt diese nicht ab — sie laufen über einen Platform Channel
/// gegen nativen Kotlin-Code (android/app/src/main/kotlin/.../MainActivity.kt).
///
/// Auf Linux-Desktop sind alle Aufrufe stille No-ops. Die App bleibt dort
/// vollständig bedienbar: Erfassen, Check-ins, Regelinspektor.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import '../i18n/i18n.dart';

/// Ergebnis eines Systemaufrufs — mit Grund, wenn er scheitert.
///
/// **Warum das ein eigener Typ ist.** Ein `bool` zurueckzugeben heisst, dass
/// jeder Fehlschlag auf dem Geraet als „passiert nichts" ankommt. Genau das
/// war der teuerste Fehler in diesem Projekt: fuenf gemeldete Probleme, vier
/// verschiedene Ursachen, und keine davon von aussen unterscheidbar. Ein
/// unschoener Satz ist besser als ein stummer Knopf.
final class PlatformOutcome {
  final bool ok;
  final String? reason;

  const PlatformOutcome(this.ok, [this.reason]);

  static const unsupported = PlatformOutcome(
    false,
    'Diese Funktion gibt es nur auf Android.',
  );
}

/// Wohin eine Benachrichtigung führt.
///
/// Die Zeichenketten sind Intent-Actions und stehen genauso in
/// `MainActivity.consumeLaunchAction`. Sie hier zu benennen ist der Punkt:
/// Ein Tippfehler in einem freien String hätte zur Folge, dass die
/// Benachrichtigung stumm auf der Übersicht landet — funktionierend genug,
/// um nicht aufzufallen.
abstract final class AxiomRoute {
  static const capture = 'de.axiom.CAPTURE';
  static const checkin = 'de.axiom.CHECKIN';
  static const focus = 'de.axiom.FOCUS';
  static const sensation = 'de.axiom.SENSATION';
  static const anchors = 'de.axiom.ANCHORS';
  static const review = 'de.axiom.REVIEW';
  static const body = 'de.axiom.BODY';
  static const inbox = 'de.axiom.INBOX';
}

abstract final class AndroidBridge {
  static const _channel = MethodChannel('de.axiom/system');

  /// Wie lange auf eine Antwort der Systemseite gewartet wird.
  ///
  /// **Warum es die überhaupt gibt.** Ein Aufruf über den MethodChannel
  /// landet auf dem Android-Hauptthread. Blockiert der — etwa weil eine
  /// Systemschnittstelle auf eine Binder-Verbindung wartet, die nicht kommt
  /// — dann bleibt auf der Dart-Seite ein Future offen, das nie fertig wird.
  /// Genau so ist die App einmal auf einem Ladekreisel stehengeblieben, ohne
  /// dass irgendwo ein Fehler stand. Lieber eine Funktion, die nach fünf
  /// Sekunden „geht nicht" sagt, als eine App, die wartet.
  static const Duration _timeout = Duration(seconds: 5);

  /// Health Connect liest über eine Prozessgrenze und darf länger brauchen.
  static const Duration _healthTimeout = Duration(seconds: 20);

  /// Ob die Systembruecke auf diesem Geraet ueberhaupt etwas tun kann.
  ///
  /// `kIsWeb` kommt aus Flutter, nicht aus einer eigenen Konstante. Die
  /// selbstgebaute Fassung (`bool.fromEnvironment('dart.library.js_util')`)
  /// war eine stille Wette darauf, wie der Compiler diese Kennung fuer
  /// Android beantwortet — und faellt sie falsch aus, ist *jede*
  /// Systemfunktion tot, ohne dass irgendwo ein Fehler erscheint.
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  // ── Berechtigungen ────────────────────────────────────────────────────

  /// Ab Android 14 erforderlich für minutengenaue Erinnerungen.
  /// Ohne sie ist der wirksamste Interventionstyp dieses Profils wertlos [D4].
  static Future<bool> requestExactAlarm() => _invoke('requestExactAlarm');

  static Future<bool> requestNotifications() => _invoke('requestNotifications');

  /// Samsung schläfert Apps aggressiv ein. Ohne Ausnahme feuern Alarme
  /// unzuverlässig — Risiko R4.
  static Future<bool> requestIgnoreBatteryOptimizations() =>
      _invoke('requestIgnoreBatteryOptimizations');

  static Future<Map<String, bool>> permissionStatus() async {
    if (!isSupported) return const {};
    try {
      final result = await _channel
          .invokeMapMethod<String, bool>('permissionStatus')
          .timeout(_timeout);
      return result ?? const {};
    } on Object {
      return const {};
    }
  }

  // ── Exakte Alarme ─────────────────────────────────────────────────────

  /// Plant eine minutengenaue Erinnerung.
  /// Nutzt `setExactAndAllowWhileIdle`, nicht WorkManager — WorkManager
  /// bündelt Aufwachvorgänge und ist für Zeitanker unbrauchbar.
  static Future<bool> scheduleExact({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    String channel = 'axiom_nudge',
    String? route,
  }) async {
    if (!isSupported) return false;
    return _invoke('scheduleExact', {
      'id': id,
      'atMillis': at.millisecondsSinceEpoch,
      'title': title,
      'body': body,
      'channel': channel,
      // Wohin der Tipp führt. Ohne das endet jeder Anstoß auf der
      // Übersicht, und der Weg zur Handlung beginnt von vorn [D2].
      'route': ?route,
    });
  }

  static Future<bool> cancelAlarm(int id) => _invoke('cancelAlarm', {'id': id});

  /// Plant die drei täglichen Check-ins.
  /// Zeitgetriggerte Prompts haben bei diesem Profil die höchste
  /// Befolgungsrate — Pünktlichkeit gilt auch gegenüber der App [D4].
  static Future<void> scheduleDailyCheckins({
    AppLanguage language = AppLanguage.de,
  }) async {
    if (!isSupported) return;
    const slots = [(1, 9, 0), (2, 14, 0), (3, 21, 0)];
    final now = DateTime.now();
    for (final (id, hour, minute) in slots) {
      var at = DateTime(now.year, now.month, now.day, hour, minute);
      if (at.isBefore(now)) at = at.add(const Duration(days: 1));
      await scheduleExact(
        id: id,
        at: at,
        title: translate(language, 'Check-in'),
        body: translate(language, 'Vier Regler, ungefähr reicht.'),
        channel: 'axiom_nudge',
        route: AxiomRoute.checkin,
      );
    }
  }

  /// Selbsttest: Feuern die eigenen Alarme pünktlich?
  /// Ein stiller Ausfall wäre schlimmer als ein lauter — deshalb wird die
  /// tatsächliche Feuerzeit protokolliert und Drift sichtbar gemeldet (R4).
  static Future<Duration?> lastAlarmDrift() async {
    if (!isSupported) return null;
    try {
      final ms = await _channel
          .invokeMethod<int>('lastAlarmDriftMillis')
          .timeout(_timeout);
      return ms == null ? null : Duration(milliseconds: ms);
    } on Object {
      return null;
    }
  }

  // ── Widget & Quick Tile ───────────────────────────────────────────────

  /// Aktualisiert Homescreen-Widget und Always-On-Anzeige.
  /// Objektpermanenz: Was nicht sichtbar ist, existiert für dieses Profil
  /// nicht [D9].
  static Future<void> updateWidget({
    required String headline,
    required String detail,
    required int capacity,
  }) async {
    if (!isSupported) return;
    await _invoke('updateWidget', {
      'headline': headline,
      'detail': detail,
      'capacity': capacity,
    });
  }

  // ── Dauerhafte Anzeige ────────────────────────────────────────────────

  /// Schaltet die Präsenz im Benachrichtigungsbereich ein.
  ///
  /// Sie erscheint auch auf dem Sperrbildschirm und nimmt getippten Text
  /// direkt entgegen — ohne Entsperren, ohne App-Start. Lockscreen-Widgets
  /// gibt es auf Android seit 5.0 nicht mehr; das hier ist der verbliebene
  /// Weg zu ständiger Sichtbarkeit [D9].
  static Future<PlatformOutcome> startPresence({
    required String headline,
    required String detail,
  }) => _outcome('presenceStart', {'headline': headline, 'detail': detail});

  static Future<bool> updatePresence({
    required String headline,
    required String detail,
  }) => _invoke('presenceUpdate', {'headline': headline, 'detail': detail});

  static Future<bool> stopPresence() => _invoke('presenceStop');

  /// Was gewollt ist — der gespeicherte Schalter.
  static Future<bool> presenceEnabled() => _invoke('presenceEnabled');

  /// Was tatsächlich hängt — die Benachrichtigung selbst.
  ///
  /// Die beiden auseinanderzuhalten ist der Unterschied zwischen „der
  /// Schalter springt zurück" und einem Satz, der sagt, warum.
  static Future<bool> presenceActive() => _invoke('presenceActive');

  /// Hält die Multicast-Sperre, solange der Expertenmodus läuft.
  ///
  /// Ohne sie verwirft Androids WLAN-Treiber eingehende Multicast-Pakete,
  /// und der mDNS-Responder hört keine einzige Frage — ohne Fehler, ohne
  /// Log, einfach still.
  static Future<bool> multicastLock({required bool hold}) =>
      _invoke('multicastLock', {'hold': hold});

  /// Öffnet die Einstellungen genau dieses Kanals, nicht die App-Übersicht.
  static Future<bool> openPresenceChannel() => _invoke('openPresenceChannel');

  /// Jeder Schritt einzeln, so wie das System ihn meldet.
  ///
  /// Es gibt fünf Gründe, aus denen die Anzeige aus bleibt, und vier davon
  /// kann nur Android beantworten. Sie alle zu zeigen ist billiger, als sie
  /// aus der Ferne zu raten.
  static Future<Map<String, Object?>> presenceDiagnosis() async {
    if (!isSupported) return const {};
    try {
      final result = await _channel
          .invokeMapMethod<String, Object?>('presenceDiagnosis')
          .timeout(_timeout);
      return result ?? const {};
    } on Object {
      return const {};
    }
  }

  // ── Laufender Slot (Live Update) ──────────────────────────────────────

  /// Zeigt den laufenden Slot in der Statusleisten-Pille, auf dem
  /// Sperrbildschirm und in Samsungs Now Bar.
  ///
  /// Der teuerste Fehlermodus im Fokus ist der fehlende Ausstieg [D6]: Die
  /// Sitzung läuft weiter, das Zeitgefühl fehlt [D4]. Eine Anzeige, die man
  /// erst öffnen muss, kommt dafür zu spät.
  static Future<bool> startLiveSlot({
    required String kind,
    required String title,
    required String detail,
    required DateTime startedAt,
    required Duration planned,
  }) => _invoke('liveSlotStart', {
    'kind': kind,
    'title': title,
    'detail': detail,
    'startedAtMillis': startedAt.millisecondsSinceEpoch,
    'plannedMinutes': planned.inMinutes,
  });

  static Future<bool> stopLiveSlot() => _invoke('liveSlotStop');

  static Future<bool> liveSlotRunning() => _invoke('liveSlotRunning');

  /// Ob das Gerät Live Updates befördert (Android 16+). Darunter bleibt es
  /// eine gewöhnliche laufende Benachrichtigung — die Oberfläche soll keine
  /// Pille versprechen, die nie erscheint.
  static Future<bool> liveSlotPromotable() => _invoke('liveSlotPromotable');

  // ── Health Connect ────────────────────────────────────────────────────

  /// Verfügbarkeit und Freigabe. Wird vor jeder Nutzung neu geprüft:
  /// Berechtigungen können jederzeit einzeln entzogen werden (R8).
  static Future<Map<String, bool>> healthStatus() async {
    if (!isSupported) return const {};
    try {
      final result = await _channel
          .invokeMapMethod<String, bool>('healthStatus')
          .timeout(_healthTimeout);
      return result ?? const {};
    } on Object {
      return const {};
    }
  }

  static Future<PlatformOutcome> healthRequestPermissions() =>
      _outcome('healthRequestPermissions');

  /// Antwortet der Kanal ueberhaupt?
  ///
  /// Erste Zeile im Systemcheck. Schlaegt das fehl, ist jede weitere Zeile
  /// dort bedeutungslos — und man sucht sonst tagelang an der falschen
  /// Stelle.
  static Future<bool> ping() => _invoke('ping');

  static Future<bool> healthOpenSettings() => _invoke('healthOpenSettings');

  /// Rohe Aufzeichnungen ab [since]. Die Umrechnung in Events macht
  /// [HealthSync] — hier passiert nichts Fachliches.
  static Future<List<Map<String, Object?>>> healthRead(DateTime since) async {
    if (!isSupported) return const [];
    try {
      final result = await _channel
          .invokeListMethod<Map<Object?, Object?>>('healthRead', {
            'sinceMillis': since.millisecondsSinceEpoch,
          })
          .timeout(_healthTimeout);
      return (result ?? const [])
          .map((row) => row.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    } on Object {
      return const [];
    }
  }

  // ── Widget ────────────────────────────────────────────────────────────

  /// Bittet das System, das Widget zu platzieren.
  ///
  /// Der Umweg ueber die Widget-Auswahl des Launchers ist unzuverlaessig:
  /// Samsungs Startbildschirm merkt sich die Widget-Liste einer App und
  /// aktualisiert sie nach einem Update nicht immer. Wer dort nichts findet
  /// oder ein „konnte nicht hinzugefuegt werden" bekommt, kommt hierueber
  /// trotzdem ans Ziel.
  static Future<PlatformOutcome> requestPinWidget() =>
      _outcome('requestPinWidget');

  /// Wie viele Widget-Instanzen tatsaechlich auf dem Startbildschirm liegen.
  static Future<int> widgetCount() async {
    if (!isSupported) return 0;
    try {
      return await _channel
              .invokeMethod<int>('widgetCount')
              .timeout(_timeout) ??
          0;
    } on Object {
      return 0;
    }
  }

  // ── Notiz-Rolle (S-Pen) ───────────────────────────────────────────────

  /// Fragt die Rolle „Notiz-App" an.
  ///
  /// Ohne diese Rolle taucht AXIOM beim Stift-Doppeltipp nicht auf. Der
  /// Intent-Filter allein reicht nicht — das System fragt die Rolle ab,
  /// nicht den Filter.
  static Future<PlatformOutcome> requestNotesRole() =>
      _outcome('requestNotesRole');

  // ── Diagnose ──────────────────────────────────────────────────────────

  /// Rohwerte, so wie das Geraet sie meldet.
  ///
  /// Existiert, weil „geht nicht" keine Fehlermeldung ist. Jede Zeile hier
  /// ist eine Aussage des Systems, nicht eine Vermutung der App.
  static Future<Map<String, Object?>> diagnostics() async {
    if (!isSupported) return const {};
    try {
      final result = await _channel
          .invokeMapMethod<String, Object?>('diagnostics')
          .timeout(_healthTimeout);
      return result ?? const {};
    } on TimeoutException {
      return const {'error': 'Das System hat nicht geantwortet.'};
    } on Object catch (e) {
      return {'error': '$e'};
    }
  }

  // ── Spracheingabe ─────────────────────────────────────────────────────

  /// Oeffnet die Spracherkennung des Systems und gibt den Text zurueck.
  ///
  /// Bewusst ueber den System-Recognizer statt ueber eine Bibliothek: Die
  /// App braucht so weder eine eigene Netzwerkberechtigung noch ein
  /// Mikrofonrecht — beides liegt bei der Erkennungs-App. Ist offline ein
  /// Sprachpaket installiert, funktioniert es auch ohne Netz.
  static Future<String?> listen({String? locale}) async {
    if (!isSupported) return null;
    try {
      // Grosszuegig: Hier spricht ein Mensch. Aber nicht unbegrenzt — sonst
      // bleibt das Mikrofon im Erfassungsfeld dauerhaft auf „hoert zu",
      // wenn die Erkennung haengt.
      return await _channel
          .invokeMethod<String>('listen', {'locale': ?locale})
          .timeout(const Duration(minutes: 3));
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<bool> speechAvailable() => _invoke('speechAvailable');

  // ── Expertenmodus ─────────────────────────────────────────────────────

  /// Zeigt an, dass der lokale Server läuft.
  ///
  /// Zwei Zwecke, beide notwendig. Erstens hält der Vordergrunddienst den
  /// Prozess am Leben, während man am Rechner arbeitet — sonst räumt Android
  /// die App ab und der Server verschwindet mitten im Tippen. Zweitens ist
  /// ein offener Port etwas, das man sehen muss: Eine Benachrichtigung, die
  /// sich nicht wegwischen lässt, ist hier kein Ärgernis, sondern die
  /// ehrliche Anzeige eines Zustands.
  static Future<bool> startExpertNotice({required String address}) =>
      _invoke('expertNoticeStart', {'address': address});

  static Future<bool> stopExpertNotice() => _invoke('expertNoticeStop');

  // ── Automation ────────────────────────────────────────────────────────

  /// Sendet einen Broadcast, den Samsung „Modi und Routinen" aufgreifen kann.
  /// Bewusst über Routinen statt über direkte APIs: Der Nutzer sieht und
  /// ändert die Automation selbst, ohne die App anzufassen (G2).
  static Future<void> broadcast(String action) =>
      _invoke('broadcast', {'action': action});

  static Future<void> focusStart() => broadcast('axiom.FOCUS_START');
  static Future<void> focusEnd() => broadcast('axiom.FOCUS_END');
  static Future<void> windDown() => broadcast('axiom.WINDDOWN');
  static Future<void> enterMaintenanceMode() => broadcast('axiom.L3_ENTER');

  // ── S-Pen / Samsung Notes ─────────────────────────────────────────────

  /// Holt Screen-off-Memos ab, die seit dem letzten Aufruf entstanden sind.
  ///
  /// Der reibungsärmste Erfassungskanal, den das Gerät bietet: Stift ziehen,
  /// schreiben, fertig — ohne Entsperren. Genau das Zeitfenster von wenigen
  /// Sekunden, in dem der Gedanke noch existiert [D9].
  /// Liest die wartenden Notizen, **ohne** sie zu löschen.
  ///
  /// Der Gegenpart ist [ackPendingMemos]. Beides zusammen in einem Aufruf
  /// zu erledigen war der Fehler: Schlägt das Speichern danach fehl — und
  /// dieser Aufruf verschluckt jeden Fehler zu einer leeren Liste —, ist
  /// der erfasste Gedanke weg [D9].
  static Future<List<String>> peekPendingMemos() async {
    if (!isSupported) return const [];
    try {
      final result = await _channel
          .invokeListMethod<String>('peekPendingMemos')
          .timeout(_timeout);
      return result ?? const [];
    } on Object {
      return const [];
    }
  }

  /// Löscht die ersten [count] Notizen — die, die sicher gespeichert sind.
  static Future<bool> ackPendingMemos(int count) =>
      _invoke('ackPendingMemos', {'count': count});

  // ── Ort (D2) ──────────────────────────────────────────────────────────

  /// Ortswechsel, die eine Geräteroutine über `de.axiom.PLACE` geschickt hat.
  ///
  /// Der Empfänger läuft auch, wenn die App nicht läuft; er kann aber nicht
  /// an die verschlüsselte Datenbank. Deshalb dieselbe Ablage wie bei den
  /// Notizen: Er legt ab, die App holt beim nächsten Blick ab — mit dem
  /// Zeitstempel des Empfangs, damit das Ereignis an der richtigen Stelle im
  /// Strom landet.
  ///
  /// Jeder Eintrag: `{'place': String, 'at': int}`. Leerer `place` heißt
  /// „kein Ort mehr gesetzt".
  static Future<List<Map<String, Object?>>> peekPendingPlaces() async {
    if (!isSupported) return const [];
    try {
      final result = await _channel
          .invokeListMethod<Map<Object?, Object?>>('peekPendingPlaces')
          .timeout(_timeout);
      return (result ?? const [])
          .map((row) => row.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    } on Object {
      return const [];
    }
  }

  static Future<bool> ackPendingPlaces(int count) =>
      _invoke('ackPendingPlaces', {'count': count});

  // ── Intern ────────────────────────────────────────────────────────────

  /// Wie [_invoke], aber mit dem Grund des Scheiterns.
  static Future<PlatformOutcome> _outcome(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    if (!isSupported) return PlatformOutcome.unsupported;
    try {
      final result = await _channel
          .invokeMapMethod<String, Object?>(method, args)
          .timeout(_timeout);
      if (result == null) return const PlatformOutcome(false);
      return PlatformOutcome(result['ok'] == true, result['reason'] as String?);
    } on PlatformException catch (e) {
      return PlatformOutcome(false, e.message);
    } on TimeoutException {
      return const PlatformOutcome(
        false,
        'Das System hat nicht geantwortet. Die Funktion bleibt aus, die App '
        'läuft weiter.',
      );
    } on Object {
      return const PlatformOutcome(
        false,
        'Die Systembrücke antwortet nicht. Das ist ein Fehler in AXIOM, '
        'nicht am Gerät.',
      );
    }
  }

  static Future<bool> _invoke(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    if (!isSupported) return false;
    try {
      return await _channel
              .invokeMethod<bool>(method, args)
              .timeout(_timeout) ??
          false;
    } on Object {
      // Ausnahme, Zeitüberschreitung oder fehlender Kanal — für den Aufrufer
      // ist das dasselbe: Es hat nicht geklappt, und die App läuft weiter.
      return false;
    }
  }
}
