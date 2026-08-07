# AXIOM — Konzept

> **Arbeitstitel: AXIOM.** Ein Axiom ist eine Regel, die man setzt, nicht ableitet.
> Genau das ist das Bedienprinzip: Du setzt die Regeln. Das System vollzieht sie ausnahmslos.

---

## 1. Was AXIOM ist

**Ein deterministisches, lokal laufendes Regelwerk zur Selbstregulation.**
Ein Exocortex für ein hochkompensiertes ADHS-Zielprofil (siehe
[01-ZIELPROFIL](01-PROFIL-DEFIZITE.md) — eine Konstruktionsannahme, keine Personenbeschreibung).

AXIOM ist **kein** Habit-Tracker, **keine** To-do-App, **kein** Coach und **kein** Therapie-Ersatz.

Der Unterschied ist konzeptionell, nicht kosmetisch:

| Klassische Produktivitäts-App | AXIOM |
|---|---|
| Fragt: *Was willst du tun?* | Fragt: *In welchem Zustand bist du?* — und leitet daraus ab, was jetzt überhaupt möglich ist |
| Modelliert `priority` | Modelliert `activation_energy` × `salience` gegen verfügbare Kapazität |
| Optimiert Output | Optimiert **Regulationsreserve** — Output ist die Folge, nicht das Ziel |
| Belohnt Nutzung | **Deckelt** Nutzung (Meta-Work-Guard) |
| Undurchsichtige Heuristik | Jede Ausgabe nennt die Regel-ID, die sie erzeugt hat |
| Motiviert | **Vollzieht** — Motivation ist kein Eingabeparameter |

### 1.1 Die Grundthese

> Ein hochkompensiertes ADHS-Profil scheitert nicht an fehlender Struktur.
> Es scheitert daran, dass die Struktur **jeden Tag neu im Kopf erzeugt** werden muss.

AXIOM übernimmt die Erzeugung. Nicht die Entscheidung — die bleibt beim Nutzer. Aber die
Buchhaltung, das Nachrechnen, das Wachehalten, das Erinnern: das läuft ab jetzt auf Silizium.

Der Erfolgsmaßstab ist deshalb **nicht** "mehr erledigt", sondern:
**gleiche Leistung bei messbar geringerer kognitiver Last.**

---

## 2. Das mentale Modell: Zustand → Regel → Ausgabe

AXIOM behandelt den Nutzer als beobachtbares System mit einem Zustandsvektor. Alles Weitere ist
eine reine Funktion dieses Vektors.

```
   SIGNALE                    ZUSTAND (State Vector)              REGELWERK          AUSGABE
   ───────                    ────────────────────────            ─────────          ───────
   Schlaf ─────┐
   Check-ins ──┤              capacity        0..100              R-001 IF ...  ┐
   Health ─────┼──> derive ─> focus_debt      0..100        ──>   R-002 IF ...  ├─> genau EINE
   Nutzung ────┤              sensation_need  0..100              R-003 IF ...  │   nächste
   Uhrzeit ────┤              load_index      0..100              ...           ┘   Handlung
   Kalender ───┘              regulation      0..100
                                                                                    + Regel-ID
                                                                                    + Begründung
```

Drei Eigenschaften machen das für einen Systemizer tragfähig:

- **Deterministisch.** Gleicher Zustand + gleiches Regelwerk = gleiche Ausgabe. Immer. Reproduzierbar.
- **Auditierbar.** Jede Ausgabe trägt die Regel-ID. `Warum das?` ist immer beantwortbar.
- **Versioniert.** Das Regelwerk ist YAML unter Git. Änderungen sind ein Diff, kein Gefühl.

Ein Regelwerk, das man auditieren kann, wird benutzt. Eines, das man nur glauben kann, wird verworfen.

---

## 3. Die vier Systemgesetze

Nicht verhandelbar. Jeder Konflikt wird zugunsten dieser Gesetze aufgelöst.

### G1 — Auslagern statt anfordern
Das System darf **nie** kognitive Last hinzufügen. Jeder Screen, der Nachdenken erfordert, ist ein
Bug. Erfassung < 3 s. Check-in < 15 s. Tagesreview < 2 min, hart limitiert.

### G2 — Erklärbar statt intelligent
Jede Ausgabe ist auf eine sichtbare Regel zurückführbar. Kein Score ohne Formel, keine Empfehlung
ohne Regel-ID. ML/LLM darf **nie** in der Entscheidungsschleife stehen — nur optional in der
Auswertung, und dort klar als nicht-deterministisch markiert.

