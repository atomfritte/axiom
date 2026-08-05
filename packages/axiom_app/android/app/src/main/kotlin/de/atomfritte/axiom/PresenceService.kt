package de.atomfritte.axiom

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
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

        const val ACTION_START = "de.atomfritte.axiom.PRESENCE_START"
        const val ACTION_STOP = "de.atomfritte.axiom.PRESENCE_STOP"
        const val ACTION_UPDATE = "de.atomfritte.axiom.PRESENCE_UPDATE"
        const val ACTION_QUICK_CAPTURE = "de.atomfritte.axiom.QUICK_CAPTURE"

        const val KEY_TEXT = "axiom_quick_text"

        private const val PREFS = "axiom_presence"

        /**
         * Startet die Anzeige und sagt, wenn es nicht geklappt hat.
         *
         * Frueher gab das nichts zurueck. Der Schalter sprang dann kommentarlos
         * zurueck, und von aussen war nicht zu unterscheiden, ob die
         * Berechtigung fehlt, das System den Dienst ablehnt oder AXIOM kaputt
         * ist.
         */
        fun start(context: Context, headline: String, detail: String): Map<String, Any?> {
            // Der Kanal einzeln abgeschaltet ist der haeufigste Fall, in dem
            // alles „an" aussieht und trotzdem nichts erscheint.
            createChannel(context)
            val channel = context.getSystemService(NotificationManager::class.java)
                .getNotificationChannel(CHANNEL)
            if (channel != null &&
                channel.importance == NotificationManager.IMPORTANCE_NONE
            ) {
                // Nur der Schluessel: Den Satz baut die Dart-Seite, die
                // kennt die gewaehlte Sprache.
                return mapOf("ok" to false, "reason" to "reason.presence.channel")
            }

            if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) {
                return mapOf(
                    "ok" to false,
                    "reason" to "reason.presence.notifications",
                )
            }

            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString("headline", headline)
                .putString("detail", detail)
                .putBoolean("enabled", true)
                .apply()

            val intent = Intent(context, PresenceService::class.java)
                .setAction(ACTION_START)
            return try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                mapOf("ok" to true)
            } catch (e: Throwable) {
                // Zuruecknehmen, sonst behauptet die Einstellung etwas, das
                // nicht laeuft.
                context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                    .putBoolean("enabled", false)
                    .apply()
                mapOf(
                    "ok" to false,
                    "reason" to "reason.presence.refused",
                    "reasonArgs" to listOf(e.javaClass.simpleName),
                )
            }
        }

        /**
         * Haengt die Benachrichtigung wirklich im Schacht?
         *
         * Der gespeicherte Schalter sagt nur, was gewollt war. Ob es auch
         * passiert ist, weiss allein das System.
         */
        fun isActive(context: Context): Boolean {
            val visible = try {
                context.getSystemService(NotificationManager::class.java)
                    .activeNotifications.any { it.id == NOTIFICATION_ID }
            } catch (e: Throwable) {
                false
            }
            // Beides zaehlt. `startForeground` ohne Ausnahme heisst: Der
            // Dienst laeuft. Der Schacht ist die zweite Bestaetigung, aber
            // nicht die einzige — ein aufgeschobenes Anzeigen darf hier nicht
            // als Fehlschlag durchgehen.
            return visible ||
                context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .getBoolean("service_running", false)
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

        private fun note(context: Context, running: Boolean, error: String?) {
            val edit = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putBoolean("service_running", running)
            if (error == null) edit.remove("last_error") else edit.putString("last_error", error)
            edit.apply()
        }

        /**
         * Jeder Schritt einzeln — statt eines „geht nicht".
         *
         * Der Schalter kann aus fuenf Gruenden aus bleiben, und vier davon
         * kann nur das System beantworten. Sie hier alle zu zeigen ist
         * billiger als jedes Mal zu raten.
         */
        fun diagnosis(context: Context): Map<String, Any?> {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val manager = context.getSystemService(NotificationManager::class.java)
            val channel = try {
                manager.getNotificationChannel(CHANNEL)
            } catch (e: Throwable) {
                null
            }
            return mapOf(
                "wanted" to prefs.getBoolean("enabled", false),
                "serviceRunning" to prefs.getBoolean("service_running", false),
                "notificationVisible" to isActive(context),
                "notificationsEnabled" to
                    NotificationManagerCompat.from(context).areNotificationsEnabled(),
                "channelExists" to (channel != null),
                "channelImportance" to (channel?.importance ?: -1),
                "lastError" to prefs.getString("last_error", null),
            )
        }

        fun isEnabled(context: Context): Boolean =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean("enabled", false)

        fun createChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val channel = android.app.NotificationChannel(
                CHANNEL,
                AxiomTexts.get(context, "channel.presence.name"),
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = AxiomTexts.get(context, "channel.presence.description")
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
            context.getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        // Wer den Dienst wegraeumt — Akkuoptimierung, Speicherdruck, der
        // Nutzer selbst — hinterlaesst sonst keine Spur.
        note(this, running = false, error = null)
        super.onDestroy()
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
                // Scheitert das hier, sah man frueher nur einen Schalter, der
                // zurueckspringt. Die Ausnahme ist die einzige Stelle, an der
                // das System den Grund nennt — sie wird aufgehoben.
                try {
                    startForeground(NOTIFICATION_ID, buildNotification())
                    note(this, running = true, error = null)
                } catch (e: Throwable) {
                    // Roh, wie das System es meldet, und ohne eigenen Satz
                    // drumherum: Diese Zeile ist eine Aussage von Android,
                    // keine von AXIOM — und damit auch nichts, was in einer
                    // Sprache stehen muesste.
                    note(
                        this,
                        running = false,
                        error = e.message
                            ?.let { "${e.javaClass.simpleName}: $it" }
                            ?: e.javaClass.simpleName,
                    )
                    stopSelf()
                    return START_NOT_STICKY
                }
            }
        }
        // Nach einem Prozessende neu starten: Eine Praesenz, die nach dem
        // ersten Speicherdruck verschwindet, ist keine.
        return START_STICKY
    }

    private fun buildNotification(): Notification {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val headline = prefs.getString("headline", null)
            ?: AxiomTexts.get(this, "presence.headline")
        val detail = prefs.getString("detail", null)
            ?: AxiomTexts.get(this, "presence.detail")

        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        // Direkt in der Benachrichtigung tippen. Der Kern des Ganzen:
        // kein Entsperren, kein App-Start, kein Kontextwechsel [D9].
        val remoteInput = RemoteInput.Builder(KEY_TEXT)
            .setLabel(AxiomTexts.get(this, "presence.input"))
            .build()

        val captureIntent = PendingIntent.getBroadcast(
            this, 1,
            Intent(this, QuickCaptureReceiver::class.java)
                .setAction(ACTION_QUICK_CAPTURE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )

        val captureAction = NotificationCompat.Action.Builder(
            android.R.drawable.ic_menu_edit,
            AxiomTexts.get(this, "presence.capture"),
            captureIntent,
        )
            .addRemoteInput(remoteInput)
            .setAllowGeneratedReplies(false)
            .build()

        val checkinIntent = PendingIntent.getActivity(
            this, 2,
            Intent(this, MainActivity::class.java)
                .setAction("de.atomfritte.axiom.CHECKIN")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(headline)
            .setContentText(detail)
            .setContentIntent(open)
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            // Ohne das haelt Android ab 12 die Benachrichtigung eines
            // Vordergrunddienstes mit niedriger Wichtigkeit bis zu zehn
            // Sekunden zurueck. Fuer eine Praesenz, die sofort da sein soll,
            // ist das ein Fehler — und fuer jede Pruefung „haengt sie?"
            // innerhalb dieser zehn Sekunden ein falsches Nein.
            .setForegroundServiceBehavior(
                NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE
            )
            // Auf dem Sperrbildschirm vollstaendig sichtbar: Der Zeitanker
            // nuetzt nur, wenn man ihn ohne Entsperren lesen kann [D4].
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .addAction(captureAction)
            .addAction(
                android.R.drawable.ic_menu_agenda,
                AxiomTexts.get(this, "presence.checkin"),
                checkinIntent,
            )

        if (Build.VERSION.SDK_INT >= 36) {
            // Die naechste Handlung als Pille neben der Uhr und in Samsungs
            // Now Bar. Es gibt keine eigene Samsung-Schnittstelle dafuer —
            // One UI 8 fuellt die Now Bar aus genau diesen Live Updates.
            //
            // Das System entscheidet, ob es die Bitte annimmt: Die Regel
            // ist auf zeitlich begrenzte, selbst gestartete Vorgaenge
            // zugeschnitten, und eine dauerhafte Anzeige ist das nicht.
            // Deshalb wird hier gebeten, nicht behauptet — und der
            // Systemcheck sagt, was daraus geworden ist.
            builder.setRequestPromotedOngoing(true)
            // Was in die Pille Platz hat. Wenige Zeichen, kein Satz.
            builder.setShortCriticalText(AxiomTexts.get(this, "presence.short"))
        }

        return builder.build()
    }
}
