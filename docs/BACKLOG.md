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

### Ein Name pro Messwert — „Reichweite heute" ist „Kapazität"
- **Defizit:** D9 — und R7 hängt mit dran
- **Frühestens:** sobald jemand `instruments.dart` und `state_screen.dart` in einer Hand hat
- **Warum nicht jetzt:** Die Reichweitenkante beschriftet die Kapazität mit *Reichweite heute*,
  der Zustandsschirm nennt dieselbe Zahl *Kapazität*, und die Regelbegründungen sprechen von
  *capacity*. Beim Umbau der Mulde ist die doppelte **Anzeige** verschwunden — auf „Jetzt" stand
  „Reichweite heute 61" und drei Zentimeter darunter „Kapazität 61". Geblieben ist der doppelte
  **Name**: derselbe Messwert heißt auf zwei Bildschirmen verschieden, und wer beide sieht, sucht
  nach dem Unterschied, den es nicht gibt. Zu ändern wären `ReachEdge` in
  `packages/axiom_app/lib/design/widgets/instruments.dart` und die Kopfzeile in
  `state_screen.dart` — beides lag außerhalb dieser Runde. Welcher der beiden Namen gewinnt, ist
  eine echte Frage: „Kapazität" ist der Begriff des Regelwerks, „Reichweite heute" sagt, was die
  Zahl *tut*. Entscheiden, dann überall gleich schreiben.
- **Notiert:** 2026-08-06

### „Review" eindeutschen
- **Defizit:** keins — Sprachkonsistenz
- **Frühestens:** bei der nächsten Arbeit an `review_screen.dart`
- **Warum nicht jetzt:** Der Bildschirm heißt `{0}-Review`, also „Tag-Review", „Woche-Review".
  Das ist ein englisches Wort in einer Oberfläche, deren deutscher Satz zugleich der
  Übersetzungsschlüssel ist — und „Woche-Review" ist auch als deutsche Fügung falsch gebildet.
  „Tagesrückblick" und „Wochenrückblick" wären richtig. Die Zeile in der Mulde auf „Jetzt" trägt
  denselben Namen wie der Bildschirm, absichtlich; sie muss deshalb mitgeändert werden, und
  `review_screen.dart` gehörte in dieser Runde jemand anderem.
- **Notiert:** 2026-08-06

### Die 16 Regeln ohne Test nachziehen
- **Defizit:** keins — Werkzeugqualität, zahlt auf G2 ein
- **Frühestens:** eine Regel pro Gelegenheit, nicht als Block
- **Warum nicht jetzt:** Das Gate ist gebaut — der Validator gleicht jede Regel-ID gegen
  `packages/axiom_core/test/rules/` ab, eine neue Regel ohne Test ist ein Fehler. Offen ist der
  Altbestand: 16 der 18 ausgelieferten Regeln stehen namentlich auf der Ausnahmeliste und
  erscheinen als Warnung. Sie in einem Zug nachzuziehen wäre ein Nachmittag Meta-Work ohne eine
  einzige erledigte Aufgabe (D3). Der Weg ist stattdessen: Wer eine dieser Regeln anfasst,
  schreibt ihren Test und streicht sie von der Liste. Solange sie draufsteht, wird ihre Bedingung
  nirgends gegen einen Zustand ausgewertet — das ist der Preis, und er steht hier, damit er
  sichtbar bleibt.
- **Notiert:** 2026-08-06

### R-010 und R-090 autorisieren oder herabstufen
- **Defizit:** keins — es geht um den Vertrag hinter G4
- **Frühestens:** im nächsten Wochenreview, in Ruhe, nicht wenn eine der beiden gerade eingreift
- **Warum nicht jetzt:** `severity: enforce` heißt, eine Regel verändert Systemverhalten — sie
  sperrt, sie schaltet um, sie darf Ruhezeiten durchbrechen. Das Regelwerk nennt das den
  „Vertrag mit dem Vergangenheits-Ich": zulässig nur, wenn man diese eine Regel im ruhigen
  Zustand selbst autorisiert hat. Seit dem 2026-08-06 trägt R-052 dafür ein `authorised_on`.
  R-010 und R-090 greifen genauso ein, haben das Datum aber nicht — der Validator warnt bei
  jedem Lauf. Beides ist möglich und beides ist in Ordnung: Datum eintragen, oder auf
  `intervene` herabstufen und damit sagen, dass sie fragen statt handeln sollen. Was **nicht**
  geht, ist die Warnung stehenzulassen — eine Warnung, die man täglich sieht und nie
  beantwortet, ist nach zwei Wochen unsichtbar, und dann trägt sie die nächste mit weg.
- **Notiert:** 2026-08-07

