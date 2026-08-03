<img src="assets/brand/axiom-wordmark.svg" alt="AXIOM" width="320">

*[English](README.md) · **Deutsch***

Deterministisches, lokal laufendes Regelwerk zur Selbstregulation.
Ein Exocortex für ein hochkompensiertes ADHS-Profil.

**Privat. Ein Nutzer. Ein Gerät. Kein Produkt.**

---

> ⚠️ **Kein Medizinprodukt.** AXIOM ist keine Diagnostik, keine Therapie und kein Ersatz für
> ärztliche oder psychotherapeutische Behandlung. Es misst selbst berichtete und gerätegemessene
> Zustände und wendet **selbst gesetzte** Regeln darauf an — mehr nicht.

---

## Die Idee in drei Sätzen

Ein hochkompensiertes ADHS-Profil scheitert nicht an fehlender Struktur, sondern daran, dass die
Struktur jeden Tag neu im Kopf erzeugt werden muss. AXIOM übernimmt die Erzeugung: Zustand messen,
selbst gesetzte Regeln anwenden, **genau eine** nächste Handlung ausgeben — mit Begründung und
Regel-ID.

Erfolgsmaß ist nicht "mehr erledigt", sondern **gleiche Leistung bei geringerer kognitiver Last**.

## Was AXIOM anders macht

| Klassische App | AXIOM |
|---|---|
| Fragt *Was willst du tun?* | Fragt *In welchem Zustand bist du?* |
| Modelliert `priority` | Modelliert `activation_energy` gegen verfügbare Kapazität |
| Zeigt eine Liste | Zeigt **eine** Handlung + `rule_id` + Begründung |
| Belohnt Nutzung | **Deckelt** Nutzung (Meta-Guard) |

## Dokumentation

| Dokument | Inhalt |
|---|---|
| [00-KONZEPT](docs/00-KONZEPT.md) | Was AXIOM ist, die vier Systemgesetze, alle 13 Module |
| [01-PROFIL-DEFIZITE](docs/01-PROFIL-DEFIZITE.md) | Defizitanalyse D1–D12 — die Grundlage von allem |
| [02-ARCHITEKTUR](docs/02-ARCHITEKTUR.md) | Schichten, Ports, Auswertungszyklus |
| [03-DATENMODELL](docs/03-DATENMODELL.md) | Events, StateVector, Task, Formeln |
| [04-REGELWERK](docs/04-REGELWERK.md) | Regel-DSL, Semantik, Konfliktauflösung |
| [05-ROADMAP](docs/05-ROADMAP.md) | Stufen S1–S4 mit Abbruchkriterien |
| [06-METRIKEN](docs/06-METRIKEN.md) | Erfolgsmessung, Baseline-Protokoll |
| [07-RISIKEN](docs/07-RISIKEN.md) | Was schiefgeht — R1 ist das entscheidende |
| [08-GERAET-S25U](docs/08-GERAET-S25U.md) | S-Pen, Health Connect, Android-Fallstricke |
| [ADR](docs/adr/) | Architekturentscheidungen mit Begründung |
| [BACKLOG](docs/BACKLOG.md) | Ideen, die bewusst *nicht* jetzt gebaut werden |

Für Claude Code: [CLAUDE.md](CLAUDE.md)

## Stack

Flutter 3.44 / Dart 3.12 · SQLite (Drift + SQLCipher) · YAML-Regelwerk unter Git
Ziele: Android (Galaxy S25 Ultra, primär) und Linux Desktop (Companion)

## Struktur

```
packages/axiom_core   pure Dart — Domain + State Engine + Rule Engine   ← das Herz
packages/axiom_data   SQLite, YAML-Loader, Health Connect, Export
packages/axiom_app    Flutter UI, Notifications, Widgets
rules/core            mitgelieferte Regeln (versioniert)
rules/personal        persönliche Regeln (git-ignoriert)
tools/                Validator, Layering-Check, Szenario-Runner
```

## Entwicklung

```bash
# Prüfen — alles muss grün sein
dart run tools/bin/validate_rules.dart rules
dart run tools/bin/check_layering.dart .
(cd packages/axiom_core && dart analyze && dart test)
(cd packages/axiom_data && dart analyze && dart test)
(cd packages/axiom_app  && flutter analyze && flutter test)

# Regelwerk in die App-Assets spiegeln — vor jedem App-Build
dart run tools/bin/sync_rules.dart

# Starten
(cd packages/axiom_app && flutter run -d linux)
(cd packages/axiom_app && flutter run -d <geraet>)     # adb devices
```

## Status

**S1 bis S4 stehen.** Android-APK und Linux-Desktop bauen und starten.

