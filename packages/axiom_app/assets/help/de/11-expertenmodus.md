# Am Rechner: der Expertenmodus

Regeln schreiben, die Aufgabenliste mit allen Feldern überblicken, den Ereignisstrom lesen — am großen Bildschirm, auf den echten Daten des Telefons.

AXIOM startet dafür einen kleinen Server auf dem Telefon. Der Rechner ruft ihn im selben Netz auf. Es geht nichts ins Internet und nichts über einen fremden Dienst.

## Einschalten

*System → Expertenmodus*, dann *Server starten*. Danach stehen drei Dinge auf dem Bildschirm:

- die **Adresse**, meist `axiom.local` mit einem Port, dazu eine IP-Adresse als Ausweichweg
- eine **PIN**, sechsstellig, gültig nur für diesen Start
- der **Fingerabdruck** des Zertifikats

## Die zwei Vergleiche

Der Browser wird einmal warnen, weil das Zertifikat selbst signiert ist — keine fremde Stelle bürgt dafür. Statt die Warnung wegzuklicken: den Fingerabdruck mit dem vergleichen, den der Browser unter „Zertifikat anzeigen" nennt. Stimmen beide überein, sprichst du mit diesem Telefon und mit nichts dazwischen.

Nach der PIN erscheint eine zweite Zahl, auf dem Telefon und im Browser. Der Schutz liegt nicht in der Bestätigung, sondern im Vergleich: Fragt jemand anders im selben Moment an, steht dessen Zahl auf dem Telefon und nicht auf deinem Bildschirm. Deshalb steht „Stimmt nicht" gleichberechtigt daneben — ablehnen kostet nichts außer einem zweiten Versuch.

## Was ihn wieder ausmacht

Fünf falsche PINs. Dreißig Minuten ohne Anfrage. Der Knopf in der App oder auf der Benachrichtigung. Und das Beenden der App ohnehin.

Einen Autostart beim Hochfahren gibt es nicht. Optional startet der Server mit, wenn du AXIOM öffnest — Anmeldung, dauerhafte Anzeige und die Abschaltung nach Leerlauf bleiben auch dann.

## Was dort geht

- **Aufgaben als Liste**, alle Felder, direkt änderbar. Die App zeigt bewusst nur eine Handlung; Planen ist etwas anderes als Entscheiden im Moment.
- **Regelwerk im YAML.** Ungültiges wird abgelehnt, nicht übersprungen. Auch hier gilt: sieben Tage stumm.
- **Zustand und Ereignisstrom.** Nur lesend — Ereignisse sind unveränderlich.

## Was das kostet

Weil es diesen Modus gibt, hat AXIOM die Netzwerkberechtigung. Die frühere Zusage, dass Daten das Gerät auf Systemebene nicht verlassen können, gilt damit nicht mehr. An ihre Stelle tritt eine engere, getestete: **AXIOM lauscht, ruft aber nichts von sich aus auf.** Es gibt keinen Netzwerk-Client im Code, und ein Test hält das fest.

Damit `axiom.local` aufgeht, beantwortet AXIOM Namensanfragen im lokalen Netz. Das Paket enthält nur Name und IP dieses Geräts und läuft nur, solange der Server läuft.