### G3 — Kanalisieren statt unterdrücken
Reizbedarf wird budgetiert und auf gewählte Kanäle gelenkt. AXIOM moralisiert nicht, verbietet
nicht und beschämt nicht. Es verzögert, macht sichtbar und bietet Alternativen.

### G4 — Selbstbegrenzung
AXIOM deckelt seine eigene Nutzungszeit und rationiert seine eigene Konfiguration. Überschreitung
sperrt den Konfigurationsmodus bis zum nächsten Review-Slot. **Eine App, die den Systemizing-Drive
füttert statt bedient, ist das Problem — nicht die Lösung.**

---

## 4. Modulübersicht

13 Module, abgebildet auf D1–D12 aus der [Defizitanalyse](01-PROFIL-DEFIZITE.md).
Spalte *Stufe* verweist auf die [Roadmap](05-ROADMAP.md).

| ID | Modul | Löst | Kernidee | Stufe |
|---|---|---|---|---|
| **M0** | **State Engine** | Basis | Zustandsvektor + deterministische Regelauswertung. Das Herz. | S1 |
| **M1** | **Capture** | D9 | Erfassung < 3 s. S-Pen Screen-Off-Memo, Quick-Tile, Widget. Keine Kategorie beim Erfassen. | S1 |
| **M2** | **Task Kernel** | D2, D12 | `activation_energy` statt `priority`. Zeigt nur, was jetzt **startbar** ist. Atomizer bei Blockade. | S2 |
| **M3** | **Time Anchor** | D4 | Backward-Chaining: Termin → Abfahrt → Vorbereitung → letzter Kontextwechsel. Automatisch. | S2 |
| **M4** | **Focus Governor** | D6, D11 | Hyperfokus schützen wenn richtig, gestuft unterbrechen wenn falsch. Wiedereinstiegs-Breadcrumbs. | S3 |
| **M5** | **Sensation Budget** | D5 | Reizbedarf als geplantes Budget. Hochreiz-Slots als Währung für Niedrigreiz-Pflichten. | S3 |
| **M6** | **Impulse Interceptor** | D5, D10 | Cooldown + selbst geschriebene Prüf-Checkliste vor definierten Risikohandlungen. | S3 |
| **M7** | **Body Loop** | D7 | Wasser, Essen, Bewegung, Augen. Zeitgetriggert. Health Connect. | S2 |
| **M8** | **Sleep Gate** | D8 | Abendritual, Ausstiegsanker, harte Wind-Down-Grenze. Bricht die Nacht-Kaskade. | S2 |
| **M9** | **Load Monitor** | D1 | Kompensationskosten-Radar. Eskalationsstufen L0–L3 mit erzwungenem Erhaltungsmodus. | S3 |
| **M10** | **Signal Log** | D10 | Emotionale Spikes als *Incident + Post-Mortem*, nicht als Gefühlstagebuch. | S4 |
| **M11** | **Review Cadence** | D12 | Tag/Woche/Monat/Quartal als Ops-Review. Harter Zeitdeckel. Re-materialisiert Ziele. | S2 |
| **M12** | **Meta-Guard** | D3 | Deckelt AXIOM-Nutzungszeit. Sperrt Konfiguration außerhalb der Review-Slots. | **S1** |
| **M13** | **Med Window** | opt. | Wirkfenster-Protokoll. Legt Hoch-AE-Aufgaben ins Fenster. **Default: aus.** Keine Dosisempfehlung. | S4 |

**M12 ist Stufe 1.** Der Wächter existiert, bevor es etwas zu bewachen gibt — sonst frisst das
Projekt sich selbst.

**Gezählt wird Aufmerksamkeit, nicht Laufzeit.** Ein offenes Fenster ist keine Nutzung. Die
Weboberfläche des Expertenmodus fragt von selbst weiter, auch aus einem Reiter im Hintergrund;
gebucht wurde deshalb, dass sie *lief* — 115 von 12 Minuten an einem Tag, an dem niemand
hinsah. Der Desktop-Companion hatte denselben Fehler ohne Reiter: ein Fenster ohne Fokus auf
dem zweiten Bildschirm. Ein Deckel, der falsch misst, ist schlimmer als keiner, weil er einen
daran gewöhnt, die eine Zahl zu übergehen, die G4 durchsetzen soll. Gezählt wird jetzt nur,
was sichtbar ist, den Fokus hat und seit weniger als fünf Minuten eine Regung gesehen hat.

