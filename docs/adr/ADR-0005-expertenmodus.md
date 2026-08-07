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
`language_test.dart` hält das fest: `package:http`, `HttpClient`, `Socket.connect`,
`WebSocket.connect` und `dart:html` sind im gesamten App-Code verboten. Ein Analytics-SDK bliebe
damit ebenso wirkungslos wie vorher — es käme nicht heraus.

**2a. Eine Ausnahme, und nur eine: der Name im lokalen Netz.**

Der Server meldet sich per Multicast DNS als `axiom.local` an. Das ist die einzige Stelle, an der
AXIOM von sich aus ein Paket verschickt, und sie braucht eine Begründung.

*Warum überhaupt.* Ohne Namen steht auf dem Telefon eine IP, die man abtippt — und die der Router
neu vergibt, sobald das Gerät länger weg war. Mit ihr wechselt das Zertifikat, und die
Browser-Warnung kommt erneut. Genau die Wiederholung erzeugt die Gewöhnung, gegen die Punkt 4
argumentiert. Ein Name, der bleibt, ist deshalb keine Bequemlichkeit, sondern die Bedingung dafür,
dass der Fingerabdruck-Vergleich einmal stattfindet und danach nur noch bestätigt wird.

*Warum es die Zusage nicht bricht.* Drei Eigenschaften, alle drei in `language_test.dart` geprüft:

| | |
|---|---|
| Ziel | `224.0.0.251` — link-lokal. Kein Router leitet das weiter; es gibt keinen Empfänger außerhalb des eigenen Netzsegments |
| Inhalt | Name und IP **dieses** Geräts. Keine Nutzdaten, keine Kennung, nichts aus der Datenbank |
| Dauer | nur solange der Expertenmodus läuft. Beim Beenden geht ein Abschied mit TTL 0 hinaus, damit der Name nicht in fremden Zwischenspeichern stehen bleibt |

Ein Test hält fest, dass genau **eine** Datei einen Datagramm-Socket öffnet, dass sie an keine
andere Adresse als die Multicast-Gruppe sendet und dass der Abschied existiert. Wächst diese
Liste, ist das eine Entscheidung und kein Versehen.

**2b. Systemmeldungen im Browser — ja. Web Push — nein.**

Eine feuernde Regel endete im Browser als Feld auf einer Seite. Lag der Reiter hinten, war sie
damit unsichtbar; und die Regeln, die etwas taugen, feuern gerade dann, wenn man nicht hinsieht.
Die Seite darf sich deshalb melden — aber es gibt zwei Bauformen dafür, und nur eine ist mit
Punkt 2 vereinbar.

| | Web Push (`PushManager`) | `new Notification(…)` |
|---|---|---|
| Weg | Der Browser meldet sich bei einem Zustelldienst an — Mozilla oder Google — und bekommt von dort eine Endpunkt-URL. Die Meldung läuft über diesen fremden Server | Der Browser zeigt sie selbst |
| Netz | ausgehende Verbindung zu einem Dritten, dauerhaft | keine |
| Reichweite | auch wenn die Seite zu ist | nur solange die Seite offen ist |
| Zulässig | **nein** | ja |

Web Push ist ausgeschlossen, und zwar unabhängig davon, wie wenig im Paket steht: Schon die
Anmeldung ist eine ausgehende Verbindung, und sie besteht dauerhaft. Dass ein Dritter dabei
mitzählt, wann dieses Gerät Meldungen bekommt, ist bei einer Datenbank mit Gesundheitsdaten
kein akzeptabler Preis für Bequemlichkeit.

Die kürzere Reichweite der erlaubten Bauform ist kein Verlust, sondern passend: Der
Expertenmodus läuft ohnehin nur, solange die App läuft. Was gemeldet werden soll, wenn nichts
läuft, gehört auf das Telefon — dort stehen die geplanten Wecker (siehe
[08-GERAET §5.4](../08-GERAET-S25U.md)).