### Statuszahlen aus dem Repo erzeugen statt eintippen
- **Defizit:** keins
- **Frühestens:** beim nächsten Release-Durchgang
- **Warum nicht jetzt:** Die Status-Tabelle beider READMEs nannte 854 Tests und 18 Regeln, davon
  16 aktiv und 8 ungeeicht. Vier von fünf Zahlen waren falsch — in einer README, die damit wirbt,
  dass ihre Zusagen nachprüfbar sind. Die Zahlen stehen jetzt nicht mehr da; stattdessen der
  Befehl, der sie erzeugt. Ein kleines Skript im Release-Ablauf (`dart test` je Paket zählen,
  `validate_rules.dart` auswerten, Tabelle schreiben oder bei Abweichung mit Exit 1 abbrechen)
  wäre die dauerhafte Lösung. Es ist aber genau die Art Nebenbaustelle, die vor einem Release
  attraktiv wirkt (D3) — deshalb erst, wenn ein Release ansteht.
- **Notiert:** 2026-08-06

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
  bräuchte entweder ein lokales Modell (Größe, Akku) oder einen fremden Dienst. Hier stand als
  Begründung, `INTERNET` sei nicht deklariert (ADR-0002) — das gilt seit ADR-0005 nicht mehr.
  Die Berechtigung ist da, der Grund bleibt: AXIOM ruft nichts von sich aus auf, und ein
  Transkriptionsdienst wäre der erste ausgehende Aufruf des Projekts.
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
| Statusfarben als Noten (grün erledigt, rot kritisch, gelb in Arbeit) — abgelehnt ist die *Bedeutung*, nicht das helle Aussehen: Das gibt es seit dem Farbschema **Werkbank**, und `caution` ist auch dort Kupfer und nicht Rot | Mondays Farben sind **Noten**: grün gut, rot schlecht. R7 sagt, Zustandswerte sind Messwerte und keine Noten — eine rote Aufgabe wäre ein Vorwurf, den man beim Draufsehen mitliest. Übernommen wird die Idee, nicht die Umsetzung: Eine Farbrampe für **Dringlichkeit**, abgeleitet aus dem Abstand zu `decayAt`, ist eine Messung. Überfällig ist eine Tatsache, kein Urteil |
| Sortier- und Filterbaukasten, speicherbare Ansichten | Eine Ansicht zu bauen ist befriedigender als sie zu benutzen (D3). Es bleibt bei drei festen Filtern — Suche, Reichweite, überfällig — und einer Reihenfolge, die nicht verstellbar ist: derselben, nach der das System auswählt. Zwei Reihenfolgen wären zwei Wahrheiten |
| Pomodoro als starres Ritual (feste 25/5, Pausenzwang, Pomodoro-Zähler) | Der nützliche Teil — ein sichtbares, begrenztes Zeitfenster — ist M4. Der starre Teil wäre eine Verschlechterung: Ein festes Intervall misst nichts, unterbricht produktiven Hyperfokus (G3) und der Pausenhaushalt ist Meta-Work (D3). Der Zähler wäre ein Streak (D10). Stattdessen: `plannedFocusFor(capacity)` |
| Multi-User, Rollen, Rechte | Kein Anwendungsfall |
| UI-Redesign vor S3 | Die klassische Ausweichbaustelle |
| Die Aufgabenliste als eigener Navigationsreiter | Sie ist das am häufigsten verlinkte Ziel der App und damit der naheliegendste Kandidat für den zweiten Reiter. Genau deshalb nicht: Eine Liste, die von überall einen Tipp entfernt ist, ist eine ständige Einladung, **auszuwählen statt anzufangen** — und die Auswahl aus einer Liste ist die Entscheidung, die G1 dem Nutzer abnehmen soll. Der Bestand liegt einen Tipp hinter der Reichweitenkante auf „Jetzt", mit Stand in der Zeile („3 startbar · 2 heute außerhalb der Reichweite"), und dort bleibt er. Geprüft am 2026-08-06 beim Umbau der Informationsarchitektur |
| Ein vierter Reiter für „Werkzeuge" (Fokus, Reiz, Bremse) | Drei Ziele in der Navigation, nicht sechs. Jeder Reiter ist eine Entscheidung **vor** dem Tun (G1). Die drei stehen als Zeilen in der Mulde auf „Jetzt", mit ihrem Stand daneben — sichtbar, aber nicht auf Augenhöhe mit der einen Handlung |

---

## Prüffrage bei jedem neuen Eintrag

> **Reduziert das die Last — oder erzeugt es nur ein interessanteres System?**

Wenn die Antwort nicht sofort klar ist, ist es das Zweite.
