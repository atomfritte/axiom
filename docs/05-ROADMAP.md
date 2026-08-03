# 05 — Roadmap

## Grundregel

> **Erst messen, dann regeln.** Ein Regelwerk ohne Baseline ist geraten — und geratene Regeln
> werden zu Recht ignoriert.

Und die härtere Regel für genau dieses Profil:

> **Jede Stufe hat ein Abbruchkriterium.** Wird es gerissen, wird nicht weitergebaut, sondern
> repariert oder gestrichen. Ein hochkompensierter Systemizer baut sonst Stufe 4, während Stufe 1
> ungenutzt daliegt — und genau das ist der Fehlermodus, den dieses Projekt vermeiden muss (D3).

---

## S1 — Fundament & Baseline  ✅ gebaut, Baseline offen

**Module:** M0 State Engine (nur Erfassung) · M1 Capture · M12 Meta-Guard

Die App gibt in dieser Stufe **keine einzige Empfehlung**. Sie misst.

| Deliverable | Stand |
|---|---|
| `axiom_core` | ✅ Domain + State Engine + Rule Engine, 63 Tests |
| EventStore | ✅ SQLite append-only, Schema v2, Rebuild-Test grün |
| M1 Capture | ✅ App, Quick Tile, Shortcut, Share-Ziel. S-Pen-Anbindung offen (S2) |
| Check-in | ✅ 4 Regler, 3 × täglich per exaktem Alarm |
| M12 Meta-Guard | ✅ Nutzungszeit sichtbar, Konfigurationssperre bei 12 min |
| Regel-Runner | ✅ 7 Regeln laufen in `log_only` mit — stumm |
| Oberfläche | ✅ Jetzt · Zustand · System · Eingang · Onboarding |
| Android-Integration | ✅ Widget, Alarme, Boot-Wiederherstellung, 4 Kanäle |
| Health Connect | ⬜ Berechtigungen deklariert, Import folgt |
| **Baseline** | ⬜ **14 Tage durchgehende Daten — der eigentliche Punkt** |

**Abbruchkriterium:** Wenn nach 14 Tagen die Erfassung nicht routiniert läuft (< 80 % der
Check-ins), wird **kein** weiteres Modul gebaut. Dann ist die Erfassungsreibung das Problem —
und jedes Feature obendrauf verschlimmert es.

**Warum M12 schon hier:** Der Wächter muss stehen, bevor es etwas zu bewachen gibt. Später
eingebaut wird er nie eingebaut.

---

## S2 — Kern-Regelkreis  ✅ gebaut, Kalibrierung offen

**Module:** M2 Task Kernel · M3 Time Anchor · M7 Body Loop · M8 Sleep Gate · M11 Review Cadence

Die vier Defizite mit dem besten Aufwand-Wirkungs-Verhältnis: Aufgabenstart (D2), Zeitkosten (D4),
Körper (D7), Schlaf (D8).

| Deliverable | Stand |
|---|---|
| M2 Task Kernel | ✅ AE-basierte Auswahl, genau **eine** Ausgabe, Atomizer mit Formenkatalog |
| M3 Time Anchor | ✅ Rückwärtsverkettung, exakte Alarme je Schritt, Widget-Anbindung |
| M7 Body Loop | ✅ Vier Signale, zeitgetriggert. Health-Connect-Import offen |
| M8 Sleep Gate | ✅ Abendgrenze, Schlaferfassung, Wind-Down-Broadcast |
| M11 Review | ✅ Tag/Woche/Monat/Quartal, Zeitdeckel **läuft und schließt** |
| Live-Regeln | ✅ 5 zeitbasierte Regeln aktiv (R-100 bis R-120) |
| Kalibrierung | ⬜ **Braucht die Baseline.** Werkzeug steht: `tools/bin/calibrate.dart` |
| Schwellen-Regeln | ⬜ R-050 ff. bleiben stumm, bis `weights.yaml` kalibriert ist |

**Abbruchkriterium:** Wird das Wochenreview zweimal in Folge ausgelassen, wird der Umfang
gekürzt statt erweitert. Ein Review, das nicht stattfindet, macht das gesamte Regelwerk blind.

**Warum die Kalibrierung offen bleibt:** Ohne 14 Tage Daten sind alle Gewichte in
`weights.yaml` geraten. Regeln, die auf abgeleitete Werte (`capacity`, `load_index`,
`sensation_need`) prüfen, würden daher auf geratener Grundlage feuern — und eine App, die
einmal offensichtlich danebenliegt, macht man nicht wieder auf (R3). Die zeitbasierten Regeln
sind davon nicht betroffen: Uhrzeiten und Ereigniszählungen sind exakt. Ein Test in
`axiom_data` erzwingt diese Trennung, solange `calibration.status: uncalibrated` gesetzt ist.

