# 03 — Datenmodell

Normativ. Der Code in `packages/axiom_core/lib/src/domain/` folgt diesem Dokument; bei Abweichung
gilt der Code als Bug — oder das Dokument wird im selben Commit mitgeändert.

---

## 1. Grundform: Event Sourcing

Alles, was AXIOM weiß, kommt aus einem **append-only Event-Strom**. Der Zustand ist eine Projektion,
niemals eine Quelle.

```
Events (unveränderlich, geordnet)
   │
   ├──> StateDeriver  ──> StateVector   (Momentaufnahme, jederzeit neu berechenbar)
   ├──> TaskProjector ──> Task[]        (mutable Sicht, aber Änderungen erzeugen Events)
   └──> Analyzer      ──> Metriken      (Wochen-/Monatsreview)
```

**Warum:** Regeländerungen sollen rückwirkend auswertbar sein — *"hätte R-042 in der neuen Fassung
letzten Dienstag anders entschieden?"*. Das geht nur, wenn die Rohsignale erhalten bleiben. Ohne
Event-Sourcing wäre das Regelwerk nicht empirisch verbesserbar, sondern nur gefühlt.

---

## 2. Event

```dart
class Event {
  final String  id;          // ULID — zeitsortierbar, offline-kollisionsfrei
  final DateTime at;         // UTC. Immer über Clock-Port erzeugt, nie DateTime.now()
  final EventType type;
  final Map<String, Object?> payload;   // typspezifisch, JSON-serialisierbar
  final EventSource source;             // wer hat es erzeugt
}

enum EventSource { user, timer, health, device, rule, system, import }
```

Regeln:
- **Nie UPDATE, nie DELETE.** Korrekturen sind neue Events (`correction_of: <id>`).
- **Immer UTC** gespeichert, lokale Zeitzone nur zur Anzeige.
- Payload ist streng JSON — keine binären Blobs, keine Objektreferenzen.
- Ein Event ohne registrierten Typ wird abgelehnt, nicht ignoriert (Fail-Fast).

### 2.1 Event-Typen

| Typ | Payload (Kern) | Quelle | Modul |
|---|---|---|---|
| `capture` | `text`, `via` (spen/tile/widget/share), `attachments?` | user | M1 |
| `checkin` | `energy 1..5`, `focus 1..5`, `mood 1..5`, `stim_need 1..5` | user | M0 |
| `task_created` | `task_id`, `title`, `ae`, `salience`, `stakes`, `decay_at?`, `place?` | user | M2 |
| `task_started` | `task_id` | user | M2 |
| `task_completed` | `task_id`, `duration_min` | user | M2 |
| `task_abandoned` | `task_id`, `reason` | user | M2 |
| `task_split` | `parent_id`, `child_ids[]` | user | M2 (Atomizer) |
| `task_linked` | `blocker_id`, `blocked_id` | user | M2 (Blocker) |
| `task_unlinked` | `blocker_id`, `blocked_id` | user | M2 (Blocker) |
| `place_entered` | `place` (leer = keiner mehr) | user/device | M2 |
| `focus_start` | `anchor_task_id?`, `planned_min` | user | M4 |
| `focus_end` | `actual_min`, `on_anchor bool`, `exit` (planned/interrupted/lost) | user/rule | M4 |
| `sensation_slot` | `channel`, `intensity 1..5`, `duration_min`, `planned bool` | user | M5 |
| `impulse_intercepted` | `trigger_id`, `outcome` (aborted/proceeded/expired), `cooldown_min` | rule | M6 |
| `body_prompt` | `kind` (water/food/move/eyes/bladder), `ack bool` | timer | M7 |
| `sleep_window` | `bed_at`, `wake_at`, `quality 1..5`, `est_debt_min` | health/user | M8 |
| `health_sample` | `metric`, `value`, `unit`, `window` | health | M7/M9 |
| `signal_incident` | `intensity 1..5`, `trigger_class`, `note?` | user | M10 |
| `signal_postmortem` | `incident_id`, `root_cause`, `countermeasure` | user | M10 |
| `decision_emitted` | `rule_id`, `action`, `state_snapshot_id` | rule | M0 |
| `decision_feedback` | `decision_id`, `response` (followed/deferred/rejected) | user | M0 |
| `review_completed` | `scope` (day/week/month/quarter), `duration_min` | user | M11 |
| `meta_usage` | `screen`, `duration_s`, `counts_to_budget bool` | system | M12 |
| `med_intake` | `substance`, `dose`, `at` | user | M13 (opt-in) |

