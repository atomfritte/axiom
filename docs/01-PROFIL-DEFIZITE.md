# 01 — Zielprofil & Defizitanalyse

> **Kein klinisches Dokument, keine Personenbeschreibung.** Dies ist die Entwurfsgrundlage einer
> Software: ein **Zielprofil**, gegen das entwickelt wird — vergleichbar mit einer Persona, nicht
> mit einer Akte. Es beschreibt kein Individuum, ersetzt keine Diagnostik, keine Therapie und keine
> ärztliche Beratung. Alle Aussagen sind Konstruktionsannahmen, die das System **messbar machen**
> soll — nicht Wahrheiten, die es voraussetzt.
>
> Der Nutzen dieses Dokuments liegt in der Ableitung: Jede Designentscheidung im Repository
> verweist auf einen Punkt aus `D1`–`D12`. Ohne diese Liste wäre nicht nachvollziehbar, warum die
> App gebaut ist, wie sie gebaut ist.

---

## 1. Zielprofil

| Dimension | Ausprägung |
|---|---|
| Grundmuster | ADHS, kombinierter Typus |
| Kompensationsgrad | hoch ("hochkompensiert, kognitiv") |
| Leitmotiv 1 | **Systemizing-Drive** — Logik, Regeln, Determinismus, Pünktlichkeit |
| Leitmotiv 2 | **High Sensation Seeking** — Reizhunger, Novelty, Risikotoleranz |
| Lebensphase | Erwachsenenalter, Kompensation über Jahrzehnte eingeübt |
| Referenzgerät | Android-Flaggschiff mit Stift und Always-on-Display, dazu ein Linux-Desktop |

### 1.1 Die zentrale Spannung

Das Profil ist kein Defizit-Profil, sondern ein **Konflikt-Profil**. Zwei Systeme ziehen
gegeneinander:

```
  SYSTEMIZING-DRIVE                  HIGH SENSATION SEEKING
  Ordnung, Regel, Vorhersagbarkeit   Neuheit, Intensität, Unvorhersagbarkeit
  Zeit als Vertrag                   Zeit als Störung
  "Erst zu Ende bringen"             "Jetzt das Neue"
             \                                  /
              \                                /
               ->  ADHS-Exekutivsystem  <-
                   (begrenzte Regulationsreserve)
```

Der Systemizing-Drive ist der **Kompensationsmechanismus**. Er funktioniert — deshalb
"hochkompensiert". Aber er läuft auf demselben knappen Budget wie alles andere. Und Sensation
Seeking **plündert** genau dieses Budget.

**Konsequenz für die App:** Das Ziel ist nicht "mehr Struktur". Struktur ist bereits im Überfluss
vorhanden und wird manuell erzeugt — *das ist der Kostenpunkt*. Das Ziel ist **Auslagerung der
Struktur-Erzeugung**, damit die Regulationsreserve für das Leben frei wird.

---

## 2. Defizitbereiche

Sortiert nach **Hebelwirkung** (Schadenspotenzial x Beeinflussbarkeit durch Software),
nicht nach Lehrbuch-Reihenfolge.

---

### D1 — Kompensationskosten & Erschöpfungsspirale  ⚠️ HÖCHSTE PRIORITÄT

**Das eigentliche klinische Risiko dieses Profils in diesem Alter.**

Hochkompensiert heißt: Die Leistung stimmt, der Preis ist unsichtbar. Jede erbrachte Struktur
wurde in Echtzeit im Kopf berechnet — Termine, Übergänge, Zeitpuffer, soziale Erwartungen. Nach
Jahrzehnten läuft das System dauerhaft am Limit, ohne dass ein einzelner Tag auffällig wäre.

**Symptomatik:** Erholung wirkt nicht mehr. Wochenenden reichen nicht. Reizbarkeit steigt bei
gleichbleibender Last. Rückzug aus sozialem Kontakt "aus Effizienzgründen". Zunehmende
Alles-oder-nichts-Reaktionen. Klassischer Verlauf Richtung Erschöpfungsdepression — die bei
spätdiagnostizierten Erwachsenen häufig *als Erstdiagnose vor* dem ADHS steht.

