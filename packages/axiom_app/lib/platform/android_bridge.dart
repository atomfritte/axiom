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

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';

import '../i18n/i18n.dart';
import 'system_texts.dart';

/// Ergebnis eines Systemaufrufs — mit Grund, wenn er scheitert.
///
/// **Warum das ein eigener Typ ist.** Ein `bool` zurueckzugeben heisst, dass
/// jeder Fehlschlag auf dem Geraet als „passiert nichts" ankommt. Genau das
/// war der teuerste Fehler in diesem Projekt: fuenf gemeldete Probleme, vier
/// verschiedene Ursachen, und keine davon von aussen unterscheidbar. Ein
/// unschoener Satz ist besser als ein stummer Knopf.
///
/// [reason] ist ein fertiger Satz in der Sprache, die der Aufrufer
/// mitgegeben hat. Die Systemseite liefert dafuer nur einen Schluessel —
/// Kotlin kennt die gewaehlte Sprache nicht und soll keine Saetze bauen.
final class PlatformOutcome {
  final bool ok;
  final String? reason;

  const PlatformOutcome(this.ok, [this.reason]);

  static PlatformOutcome unsupported(AppLanguage language) => PlatformOutcome(
        false,
        SystemTexts.reason(language, 'reason.unsupported'),
      );
}

/// In welchem Zustand der Schlüssel der Datenbank ist.
///
/// **Warum drei Werte und nicht zwei.** Vorher gab es nur eine Passphrase
/// oder `null`. Damit war „hier gibt es keine Verschlüsselung" nicht von
/// „ich komme gerade nicht an den Schlüssel" zu unterscheiden. Die Folge:
/// Die App öffnete im Zweifel unverschlüsselt, traf auf eine verschlüsselte
/// Datei, hielt sie für kaputt — und legte sie neu an. Ein
/// vorübergehender Fehler des Schlüsselspeichers kostete so den gesamten
/// Ereignisstrom.
enum DatabaseKeyState {
  /// Der Schlüssel liegt vor.
  ready,

  /// Auf diesem Gerät wurde nie einer angelegt. Auf dem Linux-Rechner ist das
  /// der Normalfall — dort gibt es keinen Schlüsselspeicher. Eine vorhandene
  /// Datei kann dann nur im Klartext liegen, und genau so wird sie geöffnet.
  none,

  /// Es gab einen, er ist gerade nicht zu bekommen. Die Datei ist dann mit
  /// hoher Wahrscheinlichkeit verschlüsselt. **Hier wird nichts geöffnet und
  /// nichts gelöscht** — ein Startfehler ist billiger als ein Datenverlust.
  unavailable,
}

/// Antwort der Systemseite auf die Frage nach dem Datenbankschlüssel.
final class DatabaseKeyResult {
  final DatabaseKeyState state;

  /// Nur bei [DatabaseKeyState.ready] gesetzt.
  final String? key;

  const DatabaseKeyResult(this.state, [this.key]);

  static const absent = DatabaseKeyResult(DatabaseKeyState.none);
  static const unavailable = DatabaseKeyResult(DatabaseKeyState.unavailable);

  /// Liest die Antwort von `DatabaseKey.passphrase` (Kotlin).
  ///
  /// Alles, was nicht eindeutig ist — fehlender Zustand, unbekannter
  /// Zustand, `ready` ohne Schlüssel —, gilt als [DatabaseKeyState.unavailable].
  /// Die Richtung ist Absicht: Im Zweifel nicht anfassen.
  factory DatabaseKeyResult.fromMessage(Map<String, Object?>? message) {
    final key = message?['key'];
    return switch (message?['state']) {
      'ready' when key is String && key.isNotEmpty =>
        DatabaseKeyResult(DatabaseKeyState.ready, key),
      'none' => absent,
      _ => unavailable,
    };
  }
}

/// Der Schlüssel ist angelegt, aber gerade nicht zu bekommen.
///
/// Absichtlich ein eigener Typ und keine `null`-Rückgabe: Der Aufrufer soll
/// genau diesen Fall erkennen und die Datenbank **nicht** anfassen. Was
/// [toString] sagt, steht auf dem Startbildschirm (`AxiomGate`) — deshalb ein
/// Satz und keine Fehlernummer.
final class DatabaseKeyUnavailable implements Exception {
  const DatabaseKeyUnavailable();