Drei Bedingungen, alle in `expert_client_test.dart` als Verhalten geprüft, nicht als
Schreibweise:

1. **Aus, bis jemand einschaltet.** Ein Browser, den man beim ersten Aufruf um Erlaubnis bittet,
   bekommt „Nein" — und danach ist er nicht mehr zu fragen.
2. **Nur was auch auf dem Telefon zu sehen wäre.** `severity: info` steht dort auf
   `IMPORTANCE_MIN` und erscheint gar nicht; im Browser poppt es dann auch nicht auf. Ein Ton
   nur bei `intervene` und höher.
3. **Einmal pro Entscheidung, und nicht, wenn jemand hinsieht.** Der Takt holt den Zustand alle
   20 Sekunden; ohne beides meldete dieselbe anliegende Handlung dreimal pro Minute (R2) —
   und zwar neben dem Feld, in dem sie ohnehin in großer Schrift steht.

Ein Test verbietet `PushManager`, `pushManager`, `applicationServerKey` und `serviceWorker` im
Quelltext der Seite. Ohne ihn wäre die Grenze nur eine Absicht: Beide Bauformen heißen
umgangssprachlich „Benachrichtigung", und die verbotene ist die bequemere.

*Was dazu nötig war.* Android filtert eingehende Multicast-Pakete im WLAN-Treiber weg, solange
niemand einen `MulticastLock` hält. Ohne ihn — und ohne
`CHANGE_WIFI_MULTICAST_STATE` — hört der Responder keine einzige Anfrage, ohne Fehler und ohne
Logeintrag. Die Sperre hängt am Expertenmodus, nicht am App-Start: Sie kostet Strom.

**3. Der Server ist aus, bis er eingeschaltet wird.** Kein Start beim Hochfahren, kein
Weiterlaufen nach einem Neustart, kein Anlauf aus einem Dienst heraus. Er hält sich an fünf
Regeln:

| | |
|---|---|
| Anmeldung | Zahlenabgleich oder sechsstellige PIN — siehe Punkt 3a |
| Sitzung | `HttpOnly`-Cookie, `SameSite=Strict`; die PIN steht nie in einer URL |
| Fehlversuche | nach fünf falschen PINs stoppt der Server sich selbst |
| Leerlauf | nach 30 Minuten ohne Anfrage stoppt er sich selbst |
| Sichtbarkeit | dauerhafte Benachrichtigung mit Adresse und Stopp-Knopf, solange er läuft |

**3a. Anmeldung per Zahlenabgleich.**

Die PIN abzutippen ist der Normalfall geblieben, aber nicht der erste Weg. Wer die Adresse
aufruft, bekommt eine zweistellige Zahl; dieselbe Zahl erscheint auf dem Telefon, zusammen mit
„Stimmt überein" und „Stimmt nicht".

*Warum das mehr ist als Bequemlichkeit.* Eine Benachrichtigung „Anmeldung zulassen?" wird
weggedrückt wie jede andere — die Bestätigung allein sichert nichts. Der Schutz liegt im
**Vergleich**: Fragt jemand anders im selben Moment an, steht dessen Zahl auf dem Telefon und
nicht auf dem Bildschirm, vor dem der Nutzer sitzt. Wer nur bestätigt, was übereinstimmt, lässt
niemand anderen herein.

Deshalb gibt es zu jedem Zeitpunkt **genau eine** offene Anfrage: Zwei Zahlen zur Auswahl wären
wieder ein Knopf. Sie verfällt nach 90 Sekunden, eine neue Anfrage ist frühestens nach drei
Sekunden möglich, und eine Ablehnung zählt wie ein Fehlversuch — nach fünf schaltet sich der
Server ab.

**3b. Mitstarten mit der App — optional, aus als Voreinstellung.**

