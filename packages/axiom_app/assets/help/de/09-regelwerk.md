# Das Regelwerk

Jede Regel ist lesbar: Bedingung, Aktion, Begründung, Grenzen und was sie in den letzten sieben Tagen getan hat. Zu finden unter *System → Regelwerk*.

![System: oben das Meta-Work-Budget, darunter der Stand der Eichung. Das Regelwerk liegt einen Tipp weiter.](img/system.webp)

## Was an einer Regel steht

- **Begründung** — warum es sie gibt. Pflichtfeld; ohne sie wird die Regel nicht geladen.
- **Bedingung** — der vollständige Wenn-Baum in Klartext.
- **Grenzen** — Priorität, Mindestabstand, Höchstzahl pro Tag, Backoff.
- **Letzte 7 Tage** — wie oft gefeuert, wie oft verdrängt, wie oft befolgt, verschoben, abgelehnt.
- **Gerade inaktiv** — warum sie jetzt nicht greift: Bedingung trifft nicht zu, Cooldown läuft, Tageslimit erreicht, Ruhezeit, oder die Datenlage ist zu dünn.

Marken am Rand: **SHADOW** heißt, die Regel läuft stumm mit. **UNGEEICHT** heißt, sie prüft auf Werte, deren Formelgewichte noch geschätzt sind.

## Die globalen Grenzen

| Grenze | Wert |
|---|---|
| Interventionen pro Tag | 12 |
| Meldungen pro Stunde | 2 |
| Ruhezeit | 23:00–06:30 |
| Mindestkonfidenz | 0,40 |

Ohne diese Deckel summieren sich einzeln vernünftige Regeln zu einer Benachrichtigungsflut — der häufigste Grund, warum solche Apps nach drei Wochen stummgeschaltet werden. Und eine stummgeschaltete App ist eine gelöschte App mit Extraschritten.

## Ändern

Der Editor bietet nur an, was die Engine versteht, und wertet jede Bedingung sofort gegen den Zustand von jetzt aus: Man sieht beim Tippen, ob die Regel gerade zuträfe und an welchem Teil sie scheitert.

Zwei Dinge sind nicht verhandelbar:

1. **Begründung und Mindestabstand sind Pflicht.** Sonst speichert der Editor nicht.
2. **Jede gespeicherte Regel läuft sieben Tage stumm**, auch eine geänderte. Geändert ist neu, und beurteilt wird sie an Tagen, die noch kommen.

Änderungen liegen als Überlagerung in der Datenbank; die mitgelieferten Dateien bleiben unberührt. Über das Code-Symbol lässt sich jede Regel als YAML kopieren — genau in der Form, die am Rechner nach `rules/` zurückkann. Erst dort ist sie versioniert.

## Abschalten

Ein Schalter je Regel. Ausgeschaltet bleibt sie erhalten, wird aber nicht ausgewertet.

Abschalten geht immer — auch wenn das Meta-Work-Budget aufgebraucht und der Editor deshalb zu ist. Eine falsch feuernde Regel bis morgen laufen zu lassen wäre Schadensbegrenzung durch Nichtstun.

Warum es dieses Budget gibt und wann der Editor wieder aufgeht, steht in [Rückblick und Eichung](kapitel:10).
