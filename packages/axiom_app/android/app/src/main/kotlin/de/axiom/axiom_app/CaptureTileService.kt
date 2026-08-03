package de.axiom.axiom_app

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * Schnelleinstellung "AXIOM erfassen".
 *
 * Herunterwischen, tippen, schreiben. Zwischen Einfall und Notiz liegen
 * wenige Sekunden; jede zusätzliche Hürde in diesem Fenster führt zum
 * Verlust des Gedankens [D9].
 */
class CaptureTileService : TileService() {

    override fun onStartListening() {
        qsTile?.apply {
            state = Tile.STATE_INACTIVE
            label = "Erfassen"
            contentDescription = "Gedanken in AXIOM festhalten"
            updateTile()
        }
    }

    override fun onClick() {
        val intent = Intent(this, MainActivity::class.java)
            .setAction("de.axiom.CAPTURE")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(
                PendingIntent.getActivity(
                    this, 0, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            )
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
