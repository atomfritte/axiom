package de.axiom.axiom_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.util.Calendar

/**
 * Stellt die Tagesanker nach Neustart oder App-Update wieder her.
 *
 * Android verwirft beim Booten alle Alarme. Ohne diesen Empfänger wären die
 * Check-ins nach jedem Neustart still verschwunden — der schlimmste
 * Fehlermodus, weil er nicht auffällt.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) return

        MainActivity.createChannels(context)

        // Dieselben drei Slots wie AndroidBridge.scheduleDailyCheckins.
        listOf(1 to 9, 2 to 14, 3 to 21).forEach { (id, hour) ->
            val at = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
                if (timeInMillis <= System.currentTimeMillis()) {
                    add(Calendar.DAY_OF_YEAR, 1)
                }
            }
            AlarmScheduler.schedule(
                context = context,
                id = id,
                atMillis = at.timeInMillis,
                title = "Check-in",
                body = "Vier Regler, ungefähr reicht.",
                channel = "axiom_nudge",
            )
        }
    }
}