| | |
|---|---|
| Tests | 451 grün (215 Core · 88 Daten · 148 App) |
| Analyzer | keine Meldungen in allen Paketen |
| Regelwerk | 17 Regeln gültig, 16 aktiv — davon 8 **ungeeicht** |
| Release-APK | gebaut, **ohne INTERNET-Berechtigung** — im APK verifiziert |

**Stufe 1** — Erfassung (< 3 s), Check-in, Kapazitätslinie, Zustandsanzeige
mit Herleitung, Regelinspektor, Meta-Guard, Onboarding, Widget, Quick Tile,
exakte Alarme, App-Shortcuts, Share-Ziel.

**Stufe 2** — Zeitanker mit Rückwärtsverkettung (M3), Atomizer (M2),
Körpersignale (M7), Abendgrenze und Schlaferfassung (M8), Review mit
erzwungenem Zeitdeckel (M11).

**Stufe 3** — Focus Governor (M4), Reiz-Haushalt mit Slot-als-Währung (M5),
Impuls-Bremse mit selbst geschriebener Checkliste (M6), Load Monitor mit
realen Konsequenzen bis zum Erhaltungsmodus (M9).

**Stufe 4** — Signal-Log mit getrenntem Erfassen und Nachbetrachten (M10),
Wirkfenster-Protokoll (M13, opt-in), verschlüsselter Datenabgleich per Datei
statt Server.

**Systemanbindung** — Live Update des laufenden Fokus-Slots in
Statusleisten-Pille, Sperrbildschirm und Samsungs Now Bar (Android 16,
`ProgressStyle` + `requestPromotedOngoing`); Health Connect für Schlaffenster
und Tagesschritte, idempotent importiert; Direct Share als festes Ziel im
Teilen-Blatt.

### Zwei Sprachen

Deutsch ist die Quelle, Englisch die Übersetzung — umschaltbar unter
*System → Anzeige*. Besonderheit: Der **deutsche Satz ist der Schlüssel**.

```dart
Text(context.t('Nichts in Reichweite'))
```

Damit bleibt die Formulierung dort lesbar, wo sie gewählt wurde. Genau darauf
kommt es hier an: „Nichts in Reichweite" ist eine bewusste Entscheidung gegen
„Du hast 14 offene Aufgaben", und diese Entscheidung soll nicht hinter einem
Bezeichner wie `now.emptyTitle` verschwinden.

Drei Ebenen sind abgedeckt:

| Ebene | Wo | Wie |
|---|---|---|
| Oberfläche | `lib/i18n/en.dart` | deutscher Satz → englischer Satz |
| Kern | `Phrase('{0} min über …', [n])` | Quelltext und Werte getrennt, damit Zahlen nicht zurückgerechnet werden müssen |
| Regelwerk | `title_en`, `rationale_en` im YAML | Regeln sind Daten, ihre Übersetzung auch |

`i18n_test.dart` hält drei Dinge fest: **jeder** übersetzbare Text hat eine
englische Fassung, die Platzhalter stimmen auf beiden Seiten überein, und der
Ton hält — keine Schuldsprache, keine Ausrufezeichen. Eine Übersetzung kann
aus einem Messwert unbemerkt ein Urteil machen; das ist der eigentliche Grund
für diesen Test.

### Wege in die App hinein

Zwischen Einfall und Notiz liegen wenige Sekunden. Was in dieser Zeit nicht
festgehalten ist, ist weg (D9) — deshalb gibt es nicht einen Weg, sondern
sieben. In der App stehen sie unter *System → Erfassen*, mit Einrichtung.

| Weg | Reibung | Wie |
|---|---|---|
| **Dauerhafte Benachrichtigung** | minimal | Tippen direkt in der Benachrichtigung, ohne Entsperren (`RemoteInput`) |
| Schnelleinstellung | sehr niedrig | Quick-Settings-Kachel |
| Homescreen-Widget | niedrig | nächste Handlung + Kapazität, Tipp führt ins Eingabefeld |
| App-Shortcut | niedrig | langes Tippen aufs Symbol |
| Teilen aus anderen Apps | niedrig | `ACTION_SEND` |
| S-Pen | niedrig | `ACTION_CREATE_NOTE` (Android 14+), zusätzlich auf Air Actions legbar |
| Sprache | niedrig | `actions.intent.CREATE_NOTE` für Assistant, Bixby-Routine |

Zwei Grenzen des Systems, ausdrücklich benannt:

- **Lockscreen-Widgets gibt es auf Android nicht** — mit 5.0 entfernt. Der
  verbliebene Weg zu ständiger Sichtbarkeit im gesperrten Zustand ist die
  dauerhafte Benachrichtigung (`VISIBILITY_PUBLIC`).
