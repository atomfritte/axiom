package de.axiom.axiom_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Stellt alle geplanten Alarme nach Neustart oder App-Update wieder her.
 *
 * Android verwirft beim Booten jeden Alarm. Ohne diesen Empfänger wären die
 * Erinnerungen still verschwunden — der schlimmste Fehlermodus, weil er
 * nicht auffällt: Es kommt einfach nichts, und man merkt es erst, wenn der
 * Termin vorbei ist.
 *
 * **Warum hier nichts mehr fest verdrahtet ist.** Vorher setzte dieser
 * Empfänger drei Tages-Check-ins neu — mit fest deutschem Text und ohne
 * Ziel. Alles andere blieb weg: Ankererinnerungen, Abendgrenze,
 * Schlafeintrag. Ausgerechnet die Rückwärtsverkettung eines Termins (M3),
 * also die Erinnerung mit der höchsten Folgewirkung, überlebte keinen
 * Neustart.
 *
 * Die Termine stehen in der Datenbank, an die Kotlin nicht herankommt.
 * Deshalb merkt sich der Planer, was er geplant hat, und hier wird es
 * abgespielt — mit den Texten in der Sprache, in der sie gesetzt wurden.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) return

        MainActivity.createChannels(context)
        AlarmScheduler.restoreAll(context)
    }
}
