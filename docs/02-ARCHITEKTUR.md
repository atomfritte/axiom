# 02 — Architektur

## 1. Leitprinzipien

1. **Der Kern ist UI-frei.** Zustandsberechnung und Regelauswertung liegen in `axiom_core`, einem
   reinen Dart-Package ohne Flutter-Abhängigkeit. Es ist ohne Emulator, ohne Gerät und ohne UI
   vollständig testbar. → *Regeln werden getestet, nicht angeklickt.*
2. **Local-first, immer.** Keine Netzwerkabhängigkeit im kritischen Pfad. Die App funktioniert im
   Flugmodus vollständig. Sync ist optional und additiv.
3. **Determinismus.** `evaluate(state, ruleset) → decision` ist eine reine Funktion. Zeit,
   Zufall und I/O werden injiziert (`Clock`, `Random`), nie direkt aufgerufen. Voraussetzung für
   Reproduzierbarkeit, Zeitreise-Tests und Nachvollziehbarkeit (G2).
4. **Append-only Ereignisse.** Alle Signale sind unveränderliche Events. Der Zustand ist eine
   Projektion. Damit ist jede vergangene Entscheidung rekonstruierbar — die Grundlage für Audits
   und für rückwirkende Regelanalyse ("hätte die neue Regel damals besser entschieden?").
5. **Regeln sind Daten.** YAML, unter Git, zur Laufzeit geladen. Eine Regeländerung ist ein Commit
   und ein Diff, kein Rebuild.

---

## 2. Systemüberblick

```
┌─────────────────────────────────────────────────────────────────────┐
│  PRESENTATION                       packages/axiom_app  (Flutter)   │
│  Android (primär) · Linux Desktop (Companion)                       │
│  Widgets · Quick-Tile · Notifications · S-Pen Capture               │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ nur über Ports (Interfaces)
┌───────────────────────────────▼─────────────────────────────────────┐
│  CORE                               packages/axiom_core  (pure Dart)│
│                                                                     │
│   Domain          Event · StateVector · Task · Rule · Decision      │
│   Engine          StateDeriver → RuleEngine → DecisionResolver      │
│   Ports           EventStore · RuleSource · Clock · Notifier ·      │
│                   HealthSource · DeviceAutomation                   │
│                                                                     │
│   KEINE Flutter-, Platform- oder I/O-Abhängigkeit.                  │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ Port-Implementierungen
┌───────────────────────────────▼─────────────────────────────────────┐
│  INFRASTRUCTURE                     packages/axiom_data             │
│  SQLite (Drift, SQLCipher) · YAML-Loader · Health Connect ·         │
│  Alarm/Notification-Scheduler · Export/Backup                       │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ optional, ab S4
┌───────────────────────────────▼─────────────────────────────────────┐
│  SYNC (self-hosted, optional)       ops/sync                        │
│  Docker · E2E-verschlüsselter Blob-Sync · Server sieht Klartext nie │
└─────────────────────────────────────────────────────────────────────┘
```

**Abhängigkeitsrichtung: immer nach innen.** `axiom_core` kennt weder `axiom_app` noch
`axiom_data`. Verletzungen dieser Regel werden im CI geprüft (`tools/check_layering.dart`).

---

## 3. Packages

| Package | Typ | Verantwortung | Darf abhängen von |
|---|---|---|---|
| `axiom_core` | pure Dart | Domain, State Engine, Rule Engine, Ports | nichts Externes (nur `meta`, `collection`) |
| `axiom_data` | Dart | SQLite/Drift, YAML-Loader, Health, Export | `axiom_core` |
| `axiom_app` | Flutter | UI, Notifications, Widgets, Platform-Kanäle | `axiom_core`, `axiom_data` |
| `ops/sync` | Docker | optionaler Sync-Endpoint | — |

---

## 4. Der Auswertungszyklus

Der einzige Pfad, über den AXIOM je eine Ausgabe erzeugt:

```
  1. INGEST      Event kommt an (Check-in, Timer, Health-Sample, Capture, Kalender)
                 └─> append-only in den EventStore. Unveränderlich.

  2. DERIVE      StateDeriver projiziert Events → StateVector
                 └─> capacity · focus_debt · sensation_need · load_index · regulation
                 └─> jede Dimension: reine Funktion mit dokumentierter Formel  (G2)

  3. EVALUATE    RuleEngine wertet ALLE Regeln gegen den StateVector aus
                 └─> Ergebnis: Liste feuernder Regeln, je mit Priorität + Aktion

  4. RESOLVE     DecisionResolver löst Konflikte deterministisch auf
                 └─> Sortierung: (severity, priority, rule_id)  — total, stabil, ohne Zufall
                 └─> Ergebnis: GENAU EINE nächste Handlung  (G1: keine Auswahl-Last)

  5. EMIT        Ausgabe an die UI — immer mit rule_id + menschenlesbarer Begründung
                 └─> Entscheidung wird selbst als Event geloggt (Audit-Trail)

  6. FEEDBACK    Reaktion des Nutzers (befolgt / verschoben / abgelehnt) → Event
                 └─> speist die Regelqualitäts-Metrik im Wochenreview
```

