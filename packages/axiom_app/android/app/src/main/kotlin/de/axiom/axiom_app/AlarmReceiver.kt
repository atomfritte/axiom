package de.axiom.axiom_app

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat

/**
 * Empfängt exakte Alarme und zeigt die Intervention an.
 *
 * Protokolliert dabei die Abweichung zwischen geplanter und tatsächlicher
 * Feuerzeit. Auf Samsung-Geräten mit aktiver Akkuoptimierung kann diese
 * Drift erheblich sein — und weil unzuverlässige Zeittrigger das gesamte
 * Konzept entwerten, muss sie sichtbar werden statt still zu bleiben (R4).
 */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("id", 0)
        val plannedAt = intent.getLongExtra("plannedAt", 0L)
        if (plannedAt > 0) {
            AlarmScheduler.recordDrift(context, plannedAt, System.currentTimeMillis())
        }

        val channel = intent.getStringExtra("channel") ?: "axiom_nudge"
        val title = intent.getStringExtra("title").orEmpty()
        val body = intent.getStringExtra("body").orEmpty()

        MainActivity.createChannels(context)

        val open = PendingIntent.getActivity(
            context, id,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, channel)
            .setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(open)
            .setAutoCancel(true)
            // Keine Sammelmeldungen: eine Benachrichtigung, eine Handlung (G1).
            .setOnlyAlertOnce(true)
            .build()

        context.getSystemService(NotificationManager::class.java)
            .notify(id, notification)

        // Tagesanker sind wiederkehrend — direkt für morgen neu setzen.
        if (id in 1..3) {
            AlarmScheduler.schedule(
                context = context,
                id = id,
                atMillis = plannedAt + 24 * 60 * 60 * 1000L,
                title = title,
                body = body,
                channel = channel,
            )
        }
    }
}
