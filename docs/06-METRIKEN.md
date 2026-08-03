# 06 — Metriken & Baseline-Protokoll

> Was nicht gemessen wird, existiert für ein Regelwerk nicht.
> Was gemessen wird, aber keine Entscheidung beeinflusst, ist Ballast.

Jede Metrik hier hat eine Konsequenz. Metriken ohne Konsequenz werden gestrichen.

---

## 1. Nordstern

**Gleiche Leistung bei messbar geringerer kognitiver Last.**

Nicht: mehr erledigen. Nicht: längere Streaks. Nicht: mehr Nutzung.
Der Zweck ist die Rückgewinnung von Regulationsreserve (D1).

Operationalisiert über drei Größen:

| Größe | Erhebung | Richtung |
|---|---|---|
| `load_index` (7-Tage-Mittel) | abgeleitet, siehe [Datenmodell §3.1](03-DATENMODELL.md) | ↓ |
| `compensation_effort` | Check-in-Frage: *"Wie viel Kraft hat es heute gekostet, den Tag zu strukturieren?"* 1–5 | ↓ |
| `recovery_quality` | Check-in-Frage: *"Hat die Erholung heute gewirkt?"* 1–5 | ↑ |

---

## 2. Kernmetriken (K1–K6)

| ID | Metrik | Definition | Ziel nach 90 Tagen | Konsequenz bei Verfehlung |
|---|---|---|---|---|
| **K1** | Erfassungsverlust | Anteil vergessener Verpflichtungen (im Review retrospektiv erfasst) | ≈ 0 | M1-Reibung senken (Kanal, Latenz) |
| **K2** | Kompensationslast | `load_index` 7-Tage-Mittel vs. Baseline | −15 Pkt bei gleicher externer Last | Erhaltungsmodus-Schwellen anpassen |
| **K3** | Terminstress | Check-in: Anspannung vor Terminen 1–5, bei **unveränderter Pünktlichkeit** | −1 Stufe | M3 Backward-Chaining nachschärfen |
| **K4** | Reizdeckung | Anteil `sensation_slot` mit `planned: true` an allen Slots | > 70 % | M5-Pool erweitern, Schwellen senken |
| **K5** | Impulsdurchbrüche | `impulse_intercepted` mit `outcome: proceeded` pro Monat | fallend | Cooldown verlängern, Checkliste überarbeiten |
| **K6** | **Meta-Work-Quote** | Zeit **in** AXIOM ÷ geschätzte Zeit **durch** AXIOM gewonnen | < 0,25 und fallend | 🔴 **Projekt-Stopp und Rückbau** |

**K6 ist das Abbruchkriterium des gesamten Projekts.** Steigt es über 1,0 — mehr Zeit im System
als durch das System gewonnen — ist AXIOM nachweislich Teil des Problems (D3, R1). Dann wird
zurückgebaut, nicht optimiert.

---

## 3. Regelqualität

Pro Regel, im Wochenreview:

```
fire_count        wie oft gefeuert
follow_rate       followed / (followed + deferred + rejected)
suppress_count    wie oft von höherer Regel verdrängt
```

| Muster | Diagnose | Maßnahme |
|---|---|---|
| `follow_rate` < 40 % | Regel nervt oder trifft nicht | DEPRECATED → nächste Woche entfernen |
| `fire_count` = 0 über 14 d | Bedingung zu eng oder tot | Bedingung prüfen oder streichen |
| `fire_count` > 20/Woche | Bedingung zu weit | Schwelle anheben, Cooldown verlängern |
| `suppress_count` hoch | Regelkonflikt | Priorität/Severity klären |

Ohne diese Auswertung wächst das Regelwerk monoton — und ein monoton wachsendes Regelwerk ist
die Meta-Work-Falle in Reinform.

---

## 4. Baseline-Protokoll (S1, 14 Tage)

**In dieser Phase gibt AXIOM keine einzige Empfehlung.** Es misst.

### Erhebung

| Zeit | Aktion | Dauer |
|---|---|---|
| ~09:00 | Check-in 1: Energie · Fokus · Stimmung · Reizbedarf | < 15 s |
| ~14:00 | Check-in 2 | < 15 s |
| ~21:00 | Check-in 3 + Kompensationsaufwand + Erholungsqualität | < 30 s |
| laufend | Capture bei jedem Impuls (S-Pen/Tile/Widget) | < 3 s |
| passiv | Health Connect: Schlaf, Schritte, Herzfrequenz | 0 s |
| passiv | Nutzungszeit AXIOM (M12) | 0 s |

