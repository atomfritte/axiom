# Backlog

Ideen, die **bewusst nicht jetzt** gebaut werden.

Zweck dieses Dokuments: Der Systemizing-Drive erzeugt laufend neue Systemideen. Das ist Teil des
Profils (D3), kein Mangel an Disziplin. Ideen aufzuschreiben löst zwei Probleme gleichzeitig —
sie gehen nicht verloren (D9) und sie müssen nicht im Kopf behalten werden.

**Eintrag hier ≠ Zusage.** Die meisten Einträge werden nie gebaut, und das ist der Normalfall.

---

## Format

```
### Titel
- **Defizit:** D? (oder: keins — dann ist es Meta-Work)
- **Frühestens:** Stufe S?
- **Warum nicht jetzt:**
- **Notiert:** JJJJ-MM-TT
```

---

## Aufgenommen

### Kalender-Zweiweg-Sync
- **Defizit:** D4
- **Frühestens:** S3
- **Warum nicht jetzt:** Lesender Zugriff reicht für M3 Backward-Chaining. Schreibender Zugriff
  erhöht die Komplexität erheblich und löst kein zusätzliches Defizit.
- **Notiert:** 2026-08-03

### Galaxy-Watch-Companion
- **Defizit:** D7, D9
- **Frühestens:** S4
- **Warum nicht jetzt:** Erst muss belegt sein, dass die Kanäle auf dem Telefon genutzt werden.
  Ein zweites Gerät verdoppelt die Erfassungsoberfläche, bevor die erste steht.
- **Notiert:** 2026-08-03

### Sprachnotiz mit Transkription
- **Defizit:** D9
- **Frühestens:** S3
- **Warum nicht jetzt:** Der S-Pen ist reibungsärmer und läuft komplett offline. Transkription
  bräuchte entweder ein lokales Modell (Größe, Akku) oder Netzwerk — und `INTERNET` ist in
  S1–S3 nicht deklariert (ADR-0002).
- **Notiert:** 2026-08-03

### Regel-Analytik-Dashboard
- **Defizit:** keins direkt — dient der Regelqualität
- **Frühestens:** S4
- **Warum nicht jetzt:** Klassischer Meta-Work-Kandidat. Die Wochenreview-Tabelle aus
  `docs/06-METRIKEN.md §3` reicht, bis sie nachweislich nicht mehr reicht.
- **Notiert:** 2026-08-03

### Offline-LLM zur Muster-Auswertung der Baseline
- **Defizit:** keins direkt
- **Frühestens:** S4, und nur außerhalb der Entscheidungsschleife
- **Warum nicht jetzt:** ADR-0003. Zulässig wäre ausschließlich: Muster in Baseline-Daten
  vorschlagen, die der Nutzer dann selbst in eine Regel überführt. Nie eine Entscheidung treffen.
- **Notiert:** 2026-08-03

---

## Abgelehnt — Entscheidung ist gefallen

Diese Ideen werden auftauchen und attraktiv wirken. Sie stehen hier, damit die Entscheidung
bereits getroffen ist, bevor der Reiz kommt.

| Idee | Grund |
|---|---|
| Plugin-System / Skripting-Layer | Reiner Meta-Work-Treibstoff (D3, R1). YAML-Regeln sind die Erweiterungsgrenze |
| KI trifft Entscheidungen | Verletzt G2, zerstört Auditierbarkeit (ADR-0003) |
| Streaks mit Verlustmechanik | Bruch → Abbruch statt Korrektur (D10) |
| Punkte/Badges ohne reale Konsequenz | Habituiert binnen Tagen und entwertet den Mechanismus dauerhaft |
| Social, Sharing, Leaderboards | Trifft Rejection Sensitivity frontal (D10) |
| Veröffentlichung im Play Store | Anderes Projekt. Ändert alle Datenschutzannahmen |
| Web-Frontend | Kein Anwendungsfall, zusätzliche Angriffsfläche für Gesundheitsdaten |
| Multi-User, Rollen, Rechte | Kein Anwendungsfall |
| UI-Redesign vor S3 | Die klassische Ausweichbaustelle |

---

## Prüffrage bei jedem neuen Eintrag

> **Reduziert das die Last — oder erzeugt es nur ein interessanteres System?**

Wenn die Antwort nicht sofort klar ist, ist es das Zweite.