**Schritt 4 ist der Kern.** Klassische Apps zeigen eine Liste und delegieren die Auswahl an den
Nutzer — genau die Entscheidung, die bei niedriger Kapazität am teuersten ist. AXIOM entscheidet
und begründet. Die Liste bleibt zugänglich, ist aber nie der Standardweg.

---

## 5. Ports (Interfaces im Core)

Der Core definiert, die Infrastruktur implementiert. Tests nutzen In-Memory-Fakes.

| Port | Zweck | Prod-Implementierung |
|---|---|---|
| `EventStore` | append / query Events | Drift + SQLite (SQLCipher) |
| `RuleSource` | Regelwerk laden + validieren | YAML aus `rules/`, App-Assets + User-Overlay |
| `Clock` | **jede** Zeitabfrage | `SystemClock` / `FakeClock` (Tests) |
| `Notifier` | Interventionen ausspielen | Android Notifications + exakte Alarme |
| `HealthSource` | Schlaf, Schritte, HR | Health Connect (Android) |
| `DeviceAutomation` | DND, Fokusmodus, Routinen | Android APIs / Samsung Modes&Routines |
| `SecureStore` | Schlüssel, Biometrie-Gate | Android Keystore |

`Clock` als Port ist nicht optional: ohne ihn sind zeitabhängige Regeln (also fast alle) nicht
deterministisch testbar. Direkte `DateTime.now()`-Aufrufe im Core sind ein CI-Fehler.

---

## 6. Datenfluss & Speicherung

- **Events** — append-only, unveränderlich. Nie UPDATE, nie DELETE (außer bei explizitem Purge
  durch den Nutzer). Die Quelle der Wahrheit.
- **Snapshots** — periodische StateVector-Projektionen zur Beschleunigung. Jederzeit aus Events
  neu berechenbar, also verwerfbar.
- **Tasks** — mutabler Projektionszustand, aber jede Änderung erzeugt zusätzlich ein Event.
- **Decisions** — jede Ausgabe wird protokolliert: Zeit, Zustand, Regel-ID, Nutzerreaktion.
  Das ist das Audit-Log, das G2 einlösbar macht.

Verschlüsselung: SQLCipher, Schlüssel im Android Keystore, Biometrie-Gate beim Start.
Backup: signierter, verschlüsselter Export (`.axiom` = tar + age/libsodium) auf Nutzerwunsch.

Details: [03-DATENMODELL.md](03-DATENMODELL.md)

---

## 7. Plattform-Integration (Samsung Galaxy S25 Ultra)

Die Geräteauswahl ist ein echter Architekturvorteil — mehrere Reibungsprobleme aus D9 und D4 sind
hier hardwareseitig lösbar.

| Fähigkeit | Nutzung in AXIOM | Modul |
|---|---|---|
| **S-Pen Screen-Off-Memo** | Erfassung ohne Entsperren. Der reibungsärmste Kanal, den das Gerät bietet. | M1 |
| **Quick Settings Tile** | 1-Tap-Capture aus jedem Kontext | M1 |
| **Home-Widget** | "Jetzt: X" + Zeitanker permanent sichtbar (Objektpermanenz) | M2, M3 |
| **Always-On-Display** | Nächster Anker ohne Bildschirmaktivierung | M3 |
| **Exakte Alarme** (`SCHEDULE_EXACT_ALARM`) | Zeittrigger sind der wirksamste Interventionstyp (D4) — Minutengenauigkeit ist Pflicht | M3, M7, M8 |
| **Health Connect** | Schlaf, Schritte, Herzfrequenz → `capacity`, `load_index` | M7, M8, M9 |
| **Modes & Routines** | DND-Automation für Deep-Work-Slots | M4 |
| **Bixby Routines / Intents** | externe Trigger in AXIOM hinein | M1, M6 |
| **DeX / Linux-Desktop** | Deep-Work-Erkennung am Rechner | M4 |

