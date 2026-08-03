# ADR-0005 — Expertenmodus über einen lokalen HTTP-Server

**Status:** akzeptiert · **Datum:** 2026-08-03
**Ändert:** [ADR-0002](ADR-0002-local-first.md) Punkt 2

## Kontext

Regeln schreiben, eine Aufgabenliste mit allen Feldern überblicken, den Ereignisstrom lesen — das
sind Tätigkeiten, die Fläche brauchen. Auf einem Telefon sind sie möglich, aber unangenehm.

Es gab drei Wege dorthin:

1. **Linux-Desktop-Build** — existiert, braucht keine Berechtigung, hat aber eine **eigene
   Datenbank**. Der Austausch läuft über die verschlüsselte `.axiom`-Datei; wer am Rechner eine
   Regel schreibt, hat sie nicht auf dem Telefon.
2. **Google Drive über SAF** — löst den Dateiaustausch, nicht die Oberfläche.
3. **Lokaler HTTP-Server auf dem Telefon** — der Browser am Rechner arbeitet direkt auf den
   echten Daten des Geräts.

Weg 3 wurde gewählt. Er kostet die Berechtigung `INTERNET`.

## Entscheidung

**1. `INTERNET` wird deklariert.** Damit endet die strukturelle Garantie aus ADR-0002 Punkt 2:
Es ist nicht mehr auf Betriebssystemebene ausgeschlossen, dass Daten das Gerät verlassen.

**2. An ihre Stelle tritt eine engere, prüfbare Zusage:** *AXIOM ruft nichts von sich aus auf.*
Die App hat keinen HTTP-Client, keine ausgehende Verbindung, kein SDK, das eine aufbauen könnte.
Sie **lauscht** auf einem Port, und nur solange sie ausdrücklich eingeschaltet ist.
`language_test.dart` hält das fest: `package:http`, `HttpClient`, `Socket.connect` und
`dart:html` sind im gesamten App-Code verboten. Ein Analytics-SDK bliebe damit ebenso wirkungslos
wie vorher — es käme nicht heraus.

**3. Der Server ist aus, bis er eingeschaltet wird.** Kein Autostart, kein Weiterlaufen nach
einem Neustart. Er hält sich an fünf Regeln:

| | |
|---|---|
| Anmeldung | Sechsstellige PIN, bei jedem Start neu, nur in der App sichtbar |
| Sitzung | `HttpOnly`-Cookie, `SameSite=Strict`; die PIN steht nie in einer URL |
| Fehlversuche | nach fünf falschen PINs stoppt der Server sich selbst |
| Leerlauf | nach 30 Minuten ohne Anfrage stoppt er sich selbst |
| Sichtbarkeit | dauerhafte Benachrichtigung mit Adresse und Stopp-Knopf, solange er läuft |

**4. Kein TLS.** Ein selbst signiertes Zertifikat erzeugt im Browser eine Warnung, die man
wegklickt — und die Gewöhnung daran ist gefährlicher als der Klartext im eigenen WLAN. Die
Konsequenz steht ausdrücklich in der App: **Wer im Netz mitliest, sieht mit.** Der Expertenmodus
gehört ins eigene Netz, nicht ins Hotel-WLAN.

## Begründung

Die Alternative wäre gewesen, den Wunsch abzulehnen und beim Desktop-Build zu bleiben. Dagegen
spricht ein sachlicher Punkt: Der Desktop-Build arbeitet auf einer **anderen Datenbank**. Für
Regelarbeit ist das kein Detail, sondern der Unterschied zwischen „ich ändere die Regel, die
gerade läuft" und „ich ändere eine Kopie und muss sie danach hinüberbringen". Genau dieser
Zwischenschritt ist die Art von Reibung, an der dieses Profil hängenbleibt (D2).

Der Preis ist real und wird hier nicht kleingeredet: Eine Berechtigung, die nicht da ist, kann
nicht missbraucht werden. Eine, die da ist, schon. Was bleibt, ist eine Zusage im Code statt einer
Garantie im System — plus Tests, die sie festhalten.

## Konsequenzen

- ADR-0002 Punkt 2 gilt nicht mehr. Punkt 1 (local-first, kein Account, kein Backend), Punkt 3
  (Event Sourcing) und Punkt 4 (Sync nur E2E-verschlüsselt) bleiben unverändert.
- Der Expertenmodus ist **kein zweiter Client**. Er zeigt, was das Telefon bewusst nicht zeigt:
  Listen, Rohdaten, Felder. Die Entscheidung im Moment — genau eine Handlung (G1) — bleibt dort,
  wo sie hingehört.
- Neue Prüfpflicht vor jedem Release: kein ausgehender Netzwerkcode, Server standardmäßig aus.
- Sollte der Expertenmodus zur Hauptoberfläche werden, ist das ein Signal, dass die
  Telefon-Ansicht etwas Falsches tut — nicht, dass der Server erweitert gehört.
