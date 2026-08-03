# 07 — Risiken

Sortiert nach Eintrittswahrscheinlichkeit × Schaden. Die drei obersten sind **profilspezifisch** —
sie treffen nicht jedes Projekt, aber dieses mit hoher Wahrscheinlichkeit.

---

## R1 — Das Projekt wird selbst zur Prokrastination  🔴 sehr hoch

**Mechanik:** Der Systemizing-Drive (D3) findet in einem selbstgebauten Regelsystem sein perfektes
Ziel. Das System zu bauen ist stimulierender als alles, wofür es gebaut wird. Ergebnis: eine
elegante Architektur, ein durchdachtes Regelwerk — und ein Leben, das unverändert weiterläuft.

**Frühindikatoren:**
- Mehr Zeit in `docs/` und `rules/` als in der laufenden App
- Refactoring vor der ersten echten Nutzung
- S3-Module werden gebaut, während S1 kaum genutzt wird
- Die Idee "erst noch schnell das Plugin-System" taucht auf

**Gegenmaßnahmen:**
- M12 Meta-Guard ist Stufe 1, nicht später
- Harte Abbruchkriterien pro Stufe ([Roadmap](05-ROADMAP.md))
- Verhältnis **Zeit IN AXIOM : Zeit DURCH AXIOM gewonnen** ist eine Kernmetrik
- CLAUDE.md verpflichtet Claude, bei Feature-Wünschen ohne D-Bezug zu widersprechen

**Restrisiko:** hoch. Dies ist das Risiko, das das Projekt tatsächlich beenden wird, wenn es
scheitert. Nicht Technik, nicht Zeit.

---

## R2 — Benachrichtigungsflut → Abstumpfung → Deinstallation  🔴 hoch

**Mechanik:** Jede Regel ist einzeln vernünftig. In Summe entsteht Dauerbeschallung. Erst werden
Benachrichtigungen weggewischt, dann stummgeschaltet, dann ist die App tot. Der häufigste
Sterbeverlauf von ADHS-Apps überhaupt.

**Gegenmaßnahmen:**
- Globale Obergrenzen (`max_interventions_per_day: 12`, `max_notifications_per_hour: 2`)
- Cooldown ist ein Pflichtfeld — keine Regel ohne
- Exponentielles Backoff bei wiederholter Ablehnung
- SHADOW-Phase: jede Regel läuft ≥ 7 Tage stumm mit, bevor sie sprechen darf
- Wochenreview listet Streichkandidaten

**Restrisiko:** mittel. Die Mechanik ist bekannt und strukturell adressiert.

---

## R3 — Falsche Formeln erzeugen falsche Empfehlungen → Vertrauensverlust  🟠 hoch

**Mechanik:** Die Startgewichte in `weights.yaml` sind plausibel geraten, nicht validiert. Sagt die
App bei `capacity: 30` "mach die schwere Aufgabe", ist das Vertrauen weg. Und ein Systemizer gibt
einem System, das nachweislich falsch rechnet, keine zweite Chance — zu Recht.

**Gegenmaßnahmen:**
- S1 ist **reines Messen**, 14 Tage, keine Empfehlungen
- Kalibrierung gegen echte Baseline-Daten vor der ersten Live-Regel
- Jede Ausgabe zeigt ihre Herleitung — ein sichtbar falscher Rechenweg ist korrigierbar, ein
  unsichtbarer ist nur enttäuschend
- Feedback-Loop (`followed`/`deferred`/`rejected`) macht Regelqualität messbar

**Restrisiko:** mittel. Transparenz verwandelt Fehler in Kalibrierungsdaten.

---

## R4 — Android killt Hintergrundprozesse (Samsung-spezifisch)  🟠 hoch

**Mechanik:** Samsungs Akku-Optimierung beendet Hintergrunddienste aggressiv. Zeittrigger feuern
nicht oder verspätet. Da Zeittrigger bei diesem Profil der **wirksamste** Interventionstyp sind
(D4), entwertet das den Kern des Systems.

**Gegenmaßnahmen:**
- Onboarding erzwingt: Batterieoptimierung aus, "Nie schlafen legen" für AXIOM
- `SCHEDULE_EXACT_ALARM` statt `WorkManager` für alles Zeitkritische
- **Selbsttest:** AXIOM prüft täglich, ob die eigenen Alarme pünktlich gefeuert haben, und meldet
  Drift sichtbar — ein stiller Ausfall wäre schlimmer als ein lauter
- Foreground-Service während aktiver Slots

**Restrisiko:** mittel. Nicht vollständig beherrschbar, aber erkennbar.

---

## R5 — Fehlalarme des Focus Governor  🟠 mittel

**Mechanik:** M4 unterbricht produktiven Hyperfokus zur falschen Zeit. Der wertvollste kognitive
Zustand dieses Profils wird zerstört — und die Ursache ist die App. Das ist die schnellste Art,
Ablehnung zu erzeugen.

**Gegenmaßnahmen:**
- M4 erst in S3, nach Kalibrierung
- Voreingestellter Anker: Ist der Fokus **auf** dem geplanten Ziel, wird geschützt statt unterbrochen
- Gestufte Eskalation (sanft → deutlich), nie sofort hart
- Abbruchkriterium: `rejected` > 40 % → zurückbauen, nicht verfeinern

**Restrisiko:** mittel.

---

## R6 — Datenleck / Gerät kompromittiert  🟠 mittel (Schaden: sehr hoch)

**Mechanik:** Die Daten dokumentieren psychische Verfassung, Impulskontrolle, Substanzkonsum,
Beziehungskonflikte, Medikation. Bei Verlust: erheblicher persönlicher Schaden, potenziell mit
beruflichen und versicherungsrechtlichen Folgen.

