# ADR-0001 — Technologie-Stack: Flutter + Dart

**Status:** akzeptiert · **Datum:** 2026-08-03

## Kontext

Zielgerät ist ein Samsung Galaxy S25 Ultra (Android 15+). Der Entwicklungsrechner läuft Linux
(CachyOS). Ein Desktop-Companion für Deep-Work-Erkennung und Wochenreview ist ab S3 vorgesehen.
Ein Nutzer, ein Entwickler, kein Veröffentlichungsdruck.

Kritische Anforderungen:
- **Minutengenaue Zeittrigger** (exakte Alarme) — der wirksamste Interventionstyp dieses Profils (D4)
- Home-Widget, Quick-Tile, Always-On-Display-Integration (D9 Objektpermanenz)
- Health Connect
- Vollständige Offline-Fähigkeit, lokal verschlüsselte Datenhaltung
- **Kern ohne UI testbar** — das Regelwerk ist das Risiko, nicht das Layout

## Erwogene Optionen

**PWA / Web** — schnellster Start, plattformunabhängig.
✗ **Ausgeschlossen.** Keine zuverlässigen exakten Alarme, keine Home-Widgets, keine Screen-Off-Erfassung,
kein Health Connect. Da Zeittrigger den Kern des Konzepts tragen, wäre das Konzept selbst entwertet.

**Native Android (Kotlin)** — beste Plattformintegration.
Kein Desktop-Companion ohne zweite Codebase. Kein Vorteil bei Widgets/Alarmen, der über
Flutter-Plugins nicht erreichbar wäre.

**React Native** — großes Ökosystem.
Schwächere Desktop-Story, mehr Bridge-Reibung bei nativen Diensten, Node-Toolchain als
Zusatzkomplexität ohne Gegenwert.

**Flutter** — eine Codebase für Android und Linux-Desktop.
Toolchain bereits installiert und lauffähig (3.44.4 stable / Dart 3.12.2).
Der entscheidende Punkt: **Dart erlaubt einen vollständig UI-freien Kern als reines Package**, der
mit `dart test` ohne Emulator, ohne Gerät, ohne Flutter läuft.

## Entscheidung

**Flutter (Android primär, Linux als Companion) mit striktem Package-Schnitt:**

```
axiom_core   pure Dart — Domain + Engine. Keine Flutter-Abhängigkeit.
axiom_data   SQLite/Drift, YAML, Health, Export.
axiom_app    Flutter UI + Plattformkanäle.
```

## Begründung

1. **Testbarkeit des Kerns** — Regeln sind die Substanz dieses Projekts. Sie müssen als Unit-Tests
   überprüfbar sein, nicht durch Anklicken. Ein UI-freies Dart-Package liefert das direkt.
2. **Desktop-Companion ohne zweite Codebase** — realer Mehrwert (Deep-Work-Erkennung, Review am
   großen Bildschirm) zu geringen Grenzkosten.
3. **Toolchain vorhanden** — Flutter, Dart, Android SDK, Java 17 sind installiert. Kein Setup-Overhead,
   und Setup-Overhead ist bei diesem Profil ein realer Projektkiller (R1).
4. **Plattformzugriff ausreichend** — exakte Alarme, Widgets, Health Connect und Notification
   Channels sind über etablierte Plugins bzw. schmale Platform Channels erreichbar.

## Konsequenzen

**Positiv:** Ein Kern, zwei Plattformen. Engine ohne Gerät testbar. Schneller Start.

**Negativ:**
- Widgets und Quick-Tiles erfordern nativen Kotlin-Code über Platform Channels — Flutter deckt das
  nicht direkt ab. Aufwand ist eingeplant.
- Die Screen-Off-Memo-Anbindung läuft über Samsung Notes (Import-Watch), nicht über eine direkte API.
  Nicht elegant, aber der reibungsärmste verfügbare Erfassungsweg — und Reibung schlägt Eleganz (D9).

**Risiken:** siehe R4 (Android-Hintergrundbeschränkungen) in [07-RISIKEN](../07-RISIKEN.md).
