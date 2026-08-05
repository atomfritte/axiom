# Deine Daten

Alles bleibt auf dem Gerät. Kein Konto, keine Cloud, keine Telemetrie — und ein Export, der sich auch ohne AXIOM lesen lässt.

## Wo sie liegen

In einer SQLite-Datei im privaten Speicher der App. Andere Apps kommen nicht heran — dafür sorgt Android.

**Auf dem Telefon ist die Datei verschlüsselt.** Ohne Schlüssel ist sie nicht lesbar, auch nicht als Kopie. Der Schlüssel liegt im Schlüsselspeicher des Geräts, in gesicherter Hardware, und kann sie nicht verlassen — er wandert nicht in ein Backup und nicht auf ein anderes Gerät mit.

Was das **nicht** schützt: jemanden, der dein entsperrtes Gerät in der Hand hält und die App öffnet. Für den entschlüsselt der Schlüsselspeicher bereitwillig. Ein Bildschirmschloss ist deshalb keine Formalität, sondern die erste Verteidigungslinie.

**Auf dem Rechner liegt die Datei im Klartext.** Linux hat keinen Schlüsselspeicher, in den ein Schlüssel gehörte; eine Schlüsseldatei daneben wäre eine Attrappe. Was dort liegt, ist so geschützt wie dein Benutzerkonto. Die App sagt dir, was gerade gilt — unter *System → Daten*.

**Exporte** sind auf beiden Seiten verschlüsselt, mit einer Passphrase, die du vergibst.

Geht der Schlüssel verloren — gelöschte App-Daten, ein zurückgespieltes Backup, ein neues Gerät —, ist die Datenbank nicht mehr lesbar. AXIOM legt dann eine neue an und **sagt es dir** auf demselben Bildschirm, statt kommentarlos leer dazustehen.

Alles ist ein **Ereignis**, und Ereignisse werden nur angehängt, nie geändert und nie gelöscht. Eine Korrektur ist ein neues Ereignis. Daraus folgt zweierlei: Der gesamte Zustand lässt sich jederzeit aus dem Strom neu berechnen, und nichts verschwindet stillschweigend.

## Was hineinkommt

Check-ins, Erfassungen, Aufgaben, Anker, Fokusblöcke, Reiz-Slots, abgefangene Impulse, Vorfälle — und, falls freigegeben, Schlaffenster und Tagesschritte aus Health Connect.

![Health Connect ist freiwillig und liest nur zwei Größen. Auf dem Desktop entfällt die Frage.](img/health.webp)

Health Connect wird **nur gelesen**, nie beschrieben: Schlafzeiten und Schritte pro Tag. Kein Puls, kein Gewicht, kein Standort. Die Freigabe lässt sich jederzeit in beide Richtungen ändern, unter *System → Datenquellen*.

Einen Standortzugriff gibt es nicht. Der „Ort" einer Aufgabe ist ein Name, den du oder eine Geräteroutine setzt.

## Wie sie herauskommen

Unter *System → Daten*:

- **Export** schreibt alle Ereignisse in eine `.axiom`-Datei, verschlüsselt mit einem Kennwort von mindestens acht Zeichen. Innen ist es NDJSON — mit dem Kennwort auch ohne AXIOM lesbar. Sonst wäre es keine Datenhoheit.
- **Import** spielt fehlende Ereignisse ein. Vorhandene bleiben unberührt, der Import ist wiederholbar. Ein **Probelauf** zeigt vorher, was passieren würde.

So gleichen sich zwei Geräte an: Beide importieren die Datei des anderen, danach haben beide alles. Weil Ereignisse unveränderlich sind, kann dabei nichts kollidieren.

> Das Kennwort steht nirgends. Geht es verloren, ist die Datei unbrauchbar — das ist der Preis dafür, dass sie sonst niemand lesen kann.

## Das Wirkfenster

Ebenfalls unter *System → Daten*, standardmäßig **aus**. Eingeschaltet protokolliert es Einnahmen mit Beginn und Dauer der Wirkung, so wie du sie beobachtest.

AXIOM protokolliert nur. Es nennt keine Dosis, schlägt keine Einnahmezeit vor und bewertet keine Wirkung. Alles, was die Behandlung betrifft, gehört zu deiner Ärztin oder deinem Arzt.

Wohin AXIOM Daten von sich aus schickt: nirgendwohin. Warum diese Zusage mit dem Expertenmodus eine engere Form bekommt, steht in [Am Rechner: der Expertenmodus](kapitel:11).
