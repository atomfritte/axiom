package de.axiom.axiom_app

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Der laufende Slot als Live Update — Statusleisten-Pille, Sperrbildschirm
 * und Samsungs Now Bar.
 *
 * **Warum das mehr ist als eine hübschere Benachrichtigung.** Der teuerste
 * Fehlermodus im Fokus ist nicht das falsche Ziel, sondern der fehlende
 * Ausstieg [D6]: Die Sitzung läuft weiter, das Zeitgefühl fehlt [D4], und
 * bemerkt wird es erst, wenn etwas anderes bereits verpasst ist. Eine
 * Anzeige, die man erst öffnen muss, kommt dafür zu spät — sie setzt genau
 * die Selbstbeobachtung voraus, die im Zustand ausfällt.
 *
 * Ab Android 16 kann eine laufende Benachrichtigung um Beförderung bitten
 * (`requestPromotedOngoing`). Sie erscheint dann als Pille neben der Uhr,
 * auf dem Sperrbildschirm und in Samsungs Now Bar — sichtbar, ohne etwas
 * zu tun. Genau das ist der Zweck.
 *
 * Vor Android 16 bleibt eine gewöhnliche laufende Benachrichtigung mit
 * Countdown. Weniger prominent, aber nicht wirkungslos.
 *
 * **Kein Timer, der abläuft.** Die geplante Dauer ist ein Bezugspunkt, kein
 * Limit. Nach ihrem Ende zählt die Anzeige die Überziehung weiter — sachlich,
 * ohne Alarm und ohne Wertung (G3). Der Balken wechselt die Farbe, mehr
 * nicht.
 */
class LiveSlotService : Service() {

