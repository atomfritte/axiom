# 08 — Geräteintegration: Samsung Galaxy S25 Ultra

Das Gerät ist ein echter Architekturvorteil. Mehrere Defizite aus der Analyse sind hier
**hardwareseitig** adressierbar — vor allem D9 (Erfassungslücke) und D4 (Zeitkosten).

---

## 1. Erfassungskanäle (M1) — Zielwert < 3 Sekunden

Priorisiert nach Reibung. Reibung entscheidet über Nutzung, nicht Funktionsumfang.

| Kanal | Ablauf | Reibung | Verfügbar |
|---|---|---|---|
| **S-Pen Screen-Off-Memo** | Stift ziehen → schreiben → fertig | **minimal** — kein Entsperren | ★ Primärkanal |
| Quick Settings Tile | herunterwischen → tippen → diktieren/tippen | sehr niedrig | überall |
| Home-Widget | tippen → tippen | niedrig | Homescreen |
| Share-Intent | aus jeder App teilen → AXIOM | niedrig | app-abhängig |
| Bixby / Sprache | "Hey Bixby, AXIOM notiere …" | niedrig, aber unzuverlässig | situativ |
| Edge Panel | von der Kante wischen | mittel | überall |

**Der S-Pen ist der strategische Hebel.** Kein anderes Android-Gerät bietet Erfassung ohne
Entsperren, ohne App-Start, ohne Auswahl. Genau das Fenster von wenigen Sekunden, in dem der
Gedanke noch existiert (D9), ist hier abgedeckt.

**Umsetzung:** Screen-Off-Memos landen in Samsung Notes. AXIOM importiert sie periodisch
(Ordner-Watch bzw. Notes-Export) und leert die Quelle. Nicht elegant, aber der reibungsärmste
verfügbare Weg — und Reibung schlägt Eleganz.

**Nicht verhandelbar:** Beim Erfassen wird **nie** nach Kategorie, Projekt, Priorität oder Datum
gefragt. Rein damit, Triage später im Review. Jede Rückfrage im Erfassungsmoment kostet den
Gedanken.

---

## 2. Ausgabekanäle

| Kanal | Nutzung | Modul |
|---|---|---|
| **Home-Widget** | "Jetzt: X" + nächster Zeitanker, permanent sichtbar | M2, M3 |
| **Always-On-Display** | nächster Anker + Restzeit, ohne Bildschirm zu wecken | M3 |
| **Exakte Alarme** | zeitgetriggerte Interventionen — der wirksamste Typ (D4) | M3, M7, M8 |
| **Notification (silent)** | `nudge`-Stufe, wegwischbar | alle |
| **Notification (alerting)** | `intervene`-Stufe, verlangt Antwort | M4, M6 |
| **Foreground Service** | während aktiver Fokus-/Reiz-Slots | M4, M5 |
| **Full-Screen Intent** | nur `enforce` (Cooldown-Ablauf, L3-Eskalation) | M6, M9 |

Widget und AOD lösen **Objektpermanenz** (D9): Was nicht sichtbar ist, existiert für dieses Profil
nicht. Der nächste Anker muss ohne Interaktion sichtbar sein.

---

## 3. Sensorik & Datenquellen

| Quelle | Daten | Speist |
|---|---|---|
| **Health Connect** | Schlafphasen, Schlafdauer, Schritte, Herzfrequenz, HRV | `sleepDebt`, `capacity`, `loadIndex` |
| Galaxy Watch (falls vorhanden) | HR, HRV, Schlaf, Bewegung | `loadIndex`, M4 Bewegungslosigkeitserkennung |
| Bildschirmzeit / Usage Stats | App-Nutzung, Entsperrvorgänge, Nachtnutzung | M4 Hyperfokus, M8 Nacht-Kaskade |
| Kalender (lesend) | Termine | M3 Backward-Chaining |
| Standort (grob, optional) | zu Hause / unterwegs | Kontextfilter M2 |

Alle Quellen sind **einzeln abschaltbar**. Voreinstellung: nur Health Connect und Kalender.
Standort und Usage Stats sind opt-in — sie sind die invasivsten und liefern den geringsten
Grenznutzen.

---

## 4. Automation

### Samsung Modes & Routines
AXIOM sendet Broadcast-Intents, die Samsung-Routinen auslösen:

```
axiom.FOCUS_START   → DND an, Graustufen, Fokusmodus       (M4)
axiom.FOCUS_END     → zurücksetzen
axiom.WINDDOWN      → Blaulichtfilter, Lautstärke runter    (M8)
axiom.L3_ENTER      → Erhaltungsmodus: Benachrichtigungen minimieren  (M9)
```