`decision_emitted` + `decision_feedback` sind das Rückgrat der Regelqualität: ohne sie lässt sich
nicht messen, ob eine Regel hilft oder nur nervt.

---

## 3. StateVector

Der Zustandsvektor. Sechs Dimensionen, jede 0–100, jede mit **dokumentierter Formel**.
Keine Dimension ohne nachvollziehbare Herleitung (G2).

```dart
class StateVector {
  final DateTime at;
  final int capacity;        // verfügbare exekutive Kapazität       → steuert M2
  final int focusDebt;       // ununterbrochene Fokuslast            → steuert M4
  final int sensationNeed;   // ungedeckter Reizbedarf               → steuert M5, M6
  final int loadIndex;       // kumulierte Kompensationskosten       → steuert M9  [D1]
  final int regulation;      // emotionale Regulationsreserve        → steuert M6, M10
  final int sleepDebt;       // Schlafschuld in Minuten, normiert    → speist capacity, loadIndex
}
```

### 3.1 Formeln (v1 — Startwerte, kalibrierbar)

Alle Gewichte liegen in `rules/core/weights.yaml` und sind nach der Baseline-Phase anzupassen.
Die Startwerte sind **plausibel geraten, nicht validiert** — genau deshalb existiert S1.

```
capacity =
    100
  − 0.30 × sleepDebtNorm            Schlaf ist der stärkste Einzelmodulator          [D8]
  − 0.25 × loadIndex                chronische Last frisst Tageskapazität            [D1]
  − 0.20 × focusDebt                verbrauchte Fokuszeit heute
  − 0.15 × (100 − regulation)       emotionale Belastung kostet Exekutivfunktion     [D10]
  + 0.10 × circadianBonus(t)        persönliches Leistungsfenster (aus Baseline)
  [+ medWindowBonus(t)]             nur wenn M13 aktiv                               [D13]
  → clamp 0..100

sensationNeed =
    baselineDrive                                   Trait, hoch bei diesem Profil    [D5]
  + 0.40 × minutesInLowStimulus / 60 × 10
  − 0.60 × Σ(slot.intensity × slot.duration) / 30   in den letzten 24 h
  → clamp 0..100

loadIndex = gleitender 7-Tage-Mittelwert über:
    0.30 × sleepDebtNorm
  + 0.25 × (100 − recoveryQuality)      Erholung wirkt nicht mehr → Kernsignal       [D1]
  + 0.20 × compensationEffort           selbst berichteter Maskierungsaufwand
  + 0.15 × irritabilityTrend            aus checkin.mood-Varianz
  + 0.10 × socialWithdrawal             Rückzug als Frühindikator
  → clamp 0..100     Schwellen: L1 ≥ 55 · L2 ≥ 70 · L3 ≥ 85

focusDebt   = Σ Fokusminuten heute, gewichtet nach Zeit seit letzter echter Pause
regulation  = 100 − (Intensität/Frequenz von signal_incident der letzten 72 h, abklingend)
sleepDebt   = Σ (soll − ist) der letzten 7 Nächte, normiert auf 0..100
```

**Wichtig:** Jede Formel muss im UI aufklappbar sein — *"capacity = 62, weil: Schlafschuld −18,
Load −12, Fokuslast −8"*. Ein Score ohne sichtbare Herleitung wird von diesem Profil (zu Recht)
als Willkür verworfen.

---

## 4. Task

Der zentrale Modellbruch mit klassischen To-do-Apps: **keine `priority`-Spalte.**

```dart
class Task {
  final String id;
  final String title;
  final int activationEnergy;   // 1..10  Wie schwer ist der KALTSTART?      [D2]
  final int salience;           // 1..10  Wie viel intrinsischer Zug?
  final int stakes;             // 1..10  Was kostet das Nicht-Tun?
  final DateTime? decayAt;      //        Wann verfällt / eskaliert sie?
  final Duration? estimate;     //        optional, notorisch unzuverlässig
  final String? parentId;       //        Atomizer-Hierarchie
  final TaskState state;        //        inbox|ready|active|blocked|done|dropped
                                //        `blocked` = zerlegt, NICHT „wartet" (§4.2)
  final List<String> contexts;  //        @home @phone @errand @deepwork
  final String? breadcrumb;     //        Wiedereinstiegsnotiz                [D11]
  final String? place;          //        frei vergebener Ortsname            [D2]
}
```

