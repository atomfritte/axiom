package de.axiom.axiom_app

import android.content.Context
import android.content.Intent
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat

/**
 * AXIOM als direktes Ziel im Teilen-Blatt.
 *
 * Ohne das steht die App in der Liste *unter* der Zeile mit den direkten
 * Zielen: erst Blatt aufziehen, dann suchen, dann tippen. Mit Direct Share
 * ist es ein Tipp in der obersten Reihe — und, wichtiger als der Tipp, ein
 * fester Platz. Ein Ziel, das immer an derselben Stelle steht, muss nicht
 * gesucht werden [D9].
 *
 * **Warum ein dynamischer Shortcut und nicht der statische aus
 * `shortcuts.xml`:** Direct-Share-Ziele müssen langlebig sein
 * (`setLongLived`), und das kann nur ein zur Laufzeit angemeldeter Shortcut.
 * Der statische Eintrag bleibt daneben bestehen — er bedient das lange
 * Tippen auf das App-Symbol.
 */
object ShareTargets {

    private const val CATEGORY = "de.axiom.category.CAPTURE"
    private const val ID = "capture_direct"

    fun publish(context: Context) {
        val shortcut = ShortcutInfoCompat.Builder(context, ID)
            .setShortLabel("Erfassen")
            .setLongLabel("In AXIOM erfassen")
            .setIcon(IconCompat.createWithResource(context, R.mipmap.ic_launcher))
            .setCategories(setOf(CATEGORY))
            .setLongLived(true)
            .setIntent(
                Intent(context, MainActivity::class.java)
                    .setAction("de.axiom.CAPTURE")
            )
            .build()

        try {
            ShortcutManagerCompat.pushDynamicShortcut(context, shortcut)
        } catch (e: IllegalStateException) {
            // Kein Grund, den Start abzubrechen: Das Teilen funktioniert
            // weiterhin ueber den Intent-Filter, nur eine Reihe tiefer.
        }
    }
}