**Gegenmaßnahmen:**
- SQLCipher, Schlüssel im Android Keystore, Biometrie-Gate
- Kein Netzwerkzugriff im Core. Keine Telemetrie. Kein Analytics-SDK. Kein Crash-Reporting an Dritte
- `rules/personal/` ist git-ignoriert
- Export nur verschlüsselt und nur auf explizite Aktion
- Sync (S4) E2E-verschlüsselt — der Server sieht nie Klartext
- **Vor jedem `git push`:** prüfen, ob echte persönliche Daten im Diff sind

**Restrisiko:** niedrig bei Einhaltung — aber der Schaden im Eintrittsfall ist der höchste im
Projekt. Deshalb keine Ausnahmen.

---

## R7 — Selbstoptimierungs-Druck & Quantified-Self-Falle  🟡 mittel

**Mechanik:** Ein Score, der den eigenen Zustand misst, wird zum Ziel. Schlechte `capacity` fühlt
sich an wie persönliches Versagen. Bei RSD-Anfälligkeit (D10) erzeugt das exakt die
Selbstabwertung, die das System reduzieren sollte. Die App würde dann zur zusätzlichen
Bewertungsinstanz — dem genauen Gegenteil ihres Zwecks.

**Gegenmaßnahmen:**
- Alle Anti-Ziele: keine Streaks mit Verlustmechanik, keine Schuld-Formulierungen, kein Vergleich
- Sprachregelung: Zustände sind **Messwerte, keine Noten**. "Kapazität 30" ist eine Information,
  kein Urteil
- Niedrige `capacity` löst *Entlastung* aus (weniger wird gezeigt), nicht Ermahnung
- L3 Erhaltungsmodus ist ausdrücklich ein Erfolg des Systems, kein Scheitern des Nutzers

**Restrisiko:** mittel. Erfordert bewusste Sprachpflege in jedem UI-Text.

---

## R8 — Datenlücken machen Regeln blind  🟡 mittel

**Mechanik:** Check-ins werden ausgelassen. Der StateVector wird ungenau. Regeln feuern auf Basis
veralteter Werte. Kaskadierende Fehlentscheidungen.

**Gegenmaßnahmen:**
- Konfidenzwert pro Dimension: bei alten Daten wird der Zustand **konservativ** geschätzt
- Regeln unterhalb eines Konfidenzschwellenwerts feuern nicht — lieber schweigen als raten
- Passive Signale (Health, Nutzung, Uhrzeit) tragen auch ohne Check-in
- Kein Nachtragen-Zwang, keine Lückenmahnung: **das System läuft weiter, auch nach 3 stillen Tagen**

**Restrisiko:** niedrig.

---

## R9 — Über-Engineering des Kerns  🟡 mittel

**Mechanik:** Event Sourcing, Ports & Adapters, DSL, Validator — für einen Ein-Nutzer-Fall
angemessen? Die Antwort ist hier **ja**, aber die Grenze ist schmal: Jede weitere
Abstraktionsschicht ist ab sofort verdächtig.

**Gegenmaßnahmen:**
- Die "Nicht gebaut"-Liste in [02-ARCHITEKTUR.md §8](02-ARCHITEKTUR.md) ist bindend
- Priorisierungsregel: das Einfachere gewinnt
- CLAUDE.md verpflichtet Claude, gegen unnötige Abstraktion zu argumentieren

**Restrisiko:** mittel — eng gekoppelt an R1.

---

## R10 — Verwechslung mit Behandlung  🟡 niedrig (Schaden: hoch)

**Mechanik:** AXIOM misst Zustände, die klinisch aussehen. Ein anhaltend hoher `load_index` kann
Erschöpfungsdepression bedeuten — die App kann das nicht unterscheiden und darf es nicht versuchen.
Risiko: Die App wird als Ersatz für Diagnostik oder Behandlung genutzt, und eine reale
Verschlechterung wird als "Systemwert" abgetan.

**Gegenmaßnahmen:**
- Keine diagnostische Sprache. Kein Screening-Score. Keine klinischen Schwellenwerte
- Bei anhaltendem L3 (> 14 Tage): sichtbarer Hinweis, professionelle Abklärung zu erwägen
- Krisen-Kontakte hinterlegbar und im Erhaltungsmodus sichtbar
- M13 protokolliert Medikation, empfiehlt aber **nie** eine Dosis oder Änderung
- Disclaimer in README und Onboarding

**Restrisiko:** niedrig bei klarer Abgrenzung — aber der einzige Punkt mit gesundheitlichem
Schadenspotenzial. Deshalb explizit gelistet.

---

## Risikoübersicht

| ID | Risiko | W'keit | Schaden | Priorität |
|---|---|---|---|---|
| R1 | Projekt als Prokrastination | sehr hoch | hoch | 🔴 |
| R2 | Benachrichtigungsflut | hoch | hoch | 🔴 |
| R3 | Falsche Formeln → Vertrauensverlust | hoch | hoch | 🟠 |
| R4 | Android killt Hintergrund | hoch | mittel | 🟠 |
| R5 | Focus-Governor-Fehlalarme | mittel | hoch | 🟠 |
| R6 | Datenleck | niedrig | sehr hoch | 🟠 |
| R7 | Quantified-Self-Falle | mittel | mittel | 🟡 |
| R8 | Datenlücken | mittel | mittel | 🟡 |
| R9 | Über-Engineering | mittel | mittel | 🟡 |
| R10 | Verwechslung mit Behandlung | niedrig | hoch | 🟡 |

**Wenn dieses Projekt scheitert, dann an R1.** Nicht an Technik, nicht an Zeitmangel. Deshalb ist
M12 Meta-Guard Stufe 1 und nicht Stufe 4.
