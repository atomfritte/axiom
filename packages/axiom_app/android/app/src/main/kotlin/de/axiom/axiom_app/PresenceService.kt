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
import androidx.core.app.RemoteInput

/**
 * Dauerhafte Präsenz im Benachrichtigungsbereich.
 *
 * Zwei Gründe, warum das mehr ist als ein hübsches Extra:
 *
 * **Sichtbarkeit.** Was nicht sichtbar ist, existiert für dieses Profil
 * nicht [D9]. Ein Homescreen-Widget hilft nur, wenn man auf dem Homescreen
 * ist. Diese Benachrichtigung steht überall — auch auf dem Sperrbildschirm.
 * (Lockscreen-*Widgets* gibt es auf Android seit 5.0 nicht mehr; die
 * dauerhafte Benachrichtigung ist der verbliebene Weg.)
 *
 * **Erfassung ohne Kontextwechsel.** Über `RemoteInput` lässt sich direkt
 * aus der Benachrichtigung tippen — ohne Entsperren, ohne App-Start, ohne
 * die laufende Tätigkeit zu verlassen. Zwischen Einfall und Notiz liegen
 * damit zwei Sekunden statt zehn, und genau in diesen Sekunden geht der
 * Gedanke sonst verloren.
 *
 * Der Kanal ist stumm und ohne Abzeichen: Präsenz soll nicht stören.
 */
class PresenceService : Service() {

    companion object {
        const val CHANNEL = "axiom_presence"
        const val NOTIFICATION_ID = 4711

        const val ACTION_START = "de.axiom.PRESENCE_START"
        const val ACTION_STOP = "de.axiom.PRESENCE_STOP"
        const val ACTION_UPDATE = "de.axiom.PRESENCE_UPDATE"
        const val ACTION_QUICK_CAPTURE = "de.axiom.QUICK_CAPTURE"

        const val KEY_TEXT = "axiom_quick_text"

        private const val PREFS = "axiom_presence"

        fun start(context: Context, headline: String, detail: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString("headline", headline)
                .putString("detail", detail)
                .putBoolean("enabled", true)
                .apply()

            val intent = Intent(context, PresenceService::class.java)
                .setAction(ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun update(context: Context, headline: String, detail: String) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (!prefs.getBoolean("enabled", false)) return
            prefs.edit()
                .putString("headline", headline)
                .putString("detail", detail)
                .apply()
            // Ab Android 8 wirft startService aus dem Hintergrund, wenn der
            // Dienst nicht schon laeuft — etwa nachdem das System den Prozess
            // beendet hat. Der Text ist dann beim naechsten Start wieder da;
            // ein Absturz waere der teurere Weg dorthin.
            try {
                context.startService(
                    Intent(context, PresenceService::class.java).setAction(ACTION_UPDATE)
                )
            } catch (e: Throwable) {
                // Naechster Vordergrundstart holt es nach.
            }
        }

        fun stop(context: Context) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putBoolean("enabled", false)
                .apply()
            try {
                context.startService(
                    Intent(context, PresenceService::class.java).setAction(ACTION_STOP)
                )
            } catch (e: Throwable) {
                // Laeuft nicht mehr — dann ist nichts zu stoppen.
            }
        }

        fun isEnabled(context: Context): Boolean =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean("enabled", false)

        fun createChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val channel = android.app.NotificationChannel(
                CHANNEL,
                "Dauerhafte Anzeige",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Zeigt die nächste Handlung. Still, ohne Ton."
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
        when (intent?.action) {
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                createChannel(this)
                startForeground(NOTIFICATION_ID, buildNotification())
            }
        }
        // Nach einem Prozessende neu starten: Eine Praesenz, die nach dem
        // ersten Speicherdruck verschwindet, ist keine.
        return START_STICKY
    }

    private fun buildNotification(): Notification {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val headline = prefs.getString("headline", null) ?: "AXIOM"
        val detail = prefs.getString("detail", null) ?: "Tippen zum Erfassen"

        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        // Direkt in der Benachrichtigung tippen. Der Kern des Ganzen:
        // kein Entsperren, kein App-Start, kein Kontextwechsel [D9].
        val remoteInput = RemoteInput.Builder(KEY_TEXT)
            .setLabel("Was ist dir eingefallen?")
            .build()

        val captureIntent = PendingIntent.getBroadcast(
            this, 1,
            Intent(this, QuickCaptureReceiver::class.java)
                .setAction(ACTION_QUICK_CAPTURE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )

        val captureAction = NotificationCompat.Action.Builder(
            android.R.drawable.ic_menu_edit,
            "Erfassen",
            captureIntent,
        )
            .addRemoteInput(remoteInput)
            .setAllowGeneratedReplies(false)
            .build()

        val checkinIntent = PendingIntent.getActivity(
            this, 2,
            Intent(this, MainActivity::class.java)
                .setAction("de.axiom.CHECKIN")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(headline)
            .setContentText(detail)
            .setContentIntent(open)
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            // Auf dem Sperrbildschirm vollstaendig sichtbar: Der Zeitanker
            // nuetzt nur, wenn man ihn ohne Entsperren lesen kann [D4].
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .addAction(captureAction)
            .addAction(
                android.R.drawable.ic_menu_agenda,
                "Check-in",
                checkinIntent,
            )
            .build()
    }
}