    companion object {
        const val CHANNEL = "axiom_live"
        const val NOTIFICATION_ID = 4712

        const val ACTION_START = "de.axiom.LIVE_START"
        const val ACTION_STOP = "de.axiom.LIVE_STOP"

        private const val PREFS = "axiom_live"

        /** Wie oft die Anzeige neu geschrieben wird, solange ein Slot läuft. */
        private const val TICK_MS = 30_000L

        /**
         * Wie weit über die geplante Dauer hinaus der Balken noch Platz hat.
         * Danach steht er am Anschlag — die Zahl läuft weiter, der Balken
         * nicht. Ein Balken, der immer weiter wächst, sagt nichts mehr.
         */
        private const val OVERRUN_HEADROOM = 0.5

        private const val COLOR_CALM = 0xFF7FA88A.toInt()
        private const val COLOR_SIGNAL = 0xFFE8A33D.toInt()

        fun start(
            context: Context,
            kind: String,
            title: String,
            detail: String,
            startedAtMillis: Long,
            plannedMinutes: Int,
        ) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString("kind", kind)
                .putString("title", title)
                .putString("detail", detail)
                .putLong("startedAt", startedAtMillis)
                .putInt("plannedMin", plannedMinutes.coerceAtLeast(1))
                .putBoolean("running", true)
                .apply()

            val intent = Intent(context, LiveSlotService::class.java)
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
                    Intent(context, LiveSlotService::class.java).setAction(ACTION_STOP)
                )
            } catch (e: Throwable) {
                // Laeuft nicht mehr — dann ist nichts zu stoppen.
            }
        }

        fun isRunning(context: Context): Boolean =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean("running", false)

        /**
         * Ob das System Live Updates kennt. Die Oberfläche fragt das ab, um
         * nichts zu versprechen, was das Gerät nicht einlöst.
         */
        fun isPromotable(): Boolean = Build.VERSION.SDK_INT >= 36

        /**
         * Ob eine Benachrichtigung tatsächlich befördert wurde.
         *
         * Die Bitte um die Pille ist eine Bitte. Ob das System sie annimmt,
         * steht allein an der geposteten Benachrichtigung — und nur das ist
         * die Antwort auf „steht es oben?". Ohne diese Unterscheidung sagt
         * die App, Live Updates gingen, und der Nutzer sieht nichts.
         */
        fun isPromoted(context: Context, id: Int): Boolean {
            if (Build.VERSION.SDK_INT < 36) return false
            return try {
                val posted = context.getSystemService(NotificationManager::class.java)
                    .activeNotifications
                    .firstOrNull { it.id == id }
                    ?: return false
                posted.notification.flags and
                    android.app.Notification.FLAG_PROMOTED_ONGOING != 0
            } catch (e: Throwable) {
                false
            }
        }

        fun createChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val channel = android.app.NotificationChannel(
                CHANNEL,
                "Laufender Slot",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Fokus und Reiz-Slots, solange sie laufen. Still."
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
            context.getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private val tick = object : Runnable {
        override fun run() {
            if (!isRunning(this@LiveSlotService)) return
            NotificationManagerCompat.from(this@LiveSlotService)
                .notify(NOTIFICATION_ID, build())
            handler.postDelayed(this, TICK_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP || !isRunning(this)) {
            handler.removeCallbacks(tick)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        createChannel(this)
        startForeground(NOTIFICATION_ID, build())
        handler.removeCallbacks(tick)
        handler.postDelayed(tick, TICK_MS)
        // Ein laufender Slot, dessen Anzeige nach dem ersten Speicherdruck
        // verschwindet, waere schlimmer als keine Anzeige.
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        super.onDestroy()
    }

    private fun build(): Notification {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val kind = prefs.getString("kind", "focus") ?: "focus"
        val title = prefs.getString("title", null) ?: "Slot läuft"
        val detail = prefs.getString("detail", null).orEmpty()
        val startedAt = prefs.getLong("startedAt", System.currentTimeMillis())
        val plannedMin = prefs.getInt("plannedMin", 50).coerceAtLeast(1)

        val elapsedMin =
            ((System.currentTimeMillis() - startedAt) / 60_000L).toInt().coerceAtLeast(0)
        val remainingMin = plannedMin - elapsedMin
        val over = remainingMin < 0

        val stop = PendingIntent.getActivity(
            this, 3,
            Intent(this, MainActivity::class.java)
                .setAction(if (kind == "focus") "de.axiom.FOCUS" else "de.axiom.SENSATION")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(
                if (detail.isEmpty()) elapsedLabel(elapsedMin, plannedMin)
                else "$detail · ${elapsedLabel(elapsedMin, plannedMin)}"
            )
            .setContentIntent(stop)
            .setOngoing(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setColor(if (over) COLOR_SIGNAL else COLOR_CALM)
            .setColorized(true)
            // Zaehlt selbstaendig weiter, auch zwischen zwei Aktualisierungen.
            .setWhen(startedAt + plannedMin * 60_000L)
            .setUsesChronometer(true)
            .setChronometerCountDown(!over)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Beenden",
                stop,
            )

        if (Build.VERSION.SDK_INT >= 36) {
            // Der eigentliche Punkt: Pille neben der Uhr, Sperrbildschirm,
            // Now Bar. Das System darf ablehnen — dann bleibt es eine
            // gewoehnliche laufende Benachrichtigung.
            builder.setRequestPromotedOngoing(true)
            builder.setShortCriticalText(chipLabel(remainingMin))
            builder.setStyle(progressStyle(elapsedMin, plannedMin, over))
        }

        return builder.build()
    }

    /**
     * Zwei Abschnitte: die geplante Dauer, danach die Überziehung.
     * Der Farbwechsel ist die ganze Aussage — kein Text, kein Ausrufezeichen.
     */
    private fun progressStyle(
        elapsedMin: Int,
        plannedMin: Int,
        over: Boolean,
    ): NotificationCompat.ProgressStyle {
        val headroom = (plannedMin * OVERRUN_HEADROOM).toInt().coerceAtLeast(5)
        val total = plannedMin + headroom
        return NotificationCompat.ProgressStyle()
            .setProgressSegments(
                listOf(
                    NotificationCompat.ProgressStyle.Segment(plannedMin)
                        .setColor(COLOR_CALM),
                    NotificationCompat.ProgressStyle.Segment(headroom)
                        .setColor(COLOR_SIGNAL),
                )
            )
            .setProgress(elapsedMin.coerceIn(0, total))
            .setProgressTrackerIcon(
                androidx.core.graphics.drawable.IconCompat.createWithResource(
                    this, R.drawable.ic_notification,
                )
            )
            .setStyledByProgress(!over)
    }

    /** Was in die Pille passt — sehr wenig. Sieben Zeichen sind das Maximum. */
    private fun chipLabel(remainingMin: Int): String =
        if (remainingMin >= 0) "$remainingMin min" else "+${-remainingMin} min"

    private fun elapsedLabel(elapsedMin: Int, plannedMin: Int): String {
        val remaining = plannedMin - elapsedMin
        return if (remaining >= 0) {
            "noch $remaining von $plannedMin min"
        } else {
            // Sachlich, ohne Vorwurf: eine Zahl, keine Bewertung (G3, R7).
            "${-remaining} min über den Bezugspunkt"
        }
    }
}