**Warum es hier besonders greift:** Ein Systemizer merkt den Absturz zuletzt, weil das System bis
kurz vor dem Bruch nach außen fehlerfrei läuft. Es gibt kein Frühwarnsignal — bis der Ausfall total ist.

**Softwarehebel:** hoch. Das ist ein **Messproblem**, und Messprobleme sind lösbar.
→ Modul **M9 Load Monitor** (Kompensationskosten-Radar mit Eskalationsstufen)

---

### D2 — Task Initiation: die Aktivierungsenergie-Barriere

Der Klassiker, aber hier mit spezifischer Färbung. Das Problem ist **nicht** Wissen (was ist
wichtig?), **nicht** Planung (wie ginge es?), sondern der **Kaltstart**.

Ein hochkompensierter Systemizer erkennt man daran, dass er eine perfekte Priorisierung besitzt
und trotzdem die oberste Aufgabe nicht anfängt. Das ist kein Willensdefizit — die Aufgabe erzeugt
schlicht kein hinreichendes dopaminerges Signal, um den Start zu triggern.

**Der Multiplikator:** Sensation Seeking. Eine langweilige Aufgabe ist für dieses Profil nicht
"etwas unangenehm", sondern **physiologisch aversiv**. Die Aufgabe konkurriert mit einem Gehirn,
das aktiv nach Stimulation sucht.

**Softwarehebel:** sehr hoch — aber nur, wenn das Datenmodell stimmt. Klassische To-do-Apps
modellieren `priority`. Das ist die falsche Achse.
→ Modul **M2 Task Kernel** mit expliziter `activation_energy` als Erstklasse-Dimension

---

### D3 — Die Meta-Work-Falle  ⚠️ EXISTENZIELL FÜR DIESES PROJEKT

**Der Systemizing-Drive ist selbst ein Prokrastinationsvehikel.**

System bauen fühlt sich an wie Arbeit, wird belohnt wie Arbeit (Kontrolle, Ordnung, Neuheit,
Kompetenzerleben) — und ist doch keine. Das System zu optimieren ist **immer** stimulierender als
die Aufgabe, für die das System gebaut wurde. Ergebnis: eine Sammlung von 47 halbfertigen
Produktivitätssystemen und keine erledigte Steuererklärung.

**Diese App ist die perfekte Meta-Work-Falle.** Sie ist ein regelbasiertes, konfigurierbares,
selbstgebautes System — also exakt der Köder, auf den dieses Profil maximal anspringt. Ohne
Gegenmaßnahme wird das Projekt selbst zum Symptom.

**Softwarehebel:** Nur durch **eingebaute Selbstbeschränkung**. Die App muss ihre eigene Nutzung
deckeln und Konfiguration rationieren. Das ist kein Nice-to-have, das ist eine Architektur-Anforderung.
→ Modul **M12 Meta-Guard** — nicht verhandelbar, ab v0.1

---

### D4 — Zeitwahrnehmung: Pünktlichkeit als teure Kompensation

**Wichtige Umdeutung:** Pünktlichkeit ist hier *kein Nicht-Defizit*. Sie ist ein **erfolgreich
kompensiertes Defizit — und die Kompensation ist teuer.**

Zeitblindheit (defizitäre Intervallschätzung) ist bei ADHS robust vorhanden. Wer trotzdem
zuverlässig pünktlich ist, erreicht das über: massive Sicherheitspuffer, ständiges mentales
Nachrechnen, Wartezeit-Verluste, und permanente Hintergrund-Anspannung vor jedem Termin. Der
Termin kostet nicht 60 Minuten, sondern 150 — plus Regulationsreserve.

**Zweitwirkung:** Weil Pünktlichkeit als *Regel* internalisiert ist, erzeugt drohende
Unpünktlichkeit eine unverhältnismäßige Stressreaktion (Regelbruch → Selbstwert). Das ist eine
verdeckte Hauptquelle chronischer Anspannung.