**`place` ist ein Name, keine Koordinate.** Kein GPS, kein Geofence, keine
Standortberechtigung. Der aktuelle Ort ist die Projektion des letzten
`place_entered`-Events; gesetzt wird er in der App oder von einer
Geräteroutine über den Broadcast `de.atomfritte.axiom.PLACE`. Ein Geofence beantwortet
„wo bin ich", die Frage der Aufgabe ist aber „was geht hier" — und der
Gegenwert eines Kreises mit 200 m Radius wiegt `ACCESS_BACKGROUND_LOCATION`
und ein Bewegungsprofil in einer Datenbank mit Gesundheitsdaten nicht auf.

Ohne gesetzten Ort wird **nichts** unterdrückt: Ortsgebundene Aufgaben
erscheinen dann mit ihrem Ort als Hinweis. Etwas zu verstecken, das der
Nutzer nie eingeschaltet hat, wäre der schlimmere Fehler [D9].

### 4.1 Auswahlalgorithmus

```
1. FILTER    startbar ⟺ activationEnergy ≤ capacity/10  ∧  state ∈ {ready}
                       ∧  Kontext erfüllt  ∧  nicht wartend
                       ∧  (place = null ∨ aktueller Ort = null ∨ gleich)

2. SCORE     urgency  = stakes × decayPressure(decayAt, now)
             pull     = salience
             cost     = activationEnergy
             leverage = 1 + 0.35 × log2(1 + freigeräumt)
             score    = (0.6 × urgency + 0.4 × pull) × leverage / cost

3. ESCALATE  Ist eine Aufgabe mit stakes ≥ 8 durch FILTER gefallen
             und decayAt < 72 h:
               → NICHT anzeigen und Schuld erzeugen              ✗
               → M2 Atomizer: Zerlegung erzwingen, bis ein
                 Teilschritt unter capacity fällt                ✓

4. EMIT      genau EINE Aufgabe + Begründung + Regel-ID           (G1)
```

Schritt 3 ist der entscheidende. Der übliche Fehlermodus — wichtige Aufgabe steht wochenlang oben,
erzeugt bei jedem Blick Schuld, wird nie gestartet — wird hier strukturell ausgeschlossen: Was nicht
startbar ist, wird **zerlegt**, nicht angemahnt.

### 4.2 Blocker: A blockiert B

Genau **eine** Beziehungsart. Kein „hängt zusammen mit", kein „Duplikat von", kein „folgt auf" —
jede weitere Art kostet Pflege ohne Gegenwert und ist Meta-Work-Treibstoff (D3).

```dart
class TaskLink {
  final String blockerId;   // steht im Weg
  final String blockedId;   // wartet deshalb
}
```

- **„Wartet" ist kein Zustand, sondern eine Rechnung.** `TaskState.blocked` heißt in AXIOM
  *zerlegt* (durch Teilschritte vertreten). Eine Aufgabe mit mindestens einem **offenen** Blocker
  **wartet** — abgeleitet aus den Beziehungen, nie gespeichert. Deshalb wird sie in dem Moment
  wieder startbar, in dem der letzte Blocker erledigt oder verworfen ist, ohne dass irgendwo etwas
  nachgezogen werden muss.
- **Wartende Aufgaben werden nicht vorgeschlagen.** Ein Vorschlag, den man nicht ausführen kann,
  ist keiner (G1).
- **Ein Blocker bekommt Vorrang.** `leverage` misst, wie viele offene Aufgaben frei werden, wenn
  diese fertig ist — **transitiv**, nicht nur direkt. Logarithmisch, damit eine lange Kette die
  Auswahl nicht überfährt: 1 freigeräumte Aufgabe → ×1.35, 3 → ×1.70, 7 → ×2.05.
- **Zyklen sind ein Fehler, kein Sonderfall.** Eine Beziehung, die einen Kreis schlösse, wird beim
  Anlegen abgelehnt (`TaskLinkCycleError` mit dem Pfad, an dem er sich schließt). A blockiert B
  blockiert A hieße: beide warten für immer, und nichts sagt warum.

---

## 5. Rule & Decision

