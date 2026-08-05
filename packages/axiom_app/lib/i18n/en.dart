/// Englische Fassung. Schluessel ist der deutsche Quelltext.
///
/// **Der Ton ist Teil der Uebersetzung, nicht Beiwerk.** Dieselben Regeln
/// gelten wie im Deutschen: keine Schuldsprache, kein Vergleich, keine
/// Ausrufezeichen-Motivation. Ein Messwert bleibt ein Messwert — „capacity
/// 34", nicht „only 34 %". Wo das Deutsche bewusst kommentarlos bleibt,
/// bleibt es das Englische auch.
///
/// Platzhalter `{0}`, `{1}`, … duerfen in anderer Reihenfolge stehen als im
/// Deutschen. Genau dafuer sind sie nummeriert.
///
/// Fehlt ein Eintrag, erscheint der deutsche Satz. `i18n_test` verhindert,
/// dass es dazu kommt: Jeder uebersetzbare Text im Quelltext braucht hier
/// eine Zeile.
library;

const Map<String, String> kEnglish = {
  '  Stufen': '  levels',
  ' / {0} min': ' / {0} min',
  ' / {0} min heute': ' / {0} min today',
  ' min offen': ' min left',
  ' · kostet etwas': ' · has a cost',
  ', Daten veraltet': ', data is stale',
  ', zeigt die Begruendung': ', shows the reasoning',
  'AKTIVIERUNGSENERGIE': 'ACTIVATION ENERGY',
  'ANKER ÄNDERN': 'EDIT ANCHOR',
  'ANLAUF {0} H': 'RUN-UP {0} H',
  'AUF': 'ON',
  'AUSLÖSEN': 'TRIGGER',
  'AXIOM': 'AXIOM',
  'AXIOM arbeitet mit exakten Uhrzeiten. Android schläfert Apps sonst ein — dann kommt die Erinnerung 40 Minuten zu spät oder gar nicht, und das ganze Konzept ist wertlos.':
      'AXIOM works to the minute. Otherwise Android puts apps to sleep — then '
          'the reminder arrives 40 minutes late or not at all, and the whole '
          'idea is worthless.',
  'AXIOM ist als Notiz-Fähigkeit angemeldet. „Hey Google, Notiz in AXIOM" öffnet die Erfassung.':
      'AXIOM is registered as a note-taking capability. “Hey Google, take a '
          'note in AXIOM” opens capture.',
  'AXIOM konnte nicht starten.': 'AXIOM could not start.',
  'AXIOM liest zwei Größen: Schlaffenster und Tagesschritte. Beide gehen in die Kapazität ein — heute nur, soweit du sie selbst einträgst.':
      'AXIOM reads two things: sleep windows and daily steps. Both feed '
          'capacity — today only as far as you enter them yourself.',
  'AXIOM meldet sich beim System als Notiz-App an. Damit erscheint es beim Doppeltipp mit dem Stift und in der Schnelleinstellung „Notiz".':
      'AXIOM registers with the system as a note app. It then appears on a '
          'double tap with the pen and in the “Note” quick setting.',
  'AXIOM misst deinen Zustand, wendet Regeln darauf an, die du selbst setzt, und nennt dir eine nächste Handlung. Mit Begründung und der Regel, die sie erzeugt hat.':
      'AXIOM measures your state, applies rules you set yourself, and names '
          'one next action. With the reasoning and the rule that produced it.',
  'AXIOM sendet Signale, auf die Routinen reagieren können: Fokus an und aus, Abendgrenze, Erhaltungsmodus.':
      'AXIOM sends signals that routines can react to: focus on and off, '
          'evening cutoff, maintenance mode.',
  'Ab 70 nichts Neues zusätzlich aufnehmen. Bestehendes eher abgeben als erweitern.':
      'Above 70, take on nothing new. Hand existing things off rather than '
          'adding to them.',
  'Ab jetzt können die Formelgewichte aus deinen Messungen kommen statt aus Schätzungen. Das ist der Punkt, ab dem die Empfehlungen belastbar werden.':
      'From here the formula weights can come from your measurements instead '
          'of estimates. That is the point where the output becomes reliable.',
  'Ab jetzt runterfahren. Was offen ist, ist morgen noch offen.':
      'Wind down from here. What is open will still be open tomorrow.',
  'Abbrechen': 'Cancel',
  'Abbrechen, ohne Notiz': 'Stop without a note',
  'Abend.': 'Evening.',
  'Abendgrenze': 'Evening cutoff',
  'Abgelegt': 'Filed',
  'Akkuoptimierung aus': 'Battery optimisation off',
  'Aktion': 'Action',
  'Aktualisierung nötig': 'Update needed',
  'Alle Ereignisse in eine verschlüsselte Datei. Ohne das Kennwort ist sie nicht lesbar — auch nicht von dir.':
      'Every event into one encrypted file. Without the passphrase it cannot '
          'be read — not by you either.',
  'Alles Offene braucht mehr Anlauf, als heute da ist. Das ist eine Messung, keine Bewertung. Eine Aufgabe in kleinere Schritte zu zerlegen hilft mehr als Anlauf nehmen.':
      'Everything open needs more of a run-up than today has. That is a '
          'measurement, not a verdict. Splitting a task into smaller steps '
          'helps more than trying harder.',
  'Alles steht zur Auswahl.': 'Everything is available.',
  'Als Nächstes: {0} um {1}.': 'Next: {0} at {1}.',
  'Anderer Ort': 'Another place',
  'Anderswo · {0}': 'Elsewhere · {0}',
  'Anfangen': 'Start',
  'Anzeige': 'Display',
  'Anker': 'Anchor',
  'Anker entfernen': 'Remove anchor',
  'Anker setzen': 'Set anchor',
  'Anstehend · {0}': 'Upcoming · {0}',
  'Anziehen, Sachen suchen, Tasche packen.':
      'Getting dressed, finding things, packing a bag.',
  'Auf dem Desktop läuft AXIOM ohne Systemrechte. Erfassen, Check-ins und der Regelinspektor funktionieren vollständig.':
      'On the desktop AXIOM runs without system permissions. Capture, '
          'check-ins and the rule inspector work in full.',
  'Auf diesem Gerät gibt es kein Health Connect. Schlaf und Bewegung kommen weiterhin aus deiner Eingabe.':
      'This device has no Health Connect. Sleep and movement keep coming from '
          'what you enter.',
  'Aufgabe zerlegen': 'Split task',
  'Aufgaben sitzen auf einer Skala: Wie schwer fällt der Start? Der Strich zeigt, wie viel Anlauf du heute hast.':
      'Tasks sit on a scale: how hard is it to start? The line shows how much '
          'run-up you have today.',
  'Aus Export vom {0}.{1}. · Schema v{2}':
      'From export of {0}/{1} · schema v{2}',
  'Aus anderen Apps teilen': 'Share from other apps',
  'Aus deiner Beobachtung. AXIOM schlägt hier nichts vor — das hängt von Präparat, Person und Tag ab.':
      'From your own observation. AXIOM suggests nothing here — it depends on '
          'the substance, the person and the day.',
  'Aus dem, was du gerade tust, herauszukommen dauert. Der Schritt, den man im Kopf immer vergisst.':
      'Getting out of what you are doing takes time. The step everyone leaves '
          'out when planning in their head.',
  'Aus konzentrierter Arbeit heute. Der Tausch ist der einzige, den dieses Belohnungssystem zuverlässig annimmt.':
      'From focused work today. That trade is the only one this reward system '
          'reliably accepts.',
  'Aussteigen': 'Step out',
  'BASELINE': 'BASELINE',
  'BASELINE LÄUFT': 'BASELINE RUNNING',
  'BASELINE TAG {0}': 'BASELINE DAY {0}',
  'BASELINE VOLLSTÄNDIG': 'BASELINE COMPLETE',
  'Baseline vollständig': 'Baseline complete',
  'Baumarkt, Büro, Zuhause …': 'Hardware store, office, home …',
  'Bedingung': 'Condition',
  'Bedingung trifft nicht zu': 'condition does not hold',
  'Befehl kopiert.': 'Command copied.',
  'Begrenzt — Kleines zuerst.': 'Limited — small things first.',
  'Begründung': 'Reasoning',
  'Bei Anlage KAP, Zeile 7': 'On form KAP, line 7',
  'Beispiel': 'Example',
  'Bereit.': 'Ready.',
  'Bezeichnung, wie du sie führst': 'Name it the way you think of it',
  'Bis dahin laufen die Regeln auf geschätzten Gewichten. Sie können danebenliegen — betroffene Regeln sind unten mit UNGEEICHT markiert.':
      'Until then the rules run on estimated weights. They can be off — the '
          'rules affected are marked UNCALIBRATED below.',
  'Bis zur Frist der am knappsten dastehenden Aufgabe. Ohne Frist steht hier 9999 — eine Zahl, die keine Regel unterschreitet.':
      'Until the deadline of the task with the least room. Without a deadline it reads 9999 — a number no rule goes below.',
  'Bixby: Routinen → Meine Routinen → Aktion hinzufügen → App öffnen → AXIOM. Dort lässt sich auch ein Sprachbefehl hinterlegen.':
      'Bixby: Routines → My routines → Add action → Open app → AXIOM. A voice '
          'command can be stored there too.',
  'Bleibt etwas Wichtiges rechts der Linie liegen, schlägt AXIOM vor, es in kleinere Schritte zu zerlegen, bis ein Teil links landet.':
      'If something important stays right of the line, AXIOM suggests '
          'splitting it until one piece lands on the left.',
  'Bremse': 'Brake',
  'Budget aufgebraucht. Änderungen am Regelwerk sind bis morgen zu. Erfassen, Arbeiten und Nachsehen bleiben offen. Das ist Absicht: Das System zu optimieren fühlt sich an wie Arbeit, ist aber keine.':
      'Budget used up. Rule changes are closed until tomorrow. Capture, work '
          'and looking things up stay open. That is deliberate: tuning the '
          'system feels like work but is not.',
  'CHECK-IN': 'CHECK-IN',
  'Check-in': 'Check-in',
  'Check-in gespeichert.': 'Check-in saved.',
  'Check-in machen': 'Do a check-in',
  'Cooldown läuft': 'cooldown running',
  'Cooldowns, die abgelaufen sind, ohne dass die Handlung ausgeführt wurde.':
      'Cooldowns that ran out without the action being carried out.',
  'DA SEIN UM': 'BE THERE AT',
  'DANACH': 'AFTERWARDS',
  'DATEN ALT': 'STALE DATA',
  'DEINE FRAGEN': 'YOUR QUESTIONS',
  'DIE ERSTEN 14 TAGE': 'THE FIRST 14 DAYS',
  'Damals: {0}/5': 'At the time: {0}/5',
  'Damit Erinnerungen auf die Minute kommen.':
      'So reminders arrive to the minute.',
  'Damit es zuverlässig läuft': 'So it runs reliably',
  'Das Kennwort steht nirgends. Geht es verloren, ist die Datei unbrauchbar — das ist der Preis dafür, dass sie sonst niemand lesen kann.':
      'The passphrase is stored nowhere. If it is lost, the file is unusable — '
          'that is the price of nobody else being able to read it.',
  'Das ist noch zu groß. Ein Schritt, der gerade so passt, passt morgen nicht mehr — dann fängt das Ganze von vorn an. Was wäre der Handgriff davor?':
      'That is still too big. A step that only just fits today will not fit '
          'tomorrow — and then it starts over. What is the move before it?',
  'Das zentrale Bild': 'The central picture',
  'Datei nicht gefunden.': 'File not found.',
  'Daten': 'Data',
  'Datenbank auf den Rechner holen und auswerten. Das Werkzeug schreibt nichts — es schlägt nur vor.':
      'Pull the database onto the computer and analyse it. The tool writes '
          'nothing — it only proposes.',
  'Datenlage zu dünn — lieber schweigen':
      'too little data — better to stay quiet',
  'Datenquellen': 'Data sources',
  'Dauerhafte Anzeige': 'Always visible',
  'Deine Prüffragen': 'Your own questions',
  'Der Nutzen liegt nicht im Aufschreiben, sondern im Muster: Was regelmäßig trifft, lässt sich vorbereiten.':
      'The value is not in writing it down but in the pattern: what hits '
          'regularly can be prepared for.',
  'Der Ort entscheidet, was hier vorgeschlagen wird. Ohne Ort steht alles zur Auswahl — es wird nichts ausgeblendet, was du nicht selbst eingeschaltet hast.':
      'The place decides what gets suggested here. Without a place everything is available — nothing is hidden that you did not switch on yourself.',
  'Der Rest, grob — kommt später dran': 'The rest, roughly — for later',
  'Der Unterschied zu anderen Apps: Hier wird nicht gefragt, was du tun willst — sondern in welchem Zustand du bist. Was heute außerhalb deiner Reichweite liegt, wird gar nicht erst gezeigt.':
      'What makes this different: it does not ask what you want to do — it '
          'asks what state you are in. What is out of reach today is not shown '
          'at all.',
  'Der erste Wert ist drin. Ab jetzt sammelt AXIOM zwei Wochen lang Daten, bevor es anfängt, Empfehlungen zu geben.':
      'The first value is in. AXIOM now collects data for two weeks before it '
          'starts making recommendations.',
  'Der letzte Punkt ist Pflicht. Jedes Review ohne Streichoption lässt das System nur wachsen.':
      'The last point is mandatory. Any review without a delete option only '
          'lets the system grow.',
  'Der letzte Punkt ist der, den man im Kopf immer vergisst.':
      'The last point is the one everyone forgets when planning in their head.',
  'Der schnellste Weg, den das Gerät hergibt: zwei Sekunden statt zehn.':
      'The fastest route this device offers: two seconds instead of ten.',
  'Der stärkste einzelne Einfluss auf die Kapazität von heute. Grob geschätzt reicht.':
      'The single strongest influence on today’s capacity. A rough estimate is '
          'enough.',
  'Deutlich. Ein Reiz-Slot wäre fällig.': 'Marked. A stimulation slot is due.',
  'Deutlich. Ein Slot wäre fällig.': 'Marked. A slot is due.',
  'Die Einordnung kommt in etwa zwölf Stunden.':
      'The review comes in about twelve hours.',
  'Die Einschätzung im Moment und im Rückblick liegen bei dir nah beieinander.':
      'Your reading in the moment and in hindsight sit close together.',
  'Die Formelgewichte stammen aus deinen Daten.':
      'The formula weights come from your data.',
  'Die Gewichte können jetzt geeicht werden.':
      'The weights can be calibrated now.',
  'Die Kompensationslast liegt im gewohnten Bereich.':
      'Compensation load is in its usual range.',
  'Die Last ist seit über zwei Wochen auf diesem Niveau. AXIOM misst nur — für die Einordnung ist ärztliche oder psychotherapeutische Abklärung der richtige Weg.':
      'Load has been at this level for over two weeks. AXIOM only measures — '
          'medical or psychotherapeutic assessment is the right way to '
          'interpret it.',
  'Die Last steigt seit einigen Tagen. Nach außen noch unauffällig — genau deshalb steht es hier.':
      'Load has been rising for a few days. Still invisible from outside — '
          'which is exactly why it is shown here.',
  'Die Last steigt seit einigen Tagen. Noch unauffällig nach außen — genau deshalb wird sie hier angezeigt.':
      'Load has been rising for a few days. Still invisible from outside — '
          'which is exactly why it is shown here.',
  'Die Prüffragen schreibst du im ruhigen Zustand. Eine fremde Frage klickt man weg, die eigene beantwortet man.':
      'You write these questions while calm. Someone else’s question gets '
          'dismissed; your own gets answered.',
  'Die Restzeit steht als laufende Benachrichtigung im Benachrichtigungsbereich.':
      'The remaining time sits in the notification shade as an ongoing '
          'notification.',
  'Die Restzeit steht in der Statusleiste, auf dem Sperrbildschirm und in der Now Bar. Du musst hier nicht nachsehen.':
      'The remaining time sits in the status bar, on the lock screen and in '
          'the Now bar. You do not have to look here.',
  'Die Systemkomponente ist älter als das, was AXIOM liest. Sie lässt sich in den Systemeinstellungen aktualisieren.':
      'The system component is older than what AXIOM reads. It can be updated '
          'in system settings.',
  'Die Vorlaufzeit ist die Zeit, die im Kalender nicht steht: aussteigen, fertigmachen, Puffer. Sie erklärt, warum ein Termin mehr kostet als seine Dauer.':
      'Lead time is the time the calendar never shows: stepping out, getting '
          'ready, buffer. It explains why an appointment costs more than its '
          'duration.',
  'Die Vorschläge im nächsten Wochen-Review durchgehen. Nicht blind übernehmen — jeder Wert soll erklärbar sein.':
      'Go through the proposals in the next weekly review. Do not adopt them '
          'blindly — every value should be explainable.',
  'Die\nKapazitätslinie.': 'The\ncapacity line.',
  'Diese Regel prüft auf Werte, deren Formelgewichte noch geschätzt sind. Sie kann danebenliegen, bis weights.yaml an echten Daten kalibriert ist.':
      'This rule tests values whose formula weights are still estimates. It '
          'can be off until weights.yaml is calibrated against real data.',
  'Diese Regeln wurden abgelehnt und sind nicht aktiv. Eine stumm übersprungene Regel wäre schlimmer als ein Fehler: Man verlässt sich auf etwas, das es nicht gibt.':
      'These rules were rejected and are not active. A silently skipped rule '
          'would be worse than an error: you would rely on something that does '
          'not exist.',
  'Diese Werte sind Messungen aus deinen eigenen Angaben und Gerätedaten. Sie sind keine Diagnose und kein Befund. AXIOM ersetzt weder ärztliche noch psychotherapeutische Behandlung.':
      'These values are measurements from your own entries and device data. '
          'They are not a diagnosis or a finding. AXIOM replaces neither '
          'medical nor psychotherapeutic treatment.',
  'Dieses Modul hält fest und zeigt Muster. Es deutet nichts und behandelt nichts. Wenn dich etwas davon länger belastet, ist das ein Grund, mit einer Fachperson zu sprechen — nicht mit einer App.':
      'This module records and shows patterns. It interprets nothing and '
          'treats nothing. If any of it weighs on you for a while, that is a '
          'reason to talk to a professional — not to an app.',
  'Dosis (optional)': 'Dose (optional)',
  'Drei kurze Check-ins am Tag, dazu Schlaf und Bewegung vom Gerät. Zusammen ergibt das sechs Messwerte.':
      'Three short check-ins a day, plus sleep and movement from the device. '
          'Together that makes six readings.',
  'Drei\nSystemrechte.': 'Three\npermissions.',
  'EINGANG LEER': 'INBOX EMPTY',
  'EINNAHME': 'INTAKE',
  'EINORDNUNG': 'REVIEW',
  'ERFASSEN': 'CAPTURE',
  'ERLAUBEN': 'ALLOW',
  'EXPORT': 'EXPORT',
  'Eichung': 'Calibration',
  'Eigene Frage…': 'Your own question…',
  'Eigenen Kanal anlegen': 'Add your own channel',
  'Ein Regelwerk,\nkeine To-do-App.': 'A rulebook,\nnot a to-do app.',
  'Ein Satz reicht. Er spart dir beim nächsten Mal den halben Anlauf.':
      'One sentence is enough. It saves you half the run-up next time.',
  'Ein Stichwort, wenn du magst (optional)': 'A keyword if you like (optional)',
  'Ein Trigger ist eine Handlung, die du im Moment tun willst und am nächsten Tag oft nicht mehr. Statt sie zu sperren, schiebt AXIOM eine Wartezeit dazwischen — und stellt dir deine eigenen Fragen.':
      'A trigger is an action you want to take right now and often no longer '
          'want the next day. Instead of blocking it, AXIOM puts a waiting '
          'period in between — and asks you your own questions.',
  'Ein Vorfall wartet auf Einordnung': 'One incident is waiting for review',
  'Eine Aufgabe gehört woanders hin.': 'One task belongs somewhere else.',
  'Eine Geräteroutine kann das auch: Broadcast de.atomfritte.axiom.PLACE mit dem Zusatz „place". Ohne Standortberechtigung.':
      'A device routine can do this too: broadcast de.atomfritte.axiom.PLACE with the extra “place”. No location permission.',
  'Eine Handlung': 'One action',
  'Einen Moment.': 'One moment.',
  'Eingang': 'Inbox',
  'Eingerichtet': 'Set up',
  'Einmal einrichten': 'Set up once',
  'Einmal\nkurz messen.': 'One quick\nmeasurement.',
  'Einnahme eintragen': 'Log an intake',
  'Einspielen': 'Import',
  'Einstellungen öffnen': 'Open settings',
  'Eintragen': 'Log',
  'Emotionale Spitzen festhalten und einordnen':
      'Record emotional spikes and review them',
  'Energie': 'Energy',
  'Erfassen': 'Capture',
  'Erfassen, Check-in und Fokus direkt vom Startbildschirm.':
      'Capture, check-in and focus straight from the home screen.',
  'Erfasst und einsortiert': 'Captured and sorted',
  'Erfasst.': 'Captured.',
  'Erfasste Nutzungszeit gegen deine eigene Schätzung.':
      'Recorded time in the app against your own estimate.',
  'Erhaltungsmodus': 'Maintenance mode',
  'Erhaltungsmodus. Für die nächsten Tage nur Pflicht und Erholung — auch wenn es gerade läuft.':
      'Maintenance mode. For the next few days: obligations and recovery only '
          '— even when it is going well.',
  'Erhaltungsmodus. Nur Pflicht und Erholung.':
      'Maintenance mode. Obligations and recovery only.',
  'Erholung hat gewirkt': 'Recovery worked',
  'Erhöht. Im Blick behalten.': 'Raised. Worth watching.',
  'Erledigt': 'Done',
  'Erledigte Check-ins geteilt durch geplante.':
      'Completed check-ins divided by scheduled ones.',
  'Erster Messpunkt': 'First reading',
  'Etwas Körperliches, das in zwei Minuten erledigt ist. Nicht der Plan — der erste Handgriff.':
      'Something physical that takes two minutes. Not the plan — the first '
          'move.',
  'Exakte Erinnerungen': 'Exact reminders',
  'Exportiert: {0}': 'Exported: {0}',
  'Fahrzeit': 'Travel time',
  'Falls nicht sichtbar: Schnelleinstellungen aufziehen → Stift-Symbol → „AXIOM erfassen" nach oben ziehen.':
      'If it is not there: pull down quick settings → pencil icon → drag '
          '“AXIOM capture” up.',
  'Fertig': 'Done',
  'Fertigmachen': 'Get ready',
  'Festhalten': 'Record',
  'Fokus': 'Focus',
  'Fokus beenden': 'End focus',
  'Fokus läuft': 'Focus running',
  'Fokus starten': 'Start focus',
  'Fokuslast heute': 'Focus load today',
  'Folgen, nicht Wichtigkeit.': 'Consequences, not importance.',
  'Freigabe um {0}. Bis dahin steht die Sache still — sie läuft nicht weg.':
      'Released at {0}. Until then it sits still — it is not going anywhere.',
  'Freigabe {0}': 'Released {0}',
  'Fällt weg': 'Drops out',
  'Für Nachtentscheidungen ist „bis 09:00" das Wirksamste — was um eins dringend wirkt, sieht um neun anders aus.':
      'For night-time decisions “until 09:00” works best — what feels urgent '
          'at one looks different at nine.',
  'Für alles, was dazwischenkommt.': 'For whatever comes up.',
  'Für die nächsten Tage nur Pflicht und Erholung. Dass dieser Modus greift, ist der Zweck des Systems — nicht dein Versagen.':
      'For the next few days: obligations and recovery only. This mode kicking '
          'in is what the system is for.',
  'GEEICHT': 'CALIBRATED',
  'GESCHÜTZT': 'PROTECTED',
  'Gab es Erhaltungsmodus-Tage? Was ging voraus?':
      'Were there maintenance-mode days? What came before them?',
  'Gedeckt.': 'Covered.',
  'Geht das nur an einem Ort?': 'Does this only work in one place?',
  'Gehört zu einem anderen Ort als „{0}". Sie kommen zurück, sobald der Ort passt oder keiner gesetzt ist.':
      'Belongs to a place other than “{0}”. They come back as soon as the place matches, or as soon as none is set.',
  'Geld, Schlaf, Gesundheit oder Beziehung. Wird nicht verboten — nur nicht von selbst vorgeschlagen.':
      'Money, sleep, health or relationships. Not forbidden — just not '
          'suggested on its own.',
  'Gemeint sind Momente, in denen etwas unverhältnismäßig hart getroffen hat — Kritik, Zurückweisung, ein eigener Fehler. Zwei Tipps im Moment, die Einordnung kommt später.':
      'This means moments where something landed disproportionately hard — '
          'criticism, rejection, a mistake of your own. Two taps in the '
          'moment; the review comes later.',
  'Genug Daten zum Eichen.': 'Enough data to calibrate.',
  'Geplante Slots geteilt durch alle Slots.':
      'Planned slots divided by all slots.',
  'Gerade inaktiv': 'Currently inactive',
  'Gezählte Ereignisse im Zeitraum.': 'Events counted in the period.',
  'Geändert wird erst im Wochen-Review.':
      'Changes happen in the weekly review.',
  'Gleicher Zustand, gleiche Regeln — immer dasselbe Ergebnis. Nichts davon ist geraten, und du kannst jederzeit nachsehen, wie ein Wert zustande kam.':
      'Same state, same rules — always the same result. None of it is '
          'guesswork, and you can check at any time how a value came about.',
  'Gleitender Mittelwert aus Schlafschuld, Erholungsqualität, Kompensationsaufwand, Reizbarkeit und Rückzug.':
      'Rolling average of sleep debt, recovery quality, compensation effort, '
          'irritability and withdrawal.',
  'Grenzen': 'Limits',
  'Grob reicht. Einordnen kannst du später.':
      'Rough is fine. You can sort it later.',
  'Hat es getragen?': 'Did it hold?',
  'Hat nie gefeuert. Entweder ist die Bedingung zu eng oder die Regel überflüssig.':
      'Never fired. Either the condition is too narrow or the rule is '
          'redundant.',
  'Health Connect ist eine Schnittstelle des Geräts. Nichts davon verlässt das Telefon — AXIOM hat keine Netzwerkberechtigung.':
      'Health Connect is an interface of the device. None of it leaves the '
          'phone — AXIOM has no network permission.',
  'Health Connect · {0}': 'Health Connect · {0}',
  'Herunterwischen, tippen, schreiben. Funktioniert aus jeder App heraus.':
      'Swipe down, tap, type. Works from inside any app.',
  'Heute liegt nichts davon in Reichweite. Zerlegen hilft mehr als Anlauf nehmen.':
      'None of it is in reach today. Splitting helps more than trying harder.',
  'Heute liegt nichts unter der Linie.': 'Nothing sits below the line today.',
  'Hoch. Jetzt planen, was sonst ungeplant passiert.':
      'High. Plan now what otherwise happens unplanned.',
  'Hoch. Was jetzt nicht geplant wird, passiert ungeplant.':
      'High. What is not planned now happens unplanned.',
  'Homescreen-Widget': 'Home screen widget',
  'Häufungen · 30 Tage': 'Clusters · 30 days',
  'IM RÜCKBLICK': 'IN HINDSIGHT',
  'IMPORT': 'IMPORT',
  'INS BETT': 'TO BED',
  'Im Benachrichtigungsbereich bleiben': 'Stay in the notification shade',
  'Im Normalbereich.': 'In the normal range.',
  'Impulse abgefangen': 'Impulses intercepted',
  'In dieser Zeit gibt AXIOM absichtlich keine Empfehlungen. Es misst nur. Regeln, die auf geratenen Werten beruhen, liegen falsch — und eine App, die einmal offensichtlich danebenliegt, macht man nicht wieder auf.':
      'During this time AXIOM deliberately gives no recommendations. It only '
          'measures. Rules built on guessed values are wrong — and an app that '
          'is obviously wrong once does not get opened again.',
  'In einen ersten Schritt zerlegen': 'Split into a first step',
  'Interventionen pro Tag': 'Interventions per day',
  'Ist die Last gesunken? Belegen, nicht behaupten.':
      'Has load come down? Show it, do not claim it.',
  'JETZT': 'NOW',
  'JETZT BEENDEN': 'END NOW',
  'Jetzt': 'Now',
  'Jetzt abgleichen': 'Sync now',
  'Jetzt einplanen': 'Schedule it now',
  'Jetzt ist genug Abstand da. Zwei Fragen, dann ist es abgelegt.':
      'There is enough distance now. Two questions, then it is filed.',
  'Jetzt nicht': 'Not now',
  'Jetzt nichts Neues zusätzlich aufnehmen. Bestehendes eher abgeben als erweitern.':
      'Take on nothing new right now. Hand existing things off rather than '
          'adding to them.',
  'KANAL': 'CHANNEL',
  'KAPAZITÄT {0}': 'CAPACITY {0}',
  'KEINE ANKER': 'NO ANCHORS',
  'KEINE TRIGGER': 'NO TRIGGERS',
  'Kalt duschen': 'Cold shower',
  'Kanal speichern': 'Save channel',
  'Kanäle · {0}': 'Channels · {0}',
  'Kapazitaetslinie. Kapazitaet {0} von 100. {1} von {2} Aufgaben sind jetzt startbar.':
      'Capacity line. Capacity {0} out of 100. {1} of {2} tasks can be started '
          'now.',
  'Kapazität': 'Capacity',
  'Kein Ort': 'No place',
  'Kein Vorschlag heißt: gerade ist nichts nötig. Was dir einfällt, kannst du unten erfassen.':
      'No suggestion means nothing is needed right now. Whatever comes to '
          'mind, you can capture it below.',
  'Kein Weg ist Pflicht. Der beste ist der, den du tatsächlich nutzt — welcher das ist, steht nach der Baseline in der Auswertung.':
      'No route is mandatory. The best one is the one you actually use — which '
          'that is shows up in the review after the baseline.',
  'Keine Cloud, kein Konto, keine Auswertung durch andere':
      'No cloud, no account, nobody else analysing you',
  'Keine Erinnerung, die dir Vorwürfe macht':
      'No reminder that holds anything against you',
  'Keine KI, die für dich entscheidet': 'No AI deciding for you',
  'Keine Streaks, die brechen können': 'No streaks that can break',
  'Kennwort': 'Passphrase',
  'Kennwort, mindestens acht Zeichen': 'Passphrase, at least eight characters',
  'Kennzahlen': 'Metrics',
  'Knopf in der App': 'Button in the app',
  'Kompensationslast': 'Compensation load',
  'Konkret, nicht als Vorsatz. Optional.':
      'Concrete, not a resolution. Optional.',
  'Kostet etwas': 'Has a cost',
  'Kraftaufwand für Struktur': 'Effort spent on structure',
  'Kritisch. Nichts Neues aufnehmen.': 'Critical. Take on nothing new.',
  'Kumulierter Aufwand, den Alltag zu strukturieren.':
      'Accumulated effort of structuring everyday life.',
  'Kurz durchgehen': 'Quick pass',
  'Körper': 'Body',
  'LETZTE EINTRÄGE': 'RECENT ENTRIES',
  'Langes Tippen auf das App-Symbol': 'Long press on the app icon',
  'Langes Tippen auf den Homescreen → Widgets → AXIOM.':
      'Long press the home screen → Widgets → AXIOM.',
  'Lasse ich': 'Letting it go',
  'Last erhöht': 'Load raised',
  'Last kritisch': 'Load critical',
  'Laufendes abschließen': 'Finish what is running',
  'Letzte 7 Tage': 'Last 7 days',
  'Los geht’s': 'Get started',
  'LÄUFT': 'RUNNING',
  'LÄUFT AUF': 'RUNNING ON',
  'Läuft': 'Running',
  'Läuft.': 'Running.',
  'Läuft. Benachrichtigungen sind stumm.':
      'Running. Notifications are silenced.',
  'Läuft…': 'Running…',
  'META-WORK-BUDGET': 'META-WORK BUDGET',
  'Mache ich': 'Doing it',
  'Meldungen pro Stunde': 'Notifications per hour',
  'Messen': 'Measure',
  'Messpunkte': 'readings',
  'Messpunkte erfasst': 'Readings captured',
  'Messwerte': 'Readings',
  'Mindestkonfidenz': 'Minimum confidence',
  'Mit gesetztem Ziel bleibt es still, solange der Block läuft. Benachrichtigungen werden unterdrückt.':
      'With a target set it stays quiet while the block runs. Notifications '
          'are suppressed.',
  'Mittag.': 'Midday.',
  'Mitteilungen': 'Notifications',
  'Morgen.': 'Morning.',
  'Morgen: ein Anker, eine Aufgabe.': 'Tomorrow: one anchor, one task.',
  'Musik, laut': 'Music, loud',
  'März': 'March',
  'NACHBETRACHTUNG': 'HINDSIGHT',
  'NACHBETRACHTUNG · {0} OFFEN': 'HINDSIGHT · {0} OPEN',
  'NEUER ANKER': 'NEW ANCHOR',
  'NICHT GELADEN · {0}': 'NOT LOADED · {0}',
  'NICHTS ANLIEGEND': 'NOTHING PENDING',
  'NICHTS ERFASST': 'NOTHING CAPTURED',
  'NICHTS IN REICHWEITE': 'NOTHING IN REACH',
  'Nachmittag.': 'Afternoon.',
  'Nicht freigegeben': 'Not granted',
  'Nicht verfügbar': 'Not available',
  'Nicht wie lang es dauert. Nur der Anfang.':
      'Not how long it takes. Just the beginning.',
  'Nichts Neues · {0} bereits vorhanden': 'Nothing new · {0} already there',
  'Nichts einsortiert. Der Eingang läuft voll, und ein voller Eingang wird irgendwann gar nicht mehr geöffnet.':
      'Nothing sorted. The inbox fills up, and a full inbox eventually stops '
          'being opened at all.',
  'Nichts liegt woanders.': 'Nothing is filed elsewhere.',
  'Nichts startbar gerade. Ein Fokusblock ohne Ziel lässt sich später nicht bewerten — dann lieber ohne.':
      'Nothing startable right now. A focus block without a target cannot be '
          'assessed later — better to run it without one.',
  'Nichts terminiert.': 'Nothing scheduled.',
  'Nichts zu sortieren.': 'Nothing to sort.',
  'Nie eine Liste zum Auswählen. Genau eine Sache, plus die Regel-Nummer, die dahintersteckt.':
      'Never a list to choose from. Exactly one thing, plus the rule number '
          'behind it.',
  'Noch keine Aufgaben erfasst.': 'No tasks captured yet.',
  'Noch keine Vorfälle.': 'No incidents yet.',
  'Noch nicht gestartet. Sie beginnt, sobald das Onboarding abgeschlossen ist.':
      'Not started yet. It begins once onboarding is finished.',
  'Noch nichts eingerichtet.': 'Nothing set up yet.',
  'Noch nichts verdient heute. Ein Slot geht trotzdem — er wird nur anders gezählt.':
      'Nothing earned yet today. A slot still works — it is just counted '
          'differently.',
  'Noch wach.': 'Still awake.',
  'Noch {0} min. Die meisten Impulse überleben diese Zeit nicht.':
      '{0} min left. Most impulses do not survive that long.',
  'Normal.': 'Normal.',
  'Normalbetrieb': 'Normal operation',
  'Notieren und beenden': 'Note it and end',
  'Notiert. Diese Regel meldet sich seltener.':
      'Noted. This rule will speak up less often.',
  'Notiz wartet': 'note waiting',
  'Notizen warten': 'notes waiting',
  'Nur nötig, wenn die Aufgabe woanders nicht geht. Kein Standortzugriff — nur ein Name.':
      'Only needed if the task does not work elsewhere. No location access — just a name.',
  'Nächste Woche: höchstens drei Vorhaben.': 'Next week: three plans at most.',
  'Nächte': 'nights',
  'ODER EINE DIESER FORMEN': 'OR ONE OF THESE SHAPES',
  'ODER EINE VORLAGE': 'OR A TEMPLATE',
  'ORT': 'PLACE',
  'Offen · {0}': 'Open · {0}',
  'Oft ein anderer als der gefühlte.':
      'Often a different one than it felt like.',
  'Ohne Notiz beenden': 'End without a note',
  'Ohne gesetztes Ziel': 'No target set',
  'Ohne gesetztes Ziel fragt AXIOM nach 45 Minuten einmal leise nach, ob das noch das Richtige ist.':
      'With no target set, AXIOM asks once, quietly, after 45 minutes whether '
          'this is still the right thing.',
  'Ohne mindestens eine Frage kein Trigger. Sie ist der Vertrag.':
      'No trigger without at least one question. The question is the contract.',
  'Ordner auf den Tisch legen': 'Put the folder on the table',
  'Ort': 'Place',
  'Ort über eine Routine': 'Place via a routine',
  'Ort …': 'Place …',
  'Passt nicht': 'Does not fit',
  'Pfad kopiert.': 'Path copied.',
  'Pfad zur .axiom-Datei': 'Path to the .axiom file',
  'Priorität {0}': 'Priority {0}',
  'Probelauf': 'Dry run',
  'Puffer': 'Buffer',
  'Puffer für emotionale Belastung.': 'Headroom for emotional load.',
  'Raus, schnell': 'Outside, fast',
  'Rechtfertigt AXIOM seine eigenen Kosten?':
      'Does AXIOM justify its own cost?',
  'Regel läuft': 'rule running',
  'Regel {0}{1}': 'Rule {0}{1}',
  'Regeln anwenden': 'Apply rules',
  'Regeln laufen': 'rules running',
  'Regeln sind Wenn-Dann-Sätze in Klartext. Du kannst jede lesen, ändern und abschalten.':
      'Rules are if-then sentences in plain text. You can read, change and '
          'switch off every one of them.',
  'Regeln werden in YAML gepflegt und liegen unter Versionskontrolle. Neue Regeln laufen mindestens sieben Tage stumm mit (log_only), bevor sie etwas sagen dürfen.':
      'Rules live in YAML under version control. New rules run silently for at '
          'least seven days (log_only) before they are allowed to say '
          'anything.',
  'Regelwerk spiegeln und neu bauen. Danach verschwinden die UNGEEICHT-Markierungen.':
      'Mirror the rulebook and rebuild. The UNCALIBRATED markers disappear '
          'afterwards.',
  'Regelwerk · {0}': 'Rulebook · {0}',
  'Regelwerk · {0} offen': 'Rulebook · {0} open',
  'Regeländerungen gehören in dieses Zeitfenster — und nur hierher.':
      'Rule changes belong in this window — and only here.',
  'Regulationsreserve': 'Regulation reserve',
  'Rein damit. Sortieren kannst du später.':
      'Get it in. You can sort it later.',
  'Reine Wegzeit ohne Puffer.': 'Travel time only, no buffer.',
  'Reiz': 'Stimulation',
  'Reizbedarf': 'Stimulation need',
  'Reizbedarf geplant gedeckt': 'Stimulation need covered as planned',
  'Reizhunger': 'Stimulation hunger',
  'Rest nach dem Anlauf': 'Time left after the run-up',
  'Review abschließen': 'Finish review',
  'Routinen → Dann → Anderes → Broadcast senden → de.atomfritte.axiom.PLACE, Zusatz „place" = Büro. Ein leerer Zusatz setzt den Ort zurück.':
      'Routines → Then → Other → Send broadcast → de.atomfritte.axiom.PLACE, extra “place” = Büro. An empty extra clears the place.',
  'Routinen → Wenn → Anderes → Broadcast empfangen → de.atomfritte.axiom.FOCUS_START, de.atomfritte.axiom.FOCUS_END, de.atomfritte.axiom.WINDDOWN, de.atomfritte.axiom.L3_ENTER':
      'Routines → If → Other → Receive broadcast → de.atomfritte.axiom.FOCUS_START, '
          'de.atomfritte.axiom.FOCUS_END, de.atomfritte.axiom.WINDDOWN, de.atomfritte.axiom.L3_ENTER',
  'Ruhezeit': 'quiet hours',
  'Ruhig gerade.': 'Quiet right now.',
  'S-Pen': 'S Pen',
  'SCHEMA v{0} · {1} REGELN': 'SCHEMA v{0} · {1} RULES',
  'SCHLAF': 'SLEEP',
  'SO WIRD GERECHNET': 'HOW THIS IS CALCULATED',
  'SORTIEREN': 'SORT',
  'START FEHLGESCHLAGEN': 'STARTUP FAILED',
  'START {0}/10': 'START {0}/10',
  'SYSTEM': 'SYSTEM',
  'Samsung Modi und Routinen': 'Samsung Modes and Routines',
  'Samsung beendet Hintergrund-Apps aggressiv. Ohne diese Ausnahme feuern Erinnerungen unzuverlässig.':
      'Samsung shuts down background apps aggressively. Without this exception '
          'reminders fire unreliably.',
  'Schlaf eintragen': 'Log sleep',
  'Schlaffenster und Tagesschritte werden beim Start nachgezogen. Nur lesend, nur diese beiden, jederzeit widerrufbar.':
      'Sleep windows and daily steps are pulled in at startup. Read only, just '
          'those two, revocable at any time.',
  'Schlafschuld': 'Sleep debt',
  'Schließen': 'Close',
  'Schnelleinstellung': 'Quick setting',
  'Seit {0} min nichts getrunken oder bewegt. Kurz aufstehen kostet zwei Minuten.':
      'Nothing to drink and no movement for {0} min. Getting up costs two '
          'minutes.',
  'Seit {0} min vertieft, ohne gesetztes Ziel. Ist das noch das, was du wolltest?':
      'Deep in it for {0} min with no target set. Is this still what you '
          'wanted?',
  'Setzen': 'Set',
  'So viel niedriger fällt ein Vorfall bei dir im Rückblick aus. Kein Trost — ein Erfahrungswert, den du beim nächsten Mal einkalkulieren kannst.':
      'That is how much lower an incident reads for you in hindsight. Not '
          'reassurance — a figure you can factor in next time.',
  'Solide Mitte.': 'Solid middle.',
  'Speichern': 'Save',
  'Speichern & weiter': 'Save and continue',
  'Spielt fehlende Ereignisse ein. Vorhandene bleiben unberührt — der Import ist wiederholbar, und zwei Geräte gleichen sich an, ohne dass etwas verlorengeht.':
      'Brings in missing events. Existing ones are untouched — the import is '
          'repeatable, and two devices converge without losing anything.',
  'Sport, hart': 'Hard exercise',
  'Sprache': 'Voice',
  'Sprache der Oberfläche': 'Interface language',
  'Spät.': 'Late.',
  'Später': 'Later',
  'Standort und App-Nutzung werden nicht abgefragt — die brauchen erst spätere Module, und dann fragst du selbst danach.':
      'Location and app usage are not requested — later modules need those, '
          'and by then you will ask for them yourself.',
  'Steht.': 'Done.',
  'Stimmung': 'Mood',
  'Stufe {0}': 'Level {0}',
  'Stunden bis zur Frist': 'Hours to the deadline',
  'Stunden bis zur Frist minus dem Anlauf, den die Aufgabe braucht. Wird der Wert negativ, ist der Moment vorbei, in dem Anfangen noch gereicht hätte.':
      'Hours until the deadline minus the run-up the task needs. Once it turns negative, the moment when starting would still have been enough has passed.',
  'Stärkster einzelner Modulator der Kapazität.':
      'Single strongest modulator of capacity.',
  'System': 'System',
  'TAG {0}': 'DAY {0}',
  'TRIGGER': 'TRIGGERS',
  'Tage': 'days',
  'Tageslimit dieser Regel erreicht': 'daily limit for this rule reached',
  'Termin': 'Appointment',
  'Text markieren, teilen, AXIOM wählen. AXIOM steht in der oberen Reihe des Teilen-Blatts, nicht in der App-Liste darunter — immer an derselben Stelle.':
      'Select text, share, pick AXIOM. AXIOM sits in the top row of the share '
          'sheet, not in the app list below it — always in the same place.',
  'Tippen zum Erfassen': 'Tap to capture',
  'Trag einen Termin ein, und AXIOM rechnet rückwärts: wann du losmusst, wann du anfangen musst dich fertigzumachen, und wann Schluss ist mit dem, was du gerade tust.':
      'Enter an appointment and AXIOM works backwards: when you have to leave, '
          'when you have to start getting ready, and when what you are doing '
          'has to stop.',
  'Trigger anlegen': 'Add trigger',
  'Trigger entfernen': 'Remove trigger',
  'Trigger speichern': 'Save trigger',
  'Trigger · {0}': 'Triggers · {0}',
  'UND DANN? (OPTIONAL)': 'AND THEN? (OPTIONAL)',
  'Umgekehrte Richtung: Eine Routine sagt AXIOM, wo du bist. „WLAN Büro verbunden" ist genauer als jeder Kreis auf der Karte — und kostet keine Standortberechtigung.':
      'The other direction: a routine tells AXIOM where you are. “Office Wi-Fi connected” is more precise than any circle on a map — and costs no location permission.',
  'Ungedeckter Bedarf sucht sich den schnellsten Kanal.':
      'Uncovered need finds the fastest channel.',
  'Ungeeicht': 'Uncalibrated',
  'Unsortiert · {0}': 'Unsorted · {0}',
  'Unten rechts, immer sichtbar. Feld ist sofort aktiv, Tastatur offen.':
      'Bottom right, always visible. The field is active immediately, keyboard '
          'open.',
  'Unter 70 %: Der Bedarf deckt sich überwiegend ungeplant — und ungeplant heißt meist über den schnellsten, nicht den besten Kanal.':
      'Below 70 %: the need is mostly covered unplanned — and unplanned '
          'usually means through the fastest channel, not the best one.',
  'Unter 80 %: Der Zustandsvektor wird ungenau, und Regeln feuern auf veralteten Werten. Bevor etwas dazukommt, muss die Erfassung leichter werden.':
      'Below 80 %: the state vector goes fuzzy and rules fire on stale '
          'values. Before anything is added, capture has to get easier.',
  'Unter System → Erfassen findest du alle Wege in die App: Widget, dauerhafte Benachrichtigung mit Direkteingabe, Schnelleinstellung, S-Pen und Sprache. Such dir aus, was bei dir wirklich funktioniert.':
      'Under System → Capture you will find every route into the app: widget, '
          'ongoing notification with direct input, quick setting, S Pen and '
          'voice. Pick whichever actually works for you.',
  'VERDIENT': 'EARNED',
  'VORFALL': 'INCIDENT',
  'VORLAUF {0} MIN': 'LEAD TIME {0} MIN',
  'VORSCHLAG': 'SUGGESTION',
  'Verbrauchte Konzentrationszeit seit heute früh.':
      'Concentration time spent since this morning.',
  'Verlauf · {0}': 'History · {0}',
  'Verschlüsselter Export, Import, Wirkfenster':
      'Encrypted export, import, active window',
  'Verwerfen': 'Discard',
  'Viel möglich heute.': 'A lot is possible today.',
  'Vier Kanäle, getrennt einstellbar. Du kannst leise Hinweise stummschalten und wichtige durchlassen.':
      'Four channels, set separately. You can silence quiet hints and let the '
          'important ones through.',
  'Vier Regler, ungefähr reicht.': 'Four sliders, roughly is fine.',
  'Vier Regler, ungefähr reicht. Ohne einen Anfangswert kann AXIOM nichts berechnen — und würde raten.':
      'Four sliders, roughly is fine. Without a starting value AXIOM cannot '
          'calculate anything — it would be guessing.',
  'Vier Regler. Ungefähr reicht.': 'Four sliders. Roughly is fine.',
  'Vorbei.': 'Past.',
  'Vorfall': 'Incident',
  'Vorfälle': 'Incidents',
  'WARTEZEIT LÄUFT': 'WAITING PERIOD RUNNING',
  'WARTEZEIT VORBEI': 'WAITING PERIOD OVER',
  'WARUM ES DIESE REGEL GIBT': 'WHY THIS RULE EXISTS',
  'WAS VORHER PASSIEREN MUSS': 'WHAT HAS TO HAPPEN FIRST',
  'WAS ZU TUN IST': 'WHAT TO DO',
  'WIEDEREINSTIEG': 'RE-ENTRY',
  'Wann setzt es bei dir ein?': 'When does it set in for you?',
  'War schon': 'Already was',
  'Wartezeit läuft': 'Waiting period running',
  'Wartezeit vorbei': 'Waiting period over',
  'Wartezeit vorbei. Deine Entscheidung.': 'Waiting period over. Your decision.',
  'Was das hier ist': 'What this is',
  'Was dir zwischendurch einfällt, landet hier. Erfassen kannst du von überall — über den Knopf unten, die Schnelleinstellung oder den S-Pen.':
      'Whatever occurs to you in between lands here. You can capture from '
          'anywhere — the button below, the quick setting or the S Pen.',
  'Was ginge beim nächsten Mal anders?': 'What could go differently next time?',
  'Was hier fehlt, deckst du sonst woanders. Trag ein, was bei dir wirklich wirkt — auch wenn es etwas kostet. Gezählt wird es ohnehin.':
      'What is missing here you will cover elsewhere. Enter what actually '
          'works for you — even if it has a cost. It gets counted either way.',
  'Was ist auffällig abgewichen?': 'What deviated noticeably?',
  'Was ist die allererste Handlung?': 'What is the very first action?',
  'Was ist dir gerade eingefallen?': 'What just came to mind?',
  'Was ist heute liegengeblieben, das nicht liegenbleiben durfte?':
      'What was left today that could not be left?',
  'Was kann WEG?': 'What can GO?',
  'Was kostet es, wenn es liegenbleibt?': 'What does leaving it cost?',
  'Was links davon liegt, ist in Reichweite. Was rechts davon liegt, ist heute zu schwer — und wird dir deshalb nicht vorgehalten. Das ist eine Messung, kein Urteil über dich.':
      'What lies left of it is in reach. What lies right of it is too heavy '
          'today — and is therefore not put in front of you. That is a '
          'measurement, not a verdict about you.',
  'Was war der eigentliche Auslöser?': 'What was the actual trigger?',
  'Was wirkt bei dir wirklich?': 'What actually works for you?',
  'Wege in die App: Widget, Benachrichtigung, Stift':
      'Routes into the app: widget, notification, pen',
  'Weiteres': 'More',
  'Welche Regel hat genervt statt geholfen?':
      'Which rule got in the way instead of helping?',
  'Welches Modul ist reif — und welches kann weg?':
      'Which module is ready — and which one can go?',
  'Wenig da. Nur das Nötige.': 'Little available. Essentials only.',
  'Wettkampf': 'Competition',
  'Wie es arbeitet': 'How it works',
  'Wie fällt es heute aus?': 'How does it read today?',
  'Wie hart?': 'How hard?',
  'Wie ist der Stand?': 'Where do things stand?',
  'Wie lang, wie gut?': 'How long, how good?',
  'Wie lange': 'How long',
  'Wie lange hält es an?': 'How long does it last?',
  'Wie lange typischerweise': 'Typically how long',
  'Wie lange warten': 'How long to wait',
  'Wie schwer fällt der Start?': 'How hard is it to start?',
  'Wie schwer fällt dieser Schritt?': 'How hard is this step?',
  'Wie stark': 'How strong',
  'Wie viel exekutive Reserve heute da ist.':
      'How much executive reserve there is today.',
  'Wie war der Tag?': 'How was the day?',
  'Wird geprüft': 'Checking',
  'Wird regelmäßig von höherrangigen Regeln verdrängt — ein Konflikt, den man sonst nie bemerkt.':
      'Regularly displaced by higher-ranking rules — a conflict you would '
          'otherwise never notice.',
  'Wird überwiegend abgelehnt. Eine Regel, die nervt, entwertet auch die anderen.':
      'Mostly dismissed. A rule that grates devalues the others too.',
  'Wirkfenster': 'Active window',
  'Wirkfenster protokollieren': 'Log the active window',
  'Wo? (optional)': 'Where? (optional)',
  'Wobei musst du sein?': 'What do you have to be at?',
  'Wobei willst du eine Wartezeit?': 'What do you want a waiting period for?',
  'Woran hing es?': 'What was it hanging on?',
  'Worauf': 'On what',
  'Wovon habe ich mich lautlos verabschiedet?': 'What did I quietly let go of?',
  'ZEIT IN AXIOM HEUTE': 'TIME IN AXIOM TODAY',
  'ZEITDECKEL': 'TIME CAP',
  'ZERLEGEN': 'SPLIT',
  'ZIEL ≤ {0}': 'TARGET ≤ {0}',
  'ZU ENG': 'TOO NARROW',
  'ZU GROSS FÜR HEUTE': 'TOO BIG FOR TODAY',
  'ZULETZT STEHENGEBLIEBEN': 'WHERE YOU LEFT OFF',
  'Zeigt die nächste Handlung dauerhaft — auch auf dem Sperrbildschirm. Mit einem Tipp auf „Erfassen" tippst du direkt in die Benachrichtigung, ohne zu entsperren und ohne die App zu öffnen.':
      'Shows the next action permanently — on the lock screen too. Tap '
          '“Capture” and you type straight into the notification, without '
          'unlocking and without opening the app.',
  'Zeigt die nächste Handlung und die Kapazität. Tippen auf „ERFASSEN" springt direkt ins Eingabefeld.':
      'Shows the next action and capacity. Tapping “CAPTURE” jumps straight '
          'into the input field.',
  'Zeit im System gegen Zeit gespart': 'Time in the system against time saved',
  'Zeit um. Der Rest wartet bis zum nächsten Mal.':
      'Time is up. The rest waits until next time.',
  'Zeit, die du im System verbringst statt im Leben. Erfassen zählt nicht mit.':
      'Time you spend in the system instead of in your life. Capture does not '
          'count towards it.',
  'Zustand': 'State',
  'Zustand,\nRegel,\neine Handlung.': 'State,\nrule,\none action.',
  'Zwei Zeiten, eine Einschätzung.': 'Two times, one reading.',
  'Zwischen Einfall und Notiz liegen wenige Sekunden. Was in dieser Zeit nicht festgehalten ist, ist weg. Deshalb gibt es mehrere Wege — such dir den, der bei dir wirklich funktioniert.':
      'Between the thought and the note there are a few seconds. What is not '
          'held in that time is gone. So there are several routes — pick the '
          'one that actually works for you.',
  'bis 09:00': 'until 09:00',
  'gar nicht': 'not at all',
  'globales Tageslimit erreicht': 'global daily limit reached',
  'große Hürde': 'high barrier',
  'in {0} min': 'in {0} min',
  'kein Ort': 'no place',
  'keine Daten': 'no data',
  'lief nebenbei': 'ran alongside',
  'oder ein eigener Wert': 'or a value of your own',
  'ständig nachgehalten': 'tracked constantly',
  'vollständig': 'complete',
  'von {0} min': 'of {0} min',
  'vor {0} Stunden · Stärke {1}/5': '{0} hours ago · intensity {1}/5',
  '{0}': '{0}',
  '{0}  ({1}{2})': '{0}  ({1}{2})',
  '{0} %': '{0} %',
  '{0} %  ({1} gesamt)': '{0} %  ({1} total)',
  '{0} Aufgaben gehören woanders hin.': '{0} tasks belong somewhere else.',
  '{0} Nächte · {1} Tage Schritte übernommen':
      '{0} nights · {1} days of steps taken in',
  '{0} Stufe {1} von 5': '{0} level {1} of 5',
  '{0} Stunden': '{0} hours',
  '{0} Vorfälle warten auf Einordnung': '{0} incidents waiting for review',
  '{0} aktive {1} auf geschätzten Gewichten — unten markiert.':
      '{0} active {1} on estimated weights — marked below.',
  '{0} eingeplant.': '{0} scheduled.',
  '{0} erfasst · {1} übernommen · {2} erledigt':
      '{0} captured · {1} taken on · {2} done',
  '{0} erledigt': '{0} done',
  '{0} gespeichert': '{0} saved',
  '{0} in {1} min — {2}.': '{0} in {1} min — {2}.',
  '{0} min': '{0} min',
  '{0} min : {1} min ({2})': '{0} min : {1} min ({2})',
  '{0} min darüber': '{0} min over',
  '{0} min im System': '{0} min in the system',
  '{0} min warten{1}': 'wait {0} min{1}',
  '{0} min · Intensität {1}/5': '{0} min · intensity {1}/5',
  '{0} min über der geplanten Zeit.': '{0} min past the planned time.',
  '{0} min über der geplanten Zeit. Weitermachen ist in Ordnung — bewusst weitermachen auch.':
      '{0} min past the planned time. Carrying on is fine — carrying on '
          'deliberately is too.',
  '{0} min{1}': '{0} min{1}',
  '{0} notiert.': '{0} noted.',
  '{0} startbar · {1} heute außerhalb der Reichweite':
      '{0} startable · {1} out of reach today',
  '{0} um {1}. Fertigmachen.': '{0} at {1}. Get ready.',
  '{0} um {1}. Jetzt zu Ende bringen, was läuft.':
      '{0} at {1}. Finish what is running.',
  '{0} um {1}. Losgehen.': '{0} at {1}. Time to leave.',
  '{0} um {1}. Vorlauf {2} Minuten. {3}':
      '{0} at {1}. Lead time {2} minutes. {3}',
  '{0} von {1} gehalten': '{0} of {1} held',
  '{0} {1} auf Sortieren': '{0} {1} waiting to be sorted',
  '{0} {1} jetzt startbar.': '{0} {1} startable now.',
  '{0}% befolgt': '{0}% followed',
  '{0}-Review': '{0} review',
  '{0}-Review abgeschlossen.': '{0} review finished.',
  '{0}-Review offen · {1} min': '{0} review open · {1} min',
  '{0}/{1} min': '{0}/{1} min',
  '{0}: Blöcke sind auf {1} min begrenzt.':
      '{0}: blocks are capped at {1} min.',
  '{0}: {1} von 100{2}{3}': '{0}: {1} out of 100{2}{3}',
  '{0}:{1} übrig': '{0}:{1} left',
  'ÜBERFÄLLIG': 'OVERDUE',
  'Über 1,0: AXIOM kostet mehr Zeit, als es einbringt. Dann wird zurückgebaut, nicht optimiert — Module abschalten, Regeln streichen.':
      'Above 1.0: AXIOM costs more time than it returns. Then it gets cut '
          'back, not tuned — switch modules off, delete rules.',
  'Übernehmen': 'Take it on',
  'Überspringen': 'Skip',
  'überall': 'anywhere',
  '„Mache ich" wird frei, wenn die Wartezeit um ist.':
      '“Doing it” unlocks once the waiting period is over.',

  // ── Systemcheck und Einrichtung ──────────────────────────────────────
  'Systemcheck': 'System check',
  'Was das Gerät wirklich freigegeben hat': 'What the device has actually granted',
  'Neu prüfen': 'Check again',
  'Gerät': 'Device',
  'Modell': 'Model',
  'Einrichten': 'Set up',
  'Nachsehen': 'Look up',
  'Regelwerk': 'Rulebook',
  'Wege in die App': 'Ways into the app',
  'Bekannte Grenzen': 'Known limits',
  'Damit Erinnerungen ankommen': 'So reminders arrive',
  'Benachrichtigungen': 'Notifications',
  'Freigeben': 'Grant',
  'Freigegeben.': 'Granted.',
  'Auf die Minute genau.': 'Accurate to the minute.',
  'AXIOM darf im Hintergrund aufwachen.': 'AXIOM may wake in the background.',
  'Jede Zeile hier ist eine Aussage des Geräts, keine Vermutung der App. Was markiert ist, erklärt eine Funktion, die nicht tut, was sie soll — der Knopf daneben führt genau dorthin, wo es freigegeben wird.':
      'Every line here is a statement from the device, not a guess by the '
          'app. Whatever is marked explains a function that is not doing what '
          'it should — the button next to it goes straight to where it gets '
          'granted.',
  'Nicht freigegeben. Ohne das bleibt jede Erinnerung stumm — und ein stiller Ausfall fällt erst auf, wenn etwas verpasst ist.':
      'Not granted. Without it every reminder stays silent — and a silent '
          'failure only shows up once something has been missed.',
  'Ohne diese Freigabe kommen Zeitanker ungefähr statt pünktlich — der wirksamste Interventionstyp wird damit wertlos.':
      'Without this, time anchors arrive approximately instead of on time — '
          'which makes the most effective kind of intervention worthless.',
  'Samsung beendet Hintergrund-Apps aggressiv. Ohne Ausnahme feuern Erinnerungen unzuverlässig.':
      'Samsung shuts down background apps aggressively. Without an exception '
          'reminders fire unreliably.',
  'Jetzt hinzufügen': 'Add it now',
  'Widget hinzufügen': 'Add widget',
  '{0} Stück platziert.': '{0} placed.',
  'Noch keins platziert. Samsungs Startbildschirm merkt sich die Widget-Liste einer App und aktualisiert sie nach einem Update nicht zuverlässig — dieser Knopf geht daran vorbei.':
      'None placed yet. Samsung’s home screen caches an app’s widget list and '
          'does not reliably refresh it after an update — this button goes '
          'around that.',
  'Falls es in der Widget-Auswahl fehlt: Samsungs Startbildschirm merkt sich die Liste einer App und aktualisiert sie nach einem Update nicht zuverlässig. Der Knopf hier fragt das System direkt.':
      'If it is missing from the widget picker: Samsung’s home screen caches '
          'an app’s list and does not reliably refresh it after an update. '
          'This button asks the system directly.',
  'Anfrage gestellt — bestätige sie auf dem Startbildschirm.':
      'Request sent — confirm it on the home screen.',
  'Der Startbildschirm nimmt keine Anfrage entgegen. Dann über die Widget-Auswahl: lange auf den Homescreen tippen → Widgets → AXIOM.':
      'The home screen does not accept requests. Use the picker instead: long '
          'press the home screen → Widgets → AXIOM.',
  'Der Startbildschirm nimmt keine Anfrage entgegen. Dann über: lange auf den Homescreen tippen → Widgets → AXIOM.':
      'The home screen does not accept requests. Instead: long press the home '
          'screen → Widgets → AXIOM.',
  'S-Pen und Notiz-Taste': 'S Pen and note button',
  'AXIOM ist die Notiz-App des Systems.': 'AXIOM is the system’s note app.',
  'Der Stift-Doppeltipp fragt nicht nach dem Intent-Filter, sondern nach der Rolle „Notiz-App". Solange die woanders liegt, erscheint AXIOM dort nicht.':
      'The pen double-tap does not look for the intent filter, it looks for '
          'the “note app” role. While that sits elsewhere, AXIOM does not '
          'appear there.',
  'Läuft im Benachrichtigungsbereich.': 'Running in the notification shade.',
  'Aus. Einschalten unter Erfassen — sie braucht die Benachrichtigungsfreigabe von oben.':
      'Off. Switch it on under Capture — it needs the notification permission '
          'above.',
  'Spracheingabe': 'Voice input',
  'Diktieren': 'Dictate',
  'Hört zu …': 'Listening …',
  'Diktieren steht im Erfassungsfeld bereit.':
      'Dictation is ready in the capture field.',
  'Auf diesem Gerät ist keine Spracherkennung installiert.':
      'No speech recognition is installed on this device.',
  'Rein damit — tippen oder sprechen. Sortieren kannst du später.':
      'Get it in — type or speak. You can sort it later.',
  'Direkt beim Erfassen: Das Mikrofon im Eingabefeld diktiert, ohne dass etwas eingerichtet werden muss.':
      'Right at capture: the microphone in the input field dictates, with '
          'nothing to set up.',
  'Health Connect': 'Health Connect',
  'Verbunden, liest Schlaf und Schritte.':
      'Connected, reading sleep and steps.',
  'Vorhanden, aber noch nicht freigegeben.':
      'Present, but not granted yet.',
  'Die Systemkomponente ist zu alt und muss aktualisiert werden.':
      'The system component is too old and needs updating.',
  'Das System meldet Health Connect als nicht vorhanden (Status {0}).':
      'The system reports Health Connect as unavailable (status {0}).',
  'Schlaf und Bewegung aus Health Connect':
      'Sleep and movement from Health Connect',
  'Sieben Wege hinein — Widget, Benachrichtigung, Stift, Sprache':
      'Seven ways in — widget, notification, pen, voice',
  '{0} Regeln, jede lesbar und abschaltbar':
      '{0} rules, each readable and switchable',
  '„Hey Google, Notiz in AXIOM"': '“Hey Google, take a note in AXIOM”',
  'Sprachbefehle über den Assistenten setzen voraus, dass die App über Google Play verteilt wird. Bei einer selbst installierten App prüft Google die Anmeldung nicht — der Befehl bleibt unbekannt. Was stattdessen funktioniert: die Notiz-Rolle oben, eine Bixby-Routine, oder ein Link auf axiom://capture?text=…':
      'Assistant voice commands require the app to be distributed through '
          'Google Play. For a sideloaded app Google never verifies the '
          'registration, so the command stays unknown. What does work: the '
          'note role above, a Bixby routine, or a link to '
          'axiom://capture?text=…',
  '„Hey Google, Notiz in AXIOM" setzt dagegen voraus, dass die App über Google Play verteilt wird — bei einer selbst installierten prüft Google die Anmeldung nicht. Was hier funktioniert: eine Bixby-Routine oder ein Link auf axiom://capture?text=…':
      '“Hey Google, take a note in AXIOM”, on the other hand, requires '
          'distribution through Google Play — for a sideloaded app Google '
          'never verifies the registration. What works here: a Bixby routine '
          'or a link to axiom://capture?text=…',
  'Lockscreen-Widget': 'Lock screen widget',
  'Gibt es auf Android nicht — mit 5.0 entfernt. Die dauerhafte Benachrichtigung ist der verbliebene Weg zu ständiger Sichtbarkeit im gesperrten Zustand.':
      'Does not exist on Android — removed in 5.0. The ongoing notification '
          'is the remaining route to permanent visibility while locked.',
  'Screen-off-Memo mit dem Stift': 'Screen-off memo with the pen',
  'Landet in Samsung Notes. Dafür gibt es keine öffentliche Schnittstelle, jeder Weg dorthin wäre Reverse Engineering und würde das nächste Systemupdate nicht überleben.':
      'Lands in Samsung Notes. There is no public interface for it; any route '
          'in would be reverse engineering and would not survive the next '
          'system update.',
  'Auf dem Desktop gibt es keine Systemrechte zu prüfen. Erfassen, Check-ins und der Regelinspektor laufen trotzdem vollständig.':
      'There are no system permissions to check on the desktop. Capture, '
          'check-ins and the rule inspector still run in full.',

  'Verbindung zum System': 'Connection to the system',
  'Die Brücke antwortet. Alles Weitere hier sind echte Werte des Geräts.':
      'The bridge answers. Everything below is a real value from the device.',
  'Die Brücke antwortet nicht. Dann ist keine Systemfunktion nutzbar und jede Zeile unten steht auf leeren Werten — das ist ein Fehler in AXIOM, nicht am Gerät.':
      'The bridge does not answer. No system function works then, and every '
          'line below sits on empty values — that is a fault in AXIOM, not in '
          'the device.',
  'Das System hat die Anfrage nicht angenommen.':
      'The system did not accept the request.',
  'Die dauerhafte Anzeige gibt es nur auf Android.':
      'The ongoing display only exists on Android.',
  'Erst die Benachrichtigungen freigeben — ohne sie hätte die Anzeige nichts, worin sie erscheinen kann.':
      'Grant notifications first — without them the display has nothing to '
          'appear in.',
  'Aus. Einschalten unter Erfassen → Im Benachrichtigungsbereich bleiben.':
      'Off. Switch it on under Capture → Stay in the notification shade.',
  'Aus — und ohne die Benachrichtigungsfreigabe von oben kann sie auch nicht starten.':
      'Off — and without the notification permission above it cannot start '
          'either.',

  'Das dauert länger als vorgesehen. Bleibt es dabei, sagt System → Systemcheck, ob eine Systemschnittstelle nicht antwortet.':
      'This is taking longer than intended. If it stays that way, System → '
          'System check will say whether a system interface is not '
          'answering.',
  'Die Datenbank braucht ungewöhnlich lange. Hilft ein Neustart der App nicht, ist etwas mit der Datei nicht in Ordnung.':
      'The database is taking unusually long. If restarting the app does not '
          'help, something is wrong with the file.',

  // ── Expertenmodus (ADR-0005) ─────────────────────────────────────────
  'Expertenmodus': 'Expert mode',
  'Regeln und Listen am großen Bildschirm — aus, bis du ihn startest':
      'Rules and lists on a big screen — off until you start it',
  'Regeln schreiben, die Aufgabenliste mit allen Feldern überblicken, den Ereignisstrom lesen — am großen Bildschirm, auf den echten Daten dieses Geräts.':
      'Write rules, see the task list with every field, read the event '
          'stream — on a big screen, on this device’s real data.',
  'AUS': 'OFF',
  'Der Server läuft nur, solange du ihn eingeschaltet lässt. Kein Autostart, kein Wiederanlaufen nach einem Neustart.':
      'The server runs only while you leave it on. No autostart, no restart '
          'after a reboot.',
  'Server starten': 'Start the server',
  'Server beenden': 'Stop the server',
  'Der Server ließ sich nicht starten: {0}': 'The server could not start: {0}',
  'Im Browser öffnen': 'Open in a browser',
  'PIN — gilt nur für diesen Start': 'PIN — valid for this run only',
  'Schaltet sich ohne Anfrage nach 30 Minuten ab.':
      'Shuts down after 30 minutes without a request.',
  'Was das kostet': 'What it costs',
  'AXIOM hat jetzt die Netzwerkberechtigung':
      'AXIOM now holds the network permission',
  'Bis hierher war auf Systemebene ausgeschlossen, dass Daten das Gerät verlassen. Das gilt nicht mehr. Was bleibt: AXIOM lauscht, ruft aber nichts von sich aus auf — kein Netzwerk-Client im Code, und ein Test hält das fest.':
      'Until now it was ruled out at the system level that data could leave '
          'the device. That no longer holds. What remains: AXIOM listens but '
          'never calls out — no network client in the code, and a test pins '
          'that down.',
  'Was ihn wieder ausmacht': 'What turns it off again',
  'Der Browser wird einmal warnen': 'The browser will warn you once',
  'Das Zertifikat ist selbst signiert — keine fremde Stelle bürgt dafür. Statt die Warnung wegzuklicken: den Fingerabdruck oben mit dem vergleichen, den der Browser unter „Zertifikat anzeigen" nennt. Stimmen beide überein, sprichst du mit diesem Telefon und mit nichts dazwischen. Danach merkt sich der Browser die Ausnahme.':
      'The certificate is self-signed — no outside authority vouches for it. '
          'Instead of clicking the warning away: compare the fingerprint '
          'above with the one the browser shows under “View certificate”. If '
          'they match, you are talking to this phone and to nothing in '
          'between. The browser remembers the exception afterwards.',
  'Fingerabdruck des Zertifikats': 'Certificate fingerprint',
  'Muss mit dem übereinstimmen, den der Browser zeigt. Tut er das, ist die Verbindung geprüft — nicht bloß weggeklickt.':
      'Must match the one the browser shows. If it does, the connection has '
          'been verified — not merely clicked away.',
  'Fünf falsche PINs, dreißig Minuten ohne Anfrage, der Knopf hier, oder der Knopf auf der Benachrichtigung. Beim Beenden der App ist er ohnehin weg.':
      'Five wrong PINs, thirty minutes without a request, the button here, or '
          'the one on the notification. Closing the app ends it anyway.',
  'Was dort geht': 'What works there',
  'Aufgaben als Liste': 'Tasks as a list',
  'Alle Felder, alle Zustände, direkt änderbar. Die App zeigt bewusst nur eine Handlung — Planen ist etwas anderes als Entscheiden im Moment.':
      'Every field, every state, editable in place. The app deliberately '
          'shows one action — planning is not the same as deciding in the '
          'moment.',
  'Regelwerk im YAML': 'Rulebook as YAML',
  'Ungültiges wird abgelehnt, nicht übersprungen. Jede gespeicherte Änderung läuft sieben Tage stumm mit — dieselbe Zusage wie im Editor hier.':
      'Invalid input is rejected, not skipped. Every saved change runs '
          'silently for seven days — the same promise as in the editor here.',
  'Zustand und Ereignisstrom': 'State and event stream',
  'Die Werte mit ihrer Herleitung, und darunter der Strom, aus dem sie gerechnet werden. Nur lesend — Ereignisse sind unveränderlich.':
      'The values with their derivation, and below them the stream they are '
          'calculated from. Read-only — events are immutable.',

  // ── Regeleditor ──────────────────────────────────────────────────────
  'Neue Regel': 'New rule',
  'Bearbeiten': 'Edit',
  'Geführt, mit Vorschau gegen den Zustand von jetzt':
      'Guided, previewed against the state right now',
  'Wie sie heißt': 'What it is called',
  'Kurz und in deiner Sprache': 'Short, in your own words',
  'Dieser Satz steht später in der Meldung. Kein Vorwurf, keine Frage — eine Feststellung.':
      'This sentence ends up in the message. No blame, no question — a '
          'statement.',
  'Wann sie zutrifft': 'When it applies',
  'Was dann passiert': 'What happens then',
  'Text der Meldung (optional)': 'Text of the message (optional)',
  'Warum es sie gibt': 'Why it exists',
  'Was diese Regel verhindern oder auslösen soll':
      'What this rule should prevent or set off',
  'Pflichtfeld. Jede Ausgabe von AXIOM nennt ihre Regel und diese Begründung — ohne sie wäre die Empfehlung eine Behauptung.':
      'Required. Every output names its rule and this reasoning — without it '
          'the recommendation would be an assertion.',
  'Worauf sie einzahlt': 'What it serves',
  'Wie laut': 'How loud',
  'Regel aktiv': 'Rule active',
  'Ausgeschaltet bleibt sie erhalten, wird aber nicht ausgewertet.':
      'Switched off it is kept but not evaluated.',
  'Mindestabstand': 'Minimum interval',
  'Höchstens pro Tag': 'At most per day',
  'Rang bei Gleichstand': 'Rank on a tie',
  'kein Limit': 'no limit',
  'min': 'min',
  'mal': 'times',
  'Ohne Abstand entsteht Benachrichtigungsflut — der häufigste Grund, warum solche Apps wieder gelöscht werden.':
      'Without an interval you get a flood of notifications — the most common '
          'reason apps like this get deleted again.',
  'Eine harte Obergrenze zusätzlich zum Abstand.':
      'A hard ceiling on top of the interval.',
  'Feuern zwei Regeln gleichzeitig, gewinnt die mit dem höheren Rang. Bei Gleichstand entscheidet die Nummer — nie der Zufall.':
      'If two rules fire at once, the higher rank wins. On a tie the number '
          'decides — never chance.',
  'ALLE': 'ALL',
  'EINE VON': 'ONE OF',
  'NICHT': 'NOT',
  'IST': 'IS',
  'IST NICHT': 'IS NOT',
  'Gruppe': 'Group',
  'Gruppe entfernen': 'Remove group',
  'Bedingung entfernen': 'Remove condition',
  'von': 'from',
  'bis': 'to',
  'nie': 'never',
  'jetzt: {0}': 'now: {0}',
  'Über Mitternacht hinweg erlaubt — 22:00 bis 05:00 meint die Nacht.':
      'Crossing midnight is allowed — 22:00 to 05:00 means the night.',
  'Ein Ereignis, das nie eintrat, gilt als unendlich lange her. Für „läuft seit" braucht es zusätzlich eine Bedingung darauf, dass überhaupt etwas läuft.':
      'An event that never happened counts as infinitely long ago. For '
          '“running since” you also need a condition that something is '
          'running at all.',
  'Trifft mit dem Zustand von jetzt zu.':
      'Applies to the state right now.',
  'Trifft mit dem Zustand von jetzt nicht zu.':
      'Does not apply to the state right now.',
  'Noch unvollständig — unten steht, was fehlt.':
      'Still incomplete — what is missing is listed below.',
  'Fehlt noch': 'Still missing',
  'Der Titel fehlt. Er steht später in der Meldung.':
      'The title is missing. It ends up in the message.',
  'Die Begründung ist zu kurz. Sie erscheint im Systeminspektor und muss in einem halben Jahr noch erklären, warum es diese Regel gibt.':
      'The reasoning is too short. It appears in the rule inspector and has '
          'to still explain in six months why this rule exists.',
  'Ohne Abstand meldet sich die Regel beliebig oft.':
      'Without an interval the rule can speak up arbitrarily often.',
  'SIEBEN TAGE STUMM': 'SEVEN DAYS SILENT',
  'Die Regel läuft ab dem Speichern mit und wird protokolliert, sagt aber nichts. Im Systeminspektor siehst du, wie oft sie gefeuert hätte — danach entscheidest du, ob sie das wirklich soll.':
      'From saving on, the rule runs along and gets logged but says nothing. '
          'The rule inspector shows how often it would have fired — then you '
          'decide whether it really should.',
  'Gespeichert. Die Regel läuft sieben Tage stumm mit — im Systeminspektor siehst du, wie oft sie gefeuert hätte.':
      'Saved. The rule runs silently for seven days — the rule inspector '
          'shows how often it would have fired.',
  'Auf Auslieferungsstand zurücksetzen': 'Reset to the shipped version',
  'Regel entfernen': 'Remove rule',
  'Zurückgesetzt auf die mitgelieferte Fassung.':
      'Reset to the shipped version.',
  'Regel entfernt. Die Nummer wird nicht wiederverwendet.':
      'Rule removed. The number will not be reused.',
  'ALS YAML': 'AS YAML',
  'Als YAML zeigen': 'Show as YAML',
  'Genau so kann die Regel nach rules/ zurück — der Editor ist keine Einbahnstraße.':
      'Exactly like this the rule can go back into rules/ — the editor is not '
          'a one-way street.',
  'Kopieren': 'Copy',
  'Bearbeitet': 'Edited',

  // Wortschatz des Regelwerks. Läuft über Variablen durch die Übersetzung
  // und ist deshalb im Quelltext nicht als Literal zu finden.
  'Zahl': 'Number',
  'Auswahl': 'Choice',
  'Uhrzeit': 'Time of day',
  'Seit einem Ereignis': 'Since an event',
  'Anzahl heute': 'Count today',
  'kleiner als': 'less than',
  'höchstens': 'at most',
  'mindestens': 'at least',
  'größer als': 'greater than',
  'genau': 'exactly',
  'nicht': 'not',
  'Laststufe': 'Load level',
  'Was gerade läuft': 'What is running',
  'Wochentag': 'Weekday',
  'erhöht': 'raised',
  'kritisch': 'critical',
  'nichts': 'nothing',
  'Reiz-Slot': 'Stimulation slot',
  'Erfassung': 'Capture',
  'Aufgabe erledigt': 'Task completed',
  'Aufgabe begonnen': 'Task started',
  'Fokus gestartet': 'Focus started',
  'Fokus beendet': 'Focus ended',
  'Impuls abgefangen': 'Impulse intercepted',
  'Körpersignal quittiert': 'Body signal acknowledged',
  'Schlaf eingetragen': 'Sleep logged',
  'Review abschlossen': 'Review finished',
  'Einnahme': 'Intake',
  'Review abgeschlossen': 'Review finished',

  // Bedeutung der Größen — steht im Editor unter jeder Auswahl.
  'Wie viel exekutive Reserve heute da ist. Hoch heißt: es geht viel.':
      'How much executive reserve there is today. High means a lot is '
          'possible.',
  'Puffer für emotionale Belastung. Niedrig heißt: Impulse kommen leichter durch.':
      'Headroom for emotional load. Low means impulses get through more '
          'easily.',
  'Kumulierter Aufwand, den Alltag zu strukturieren. Der Wert, der einen Absturz ankündigt, bevor er sichtbar wird.':
      'Accumulated effort of structuring everyday life. The value that '
          'announces a collapse before it becomes visible.',

  // Aktionen einer Regel.
  'Hinweis zeigen': 'Show a hint',
  'Ein Satz, mehr nicht. Die häufigste und harmloseste Aktion.':
      'One sentence, nothing more. The most common and most harmless action.',
  'Check-in anstoßen': 'Prompt a check-in',
  'Fragt die vier Regler ab.': 'Asks for the four sliders.',
  'Aufgabe vorschlagen': 'Suggest a task',
  'Schlägt die passendste startbare Aufgabe vor.':
      'Suggests the most fitting startable task.',
  'Zum Zerlegen auffordern': 'Ask to split it',
  'Wenn etwas Wichtiges außer Reichweite liegt: zerlegen statt anmahnen.':
      'When something important is out of reach: split it instead of nagging.',
  'Reiz-Slot vorschlagen': 'Suggest a stimulation slot',
  'Deckt den Bedarf geplant, bevor er sich den schnellsten Kanal sucht.':
      'Covers the need on purpose, before it finds the fastest channel.',
  'Wartezeit setzen': 'Set a waiting period',
  'Kein Verbot — nur Latenz zwischen Impuls und Handlung.':
      'No ban — only latency between impulse and action.',
  'Fokus schützen': 'Protect focus',
  'Unterdrückt Benachrichtigungen, solange der Block läuft.':
      'Suppresses notifications while the block runs.',
  'Deutlich unterbrechen': 'Interrupt clearly',
  'Nur mit belegbarem Grund. Eine falsch getimte Unterbrechung zerstört den wertvollsten Zustand, den dieses Profil hat.':
      'Only with a demonstrable reason. A badly timed interruption destroys '
          'the most valuable state this profile has.',
  'Zeitanker setzen': 'Set a time anchor',
  'Legt einen Ankerschritt an.': 'Creates an anchor step.',
  'Laststufe setzen': 'Set the load level',
  'Hebt oder senkt die Stufe, aus der die Konsequenzen folgen.':
      'Raises or lowers the level the consequences follow from.',
  'Konfiguration sperren': 'Lock configuration',
  'Nur Pflicht und Erholung. Ein Erfolg des Systems, kein Scheitern.':
      'Obligations and recovery only. A success of the system, not a failure.',
  'Der Meta-Guard gegen sich selbst (M12).':
      'The meta-guard against itself (M12).',
  'Nur mitschreiben (SHADOW)': 'Only record (SHADOW)',
  'Läuft stumm mit und wird protokolliert. Der Zustand, in dem jede neue Regel beginnt.':
      'Runs along silently and gets logged. The state every new rule starts '
          'in.',

  // ── Anzeige-Einstellungen ────────────────────────────────────────────
  'Textgröße': 'Text size',
  'Helligkeit': 'Brightness',
  'Farbschema': 'Colour scheme',
  'AUTO': 'AUTO',
  'DUNKEL': 'DARK',
  'HELL': 'LIGHT',

  // Bezeichnungen der Aufzaehlungen. Sie laufen ueber eine Variable durch
  // die Uebersetzung (context.t(size.label)) und sind deshalb im Quelltext
  // nicht als Literal zu finden — i18n_test prueft sie getrennt.
  'Kompakt': 'Compact',
  'Normal': 'Normal',
  'Groß': 'Large',
  'Sehr groß': 'Very large',
  'Instrument': 'Instrument',
  'Kontrast': 'Contrast',
  'Gedämpft': 'Muted',

  // ── Texte, die nicht aus dem Screen-Quelltext stammen ────────────────
  // Widget, Benachrichtigungen und Kern-Saetze. Sie erscheinen ausserhalb
  // der App und muessen dieselbe Sprache sprechen wie sie.
  'Los nach {0}. {1} um {2}.': 'Head to {0}. {1} at {2}.',
  'Nichts in Reichweite': 'Nothing in reach',
  'Nichts anliegend': 'Nothing pending',
  'Zerlegen hilft': 'Splitting helps',
  'Regel {0}': 'Rule {0}',
  'Start {0}/10': 'Start {0}/10',
  'ohne Anker': 'no anchor',
  'Ausgelöst durch:': 'Triggered by:',
  'IN {0} H': 'IN {0} H',
  'IN {0} T': 'IN {0} D',
  'abgeschaltet': 'switched off',

  // Wochentage und Monate. Bewusst hier und nicht ueber `intl`: Es sind
  // neunzehn Woerter, und eine weitere Abhaengigkeit waere teurer.
  'Montag': 'Monday',
  'Dienstag': 'Tuesday',
  'Mittwoch': 'Wednesday',
  'Donnerstag': 'Thursday',
  'Freitag': 'Friday',
  'Samstag': 'Saturday',
  'Sonntag': 'Sunday',
  'Januar': 'January',
  'Februar': 'February',
  'April': 'April',
  'Mai': 'May',
  'Juni': 'June',
  'Juli': 'July',
  'August': 'August',
  'September': 'September',
  'Oktober': 'October',
  'November': 'November',
  'Dezember': 'December',
  'Der Weg, der auf aktuellen Galaxy-Geräten funktioniert: Stift herausziehen, im Air-Command-Menü auf AXIOM tippen. Einrichten unter Einstellungen → Erweiterte Funktionen → S Pen → Air Command → Verknüpfungen → AXIOM.':
      'The route that works on current Galaxy devices: pull out the pen, tap AXIOM in the Air command menu. Set it up under Settings → Advanced features → S Pen → Air command → Shortcuts → AXIOM.',
  'Air Actions — der Stiftknopf als Fernbedienung — gibt es auf dem Galaxy S25 Ultra nicht mehr: Dessen Stift hat kein Bluetooth. Die Rolle „Notiz-App" für den Doppeltipp schaltet Samsung in One UI ebenfalls nicht frei. Screen-off-Memos landen weiterhin in Samsung Notes, dafür gibt es keine offene Schnittstelle.':
      'Air actions — the pen button as a remote — are gone on the Galaxy S25 Ultra: that pen has no Bluetooth. Samsung does not expose the „note app" role for the double tap in One UI either. Screen-off memos still land in Samsung Notes; there is no open interface for them.',
  'Notiz-Rolle anfragen':
      'Request the note role',
  'Dieses Gerät bietet die Rolle nicht an. Der Weg zum Stift führt über Air Command → Verknüpfungen.':
      'This device does not offer the role. The route to the pen runs through Air command → Shortcuts.',
  'Stiftknopf als Fernbedienung':
      'Pen button as a remote',
  'Der S Pen des Galaxy S25 Ultra hat kein Bluetooth Low Energy. Damit entfallen Air Actions, Kopplung und Laden — nicht nur für AXIOM, sondern für alle Apps. Was bleibt, ist das Air-Command-Menü: Stift herausziehen, AXIOM antippen. Als Verknüpfung eingetragen sind das zwei Handgriffe.':
      'The Galaxy S25 Ultra S Pen has no Bluetooth Low Energy. That removes air actions, pairing and charging — for every app, not just AXIOM. What remains is the Air command menu: pull out the pen, tap AXIOM. Entered as a shortcut, that is two moves.',
  'Der Dienst wurde gestartet, aber es hängt keine Benachrichtigung. Meistens ist der Kanal „Dauerhafte Anzeige" in den Benachrichtigungseinstellungen abgeschaltet, oder die Akkuoptimierung beendet den Dienst sofort wieder.':
      'The service started, but no notification is showing. Usually the „Persistent display" channel is switched off in the notification settings, or battery optimisation stops the service right away.',
  'Was das System dazu sagt':
      'What the system says about it',
  'Benachrichtigungen freigegeben':
      'Notifications allowed',
  'Kanal „Dauerhafte Anzeige" eingeschaltet':
      'Channel „Persistent display" switched on',
  'Dienst gestartet':
      'Service started',
  'Benachrichtigung hängt':
      'Notification is showing',
  'Kanal öffnen':
      'Open the channel',
  'Akkuoptimierung':
      'Battery optimisation',
  '{0} von {1} min':
      '{0} of {1} min',
  'Zurücklegen':
      'Put it back',
  'Ab wann tut es weh?':
      'When does it start to hurt?',
  'Treibt die Dringlichkeit. Kein Termin, keine Mahnung.':
      'Drives urgency. Not an appointment, not a reminder.',
  'offen':
      'open',
  'heute':
      'today',
  'morgen':
      'tomorrow',
  'diese Woche':
      'this week',
  'Datum …':
      'Pick a date …',
  'Aufgaben':
      'Tasks',
  'Alles Eingetragene, in der Reihenfolge der Auswahl':
      'Everything on file, in the order the system picks',
  'Die Reihenfolge ist die der Auswahl — dieselbe Formel, kein zweiter Maßstab. Sie lässt sich hier nicht umstellen.':
      'The order is the one the system picks by — same formula, no second yardstick. It cannot be changed here.',
  'In Reichweite · {0}':
      'Within reach · {0}',
  'Nicht in Reichweite · {0}':
      'Not within reach · {0}',
  'Startenergie über der heutigen Kapazität ({0}). Zerlegen macht sie erreichbar.':
      'Start energy above today’s capacity ({0}). Breaking them down brings them within reach.',
  'Erledigt · {0}':
      'Done · {0}',
  'NICHTS EINGETRAGEN':
      'NOTHING ON FILE',
  'Keine Aufgaben.':
      'No tasks.',
  'Was du erfasst, landet zuerst im Eingang. Nach dem Sortieren steht es hier.':
      'What you capture lands in the inbox first. After sorting it shows up here.',
  '/ {0} min heute':
      '/ {0} min today',
  'min offen':
      'min available',
  'abgelaufen':
      'time is up',
  'Pille und Now Bar':
      'Pill and Now Bar',
  'Live Updates gibt es erst ab Android 16.':
      'Live updates start with Android 16.',
  'Die nächste Handlung steht neben der Uhr und in der Now Bar.':
      'The next action sits next to the clock and in the Now Bar.',
  'Das System hat die Beförderung abgelehnt. Die Pille ist für zeitlich begrenzte Vorgänge gedacht — eine dauerhafte Anzeige zählt nicht immer dazu. Als Benachrichtigung bleibt sie sichtbar.':
      'The system turned the promotion down. The pill is meant for time-bound activities, and a persistent display does not always count as one. It stays visible as a notification.',
  'Erst die dauerhafte Anzeige einschalten — die Pille zeigt sie, nicht umgekehrt.':
      'Switch on the persistent display first — the pill shows it, not the other way round.',
  'Samsungs Now Bar':
      'Samsung’s Now Bar',
  'Es gibt keine eigene Samsung-Schnittstelle dafür. One UI 8 füllt die Now Bar aus den Live Updates von Android 16 — dieselbe Bitte, die AXIOM stellt. Angenommen wird sie für zeitlich begrenzte Vorgänge zuverlässig, für eine dauerhafte Anzeige nicht garantiert. Die Zeile oben sagt, wie es auf diesem Gerät ausgegangen ist.':
      'There is no separate Samsung interface for it. One UI 8 fills the Now Bar from Android 16’s live updates — the same request AXIOM makes. It is granted reliably for time-bound activities, not guaranteed for a persistent display. The row above says how it went on this device.',
  'Freiwillig':
      'Optional',
  'Schlaf und\nSchritte.':
      'Sleep and\nsteps.',
  'Der Schlaf der letzten Nächte ist der stärkste Einzelfaktor der Kapazität. Selbst eingetragen fehlt er genau an den Tagen, an denen er zählt — deshalb liest AXIOM ihn lieber aus Health Connect.':
      'The last few nights of sleep are the single strongest factor in capacity. Entered by hand it is missing on exactly the days it matters — so AXIOM would rather read it from Health Connect.',
  'WAS GELESEN WIRD':
      'WHAT IS READ',
  'Schlafzeiten und Schritte pro Tag. Sonst nichts — kein Puls, kein Gewicht, kein Standort. Geschrieben wird nie: AXIOM legt nichts in Health Connect ab.':
      'Sleep times and steps per day. Nothing else — no heart rate, no weight, no location. Nothing is ever written: AXIOM puts nothing into Health Connect.',
  'Die Daten bleiben auf dem Gerät und gehen in zwei Werte ein: Kapazität und Schlafschuld. Beides steht unter Zustand mit seiner Herleitung.':
      'The data stays on the device and feeds two values: capacity and sleep debt. Both appear under State with their derivation.',
  'Health Connect verbinden':
      'Connect Health Connect',
  'Wird geprüft …':
      'Checking …',
  'Auf diesem Gerät nicht vorhanden. AXIOM rechnet dann aus den Check-ins.':
      'Not present on this device. AXIOM then works from your check-ins.',
  'Verbunden. Der erste Import holt die letzten vier Wochen.':
      'Connected. The first import fetches the last four weeks.',
  'Öffnet die Freigabe von Health Connect. Du wählst dort selbst, was AXIOM sehen darf.':
      'Opens the Health Connect permission screen. You choose there what AXIOM may see.',
  'Das lässt sich jederzeit ändern — unter System → Systemcheck, in beide Richtungen. Ohne Health Connect fehlt AXIOM nichts Grundsätzliches, nur Genauigkeit.':
      'This can be changed at any time — under System → System check, in both directions. Without Health Connect nothing fundamental is missing, only precision.',
  'Health Connect gibt es nur auf Android. Auf dem Desktop rechnet AXIOM aus deinen Check-ins.':
      'Health Connect only exists on Android. On the desktop AXIOM works from your check-ins.',
  'Nur auf\nAndroid.':
      'Android\nonly.',
  'Health Connect gibt es nur auf Android. Auf dem Desktop rechnet AXIOM aus deinen Check-ins — dieselben Regeln, nur eine Quelle weniger.':
      'Health Connect only exists on Android. On the desktop AXIOM works from your check-ins — same rules, one source fewer.',
  'Der Name wird im Netz angesagt':
      'The name is announced on the network',
  'Damit „axiom.local" aufgeht, beantwortet AXIOM Namensanfragen im lokalen Netz. Das Paket geht an eine Adresse, die kein Router weiterleitet, enthält nur Name und IP dieses Geräts, und läuft nur, solange der Server läuft. Beim Beenden wird der Name zurückgenommen.':
      'For „axiom.local" to resolve, AXIOM answers name queries on the local network. The packet goes to an address no router forwards, carries only this device’s name and IP, and runs only while the server runs. On shutdown the name is withdrawn.',
  'Falls der Name nicht aufgeht — in manchen Netzen ist Multicast gesperrt:':
      'If the name does not resolve — some networks block multicast:',
  'Zeit im System heute':
      'Time in the system today',
  'Minuten in AXIOM selbst, ohne Erfassung. Die einzige Zahl hier, die nicht den Nutzer misst, sondern die App — G4.':
      'Minutes inside AXIOM itself, capture excluded. The only number here that measures the app rather than the person — G4.',
  'Regelwerk heute zu':
      'Rulebook closed for today',
  '{0} Minuten im System sind heute verbraucht. Regeln zu schreiben ist ab jetzt bis morgen zu. Erfassen, Arbeiten und Nachsehen bleiben offen — und eine Regel abschalten geht weiterhin.':
      '{0} minutes in the system are used up today. Writing rules is closed until tomorrow. Capture, work and looking things up stay open — and switching a rule off still works.',
  'Das ist keine Strafe, sondern der Zweck: Ein System zu bauen ist immer stimulierender als die Aufgabe, für die es gebaut wurde.':
      'This is not a punishment, it is the point: building a system is always more stimulating than the task it was built for.',
  'Verstanden':
      'Understood',
  'FREIGABE ANGEFRAGT':
      'APPROVAL REQUESTED',
  'Steht dieselbe Zahl auf dem Bildschirm, vor dem du sitzt?':
      'Is the same number on the screen you are sitting at?',
  'Wenn nicht, hat jemand anders angefragt. Dann ablehnen — das kostet nichts außer einem zweiten Versuch.':
      'If not, someone else asked. Then decline — it costs nothing but a second attempt.',
  'Stimmt überein':
      'Numbers match',
  'Stimmt nicht':
      'Does not match',
  'Mitstarten, wenn AXIOM aufgeht':
      'Start together with AXIOM',
  'Nicht beim Hochfahren und nicht ohne die App — nur, wenn du sie öffnest. Anmeldung, dauerhafte Anzeige und die Abschaltung nach dreißig Minuten Leerlauf bleiben.':
      'Not at boot and not without the app — only when you open it. Sign-in, the persistent display and the shutdown after thirty idle minutes all stay.',
  'Zerlegen':
      'Split',
  'Zerlegt · {0}':
      'Split · {0}',
  'SCHRITTE OFFEN: {0}':
      'STEPS OPEN: {0}',
  'Diese Aufgaben sind durch ihre Teilschritte vertreten. Sie kommen zurück, sobald kein Schritt mehr offen ist.':
      'These tasks are represented by their steps. They come back once no step is open any more.',

  // Hilfe
  'Wozu jeder Bildschirm da ist und wie eine Regel entscheidet':
      'What each screen is for, and how a rule decides',
  'Die Hilfe braucht ungewöhnlich lange. Sie liegt in der App, nicht im Netz — ein Neustart hilft hier fast immer.':
      'The help is taking unusually long. It sits inside the app, not on the network — a restart almost always sorts it out.',
  'In der Hilfe suchen':
      'Search the help',
  'Suche zurücksetzen':
      'Clear the search',
  'Suchen':
      'Search',
  '{0} Fundstellen':
      '{0} places found',
  'KEIN TREFFER':
      'NO MATCH',
  'Dazu steht nichts in der Hilfe':
      'The help says nothing about that',
  'Gesucht wird im Text der Kapitel, ohne Wortstammerkennung. Ein kürzeres Wort trifft oft mehr.':
      'The search runs over the chapter text, without stemming. A shorter word often matches more.',
  'KEINE KAPITEL':
      'NO CHAPTERS',
  'Die Hilfe ist nicht mitgeliefert':
      'The help is not bundled',
  'Unter assets/help/de/ liegt keine Textdatei. Die App läuft davon unberührt weiter — es gibt nur nichts nachzulesen.':
      'There is no text file under assets/help/de/. The app runs untouched by that — there is simply nothing to read up on.',
  'Die Übersicht fehlt. Die Kapitel selbst sind da — hier stehen sie so, wie sie im Verzeichnis liegen.':
      'The overview is missing. The chapters themselves are here — listed the way they sit in the directory.',
  'Dieses Kapitel gibt es noch nicht auf Englisch. Hier steht die deutsche Fassung.':
      'This chapter has no English version yet. What follows is the German one.',
  'Kapitel {0} gibt es nicht.':
      'There is no chapter {0}.',
  'NICHT GELADEN':
      'NOT LOADED',
  'Dieses Kapitel fehlt':
      'This chapter is missing',
  'Die Datei ist nicht mitgeliefert. Die anderen Kapitel sind davon unberührt.':
      'The file is not bundled. The other chapters are untouched by that.',
  'IN DIESEM KAPITEL':
      'IN THIS CHAPTER',
  'Kapitel {0}':
      'Chapter {0}',
  'Übersicht':
      'Overview',
  'Hilfe':
      'Help',
  'Bild fehlt':
      'Image missing',

  // ── Systemseite: was Android zeigt, nicht AXIOM ─────────────────────
  // Quelle: lib/platform/system_texts.dart. Diese Saetze erscheinen in
  // Benachrichtigungen, im Widget und in der Schnelleinstellung.
  'Hinweise':
      'Notices',
  'Erscheint nur im Rückblick.':
      'Only shows up in review.',
  'Leise Anstöße':
      'Quiet nudges',
  'Still, wegwischbar.':
      'Silent, swipeable.',
  'Interventionen':
      'Interventions',
  'Sichtbar, erwartet eine Antwort.':
      'Visible, expects an answer.',
  'Verbindliche Regeln':
      'Binding rules',
  'Nur für Regeln, die du selbst verbindlich gesetzt hast.':
      'Only for rules you made binding yourself.',
  'Zeigt die nächste Handlung. Still, ohne Ton.':
      'Shows the next action. Silent, no sound.',
  'Laufender Slot':
      'Running slot',
  'Fokus und Reiz-Slots, solange sie laufen. Still.':
      'Focus and sensation slots while they run. Silent.',
  'Sichtbar, solange der lokale Server läuft.':
      'Visible while the local server runs.',
  'Was ist dir eingefallen?':
      'What came to mind?',
  'Erfasst':
      'Captured',
  'Slot läuft':
      'Slot running',
  'Beenden':
      'End',
  'noch {0} von {1} min':
      '{0} of {1} min left',
  '{0} min über den Bezugspunkt':
      '{0} min past the reference point',
  '+{0} min':
      '+{0} min',
  'Expertenmodus läuft':
      'Expert mode is running',
  'Verschlüsselt mit einem selbst signierten Zertifikat. Ohne Anfrage schaltet sich der Server nach 30 Minuten ab.':
      'Encrypted with a self-signed certificate. Without a request the server shuts down after 30 minutes.',
  'Gedanken in AXIOM festhalten':
      'Hold on to a thought in AXIOM',
  'In AXIOM erfassen':
      'Capture in AXIOM',
  'Sprich einfach.':
      'Just speak.',
  'Diese Funktion gibt es nur auf Android.':
      'This only exists on Android.',
  'Das System hat nicht geantwortet. Die Funktion bleibt aus, die App läuft weiter.':
      'The system did not answer. The function stays off, the app keeps running.',
  'Das System hat nicht geantwortet.':
      'The system did not answer.',
  'Die Systembrücke antwortet nicht. Das ist ein Fehler in AXIOM, nicht am Gerät.':
      'The system bridge is not answering. That is a fault in AXIOM, not on the device.',
  'Dieser Startbildschirm nimmt keine Anfrage entgegen. Dann über die Widget-Auswahl: lange auf den Homescreen tippen → Widgets → AXIOM.':
      'This home screen takes no such request. Then via the widget picker: long-press the home screen → Widgets → AXIOM.',
  'Der Startbildschirm hat die Anfrage abgelehnt.':
      'The home screen declined the request.',
  'Anfrage fehlgeschlagen: {0}':
      'Request failed: {0}',
  'Die Rolle „Notiz-App" gibt es erst ab Android 14.':
      'The “note-taking app” role exists only from Android 14 on.',
  'Dieses Gerät bietet die Rolle „Notiz-App" nicht an — Samsung schaltet sie in One UI nicht frei. Der Weg zum Stift führt hier über das Air-Command-Menü: Einstellungen → Erweiterte Funktionen → S Pen → Air Command → Verknüpfungen → AXIOM.':
      'This device does not offer the “note-taking app” role — Samsung does not enable it in One UI. The way to the pen here is the Air Command menu: Settings → Advanced features → S Pen → Air Command → Shortcuts → AXIOM.',
  'Der Systemdialog ließ sich nicht öffnen: {0}':
      'The system dialog would not open: {0}',
  'Der Benachrichtigungskanal „Dauerhafte Anzeige" ist abgeschaltet. Einstellungen → Benachrichtigungen → AXIOM → Dauerhafte Anzeige.':
      'The notification channel “Always visible” is switched off. Settings → Notifications → AXIOM → Always visible.',
  'Benachrichtigungen sind für AXIOM abgeschaltet. Ohne sie hat die Anzeige nichts, worin sie erscheinen kann.':
      'Notifications are switched off for AXIOM. Without them the display has nothing to appear in.',
  'Das System hat den Dienst abgelehnt: {0}':
      'The system declined the service: {0}',
  'Health Connect meldet sich als nicht nutzbar (Status {0}). Ohne den Dienst gibt es nichts freizugeben.':
      'Health Connect reports itself as unusable (status {0}). Without the service there is nothing to grant.',
  'Die Berechtigungsabfrage ließ sich nicht öffnen: {0}':
      'The permission request would not open: {0}',
  'Health Connect ist installiert, öffnet aber keinen Freigabedialog ({0}). In den Systemeinstellungen unter Health Connect lässt sich AXIOM dort von Hand freigeben.':
      'Health Connect is installed but opens no permission dialog ({0}). In the system settings under Health Connect, AXIOM can be granted access by hand.',

  // ── Blocker: „A blockiert B" ──────────────────────────────────────────
  //
  // „Wartet", nicht „blockiert": Der Zustand `blocked` heißt in AXIOM
  // zerlegt. Im Englischen dieselbe Trennung — „waiting" gegen „split".
  'Wartet · {0}': 'Waiting · {0}',
  'Diese Aufgaben hängen an einer anderen. Sie kommen zurück, sobald ihr letzter Blocker erledigt ist.':
      'These tasks hang on another one. They come back as soon as their last blocker is done.',
  'wartet auf: {0}': 'waiting for: {0}',
  'wartet auf: {0} und {1}': 'waiting for: {0} and {1}',
  'wartet auf: {0} und {1} weitere': 'waiting for: {0} and {1} more',
  'eine andere Aufgabe': 'another task',
  'HÄLT {0} AUF · HEBEL ×{1}': 'HOLDS UP {0} · LEVERAGE ×{1}',
  'Was anderes aufhält, zählt mehr: Wert × (1 + 0,35 × log2(1 + aufgehaltene)). Drei aufgehaltene heben den Wert um 70 %, nicht um 200 %.':
      'What holds up other work counts for more: value × (1 + 0.35 × log2(1 + held up)). Three held up raise the value by 70 %, not by 200 %.',
  'ALLES WARTET': 'EVERYTHING IS WAITING',
  'Alles Offene hängt an etwas anderem.': 'Everything open hangs on something else.',
  'Jede offene Aufgabe wartet auf einen Blocker, der selbst noch aussteht. Die Aufgabenliste zeigt, worauf.':
      'Every open task waits on a blocker that is itself still open. The task list shows on what.',
  'Ansehen, was wartet': 'See what is waiting',
  'LEICHT':
      'EASY',
  'HIER':
      'HERE',
  'SCHWER':
      'HARD',
};