**Softwarehebel:** sehr hoch, und die Stärke wird zur Ressource: Zeitgetriggerte Prompts werden von
diesem Profil **zuverlässig befolgt** — Pünktlichkeit gilt auch gegenüber der App.
→ Modul **M3 Time Anchor** (automatisches Backward-Chaining statt manuellem Kopfrechnen)

---

### D5 — Reizhunger & Impulsdurchbruch (Sensation Seeking)

Im Erwachsenenalter verschiebt sich das Risikoprofil von "waghalsig" zu **teuer und
folgenreich**. Die Literatur beschreibt durchgängig dieselben Kanäle; welche davon im Einzelfall
tragen, ist genau die Frage, die die Baseline-Phase beantwortet:

| Kanal | Typische Ausprägung |
|---|---|
| Finanziell | Impulskäufe, spekulatives Handeln, Anschaffungs-Rush |
| Beruflich | Pivot bei Reizarmut, Projekt-Sprunghaftigkeit |
| Verkehr | Geschwindigkeit als legaler, jederzeit verfügbarer Dopamin-Automat |
| Substanzen | Alltagssubstanzen als Selbstmedikation — erhöhtes Komorbiditätsrisiko |
| Digital | Doomscrolling, Novelty-Feeds, Nachtstunden-Konsum |
| Sozial | Reizsuche in reizarmen Phasen ("Langeweile als Gefahr") |

**Zentrale Einsicht:** Sensation Seeking lässt sich **nicht wegtrainieren**. Der Bedarf ist real
und physiologisch. Ungedeckter Bedarf sucht sich den nächstbesten Kanal — und der ist meistens
der schädlichste, weil der schnellste.

**Umdeutung:** Reizbedarf ist kein Defizit, sondern ein **Rohstoff**, der ein Budget braucht.
Ein Sportler, ein Motorrad, Kälteexposition, laute Musik, Wettkampf — das sind legitime,
planbare Deckungen desselben Bedarfs.

**Softwarehebel:** hoch, zweistufig.
→ Modul **M5 Sensation Budget** (proaktive Deckung) + **M6 Impulse Interceptor** (reaktive Bremse)

---

### D6 — Hyperfokus: Allokationsdefizit, nicht Aufmerksamkeitsdefizit

Aufmerksamkeit ist reichlich vorhanden. Steuerbar ist sie nicht. Zwei Fehlermodi:

- **Falsches Ziel:** 6 Stunden auf ein irrelevantes technisches Detail, während die Frist verstreicht.
- **Kein Ausstieg:** Auch bei richtigem Ziel wird der Ausstieg verpasst — Essen, Trinken, Schlaf,
  Termine, Beziehung. Der produktivste Zustand ist gleichzeitig der teuerste.

**Softwarehebel:** hoch, aber **hochsensibel**. Falsch dosierte Unterbrechung zerstört den
wertvollsten kognitiven Zustand, den dieses Profil hat. Die Regel muss lauten: *schützen wenn
richtig, unterbrechen wenn falsch* — und die Unterscheidung braucht einen vorher gesetzten Anker.
→ Modul **M4 Focus Governor** (gestufte Eskalation, kein hartes Alarmieren)

---

### D7 — Interozeption: der blinde Körper

Hunger, Durst, Blase, Müdigkeit, beginnende Überlastung werden systematisch zu spät bemerkt.
Bei ADHS gut belegt und im Alltag durchgängig unterschätzt.

**Warum im Erwachsenenalter relevant:** Was in jungen Jahren folgenlos bleibt, wird später zum
kardiometabolischen Risikofaktor — Dehydrierung, unregelmäßige Mahlzeiten, Bewegungsmangel im Hyperfokus,
Schlafdefizit. Und: körperlicher Zustand ist der **größte einzelne Modulator** der
Exekutivfunktion. Ein dehydrierter, unterschlafener Tag hat objektiv weniger Kapazität.

**Softwarehebel:** sehr hoch bei sehr geringem Aufwand — reine Zeittrigger, und Zeittrigger
sind bei diesem Profil (D4) hochwirksam.
→ Modul **M7 Body Loop** (+ Health-Connect-Anbindung)

---

### D8 — Schlaf: verzögerte Phase als Systemverstärker

