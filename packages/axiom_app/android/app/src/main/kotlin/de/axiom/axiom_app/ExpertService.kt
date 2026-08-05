package de.axiom.axiom_app

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Zeigt an, dass der Expertenmodus läuft — und hält ihn am Leben.
 *
 * **Warum ein Vordergrunddienst.** Der Server selbst liegt in Dart, im
 * Prozess der App. Wer am Rechner arbeitet, hat das Telefon in der Tasche;
 * Android räumt eine App im Hintergrund nach Belieben ab, und mit ihr wäre
 * der Server mitten im Tippen weg. Der Dienst verhindert das.
 *
 * **Warum die Benachrichtigung nicht wegwischbar ist.** Ein offener Port mit
 * Gesundheitsdaten ist ein Zustand, den man sehen muss. Das ist hier kein
 * Ärgernis, sondern die einzige ehrliche Anzeige — samt Adresse und einem
 * Knopf, der ihn beendet.
 */
class ExpertService : Service() {

    companion object {
        const val CHANNEL = "axiom_expert"
        const val NOTIFICATION_ID = 4713

        const val ACTION_START = "de.axiom.EXPERT_START"
        const val ACTION_STOP = "de.axiom.EXPERT_STOP"

        private const val PREFS = "axiom_expert"

        fun start(context: Context, address: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString("address", address)
                .putBoolean("running", true)
                .apply()

            val intent = Intent(context, ExpertService::class.java)
                .setAction(ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putBoolean("running", false)
                .apply()
            try {
                context.startService(
                    Intent(context, ExpertService::class.java).setAction(ACTION_STOP)
                )
            } catch (e: Throwable) {
                // Laeuft nicht mehr — dann ist nichts zu stoppen.
            }
        }

        fun isRunning(context: Context): Boolean =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean("running", false)

        fun createChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val channel = android.app.NotificationChannel(
                CHANNEL,
                AxiomTexts.get(context, "channel.expert.name"),
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = AxiomTexts.get(context, "channel.expert.description")
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
            context.getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP || !isRunning(this)) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        createChannel(this)
        startForeground(NOTIFICATION_ID, build())
        // Bewusst NICHT sticky: Ein Server, der sich nach einem Prozessende
        // von selbst wieder oeffnet, waere genau das, was ADR-0005
        // ausschliesst — er geht nur auf Kommando an.
        return START_NOT_STICKY
    }

    private fun build(): Notification {
        val address = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString("address", null) ?: ""

        val stop = PendingIntent.getActivity(
            this, 5,
            Intent(this, MainActivity::class.java)
                .setAction(ACTION_STOP)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(AxiomTexts.get(this, "expert.title"))
            .setContentText(address)
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    "$address\n\n" + AxiomTexts.get(this, "expert.detail")
                )
            )
            .setContentIntent(stop)
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(false)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                AxiomTexts.get(this, "expert.stop"),
                stop,
            )
            .build()
    }
}
