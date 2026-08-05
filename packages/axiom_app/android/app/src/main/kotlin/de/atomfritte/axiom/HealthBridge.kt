package de.atomfritte.axiom

import android.app.Activity
import android.content.Context
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.aggregate.AggregationResultGroupedByPeriod
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateGroupByPeriodRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.Instant
import java.time.LocalDateTime
import java.time.Period
import java.time.ZoneId

/**
 * Health Connect — Schlaf und Bewegung aus dem System statt aus Selbstauskunft.
 *
 * **Warum das zählt.** Der körperliche Zustand ist der größte einzelne
 * Modulator der Exekutivfunktion [D7], und Schlafdefizit ist der Startpunkt
 * der Kaskade aus D8. Beides ging bisher nur über Selbstauskunft in die
 * Kapazitätsrechnung ein — also genau über den Kanal, der unter Last als
 * erstes ausfällt. Wer schlecht geschlafen hat, trägt das am nächsten Tag
 * am seltensten nach.
 *
 * **Was hier nicht passiert.** Kein Herzfrequenz-Dauerlesen, keine
 * Bewertung, keine Zielvorgabe. Zwei Größen, beide roh, beide als Event
 * abgelegt: Schlaffenster und Tagesschritte. Die Auswertung macht der
 * StateDeriver, sichtbar und nachrechenbar (G2).
 *
 * **Nichts verlässt das Gerät.** Health Connect ist eine lokale
 * Systemschnittstelle. Die App hat keine INTERNET-Berechtigung — daran
 * ändert dieser Import nichts (ADR-0002).
 */
object HealthBridge {

    const val REQUEST_CODE = 8801

    /** Nur lesend, nur was in eine Regel eingeht. */
    val PERMISSIONS: Set<String> = setOf(
        HealthPermission.getReadPermission(SleepSessionRecord::class),
        HealthPermission.getReadPermission(StepsRecord::class),
    )

    /**
     * Ob Health Connect auf diesem Gerät nutzbar ist.
     *
     * Drei Zustände, die die Oberfläche unterscheiden muss: nicht vorhanden,
     * vorhanden aber nicht freigegeben, nutzbar. Ein pauschales "geht nicht"
     * würde den Nutzer im Dunkeln lassen, warum keine Schlafdaten ankommen.
     */
    suspend fun status(context: Context): Map<String, Any> {
        val sdk = try {
            HealthConnectClient.getSdkStatus(context)
        } catch (e: Throwable) {
            HealthConnectClient.SDK_UNAVAILABLE
        }
        if (sdk != HealthConnectClient.SDK_AVAILABLE) {
            return mapOf(
                "available" to false,
                "granted" to false,
                "needsUpdate" to
                    (sdk == HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED),
            )
        }
        return mapOf(
            "available" to true,
            "granted" to hasPermissions(context),
            "needsUpdate" to false,
        )
    }

    /**
     * Ob alle benoetigten Freigaben vorliegen.
     *
     * Suspendierend, nicht blockierend: Die frueherere Fassung rief
     * `runBlocking` auf — und weil `status()` aus dem MethodChannel-Handler
     * kommt, hing damit der UI-Thread an einer Prozessgrenze. Bei einem
     * langsamen Health-Connect-Dienst ist das ein ANR beim App-Start.
     */
    suspend fun hasPermissions(context: Context): Boolean = try {
        val client = HealthConnectClient.getOrCreate(context)
        client.permissionController.getGrantedPermissions()
            .containsAll(PERMISSIONS)
    } catch (e: Throwable) {
        false
    }