Verzögerte Schlafphase ist bei ADHS die Regel, nicht die Ausnahme. Verstärkt durch Sensation
Seeking: Die Nacht ist reizarm genug für Hyperfokus und bietet zugleich die stärkste Novelty
(niemand stört, alles ist möglich). "Revenge Bedtime Procrastination" ist bei diesem Profil
nahezu vorprogrammiert.

**Kaskade:** Schlafdefizit → Exekutivfunktion sinkt → Kompensationsaufwand steigt → Reizhunger
steigt (Dopamin-Unterversorgung) → Abendkonsum steigt → Schlafdefizit. Ein sich selbst
verstärkender Kreis, der jedes andere Modul untergräbt.

**Softwarehebel:** hoch — aber nur über **Abendrituale und Ausstiegsanker**, nie über
Schlaf-Tracking allein. Messen allein ändert nichts.
→ Modul **M8 Sleep Gate**

---

### D9 — Arbeitsgedächtnis & Objektpermanenz

Bei hoher Kompensation maskiert, aber unter Last unmittelbar sichtbar: Der Gedanke, der beim
Aufstehen da war, ist beim Ankommen weg. Was nicht sichtbar ist, existiert nicht.

**Kritischer Punkt:** Die Erfassungslücke. Zwischen "Idee/Verpflichtung entsteht" und "irgendwo
sicher notiert" liegt ein Zeitfenster von wenigen Sekunden. Jede Reibung in diesem Fenster —
Entsperren, App suchen, Kategorie wählen — führt zum Totalverlust der Information.

**Softwarehebel:** sehr hoch, und fast vollständig eine Frage der Reibung: Der beste Kanal ist
der, der ohne Entsperren, ohne App-Start und ohne Auswahl auskommt. Welche das auf einem konkreten
Gerät sind, steht in [08-GERAET](08-GERAET-S25U.md).
→ Modul **M1 Capture** (< 3 Sekunden, immer, ohne Kategorisierungszwang)

---

### D10 — Emotionale Dysregulation & Rejection Sensitivity

Bei Erwachsenen mit ADHS häufig der subjektiv belastendste Anteil und zugleich der am seltensten
adressierte. Beschrieben wird: unverhältnismäßig starke, sehr schnell einsetzende Reaktion auf
wahrgenommene Ablehnung, Kritik oder eigenes Scheitern. Dauer meist kurz, Nachwirkung lang
(Vermeidung, Rückzug, Beziehungsschäden, überstürzte Entscheidungen).

**Profilspezifisch verschärfend:** Ein Systemizer mit internalisiertem Regelwerk erlebt eigenes
Scheitern als *Regelbruch*, nicht als Ereignis. Das erhöht die Selbstwert-Kopplung erheblich.

**Softwarehebel:** mittel — Software ist kein Therapieersatz. Was funktioniert: **Latenz einbauen**
zwischen Impuls und Handlung, und Nachbereitung in einem Format, das dieses Profil akzeptiert.
Ein "Gefühlstagebuch" wird abgelehnt. Ein **Post-Mortem mit Root-Cause-Analyse** wird geführt.
Identischer Inhalt, anderes Framing — und das Framing entscheidet über die Adhärenz.
→ Modul **M10 Signal Log** (Incident/Post-Mortem-Framing)

---

### D11 — Kontextwechsel & Wiedereinstiegskosten

Jeder Wechsel kostet Aufbauzeit, jede Unterbrechung wirft den mühsam geladenen Kontext weg. Bei
diesem Profil wird die Unterbrechung zusätzlich **aktiv gesucht** (Sensation Seeking) — der
Wechsel selbst ist der Reiz.

**Softwarehebel:** mittel-hoch. Kein Session-Zwang, sondern **Wiedereinstiegs-Breadcrumbs**:
Beim Verlassen automatisch den Zustand einfrieren, beim Zurückkommen wiederherstellen.
→ Teil von **M4 Focus Governor**

---

### D12 — Langzeit-Zielverfolgung & Belohnungsdiskontierung

