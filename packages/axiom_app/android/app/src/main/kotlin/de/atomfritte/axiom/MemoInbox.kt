package de.atomfritte.axiom

import android.content.Context
import org.json.JSONArray

/**
 * Ablage für Erfassungen, die außerhalb der laufenden App entstehen —
 * Schnelleinstellung, geteilter Text, künftig S-Pen-Memos bei
 * ausgeschaltetem Bildschirm.
 *
 * Der S-Pen ist der reibungsärmste Kanal, den dieses Gerät bietet: Stift
 * ziehen, schreiben, fertig — ohne Entsperren [D9]. Die Anbindung an Samsung
 * Notes folgt in Stufe 2; die Ablage steht bereits, damit die Dart-Seite
 * dann unverändert bleibt.
 *
 * JSON statt Trennzeichen, weil Notizen beliebigen Text enthalten dürfen —
 * ein Trennzeichen wäre irgendwann Teil einer Notiz und würde sie zerreißen.
 */
object MemoInbox {
    private const val PREFS = "axiom_memos"
    private const val KEY = "pending"

    @Synchronized
    fun add(context: Context, text: String) {
        if (text.isBlank()) return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val array = JSONArray(prefs.getString(KEY, "[]"))
        array.put(text)
        // `commit`, nicht `apply`: Der Schreiber ist oft ein Receiver oder
        // eine Kachel, deren Prozess unmittelbar danach beendet werden darf.
        // `apply` schreibt im Hintergrund — und was dann noch im Puffer
        // liegt, ist weg.
        prefs.edit().putString(KEY, array.toString()).commit()
    }

    /**
     * Gibt die wartenden Notizen zurück — **ohne** sie zu löschen.
     *
     * Vorher gab es hier ein `drain`, das in einem Zug las und leerte. Das
     * ist genau ein Schritt zu früh: Die Dart-Seite speichert erst danach,
     * und schlägt das fehl — Zeitüberschreitung des Kanals, Prozessende,
     * geschlossene Datenbank —, ist der Gedanke weg. Ohne Meldung, denn
     * `pullPendingMemos` gibt bei jedem Fehler eine leere Liste zurück.
     *
     * Zwischen Einfall und Notiz liegen wenige Sekunden, und was in dieser
     * Zeit nicht sicher liegt, ist verloren [D9]. Deshalb erst bestätigen,
     * dann löschen.
     */
    @Synchronized
    fun peek(context: Context): List<String> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val array = JSONArray(prefs.getString(KEY, "[]"))
        return (0 until array.length()).map { array.getString(it) }
    }

    /**
     * Entfernt die ersten [count] Notizen — die, die bestätigt wurden.
     *
     * Nicht alles: Zwischen `peek` und `ack` kann eine neue Notiz
     * dazugekommen sein, und die wurde nie gespeichert.
     */
    @Synchronized
    fun ack(context: Context, count: Int): Int {
        if (count <= 0) return 0
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val array = JSONArray(prefs.getString(KEY, "[]"))
        val rest = JSONArray()
        for (i in count until array.length()) rest.put(array.getString(i))
        prefs.edit().putString(KEY, rest.toString()).commit()
        return minOf(count, array.length())
    }
}