  @override
  String toString() =>
      'Der Schlüsselspeicher des Geräts antwortet gerade nicht. '
      'AXIOM lässt die Datenbank deshalb zu: Ohne Schlüssel wäre die '
      'vorhandene Datei nicht lesbar, und weiterzumachen hieße, sie zu '
      'verlieren. Ein erneuter Start nach dem nächsten Entsperren genügt '
      'in der Regel.';
}

/// Wohin eine Benachrichtigung führt.
///
/// Die Zeichenketten sind Intent-Actions und stehen genauso in
/// `MainActivity.consumeLaunchAction`. Sie hier zu benennen ist der Punkt:
/// Ein Tippfehler in einem freien String hätte zur Folge, dass die
/// Benachrichtigung stumm auf der Übersicht landet — funktionierend genug,
/// um nicht aufzufallen.
abstract final class AxiomRoute {
  static const capture = 'de.atomfritte.axiom.CAPTURE';
  static const checkin = 'de.atomfritte.axiom.CHECKIN';
  static const focus = 'de.atomfritte.axiom.FOCUS';
  static const sensation = 'de.atomfritte.axiom.SENSATION';
  static const anchors = 'de.atomfritte.axiom.ANCHORS';
  static const review = 'de.atomfritte.axiom.REVIEW';
  static const body = 'de.atomfritte.axiom.BODY';
  static const inbox = 'de.atomfritte.axiom.INBOX';
}

/// Der Wecker auf das geplante Ende eines Fokusblocks [D6, M4].
///
/// **Warum es ihn geben muss.** Der Fokus-Governor existiert, um Hyperfokus
/// zu unterbrechen. Die laufende Anzeige zeigt zwar die Restzeit, aber sie
/// zeigt sie in der Statusleiste — und wer vertieft ist, sieht per
/// Definition nicht dorthin. Ein Fortschrittsbalken, der voll läuft und dann
/// nichts tut, ist keine Unterbrechung, sondern eine Anzeige für jemanden,
/// der ohnehin schon hinsieht. Zeittrigger sind der wirksamste
/// Interventionstyp dieses Profils [D4]; hier ist die Stelle, an der das
/// zählt.
///
/// **Warum `axiom_intervene` und damit hörbar.** Es gibt vier Kanäle:
/// `axiom_info` (MIN) und `axiom_nudge` (LOW) machen keinen Ton — ein
/// stummes Blockende wäre genau der Zustand, der behoben werden soll: eine
/// Meldung, die die eine Person nicht erreicht, für die sie gedacht ist.
/// `axiom_enforce` (HIGH) blendet sich über das laufende Bild; das ist ein
/// Schreck und gehört dem Notfall, nicht dem Ende einer geplanten Stunde.
/// Bleibt `axiom_intervene` (DEFAULT): Es klingt einmal und legt sich in die
/// Leiste.
///
/// Der Fokus**start** bekommt bewusst keinen Ton. Dort hat man gerade selbst
/// den Knopf gedrückt — ein Ton, der bestätigt, was man eben getan hat, ist
/// ein Schreck ohne Information.
///
/// **Kein eigener Tonweg.** Der Klang gehört dem Betriebssystem: kein
/// Soundplayer, keine Audiodatei, kein zweiter Lautstärkeregler in den
/// Einstellungen. Wer ihn abstellen will, tut das in den Kanaleinstellungen
/// von Android — dort, wo er ihn sucht, und nicht in einem Schalter, den
/// AXIOM zusätzlich pflegen müsste [D3].
abstract final class FocusEndAlarm {
  /// Feste ID. Die Vergabe aller Alarm-IDs steht bei
  /// [AndroidBridge.scheduleExact].
  static const int alarmId = 20;