Was dabei **nicht** infrage kam: den Expertenmodus auszunehmen. Er ist die Fläche, auf der sich
am leichtesten Stunden am System statt an der Arbeit verbringen lassen (D3, R1) — nähme man ihn
heraus, ließe sich das ganze Meta-Work dorthin verlagern, und das Telefon meldete ungerührt
3/12. Jede einzelne Bedingung ist deshalb so geschrieben, dass ihr Ausfall zum Zählen führt und
nicht zum Schweigen: Ein Fehler darf zu viel buchen, er darf den Deckel nicht stilllegen.

---

## 5. Die tragenden Konzepte

### 5.1 Aktivierungsenergie statt Priorität

Der zentrale Modellbruch mit allen existierenden To-do-Apps.

```
Aufgabe {
  activation_energy: 1..10   // Wie schwer ist der KALTSTART?  (nicht: wie lang, nicht: wie wichtig)
  salience:          1..10   // Wie viel intrinsischen Zug erzeugt sie?
  stakes:            1..10   // Was kostet das Nicht-Tun?  (Konsequenz, nicht Wichtigkeit)
  decay_at:          date?   // Wann verfällt sie?
}
```

Auswahlregel:

```
sichtbar  ⟺  activation_energy ≤ current_capacity
rangfolge ⟺  stakes × decay_pressure ÷ activation_energy
```

Damit verschwindet der klassische Fehlermodus: eine To-do-Liste, deren oberster Eintrag seit
sechs Wochen unangetastet oben steht und bei jedem Blick Schuld erzeugt. Wenn `capacity` niedrig
ist, ist dieser Eintrag **nicht sichtbar** — und stattdessen steht dort etwas Startbares.

Kein Selbstbetrug: Wenn `stakes` hoch und `decay_at` nah ist, eskaliert die Aufgabe trotzdem — dann
aber über M2 Atomizer (Zerlegung, bis ein Teilschritt unter die Kapazität fällt), nicht über Schuld.

### 5.2 Sensation Budget — Reizbedarf als Haushaltsposten

Die Kernumdeutung aus D5: Reizhunger ist ein **Bedarf**, kein Fehler. Ungedeckter Bedarf sucht
sich den schnellsten Kanal, und der schnellste ist fast immer der teuerste.

```
sensation_need steigt   mit Zeit in Niedrigreiz-Tätigkeit
sensation_need fällt    durch gebuchte Hochreiz-Slots

  need > 70  →  Regel R-050 feuert:  Hochreiz-Slot JETZT einplanen
                                     (Sport / Kälte / Musik / Wettkampf / gewähltes Risiko-Hobby)
  need > 85  →  Regel R-051 feuert:  M6 Impulse Interceptor aktiviert Risikokanäle
                                     (Kauf, Verkehr, Substanz, Nacht-Bestellung)
```

Der Slot ist gleichzeitig **Währung**: 90 Minuten Niedrigreiz-Pflicht schaltet einen geplanten
Hochreiz-Slot frei. Das ist keine Gamification-Dekoration — es ist der einzige Tauschhandel, den
dieses Belohnungssystem zuverlässig akzeptiert.

### 5.3 Impulse Interceptor — Vertrag mit dem Vergangenheits-Ich

Ein Systemizer bricht ungern eine Regel, die er selbst gesetzt hat. Das ist die stärkste
verfügbare Bremse.

```
TRIGGER (selbst definiert)     →  COOLDOWN      →  CHECKLISTE (selbst geschrieben)  →  Freigabe
Kauf > 200 €                      15 min           4 Fragen, im ruhigen Zustand         oder Verfall
Bestellung nach 22:00             bis 09:00        formuliert
Kündigung / Vertragsende          24 h
Nachricht im emotionalen Spike    30 min
```

Kein Verbot. Kein Blocken. Nur **Latenz plus Sichtbarkeit** — und der Impulsdurchbruch überlebt
diese Latenz meistens nicht.

### 5.4 Load Monitor — Frühwarnung statt Rückblick

Der `load_index` aggregiert Schlafschuld, Kompensationsaufwand, Erholungsqualität, Reizbarkeit und
soziale Rückzugstendenz. Er hat vier Stufen mit **realen Konsequenzen im System**:

| Stufe | Bedeutung | Systemverhalten |
|---|---|---|
| **L0** | Normalbetrieb | volle Funktion |
| **L1** | erhöhte Last | Warnung im Wochenreview, Hoch-AE-Aufgaben werden entzerrt |
| **L2** | kritisch | neue Verpflichtungen brauchen Bestätigung; Deep-Work-Slots gekürzt |
| **L3** | Erhaltungsmodus | 72 h: nur Pflicht + Erholung. Alles Optionale wird ausgeblendet. |

