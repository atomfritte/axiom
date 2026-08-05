# R8-Regeln fuer AXIOM.
#
# Der Grundsatz hier ist derselbe wie im Core: Fail-Fast statt stillem
# Verschlucken. Eine Klasse, die R8 wegoptimiert und die zur Laufzeit ueber
# Reflexion gesucht wird, faellt nicht beim Bauen auf, sondern auf dem Geraet
# — und dort als "passiert nichts".

# Flutters Einbettung. Wird ueber JNI und Reflexion angesprochen.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Health Connect ruft die Permission-Rationale-Activity ueber einen Intent
# auf, den das System aufloest — kein Aufrufer im eigenen Code.
-keep class androidx.health.connect.client.** { *; }
-keep class de.atomfritte.axiom.HealthBridge { *; }

# Alles, was aus dem Manifest heraus instanziiert wird: Activities, Services,
# Receiver, TileService, Widget-Provider. R8 findet die Referenz im XML nicht.
-keep class de.atomfritte.axiom.MainActivity { *; }
-keep class de.atomfritte.axiom.CreateNoteActivity { *; }
-keep class de.atomfritte.axiom.PresenceService { *; }
-keep class de.atomfritte.axiom.LiveSlotService { *; }
-keep class de.atomfritte.axiom.ExpertService { *; }
-keep class de.atomfritte.axiom.CaptureTileService { *; }
-keep class de.atomfritte.axiom.AxiomWidgetProvider { *; }
-keep class de.atomfritte.axiom.AlarmReceiver { *; }
-keep class de.atomfritte.axiom.BootReceiver { *; }
-keep class de.atomfritte.axiom.QuickCaptureReceiver { *; }
-keep class de.atomfritte.axiom.PlaceReceiver { *; }

# sqlite3 laedt seine native Bibliothek ueber einen festen Klassennamen.
-keep class org.sqlite.** { *; }

# Kotlin-Coroutinen: der Debug-Probe-Mechanismus greift reflektiv zu.
-dontwarn kotlinx.coroutines.**

# Play Core. Flutters Einbettung verweist auf Deferred Components und
# SplitCompat — beides Play-Store-Mechanik. AXIOM wird nicht ueber den Store
# verteilt (docs/BACKLOG.md), die Klassen sind also zu Recht nicht da. Kein
# `-keep`, sondern `-dontwarn`: Es gibt nichts zu behalten.
-dontwarn com.google.android.play.core.**