Zusätzlich, ereignisbasiert und ohne Zwang:
- Termin wahrgenommen → tatsächlicher Zeitaufwand **inklusive Vorlauf und Puffer** (kalibriert M3)
- Impulshandlung erfolgt → Kanal, Betrag/Intensität, Zeit, Vorzustand (kalibriert M5/M6)
- Hyperfokus-Episode → Start, Ende, Ziel getroffen ja/nein (kalibriert M4)

### Wann ist die Baseline vollständig?

Nicht nach 14 Tagen — nach **drei erfüllten Bedingungen**. Der Stand steht in
der App unter *System → Eichung*, und die Hauptansicht meldet sich, sobald
alle drei erfüllt sind.

| Bedingung | Nötig | Warum |
|---|---|---|
| Zeitraum | 14 Tage | Kürzer erfasst keinen vollen Wochenrhythmus |
| Messpunkte | 20 Check-ins | Darunter bleiben pro Tageszeit zu wenige Messungen |
| Nächte | 7 Schlafeinträge | Für die Schlaf-Kapazitäts-Kopplung |

Die Schwellen stehen in `axiom_core/lib/src/engine/baseline.dart` — App und
`calibrate.dart` nutzen dieselben Werte, damit sie nicht auseinanderlaufen.

**Zeit allein genügt nicht.** Vierzehn Tage mit fünf Check-ins würden die
Gewichte auf Rauschen eichen, und ein auf Rauschen geeichtes System ist
schlechter als ein ehrlich geschätztes (R3).

### Auswertung nach 14 Tagen

1. **Circadianes Profil** — wann ist `capacity` real am höchsten? → `circadianBonus(t)`
2. **Schlafkopplung** — wie stark sagt Schlafschuld die Kapazität am Folgetag vorher? → Gewicht in `capacity`
3. **Reizzyklus** — nach wie vielen Stunden Niedrigreiz bricht ein Impuls durch? → Schwelle R-050
4. **Terminkosten** — reale Gesamtkosten eines Termins vs. Kalendereintrag → Puffer in M3
5. **Erfassungsquote** — welcher Kanal wird tatsächlich genutzt? → M1 auf diesen Kanal optimieren
6. **Baseline-Werte** für K1–K6 einfrieren → Vergleichsbasis für alle Folgemessungen

**Erst danach** werden Formelgewichte gesetzt und die ersten Regeln aus SHADOW aktiviert.

---

## 5. Reviewstruktur (M11)

Format bewusst als **Ops-Review**, nicht als Journal — dasselbe Vorgehen, das dieses Profil
beruflich akzeptiert.

### Täglich — max. 2 min, hart limitiert
```
1. Was ist heute liegengeblieben, das nicht liegenbleiben durfte?  (max 1 Eintrag)
2. Morgen: ein Anker, eine Aufgabe.
```

### Wöchentlich — max. 15 min, Konfigurationsfenster
```
1. Metriken K1–K6: Ist-Werte, Trend
2. Anomalien: Was ist auffällig abgewichen?
3. Regelqualität: Streichkandidaten, SHADOW-Regeln bewerten
4. Regeländerungen  ← das EINZIGE Zeitfenster dafür  (M12)
5. Nächste Woche: max. 3 Vorhaben
```

### Monatlich — max. 30 min
```
1. Zieltreue: Wovon habe ich mich lautlos verabschiedet?   ← D12, der Kernpunkt
2. Load-Trend, Erhaltungsmodus-Episoden
3. Modulaktivierung  ← das EINZIGE Zeitfenster dafür  (M12)
```

### Quartal — max. 60 min
```
1. Nordstern: Ist die Last gesunken?  Belegen, nicht behaupten
2. K6 Meta-Work-Quote: Rechtfertigt AXIOM seine eigenen Kosten?
3. Rückbau: Was kann WEG?   ← Pflichtpunkt, nicht optional
```

Der Rückbaupunkt ist Absicht. Jedes Review ohne Streichoption erzeugt monotones Wachstum.

---

## 6. Anti-Metriken

Werden **nicht** erhoben, nicht angezeigt, nicht gespeichert:

| Nicht gemessen | Grund |
|---|---|
| Streak-Länge mit Verlustmechanik | Bruch → Abbruch statt Korrektur (D10, R7) |
| Erledigungsquote als Bewertung | Erzeugt Schuld, misst nicht den Nordstern |
| Vergleich mit anderen | Trifft Rejection Sensitivity frontal (D10) |
| "Produktivitäts-Score" als Note | Verwandelt Messwert in Urteil (R7) |
| Nutzungsdauer als Erfolg | Verwechselt Symptom mit Ziel — hier ist Nutzung ein **Kosten**posten |

Ein Zustandswert ist ein **Messwert, keine Note**. `capacity: 28` bedeutet: *heute wird weniger
gezeigt*. Nicht: *du hast versagt*.