    /**
     * Öffnet den Systemdialog. Die Freigabe erteilt das System, nicht die App
     * — und sie ist jederzeit einzeln widerrufbar. Deshalb wird der Zustand
     * vor jeder Nutzung erneut geprüft und nicht zwischengespeichert (R8).
     */
    fun requestPermissions(activity: Activity): Map<String, Any?> {
        val sdk = try {
            HealthConnectClient.getSdkStatus(activity)
        } catch (e: Throwable) {
            HealthConnectClient.SDK_UNAVAILABLE
        }
        if (sdk != HealthConnectClient.SDK_AVAILABLE) {
            // Nur der Schluessel und der Rohwert: Den Satz baut die
            // Dart-Seite, die kennt die gewaehlte Sprache.
            return mapOf(
                "ok" to false,
                "reason" to "reason.health.unusable",
                "reasonArgs" to listOf(sdk.toString()),
            )
        }
        // Ab Android 14 sind das gewoehnliche Laufzeitberechtigungen. Der
        // androidx-Vertrag oeffnet dort eine Activity, die es auf manchen
        // Geraeten nicht gibt — dann passiert genau nichts. Der direkte Weg
        // ueber das Berechtigungssystem funktioniert immer.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return try {
                ActivityCompat.requestPermissions(
                    activity, PERMISSIONS.toTypedArray(), REQUEST_CODE,
                )
                mapOf("ok" to true)
            } catch (e: Throwable) {
                mapOf(
                    "ok" to false,
                    "reason" to "reason.health.dialog",
                    "reasonArgs" to listOf(e.javaClass.simpleName),
                )
            }
        }
        return try {
            val contract = PermissionController.createRequestPermissionResultContract()
            activity.startActivityForResult(
                contract.createIntent(activity, PERMISSIONS),
                REQUEST_CODE,
            )
            mapOf("ok" to true)
        } catch (e: Throwable) {
            mapOf(
                "ok" to false,
                "reason" to "reason.health.silent",
                "reasonArgs" to listOf(e.javaClass.simpleName),
            )
        }
    }

    /**
     * Liest Schlaffenster und Tagesschritte ab [sinceMillis].
     *
     * Schlaf kommt als Einzelaufzeichnung mit stabiler Quell-ID zurück,
     * Schritte als Tagessumme. Beides ist damit wiederholbar importierbar,
     * ohne Dubletten zu erzeugen — Events sind append-only, ein doppelter
     * Import wäre nicht rückgängig zu machen.
     */
    suspend fun read(context: Context, sinceMillis: Long): List<Map<String, Any?>> {
        if (!hasPermissions(context)) return emptyList()
        val client = HealthConnectClient.getOrCreate(context)
        val zone = ZoneId.systemDefault()
        val start = Instant.ofEpochMilli(sinceMillis)
        val end = Instant.now()
        if (!start.isBefore(end)) return emptyList()

        val out = mutableListOf<Map<String, Any?>>()

        val sleep = client.readRecords(
            ReadRecordsRequest(
                recordType = SleepSessionRecord::class,
                timeRangeFilter = TimeRangeFilter.between(start, end),
            )
        )
        for (record in sleep.records) {
            out += mapOf(
                "kind" to "sleep",
                "sourceId" to record.metadata.id,
                "startMillis" to record.startTime.toEpochMilli(),
                "endMillis" to record.endTime.toEpochMilli(),
            )
        }

        val steps: List<AggregationResultGroupedByPeriod> = client.aggregateGroupByPeriod(
            AggregateGroupByPeriodRequest(
                metrics = setOf(StepsRecord.COUNT_TOTAL),
                timeRangeFilter = TimeRangeFilter.between(
                    LocalDateTime.ofInstant(start, zone),
                    LocalDateTime.ofInstant(end, zone),
                ),
                timeRangeSlicer = Period.ofDays(1),
            )
        )
        val today = java.time.LocalDate.now(zone)
        for (bucket in steps) {
            // Den laufenden Tag auslassen: Sein Zaehler waechst noch. Einmal
            // importiert, traegt er eine Quell-ID und wuerde beim naechsten
            // Import als "schon vorhanden" uebersprungen — der Tag bliebe
            // fuer immer auf dem Stand des ersten Imports stehen.
            if (!bucket.startTime.toLocalDate().isBefore(today)) continue
            val count = bucket.result[StepsRecord.COUNT_TOTAL] ?: continue
            out += mapOf(
                "kind" to "steps",
                // Der Tag ist die Identitaet: ein erneuter Import desselben
                // Tages ersetzt nichts, er wird erkannt und uebersprungen.
                "sourceId" to "steps-${bucket.startTime.toLocalDate()}",
                "startMillis" to
                    bucket.startTime.atZone(zone).toInstant().toEpochMilli(),
                "endMillis" to
                    bucket.endTime.atZone(zone).toInstant().toEpochMilli(),
                "count" to count,
            )
        }

        return out
    }

}
