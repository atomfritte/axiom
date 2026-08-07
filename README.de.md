<img src="assets/brand/axiom-wordmark.svg" alt="AXIOM" width="320">

*[English](README.md) · **Deutsch***

Deterministisches, lokal laufendes Regelwerk zur Selbstregulation.
Ein Exocortex für ein hochkompensiertes ADHS-Profil.

**Privat. Ein Nutzer. Ein Gerät. Kein Produkt.**

---

> ⚠️ **Kein Medizinprodukt.** AXIOM ist keine Diagnostik, keine Therapie und kein Ersatz für
> ärztliche oder psychotherapeutische Behandlung. Es misst selbst berichtete und gerätegemessene
> Zustände und wendet **selbst gesetzte** Regeln darauf an — mehr nicht.

---

## Die Idee in drei Sätzen

Ein hochkompensiertes ADHS-Profil scheitert nicht an fehlender Struktur, sondern daran, dass die
Struktur jeden Tag neu im Kopf erzeugt werden muss. AXIOM übernimmt die Erzeugung: Zustand messen,
selbst gesetzte Regeln anwenden, **genau eine** nächste Handlung ausgeben — mit Begründung und
Regel-ID.

Erfolgsmaß ist nicht "mehr erledigt", sondern **gleiche Leistung bei geringerer kognitiver Last**.

## Was der Hinweis in der Praxis bedeutet

Der Banner oben ist kurz, damit er gelesen wird. Hier steht, wozu er sich tatsächlich verpflichtet
— damit man es prüfen kann, statt es glauben zu müssen:

**Es ist eine Aufgabenliste.** Mit Regeln, gebaut um die Funktionsweise eines neurodivergenten
Gehirns — aber eine Aufgabenliste. Sie diagnostiziert nicht, screent nicht, behandelt nicht,
überwacht nicht.

**Nichts Klinisches.** Keine Schwellenwerte aus einem Handbuch, kein Auswertungsscore, keine
Behauptung, die Nutzung verbessere einen Zustand. `capacity` und `load_index` sind Arithmetik über
Zahlen, die man selbst eingetippt hat. Sie beschreiben einen Zustand innerhalb dieser App und
bedeuten außerhalb nichts.

**Es rät nie zur Medikation.** Das Med-Modul schreibt, wenn eingeschaltet, nur auf, was man ihm
sagt. Es schlägt keine Dosis, keine Einnahmezeit, keine Änderung vor — kein einziges Mal, unter
keinen Umständen. Das ist im Code erzwungen und im Regelwerk des Projekts selbst, nicht der guten
Absicht überlassen.

**Es weiß, wann es sich zurückhält.** Die einzige Meinung, die AXIOM zur eigenen Gesundheit hat,
ist ein sichtbarer Hinweis nach vierzehn Tagen auf der höchsten Laststufe: dass ein Gespräch mit
einem Menschen mehr bringen könnte als eine weitere Regel.

## Was AXIOM anders macht

| Klassische App | AXIOM |
|---|---|
| Fragt *Was willst du tun?* | Fragt *In welchem Zustand bist du?* |
| Modelliert `priority` | Modelliert `activation_energy` gegen verfügbare Kapazität |
| Zeigt eine Liste | Zeigt **eine** Handlung + `rule_id` + Begründung |
| Belohnt Nutzung | **Deckelt** Nutzung (Meta-Guard) |

## Die vier Gesetze

Jeder Zielkonflikt wird zugunsten dieser Gesetze aufgelöst — auch gegen eine ausdrückliche
Feature-Bitte.

| | Gesetz | Operativ |
|---|---|---|
| **G1** | **Auslagern statt anfordern** | Kein Screen, der Nachdenken erzwingt. Erfassung < 3 s, Check-in < 15 s, Tagesreview < 2 min. |
| **G2** | **Erklärbar statt intelligent** | Jede Ausgabe nennt `rule_id` und Begründung. Keine KI in der Entscheidungsschleife. |
| **G3** | **Kanalisieren statt unterdrücken** | Reizbedarf wird budgetiert, nie moralisiert. Keine Schuld-Sprache, keine Verbote — nur Latenz, Sichtbarkeit, Alternativen. |
| **G4** | **Selbstbegrenzung** | AXIOM deckelt seine eigene Nutzungszeit und rationiert seine eigene Konfiguration. |

G4 ist das wichtigste Gesetz hier. Das Hauptrisiko dieses Projekts ist nicht technisches
Scheitern, sondern dass das Bauen des Systems zur Prokrastination wird. Deshalb wurde der
Meta-Guard zuerst gebaut, nicht zuletzt.

## Was AXIOM tut

Was folgt, ist danach gegliedert, worauf ein Nutzer trifft, nicht nach Modulnummern — die stehen
in [00-KONZEPT](docs/00-KONZEPT.md). Zu jedem Punkt gibt es in der App selbst unter *Hilfe* eine
längere, bebilderte Fassung, als reines Markdown in
[`packages/axiom_app/assets/help/de/`](packages/axiom_app/assets/help/de/) — je Abschnitt unten
verlinkt.

### Erfassen