  /// Stellt den Wecker auf das Ende des Blocks.
  ///
  /// [now] kommt vom Aufrufer und nicht aus `DateTime.now()`: Wer den Wecker
  /// stellt, hat eine Uhr — im Test eine gestellte. Ohne das wäre „der
  /// Wecker steht auf der richtigen Minute" nicht prüfbar.
  ///
  /// Liegt das Ende schon hinter uns, wird nichts gestellt, sondern
  /// abbestellt: Ein Alarm, der sofort feuert, meldet ein Ende, das beim
  /// Lesen längst vorbei ist.
  static Future<bool> arm({
    required DateTime startedAt,
    required Duration planned,
    required DateTime now,
    String? anchorTitle,
    AppLanguage language = AppLanguage.de,
  }) {
    final endsAt = startedAt.add(planned);
    if (!endsAt.isAfter(now)) return disarm();

    final (title, body) = describe(planned, anchorTitle, language);
    return AndroidBridge.scheduleExact(
      id: alarmId,
      at: endsAt,
      title: title,
      body: body,
      // Hörbar. Die Begründung steht im Kopfkommentar dieser Klasse.
      channel: 'axiom_intervene',
      // Auf den Fokusschirm: Dort steht „Fokus beenden", und dahinter liegt
      // die Frage nach der Wiedereinstiegsnotiz — der eigentliche Zweck des
      // Ausstiegs [D11]. Ohne Ziel landete der Tipp auf der Übersicht, und
      // der Weg zur Handlung begänne von vorn [D2].
      route: AxiomRoute.focus,
    );
  }

  /// Nimmt den Wecker zurück.
  ///
  /// Ein Alarm, der nach dem vorzeitigen Ende noch feuert, ist schlimmer als
  /// keiner: Er meldet etwas, das nicht mehr läuft — und danach glaubt man
  /// ihm auch beim nächsten Mal nicht mehr.
  static Future<bool> disarm() => AndroidBridge.cancelAlarm(alarmId);

  /// Überschrift und Text der Meldung.
  ///
  /// Sichtbar für den Test, weil der Ton hier das Eigentliche ist und die
  /// Systemseite ihn auf dem Rechner nie zu sehen bekommt.
  ///
  /// Die Überschrift ist eine **Ablesung**, kein Urteil: „50 von 50 min" —
  /// dieselbe Zeile, die während des Blocks auf der Hauptansicht steht (R7).
  /// Kein „Zeit abgelaufen", kein Ausrufezeichen, keine Aufforderung. Der
  /// Text darunter ist die nächste Handlung, und zwar genau die, die der
  /// Fokusschirm beim Beenden ohnehin stellt.
  @visibleForTesting
  static (String, String) describe(
    Duration planned,
    String? anchorTitle,
    AppLanguage language,
  ) {
    final minutes = planned.inMinutes;
    return (
      translate(language, '{0} von {1} min', [minutes, minutes]),
      anchorTitle == null || anchorTitle.isEmpty
          ? translate(
              language, 'Woran warst du dran, und was wäre der nächste Handgriff?')
          : translate(
              language, 'Wo genau bist du bei „{0}" stehengeblieben?', [anchorTitle]),
    );
  }
}

/// Der Wecker fuer den Eingang — R-150 auf einem Weg, der die App nicht braucht.
///
/// **Warum es ihn ueberhaupt gibt.** Eine gefeuerte Regel wird in AXIOM zu
/// einer Zeile auf dem Bildschirm, zu nichts sonst. Die vier
/// Benachrichtigungskanaele benutzen ausschliesslich geplante Alarme. Wer
/// die App nicht oeffnet, erfaehrt von keiner Regel etwas — und R-150
/// („Etwas liegt seit Tagen im Eingang") existiert genau fuer den Fall, dass
/// man sie eben nicht oeffnet. Sie war damit auf dem einzigen Weg stumm, auf
/// dem sie haette sprechen muessen.
///
/// **Warum ein Wecker und keine Hintergrundauswertung.** Eine periodische
/// Auswertung braeuchte einen Dienst, der die App weckt, die Datenbank
/// oeffnet und das Regelwerk laedt — fuer eine Frage, deren Antwort sich in
/// der Zwischenzeit nur langsam aendert. Der Wecker steht stattdessen im
/// Voraus auf den Zeitpunkt, an dem die aelteste Notiz alt genug wird, und
/// wird zurueckgenommen, sobald sie beantwortet ist. Dasselbe Verfahren wie
/// bei den Ankerschritten (`SystemSync.scheduleAnchorReminders`).
///
/// **Der Kanal ist `axiom_nudge`, nicht `axiom_intervene`.** Sichtbar, aber
/// still. Ein Ton gehoert zum Unterbrechen von Vertiefung (siehe
/// [FocusEndAlarm]); eine drei Tage alte Notiz ist nicht dringend, sie ist
/// nur vergessen. Wer sie mit einem Klang meldet, bekommt beim naechsten
/// echten Klang keine Aufmerksamkeit mehr.
abstract final class InboxAgeAlarm {
  /// Feste ID. Die Vergabe aller Alarm-IDs steht bei
  /// [AndroidBridge.scheduleExact].
  static const int alarmId = 21;

