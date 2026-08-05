package de.atomfritte.axiom

import android.content.Context

/**
 * Nutzertexte der Systemseite — entgegengenommen, nicht erfunden.
 *
 * **Warum es diese Ablage gibt.** Benachrichtigungen, Widget,
 * Schnelleinstellung und Kanalnamen sind Nutzertext, werden aber von Android
 * gezeichnet. Fest im Kotlin-Quelltext waren sie fest deutsch: Wer die App
 * auf Englisch stellte, bekam eine englische Oberfläche und deutsche
 * Benachrichtigungen daneben. Ausserdem lief dieser Text an der
 * Übersetzungspruefung vorbei, die nur `lib/` liest.
 *
 * Jetzt gilt: Dart schickt die fertigen Saetze herunter
 * (`SystemTexts.forLanguage`), hier liegen sie ab, und die Dienste lesen sie
 * von hier. Der Schluessel ist ein stabiler Name, kein Satz — ein Satz, der
 * sich aendert, waere hier ein stiller Fehlschlag.
 *
 * **Was passiert, bevor die App je lief.** Ein Alarm nach einem Neustart, die
 * Schnelleinstellung direkt nach der Installation, das Teilen-Ziel beim
 * ersten Start: Da ist noch nichts abgelegt. Dafuer steht in [FALLBACK] zu
 * jedem Schluessel eine Android-Ressource — dieselben Saetze, in der
 * Geraetesprache. Sichtbar unfertig gibt es hier also nicht; es gibt
 * hoechstens die Sprache des Geraets statt der in der App gewaehlten.
 */
object AxiomTexts {
    private const val PREFS = "axiom_texts"
    private const val KEY_STAMP = "stamp"

    /**
     * Der Rueckfall je Schluessel.
     *
     * Diese Liste ist zugleich der Vertrag mit der Dart-Seite: `i18n_test`
     * haelt sie deckungsgleich mit `SystemTexts.sources`. Ein Schluessel, den
     * nur eine Seite kennt, waere sonst ein Text, der irgendwann leer bleibt.
     */
    val FALLBACK: Map<String, Int> = mapOf(
        "channel.info.name" to R.string.axiom_channel_info_name,
        "channel.info.description" to R.string.axiom_channel_info_description,
        "channel.nudge.name" to R.string.axiom_channel_nudge_name,
        "channel.nudge.description" to R.string.axiom_channel_nudge_description,
        "channel.intervene.name" to R.string.axiom_channel_intervene_name,
        "channel.intervene.description" to R.string.axiom_channel_intervene_description,
        "channel.enforce.name" to R.string.axiom_channel_enforce_name,
        "channel.enforce.description" to R.string.axiom_channel_enforce_description,
        "channel.presence.name" to R.string.axiom_channel_presence_name,
        "channel.presence.description" to R.string.axiom_channel_presence_description,
        "channel.live.name" to R.string.axiom_channel_live_name,
        "channel.live.description" to R.string.axiom_channel_live_description,
        "channel.expert.name" to R.string.axiom_channel_expert_name,
        "channel.expert.description" to R.string.axiom_channel_expert_description,

        "presence.headline" to R.string.axiom_presence_headline,
        "presence.detail" to R.string.axiom_presence_detail,
        "presence.short" to R.string.axiom_presence_short,
        "presence.input" to R.string.axiom_presence_input,
        "presence.capture" to R.string.axiom_presence_capture,
        "presence.checkin" to R.string.axiom_presence_checkin,
        "presence.saved" to R.string.axiom_presence_saved,

        "live.title" to R.string.axiom_live_title,
        "live.stop" to R.string.axiom_live_stop,
        "live.remaining" to R.string.axiom_live_remaining,
        "live.over" to R.string.axiom_live_over,
        "live.chip" to R.string.axiom_live_chip,
        "live.chip.over" to R.string.axiom_live_chip_over,

        "widget.label" to R.string.axiom_widget_label,
        "widget.capture" to R.string.axiom_widget_capture,
        "widget.headline" to R.string.axiom_widget_headline,
        "widget.detail" to R.string.axiom_widget_detail,
        "widget.capacity" to R.string.axiom_widget_capacity,

        "expert.title" to R.string.axiom_expert_title,
        "expert.detail" to R.string.axiom_expert_detail,
        "expert.stop" to R.string.axiom_expert_stop,

        "tile.label" to R.string.axiom_tile_label,
        "tile.description" to R.string.axiom_tile_description,
        "share.short" to R.string.axiom_share_short,
        "share.long" to R.string.axiom_share_long,

        "speech.prompt" to R.string.axiom_speech_prompt,
    )

    /**
     * Nimmt die Texte einer Sprache entgegen.
     *
     * Gibt zurueck, ob sich dadurch etwas geaendert hat. Nur dann muessen die
     * Kanaele neu geschrieben und das Widget neu gezeichnet werden — der
     * Abgleich laeuft nach jedem Auswertungszyklus, und zwanzig
     * Schreibvorgaenge pro Zyklus waeren Verschwendung ohne Gegenwert.
     *
     * Verglichen wird nicht die Sprache, sondern ein Abdruck des ganzen
     * Buendels. Ueber die Sprache allein waere ein Update, das *einen* Satz
     * umformuliert, unsichtbar geblieben: Die Sprache ist dieselbe, also
     * haette hier nichts geschrieben — und auf dem Geraet staende der alte
     * Satz weiter, ohne dass irgendwo etwas darauf hindeutet. `String` und
     * `Map` haben in Java einen festgelegten `hashCode`, der Abdruck ist also
     * ueber Laeufe und Neustarts hinweg derselbe.
     */
    @Synchronized
    fun apply(context: Context, language: String, texts: Map<String, String>): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val stamp = 31 * language.hashCode() + texts.hashCode()
        if (prefs.getInt(KEY_STAMP, 0) == stamp && stamp != 0) return false
        val edit = prefs.edit().putInt(KEY_STAMP, stamp)
        texts.forEach { (key, value) -> edit.putString(key, value) }
        // `commit`, nicht `apply`: Direkt danach werden die Kanaele neu
        // geschrieben, und die lesen genau diese Werte.
        edit.commit()
        return true
    }

    /**
     * Der abgelegte Text, sonst der Rueckfall aus den Ressourcen.
     *
     * Ein unbekannter Schluessel gibt den Schluessel selbst zurueck. Das ist
     * haesslich und genau deshalb richtig: sichtbar unfertig statt stumm leer.
     */
    fun get(context: Context, key: String): String {
        val stored = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(key, null)
        if (stored != null) return stored
        val fallback = FALLBACK[key] ?: return key
        return try {
            context.getString(fallback)
        } catch (e: Throwable) {
            key
        }
    }

    /**
     * Wie [get], mit eingesetzten Platzhaltern `{0}`, `{1}`, …
     *
     * Bewusst dieselbe Schreibweise wie in Dart und nicht `%s`: Derselbe Satz
     * steht in `SystemTexts`, in `en.dart` und in `strings.xml`, und er soll
     * ueberall gleich aussehen. Ausserdem darf die englische Fassung die
     * Reihenfolge aendern — dafuer sind die Platzhalter nummeriert.
     */
    fun format(context: Context, key: String, vararg args: Any?): String {
        var text = get(context, key)
        args.forEachIndexed { index, value ->
            text = text.replace("{$index}", value?.toString().orEmpty())
        }
        return text
    }
}
