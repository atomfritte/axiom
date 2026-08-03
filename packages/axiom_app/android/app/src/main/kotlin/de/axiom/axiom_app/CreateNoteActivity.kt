package de.axiom.axiom_app

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * Antwort auf `ACTION_CREATE_NOTE` — die offizielle Stift-Schnittstelle
 * seit Android 14.
 *
 * Damit erscheint AXIOM dort, wo das System nach einer Notiz-App fragt:
 * beim Doppeltipp mit dem Stift, über die Schnelleinstellung „Notiz",
 * und auf dem Sperrbildschirm.
 *
 * **Warum nicht direkt Samsung Notes anzapfen:** Screen-off-Memos landen in
 * Samsung Notes, und dafür gibt es keine öffentliche Schnittstelle. Der
 * Systemweg ist der einzige, der ohne Reverse Engineering funktioniert und
 * ein Update überlebt. Zusätzlich lässt sich diese Activity in Samsungs
 * Air-Command-Menue als Verknuepfung eintragen. Air Actions — der
 * Stiftknopf als Fernbedienung — gibt es auf dem S25 Ultra nicht: Dessen
 * Stift hat kein Bluetooth Low Energy.
 */
class CreateNoteActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Vorbelegter Text, falls das System einen mitschickt. Assistenten
        // legen ihn unter "text" ab, Teilen-Aufrufe unter EXTRA_TEXT.
        val prefill = intent?.getStringExtra(Intent.EXTRA_TEXT)
            ?: intent?.getStringExtra("text")

        startActivity(
            Intent(this, MainActivity::class.java)
                .setAction("de.axiom.CAPTURE")
                .apply { if (!prefill.isNullOrBlank()) putExtra(Intent.EXTRA_TEXT, prefill) }
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
        )
        finish()
    }
}