Die erste Fassung schloss jeden Autostart aus. Das galt einem Server, der von selbst aufgeht und
läuft, ohne dass jemand davon weiß. Erlaubt ist jetzt etwas Engeres: Wer die Einstellung
setzt, hat den Server dabei, **sobald er die App öffnet** — nicht beim Hochfahren, nicht aus
einem Dienst, nicht ohne die App.

Der Anlass ist real: Am Arbeitsplatz liegt das Telefon in der Tasche, und ein Server, den man
erst am Gerät einschalten muss, wird nicht benutzt. Alle Sicherungen bleiben: Anmeldung,
dauerhafte Benachrichtigung mit Adresse und Stopp-Knopf, Abschaltung nach dreißig Minuten
Leerlauf. Der Unterschied zum ursprünglich Verbotenen ist, dass niemand den Zustand verpassen
kann — die Anzeige steht, solange er läuft.

**4. TLS mit selbst signiertem Zertifikat.**

Die erste Fassung dieses ADR verzichtete auf TLS mit dem Argument, man klicke die Browser-Warnung
ohnehin weg. Das war zu bequem gedacht: Ohne TLS liegen PIN, Sitzungscookie und sämtliche
Gesundheitsdaten im Klartext im Netz. **Passives Mitlesen ist trivial und hinterlässt keine
Spur**; ein aktives Übernehmen der Verbindung ist ein deutlich anderer Aufwand. Der Unterschied
ist real, und er zählt mehr als die Unbequemlichkeit einer Warnung.

Das Warn-Argument stimmt nur, solange die Warnung nichts Überprüfbares zeigt. Deshalb:

- **Der Fingerabdruck steht in der App.** Der Browser nennt denselben Wert unter „Zertifikat
  anzeigen". Stimmen beide überein, ist die Verbindung geprüft — das ist Authentifizierung, kein
  Wegklicken.
- **Das Zertifikat bleibt dasselbe.** Schlüssel und Zertifikat liegen in der Einstellungstabelle
  und überleben Neustarts. Ein neues Zertifikat bei jedem Start erzeugte bei jedem Start eine
  neue Warnung — genau die Gewöhnung, die das ursprüngliche Argument fürchtete.
- **Kein stiller Rückfall.** Schlägt TLS fehl, startet der Server nicht. Klartext als
  Ausweichweg wäre das Schlechteste von beidem.

Erzeugt wird es auf dem Gerät (RSA-2048, in einem eigenen Isolate, damit der Knopf nicht hängt),
mit LAN-Adresse **und** `axiom.local` als Subject Alternative Name — ohne passenden SAN lehnen
aktuelle Browser rundheraus ab, statt eine Ausnahme anzubieten. Ändert sich, *was* im Zertifikat
steht, zählt eine Formmarke hoch: Sonst würde das gespeicherte Zertifikat an der unveränderten
Adresse wiedererkannt und weiterverwendet, und der neue Weg schlüge fehl.

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
- Der Expertenmodus ist inzwischen **ein vollwertiger Client**. Die erste Fassung sagte, die
  Entscheidung im Moment bleibe auf dem Telefon; das galt für ein Gerät, das man dabei hat. Am
  Arbeitsplatz liegt es in der Tasche, und ein Vorschlag, den man nicht annehmen kann, ist
  keiner.

  **G1 bleibt davon unberührt.** Der Browser zeigt dieselbe Rangfolge wie das Telefon — eine
  feuernde Regel, sonst das Laufende, sonst der Vorschlag — und genau eine Handlung, nie eine
  Liste zur Auswahl. Die Liste steht daneben, als das, was der Expertenmodus ohnehin ist:
  Bestand, nicht Auswahl.
- Neue Prüfpflicht vor jedem Release: kein ausgehender Netzwerkcode, Server standardmäßig aus.
- Sollte der Expertenmodus zur Hauptoberfläche werden, ist das ein Signal, dass die
  Telefon-Ansicht etwas Falsches tut — nicht, dass der Server erweitert gehört.
