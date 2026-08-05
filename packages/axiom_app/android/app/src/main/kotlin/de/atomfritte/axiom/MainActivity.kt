package de.atomfritte.axiom

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.role.RoleManager
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.net.wifi.WifiManager
import android.provider.Settings
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

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
        const val CHANNEL = "de.atomfritte.axiom/system"

        const val REQ_NOTIFICATIONS = 8802
        const val REQ_NOTES_ROLE = 8803
        const val REQ_SPEECH = 8804

        /** [texts] ist der Schluesselpraefix in [AxiomTexts], nicht der Text. */
        data class ChannelSpec(val id: String, val texts: String, val importance: Int)

        /**
         * Ein Benachrichtigungskanal je Eingriffstiefe.
         * Sonst kann der Nutzer nur alles oder nichts stummschalten — und
         * schaltet im Zweifel alles stumm.
         */
        val CHANNELS = listOf(
            ChannelSpec("axiom_info", "channel.info", NotificationManager.IMPORTANCE_MIN),
            ChannelSpec("axiom_nudge", "channel.nudge", NotificationManager.IMPORTANCE_LOW),
            ChannelSpec("axiom_intervene", "channel.intervene", NotificationManager.IMPORTANCE_DEFAULT),
            ChannelSpec("axiom_enforce", "channel.enforce", NotificationManager.IMPORTANCE_HIGH),
        )

        /**
         * Legt die Kanaele an — und benennt sie um, wenn sie schon da sind.
         *
         * **Was `createNotificationChannel` bei einem vorhandenen Kanal
         * wirklich tut.** Nachgesehen, weil davon abhaengt, ob ein
         * Sprachwechsel ueberhaupt ankommt: Name, Beschreibung und Gruppe
         * werden uebernommen — die Dokumentation nennt den Sprachwechsel
         * ausdruecklich als den vorgesehenen Anlass dafuer. Die Wichtigkeit
         * nur, wenn sie *gesenkt* wird und der Nutzer den Kanal nicht selbst
         * angefasst hat. **Alles andere wird ignoriert**: Ton, Vibration,
         * Abzeichen, `setBypassDnd`. Wer also spaeter am Klangverhalten etwas
         * aendern will, braucht eine neue Kanal-ID; fuer Text genuegt dieser
         * Aufruf.
         */
        fun createChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java)
            CHANNELS.forEach { spec ->
                val channel = NotificationChannel(
                    spec.id,
                    AxiomTexts.get(context, "${spec.texts}.name"),
                    spec.importance,
                )
                channel.description =
                    AxiomTexts.get(context, "${spec.texts}.description")
                // Nur die verbindliche Stufe darf Ruhezeiten durchbrechen.
                // Wirkt ausschliesslich beim ersten Anlegen — siehe oben.
                channel.setBypassDnd(spec.id == "axiom_enforce")
                manager.createNotificationChannel(channel)
            }
        }

        /**
         * Schreibt die Kanaltexte neu, nachdem die App die Sprache geliefert
         * hat.
         *
         * Die Kanaele entstehen frueh — beim Start, nach einem Neustart, beim
         * ersten Alarm — und damit lange bevor Dart sagen kann, welche
         * Sprache gilt. Bis dahin greift `res/values(-de)/strings.xml`, also
         * die Sprache des Geraets. Sobald die App laeuft, gewinnt die in der
         * App gewaehlte.
         */
        fun renameChannels(context: Context) {
            createChannels(context)
            PresenceService.createChannel(context)
            LiveSlotService.createChannel(context)
            ExpertService.createChannel(context)
        }
    }

    /**
     * Health Connect liest asynchron. Der Scope haengt an der Activity,
     * damit ein laufender Lesevorgang beim Schliessen nicht weiterlaeuft.
     */
    /// Alles Health-Connect-Bezogene laeuft hier — und zwar **nicht** auf
    /// dem Hauptthread.
    ///
    /// `HealthConnectClient.getOrCreate` fragt den Paketmanager und baut eine
    /// Binder-Verbindung auf. Auf `Dispatchers.Main` blockiert das den
    /// UI-Thread; blockiert der, rendert Flutter nicht mehr und die App
    /// steht auf dem letzten gezeichneten Bild — einem Ladekreisel, der nie
    /// aufhoert. Genau dieser Ausfall ist von aussen nicht von einem Absturz
    /// zu unterscheiden.
    private val scope = CoroutineScope(
        SupervisorJob() + Dispatchers.IO +
            CoroutineExceptionHandler { _, _ ->
                // Eine Diagnoseabfrage darf die App nicht mitnehmen. Ohne
                // Handler landet die Ausnahme beim Standard-Handler von
                // Android, und der beendet den Prozess.
            },
    )

    /// Antwortet dem MethodChannel auf dem Hauptthread.
    ///
    /// `MethodChannel.Result` darf nur von dort aufgerufen werden. Und es
    /// muss **immer** aufgerufen werden: Eine Antwort, die ausbleibt, ist auf
    /// der Dart-Seite ein Future, das nie fertig wird.
    private fun reply(result: MethodChannel.Result, value: Any?) {
        runOnUiThread {
            try {
                result.success(value)
            } catch (e: Throwable) {
                // Schon beantwortet oder Engine weg — beides kein Grund,
                // hier zu sterben.
            }
        }
    }

    /** Laufende Spracheingabe. Es kann immer nur eine geben. */
    private var pendingSpeech: MethodChannel.Result? = null

    /** Neuer Intent bei bereits laufender App (singleTop). */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    override fun onDestroy() {
        // Eine laufende Spracheingabe muss beantwortet werden, auch wenn die
        // Activity vorher stirbt: Sonst wartet die Dart-Seite fuer immer und
        // das Mikrofon im Erfassungsfeld bleibt dauerhaft "hoert zu".
        pendingSpeech?.success(null)
        pendingSpeech = null
        scope.cancel()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        renameChannels(this)
        // Muss bei jedem Start erneut angemeldet werden: Das System raeumt
        // langlebige Shortcuts auf, wenn die App laenger nicht lief.
        ShareTargets.publish(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Alles, was das System anzeigt, kommt von der Dart-Seite
                    // — sie kennt die gewaehlte Sprache, Kotlin nicht.
                    "applyTexts" -> {
                        @Suppress("UNCHECKED_CAST")
                        val texts = (call.argument<Map<String, Any?>>("texts")
                            ?: emptyMap())
                            .mapValues { it.value?.toString().orEmpty() }
                        val changed = AxiomTexts.apply(
                            this,
                            call.argument<String>("language").orEmpty(),
                            texts,
                        )
                        // Nur bei einem Wechsel: Kanalnamen neu schreiben und
                        // das Widget neu zeichnen. Der Aufruf laeuft nach
                        // jedem Auswertungszyklus.
                        if (changed) {
                            renameChannels(this)
                            AxiomWidgetProvider.redraw(this)
                            // Das Teilen-Ziel traegt seine Beschriftung mit
                            // sich; ohne dieses erneute Anmelden stuende sie
                            // bis zum naechsten App-Start in der alten
                            // Sprache im Teilen-Blatt.
                            ShareTargets.publish(this)
                        }
                        result.success(true)
                    }

                    // Der Schluessel der Datenbank. Kommt vor allem anderen,
                    // weil ohne ihn nichts geoeffnet werden kann.
                    "databaseKey" -> result.success(DatabaseKey.passphrase(this))

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
                            route = call.argument<String>("route"),
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

                    // Zwei Schritte statt einem: lesen, speichern lassen,
                    // dann erst loeschen. Siehe MemoInbox.peek.
                    "peekPendingMemos" -> result.success(MemoInbox.peek(this))

                    "ackPendingMemos" -> result.success(
                        MemoInbox.ack(this, call.argument<Int>("count") ?: 0)
                    )

                    // Ortswechsel, die eine Geraeteroutine geschickt hat.
                    // Dasselbe Zweischrittmuster: lesen, speichern lassen,
                    // dann erst loeschen.
                    "peekPendingPlaces" -> result.success(PlaceInbox.peek(this))

                    "ackPendingPlaces" -> result.success(
                        PlaceInbox.ack(this, call.argument<Int>("count") ?: 0)
                    )

                    // Dauerhafte Anzeige im Benachrichtigungsbereich.
                    "presenceStart" -> result.success(
                        PresenceService.start(
                            this,
                            call.argument<String>("headline").orEmpty(),
                            call.argument<String>("detail").orEmpty(),
                        )
                    )

                    // Der gespeicherte Schalter sagt, was gewollt war.
                    // Das hier sagt, was tatsaechlich haengt.
                    "presenceActive" -> result.success(PresenceService.isActive(this))

                    // Solange sie gehalten wird, reicht der WLAN-Treiber
                    // Multicast-Pakete durch. Sie kostet Strom, deshalb
                    // haengt sie am Expertenmodus und nicht am App-Start.
                    "multicastLock" -> result.success(
                        setMulticastLock(call.argument<Boolean>("hold") ?: false)
                    )

                    "presenceDiagnosis" ->
                        result.success(PresenceService.diagnosis(this))

                    // Direkt auf den Kanal, nicht auf die App-Uebersicht:
                    // Der abgeschaltete Kanal liegt dort zwei Ebenen tief.
                    "openPresenceChannel" -> result.success(
                        try {
                            PresenceService.createChannel(this)
                            startActivity(
                                Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                    .putExtra(
                                        Settings.EXTRA_CHANNEL_ID,
                                        PresenceService.CHANNEL,
                                    )
                            )
                            true
                        } catch (e: Throwable) {
                            try {
                                startActivity(
                                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                        .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                )
                                true
                            } catch (e2: Throwable) {
                                false
                            }
                        }
                    )

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
                    // Asynchron: Der Aufruf geht ueber eine Prozessgrenze
                    // zum Health-Connect-Dienst und darf den UI-Thread nicht
                    // blockieren.
                    "healthStatus" -> scope.launch {
                        val status = try {
                            HealthBridge.status(this@MainActivity)
                        } catch (e: Throwable) {
                            mapOf("available" to false, "granted" to false)
                        }
                        healthGrantedCached = status["granted"] == true
                        reply(result, status)
                    }

                    "healthRequestPermissions" ->
                        result.success(HealthBridge.requestPermissions(this))

                    // Was die Bruecke selbst ueber sich sagen kann. Steht als
                    // erste Zeile im Systemcheck: Antwortet der Kanal nicht,
                    // ist jede weitere Zeile bedeutungslos.
                    "ping" -> result.success(true)

                    "healthRead" -> {
                        val since = call.argument<Long>("sinceMillis") ?: 0L
                        scope.launch {
                            val records = try {
                                HealthBridge.read(this@MainActivity, since)
                            } catch (e: Throwable) {
                                emptyList()
                            }
                            reply(result, records)
                        }
                    }

                    "healthOpenSettings" -> {
                        result.success(openHealthSettings())
                    }

                    // ── Widget ──────────────────────────────────────────
                    "requestPinWidget" -> result.success(requestPinWidget())

                    "widgetCount" -> result.success(widgetCount())

                    // ── Notiz-Rolle (S-Pen) ─────────────────────────────
                    "requestNotesRole" -> result.success(requestNotesRole())

                    "openDefaultApps" -> result.success(openDefaultApps())

                    // ── Diagnose ────────────────────────────────────────
                    "diagnostics" -> scope.launch {
                        // Erst den Health-Stand nachziehen, dann den Rest:
                        // Ein Systemcheck, der veraltete Werte zeigt, ist
                        // schlimmer als keiner.
                        healthGrantedCached = try {
                            HealthBridge.hasPermissions(this@MainActivity)
                        } catch (e: Throwable) {
                            false
                        }
                        val values = withContext(Dispatchers.Main) {
                            diagnostics()
                        }
                        reply(result, values)
                    }

                    // ── Spracheingabe ───────────────────────────────────
                    "speechAvailable" -> result.success(
                        SpeechRecognizer.isRecognitionAvailable(this)
                    )

                    "listen" -> startListening(
                        call.argument<String>("locale"), result
                    )

                    // ── Expertenmodus (ADR-0005) ────────────────────────
                    "expertNoticeStart" -> {
                        ExpertService.start(
                            this, call.argument<String>("address").orEmpty())
                        result.success(true)
                    }

                    "expertNoticeStop" -> {
                        ExpertService.stop(this)
                        result.success(true)
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
                "de.atomfritte.axiom.CAPTURE",
                "de.atomfritte.axiom.CHECKIN",
                "de.atomfritte.axiom.FOCUS",
                "de.atomfritte.axiom.SENSATION",
                "de.atomfritte.axiom.ANCHORS",
                "de.atomfritte.axiom.REVIEW",
                "de.atomfritte.axiom.BODY",
                "de.atomfritte.axiom.INBOX",
                ExpertService.ACTION_STOP,
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
            action == "de.atomfritte.axiom.CAPTURE" ||
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

    private var multicastLock: WifiManager.MulticastLock? = null

    /**
     * Hält die Multicast-Sperre, solange der Expertenmodus läuft.
     *
     * Android filtert Multicast im WLAN-Treiber weg, wenn niemand sie
     * anfordert — aus Stromgründen. Ohne sie hört der mDNS-Responder keine
     * einzige Frage, und `axiom.local` löst nirgends auf.
     */
    private fun setMulticastLock(hold: Boolean): Boolean = try {
        if (hold) {
            if (multicastLock?.isHeld != true) {
                val wifi = applicationContext
                    .getSystemService(Context.WIFI_SERVICE) as WifiManager
                multicastLock = wifi.createMulticastLock("axiom-mdns").apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
        } else {
            multicastLock?.takeIf { it.isHeld }?.release()
            multicastLock = null
        }
        true
    } catch (e: Throwable) {
        false
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

    /**
     * Benachrichtigungen freigeben lassen.
     *
     * Ab Android 13 ist das eine Laufzeitberechtigung — sie muss *angefragt*
     * werden. Die frühere Fassung öffnete nur die Einstellungen; wer dort
     * nichts fand, hatte anschließend eine App, deren Erinnerungen still
     * ins Leere liefen, ohne dass irgendwo ein Fehler stand. Genau der
     * stille Ausfall, den R4 beschreibt.
     */
    private fun requestNotifications(): Boolean {
        if (NotificationManagerCompat.from(this).areNotificationsEnabled()) return true

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val state = ContextCompat.checkSelfPermission(
                this, Manifest.permission.POST_NOTIFICATIONS,
            )
            if (state != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    REQ_NOTIFICATIONS,
                )
                return false
            }
        }

        // Berechtigung da, aber der Nutzer hat den Kanal abgeschaltet:
        // Dafuer gibt es nur den Weg ueber die Einstellungen.
        startActivity(
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        )
        return false
    }

    /**
     * Bittet das System, das Widget zu platzieren.
     *
     * Der Umweg über die Widget-Auswahl des Launchers ist unzuverlässig:
     * Samsungs Startbildschirm merkt sich die Widget-Liste einer App und
     * aktualisiert sie nach einem Update nicht zuverlässig. Diese Anfrage
     * geht am Cache vorbei.
     */
    private fun requestPinWidget(): Map<String, Any?> {
        val manager = getSystemService(AppWidgetManager::class.java)
        if (!manager.isRequestPinAppWidgetSupported) {
            return failure("reason.widget.unsupported")
        }
        return try {
            val requested = manager.requestPinAppWidget(
                ComponentName(this, AxiomWidgetProvider::class.java),
                null,
                null,
            )
            if (requested) success()
            else failure("reason.widget.refused")
        } catch (e: Throwable) {
            failure("reason.widget.failed", e.javaClass.simpleName)
        }
    }

    private fun widgetCount(): Int = try {
        getSystemService(AppWidgetManager::class.java)
            .getAppWidgetIds(ComponentName(this, AxiomWidgetProvider::class.java))
            .size
    } catch (e: Throwable) {
        0
    }

    /**
     * Fragt die Rolle „Notiz-App" an.
     *
     * Ohne sie erscheint AXIOM beim Stift-Doppeltipp nicht. Der
     * Intent-Filter allein genügt nicht — das System fragt die Rolle ab,
     * nicht den Filter. Das war der Grund, warum die Stift-Aktion trotz
     * korrekt registriertem `ACTION_CREATE_NOTE` nicht auftauchte.
     */
    private fun requestNotesRole(): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return failure("reason.notes.since14")
        }
        return try {
            val roles = getSystemService(RoleManager::class.java)
            if (roles.isRoleHeld(RoleManager.ROLE_NOTES)) return success()
            if (!roles.isRoleAvailable(RoleManager.ROLE_NOTES)) {
                // Die Standard-Apps zu oeffnen waere hier eine Sackgasse:
                // Ohne die Rolle gibt es dort keinen Eintrag „Notizen", und
                // man sucht in einem Menue nach etwas, das es nicht gibt.
                return failure("reason.notes.unavailable")
            }
            startActivityForResult(
                roles.createRequestRoleIntent(RoleManager.ROLE_NOTES),
                REQ_NOTES_ROLE,
            )
            success()
        } catch (e: Throwable) {
            failure("reason.notes.dialog", e.javaClass.simpleName)
        }
    }

    /** Systemeinstellung „Standard-Apps" — der Weg, wenn die Rolle fehlt. */
    private fun openDefaultApps(): Boolean = try {
        startActivity(Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS))
        true
    } catch (e: Throwable) {
        false
    }

    private fun success(): Map<String, Any?> = mapOf("ok" to true)

    /**
     * Fehlschlag mit Grund — als Schluessel, nicht als Satz.
     *
     * Jeder verschluckte Fehler wird auf dem Geraet zu „passiert nichts", und
     * „passiert nichts" ist von aussen nicht diagnostizierbar. Lieber ein
     * unschoener Satz als ein stummer Knopf.
     *
     * Den Satz baut aber die Dart-Seite: Sie kennt die gewaehlte Sprache,
     * Kotlin nicht. Hier steht nur der Schluessel aus `SystemTexts.reasons`
     * und, wo noetig, der Wert fuer `{0}` — meist der Name der Ausnahme.
     */
    private fun failure(reason: String, vararg args: String): Map<String, Any?> =
        mapOf("ok" to false, "reason" to reason, "reasonArgs" to args.toList())

    private fun notesRoleHeld(): Boolean = try {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
            getSystemService(RoleManager::class.java)
                .isRoleHeld(RoleManager.ROLE_NOTES)
    } catch (e: Throwable) {
        false
    }

    /**
     * Rohwerte für den Systemcheck.
     *
     * „Geht nicht" ist keine Fehlermeldung. Jeder Wert hier ist eine Aussage
     * des Systems — nicht eine Vermutung der App darüber, was das System
     * wohl gerade tut.
     */
    /// Letzter bekannter Health-Freigabestand, gesetzt von healthStatus.
    private var healthGrantedCached = false

    private fun diagnostics(): Map<String, Any?> {
        val alarms = getSystemService(AlarmManager::class.java)
        val power = getSystemService(PowerManager::class.java)
        val health = try {
            androidx.health.connect.client.HealthConnectClient.getSdkStatus(this)
        } catch (e: Throwable) {
            -1
        }
        return mapOf(
            "sdkInt" to Build.VERSION.SDK_INT,
            "release" to Build.VERSION.RELEASE,
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "channelAlive" to true,
            "notifications" to
                NotificationManagerCompat.from(this).areNotificationsEnabled(),
            "postNotificationsGranted" to (
                Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                    ContextCompat.checkSelfPermission(
                        this, Manifest.permission.POST_NOTIFICATIONS,
                    ) == PackageManager.PERMISSION_GRANTED
                ),
            "exactAlarm" to (
                Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                    alarms.canScheduleExactAlarms()
                ),
            "batteryUnrestricted" to
                power.isIgnoringBatteryOptimizations(packageName),
            "healthSdkStatus" to health,
            // Bewusst nicht abgefragt: Der Aufruf ist suspendierend, und
            // dieser Ueberblick darf den UI-Thread nicht anhalten. Den
            // genauen Stand liefert healthStatus.
            "healthGranted" to healthGrantedCached,
            "widgetCount" to widgetCount(),
            "widgetPinSupported" to
                getSystemService(AppWidgetManager::class.java)
                    .isRequestPinAppWidgetSupported,
            "notesRoleAvailable" to (
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE
                ),
            "notesRoleHeld" to notesRoleHeld(),
            "presenceRunning" to PresenceService.isActive(this),
            "presenceWanted" to PresenceService.isEnabled(this),
            "liveSlotPromotable" to LiveSlotService.isPromotable(),
            // Was daraus geworden ist, nicht was moeglich waere.
            "presencePromoted" to
                LiveSlotService.isPromoted(this, PresenceService.NOTIFICATION_ID),
            "liveSlotPromoted" to
                LiveSlotService.isPromoted(this, LiveSlotService.NOTIFICATION_ID),
            "speechAvailable" to SpeechRecognizer.isRecognitionAvailable(this),
        )
    }

    /**
     * Spracheingabe über den System-Recognizer.
     *
     * Bewusst kein eigenes Mikrofonrecht und keine Bibliothek: Die
     * Erkennung passiert in der Recognizer-App, AXIOM bekommt nur den
     * fertigen Text. Damit bleibt die App ohne Netz- und Mikrofonrechte.
     */
    private fun startListening(locale: String?, result: MethodChannel.Result) {
        if (pendingSpeech != null) {
            result.success(null)
            return
        }
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            // Ohne Vorgabe die Sprache des Geraets. Fest "de-DE" hiess: Wer
            // die App auf Englisch stellt, diktiert weiter gegen eine
            // deutsche Erkennung — und bekommt Wortsalat zurueck.
            .putExtra(
                RecognizerIntent.EXTRA_LANGUAGE,
                locale ?: java.util.Locale.getDefault().toLanguageTag(),
            )
            .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            // Offline bevorzugen, wenn ein Sprachpaket da ist: schneller und
            // ohne dass Gesprochenes das Geraet verlaesst.
            .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            .putExtra(
                RecognizerIntent.EXTRA_PROMPT,
                AxiomTexts.get(this, "speech.prompt"),
            )
        return try {
            pendingSpeech = result
            startActivityForResult(intent, REQ_SPEECH)
        } catch (e: Throwable) {
            pendingSpeech = null
            result.success(null)
        }
    }

    @Deprecated("Ohne ComponentActivity gibt es keinen ActivityResultLauncher.")
    override fun onActivityResult(request: Int, code: Int, data: Intent?) {
        super.onActivityResult(request, code, data)
        if (request != REQ_SPEECH) return
        val pending = pendingSpeech ?: return
        pendingSpeech = null
        val text = data
            ?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
            ?.firstOrNull()
            ?.trim()
        pending.success(if (code == RESULT_OK && !text.isNullOrEmpty()) text else null)
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

    /**
     * Spiegelt jeden geplanten Alarm, damit er einen Neustart überlebt.
     *
     * Android verwirft beim Booten alle Alarme. Der BootReceiver konnte
     * vorher nur die drei Tages-Check-ins wiederherstellen, weil er sie
     * fest verdrahtet kannte. Alles andere — Ankererinnerungen, Abendgrenze,
     * Schlafeintrag — war nach einem Neustart still weg. Genau die
     * Erinnerungen also, die einen Termin retten sollen, und genau der
     * Fehlermodus, der nicht auffällt: Es kommt einfach nichts.
     *
     * Der Termin selbst steht in der Datenbank, an die Kotlin nicht
     * herankommt. Also merkt sich der Planer, was er geplant hat.
     */
    private fun remember(
        context: Context,
        id: Int,
        atMillis: Long,
        title: String,
        body: String,
        channel: String,
        route: String?,
    ) {
        try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val all = org.json.JSONObject(prefs.getString("all", "{}") ?: "{}")
            all.put(
                id.toString(),
                org.json.JSONObject()
                    .put("at", atMillis)
                    .put("title", title)
                    .put("body", body)
                    .put("channel", channel)
                    .put("route", route ?: org.json.JSONObject.NULL),
            )
            prefs.edit().putString("all", all.toString()).apply()
        } catch (e: Throwable) {
            // Der Alarm ist trotzdem gesetzt. Nur der Neustart-Schutz fehlt.
        }
    }

    private fun forget(context: Context, id: Int) {
        try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val all = org.json.JSONObject(prefs.getString("all", "{}") ?: "{}")
            all.remove(id.toString())
            prefs.edit().putString("all", all.toString()).apply()
        } catch (e: Throwable) {
        }
    }

    /**
     * Setzt alle gemerkten Alarme neu — nach einem Neustart oder Update.
     *
     * Vergangene fallen dabei weg: Eine Erinnerung an einen Termin von
     * gestern nachzureichen wäre schlimmer als sie zu verlieren.
     */
    fun restoreAll(context: Context): Int {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val all = try {
            org.json.JSONObject(prefs.getString("all", "{}") ?: "{}")
        } catch (e: Throwable) {
            return 0
        }
        val now = System.currentTimeMillis()
        val kept = org.json.JSONObject()
        var restored = 0
        for (key in all.keys()) {
            val entry = all.optJSONObject(key) ?: continue
            val at = entry.optLong("at")
            if (at <= now) continue
            kept.put(key, entry)
            schedule(
                context = context,
                id = key.toIntOrNull() ?: continue,
                atMillis = at,
                title = entry.optString("title"),
                body = entry.optString("body"),
                channel = entry.optString("channel", "axiom_nudge"),
                route = entry.optString("route").takeIf { it.isNotEmpty() && it != "null" },
            )
            restored++
        }
        prefs.edit().putString("all", kept.toString()).apply()
        return restored
    }

    fun schedule(
        context: Context,
        id: Int,
        atMillis: Long,
        title: String,
        body: String,
        channel: String,
        route: String? = null,
    ): Boolean {
        remember(context, id, atMillis, title, body, channel, route)
        val alarms = context.getSystemService(AlarmManager::class.java)
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra("id", id)
            putExtra("title", title)
            putExtra("body", body)
            putExtra("channel", channel)
            putExtra("plannedAt", atMillis)
            // Wohin der Tipp auf die Benachrichtigung fuehrt.
            putExtra("route", route)
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
        forget(context, id)
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