L3 ist bewusst unbequem. Das ist der Punkt: Ein hochkompensiertes System bemerkt seinen eigenen
Absturz zuletzt und braucht einen **externen Notaus**, den es im Vorfeld selbst autorisiert hat.

### 5.5 Meta-Guard — die App gegen sich selbst

```
Zeitbudget in AXIOM        ≤ 12 min / Tag   (Erfassung zählt nicht mit)
Regeländerungen            nur im Wochenreview-Slot
Neue Module aktivieren     nur im Monatsreview-Slot
Budget überschritten       Konfiguration gesperrt bis zum nächsten Review

Wochenreport zeigt:  Zeit IN AXIOM  vs.  Zeit DURCH AXIOM gewonnen
                     Kippt das Verhältnis, ist das ein Systemfehler — kein Nutzerfehler.
```

---

## 6. Architekturentscheidungen in einem Satz

| Entscheidung | Wahl | Grund |
|---|---|---|
| Plattform | **Flutter** (Android + Linux-Desktop) | Eine Codebase, Toolchain vorhanden, Desktop-Companion für Deep-Work-Tracking |
| Datenhaltung | **Local-first, SQLite (verschlüsselt)** | Gesundheitsdaten. Kein Cloud-Zwang. Offline muss immer funktionieren |
| Sync | **optional, self-hosted, ab S4** | Kein Blocker für v1. Ein Gerät reicht zunächst |
| Regelwerk | **YAML unter Git, zur Laufzeit geladen** | Auditierbar, diffbar, ohne Rebuild änderbar |
| Engine | **reines Dart-Package, headless** | Ohne UI testbar. Regeln sind Unit-getestet, nicht angeklickt |
| KI/LLM | **nie in der Entscheidungsschleife** | G2. Optional in der Auswertung, klar markiert |

Details und Alternativen: [ADR-Verzeichnis](adr/).

---

## 7. Erfolgsmaß

AXIOM ist erfolgreich, wenn nach 90 Tagen gilt:

1. **Erfassungsverlust ≈ 0** — was auftaucht, landet im System (D9)
2. **`load_index` messbar gesunken** bei gleicher externer Last (D1) — das wichtigste Einzelkriterium
3. **Terminstress gesunken** bei unveränderter Pünktlichkeit (D4)
4. **Reizbedarf überwiegend geplant gedeckt**, Impulsdurchbrüche rückläufig (D5)
5. **Zeit in AXIOM ≤ 12 min/Tag**, Trend fallend (D3) — steigt sie, ist das Projekt gescheitert
6. **Das System läuft weiter, auch wenn 3 Tage nichts eingetragen wurde** — kein Streak-Bruch,
   keine Schuld, kein Neuanfang nötig

**Nicht** Erfolgsmaß: erledigte Aufgaben, Streak-Länge, Nutzungsdauer, Feature-Anzahl.

---

## 8. Anti-Ziele

Explizit ausgeschlossen — jedes davon würde dieses spezifische Profil aktiv schädigen:

- ❌ **Streaks mit Verlustmechanik** — ein gebrochener Streak erzeugt bei RSD-Anfälligkeit (D10)
  Abbruch statt Korrektur
- ❌ **Schuldbasierte Erinnerungen** ("Du hast 14 offene Aufgaben")
- ❌ **Endlose Konfigurierbarkeit** — direkter Meta-Work-Treibstoff (D3)
- ❌ **Social/Sharing/Leaderboards** — externe Bewertung trifft D10 frontal
- ❌ **Cloud-Pflicht, Telemetrie, Account-Zwang**
- ❌ **Gamification als Deko** — Punkte ohne reale Konsequenz habituieren binnen Tagen und
  entwerten den Mechanismus dauerhaft
- ❌ **Ein KI-Assistent, der Entscheidungen trifft** — verletzt G2, zerstört die Auditierbarkeit
- ❌ **Feature-Vollständigkeit** — jedes Modul, das nicht auf D1–D12 einzahlt, wird nicht gebaut

---

## 9. Nächster Schritt

**Stufe 1 = M0 + M1 + M12 + zwei Wochen reines Messen.**
Keine Regeln, keine Empfehlungen, keine Optimierung. Erst Daten, dann Regelwerk.

Ein Regelwerk ohne Baseline ist geraten — und geratene Regeln werden zu Recht ignoriert.

→ [Roadmap](05-ROADMAP.md)
