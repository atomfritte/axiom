package de.atomfritte.axiom

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.RemoteInput

/**
 * Nimmt Text entgegen, der direkt in der Benachrichtigung getippt wurde.
 *
 * Der ganze Punkt: Zwischen Einfall und Notiz liegen zwei Sekunden statt
 * zehn. Kein Entsperren, kein App-Start, kein Kontextwechsel — und genau
 * in diesen Sekunden geht der Gedanke sonst verloren [D9].
 *
 * Die App muss dafür nicht laufen. Der Text landet in [MemoInbox] und wird
 * beim nächsten Start eingesammelt.
 */
class QuickCaptureReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val text = RemoteInput.getResultsFromIntent(intent)
            ?.getCharSequence(PresenceService.KEY_TEXT)
            ?.toString()
            ?.trim()

        if (!text.isNullOrEmpty()) {
            MemoInbox.add(context, text)
            // Rueckmeldung in der Benachrichtigung selbst: Ohne sie weiss
            // man nicht, ob es angekommen ist — und tippt es nochmal.
            PresenceService.update(
                context,
                AxiomTexts.get(context, "presence.saved"),
                if (text.length > 40) "${text.take(40)}…" else text,
            )
        }
    }
}
