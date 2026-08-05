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

### Biometrie-Gate vor dem Start
- **Defizit:** keins — Schutz, nicht Selbstregulation
- **Frühestens:** wenn das Gerät regelmäßig entsperrt aus der Hand gegeben wird
- **Warum nicht jetzt:** Die Datenbank ist verschlüsselt, aber der Schlüsselspeicher gibt sie
  jedem heraus, der die App öffnen kann. Ein Biometrie-Gate würde genau diese Lücke schließen —
  `setUserAuthenticationRequired(true)` am Keystore-Schlüssel, ein Satz Code. Es kostet aber
  einen Bildschirm vor jedem Start, in einer App, deren Erfassung unter drei Sekunden bleiben
  soll (G1). Der Reibungspreis ist real und der Zugewinn hängt daran, wie oft das entsperrte
  Gerät fremden Händen erreichbar ist. Erst entscheiden, dann bauen.
- **Notiert:** 2026-08-05

### Verschlüsselung auch auf dem Linux-Rechner
- **Defizit:** keins
- **Frühestens:** wenn der Rechner geteilt wird
- **Warum nicht jetzt:** Auf Android wickelt der Keystore die Passphrase ein. Linux hat nichts
  Gleichwertiges: Eine Schlüsseldatei neben der Datenbank wäre eine Attrappe, und `libsecret`
  wäre eine Abhängigkeit für einen Companion, der auf genau einem Rechner läuft. Bliebe eine
  Passphrase bei jedem Start — machbar, weil der Desktop nicht der Drei-Sekunden-Pfad ist, aber
  ein Bildschirm mehr für einen Rechner, dessen Benutzerkonto die eigentliche Grenze ist. Der
  Zustand wird stattdessen **angezeigt** (*System → Daten*), statt ihn zu verschleiern.
- **Notiert:** 2026-08-05

### Weboberfläche des Expertenmodus übersetzen
- **Defizit:** keins — Reichweite, nicht Selbstregulation
- **Frühestens:** wenn jemand ohne Deutsch den Expertenmodus benutzt
- **Warum nicht jetzt:** Die App hat zwei Sprachen, `index.html` hat eine: Alle Texte stehen
  fest auf Deutsch im Markup. Die App löst das über den deutschen Satz als Schlüssel — im
  Browser bräuchte es denselben Mechanismus, also eine ausgelieferte Tabelle und einen Aufruf
  pro Text. Machbar, aber es ist die Oberfläche, die genau ein Mensch benutzt. Sichtbare Folge:
  englische Screenshots der Weboberfläche gibt es nicht.
- **Notiert:** 2026-08-05

### Geofences für ortsgebundene Aufgaben
- **Defizit:** D2 — aber ohne Geofence gelöst
- **Frühestens:** nicht vorgesehen (siehe `docs/02-ARCHITEKTUR.md §8`)
- **Warum nicht jetzt:** Ein Geofence beantwortet „wo bin ich", die eigentliche Frage ist aber
  „was geht hier". Er kostet `ACCESS_BACKGROUND_LOCATION` — die eingriffstiefste Berechtigung,
  die Android kennt —, verlangt entweder Play Services (nutzt dieses Projekt nicht) oder einen
  dauerhaft messenden Dienst, und legt in einer Datenbank mit Gesundheitsdaten ein
  Bewegungsprofil an. Der Gegenwert wäre ein Kreis mit 200 m Radius, der nicht weiß, ob der
  Baumarkt offen hat. Gebaut wurde stattdessen `Task.place` als frei vergebener Name, gesetzt in
  zwei Tipps oder von einer Geräteroutine über `de.atomfritte.axiom.PLACE` — „WLAN Büro verbunden" ist
  genauer als jeder Kreis und kostet keine Berechtigung.
- **Notiert:** 2026-08-05

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
| Echte Geofences (GPS-Radius um einen Ort, Auslösung beim Betreten) | Ein Geofence beantwortet „wo bin ich", die Frage ist aber „was geht hier". Er kostet `ACCESS_BACKGROUND_LOCATION` — die eingriffstiefste Berechtigung, die Android kennt —, verlangt entweder Play Services (nutzt dieses Projekt nicht) oder einen dauerhaft messenden Dienst, und legt in einer Datenbank mit Gesundheitsdaten ein Bewegungsprofil an. Der Gegenwert ist ein Kreis, der nicht weiß, ob der Baumarkt offen hat. **Gebaut wurde stattdessen:** Orte als Kontext, vom Nutzer gesetzt oder von einer Samsung-Routine per Broadcast (`de.atomfritte.axiom.PLACE`). „WLAN Büro verbunden" ist genauer als jeder Radius, kostet keine Berechtigung und kann kein Profil hinterlassen. Wird das nach einigen Wochen nachweislich benutzt und ist das Setzen von Hand die Hürde, ist ein eigenes ADR fällig — vorher nicht |
| Projekte als eigener Typ (Projekt → Aufgabe → Teilschritt, mit eigener Ansicht, Farbe, Fortschritt) | Es gibt die Mechanik schon: `parentId`. Eine zerlegte Aufgabe **ist** ein Projekt, ihre Teilschritte sind seine Aufgaben, und die Kette darf beliebig tief werden. Ein zweiter Typ daneben wäre eine zweite Ordnungsachse — und die will gepflegt werden: Wohin gehört das hier? Brauche ich ein neues Projekt? Ist das noch dasselbe? Genau diese Fragen sind Meta-Work-Treibstoff (D3), und sie kommen ohne eine einzige erledigte Aufgabe aus. Statt dessen: die vorhandene Kette sichtbar machen (Baum, Fortschritt „2 von 5") |
| Statusfarben nach Monday-Vorbild (grün erledigt, rot kritisch, gelb in Arbeit) | Mondays Farben sind **Noten**: grün gut, rot schlecht. R7 sagt, Zustandswerte sind Messwerte und keine Noten — eine rote Aufgabe wäre ein Vorwurf, den man beim Draufsehen mitliest. Übernommen wird die Idee, nicht die Umsetzung: Eine Farbrampe für **Dringlichkeit**, abgeleitet aus dem Abstand zu `decayAt`, ist eine Messung. Überfällig ist eine Tatsache, kein Urteil |
| Sortier- und Filterbaukasten, speicherbare Ansichten | Eine Ansicht zu bauen ist befriedigender als sie zu benutzen (D3). Es bleibt bei drei festen Filtern — Suche, Reichweite, überfällig — und einer Reihenfolge, die nicht verstellbar ist: derselben, nach der das System auswählt. Zwei Reihenfolgen wären zwei Wahrheiten |
| Pomodoro als starres Ritual (feste 25/5, Pausenzwang, Pomodoro-Zähler) | Der nützliche Teil — ein sichtbares, begrenztes Zeitfenster — ist M4. Der starre Teil wäre eine Verschlechterung: Ein festes Intervall misst nichts, unterbricht produktiven Hyperfokus (G3) und der Pausenhaushalt ist Meta-Work (D3). Der Zähler wäre ein Streak (D10). Stattdessen: `plannedFocusFor(capacity)` |
| Multi-User, Rollen, Rechte | Kein Anwendungsfall |
| UI-Redesign vor S3 | Die klassische Ausweichbaustelle |

---

## Prüffrage bei jedem neuen Eintrag

> **Reduziert das die Last — oder erzeugt es nur ein interessanteres System?**

Wenn die Antwort nicht sofort klar ist, ist es das Zweite.
