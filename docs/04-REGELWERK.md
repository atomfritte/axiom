# 04 — Regelwerk (DSL & Semantik)

Das Regelwerk ist die **Benutzeroberfläche für den Systemizing-Drive**. Es ist bewusst als lesbares,
versioniertes YAML gebaut und nicht als Einstellungsdialog: Ein Systemizer will das Regelwerk
*lesen, diffen und begründen* können — nicht Schieberegler bedienen.

Gleichzeitig gilt G4: **Regeln ändern darf man nur im Wochenreview-Slot** (M12 Meta-Guard).
Ohne diese Grenze wird das Regelwerk selbst zur Prokrastinationsfläche (D3).

---

## 1. Aufbau einer Regel

```yaml
# rules/core/sensation.yaml
- id: R-050
  title: "Reizbedarf proaktiv decken"
  deficit: D5                      # Rückbindung an die Defizitanalyse
  rationale: >                     # PFLICHT. Wird dem Nutzer als Begründung angezeigt.
    Ungedeckter Reizbedarf sucht sich den schnellsten Kanal — und der ist
    meist der teuerste (Impulskauf, Substanz, Risikoverhalten). Ein geplanter
    Hochreiz-Slot deckt denselben Bedarf zu kalkulierbaren Kosten.
  when:
    all:
      - sensation_need: { gte: 70 }
      - capacity:       { gte: 30 }        # bei leerem Tank kein Sport-Vorschlag
      - not: { active_slot: sensation }
      - time_between: ["07:00", "21:00"]
  then:
    action: suggest_slot
    params:
      pool: [sport, kaelte, musik_laut, wettkampf, motorrad]
      duration_min: 30
  priority: 60
  severity: nudge
  cooldown: { minutes: 180, max_per_day: 3 }
  enabled: true
```

### Feldreferenz

| Feld | Pflicht | Bedeutung |
|---|---|---|
| `id` | ✔ | `R-NNN`, global eindeutig, **wird nie wiederverwendet** (auch nicht nach Löschung) |
| `title` | ✔ | Kurzform für Logs und UI |
| `rationale` | ✔ | Warum es diese Regel gibt. Ladefehler, wenn leer → erzwingt G2 |
| `deficit` | – | `D1`–`D12`. Regeln ohne Defizitbezug sind verdächtig |
| `when` | ✔ | Bedingungsbaum (siehe §2) |
| `then` | ✔ | Aktion (siehe §3) |
| `priority` | ✔ | 0–100. Höher gewinnt bei gleicher `severity` |
| `severity` | ✔ | `info` \| `nudge` \| `intervene` \| `enforce` (siehe §4) |
| `cooldown` | ✔ | Spam-Schutz. Ohne Cooldown kein Laden |
| `enabled` | – | Default `true` |

`rationale` und `cooldown` sind Pflicht, weil ihr Fehlen die zwei häufigsten Fehlermodi erzeugt:
unerklärliche Ausgaben (Vertrauensverlust) und Benachrichtigungsflut (Abstumpfung, dann
Deinstallation).

---

## 2. Bedingungen (`when`)

### Kombinatoren
`all` (UND) · `any` (ODER) · `not` (Negation) · beliebig verschachtelbar.

### Vergleichsoperatoren
`eq` `ne` `lt` `lte` `gt` `gte` `between` `in`

### Zustandsvariablen

| Variable | Typ | Quelle |
|---|---|---|
| `capacity` `focus_debt` `sensation_need` `load_index` `regulation` `sleep_debt` | 0..100 | StateVector |
| `load_level` | `L0..L3` | abgeleitet aus `load_index` |
| `time_between: ["HH:MM","HH:MM"]` | bool | Clock (lokale Zeit) |
| `weekday` | `mon..sun` | Clock |
| `minutes_since(event_type)` | int | EventStore |
| `count_today(event_type)` | int | EventStore |
| `active_slot` | enum | laufender Slot (focus/sensation/none) |
| `next_anchor_in` | min | M3 Time Anchor |
| `task_available(ae_max)` | bool | M2 Task Kernel |
| `streak_days(x)` | int | nur für Auswertung — **nie für Verlustmechanik** (Anti-Ziel) |

### Beispiele

```yaml
# Hyperfokus ohne Pause                                            [D6]
when:
  all:
    - minutes_since: { event: focus_start, gte: 90 }
    - minutes_since: { event: body_prompt, gte: 90 }

# Nachtbestellung abfangen                                         [D5]
when:
  all:
    - time_between: ["22:00", "05:00"]
    - regulation: { lt: 50 }

# Erhaltungsmodus                                                  [D1]
when:
  any:
    - load_level: { eq: L3 }
    - all:
        - sleep_debt: { gte: 70 }
        - capacity:   { lt: 25 }
```

---

## 3. Aktionen (`then`)

| Aktion | Wirkung | Modul |
|---|---|---|
| `suggest_task` | eine startbare Aufgabe vorschlagen | M2 |
| `force_atomize` | Zerlegung erzwingen, bis Teilschritt < capacity | M2 |
| `set_anchor` | Zeitanker + Rückwärtskette erzeugen | M3 |
| `notify` | Benachrichtigung mit Text + Regelbegründung | alle |
| `start_cooldown` | Impuls-Cooldown starten, Checkliste zeigen | M6 |
| `suggest_slot` | Hochreiz-Slot aus Pool vorschlagen | M5 |
| `protect_focus` | DND aktivieren, Unterbrechungen unterdrücken | M4 |
| `escalate_interrupt` | gestufte Unterbrechung (sanft → laut) | M4 |
| `set_load_level` | Eskalationsstufe setzen | M9 |
| `restrict_mode` | Erhaltungsmodus: Optionales ausblenden | M9 |
| `lock_config` | Konfiguration bis zum nächsten Review sperren | M12 |
| `prompt_checkin` | Kurz-Check-in anfordern (< 15 s) | M0 |
| `log_only` | nur protokollieren, keine Ausgabe — für Kalibrierung | alle |

