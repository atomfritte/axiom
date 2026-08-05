# Rückblick und Eichung

Vier Rückblicke mit hartem Zeitdeckel — und der Vorgang, mit dem aus geschätzten Formelgewichten deine eigenen werden.

## Die vier Umfänge

| Umfang | Deckel | Worum es geht |
|---|---|---|
| Tag | 2 min | Was ist liegengeblieben, das nicht liegenbleiben durfte |
| Woche | 15 min | Abweichungen, genervte Regeln, höchstens drei Vorhaben |
| Monat | 30 min | Wovon habe ich mich lautlos verabschiedet |
| Quartal | 60 min | Ist die Last gesunken? Was kann weg? |

Der Deckel läuft sichtbar mit und schließt am Ende von selbst. Das ist keine Bequemlichkeit: Ein Rückblick ohne Grenze wird selbst zur Ausweichbeschäftigung.

![Das Wochen-Review: Kennzahlen mit ihrer Folge, jede aufklappbar mit dem Rechenweg.](img/review.webp)

Jede Kennzahl zeigt aufgeklappt, wie sie gerechnet wurde. Auffällige Werte bekommen einen Punkt und einen Satz dazu, was daraus folgt — keine Note.

Zum Regelwerk erscheinen Verdikte: **STREICHEN** bei einer Regel, die nur abgelehnt wird, **ZU ENG** bei einer, die nie feuert, **KONFLIKT** bei zweien, die sich gegenseitig verdrängen. Geändert wird ab dem Wochen-Rückblick; im Tagesrückblick stehen sie nur da.

## Warum die Zeit gedeckelt ist

AXIOM zählt die Zeit, die du im System verbringst statt im Leben. Erfassen zählt nicht mit — Konfiguration, Auswertung und Herumschauen schon. Das Budget beträgt zwölf Minuten am Tag.

Ist es aufgebraucht, ist der Regeleditor für heute zu; morgen ist er wieder offen. Erfassen, Arbeiten, Nachsehen und das Abschalten einer Regel bleiben die ganze Zeit über offen.

> Das ist keine Strafe, sondern der Zweck. Ein System zu bauen ist immer stimulierender als die Aufgabe, für die es gebaut wurde.

## Eichen

Sind die drei Baseline-Bedingungen erfüllt, meldet die Hauptansicht das von selbst. Ab dann können die Formelgewichte aus deinen Messungen kommen statt aus Schätzungen — das ist der Punkt, ab dem die Empfehlungen belastbar werden.

Der Ablauf steht in der App unter *System → Eichung*, mit Befehlen zum Antippen und Kopieren:

1. Datenbank auf den Rechner holen und mit `calibrate.dart` auswerten. Das Werkzeug schreibt nichts — es schlägt nur vor.
2. Die Vorschläge im nächsten Wochen-Review durchgehen. Nicht blind übernehmen; jeder Wert soll erklärbar bleiben.
3. Werte in `weights.yaml` eintragen und `calibration.status` auf `calibrated` setzen.
4. Regelwerk spiegeln und neu bauen. Danach verschwinden die **UNGEEICHT**-Markierungen.

Der Umweg über den Rechner ist Absicht. Eine Eichung, die sich am Telefon in dreißig Sekunden verstellen lässt, ist keine.