**Bekannte Fallstricke** — früh testen, nicht spät entdecken:
- Samsungs aggressive Akku-Optimierung killt Hintergrundprozesse. Onboarding muss die
  Batterieoptimierung für AXIOM abschalten lassen, sonst feuern Alarme unzuverlässig — und
  unzuverlässige Zeittrigger entwerten das gesamte Konzept (D4).
- `SCHEDULE_EXACT_ALARM` erfordert ab Android 14 explizite Nutzerfreigabe.
- Health Connect braucht granulare Einzelberechtigungen pro Datentyp.

---

## 8. Was bewusst NICHT gebaut wird

| Nicht gebaut | Grund |
|---|---|
| Account-System, Cloud-Backend | Ein Nutzer, ein Gerät. Local-first. Verletzt sonst die Datenhoheit |
| Microservices | Eine App, ein Nutzer. Jede Verteilung wäre reiner Selbstzweck |
| ML-Modell in der Entscheidungsschleife | Verletzt G2 (Auditierbarkeit). Deterministische Regeln schlagen hier ein Blackbox-Modell |
| Plugin-System / Skripting-Layer | Direkter Meta-Work-Treibstoff (D3). YAML-Regeln sind die Erweiterungsgrenze |
| Multi-User, Rollen, Rechte | Kein Anwendungsfall |
| Web-Frontend | Kein Anwendungsfall, zusätzliche Angriffsfläche für Gesundheitsdaten |
| GPS, Geofences, Standortberechtigung | Ein Geofence beantwortet „wo bin ich", die Frage ist aber „was geht hier". Er kostet `ACCESS_BACKGROUND_LOCATION`, verlangt Play Services oder einen dauerhaft messenden Dienst und legt in einer Datenbank mit Gesundheitsdaten ein Bewegungsprofil an. Ortsgebundene Aufgaben laufen stattdessen über einen frei vergebenen Namen (`Task.place`), gesetzt in der App oder per Broadcast `de.atomfritte.axiom.PLACE` aus einer Geräteroutine |

Diese Liste ist Teil der Architektur. Ein hochkompensierter Systemizer wird beim Bauen genau diese
Erweiterungen attraktiv finden — deshalb stehen sie hier explizit als abgelehnt.

---

## 9. Qualitätssicherung

- **Regel-Tests** — jede Regel in `rules/` braucht mindestens einen Test mit fixiertem `FakeClock`
  und erwartetem Ergebnis. Eine ungetestete Regel wird nicht geladen (CI-Gate).
- **Golden-Szenarien** — komplette simulierte Tage als Event-Ströme mit erwarteter
  Entscheidungssequenz. Fängt Regelkonflikte, die Einzeltests nicht sehen.
- **Layering-Check** — `tools/check_layering.dart` bricht den Build bei Abhängigkeitsverletzungen.
- **Determinismus-Check** — dieselbe Event-Sequenz muss zweimal dieselbe Entscheidungsfolge
  erzeugen. Fängt versehentliche `DateTime.now()`- und `Random()`-Aufrufe.
- **Kein Netzwerk im Core** — statisch geprüft.

---

## 10. Verzeichnisstruktur

```
adhs_master/
├── CLAUDE.md                  Arbeitsanweisung für Claude Code (Gesetze, Konventionen, Gates)
├── docs/
│   ├── 00-KONZEPT.md          Was AXIOM ist und warum
│   ├── 01-PROFIL-DEFIZITE.md  Defizitanalyse D1–D12 → Module M0–M13
│   ├── 02-ARCHITEKTUR.md      dieses Dokument
│   ├── 03-DATENMODELL.md      Events, StateVector, Tasks, Formeln
│   ├── 04-REGELWERK.md        Regel-DSL, Semantik, Konfliktauflösung
│   ├── 05-ROADMAP.md          Stufen S1–S4 mit Abbruchkriterien
│   ├── 06-METRIKEN.md         Erfolgsmessung, Baseline-Protokoll
│   ├── 07-RISIKEN.md          Projekt- und Wirkungsrisiken
│   ├── 08-GERAET-S25U.md      Gerätespezifische Integration
│   └── adr/                   Architekturentscheidungen (unveränderlich, nur superseded)
├── packages/
│   ├── axiom_core/            pure Dart — Domain + Engine
│   ├── axiom_data/            SQLite, YAML, Health, Export
│   └── axiom_app/             Flutter — Android + Linux
├── rules/
│   ├── core/                  mitgelieferte Basisregeln (versioniert)
│   └── personal/              persönliche Regeln (git-ignoriert, private Daten)
├── ops/sync/                  optionaler self-hosted Sync (S4)
└── tools/                     Layering-Check, Regel-Validator, Szenario-Runner
```