  /// Ab wann eine Notiz „alt" ist.
  ///
  /// **Dieselbe Zahl wie in R-150** (`inbox_oldest_hours: { gte: 72 }`).
  /// Sie steht hier ein zweites Mal, und das ist eine bewusste Doppelung:
  /// Der Wecker muss den Zeitpunkt im Voraus kennen, die Regel wertet
  /// rueckblickend aus — beide brauchen die Schwelle, aber zu verschiedenen
  /// Zeitpunkten. `inbox_alarm_test.dart` liest den Wert aus dem
  /// ausgelieferten Regelwerk und vergleicht ihn mit diesem hier; laufen sie
  /// auseinander, faellt der Test.
  static const Duration threshold = Duration(hours: 72);

  /// Das Zeitfenster aus R-150. Ausserhalb schweigt die Regel, also soll
  /// auch der Wecker nicht klingeln — sonst meldete er etwas, das die App
  /// beim Oeffnen gar nicht anzeigt.
  static const int windowStartHour = 9;
  static const int windowEndHour = 20;

  /// Stellt den Wecker auf den Moment, in dem die aelteste offene Notiz
  /// alt genug wird — oder nimmt ihn zurueck, wenn keine da ist.
  ///
  /// [oldestUnanswered] ist der Zeitpunkt der Erfassung, nicht ihr Alter:
  /// Aus einem Alter liesse sich der Weckzeitpunkt nur mit einer zweiten Uhr
  /// ausrechnen, und die waere eine andere als die des Aufrufers.
  static Future<bool> arm({
    required DateTime? oldestUnanswered,
    required DateTime now,
    AppLanguage language = AppLanguage.de,
  }) {
    if (oldestUnanswered == null) return disarm();

    final reif = oldestUnanswered.add(threshold);
    final at = _intoWindow(reif.isAfter(now) ? reif : now, now);
    if (at == null) return disarm();

    final tage = now.difference(oldestUnanswered).inDays;
    final (title, body) = describe(tage < 3 ? 3 : tage, language);
    return AndroidBridge.scheduleExact(
      id: alarmId,
      at: at,
      title: title,
      body: body,
      // Sichtbar und still. Begruendung im Kopfkommentar dieser Klasse.
      channel: 'axiom_nudge',
      route: AxiomRoute.inbox,
    );
  }

  /// Nimmt den Wecker zurueck. Ein leerer Eingang, der sich meldet, ist die
  /// sicherste Art, dass man beim naechsten Mal nicht mehr hinsieht.
  static Future<bool> disarm() => AndroidBridge.cancelAlarm(alarmId);

  /// Schiebt einen Zeitpunkt in das Fenster, in dem R-150 ueberhaupt
  /// spricht. Faellt er davor, wird auf den Fensteranfang desselben Tages
  /// gewartet; faellt er danach, auf den naechsten Morgen.
  ///
  /// Gibt `null` zurueck, wenn dabei nichts Sinnvolles herauskommt — der
  /// Aufrufer bestellt dann ab, statt zu raten.
  static DateTime? _intoWindow(DateTime wanted, DateTime now) {
    var at = wanted;
    if (at.hour < windowStartHour) {
      at = DateTime(at.year, at.month, at.day, windowStartHour);
    } else if (at.hour >= windowEndHour) {
      at = DateTime(at.year, at.month, at.day, windowStartHour)
          .add(const Duration(days: 1));
    }
    // Nach dem Schieben kann der Zeitpunkt hinter „jetzt" zurueckgefallen
    // sein — dann der naechste Morgen. Ein Alarm in der Vergangenheit feuert
    // sofort, und eine Meldung, die im selben Moment kommt, in dem man die
    // App ohnehin benutzt, ist Laerm.
    if (!at.isAfter(now)) {
      at = DateTime(now.year, now.month, now.day, windowStartHour)
          .add(const Duration(days: 1));
    }
    return at;
  }