```dart
class Rule {
  final String id;             // "R-050" — stabil, wird nie wiederverwendet
  final String title;
  final String rationale;      // WARUM. Pflichtfeld. Wird dem Nutzer angezeigt.  (G2)
  final String? deficit;       // "D5" — Rückbindung an die Analyse
  final Condition when;        // Ausdrucksbaum über StateVector + Kontext
  final Action then;
  final int priority;          // 0..100, höher gewinnt
  final Severity severity;     // info | nudge | intervene | enforce
  final Cooldown cooldown;     // verhindert Regel-Spam
  final bool enabled;
}

class Decision {
  final String id;
  final DateTime at;
  final String ruleId;
  final Action action;
  final String explanation;    // generiert aus rationale + konkreten Zustandswerten
  final String stateSnapshotId;
  DecisionResponse? response;  // followed | deferred | rejected — Regelqualitäts-Feedback
}
```

**`rationale` ist ein Pflichtfeld.** Eine Regel ohne Begründung ist im Regel-Validator ein
Ladefehler, kein Warning. G2 ist damit nicht Konvention, sondern erzwungen.

Semantik, Operatoren und Konfliktauflösung: [04-REGELWERK.md](04-REGELWERK.md)

---

## 6. Persistenz

```sql
-- Kern: unveränderlich
events(id TEXT PK, at INTEGER, type TEXT, source TEXT, payload TEXT)
  INDEX (at), INDEX (type, at)

-- Projektionen: jederzeit verwerf- und neuberechenbar
state_snapshots(id TEXT PK, at INTEGER, vector TEXT)
tasks(id TEXT PK, title TEXT, ae INTEGER, salience INTEGER, stakes INTEGER,
      decay_at INTEGER, state TEXT, parent_id TEXT, contexts TEXT,
      breadcrumb TEXT, place TEXT)
task_links(blocker_id TEXT, blocked_id TEXT, PRIMARY KEY (blocker_id, blocked_id))
  -- blocker_id blockiert blocked_id. Projektion aus task_linked/task_unlinked.

-- Audit: das Gedächtnis des Regelwerks
decisions(id TEXT PK, at INTEGER, rule_id TEXT, action TEXT,
          explanation TEXT, state_snapshot_id TEXT, response TEXT)

-- Meta-Guard
usage_log(id TEXT PK, at INTEGER, screen TEXT, duration_s INTEGER, counts INTEGER)
```

- **Engine:** SQLite über das `sqlite3`-Paket, direkt, ohne ORM
- **Verschlüsselung: geplant, nicht gebaut.** `SqliteEventStore` nimmt einen `encryptionKey`
  entgegen und setzt `PRAGMA key`, aber kein Aufrufer übergibt einen; einen Biometrie-Gate gibt
  es nicht. Die Datei liegt im Klartext im privaten App-Verzeichnis, geschützt allein durch
  Geräteverschlüsselung und die App-Trennung von Android. Siehe `docs/BACKLOG.md`.
- **Migrationen:** versioniert, vorwärtsgerichtet, mit Test pro Schritt
- **Wiederherstellbarkeit:** Löscht man alle Projektionstabellen, muss ein voller Rebuild aus
  `events` denselben Zustand erzeugen. Das ist ein Testfall, keine Absichtserklärung.

---

## 7. Export & Datenhoheit

```
axiom-export-YYYYMMDD.axiom   =  tar {
    events.ndjson       vollständiger Roh-Event-Strom
    rules/              Regelwerk-Snapshot zum Exportzeitpunkt
    manifest.json       Schema-Version, Zeitraum, Prüfsummen
}                                verschlüsselt (age / libsodium), Schlüssel beim Nutzer
```

Nicht verhandelbar:
- **Kein Datenpunkt verlässt das Gerät ohne explizite Nutzeraktion.**
- **Keine Telemetrie. Kein Crash-Reporting an Dritte. Kein Analytics-SDK.**
- Vollständiger Export in offenem Format (NDJSON) — jederzeit, ohne AXIOM lesbar.
- Purge-Funktion: selektives Löschen nach Zeitraum oder Event-Typ, unwiderruflich und als solche
  gekennzeichnet.

Das sind Gesundheitsdaten über psychische Verfassung, Impulskontrolle und Substanzkonsum. Die
Datenhaltung ist entsprechend ausgelegt — nicht als Feature, sondern als Voraussetzung dafür, dass
man ehrlich eincheckt. Ein System, dem man nicht traut, bekommt keine ehrlichen Daten — und
liefert dann auch keine brauchbaren Entscheidungen.