Zwischen Einfall und Notiz liegen wenige Sekunden; was in dieser Zeit nicht festgehalten ist, ist
weg. Deshalb gibt es sieben Wege hinein statt einem, keiner davon Pflicht: eine dauerhafte
Benachrichtigung, in die man ohne Entsperren tippen kann, eine Schnelleinstellungs-Kachel, ein
Homescreen-Widget, langes Tippen auf das App-Symbol, `ACTION_SEND` aus jeder anderen App, das
Air-Command-Menü des S Pen, und das Mikrofon im Eingabefeld. Erfassen fragt nach nichts außer dem
Text — keine Kategorie, kein Projekt, keine Priorität, kein Datum. Sortiert wird später, bewusst,
nicht im Impuls. Details: [Erfassen](packages/axiom_app/assets/help/de/03-erfassen.md).

### Eine Handlung, nie eine Liste

Die Hauptansicht zeigt genau eine Sache, nie mehrere zur Auswahl — Auswählen ist selbst die
exekutive Funktion, die bei diesem Profil knapp ist, und eine Liste senkt diese Last nicht, sie
verlagert sie nur. Was gewinnt, in fester, nachlesbarer Reihenfolge: eine gerade feuernde Regel
(ein Termin in zehn Minuten schlägt jede Vertiefung) · eine bereits angefangene Aufgabe · die
nächste startbare Aufgabe, nach Folgen, Fristdruck und Startenergie · ein Zerlegen-Vorschlag, wenn
nichts in Reichweite ist, aber etwas wartet · nichts, wenn gerade nichts nötig ist. Drei Antworten
stehen neben der Regel, die den Vorschlag erzeugt hat — Verstanden, Später, Passt nicht — und
keine davon erzeugt Schuld, einen Streak oder eine Zählung verpasster Hinweise. „Passt nicht" ist
das, woraus das Wochen-Review später einen Streichvorschlag für die dahinterstehende Regel macht.
Jede Ausgabe trägt ihre `rule_id`; jede Regel ist eine lesbare YAML-Datei unter Versionskontrolle;
`evaluate(state, ruleset) → decision` ist eine reine Funktion — gleiche Eingabe, immer dieselbe
Ausgabe. Details: [Eine Handlung](packages/axiom_app/assets/help/de/04-eine-handlung.md).

### Zustand: Kapazität, Last, Regulation

Sechs Messwerte, jeder aufklappbar bis zu seinem Rechenweg: Kapazität, Kompensationslast,
Reizbedarf, Fokuslast heute, Regulationsreserve, Schlafschuld. Die Kapazität entscheidet am
meisten, sie bestimmt, was überhaupt gezeigt wird, und setzt sich zusammen aus Schlafschuld
(30 %), Kompensationslast (25 %), Fokuslast (20 %), Regulationsreserve (15 %) und dem
Tagesverlauf (10 %). Die Kompensationslast trägt vier Stufen mit echten Folgen im System: bei L1
sind Fokusblöcke auf 75 Minuten gedeckelt, bei L2 auf 50 und neue Verpflichtungen brauchen eine
Bestätigung, bei L3 — dem Erhaltungsmodus — ist alles Optionale ausgeblendet und Blöcke sind auf
30 Minuten gedeckelt, für 72 Stunden. An jedem Wert steht eine Konfidenz; ist sie zu niedrig,
schweigen Regeln lieber, statt zu raten. Die Zahlen kommen aus drei Quellen und keiner weiteren:
Check-ins, Schlafeinträgen und — falls freigegeben — Schlaffenstern und Schritten aus Health
Connect (unten). Details: [Zustand](packages/axiom_app/assets/help/de/05-zustand.md).

### Aufgaben: Startenergie, Zerlegen, Ort, Frist, Blocker

Ein `priority`-Feld gibt es bewusst nicht. Eine Aufgabe trägt Startenergie (1–10 — wie schwer der
Kaltstart fällt, nicht wie lang die Arbeit dauert), Folgen (was das Liegenlassen kostet), eine
optionale Frist und einen optionalen Ort. Sichtbar ist, was unter der heutigen Kapazität liegt;
die Reihenfolge unter den sichtbaren Aufgaben ergibt sich aus Folgen mal Fristdruck geteilt durch
Startenergie. Eine Aufgabe kann außerdem eine andere blockieren — genau eine Beziehungsart, „A
blockiert B", nichts Reicheres — und eine blockierte Aufgabe wartet einfach, berechnet aus dieser
Beziehung statt als eigener gespeicherter Zustand, damit ein erledigter Blocker keine veraltete
Markierung hinterlassen kann. Eine Aufgabe, die wichtig, dringend und trotzdem außer Reichweite
ist, bekommt keine Mahnung, sondern einen Zerlegen-Vorschlag, und die Frage lautet bewusst nicht
„in welche Teile zerfällt das", sondern „was ist die allererste, in zwei Minuten erledigte
Handlung" — AXIOM schlägt keine eigenen Teilschritte vor, nur die Frage, einen Formenkatalog und
eine Prüfung, ob der Schritt wirklich unter der Zielmarke liegt. Für alles mit einer Frist wird
ein Anlauf berechnet — Startenergie × 15 Minuten plus die geschätzte Arbeit — und angezeigt, sobald
er nicht mehr vor der Frist passt. Details: [Aufgaben](packages/axiom_app/assets/help/de/06-aufgaben.md).

### Zeitanker und Rückwärtsverkettung

