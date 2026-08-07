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

Für den Stift gibt es seit Android 14 den offiziellen Weg: `ACTION_CREATE_NOTE`. Er hängt aber
an der Systemrolle `ROLE_NOTES` — **und die schaltet One UI nicht frei.** `isRoleAvailable`
meldet `false`, in den Standard-Apps gibt es folglich keinen Eintrag „Notizen". In AOSP liegt
die Rolle hinter dem Entwickleroption-Schalter *Force enable Notes role*; ohne den bleibt der
Weg auf diesem Gerät zu. AXIOM behält den Intent-Filter — er kostet nichts und greift, sobald
Samsung die Rolle ausliefert —, kündigt ihn aber nicht mehr als gangbaren Weg an.

**Air Actions gibt es auf diesem Gerät nicht.** Der S Pen des S25 Ultra hat kein Bluetooth Low
Energy; Samsung nennt Kopplung, Laden und Fernbedienungsfunktionen ausdrücklich als entfallen.
Anleitungen, die auf den Stiftknopf verweisen, gehen ins Leere — und eine Anleitung, die man
befolgt und die nichts findet, kostet mehr als gar keine.

Was bleibt und funktioniert: das **Air-Command-Menü**. Es nimmt beliebige Apps als Verknüpfung
auf — Einstellungen → Erweiterte Funktionen → S Pen → Air Command → Verknüpfungen. Stift
herausziehen, AXIOM antippen: zwei Handgriffe, ohne Rolle und ohne Bluetooth.

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

**Zwei Fallstricke beim Widget — beide sahen von außen gleich aus.**

1. Der `AppWidgetProvider` braucht `android:exported="true"`. Sonst lässt sich das Widget
   nicht hinzufügen.
2. `RemoteViews` inflatet **nur Klassen mit `@RemoteView`**. `android.view.View` und
   `android.widget.Space` gehören nicht dazu. Ein einziges `<View>` als Abstandhalter genügt,
   und der Launcher zeigt „Widget kann nicht angezeigt werden" — das Widget lässt sich dann
   hinzufügen, bleibt aber leer. Erlaubt sind unter anderem `LinearLayout`, `FrameLayout`,
   `RelativeLayout`, `TextView`, `ImageView`, `ProgressBar`, `Chronometer`.
   `axiom_app/test/platform_integration_test.dart` prüft das am Layout.

**Fallstrick beim Widget:** Der `AppWidgetProvider` muss `android:exported="true"` haben. Der
Launcher läuft in einem anderen Prozess und muss den Update-Broadcast senden können; mit `false`
lässt sich das Widget schlicht nicht hinzufügen. Prüfbar am gebauten Paket:
`aapt2 dump badging app.apk | grep app-widget` muss `provides-component:'app-widget'` zeigen.

---

## 3. Sensorik & Datenquellen

| Quelle | Daten | Speist |
|---|---|---|
| **Health Connect** | Schlafdauer, Schritte pro Tag | `sleepDebt`, `capacity`, `loadIndex` |
| Bildschirmzeit / Usage Stats | App-Nutzung, Entsperrvorgänge, Nachtnutzung | M4 Hyperfokus, M8 Nacht-Kaskade |
| Kalender (lesend) | Termine | M3 Backward-Chaining |
| Standort (grob, optional) | zu Hause / unterwegs | Kontextfilter M2 |

