package de.axiom.axiom_app

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Brücke zu Android-Systemfunktionen, die Flutter nicht abdeckt.
 *
 * Kernpunkt sind exakte Alarme. Zeitgetriggerte Interventionen haben bei
 * diesem Nutzerprofil die höchste Befolgungsrate — Pünktlichkeit gilt auch
 * gegenüber der App [D4]. Deshalb `setExactAndAllowWhileIdle` statt
 * WorkManager: WorkManager bündelt Aufwachvorgänge und ist für Zeitanker
 * unbrauchbar.
 */
class MainActivity : FlutterActivity() {

    companion object {
        const val CHANNEL = "de.axiom/system"

        data class ChannelSpec(val id: String, val name: String, val importance: Int)

        /**
         * Ein Benachrichtigungskanal je Eingriffstiefe.
         * Sonst kann der Nutzer nur alles oder nichts stummschalten — und
         * schaltet im Zweifel alles stumm.
         */
        val CHANNELS = listOf(
            ChannelSpec("axiom_info", "Hinweise", NotificationManager.IMPORTANCE_MIN),
            ChannelSpec("axiom_nudge", "Leise Anstöße", NotificationManager.IMPORTANCE_LOW),
            ChannelSpec("axiom_intervene", "Interventionen", NotificationManager.IMPORTANCE_DEFAULT),
            ChannelSpec("axiom_enforce", "Verbindliche Regeln", NotificationManager.IMPORTANCE_HIGH),
        )

        fun createChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java)
            CHANNELS.forEach { spec ->
                val channel = NotificationChannel(spec.id, spec.name, spec.importance)
                channel.description = when (spec.id) {
                    "axiom_info" -> "Erscheint nur im Rückblick."
                    "axiom_nudge" -> "Still, wegwischbar."
                    "axiom_intervene" -> "Sichtbar, erwartet eine Antwort."
                    else -> "Nur für Regeln, die du selbst verbindlich gesetzt hast."
                }
                // Nur die verbindliche Stufe darf Ruhezeiten durchbrechen.
                channel.setBypassDnd(spec.id == "axiom_enforce")
                manager.createNotificationChannel(channel)
            }
        }
    }

    /**
     * Health Connect liest asynchron. Der Scope haengt an der Activity,
     * damit ein laufender Lesevorgang beim Schliessen nicht weiterlaeuft.
     */
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    /** Neuer Intent bei bereits laufender App (singleTop). */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createChannels(this)
        PresenceService.createChannel(this)
        LiveSlotService.createChannel(this)
        // Muss bei jedem Start erneut angemeldet werden: Das System raeumt
        // langlebige Shortcuts auf, wenn die App laenger nicht lief.
        ShareTargets.publish(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "permissionStatus" -> result.success(permissionStatus())

                    "requestExactAlarm" -> result.success(requestExactAlarm())

                    "requestNotifications" -> result.success(requestNotifications())

                    "requestIgnoreBatteryOptimizations" ->
                        result.success(requestIgnoreBatteryOptimizations())

                    "scheduleExact" -> result.success(
                        AlarmScheduler.schedule(
                            context = this,
                            id = call.argument<Int>("id") ?: 0,
                            atMillis = call.argument<Long>("atMillis") ?: 0L,
                            title = call.argument<String>("title").orEmpty(),
                            body = call.argument<String>("body").orEmpty(),
                            channel = call.argument<String>("channel") ?: "axiom_nudge",
                        )
                    )

                    "cancelAlarm" -> result.success(
                        AlarmScheduler.cancel(this, call.argument<Int>("id") ?: 0)
                    )

                    "lastAlarmDriftMillis" -> result.success(
                        AlarmScheduler.lastDriftMillis(this)
                    )

                    "updateWidget" -> {
                        AxiomWidgetProvider.publish(
                            context = this,
                            headline = call.argument<String>("headline").orEmpty(),
                            detail = call.argument<String>("detail").orEmpty(),
                            capacity = call.argument<Int>("capacity") ?: 0,
                        )
                        result.success(true)
                    }

                    "broadcast" -> {
                        // Samsung "Modi und Routinen" kann darauf reagieren.
                        // Bewusst über Routinen statt direkter APIs: Der Nutzer
                        // sieht und ändert die Automation selbst (G2).
                        val action = call.argument<String>("action").orEmpty()
                        if (action.isNotEmpty()) sendBroadcast(Intent(action))
                        result.success(true)
                    }

                    "pullPendingMemos" -> result.success(MemoInbox.drain(this))

                    // Dauerhafte Anzeige im Benachrichtigungsbereich.
                    "presenceStart" -> {
                        PresenceService.start(
                            this,
                            call.argument<String>("headline").orEmpty(),
                            call.argument<String>("detail").orEmpty(),
                        )
                        result.success(true)
                    }

                    "presenceUpdate" -> {
                        PresenceService.update(
                            this,
                            call.argument<String>("headline").orEmpty(),
                            call.argument<String>("detail").orEmpty(),
                        )
                        result.success(true)
                    }

                    "presenceStop" -> {
                        PresenceService.stop(this)
                        result.success(true)
                    }

                    "presenceEnabled" ->
                        result.success(PresenceService.isEnabled(this))

                    // ── Laufender Slot als Live Update ──────────────────
                    "liveSlotStart" -> {
                        LiveSlotService.start(
                            context = this,
                            kind = call.argument<String>("kind") ?: "focus",
                            title = call.argument<String>("title").orEmpty(),
                            detail = call.argument<String>("detail").orEmpty(),
                            startedAtMillis = call.argument<Long>("startedAtMillis")
                                ?: System.currentTimeMillis(),
                            plannedMinutes = call.argument<Int>("plannedMinutes") ?: 50,
                        )
                        result.success(true)
                    }

                    "liveSlotStop" -> {
                        LiveSlotService.stop(this)
                        result.success(true)
                    }

                    "liveSlotRunning" ->
                        result.success(LiveSlotService.isRunning(this))

                    // Ob das Geraet Live Updates befoerdert. Die Oberflaeche
                    // verspricht sonst eine Pille, die nie erscheint.
                    "liveSlotPromotable" ->
                        result.success(LiveSlotService.isPromotable())

                    // ── Health Connect ──────────────────────────────────
                    "healthStatus" -> result.success(HealthBridge.status(this))

                    "healthRequestPermissions" ->
                        result.success(HealthBridge.requestPermissions(this))

                    "healthRead" -> {
                        val since = call.argument<Long>("sinceMillis") ?: 0L
                        scope.launch {
                            val records = try {
                                HealthBridge.read(this@MainActivity, since)
                            } catch (e: Throwable) {
                                emptyList()
                            }
                            result.success(records)
                        }
                    }

                    "healthOpenSettings" -> {
                        result.success(openHealthSettings())
                    }

                    "pendingSharedText" -> result.success(consumeSharedText())

                    "launchAction" -> result.success(consumeLaunchAction())

                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Wie die App gestartet wurde: über die Schnelleinstellung, einen
     * Shortcut oder normal. Wird einmal gelesen und dann geleert, damit
     * das Erfassungsblatt nicht bei jedem Zurückkommen erneut aufgeht.
     */
    private fun consumeLaunchAction(): String? {
        val action = intent?.action ?: return null
        if (action !in setOf(
                "de.axiom.CAPTURE",
                "de.axiom.CHECKIN",
                "de.axiom.FOCUS",
                "de.axiom.SENSATION",
            )
        ) return null
        intent.action = Intent.ACTION_MAIN
        return action
    }

    /**
     * Text, den eine andere App geteilt oder der Assistent diktiert hat,
     * oder eine Vorbelegung aus der Stift-Schnittstelle [D9].
     */
    private fun consumeSharedText(): String? {
        val action = intent?.action ?: return null
        val relevant = action == Intent.ACTION_SEND ||
            action == "de.axiom.CAPTURE" ||
            action == Intent.ACTION_VIEW
        if (!relevant) return null

        // Drei Quellen, drei Schluessel:
        //   EXTRA_TEXT  -- Teilen aus anderen Apps
        //   "text"      -- der Assistent; so ist der Parameter in
        //                  shortcuts.xml gebunden (noteDigitalDocument.text)
        //   ?text=      -- axiom://-Link, etwa aus einer Bixby-Routine
        // Faellt einer davon aus, geht das Diktat verloren und der Kanal
        // taeuscht Funktion vor.
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
            ?: intent.getStringExtra("text")
            ?: intent.data?.getQueryParameter("text")
        intent.removeExtra(Intent.EXTRA_TEXT)
        intent.removeExtra("text")
        return text?.takeIf { it.isNotBlank() }
    }

    private fun permissionStatus(): Map<String, Boolean> {
        val alarms = getSystemService(AlarmManager::class.java)
        val power = getSystemService(PowerManager::class.java)
        return mapOf(
            "exactAlarm" to (
                Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                    alarms.canScheduleExactAlarms()
                ),
            "notifications" to
                NotificationManagerCompat.from(this).areNotificationsEnabled(),
            "batteryUnrestricted" to
                power.isIgnoringBatteryOptimizations(packageName),
        )
    }

    private fun requestExactAlarm(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val alarms = getSystemService(AlarmManager::class.java)
        if (alarms.canScheduleExactAlarms()) return true
        startActivity(
            Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                .setData(Uri.parse("package:$packageName"))
        )
        return false
    }

    private fun requestNotifications(): Boolean {
        if (NotificationManagerCompat.from(this).areNotificationsEnabled()) return true
        startActivity(
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        )
        return false
    }

    /**
     * Systemeinstellungen von Health Connect. Der Nutzer entzieht dort
     * einzelne Freigaben — deshalb muss der Weg dahin sichtbar sein und
     * nicht nur der Weg hinein.
     */
    private fun openHealthSettings(): Boolean = try {
        startActivity(
            Intent(androidx.health.connect.client.HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS)
        )
        true
    } catch (e: Throwable) {
        false
    }

    private fun requestIgnoreBatteryOptimizations(): Boolean {
        val power = getSystemService(PowerManager::class.java)
        if (power.isIgnoringBatteryOptimizations(packageName)) return true
        startActivity(
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                .setData(Uri.parse("package:$packageName"))
        )
        return false
    }
}

