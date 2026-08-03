package de.axiom.axiom_app

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

    fun add(context: Context, text: String) {
        if (text.isBlank()) return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val array = JSONArray(prefs.getString(KEY, "[]"))
        array.put(text)
        prefs.edit().putString(KEY, array.toString()).apply()
    }

    /** Gibt alle wartenden Notizen zurück und leert die Ablage. */
    fun drain(context: Context): List<String> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val array = JSONArray(prefs.getString(KEY, "[]"))
        prefs.edit().remove(KEY).apply()
        return (0 until array.length()).map { array.getString(it) }
    }
}
