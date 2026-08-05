package de.axiom.axiom_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Homescreen-Widget: die nächste Handlung und die aktuelle Kapazität,
 * permanent sichtbar.
 *
 * Objektpermanenz ist bei diesem Profil ein reales Problem: Was nicht
 * sichtbar ist, existiert nicht [D9]. Ein Widget, das die eine anstehende
 * Sache zeigt, ersetzt das Erinnern — man muss die App nicht öffnen, um zu
 * wissen, was ansteht.
 *
 * Der Kapazitätsbalken ist bewusst mit dabei: Er macht sichtbar, warum
 * gerade diese und keine schwerere Aufgabe vorgeschlagen wird (G2).
 */
class AxiomWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val PREFS = "axiom_widget"

        /** Setzt den Inhalt und zeichnet alle Instanzen neu. */
        fun publish(context: Context, headline: String, detail: String, capacity: Int) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString("headline", headline)
                .putString("detail", detail)
                .putInt("capacity", capacity)
                .apply()

            redraw(context)
        }

        /**
         * Zeichnet mit unveraendertem Inhalt neu.
         *
         * Gebraucht nach einem Sprachwechsel: „JETZT", „ERFASSEN" und die
         * Kapazitaetszeile stehen im Layout beziehungsweise werden hier
         * gesetzt — ohne dieses Neuzeichnen blieben sie in der alten Sprache
         * stehen, bis der naechste Auswertungszyklus etwas anderes zu sagen
         * hat.
         */
        fun redraw(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, AxiomWidgetProvider::class.java)
            )
            ids.forEach { render(context, manager, it) }
        }

        private fun render(context: Context, manager: AppWidgetManager, id: Int) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val headline = prefs.getString("headline", null)
                ?: AxiomTexts.get(context, "widget.headline")
            val detail = prefs.getString("detail", null)
                ?: AxiomTexts.get(context, "widget.detail")
            val capacity = prefs.getInt("capacity", 0)

            val views = RemoteViews(context.packageName, R.layout.axiom_widget).apply {
                // Die beiden festen Marken stehen auch im Layout, damit die
                // Vorschau in der Widget-Auswahl nicht leer ist. Hier werden
                // sie erneut gesetzt: Das Layout kennt nur die Sprache des
                // Geraets, AXIOM die in der App gewaehlte.
                setTextViewText(
                    R.id.widget_label, AxiomTexts.get(context, "widget.label"))
                setTextViewText(
                    R.id.widget_capture, AxiomTexts.get(context, "widget.capture"))
                setTextViewText(R.id.widget_headline, headline)
                setTextViewText(R.id.widget_detail, detail)
                setTextViewText(
                    R.id.widget_capacity,
                    AxiomTexts.format(context, "widget.capacity", capacity),
                )
                setProgressBar(R.id.widget_bar, 100, capacity, false)

                setOnClickPendingIntent(
                    R.id.widget_root,
                    PendingIntent.getActivity(
                        context, 0,
                        Intent(context, MainActivity::class.java)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                )
                setOnClickPendingIntent(
                    R.id.widget_capture,
                    PendingIntent.getActivity(
                        context, 1,
                        Intent(context, MainActivity::class.java)
                            .setAction("de.axiom.CAPTURE")
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                )
            }
            manager.updateAppWidget(id, views)
        }
    }

    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { render(context, manager, it) }
    }
}