/**
 * Plant und prüft exakte Alarme.
 *
 * Enthält einen Selbsttest: Die tatsächliche Feuerzeit wird protokolliert,
 * damit Drift sichtbar wird. Ein stiller Ausfall wäre schlimmer als ein
 * lauter — man verlässt sich sonst auf eine Erinnerung, die nie kommt (R4).
 */
object AlarmScheduler {
    private const val PREFS = "axiom_alarms"
    private const val KEY_DRIFT = "last_drift_ms"

    fun schedule(
        context: Context,
        id: Int,
        atMillis: Long,
        title: String,
        body: String,
        channel: String,
    ): Boolean {
        val alarms = context.getSystemService(AlarmManager::class.java)
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra("id", id)
            putExtra("title", title)
            putExtra("body", body)
            putExtra("channel", channel)
            putExtra("plannedAt", atMillis)
        }
        val pending = PendingIntent.getBroadcast(
            context, id, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                !alarms.canScheduleExactAlarms()
            ) {
                // Ohne Freigabe lieber ungenau als gar nicht. Den Zustand
                // zeigt der Systemscreen an, damit die Lücke sichtbar bleibt.
                alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pending)
                false
            } else {
                alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pending)
                true
            }
        } catch (e: SecurityException) {
            false
        }
    }

    fun cancel(context: Context, id: Int): Boolean {
        val alarms = context.getSystemService(AlarmManager::class.java)
        val pending = PendingIntent.getBroadcast(
            context, id,
            Intent(context, AlarmReceiver::class.java),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return false
        alarms.cancel(pending)
        pending.cancel()
        return true
    }

    fun recordDrift(context: Context, plannedAt: Long, firedAt: Long) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_DRIFT, firedAt - plannedAt)
            .apply()
    }

    fun lastDriftMillis(context: Context): Long =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getLong(KEY_DRIFT, 0L)
}