- **Samsung Notes hat keine öffentliche Schnittstelle.** Screen-off-Memos
  bleiben dort. Der offizielle Stift-Weg ist `ACTION_CREATE_NOTE`.

### Eichung

Die Formelgewichte in `rules/core/weights.yaml` sind geschätzt, nicht gemessen.
Acht aktive Regeln prüfen auf abgeleitete Werte und können deshalb
danebenliegen. Sie laufen trotzdem — eine bewusste Entscheidung. Der
Systeminspektor markiert sie als **UNGEEICHT**.

**Wo du den Stand siehst:** In der App unter *System → Eichung*. Dort stehen
drei Bedingungen mit Fortschritt — und wenn alle erfüllt sind, der komplette
Ablauf mit kopierbaren Befehlen.

| Bedingung | Nötig | Warum |
|---|---|---|
| Tage | 14 | Kürzer erfasst keinen vollen Wochenrhythmus |
| Messpunkte | 20 Check-ins | Darunter ist das circadiane Profil nicht belastbar |
| Nächte | 7 Schlafeinträge | Für die Schlaf-Kapazitäts-Kopplung |

**Zeit allein reicht nicht.** Vierzehn Tage mit fünf Check-ins würden die
Gewichte auf Rauschen eichen — schlechter als eine ehrliche Schätzung. Deshalb
werden alle drei getrennt geprüft und angezeigt.

Sind sie erfüllt, meldet sich die Hauptansicht von selbst. Der Ablauf dann:

```bash
adb exec-out run-as de.axiom.axiom_app cat files/axiom.db > axiom.db
dart run tools/bin/calibrate.dart axiom.db      # schreibt nichts, schlägt vor
# Vorschläge im Wochen-Review prüfen, dann in rules/core/weights.yaml
# eintragen und dort calibration.status auf calibrated setzen:
dart run tools/bin/sync_rules.dart
```

Danach verschwinden die UNGEEICHT-Markierungen.

## Wie es aussieht

<p>
  <img src="packages/axiom_app/test/screenshots/04-jetzt-aufgaben.png" width="180" alt="Jetzt — eine Handlung mit ihrer Regel">
  <img src="packages/axiom_app/test/screenshots/05-zustand.png" width="180" alt="Zustand — sechs Messwerte mit Herleitung">
  <img src="packages/axiom_app/test/screenshots/10-zerlegen.png" width="180" alt="Zerlegen — aus einer Aufgabe einen ersten Schritt">
  <img src="packages/axiom_app/test/screenshots/12-fokus.png" width="180" alt="Fokus — laufender Block">
</p>
<p>
  <img src="packages/axiom_app/test/screenshots/02-onboarding-linie.png" width="180" alt="Onboarding — die Kapazitätslinie erklärt">
  <img src="packages/axiom_app/test/screenshots/06-system.png" width="180" alt="System — der Regelinspektor">
  <img src="packages/axiom_app/test/screenshots/14-bremse.png" width="180" alt="Bremse — Wartezeit mit den eigenen Fragen">
  <img src="packages/axiom_app/test/screenshots/08-jetzt-hell.png" width="180" alt="Derselbe Screen in hell">
</p>

Von links: **eine Handlung** mit der Regel, die sie erzeugt hat · der **Zustand** dahinter, jede
Zahl aufklappbar bis zur Formel · **Zerlegen** von etwas außer Reichweite in einen ersten Schritt ·
ein **laufender Fokusblock**. Darunter: die Kapazitätslinie im Onboarding · der
**Regelinspektor** · die **Impuls-Bremse** mit den eigenen Fragen · dieselbe Hauptansicht in hell.

Das sind keine Werbebilder, sondern die Referenzbilder aus
`packages/axiom_app/test/screenshots/`. Sie entstehen aus den Tests — sie können also nicht vom
Code abweichen, ohne dass ein Test rot wird.

## Die Bildmarke

Eine Skala mit einem gesetzten Schwellenstrich. Links, kräftig: was in
Reichweite ist. Rechts, gedämpft: was heute darüber hinausgeht. Genau das
Kernbild der App — und genau das, was ein Axiom ist: eine Grenze, die man
setzt, nicht ableitet.

Kein Gehirn, keine Glühbirne, kein Häkchen, keine Zielfahne. Das Zeichen
kommt aus der Welt der Messinstrumente, nicht aus der Bildsprache von
Selbstoptimierungs-Apps.

Quellen in `assets/brand/`. Die Android-Symbole werden daraus erzeugt:

```bash
tools/bin/make-icons.sh
```