Umgekehrt können Routinen AXIOM triggern (Ankunft zu Hause, Bluetooth-Auto verbunden,
Kopfhörer verbunden → Kontextwechsel-Event).

**Warum über Samsung-Routinen statt direkter API:** Der Nutzer kann die Automation selbst sehen und
ändern, ohne die App anzufassen. Das entspricht G2 (Erklärbarkeit) und gibt dem Systemizing-Drive
ein legitimes Betätigungsfeld außerhalb des Codes.

---

## 5. Kritische Android-Fallstricke

Diese Punkte sind **in S1 zu verifizieren**, nicht später. Sie können das Konzept entwerten.

### 5.1 Akku-Optimierung ⚠️
Samsung beendet Hintergrundprozesse aggressiv (One UI "Apps im Ruhezustand"). Zeittrigger sind
der wirksamste Interventionstyp dieses Profils (D4) — wenn sie unzuverlässig feuern, ist der Kern
entwertet.

**Onboarding muss erzwingen:**
- Einstellungen → Akku → Nutzungsbegrenzung → AXIOM aus "Ruhende Apps" **und** "Tief ruhende Apps" entfernen
- Akkuoptimierung: **Nicht optimiert**
- Autostart erlauben

**Selbsttest:** AXIOM setzt täglich einen Kontroll-Alarm und protokolliert die tatsächliche
Feuerzeit. Drift > 2 min wird sichtbar gemeldet. Ein stiller Ausfall ist schlimmer als ein lauter.

### 5.2 `SCHEDULE_EXACT_ALARM`
Ab Android 14 explizite Nutzerfreigabe erforderlich. Ohne sie keine minutengenauen Anker.
Im Onboarding abfragen, Status dauerhaft prüfen.

### 5.3 Health Connect
Granulare Einzelberechtigungen pro Datentyp. Berechtigungen können ohne Vorwarnung entzogen
werden — Verfügbarkeit vor jeder Nutzung prüfen, sonst rechnet der StateDeriver mit Lücken
(→ Konfidenzwert, siehe R8).

### 5.4 Notification Channels
Pro `severity` ein eigener Channel — sonst kann der Nutzer nur alles oder nichts stummschalten.

```
axiom_info       stumm, ohne Badge
axiom_nudge      stumm, mit Badge
axiom_intervene  Ton, Heads-up
axiom_enforce    Ton + Full-Screen, Bypass DND
```

Nur `axiom_enforce` darf DND und Ruhezeiten durchbrechen — und nur für vom Nutzer autorisierte
Regeln (siehe [Regelwerk §4](04-REGELWERK.md)).

---

## 6. Linux-Desktop-Companion (S3)

Flutter Linux-Build auf dem CachyOS-Rechner:

| Funktion | Zweck |
|---|---|
| Deep-Work-Erkennung | aktives Fenster + Eingabeaktivität → `focus_start`/`focus_end` automatisch |
| Erfassung per Hotkey | globaler Shortcut → Capture ohne Kontextwechsel |
| Review-Ansicht | Wochenreview am großen Bildschirm — die einzige Ansicht, die Fläche braucht |
| Regelbearbeitung | YAML im Editor, Validator lokal (nur im Review-Fenster, M12) |

Sync über lokales Netz, E2E-verschlüsselt, kein Server nötig (S4).

Der Desktop-Companion ist **kein** zweiter vollständiger Client. Er ist Erfassung + Review. Alles
Interaktive bleibt auf dem Telefon, weil dort das Leben stattfindet.

---

## 7. Berechtigungen — Minimalprinzip

| Berechtigung | Zweck | Pflicht |
|---|---|---|
| `SCHEDULE_EXACT_ALARM` | Zeitanker | ✔ kritisch |
| `POST_NOTIFICATIONS` | Interventionen | ✔ |
| `READ_CALENDAR` | Backward-Chaining | ✔ für M3 |
| Health Connect (Schlaf, Schritte, HR) | Zustandsableitung | ✔ für M7/M8/M9 |
| `FOREGROUND_SERVICE` | aktive Slots | ✔ für M4/M5 |
| `PACKAGE_USAGE_STATS` | Hyperfokus-Erkennung | ✖ opt-in |
| Standort (grob) | Kontextfilter | ✖ opt-in |
| **INTERNET** | **nur bei aktivem Sync (S4)** | ✖ **in S1–S3 gar nicht deklariert** |

`INTERNET` wird in S1–S3 **nicht im Manifest deklariert**. Damit ist auf Systemebene garantiert,
dass keine Gesundheitsdaten das Gerät verlassen können — unabhängig von jedem Bug, jeder
Abhängigkeit und jedem Versehen. Das ist stärker als jede Zusicherung im Code (R6).
