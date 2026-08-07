/// Texte, die **das Betriebssystem** anzeigt — nicht die App.
///
/// **Warum sie hier stehen und nicht in Kotlin.** Benachrichtigungskanäle,
/// die dauerhafte Anzeige, das Widget, die Schnelleinstellung: Alles davon
/// wird von Android gezeichnet, aber alles davon ist Nutzertext. Stand er im
/// Kotlin-Quelltext, war er fest deutsch — eine englische Oberfläche mit
/// deutschen Benachrichtigungen daneben. Und er lief an `i18n_test` vorbei,
/// weil das nur `lib/` liest.
///
/// Deshalb der Grundsatz: **Kotlin nimmt Text entgegen, es erfindet keinen.**
/// [sources] ist die vollständige Liste dessen, was die Systemseite sagen
/// darf. [forLanguage] übersetzt sie in einem Rutsch, [SystemSync] schickt
/// sie hinunter, und Kotlin legt sie ab. Was Android zeigt, bevor die App je
/// gelaufen ist, deckt `res/values(-de)/strings.xml` ab — dieselben Sätze,
/// in der Gerätesprache.
///
/// Der Schlüssel ist hier **nicht** der deutsche Satz, anders als bei
/// `context.t`. Grund: Kotlin muss denselben Text unter einem stabilen Namen
/// wiederfinden, und ein Satz, der sich ändert, wäre dort ein stiller
/// Fehlschlag. Der deutsche Satz bleibt trotzdem die Quelle — er steht als
/// Wert daneben und geht durch dieselbe Wörterliste wie alles andere.
///
/// Platzhalter sind `{0}`, `{1}`, … wie überall. Kotlin setzt sie ein.
library;

import '../i18n/i18n.dart';

abstract final class SystemTexts {
  /// Was die Systemseite anzeigen darf — Schlüssel, deutscher Quelltext.
  ///
  /// Jeder Schlüssel hier braucht auf der Kotlin-Seite einen Rückfall in
  /// `AxiomTexts.FALLBACK`; `i18n_test` hält beide Listen deckungsgleich.
  static const Map<String, String> sources = {
    // ── Benachrichtigungskanäle ──────────────────────────────────────────
    // Ein Kanal je Eingriffstiefe. Sonst lässt sich nur alles oder nichts
    // stummschalten — und im Zweifel wird alles stummgeschaltet.
    'channel.info.name': 'Hinweise',
    'channel.info.description': 'Erscheint nur im Rückblick.',
    'channel.nudge.name': 'Leise Anstöße',
    'channel.nudge.description': 'Still, wegwischbar.',
    'channel.intervene.name': 'Interventionen',
    'channel.intervene.description': 'Sichtbar, erwartet eine Antwort.',
    'channel.enforce.name': 'Verbindliche Regeln',
    'channel.enforce.description':
        'Nur für Regeln, die du selbst verbindlich gesetzt hast.',
    'channel.presence.name': 'Dauerhafte Anzeige',
    'channel.presence.description':
        'Zeigt die nächste Handlung. Still, ohne Ton.',
    'channel.live.name': 'Laufender Slot',
    'channel.live.description':
        'Fokus und Reiz-Slots, solange sie laufen. Still.',
    'channel.expert.name': 'Expertenmodus',
    'channel.expert.description':
        'Sichtbar, solange der lokale Server läuft.',

    // ── Dauerhafte Anzeige ───────────────────────────────────────────────
    'presence.headline': 'AXIOM',
    'presence.detail': 'Tippen zum Erfassen',
    // Was in die Pille neben der Uhr passt. Wenige Zeichen, kein Satz.
    'presence.short': 'Jetzt',
    'presence.input': 'Was ist dir eingefallen?',
    'presence.capture': 'Erfassen',
    'presence.checkin': 'Check-in',
    // Rückmeldung nach dem Tippen in der Benachrichtigung. Ohne sie weiß
    // niemand, ob es angekommen ist — und tippt es nochmal [D9].
    'presence.saved': 'Erfasst',

    // ── Laufender Slot ───────────────────────────────────────────────────
    'live.title': 'Slot läuft',
    'live.stop': 'Beenden',
    'live.remaining': 'noch {0} von {1} min',
    // Sachlich, ohne Vorwurf: eine Zahl, keine Bewertung (G3, R7).
    'live.over': '{0} min über den Bezugspunkt',
    'live.chip': '{0} min',
    'live.chip.over': '+{0} min',

    // ── Homescreen-Widget ────────────────────────────────────────────────
    'widget.label': 'JETZT',
    'widget.capture': 'ERFASSEN',
    'widget.headline': 'Nichts anliegend',
    'widget.detail': 'Tippen zum Erfassen',
    'widget.capacity': 'KAPAZITÄT {0}',

    // ── Expertenmodus ────────────────────────────────────────────────────
    'expert.title': 'Expertenmodus läuft',
    'expert.detail': 'Verschlüsselt mit einem selbst signierten Zertifikat. '
        'Ohne Anfrage schaltet sich der Server nach 30 Minuten ab.',
    'expert.stop': 'Beenden',
    // Die Zahl steht im Titel, weil genau sie verglichen werden soll. Die
    // Meldung entscheidet nichts — sie fuehrt auf den Bildschirm, auf dem
    // der Vergleich seit jeher stattfindet (ADR-0005 §3a).
    'expert.approval.title': 'Freigabe: {0}',
    'expert.approval.detail':
        'Ein Browser will an die Daten dieses Telefons. Tippen, wenn dieselbe '
        'Zahl auf dem Bildschirm steht, vor dem du sitzt.',

    // ── Schnelleinstellung und Teilen-Blatt ──────────────────────────────
    'tile.label': 'Erfassen',
    'tile.description': 'Gedanken in AXIOM festhalten',
    'share.short': 'Erfassen',
    'share.long': 'In AXIOM erfassen',

    // ── Spracheingabe ────────────────────────────────────────────────────
    // Steht im Dialog der Erkennungs-App, nicht in AXIOM.
    'speech.prompt': 'Sprich einfach.',
  };