Ein Termin kostet nicht seine eigene Länge, sondern Fahrzeit plus Fertigmachen plus Puffer plus
die Zeit, sich aus dem Laufenden zu lösen — der Schritt, den man im Kopf immer vergisst. Aus
diesen vier Zahlen (voreingestellt 20 / 15 / 10 / 10 Minuten) rechnet AXIOM rückwärts vom Termin
bis zu dem Moment, in dem die laufende Tätigkeit aufhören muss, setzt auf jeden Schritt einen
exakten Alarm und zeigt den nächsten fälligen ganz oben auf der Hauptansicht, hervorgehoben,
sobald er unter zwanzig Minuten liegt. Es ist kein Kalender und liest keinen Kalender aus — nur
den Vorlauf eines Termins, der schon in einem steht. Details:
[Zeitanker](packages/axiom_app/assets/help/de/07-zeitanker.md).

### Fokus, Reiz-Budget, die Bremse

Ein Fokusblock läuft 15, 25, 50, 75 oder 90 Minuten — bei steigender Kompensationslast stehen
weniger Stufen zur Wahl —, und der Governor schützt ihn, unterbricht nur mit einem Grund, den er
nennen kann: GESCHÜTZT, HINWEIS, UNTERBRECHUNG, JETZT BEENDEN, wobei ein Termin den Block immer
schlägt. Das Beenden fragt nach einem Satz, wo man stehengeblieben ist — diese Notiz ist es, die
den Wiedereinstieg billig macht, nicht der Timer. Reizbedarf ist als Budget modelliert, nicht als
Fehler: Kanäle werden selbst angelegt, mit Intensität und typischer Dauer, konzentrierte Arbeit
verdient Budget im Verhältnis 1:3 (neunzig Minuten Pflicht schalten dreißig frei), und ein
ungeplanter Slot wird gezählt, nicht bewertet. Die Bremse zielt auf Handlungen, die man im Moment
will und am nächsten Tag oft nicht mehr: eine selbst geschriebene Checkliste plus eine Wartezeit
(5 bis 60 Minuten, 24 Stunden, oder bis 09:00) stehen zwischen Impuls und Handlung — „Lasse ich"
geht sofort, „Mache ich" erst nach Ablauf der Wartezeit. Details:
[Fokus, Reiz und die Bremse](packages/axiom_app/assets/help/de/08-fokus.md).

### Rückblick und Eichung

Vier Rückblicke, jeder mit einem harten Zeitdeckel, der sich von selbst schließt: Tag (2 min),
Woche (15 min), Monat (30 min), Quartal (60 min). Der wöchentliche macht aus den
„Passt nicht"-Antworten einer Regel ein Verdikt — STREICHEN für eine Regel, die nur abgelehnt
wird, ZU ENG für eine, die nie feuert, KONFLIKT für zwei, die sich gegenseitig verdrängen. Die
Formelgewichte starten als dokumentierte Schätzungen; sobald vierzehn Tage, zwanzig Check-ins und
sieben Schlafeinträge vorliegen, schlägt `tools/bin/calibrate.dart` echte Werte aus den Daten vor
— es schreibt selbst nichts — und im Wochen-Review wird ein Vorschlag geprüft, bevor er live geht.
Details: [Rückblick und Eichung](packages/axiom_app/assets/help/de/10-rueckblick.md).

### Der Meta-Work-Deckel

Das ist der Teil, den der Rest des Projekts eigentlich schützt, und der Grund, warum
`docs/07-RISIKEN.md` ihn R1 nennt: Ein Systemizing-Kopf kann beliebig mehr Zeit ins Konfigurieren
eines Systems stecken, als das System je einspart, weil das Justieren einer Regel zuverlässig
stimulierender ist als die Aufgabe, auf die die Regel zeigt. Unkontrolliert wird das Bauen von
AXIOM zu genau der Prokrastination, die es lösen sollte.

Der Wächter dagegen wurde in Stufe 1 gebaut, bevor es ein Regelwerk gab, an dem sich überhaupt
etwas justieren ließ: AXIOM begrenzt die eigene Nutzung auf zwölf Minuten am Tag. Erfassen zählt
nicht mit; Konfiguration, Regelbearbeitung und Herumschauen schon. Bei zwölf Minuten sperrt sich
der Regeleditor selbst — für den Rest des Tages, nicht bis zu einem künftigen Review-Slot, denn
ein Deckel, den man vorhersagen kann, ist einer, um den herum man plant. Das Wochen-Review macht
den Tausch sichtbar statt behauptet: Minuten in AXIOM gegen eine Schätzung eingesparter Minuten
(drei je Erfassung, zehn je Zerlegung, vier je erreichtem Ankerschritt) — eine Zahl, an der sich
die Prämisse prüfen lässt, nicht eine, der man glauben muss. Kippt dieses Verhältnis, ist das ein
Systemfehler, kein persönlicher. Eine Sache funktioniert unabhängig vom Budget immer: eine falsch
feuernde Regel abzuschalten. Sie bis morgen laufen zu lassen wäre der schlimmere Fehler.

## Health Connect

Zwei Größen, nur lesend, sonst nichts: Schlaffenster und Schritte pro Tag. Kein Puls, kein
Gewicht, kein Standort — und nichts geht je zurück an Health Connect; AXIOM liest nur.

