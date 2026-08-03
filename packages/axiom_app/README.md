# axiom_app — Flutter-App

Android (Galaxy S25 Ultra, primär) und Linux Desktop.

## Bauen und starten

```bash
dart run tools/bin/sync_rules.dart     # aus der Projektwurzel, VOR dem Build
flutter run -d linux                   # Desktop
flutter run -d <geraet>                # adb devices
flutter build apk --release
```

## Struktur

```
lib/design/      Tokens, Theme, Instrumente, Kapazitätslinie
lib/screens/     Jetzt · Zustand · System · Eingang · Onboarding · Blätter
lib/state/       Riverpod-Verdrahtung, AxiomRuntime (Core + Daten)
lib/platform/    Android-Brücke, Intent-Behandlung, System-Spiegelung
android/         Kotlin: Alarme, Widget, Quick Tile, Boot, Benachrichtigungen
```

## Android-Integration

| Kanal | Zweck | Datei |
|---|---|---|
| Exakte Alarme | minutengenaue Zeitanker [D4] | `AlarmReceiver.kt` |
| Boot-Wiederherstellung | Alarme überleben den Neustart | `BootReceiver.kt` |
| Homescreen-Widget | nächste Handlung permanent sichtbar [D9] | `AxiomWidgetProvider.kt` |
| Quick Settings Tile | Erfassen aus jedem Kontext [D9] | `CaptureTileService.kt` |
| App-Shortcuts | Erfassen/Check-in per langem Tippen | `res/xml/shortcuts.xml` |
| Share-Ziel | aus jeder App nach AXIOM teilen | `AndroidManifest.xml` |
| Benachrichtigungskanäle | einer je Eingriffstiefe | `MainActivity.kt` |
| Broadcast-Intents | Samsung „Modi und Routinen" | `AndroidBridge.broadcast` |

**`INTERNET` ist im Hauptmanifest nicht deklariert** (ADR-0002). Nur die
Debug- und Profile-Varianten enthalten sie, weil Flutter sie für Hot Reload
braucht. Der Release-Build hat sie nicht — geprüft in `test/language_test.dart`
und im gebauten APK.

## Tests

```bash
flutter test                                          # alles
flutter test test/screenshot_test.dart --update-goldens   # Bilder erneuern
```

- `app_test.dart` — Verhalten: genau eine Handlung (G1), sichtbare Regel-ID (G2)
- `language_test.dart` — keine Schuldsprache, echte Umlaute, kein Netzwerk
- `screenshot_test.dart` — Referenzbilder in `test/screenshots/`

## Onboarding

Fünf Schritte, jeder überspringbar. Der vierte ist der wichtigste: der erste
Check-in. Ein Onboarding, das nur erklärt und nichts tun lässt, hinterlässt
eine leere App — und eine leere App wird geschlossen.

Der letzte Schritt holt drei Systemrechte: exakte Alarme, Mitteilungen,
Akkuoptimierung aus. Ohne sie feuern Erinnerungen unzuverlässig, und
unzuverlässige Zeittrigger entwerten das Konzept (R4).
