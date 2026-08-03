# 08 — Geräteintegration: Samsung Galaxy S25 Ultra

Das Gerät ist ein echter Architekturvorteil. Mehrere Defizite aus der Analyse sind hier
**hardwareseitig** adressierbar — vor allem D9 (Erfassungslücke) und D4 (Zeitkosten).

---

## 1. Erfassungskanäle (M1) — Zielwert < 3 Sekunden

Priorisiert nach Reibung. Reibung entscheidet über Nutzung, nicht Funktionsumfang.

| Kanal | Ablauf | Reibung | Stand |
|---|---|---|---|
| **Dauerhafte Benachrichtigung** | aufziehen → tippen → schreiben, ohne Entsperren | **minimal** | ✅ Primärkanal |
| Quick Settings Tile | herunterwischen → tippen → schreiben | sehr niedrig | ✅ |
| Home-Widget | tippen → tippen | niedrig | ✅ |
| App-Shortcut | langes Tippen aufs Symbol | niedrig | ✅ |
| Share-Intent | aus jeder App teilen → AXIOM | niedrig | ✅ |
| S-Pen über `ACTION_CREATE_NOTE` | Stift doppelt tippen → AXIOM | niedrig | ✅ registriert |
| Sprache (Assistant / Bixby) | „Notiz in AXIOM" | niedrig, unzuverlässig | ✅ angemeldet |

### Warum die Benachrichtigung der Primärkanal ist

Ursprünglich war das S-Pen-Screen-Off-Memo als stärkster Kanal vorgesehen. Das hat sich nicht
halten lassen: **Samsung Notes hat keine öffentliche Schnittstelle.** Screen-off-Memos landen
dort, und jeder Weg heran wäre Reverse Engineering — der das nächste Systemupdate nicht
überlebt.

Der verbliebene Weg ist besser, als er zunächst klingt. Eine dauerhafte Benachrichtigung mit
`RemoteInput` erlaubt Tippen **direkt in der Benachrichtigung** — ohne Entsperren, ohne
App-Start, ohne Kontextwechsel. Zwei Sekunden statt zehn. Die App muss dafür nicht einmal
laufen: Der Text landet in `MemoInbox` und wird beim nächsten Start eingesammelt.

Für den Stift gibt es seit Android 14 den offiziellen Weg: `ACTION_CREATE_NOTE`. Damit erscheint
AXIOM beim Doppeltipp mit dem S-Pen, in der Schnelleinstellung „Notiz" und auf dem
Sperrbildschirm. Zusätzlich lässt sich die Activity in Samsungs *Air Actions* auf den Stiftknopf
legen.

**Nicht verhandelbar:** Beim Erfassen wird **nie** nach Kategorie, Projekt, Priorität oder Datum
gefragt. Rein damit, Triage später im Review. Jede Rückfrage im Erfassungsmoment kostet den
Gedanken.

---

## 2. Ausgabekanäle

| Kanal | Nutzung | Modul |
|---|---|---|
| **Home-Widget** | „Jetzt: X" + nächster Zeitanker, permanent sichtbar | M2, M3 |
| **Dauerhafte Benachrichtigung** | dieselbe Aussage, auch auf dem Sperrbildschirm | M2, M3 |
| **Exakte Alarme** | zeitgetriggerte Interventionen — der wirksamste Typ (D4) | M3, M7, M8 |
| **Notification (silent)** | `nudge`-Stufe, wegwischbar | alle |
| **Notification (alerting)** | `intervene`-Stufe, verlangt Antwort | M4, M6 |
| **Foreground Service** | während aktiver Fokus-/Reiz-Slots | M4, M5 |
| **Full-Screen Intent** | nur `enforce` (Cooldown-Ablauf, L3-Eskalation) | M6, M9 |

Widget und Benachrichtigung lösen **Objektpermanenz** (D9): Was nicht sichtbar ist, existiert für
dieses Profil nicht. Der nächste Anker muss ohne Interaktion sichtbar sein.

**Lockscreen-Widgets gibt es auf Android nicht.** Sie wurden mit Android 5.0 entfernt. Für
ständige Sichtbarkeit auch im gesperrten Zustand ist die dauerhafte Benachrichtigung mit
`VISIBILITY_PUBLIC` der verbliebene Weg — sie zeigt Inhalt statt Platzhalter und nimmt Eingaben
entgegen.

**Live Update / Now Bar (Android 16).** Eine laufende Benachrichtigung kann um
Beförderung bitten (`requestPromotedOngoing`) und erscheint dann als Pille
neben der Uhr, auf dem Sperrbildschirm und in Samsungs Now Bar. AXIOM nutzt das
für den laufenden Fokus-Slot: `ProgressStyle` mit zwei Abschnitten — geplante
Dauer in Ruhe-Grün, Überziehung in Signal-Amber. Der Farbwechsel ist die ganze
Aussage; es gibt keinen Alarm und keine Wertung (G3). Darunter bleibt es eine
gewöhnliche laufende Benachrichtigung mit Countdown.

**Fallstrick beim Widget:** Der `AppWidgetProvider` muss `android:exported="true"` haben. Der
Launcher läuft in einem anderen Prozess und muss den Update-Broadcast senden können; mit `false`
lässt sich das Widget schlicht nicht hinzufügen. Prüfbar am gebauten Paket:
`aapt2 dump badging app.apk | grep app-widget` muss `provides-component:'app-widget'` zeigen.

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

Umgesetzt: **nur lesend, nur Schlaffenster und Tagesschritte.** Zwei weitere Punkte, die
leicht übersehen werden:

- Ohne eine Activity, die `ACTION_SHOW_PERMISSIONS_RATIONALE` (bis Android 13) bzw.
  `VIEW_PERMISSION_USAGE` mit Kategorie `HEALTH_PERMISSIONS` (ab Android 14) beantwortet,
  **erteilt das System die Freigabe nicht**.
- Der Import muss idempotent sein. Events sind append-only — ein doppelter Import wäre
  nicht rückgängig zu machen und würde die Schlafschuld verdoppeln. Deshalb trägt jedes
  importierte Ereignis eine Quell-ID, und importierte Ereignisse bekommen ihren echten
  Zeitpunkt (`recordAt`), nicht den Importzeitpunkt.
- Die Bibliothek verlangt `minSdk 26`.

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