`log_only` ist der wichtigste Aktionstyp der Baseline-Phase (S1): Regeln laufen **stumm** mit und
werden gemessen, bevor sie jemals etwas sagen dürfen. Eine Regel geht erst dann live, wenn ihre
Trefferquote in echten Daten belegt ist.

---

## 4. Severity & Konfliktauflösung

### Severity-Stufen

| Stufe | Verhalten | Unterbricht? |
|---|---|---|
| `info` | erscheint nur im Review | nein |
| `nudge` | stille Notification, wegwischbar | nein |
| `intervene` | sichtbare Notification, verlangt Antwort | ja, sanft |
| `enforce` | verändert Systemverhalten (Sperre, Modus, Cooldown) | ja, hart |

`enforce` gibt es **nur** für Regeln, die der Nutzer im ruhigen Zustand selbst autorisiert hat —
das ist der "Vertrag mit dem Vergangenheits-Ich" aus M6. Eine App, die von sich aus hart
eingreift, wird deinstalliert. Eine, die einen selbst gesetzten Vertrag vollzieht, wird respektiert.

### Auflösung

Wenn mehrere Regeln gleichzeitig feuern:

```
1. severity  DESC     enforce > intervene > nudge > info
2. priority  DESC
3. rule_id   ASC      Tie-Break: lexikografisch, deterministisch
→ es gewinnt GENAU EINE Regel                                          (G1)
```

Verlierende Regeln werden protokolliert (`decision_emitted` mit `suppressed: true`), nicht
verworfen. Der Wochenreview zeigt chronisch unterdrückte Regeln — ein starkes Signal für einen
Regelkonflikt, den man sonst nie bemerkt.

Die Sortierung ist **total und ohne Zufall**. Gleicher Zustand ⇒ gleiche Ausgabe. Immer.

---

## 5. Cooldown

```yaml
cooldown:
  minutes: 180          # Mindestabstand zwischen zwei Feuerungen
  max_per_day: 3        # harte Tagesobergrenze
  backoff: exponential  # bei wiederholtem 'rejected' Abstand verdoppeln
```

`backoff: exponential` ist die eingebaute Selbstkorrektur: Eine Regel, die dreimal abgelehnt wird,
meldet sich seltener und taucht im Wochenreview als **Kandidat zur Streichung** auf.

Systemweite Obergrenze, unabhängig von Einzelregeln:

```yaml
# rules/core/limits.yaml
global_limits:
  max_interventions_per_day: 12
  max_notifications_per_hour: 2
  quiet_hours: ["23:00", "06:30"]     # nur enforce darf durchbrechen
```

Ohne globales Limit summieren sich einzeln vernünftige Regeln zu einer Benachrichtigungsflut. Das
ist der häufigste Grund, warum ADHS-Apps nach drei Wochen stummgeschaltet werden — und eine
stummgeschaltete App ist eine gelöschte App mit Extraschritten.

---

## 6. Regel-Lebenszyklus

```
  ENTWURF ──> SHADOW ──> AKTIV ──> BEWÄHRT
   (yaml)    log_only   live     unverändert seit 30 d
                 │         │
                 │         └──> DEPRECATED (>50 % rejected) ──> ENTFERNT
                 └──> VERWORFEN (Trefferquote zu niedrig)
```

**Jede neue Regel startet in SHADOW.** Mindestens 7 Tage `log_only`, dann Auswertung im
Wochenreview:

- Wie oft hätte sie gefeuert? (zu oft = Bedingung zu weit)
- Wäre der Rat in der Situation richtig gewesen? (manuelle Bewertung)
- Kollidiert sie mit bestehenden Regeln? (Unterdrückungs-Statistik)

Das ist die Disziplin, die dieses Projekt vor der Meta-Work-Falle schützt: Regeln werden nicht
gebastelt, sie werden **eingeführt und gemessen**. Und ein Systemizer, der Regeln empirisch
validieren darf, bekommt seinen Reiz auf der richtigen Ebene.

---

## 7. Persönliche Regeln

```
rules/core/       mitgeliefert, versioniert, im Repo
rules/personal/   privat, .gitignore'd, überschreibt core per id
```

`rules/personal/` enthält private Trigger (Beträge, Substanzen, Namen, Konfliktmuster) und gehört
nicht ins Repo — auch nicht in ein privates. Overlay-Semantik: gleiche `id` überschreibt
vollständig; neue `id` wird additiv geladen.

---

## 8. Validator

`tools/validate_rules.dart` — läuft im CI und beim App-Start. Bricht hart ab bei:

- fehlendem oder leerem `rationale` → **G2 ist damit erzwungen, nicht erhofft**
- fehlendem `cooldown`
- doppelter oder wiederverwendeter `id`
- unbekannter Variable oder Aktion
- `enforce` ohne dokumentierte Nutzerautorisierung
- Regel ohne zugehörigen Test in `packages/axiom_core/test/rules/`
- unerfüllbarer Bedingung (statische Widerspruchsprüfung, z. B. `capacity < 20 AND capacity > 80`)

Eine ungültige Regel wird **nicht geladen** und die App startet mit einem sichtbaren Fehler — kein
stilles Überspringen. Bei einem regelbasierten System ist eine stumm ignorierte Regel schlimmer als
ein Absturz: Man verlässt sich auf etwas, das nicht existiert.