Zukünftige Belohnungen verlieren bei ADHS überproportional schnell an Wert. Alles jenseits von
~2 Wochen ist motivational praktisch unsichtbar. Konsequenz: exzellente Wochenplanung,
kollabierende Jahresplanung. Ziele werden nicht aufgegeben — sie **verschwinden lautlos**.

**Softwarehebel:** mittel. Ziele müssen periodisch **zwangsweise re-materialisiert** werden,
sonst existieren sie nicht.
→ Modul **M11 Review Cadence** (Wochen-/Monats-/Quartals-Review mit hartem Zeitdeckel)

---

## 3. Stärken als Systemressourcen

Ein Defizit-only-Blick baut die falsche App. Diese Stärken sind **tragende Bauteile**:

| Stärke | Wie das System sie nutzt |
|---|---|
| Systemizing | Regeln sind **sichtbar, lesbar, editierbar, versioniert**. Keine Black Box. Jede Empfehlung nennt die Regel-ID, die sie erzeugt hat. Vertrauen entsteht hier durch Nachvollziehbarkeit — nicht durch Politur. |
| Pünktlichkeit | Zeitgetriggerte Interventionen haben bei diesem Profil eine sehr hohe Befolgungsrate. Der stärkste verfügbare Trigger-Typ. |
| Regelbindung | Selbst gesetzte Regeln wirken als **Vertrag mit dem Vergangenheits-Ich** — der Kern von M6 Impulse Interceptor. |
| Sensation Seeking | Antrieb, sobald der Reiz *auf das Ziel gelegt* wird: Wettkampf, Streak-Risiko, Zeitdruck, Neuheit. Nicht dämpfen — umlenken. |
| Technische Kompetenz | Vollzugriff auf eigene Daten (SQLite, YAML, Export). Volle Diagnostizierbarkeit. Ein Nutzer, der sein eigenes System debuggen kann, bleibt dabei. |
| Hyperfokus | Bewusst als planbare Ressource behandeln statt als Störung: Deep-Work-Slots werden geschützt, nicht unterbrochen. |

---

## 4. Ableitung: die vier Systemgesetze

Aus D1–D12 folgen vier nicht verhandelbare Designgesetze. Sie stehen in
[CLAUDE.md](../CLAUDE.md) und gelten für jede Zeile Code.

1. **G1 — Auslagern statt anfordern.** Das System darf nie zusätzliche kognitive Last erzeugen.
   Jede Interaktion, die Nachdenken erfordert, ist ein Designfehler. (aus D1, D9)
2. **G2 — Erklärbar statt intelligent.** Jede Ausgabe muss auf eine sichtbare Regel zurückführbar
   sein. Ein Systemizer verwirft ein System, das er nicht auditieren kann. (aus Stärken)
3. **G3 — Kanalisieren statt unterdrücken.** Reizbedarf wird gedeckt und gelenkt, nie moralisiert.
   (aus D5)
4. **G4 — Die App muss sich selbst begrenzen.** Sie deckelt ihre eigene Nutzungszeit und rationiert
   ihre eigene Konfiguration. (aus D3)

---

## 5. Offene Punkte (durch Nutzung zu klären)

Das Zielprofil ist eine Annahme, keine Messung. Was es offen lässt, klärt erst die Nutzung:

- **Wirkfenster:** Wo eine Medikation im Spiel ist, ist ihr Wirkfenster der stärkste bekannte
  Modulator der Tagesplanung — Aufgaben mit hoher Aktivierungsenergie gehören hinein. Modul **M13**
  ist ein optionales Add-on, standardmäßig **aus**, und protokolliert ausschließlich. Es empfiehlt
  **nie** eine Dosis, eine Einnahmezeit oder eine Änderung.
- **Komorbiditäten:** Angst, Depression und Schlafstörung treten in dieser Gruppe häufig auf und
  verändern die Priorisierung erheblich. Das System misst Indikatoren und **diagnostiziert nichts**.
- **Reale Lastverteilung:** Beruf, Verpflichtungen und soziales Umfeld sind hier bewusst nicht
  modelliert. Die Baseline-Phase (2 Wochen reines Messen) existiert genau dafür —
  **Regeln erst nach Daten**.
