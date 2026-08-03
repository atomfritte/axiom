/// Brücke zu Android-Systemfunktionen.
///
/// Flutter deckt diese nicht ab — sie laufen über einen Platform Channel
/// gegen nativen Kotlin-Code (android/app/src/main/kotlin/.../MainActivity.kt).
///
/// Auf Linux-Desktop sind alle Aufrufe stille No-ops. Die App bleibt dort
/// vollständig bedienbar: Erfassen, Check-ins, Regelinspektor.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import '../i18n/i18n.dart';

abstract final class AndroidBridge {
  static const _channel = MethodChannel('de.axiom/system');

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
      final result =
          await _channel.invokeMapMethod<String, bool>('permissionStatus');
      return result ?? const {};
    } on PlatformException {
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
  }) async {
    if (!isSupported) return false;
    return _invoke('scheduleExact', {
      'id': id,
      'atMillis': at.millisecondsSinceEpoch,
      'title': title,
      'body': body,
      'channel': channel,
    });
  }

  static Future<bool> cancelAlarm(int id) =>
      _invoke('cancelAlarm', {'id': id});

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
      );
    }
  }

  /// Selbsttest: Feuern die eigenen Alarme pünktlich?
  /// Ein stiller Ausfall wäre schlimmer als ein lauter — deshalb wird die
  /// tatsächliche Feuerzeit protokolliert und Drift sichtbar gemeldet (R4).
  static Future<Duration?> lastAlarmDrift() async {
    if (!isSupported) return null;
    try {
      final ms = await _channel.invokeMethod<int>('lastAlarmDriftMillis');
      return ms == null ? null : Duration(milliseconds: ms);
    } on PlatformException {
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
  static Future<bool> startPresence({
    required String headline,
    required String detail,
  }) =>
      _invoke('presenceStart', {'headline': headline, 'detail': detail});

  static Future<bool> updatePresence({
    required String headline,
    required String detail,
  }) =>
      _invoke('presenceUpdate', {'headline': headline, 'detail': detail});

  static Future<bool> stopPresence() => _invoke('presenceStop');

  static Future<bool> presenceEnabled() => _invoke('presenceEnabled');

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
  }) =>
      _invoke('liveSlotStart', {
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
      final result =
          await _channel.invokeMapMethod<String, bool>('healthStatus');
      return result ?? const {};
    } on PlatformException {
      return const {};
    } on MissingPluginException {
      return const {};
    }
  }

  static Future<bool> healthRequestPermissions() =>
      _invoke('healthRequestPermissions');

  static Future<bool> healthOpenSettings() => _invoke('healthOpenSettings');

  /// Rohe Aufzeichnungen ab [since]. Die Umrechnung in Events macht
  /// [HealthSync] — hier passiert nichts Fachliches.
  static Future<List<Map<String, Object?>>> healthRead(DateTime since) async {
    if (!isSupported) return const [];
    try {
      final result = await _channel.invokeListMethod<Map<Object?, Object?>>(
        'healthRead',
        {'sinceMillis': since.millisecondsSinceEpoch},
      );
      return (result ?? const [])
          .map((row) => row.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    } on PlatformException {
      return const [];
    } on MissingPluginException {
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
  static Future<bool> requestPinWidget() => _invoke('requestPinWidget');

  /// Wie viele Widget-Instanzen tatsaechlich auf dem Startbildschirm liegen.
  static Future<int> widgetCount() async {
    if (!isSupported) return 0;
    try {
      return await _channel.invokeMethod<int>('widgetCount') ?? 0;
    } on PlatformException {
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }

  // ── Notiz-Rolle (S-Pen) ───────────────────────────────────────────────

  /// Fragt die Rolle „Notiz-App" an.
  ///
  /// Ohne diese Rolle taucht AXIOM beim Stift-Doppeltipp nicht auf. Der
  /// Intent-Filter allein reicht nicht — das System fragt die Rolle ab,
  /// nicht den Filter.
  static Future<bool> requestNotesRole() => _invoke('requestNotesRole');

  // ── Diagnose ──────────────────────────────────────────────────────────

  /// Rohwerte, so wie das Geraet sie meldet.
  ///
  /// Existiert, weil „geht nicht" keine Fehlermeldung ist. Jede Zeile hier
  /// ist eine Aussage des Systems, nicht eine Vermutung der App.
  static Future<Map<String, Object?>> diagnostics() async {
    if (!isSupported) return const {};
    try {
      final result =
          await _channel.invokeMapMethod<String, Object?>('diagnostics');
      return result ?? const {};
    } on PlatformException catch (e) {
      return {'error': e.message};
    } on MissingPluginException {
      return const {'error': 'Kein Kanal'};
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
      return await _channel
          .invokeMethod<String>('listen', {'locale': ?locale});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<bool> speechAvailable() => _invoke('speechAvailable');

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
  static Future<List<String>> pullPendingMemos() async {
    if (!isSupported) return const [];
    try {
      final result =
          await _channel.invokeListMethod<String>('pullPendingMemos');
      return result ?? const [];
    } on PlatformException {
      return const [];
    }
  }

  // ── Intern ────────────────────────────────────────────────────────────

  static Future<bool> _invoke(String method, [Map<String, Object?>? args]) async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
