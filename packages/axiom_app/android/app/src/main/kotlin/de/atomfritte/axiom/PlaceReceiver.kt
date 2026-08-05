package de.atomfritte.axiom

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject

/**
 * Nimmt den aktuellen Ort von einer Geräteroutine entgegen.
 *
 * Das Gegenstück zu den ausgehenden Broadcasts (`de.atomfritte.axiom.FOCUS_START` und
 * Geschwister): Eine Samsung-Routine „WLAN Büro verbunden → Broadcast senden"
 * setzt damit den Ort — ohne GPS, ohne Geofence, ohne
 * `ACCESS_BACKGROUND_LOCATION`. Ein verbundenes WLAN ist ohnehin genauer als
 * ein Kreis mit 200 m Radius, und es kostet nichts.
 *
 *     adb shell am broadcast -a de.atomfritte.axiom.PLACE --es place "Büro"
 *
 * Ein leerer oder fehlender `place`-Zusatz heißt: kein Ort mehr gesetzt.
 *
 * **Warum ohne `android:permission`.** Der naheliegende Reflex wäre, eine
 * eigene Berechtigung zu verlangen. Das würde die Funktion genau zerstören:
 * `android:permission` prüft den *Sender*, und Samsungs Routinen-App hält
 * keine selbst definierte Berechtigung von AXIOM — der Broadcast käme
 * kommentarlos nie an. Eine Signatur-Berechtigung wäre noch enger.
 *
 * Was dagegen abgewogen wurde: Der Empfänger gibt nichts heraus (ein
 * Broadcast-Receiver hat keinen Rückkanal), er liest nichts aus der
 * Datenbank, und er kann nichts auslösen außer einer Ortsangabe. Das
 * Schlimmste, was eine fremde App damit anstellen kann, ist einen falschen
 * Ort zu setzen — sichtbar in der Hauptansicht, in zwei Tipps zurückgesetzt,
 * und im Ereignisstrom als `source: device` nachlesbar. Gemessen an einer
 * Standortberechtigung ist das die deutlich kleinere Angriffsfläche.
 *
 * Die App muss dafür nicht laufen. Der Ort landet in [PlaceInbox] und wird
 * beim nächsten Start eingesammelt — mit dem Zeitstempel des Empfangs, damit
 * das Ereignis später an der richtigen Stelle im Strom steht.
 */
class PlaceReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION = "de.atomfritte.axiom.PLACE"
        const val EXTRA_PLACE = "place"

        /** Ein Ortsname, kein Textfeld. Alles darüber ist ein Fehler. */
        const val MAX_LENGTH = 40
    }

    override fun onReceive(context: Context, intent: Intent) {
        // Nur die eine Aktion. Ein exportierter Empfänger bekommt alles, was
        // an ihn adressiert wird — auch direkt per Komponentennamen.
        if (intent.action != ACTION) return

        val place = intent.getStringExtra(EXTRA_PLACE)
            .orEmpty()
            .trim()
            .take(MAX_LENGTH)

        PlaceInbox.add(context, place, System.currentTimeMillis())
    }
}

/**
 * Ablage für Ortswechsel, die außerhalb der laufenden App entstehen.
 *
 * Wie [MemoInbox] aufgebaut, und aus demselben Grund: Die Dart-Seite liest
 * erst (`peek`), speichert, und bestätigt danach (`ack`). Wer in einem Zug
 * liest und löscht, verliert den Eintrag, sobald das Speichern scheitert.
 */
object PlaceInbox {
    private const val PREFS = "axiom_places"
    private const val KEY = "pending"

    /** Mehr als das braucht niemand — ältere Wechsel sind längst überholt. */
    private const val MAX_ENTRIES = 50

    @Synchronized
    fun add(context: Context, place: String, atMillis: Long) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val array = JSONArray(prefs.getString(KEY, "[]"))
        array.put(JSONObject().put("place", place).put("at", atMillis))

        val trimmed = if (array.length() <= MAX_ENTRIES) {
            array
        } else {
            JSONArray().also { kept ->
                for (i in array.length() - MAX_ENTRIES until array.length()) {
                    kept.put(array.get(i))
                }
            }
        }
        // `commit`, nicht `apply`: Der Prozess eines Empfängers darf
        // unmittelbar danach beendet werden, und was dann noch im Puffer
        // liegt, ist weg.
        prefs.edit().putString(KEY, trimmed.toString()).commit()
    }

    /** Die wartenden Wechsel — **ohne** sie zu löschen. */
    @Synchronized
    fun peek(context: Context): List<Map<String, Any?>> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val array = JSONArray(prefs.getString(KEY, "[]"))
        return (0 until array.length()).map { i ->
            val entry = array.getJSONObject(i)
            mapOf(
                "place" to entry.optString("place"),
                "at" to entry.optLong("at"),
            )
        }
    }

    /** Entfernt die ersten [count] Einträge — die, die bestätigt wurden. */
    @Synchronized
    fun ack(context: Context, count: Int): Int {
        if (count <= 0) return 0
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val array = JSONArray(prefs.getString(KEY, "[]"))
        val rest = JSONArray()
        for (i in count until array.length()) rest.put(array.get(i))
        prefs.edit().putString(KEY, rest.toString()).commit()
        return minOf(count, array.length())
    }
}