Was das Gerät zusätzlich hergäbe und AXIOM **nicht** liest: Herzfrequenz, HRV,
Schlafphasen, Watch-Sensorik. Nicht aus technischen Gründen — sondern weil keine
Regel sie auswertet. Eine Berechtigung ohne Regel dahinter ist eine Zusage, die
das Onboarding bricht („Schlafzeiten und Schritte pro Tag. Sonst nichts").
`platform_integration_test.dart` prüft das gegen `HealthBridge.kt`: Steht im
Manifest eine Health-Berechtigung, die der Code nie anfordert, fällt der Test.

<details>
<summary>Frühere Fassung dieser Tabelle</summary>

Hier standen ursprünglich Herzfrequenz, HRV und eine Galaxy-Watch-Zeile. Beides
war Planung, kein Zustand — sie ist nie gebaut worden, die Berechtigung stand
aber im Manifest.

| Quelle | Daten | Speist |
|---|---|---|
| ~~Health Connect~~ | ~~Schlafphasen, Schlafdauer, Schritte, Herzfrequenz, HRV~~ | ~~`sleepDebt`, `capacity`, `loadIndex`~~ |
| ~~Galaxy Watch (falls vorhanden)~~ | ~~HR, HRV, Schlaf, Bewegung~~ | ~~`loadIndex`, M4 Bewegungslosigkeitserkennung~~ |

</details>

Alle Quellen sind **einzeln abschaltbar**. Voreinstellung: nur Health Connect und Kalender.
Standort und Usage Stats sind opt-in — sie sind die invasivsten und liefern den geringsten
Grenznutzen.

---

## 4. Automation

### Samsung Modes & Routines
AXIOM sendet Broadcast-Intents, die Samsung-Routinen auslösen:

```
de.atomfritte.axiom.FOCUS_START   → DND an, Graustufen, Fokusmodus       (M4)
de.atomfritte.axiom.FOCUS_END     → zurücksetzen
de.atomfritte.axiom.WINDDOWN      → Blaulichtfilter, Lautstärke runter    (M8)
de.atomfritte.axiom.L3_ENTER      → Erhaltungsmodus: Benachrichtigungen minimieren  (M9)
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

### 5.2a Der Stift fragt nach einer Rolle, nicht nach einem Intent-Filter

`ACTION_CREATE_NOTE` korrekt zu registrieren reicht **nicht**. Der Doppeltipp mit dem S-Pen und
die Schnelleinstellung „Notiz" fragen die Rolle `RoleManager.ROLE_NOTES` ab (Android 14+). Solange
die bei Samsung Notes liegt, erscheint AXIOM dort nicht — ohne jede Fehlermeldung.

Anzufordern über `createRequestRoleIntent(ROLE_NOTES)`. Liefert das Gerät die Rolle nicht aus
(kommt vor), bleibt der Weg über *Einstellungen → Standard-Apps*.

### 5.2b App Actions brauchen Google Play

„Hey Google, Notiz in AXIOM" funktioniert bei einer selbst installierten App **nicht**. Die
`capability`-Anmeldung in `shortcuts.xml` wird nur für Apps geprüft, die über Play verteilt
werden. Das ist keine Fehlkonfiguration und lässt sich lokal nicht beheben — es steht deshalb
in der App unter „Bekannte Grenzen" statt als Versprechen im Erfassungsscreen.

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
- **Paketsichtbarkeit:** Ohne `<queries>`-Einträge für `com.google.android.apps.healthdata`
  *und* die Systemmodule ab Android 14 meldet `getSdkStatus` „nicht vorhanden", obwohl der
  Dienst läuft — und der Freigabedialog öffnet sich nie.
- **Ab Android 14 sind es gewöhnliche Laufzeitberechtigungen.** Der androidx-Vertrag öffnet dort
  eine Activity, die es nicht auf jedem Gerät gibt; dann passiert beim Antippen genau nichts.
  Der direkte Weg über `ActivityCompat.requestPermissions` funktioniert immer.
- `hasPermissions()` ist **suspendierend**. Mit `runBlocking` im MethodChannel-Handler hängt der
  UI-Thread an einer Prozessgrenze — ein ANR beim App-Start.
- **Und es gehört ganz vom Hauptthread herunter.** `getOrCreate` baut eine Binder-Verbindung auf.
  Solange Health Connect über `<queries>` gar nicht sichtbar war, kam das nie zum Tragen; sobald
  es sichtbar ist, blockiert der Aufruf den Android-Hauptthread. Blockiert der, kann Flutter keine
  Frames mehr zeigen — die App steht dann auf dem letzten gezeichneten Bild, einem Ladekreisel,
  der nie aufhört. Von außen ist das von einem Absturz nicht zu unterscheiden. Der Coroutine-Scope
  läuft deshalb auf `Dispatchers.IO`, die Antwort geht über `runOnUiThread` zurück, und jeder
  Aufruf auf der Dart-Seite hat eine Zeitgrenze.

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

**Wer über diese Kanäle spricht, und wer nicht.** Eine gefeuerte Regel wird zu einer Zeile *im*
Programm — sie schickt keine Benachrichtigung. Auf die Kanäle geht ausschließlich, was vorher
als Wecker gestellt wurde: die drei Check-ins, die Abendgrenze, der Schlafeintrag, das Ende
eines Fokusblocks, die Ankerschritte und der Eingang (R-150). Das ist eine Einschränkung, keine
Auslassung: Ein Wecker steht im Voraus fest und ist damit vorhersagbar; eine Regel feuert erst,
wenn die App ohnehin läuft und die Ausgabe schon auf dem Bildschirm steht — eine Meldung
zusätzlich wäre Lärm neben etwas Sichtbarem.

**Im Browser ist es umgekehrt.** Dort gibt es keine geplanten Wecker — der Expertenmodus läuft
nur, solange die App läuft. Dafür kann die Seite eine feuernde Regel als Systemmeldung des
Browsers zeigen (`new Notification`, kein Web Push — [ADR-0005 §2b](adr/ADR-0005-expertenmodus.md)).
Sie ist abgeschaltet, bis jemand sie einschaltet, meldet nur, was auf dem Telefon auch
erschiene (`info` also nicht), klingt nur ab `intervene`, und schweigt, solange der Reiter
vorne liegt. Beide Wege zusammen decken damit die zwei Fälle ab: Der Wecker erreicht dich,
wenn nichts läuft; die Seite erreicht dich, wenn du am Rechner sitzt und woanders hinsiehst.

Wo eine Regel den Fall trifft, dass man die App *nicht* öffnet, muss ihr Anlass deshalb doppelt
stehen: einmal als Bedingung in der Regel, einmal als Weckzeitpunkt daneben. Bei R-150 sind das
`inbox_oldest_hours: { gte: 72 }` und `InboxAgeAlarm.threshold`. Die Doppelung ist unvermeidbar
— der Wecker muss den Zeitpunkt vorher kennen, die Regel wertet rückblickend aus —, aber sie
darf nicht auseinanderlaufen: `inbox_alarm_test.dart` liest beide Werte und vergleicht sie.

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