---

## S3 — Regulation  ✅ gebaut, ungeeicht

**Module:** M4 Focus Governor · M5 Sensation Budget · M6 Impulse Interceptor · M9 Load Monitor

Die schwierigen, hochsensiblen Module.

**Ausdrücklich vorgezogen.** Die Roadmap sah vor, dass diese Module kalibrierte Formeln
aus S1/S2 voraussetzen. Auf Nutzerentscheidung laufen sie ungeeicht — mit dem Preis, dass
schwellenabhängige Regeln danebenliegen können, solange `weights.yaml` auf
`status: uncalibrated` steht.

Der Ausgleich ist Sichtbarkeit statt Blockade (G2): Der Systeminspektor markiert betroffene
Regeln als **UNGEEICHT** und nennt die Zahl im Kopf. Die Cooldowns dieser Regeln sind
weiter und die Tageslimits niedriger als sonst — eine Regel, die auf geratener Grundlage
zu oft feuert, verbrennt Vertrauen schneller, als sie Nutzen stiftet (R2, R3).

| Deliverable | Stand |
|---|---|
| M4 Focus Governor | ✅ Gestufte Eskalation, Termin schlägt Fokus, Breadcrumbs, DND-Broadcast |
| M5 Sensation Budget | ✅ Kanäle, Slot-als-Währung (1:3), deterministischer Vorschlag |
| M6 Interceptor | ✅ Trigger, Cooldown, selbst geschriebene Checkliste, Haltequote |
| M9 Load Monitor | ✅ L0–L3 mit realen Konsequenzen, Haltezeit, Referral-Hinweis |
| Linux-Companion | ⬜ Deep-Work-Erkennung am Desktop — offen |
| Kalibrierung | ⬜ **Weiterhin offen.** `tools/bin/calibrate.dart` steht bereit |

**Abbruchkriterium:** Feuert M4 mehr Fehlalarme als Treffer (Feedback-Quote `rejected` > 40 %),
wird die Erkennung zurückgebaut, nicht verfeinert. Eine Unterbrechung zur falschen Zeit kostet
mehr als jede verpasste Unterbrechung einbringt (D6).

---

## S4 — Vertiefung  (offen)

**Module:** M10 Signal Log · M13 Med Window (opt-in) · Sync

Erst wenn S1–S3 seit **mindestens 8 Wochen stabil** laufen.

| Deliverable | Bemerkung |
|---|---|
| M10 Signal Log | Incident/Post-Mortem-Framing, RSD-Muster (D10) |
| M13 Med Window | **Default aus.** Reine Protokollierung, keine Dosisempfehlung |
| Sync | self-hosted, E2E-verschlüsselt, Server sieht nie Klartext |
| Regel-Analytik | Trefferquoten, Konfliktmuster, Streichkandidaten |

Alles darüber hinaus ist Meta-Work, bis das Gegenteil bewiesen ist.

---

## Zeitachse

```
Woche   1  2  3  4  5  6  7  8  9 10 11 12 ...
S1      ███████████                              Bauen + 14 Tage Baseline
S2                 ████████████████              Kern-Regelkreis
S3                                ███████████    Regulation
S4                                          →    nur bei stabilem S1–S3
```

---

## Priorisierungsregel bei Zweifel

Bei Konflikt zwischen zwei Features gewinnt immer:

1. Das, was **kognitive Last reduziert** (G1) — vor dem, was Funktion hinzufügt
2. Das, was **auf D1 einzahlt** (Kompensationskosten) — das ist das eigentliche Risiko
3. Das, was **ohne Nutzerdisziplin funktioniert** — vor dem, was Adhärenz voraussetzt
4. Das **Einfachere** — immer

---

## Ausdrücklich nicht auf der Roadmap

Diese Ideen werden auftauchen und attraktiv wirken. Sie stehen hier, damit die Entscheidung schon
gefallen ist, bevor der Reiz kommt:

- ❌ KI-Assistent, der Aufgaben priorisiert oder Entscheidungen trifft — verletzt G2
- ❌ Plugin-System, Skripting-Layer, generische Automations-Engine — reiner Meta-Work-Treibstoff (D3)
- ❌ Mehrbenutzerfähigkeit, Sharing, Vergleich mit anderen — trifft D10 frontal
- ❌ Web-Version, App-Store-Veröffentlichung, Monetarisierung — anderes Projekt
- ❌ Redesign der UI, bevor S1–S3 laufen — die klassische Ausweichbaustelle
- ❌ Zusätzliche Wearables/Integrationen, bevor die vorhandenen genutzt werden