  /// Ueberschrift und Text. Sichtbar fuer den Test — die Systemseite
  /// bekommt ihn auf dem Rechner nie zu sehen.
  ///
  /// Eine Feststellung, keine Mahnung: kein „schon wieder", kein „immer
  /// noch", kein Ausrufezeichen. Die Zahl ist das Alter, nicht die Menge —
  /// „7 Notizen" waere eine Bilanz und traefe D10; „seit drei Tagen" ist
  /// eine Ablesung.
  @visibleForTesting
  static (String, String) describe(int tage, AppLanguage language) => (
        translate(language, 'Seit {0} Tagen im Eingang', [tage]),
        translate(language,
            'Einmal ansehen genügt: übernehmen oder verwerfen, beides ist ein Tipp.'),
      );
}

abstract final class AndroidBridge {
  static const _channel = MethodChannel('de.atomfritte.axiom/system');

  // ── Texte der Systemseite ─────────────────────────────────────────────

  /// Reicht die Texte hinunter, die Android anzeigt.
  ///
  /// Benachrichtigungskanäle, dauerhafte Anzeige, Widget, Schnelleinstellung:
  /// Alles davon zeichnet das Betriebssystem, alles davon ist Nutzertext.
  /// Kotlin kennt die in der App gewählte Sprache nicht und soll sie auch
  /// nicht kennen — es nimmt die fertigen Sätze entgegen.
  ///
  /// Läuft nach jedem Auswertungszyklus mit. Die Systemseite schreibt nur,
  /// wenn sich die Sprache geändert hat; sonst ist der Aufruf ein Blick auf
  /// eine gespeicherte Zeichenkette.
  /// Zeigt die offene Freigabeanfrage des Expertenmodus als
  /// Benachrichtigung — oder nimmt sie zurueck.
  ///
  /// **Sie entscheidet nichts.** Antippen oeffnet den Expertenmodus-
  /// Bildschirm, auf dem der Zahlenabgleich seit jeher stattfindet. Ein
  /// Freigabeknopf in der Leiste waere zwei unabhaengige Sicherheitsloecher
  /// — `Notification.Action.actionIntent` ist ein oeffentliches Feld, und
  /// ein Broadcast feuert auf einem gesperrten Geraet ohne Entsperren. Die
  /// lange Fassung steht in `ApprovalNotice.kt`.
  static Future<bool> showApproval(String number) =>
      _invoke('approvalShow', {'number': number});

  static Future<bool> hideApproval() => _invoke('approvalHide');

  static Future<bool> applySystemTexts(AppLanguage language) => _invoke(
        'applyTexts',
        {'language': language.code, 'texts': SystemTexts.forLanguage(language)},
      );

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
  static bool get isSupported =>
      debugAsIfAndroid ?? (!kIsWeb && Platform.isAndroid);

  /// Nur für Tests: so tun, als liefe die App auf einem Gerät.
  ///
  /// **Warum es das braucht.** Auf dem Rechner ist [isSupported] falsch, und
  /// jeder Aufruf endet vor dem Kanal. Damit ist eine ganze Klasse von
  /// Zusagen von hier aus unprüfbar — „beim Fokusstart steht ein Wecker auf
  /// dem Ende" etwa lässt sich sonst nur auf dem Gerät nachsehen, und was
  /// nur auf dem Gerät geprüft wird, wird nicht geprüft. Zusammen mit einem
  /// vorgeschalteten Kanal-Attrappen-Handler läuft der echte Weg durch,
  /// inklusive ID, Kanal, Ziel und Text.
  ///
  /// `null` heisst: die Wirklichkeit entscheidet. Das ist der Normalfall und
  /// der Wert, den jeder Test wieder herstellt.
  @visibleForTesting
  static bool? debugAsIfAndroid;

  // ── Schlüssel der Datenbank ───────────────────────────────────────────

  /// Wie lange auf den Schlüsselspeicher gewartet wird.
  ///
  /// Deutlich mehr als [_timeout], und das ist der Punkt. Beim allerersten
  /// Start erzeugt der Keystore einen StrongBox-Schlüssel, synchron auf dem
  /// Android-Hauptthread; fünf Sekunden reichten dafür nicht immer. Lief die
  /// Zeit ab, kam auf dieser Seite `null` an, während Kotlin fertig wurde und
  /// den Schlüssel ablegte — die App legte eine Klartextdatenbank an und
  /// verwarf sie beim nächsten Start als unlesbar. Warten ist hier billiger
  /// als aufgeben: Solange läuft der Startbildschirm.
  static const Duration _keyTimeout = Duration(seconds: 30);

