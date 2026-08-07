package de.atomfritte.axiom

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat

/**
 * Die offene Freigabeanfrage des Expertenmodus, sichtbar ohne die App.
 *
 * **Das Problem.** Wer den Browser neu lädt, muss sich neu anmelden: Der
 * Browser zeigt eine Zahl, dieselbe Zahl steht in der App, man vergleicht
 * und gibt frei. Bis hierher waren das fünf Schritte — App suchen,
 * Einstellungen, Expertenmodus, Zahl finden, tippen —, und dazwischen lag
 * eine Frist von neunzig Sekunden.
 *
 * **Warum hier trotzdem kein „Freigeben"-Knopf steht.** Er wäre der
 * naheliegende Entwurf und ein Sicherheitsloch, aus zwei unabhängigen
 * Gründen:
 *
 * 1. `Notification.Action.actionIntent` ist ein öffentliches Feld. Jede App
 *    mit `BIND_NOTIFICATION_LISTENER_SERVICE` — und jede gekoppelte Uhr,
 *    denn genau so funktionieren Aktionsknöpfe dort — bekommt die
 *    Benachrichtigung samt Aktionen und kann `actionIntent.send()` rufen,
 *    mit der Identität von AXIOM. Ein Freigabeknopf wäre also eine
 *    Fähigkeit, die AXIOM an jeden Benachrichtigungsleser auf dem Gerät
 *    verteilt, und der vergleicht nichts, der feuert nur.
 *    `setAuthenticationRequired` hilft dagegen nicht: Diese Prüfung sitzt in
 *    der Klickbehandlung von SystemUI, nicht in der Kapsel.
 * 2. Ein `PendingIntent.getBroadcast` feuert auf einem **gesperrten** Gerät
 *    sofort — genau deshalb funktioniert die Schnellerfassung ohne
 *    Entsperren. Wer das gesperrte Telefon in die Hand bekommt, gäbe damit
 *    einem fremden Browser den vollen Datensatz frei.
 *
 * Deshalb: **Die Meldung entscheidet nichts, sie navigiert.** Sie trägt die
 * Zahl im Titel und führt per `getActivity` auf den Bildschirm, auf dem der
 * Vergleich seit jeher stattfindet. `getActivity` erzwingt ab API 26 immer
 * den Sperrbildschirm, ohne Versionsabfrage. Aus fünf Schritten werden zwei
 * Tipps plus Entsperren, und die einzige Anmeldung für Gesundheitsdaten
 * (ADR-0005 §3a) bleibt unangetastet. Ein Benachrichtigungsleser, der die
 * Kapsel missbraucht, öffnet einen Bildschirm — mehr nicht.
 *
 * **Warum `axiom_nudge` und nicht `axiom_intervene`.** `/api/auth/request`
 * braucht keine Anmeldung: Jeder im selben Netz kann alle neunzig Sekunden
 * eine neue Anfrage stellen. Auf einem klingenden Kanal wäre das ein Ton im
 * Minutentakt aus dem Netz, ohne Cooldown — die Benachrichtigungsflut, gegen
 * die CLAUDE.md für jede Regel einen Pflicht-Cooldown verlangt (R2). Sichtbar
 * und still genügt: Wer die Freigabe braucht, hat sie gerade selbst
 * ausgelöst und sieht nach.
 */
object ApprovalNotice {

    /** Eigene ID, damit die laufende Anzeige des Dienstes stehenbleibt. */
    const val NOTIFICATION_ID = 4714

    /** Sichtbar und still — Begruendung im Kopfkommentar. */
    const val CHANNEL = "axiom_nudge"

    const val ACTION_APPROVE = "de.atomfritte.axiom.EXPERT_APPROVE"

    /**
     * Dieselbe Frist wie `_AuthRequest.isExpired` auf der Dart-Seite.
     *
     * Die Doppelung ist beabsichtigt und die billigere von zwei Varianten:
     * `setTimeoutAfter` lässt Android die Meldung selbst zurückziehen, ohne
     * dass ein Dart-Timer laufen muss. Läuft sie mit der Dart-Seite
     * auseinander, bleibt eine tote Zahl stehen — und eine tote Zahl ist
     * genau die, bei der ein später Tipp auf eine **fremde** neue Anfrage
     * träfe. `approval_notice_test.dart` vergleicht beide Werte.
     */
    const val TIMEOUT_MS = 90_000L

    fun show(context: Context, number: String) {
        val open = PendingIntent.getActivity(
            context, 6,
            Intent(context, MainActivity::class.java)
                .setAction(ACTION_APPROVE)
                // Die Zahl steht in der Action, nicht in den Extras.
                // `PendingIntent` unterscheidet zwei Kapseln über
                // `Intent.filterEquals`, und das vergleicht Extras NICHT —
                // zwei Anfragen ergäben dieselbe Kapsel mit der alten Zahl.
                // Der Identifier gehört zu den verglichenen Feldern.
                .setIdentifier(number)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            // `CANCEL_CURRENT` statt `UPDATE_CURRENT`: Letzteres schreibt
            // auch Kopien um, die anderswo schon liegen. Hier soll eine alte
            // Kapsel unbrauchbar werden, nicht die neue Zahl bekommen.
            PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notice = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(AxiomTexts.format(context, "expert.approval.title", number))
            .setContentText(AxiomTexts.get(context, "expert.approval.detail"))
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText(AxiomTexts.get(context, "expert.approval.detail"))
            )
            .setContentIntent(open)
            .setAutoCancel(true)
            // Geht von selbst weg, wenn die Anfrage verfallen ist.
            .setTimeoutAfter(TIMEOUT_MS)
            .setSilent(true)
            // Auf einem gesicherten Sperrbildschirm bleibt die Zahl verdeckt,
            // wenn der Nutzer das so eingestellt hat. Antippen führt trotzdem
            // auf den Bildschirm — die Meldung verliert dadurch nichts, weil
            // sie ohnehin nur navigiert.
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .build()

        manager(context).notify(NOTIFICATION_ID, notice)
    }

    fun cancel(context: Context) = manager(context).cancel(NOTIFICATION_ID)

    private fun manager(context: Context) =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
}