  /// Gründe, die die Systemseite meldet — Schlüssel, deutscher Quelltext.
  ///
  /// Diese gehen den umgekehrten Weg: Kotlin schickt den **Schlüssel** herauf,
  /// [AndroidBridge] setzt den Satz zusammen. So bleibt auch die Erklärung
  /// eines Fehlschlags übersetzbar, ohne dass Kotlin Sätze bauen muss.
  ///
  /// `{0}` ist, wo vorhanden, der Name der Ausnahme oder ein Statuswert —
  /// unschön, aber diagnostizierbar. Ein stummer Knopf ist teurer.
  static const Map<String, String> reasons = {
    'reason.unsupported': 'Diese Funktion gibt es nur auf Android.',
    'reason.timeout': 'Das System hat nicht geantwortet. Die Funktion bleibt '
        'aus, die App läuft weiter.',
    'reason.bridge':
        'Die Systembrücke antwortet nicht. Das ist ein Fehler in AXIOM, '
            'nicht am Gerät.',

    'reason.widget.unsupported':
        'Dieser Startbildschirm nimmt keine Anfrage entgegen. Dann über die '
            'Widget-Auswahl: lange auf den Homescreen tippen → Widgets → AXIOM.',
    'reason.widget.refused': 'Der Startbildschirm hat die Anfrage abgelehnt.',
    'reason.widget.failed': 'Anfrage fehlgeschlagen: {0}',

    'reason.notes.since14':
        'Die Rolle „Notiz-App" gibt es erst ab Android 14.',
    'reason.notes.unavailable':
        'Dieses Gerät bietet die Rolle „Notiz-App" nicht an — Samsung '
            'schaltet sie in One UI nicht frei. Der Weg zum Stift führt hier '
            'über das Air-Command-Menü: Einstellungen → Erweiterte Funktionen '
            '→ S Pen → Air Command → Verknüpfungen → AXIOM.',
    'reason.notes.dialog': 'Der Systemdialog ließ sich nicht öffnen: {0}',

    'reason.presence.channel':
        'Der Benachrichtigungskanal „Dauerhafte Anzeige" ist abgeschaltet. '
            'Einstellungen → Benachrichtigungen → AXIOM → Dauerhafte Anzeige.',
    'reason.presence.notifications':
        'Benachrichtigungen sind für AXIOM abgeschaltet. Ohne sie hat die '
            'Anzeige nichts, worin sie erscheinen kann.',
    'reason.presence.refused': 'Das System hat den Dienst abgelehnt: {0}',

    'reason.health.unusable':
        'Health Connect meldet sich als nicht nutzbar (Status {0}). Ohne den '
            'Dienst gibt es nichts freizugeben.',
    'reason.health.dialog':
        'Die Berechtigungsabfrage ließ sich nicht öffnen: {0}',
    'reason.health.silent':
        'Health Connect ist installiert, öffnet aber keinen Freigabedialog '
            '({0}). In den Systemeinstellungen unter Health Connect lässt '
            'sich AXIOM dort von Hand freigeben.',
  };

  /// Die ganze Liste in einer Sprache — fertig zum Hinunterreichen.
  static Map<String, String> forLanguage(AppLanguage language) => {
        for (final entry in sources.entries)
          entry.key: translate(language, entry.value),
      };

  /// Baut den Satz zu einem Grund, den die Systemseite gemeldet hat.
  ///
  /// Ein unbekannter Schlüssel wird durchgereicht statt verschluckt: Dann
  /// steht ein technischer Name auf dem Bildschirm — sichtbar unfertig, und
  /// damit besser als ein Knopf, der kommentarlos nichts tut.
  static String reason(
    AppLanguage language,
    String key, [
    List<Object?> args = const [],
  ]) {
    final source = reasons[key];
    if (source == null) return key;
    return translate(language, source, args);
  }
}