  /// Der Zustand des Datenbankschlüssels, mit Passphrase für `PRAGMA key`.
  ///
  /// Drei Zustände, nicht zwei — siehe [DatabaseKeyState]. Ohne
  /// Systembrücke (Linux-Rechner) gibt es keinen Schlüsselspeicher, in den
  /// man etwas legen könnte, das die eigene Anmeldung überdauert; eine
  /// Schlüsseldatei neben der Datenbank wäre eine Attrappe. Das ist
  /// [DatabaseKeyState.none] und ein Zustand, kein Fehler — der
  /// Systeminspektor zeigt ihn an, statt ihn zu verschweigen.
  ///
  /// Antwortet die Systemseite gar nicht, ist das **nicht** dasselbe:
  /// Vorher wurde auch daraus `null`, also „unverschlüsselt öffnen". Jede
  /// Zeitüberschreitung führte damit auf den Löschpfad in `providers.dart`.
  ///
  /// Kein Zwischenspeicher: Der Aufruf passiert genau einmal pro Start,
  /// bevor die Datenbank geöffnet wird. Eine Passphrase, die länger als
  /// nötig in einem Feld liegt, ist eine Passphrase mehr im Speicherabbild.
  static Future<DatabaseKeyResult> databaseKey() async {
    if (!isSupported) return DatabaseKeyResult.absent;
    try {
      return DatabaseKeyResult.fromMessage(
        await _channel
            .invokeMapMethod<String, Object?>('databaseKey')
            .timeout(_keyTimeout),
      );
    } on Object {
      return DatabaseKeyResult.unavailable;
    }
  }

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
  //
  // **Die Vergabe der Alarm-IDs. Eine Liste, an einer Stelle.**
  //
  // `AlarmManager` kennt keine Namen, nur eine Zahl je `PendingIntent`.
  // Zwei Stellen mit derselben Zahl überschreiben einander: Der zuletzt
  // gestellte Wecker gewinnt, der andere verschwindet — ohne Fehler, ohne
  // Log, ohne dass irgendwo etwas rot wird. Deshalb steht die Vergabe hier
  // und nicht verstreut dort, wo sie benutzt wird.
  //
  //        1 – 3   die drei täglichen Check-ins   [scheduleDailyCheckins]
  //       10       Abendgrenze                    `SleepGate.alarmWindDown`
  //       11       Schlaf eintragen, morgens      `SleepGate.alarmSleepLog`
  //       20       Ende eines Fokusblocks         [FocusEndAlarm.alarmId]
  //       21       Etwas liegt im Eingang         [InboxAgeAlarm.alarmId]
  //     1000 +     Ankerschritte, vier je Kette   `SystemSync._anchorIdBase`
  //
  // Frei sind 4 – 9, 12 – 19 und 22 – 999. Wer eine Zahl nimmt, trägt sie
  // hier ein.

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
    AppLanguage language = AppLanguage.de,
  }) => _outcome('presenceStart', language,
      {'headline': headline, 'detail': detail});

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

  /// [language] entscheidet, in welcher Sprache ein Fehlschlag erklärt wird.
  /// Sie wird durchgereicht statt global gelesen — sonst wäre sie an genau
  /// der Stelle unsichtbar, an der sie wirkt.
  static Future<PlatformOutcome> healthRequestPermissions({
    AppLanguage language = AppLanguage.de,
  }) =>
      _outcome('healthRequestPermissions', language);

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
  static Future<PlatformOutcome> requestPinWidget({
    AppLanguage language = AppLanguage.de,
  }) =>
      _outcome('requestPinWidget', language);

  /// Wie viele Widget-Instanzen tatsaechlich auf dem Startbildschirm liegen.
  static Future<int> widgetCount() => _count('widgetCount');

  // ── Notiz-Rolle (S-Pen) ───────────────────────────────────────────────

  /// Fragt die Rolle „Notiz-App" an.
  ///
  /// Ohne diese Rolle taucht AXIOM beim Stift-Doppeltipp nicht auf. Der
  /// Intent-Filter allein reicht nicht — das System fragt die Rolle ab,
  /// nicht den Filter.
  static Future<PlatformOutcome> requestNotesRole({
    AppLanguage language = AppLanguage.de,
  }) =>
      _outcome('requestNotesRole', language);

  // ── Diagnose ──────────────────────────────────────────────────────────

  /// Rohwerte, so wie das Geraet sie meldet.
  ///
  /// Existiert, weil „geht nicht" keine Fehlermeldung ist. Jede Zeile hier
  /// ist eine Aussage des Systems, nicht eine Vermutung der App.
  static Future<Map<String, Object?>> diagnostics({
    AppLanguage language = AppLanguage.de,
  }) async {
    if (!isSupported) return const {};
    try {
      final result = await _channel
          .invokeMapMethod<String, Object?>('diagnostics')
          .timeout(_healthTimeout);
      return result ?? const {};
    } on TimeoutException {
      return {'error': translate(language, 'Das System hat nicht geantwortet.')};
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

  static Future<void> focusStart() => broadcast('de.atomfritte.axiom.FOCUS_START');
  static Future<void> focusEnd() => broadcast('de.atomfritte.axiom.FOCUS_END');
  static Future<void> windDown() => broadcast('de.atomfritte.axiom.WINDDOWN');
  static Future<void> enterMaintenanceMode() => broadcast('de.atomfritte.axiom.L3_ENTER');

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
  ///
  /// Gibt zurück, wie viele wirklich weg sind.
  ///
  /// **Warum eine Zahl und kein `bool`.** `MemoInbox.ack` antwortet mit der
  /// Zahl der gelöschten Einträge. `invokeMethod<bool>` packt die Antwort mit
  /// `as bool?` aus, und ein `int` gibt dort einen TypeError — den [_invoke]
  /// wie jede andere Ausnahme fängt. Die Bestätigung lief also durch, die
  /// Notizen waren weg, und diese Seite meldete trotzdem dauerhaft „hat nicht
  /// geklappt". Ein Rückgabewert, der strukturell nie wahr werden kann, ist
  /// schlimmer als keiner: Wer ihn irgendwann abfragt, baut auf eine Aussage,
  /// die es nie gab.
  static Future<int> ackPendingMemos(int count) =>
      _count('ackPendingMemos', {'count': count});

  // ── Ort (D2) ──────────────────────────────────────────────────────────

  /// Ortswechsel, die eine Geräteroutine über `de.atomfritte.axiom.PLACE` geschickt hat.
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

  /// Wie [ackPendingMemos], und aus demselben Grund eine Zahl.
  static Future<int> ackPendingPlaces(int count) =>
      _count('ackPendingPlaces', {'count': count});

  // ── Intern ────────────────────────────────────────────────────────────

  /// Wie [_invoke], aber mit dem Grund des Scheiterns.
  ///
  /// Die Systemseite antwortet mit `reason` als Schluessel und `reasonArgs`
  /// als Werten dazu — der Satz entsteht erst hier, in der Sprache, die der
  /// Aufrufer mitgegeben hat.
  static Future<PlatformOutcome> _outcome(
    String method,
    AppLanguage language, [
    Map<String, Object?>? args,
  ]) async {
    if (!isSupported) return PlatformOutcome.unsupported(language);
    try {
      final result = await _channel
          .invokeMapMethod<String, Object?>(method, args)
          .timeout(_timeout);
      if (result == null) return const PlatformOutcome(false);
      final key = result['reason'] as String?;
      return PlatformOutcome(
        result['ok'] == true,
        key == null
            ? null
            : SystemTexts.reason(
                language,
                key,
                (result['reasonArgs'] as List?)?.cast<Object?>() ?? const [],
              ),
      );
    } on PlatformException catch (e) {
      return PlatformOutcome(false, e.message);
    } on TimeoutException {
      return PlatformOutcome(
        false,
        SystemTexts.reason(language, 'reason.timeout'),
      );
    } on Object {
      return PlatformOutcome(
        false,
        SystemTexts.reason(language, 'reason.bridge'),
      );
    }
  }

  /// Für alles, was die Systemseite mit einer Zahl beantwortet.
  ///
  /// Eigene Hülle statt [_invoke], weil der Auspacker den Typ festlegt: Ein
  /// `int` gegen `invokeMethod<bool>` ist ein TypeError, und der sähe hier
  /// aus wie ein Fehlschlag. 0 heißt „nichts passiert" — dieselbe Aussage
  /// wie `false`, nur ohne den Umweg über eine verschluckte Ausnahme.
  static Future<int> _count(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    if (!isSupported) return 0;
    try {
      return await _channel.invokeMethod<int>(method, args).timeout(_timeout) ??
          0;
    } on Object {
      return 0;
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