**Wozu es das gibt.** Die Schlafschuld ist das stärkste Einzelgewicht in der Kapazitätsformel —
30 %, siehe [Zustand](#zustand-kapazität-last-regulation) oben — und selbst berichteter Schlaf ist
genau der Kanal, der unter Last zuerst ausfällt: An den Tagen, an denen eine schlechte Nacht für
eine Empfehlung am meisten zählen würde, fehlt am ehesten der eingetippte Eintrag dazu. Ihn aus
dem System zu lesen schließt genau diese Lücke. Es öffnet keine neue: An der Ablesung selbst ist
nichts wertend, und sie landet als dieselbe Art Ereignis, die ein handgetippter Schlafeintrag auch
wäre.

**Wie es in die Formel eingeht.** Ein importiertes Schlaffenster wird zu einem
`sleep_window`-Ereignis mit einer Schlafschuld-Schätzung gegen ein Sieben-Stunden-Soll,
Tagesschritte werden zu einem `health_sample`-Ereignis — dieselbe Form, die ein manueller Eintrag
auch hätte. Der `StateDeriver` weiß nicht und fragt nicht, woher ein Messwert stammt; Health
Connect ändert nur, wie viele Messwerte es gibt und wie aktuell sie sind.

**Freiwillig, und nicht tragend.** Ohne Health Connect fehlt nichts Grundsätzliches, nur
Genauigkeit. Das Onboarding bietet es einmal an, es lässt sich jederzeit unter
*System → Datenquellen* an- und abschalten, und der Linux-Desktop-Build hat gar kein Health
Connect — er rechnet allein aus den Check-ins, dieselben Regeln, eine Quelle weniger.

**Nur lesend und idempotent.** Die angefragten Berechtigungen sind reine Leserechte. Jeder
importierte Datensatz trägt die eigene Kennung von Health Connect, und jeder Import prüft vor dem
Schreiben, was schon vorliegt — denselben Zeitraum zweimal zu importieren ändert nichts, was
zählt, weil Ereignisse in AXIOM nur angehängt werden und ein Duplikat sich nicht rückgängig
machen ließe. Nichts davon verlässt das Gerät: Health Connect ist ein lokaler Systemdienst, und
das Lesen daraus berührt die unten besprochene `INTERNET`-Berechtigung nicht.

Details: [Deine Daten](packages/axiom_app/assets/help/de/12-daten.md).

## Expertenmodus

Regeln schreiben, die Aufgabenliste mit allen Feldern überblicken, den rohen Ereignisstrom lesen —
dafür braucht es Fläche, die ein Telefon nicht hat. Der Expertenmodus ist ein kleiner
HTTP-Server, den das Telefon für einen eigenen Browser-Tab im selben Netz bereitstellt: **aus,
bis er eingeschaltet wird**, und auf der echten, laufenden Datenbank des Telefons, nicht auf einer
Kopie.

**Ein vollwertiger Client, kein Nur-Lese-Spiegel.** Der Browser zeigt dieselbe eine Handlung und
dieselbe Rangfolge, die auch das Telefon zeigen würde — eine feuernde Regel, dann das Laufende,
dann die nächste startbare Aufgabe — dazu, was das Telefon bewusst nicht zeigt: den vollständigen
Aufgabenbaum mit Blockern und Zerlegung, eine Board-Ansicht des Bestands, das Regelwerk als
bearbeitbares YAML, das Wochen-Review, den rohen Ereignisstrom und die Hilfeseiten. G1 gilt
unverändert: Die Reihenfolge ist identisch, und die vollständige Liste steht daneben als das, was
sie ist — Bestand, keine angebotene Auswahl.

**Hineinkommen.** Der Start des Servers (*System → Expertenmodus → Server starten*) zeigt eine
Adresse — meist `axiom.local`, per Multicast-DNS aufgelöst, damit der Name eine vom Router neu
vergebene IP-Adresse übersteht, dazu eine rohe IP als Ausweichweg —, einen Fingerabdruck, und ab
dann ist ein **Zahlenabgleich** der erste Weg der Anmeldung: Wer die Adresse öffnet, sieht im
Browser eine zweistellige Zahl, dieselbe Zahl erscheint auf dem Telefon neben „Stimmt überein" und
„Stimmt nicht". Die Sicherheit liegt im Vergleich, nicht im Antippen — fragt jemand anders im
selben Moment an, steht dessen Zahl auf dem Telefon und nicht auf dem Bildschirm, den man selbst
vor sich hat, sodass nur zu bestätigen, was wirklich übereinstimmt, niemand sonst hereinlässt.
Eine sechsstellige PIN, bei jedem Start neu erzeugt und nur in der App sichtbar, ist der zweite
Weg, für einen Browser, der die laufende Zahl nicht anzeigen kann. In beiden Fällen ist die
Sitzung ein `HttpOnly`-Cookie; weder PIN noch Vergleichszahl stehen je in einer URL.

**Der zweite Vergleich.** Der Browser wird einmal warnen, weil das Zertifikat selbst signiert ist
und keine fremde Stelle dafür bürgt — der Punkt ist nicht, die Warnung wegzuklicken, sondern zu
vergleichen: derselbe SHA-256-Fingerabdruck steht in der App und unter „Zertifikat anzeigen" im
Browser. Stimmen sie überein, geht die Verbindung zu diesem Telefon und zu nichts dazwischen. Das
Zertifikat wird einmal auf dem Gerät erzeugt und über Neustarts hinweg wiederverwendet, sodass die
Warnung eine einmalige Prüfung bleibt statt ein antrainierter Reflex zum Wegklicken.

**Starten und Stoppen.** Kein Autostart beim Hochfahren, nie. Optional — voreingestellt aus —
kann der Server mitstarten, sobald die App selbst geöffnet wird, für den Fall, dass das Telefon
am Arbeitsplatz in der Tasche liegt und ein Server, den niemand einschaltet, nicht benutzt wird;
alle übrigen Sicherungen unten gelten in diesem Modus unverändert weiter. Er stoppt sich selbst
nach fünf falschen PINs oder abgelehnten Anmeldungen, nach dreißig Minuten ohne Anfrage, über
einen Knopf in der App oder auf seiner eigenen dauerhaften Benachrichtigung — die die ganze
Laufzeit über steht und die Adresse nennt, damit sein Zustand nie zu erraten ist — und immer, wenn
die App geschlossen wird.

**Der Name im Netz.** Damit `axiom.local` aufgeht, beantwortet das Telefon Namensanfragen im
lokalen Netz per Multicast-DNS — die einzige Stelle, an der AXIOM von sich aus ein Paket
verschickt. Dieses Paket trägt nur Name und IP-Adresse dieses Geräts, geht nur an die link-lokale
Multicast-Gruppe, die kein Router über das eigene Netzsegment hinausleitet, existiert nur, solange
der Server läuft, und wird beim Beenden mit einem Abschiedspaket zurückgezogen.

**Der ehrliche Preis.** Der Expertenmodus ist der Grund, warum AXIOM die `INTERNET`-Berechtigung
überhaupt deklariert. Die frühere, strukturelle Zusage — dass das Betriebssystem selbst eine
ausgehende Verbindung unmöglich macht — gilt damit nicht mehr. An ihre Stelle tritt eine engere,
geprüfte statt angenommene: **AXIOM lauscht, ruft aber nie von sich aus auf.** Es gibt keinen
HTTP-Client irgendwo in der App und keinen ausgehenden Aufruf im eigenen Code;
`language_test.dart` verbietet `package:http`, `HttpClient`, `Socket.connect`,
`WebSocket.connect` und `dart:html` im gesamten App-Code und hält fest, dass genau eine Datei
überhaupt einen Socket öffnet — der Server, und der mDNS-Responder darüber, beide nur zum Lauschen
oder Ankündigen.

Hier stand zusätzlich „kein SDK, das eine aufbauen könnte". Das war zu viel versprochen:
`basic_utils`, das dem Expertenmodus sein Zertifikat erzeugt, bringt `package:http` als transitive
Abhängigkeit mit, und sein Sammelmodul exportiert `HttpUtils` und `DnsUtils` (DNS über HTTPS gegen
Google und Cloudflare) in jeden Namensraum, der es importiert. Aufgerufen wird davon nichts — aber
„könnte nicht" war eine stärkere Behauptung, als irgendein Test deckte. Seither verbietet
`language_test.dart` beide Einstiegspunkte namentlich und lässt einen Netzwerk-Client nicht mehr
als *direkte* Abhängigkeit zu. Die Zusage lautet damit, was sie sagt: nicht unmöglich, sondern
geprüft. Die vollständige Begründung, einschließlich dessen, was diese Berechtigung wert
war und was sich ändern müsste, damit dieses Urteil neu gefällt wird, steht in
[ADR-0005](docs/adr/ADR-0005-expertenmodus.md).

## Dokumentation

| Dokument | Inhalt |
|---|---|
| [00-KONZEPT](docs/00-KONZEPT.md) | Was AXIOM ist, die vier Systemgesetze, alle 13 Module |
| [01-PROFIL-DEFIZITE](docs/01-PROFIL-DEFIZITE.md) | Defizitanalyse D1–D12 — die Grundlage von allem |
| [02-ARCHITEKTUR](docs/02-ARCHITEKTUR.md) | Schichten, Ports, Auswertungszyklus |
| [03-DATENMODELL](docs/03-DATENMODELL.md) | Events, StateVector, Task, Formeln |
| [04-REGELWERK](docs/04-REGELWERK.md) | Regel-DSL, Semantik, Konfliktauflösung |
| [05-ROADMAP](docs/05-ROADMAP.md) | Stufen S1–S4 mit Abbruchkriterien |
| [06-METRIKEN](docs/06-METRIKEN.md) | Erfolgsmessung, Baseline-Protokoll |
| [07-RISIKEN](docs/07-RISIKEN.md) | Was schiefgeht — R1 ist das entscheidende |
| [08-GERAET-S25U](docs/08-GERAET-S25U.md) | S-Pen, Health Connect, Android-Fallstricke |
| [ADR](docs/adr/) | Architekturentscheidungen mit Begründung |
| [BACKLOG](docs/BACKLOG.md) | Ideen, die bewusst *nicht* jetzt gebaut werden |

Die Tabelle oben ist die *Konzept*-Dokumentation — warum AXIOM so gebaut ist, wie es gebaut ist.
Die *Nutzer*-Dokumentation — was jeder Bildschirm tut, mit Bildern — liegt in der App selbst unter
*Hilfe* und als reines Markdown in
[`packages/axiom_app/assets/help/de/`](packages/axiom_app/assets/help/de/00-index.md); der
Abschnitt „Was AXIOM tut" oben verlinkt kapitelweise dorthin.

Für Claude Code: [CLAUDE.md](CLAUDE.md)

## Stack

Flutter 3.44 / Dart 3.12 · SQLite über `sqlite3` (SQLite3MultipleCiphers) · YAML-Regelwerk unter Git
Ziele: Android (Galaxy S25 Ultra, primär) und Linux Desktop (Companion)

## Struktur

```
packages/axiom_core   pure Dart — Domain + State Engine + Rule Engine   ← das Herz
packages/axiom_data   SQLite, YAML-Loader, Health Connect, Export
packages/axiom_app    Flutter UI, Notifications, Widgets
rules/core            mitgelieferte Regeln (versioniert)
rules/personal        persönliche Regeln (git-ignoriert)
tools/                Validator, Layering-Check, Szenario-Runner
```

## Entwicklung

```bash
# Prüfen — alles muss grün sein
dart run tools/bin/validate_rules.dart rules
dart run tools/bin/check_layering.dart .
(cd packages/axiom_core && dart analyze && dart test)
(cd packages/axiom_data && dart analyze && dart test)
(cd packages/axiom_app  && flutter analyze && flutter test)

# Regelwerk in die App-Assets spiegeln — vor jedem App-Build
dart run tools/bin/sync_rules.dart

# Starten
(cd packages/axiom_app && flutter run -d linux)
(cd packages/axiom_app && flutter run -d <geraet>)     # adb devices
```

### Release signieren

`flutter build apk --release` läuft auch ohne Einrichtung — dann aber mit
dem Android-Debug-Schlüssel, und das steht in der Ausgabe. Den Schlüssel hat
jeder Rechner mit Flutter; was damit signiert ist, kann jeder überschreiben.

Für einen echten Schlüssel `packages/axiom_app/android/key.properties`
anlegen. Die Datei ist git-ignoriert, ebenso `*.p12` und `*.jks`:

```properties
storeFile=axiom-release.p12
storePassword=…
keyAlias=axiom
keyPassword=…
```

```bash
keytool -genkeypair -v -keystore axiom-release.p12 -storetype PKCS12 \
  -keyalg RSA -keysize 4096 -validity 10950 -alias axiom
```

Den Keystore aufheben. Ohne ihn lässt sich kein Build mehr über eine
vorhandene Installation legen — dann bleibt nur deinstallieren und neu
einspielen, und das löscht die Datenbank. Vorher exportieren
(*System → Daten*).

## Status

**S1 bis S4 stehen.** Android-APK und Linux-Desktop bauen und starten.

| | |
|---|---|
| Tests | grün in allen vier Paketen — `dart test` in Core, Daten und Werkzeugen, `flutter test` in App |
| Analyzer | keine Meldungen in allen Paketen |
| Regelwerk | 18 Regeln gültig, 15 aktiv — davon 5 **ungeeicht** (`dart run tools/bin/validate_rules.dart rules`) |
| Release-APK | gebaut, **mit der `INTERNET`-Berechtigung** — nur für den Expertenmodus deklariert (ADR-0005), sonst kein Netzwerkcode in der App |

In der ersten Zeile stand eine genaue Testzahl. Keine dieser Zahlen stimmte noch — in einer
README, deren ganzer Anspruch ist, dass ihre Zusagen nachprüfbar sind. Eine Zahl, die niemand
nachmisst, altert schlecht; deshalb steht dort jetzt der Befehl, der sie erzeugt.

**Stufe 1** — Erfassung (< 3 s), Check-in, Kapazitätslinie, Zustandsanzeige
mit Herleitung, Regelinspektor, Meta-Guard, Onboarding, Widget, Quick Tile,
exakte Alarme, App-Shortcuts, Share-Ziel.

**Stufe 2** — Zeitanker mit Rückwärtsverkettung (M3), Atomizer (M2),
Körpersignale (M7), Abendgrenze und Schlaferfassung (M8), Review mit
erzwungenem Zeitdeckel (M11).

**Stufe 3** — Focus Governor (M4), Reiz-Haushalt mit Slot-als-Währung (M5),
Impuls-Bremse mit selbst geschriebener Checkliste (M6), Load Monitor mit
realen Konsequenzen bis zum Erhaltungsmodus (M9).

**Stufe 4** — Signal-Log mit getrenntem Erfassen und Nachbetrachten (M10),
Wirkfenster-Protokoll (M13, opt-in), verschlüsselter Datenabgleich per Datei
statt Server.

**Systemanbindung** — Live Update des laufenden Fokus-Slots in
Statusleisten-Pille, Sperrbildschirm und Samsungs Now Bar (Android 16,
`ProgressStyle` + `requestPromotedOngoing`); Health Connect für Schlaffenster
und Tagesschritte, idempotent importiert; Direct Share als festes Ziel im
Teilen-Blatt.

### Der Regeleditor

Regeln lassen sich am Gerät schreiben (*System → Regelwerk*). Kein Textfeld: Der Editor kennt das
Vokabular der Engine, bietet deshalb nur an, was sie auflösen kann — und wertet jede Bedingung
sofort gegen den **aktuellen** Zustand aus, während man tippt. Jede Zeile zeigt, welchen Wert die
Größe gerade hat und ob dieser Teil zutrifft.

Zwei Sicherungen sind im Code erzwungen, nicht nur empfohlen:

- Jede gespeicherte Regel läuft **sieben Tage** als `log_only`, egal welche Stufe gewählt wurde.
  Eine Regel, die am Tag ihrer Entstehung live geht, wird an dem Tag beurteilt, an dem man von ihr
  überzeugt war.
- `rationale` und `cooldown` sind Pflicht. Ohne Begründung ist eine Ausgabe nicht auditierbar
  (G2); ohne Cooldown entsteht eine Benachrichtigungsflut — die häufigste Art, wie solche Apps
  sterben.

Änderungen liegen als Überlagerung in der Datenbank, nie in `rules/core/`. `ruleToYaml` gibt eine
Regel exakt in der Form zurück, die `rules/` verwendet, sodass sich alles am Telefon Geschriebene
zurück in die Versionskontrolle kopieren lässt. Ein Rundlauf-Test hält das ehrlich.

### Expertenmodus, kurz

Ausführlich oben unter [Expertenmodus](#expertenmodus) — ein lokaler HTTP-Server, den das Telefon
nur auf Kommando startet, und der einem Browser im selben Netz einen vollwertigen Client auf den
echten Daten des Telefons gibt. Der Datenabgleich selbst braucht weiterhin keinen Server:
Ereignisse sind unveränderlich, ihre Vereinigung ist deshalb konfliktfrei, und ein wiederholter
Import ist idempotent. Zwei Geräte gleichen sich über eine verschlüsselte Datei ab.

### Zwei Sprachen

Deutsch ist die Quelle, Englisch die Übersetzung — umschaltbar unter
*System → Anzeige*. Besonderheit: Der **deutsche Satz ist der Schlüssel**.

```dart
Text(context.t('Nichts in Reichweite'))
```

Damit bleibt die Formulierung dort lesbar, wo sie gewählt wurde. Genau darauf
kommt es hier an: „Nichts in Reichweite" ist eine bewusste Entscheidung gegen
„Du hast 14 offene Aufgaben", und diese Entscheidung soll nicht hinter einem
Bezeichner wie `now.emptyTitle` verschwinden.

Vier Ebenen sind abgedeckt:

| Ebene | Wo | Wie |
|---|---|---|
| Oberfläche | `lib/i18n/en.dart` | deutscher Satz → englischer Satz |
| Kern | `Phrase('{0} min über …', [n])` | Quelltext und Werte getrennt, damit Zahlen nicht zurückgerechnet werden müssen |
| Regelwerk | `title_en`, `rationale_en` im YAML | Regeln sind Daten, ihre Übersetzung auch |
| Expertenmodus | `assets/expert/index.html` | dieselbe Regel im Browser: `tr('…')` und ein `data-t`-Attribut für festes Markup. Die Seite folgt der Einstellung **des Telefons**, nicht der des Browsers — sonst liest man denselben Satz auf zwei Bildschirmen verschieden |

`i18n_test.dart` hält drei Dinge fest: **jeder** übersetzbare Text hat eine
englische Fassung, die Platzhalter stimmen auf beiden Seiten überein, und der
Ton hält — keine Schuldsprache, keine Ausrufezeichen. Eine Übersetzung kann
aus einem Messwert unbemerkt ein Urteil machen; das ist der eigentliche Grund
für diesen Test.

### Wege in die App hinein

Zwischen Einfall und Notiz liegen wenige Sekunden. Was in dieser Zeit nicht
festgehalten ist, ist weg (D9) — deshalb gibt es nicht einen Weg, sondern
sieben. In der App stehen sie unter *System → Erfassen*, mit Einrichtung.

| Weg | Reibung | Wie |
|---|---|---|
| **Dauerhafte Benachrichtigung** | minimal | Tippen direkt in der Benachrichtigung, ohne Entsperren (`RemoteInput`) |
| Schnelleinstellung | sehr niedrig | Quick-Settings-Kachel |
| Homescreen-Widget | niedrig | nächste Handlung + Kapazität, Tipp führt ins Eingabefeld |
| App-Shortcut | niedrig | langes Tippen aufs Symbol |
| Teilen aus anderen Apps | niedrig | `ACTION_SEND` |
| S-Pen | niedrig | Air-Command-Verknüpfung; `ACTION_CREATE_NOTE` liegt bereit, One UI gibt die Rolle nicht frei |
| Sprache | niedrig | `actions.intent.CREATE_NOTE` für Assistant, Bixby-Routine |

Grenzen des Systems, ausdrücklich benannt statt umgangen:

- **Lockscreen-Widgets gibt es auf Android nicht** — mit 5.0 entfernt. Der
  verbliebene Weg zu ständiger Sichtbarkeit im gesperrten Zustand ist die
  dauerhafte Benachrichtigung (`VISIBILITY_PUBLIC`).
- **Samsung Notes hat keine öffentliche Schnittstelle.** Screen-off-Memos
  bleiben dort. Der offizielle Stift-Weg ist `ACTION_CREATE_NOTE`.
- **Der S Pen des S25 Ultra hat kein Bluetooth**, deshalb gibt es Air Actions
  darauf nicht — für keine App, nicht nur für AXIOM. Was bleibt: den Stift
  herausziehen und im Air-Command-Menü auf AXIOM tippen, als Verknüpfung
  eingetragen zwei Handgriffe.
- **„Hey Google, Notiz in AXIOM" funktioniert nicht.** Sprachbefehle über den
  Assistenten setzen eine Verteilung über Google Play voraus; bei einer
  selbst installierten App prüft Google die Signatur nicht. Es funktionieren
  stattdessen das Mikrofon im Erfassungsfeld, eine Bixby-Routine, oder ein
  Link auf `axiom://capture?text=…`.

### Eichung

Die Formelgewichte in `rules/core/weights.yaml` sind geschätzt, nicht gemessen.
Fünf aktive Regeln (R-020, R-050, R-051, R-052, R-090) prüfen auf abgeleitete
Werte und können deshalb danebenliegen. Sie laufen trotzdem — eine bewusste
Entscheidung. Der Systeminspektor markiert sie als **UNGEEICHT**.

**Wo du den Stand siehst:** In der App unter *System → Eichung*. Dort stehen
drei Bedingungen mit Fortschritt — und wenn alle erfüllt sind, der komplette
Ablauf mit kopierbaren Befehlen.

| Bedingung | Nötig | Warum |
|---|---|---|
| Tage | 14 | Kürzer erfasst keinen vollen Wochenrhythmus |
| Messpunkte | 20 Check-ins | Darunter ist das circadiane Profil nicht belastbar |
| Nächte | 7 Schlafeinträge | Für die Schlaf-Kapazitäts-Kopplung |

**Zeit allein reicht nicht.** Vierzehn Tage mit fünf Check-ins würden die
Gewichte auf Rauschen eichen — schlechter als eine ehrliche Schätzung. Deshalb
werden alle drei getrennt geprüft und angezeigt.

Sind sie erfüllt, meldet sich die Hauptansicht von selbst. Der Ablauf dann:

```bash
adb exec-out run-as de.atomfritte.axiom cat files/axiom.db > axiom.db
dart run tools/bin/calibrate.dart axiom.db      # schreibt nichts, schlägt vor
# Vorschläge im Wochen-Review prüfen, dann in rules/core/weights.yaml
# eintragen und dort calibration.status auf calibrated setzen:
dart run tools/bin/sync_rules.dart
```

Danach verschwinden die UNGEEICHT-Markierungen.

## Wie es aussieht

<p>
  <img src="packages/axiom_app/test/screenshots/04-jetzt-aufgaben.png" width="180" alt="Jetzt — eine Handlung mit ihrer Regel">
  <img src="packages/axiom_app/test/screenshots/05-zustand.png" width="180" alt="Zustand — sechs Messwerte mit Herleitung">
  <img src="packages/axiom_app/test/screenshots/10-zerlegen.png" width="180" alt="Zerlegen — aus einer Aufgabe einen ersten Schritt">
  <img src="packages/axiom_app/test/screenshots/12-fokus.png" width="180" alt="Fokus — laufender Block">
</p>
<p>
  <img src="packages/axiom_app/test/screenshots/02-onboarding-linie.png" width="180" alt="Onboarding — die Kapazitätslinie erklärt">
  <img src="packages/axiom_app/test/screenshots/06-system.png" width="180" alt="System — der Regelinspektor">
  <img src="packages/axiom_app/test/screenshots/14-bremse.png" width="180" alt="Bremse — Wartezeit mit den eigenen Fragen">
  <img src="packages/axiom_app/test/screenshots/08-jetzt-hell.png" width="180" alt="Derselbe Screen in hell">
</p>

Von links: **eine Handlung** mit der Regel, die sie erzeugt hat · der **Zustand** dahinter, jede
Zahl aufklappbar bis zur Formel · **Zerlegen** von etwas außer Reichweite in einen ersten Schritt ·
ein **laufender Fokusblock**. Darunter: die Kapazitätslinie im Onboarding · der
**Regelinspektor** · die **Impuls-Bremse** mit den eigenen Fragen · dieselbe Hauptansicht in hell.

Das sind keine Werbebilder, sondern die Referenzbilder aus
`packages/axiom_app/test/screenshots/`. Sie entstehen aus den Tests — sie können also nicht vom
Code abweichen, ohne dass ein Test rot wird.

## Die Bildmarke

Eine Skala mit einem gesetzten Schwellenstrich. Links, kräftig: was in
Reichweite ist. Rechts, gedämpft: was heute darüber hinausgeht. Genau das
Kernbild der App — und genau das, was ein Axiom ist: eine Grenze, die man
setzt, nicht ableitet.

Kein Gehirn, keine Glühbirne, kein Häkchen, keine Zielfahne. Das Zeichen
kommt aus der Welt der Messinstrumente, nicht aus der Bildsprache von
Selbstoptimierungs-Apps.

Quellen in `assets/brand/`. Die Android-Symbole werden daraus erzeugt:

```bash
tools/bin/make-icons.sh
```

## Lizenz

[PolyForm Strict 1.0.0](LICENSE.md) — bewusst keine Open-Source-Lizenz.

Der Code darf gelesen und privat, nicht kommerziell ausgeführt werden. Weiterverbreitung ist nicht
erlaubt, ebenso wenig ein eigenes Werk darauf aufzubauen. Urheberrecht und jedes kommerzielle
Recht bleiben beim Autor.

Drittkomponenten behalten ihre eigenen Lizenzen, die diese Nutzung alle erlauben; die Pflichten
daraus, und die eine, die Handeln erforderte, stehen in
[THIRD-PARTY-LICENCES.md](THIRD-PARTY-LICENCES.md).
