# AXIOM — Arbeitsanweisung

Deterministisches, lokal laufendes Regelwerk zur Selbstregulation. Ein Exocortex für ein
hochkompensiertes ADHS-Zielprofil (kombinierter Typus, starker Systemizing-Drive, High Sensation
Seeking). **Ein Nutzer, ein Gerät, privat.** Kein Produkt, kein Store, keine Nutzerbasis.

Kontext vor jeder inhaltlichen Arbeit: [`docs/00-KONZEPT.md`](docs/00-KONZEPT.md) und
[`docs/01-PROFIL-DEFIZITE.md`](docs/01-PROFIL-DEFIZITE.md). Letzteres beschreibt ein
**Zielprofil**, keine Person — siehe die Vorbemerkung dort.

---

## Die vier Systemgesetze

Jeder Zielkonflikt wird zugunsten dieser Gesetze aufgelöst — auch gegen eine ausdrückliche
Feature-Bitte. In dem Fall: widersprechen, begründen, Alternative anbieten.

| | Gesetz | Operativ |
|---|---|---|
| **G1** | **Auslagern statt anfordern** | Kein Screen, der Nachdenken erzwingt. Erfassung < 3 s, Check-in < 15 s, Tagesreview < 2 min. Ausgabe ist **genau eine** Handlung, nie eine Liste zur Auswahl. |
| **G2** | **Erklärbar statt intelligent** | Jede Ausgabe nennt `rule_id` + Begründung. Kein Score ohne sichtbare Formel. **KI/LLM niemals in der Entscheidungsschleife.** |
| **G3** | **Kanalisieren statt unterdrücken** | Reizbedarf wird budgetiert, nie moralisiert. Keine Schuld-Sprache, keine Verbote — nur Latenz, Sichtbarkeit, Alternativen. |
| **G4** | **Selbstbegrenzung** | AXIOM deckelt seine eigene Nutzungszeit und rationiert seine eigene Konfiguration. |

**G4 ist das wichtigste Gesetz dieses Projekts.** Das Hauptrisiko ist nicht technisches Scheitern,
sondern dass das Bauen des Systems zur Prokrastination wird (siehe `docs/07-RISIKEN.md` R1). Deshalb:
**M12 Meta-Guard wird in Stufe 1 gebaut, nicht später.**

---

## Vor jeder Änderung

1. **Welches Defizit?** Jede Änderung zahlt auf ein `D1`–`D12` aus `docs/01-PROFIL-DEFIZITE.md` ein.
   Kein Bezug → nicht bauen, sondern nachfragen.
2. **Welche Stufe?** `docs/05-ROADMAP.md`. Module späterer Stufen werden nicht vorgezogen.
3. **Verletzt es G1–G4?** Dann widersprechen, auch wenn ausdrücklich gewünscht.
4. **Steht es auf einer Verbotsliste?** `docs/02-ARCHITEKTUR.md §8` oder `docs/05-ROADMAP.md`
   ("Ausdrücklich nicht auf der Roadmap"). Dann ist die Entscheidung bereits gefallen.
5. **Geht es einfacher?** Bei Zweifel gewinnt immer die einfachere Lösung.

---

## Architektur — harte Grenzen

```
axiom_core   pure Dart. Domain + Engine + Ports.  KEINE Flutter-, Platform- oder I/O-Abhängigkeit.
axiom_data   SQLite, YAML-Loader, Health, Export.         → darf axiom_core
axiom_app    Flutter UI, Notifications, Widgets.          → darf axiom_core, axiom_data
```

Abhängigkeiten zeigen **immer nach innen**. `axiom_core` kennt die anderen Packages nicht.
Verstöße brechen den Build (`dart run tools/check_layering.dart`).

**Nicht verhandelbar im Core:**
- Kein `DateTime.now()`, kein `Random()` — immer über die injizierten Ports `Clock` / `Rng`.
  Ohne das sind Regeln nicht deterministisch testbar, und Determinismus ist die Grundlage von G2.
- Kein `dart:io`, kein `dart:ui`, kein Netzwerk.
- `evaluate(state, ruleset) → decision` ist eine **reine Funktion**.
- Events sind **append-only**. Nie UPDATE, nie DELETE. Korrekturen sind neue Events.
- Alle Zeitstempel UTC. Lokale Zeitzone nur zur Anzeige.

---

## Regeln (`rules/`)

Vollständige Semantik: [`docs/04-REGELWERK.md`](docs/04-REGELWERK.md).

Beim Anlegen oder Ändern einer Regel gilt:

- `rationale` ist **Pflicht** — leer = Ladefehler. So wird G2 erzwungen statt erhofft.
- `title_en` und `rationale_en` sind **erwünscht, nicht Pflicht**. Fehlen sie,
  erscheint in der englischen Oberfläche der deutsche Text und der Validator
  warnt. Sichtbar unfertig ist besser als stumm fehlend — eine deshalb nicht
  geladene Regel wäre schlimmer.
- `cooldown` ist **Pflicht** — ohne Cooldown entsteht Benachrichtigungsflut (R2).
- `id` (`R-NNN`) wird **nie** wiederverwendet, auch nicht nach Löschung.
- Jede Regel braucht einen Test in `packages/axiom_core/test/rules/`, sonst wird sie nicht geladen.
- **Jede neue Regel startet als `severity: log_only` (SHADOW).** Mindestens 7 Tage stumm mitlaufen,
  dann im Wochenreview auswerten, dann erst live.
- `rules/personal/` ist git-ignoriert. Enthält private Trigger. **Nie committen, nie zitieren,
  nie in Beispiele übernehmen.**

**Regeleditor in der App.** Regeln lassen sich am Gerät ändern (*System → Regelwerk*). Die
Änderung landet als Overlay in der Datenbank, nicht in `rules/core/` — die Assets bleiben
unberührt, und `ruleToYaml` gibt jede Regel in genau der Form zurück, die nach `rules/`
zurückkopiert werden kann. Zwei Dinge sind dabei nicht verhandelbar und im Code erzwungen:

1. Jede gespeicherte Regel läuft **sieben Tage als `log_only`**, egal was gewählt wurde.
2. `rationale` und `cooldown` sind Pflichtfelder — der Editor speichert sonst nicht.

Wer eine Regel dauerhaft will, kopiert sie am Rechner nach `rules/core/` und committet sie.
Erst dann ist sie versioniert.

---

## Code-Konventionen

- **Dart 3.12 / Flutter 3.44.** Null-safety, `sealed`/`final class` wo sinnvoll.
- **Code und Bezeichner Englisch. Doku und Kommentare Deutsch.**
- **UI-Texte: Deutsch ist die Quelle, Englisch die Übersetzung.** Der deutsche
  Satz steht im Quelltext und ist zugleich der Schlüssel:
  `context.t('Nichts in Reichweite')`. Die englische Fassung steht in
  `packages/axiom_app/lib/i18n/en.dart`. Warum so: Der Ton entscheidet über die
  Wirkung, und diese Entscheidung muss dort lesbar sein, wo sie getroffen wird
  — nicht hinter einem Bezeichner wie `now.emptyTitle`.
  Für Code ohne `BuildContext` (Benachrichtigungen, Widget) gibt es
  `translate(language, …)`; die Sprache wird durchgereicht, nie global gelesen.
  Der Kern liefert Sätze mit Werten als `Phrase('{0} min über …', [n])`, damit
  Zahlen nicht aus fertigen Sätzen zurückgerechnet werden müssen.
- Domain-Typen sind unveränderlich (`final`, `copyWith`).
- Fehler: Fail-Fast im Core. Ein unbekannter Event-Typ oder eine ungültige Regel wird **abgelehnt**,
  nicht stillschweigend übersprungen. In einem regelbasierten System ist eine stumm ignorierte
  Regel schlimmer als ein Absturz.
- Keine Abkürzungen in Bezeichnern außer den etablierten Domänenbegriffen (`ae` = activation energy).
- Kommentare erklären **warum**, nicht was. Regel-Formeln bekommen einen Verweis auf das
  Defizit (`// [D5]`).

### UI-Sprache — verbindlich

Zustandswerte sind **Messwerte, keine Noten** (siehe R7). Wortwahl entscheidet hier über Wirkung:

| ✗ nie | ✓ stattdessen |
|---|---|
| "Du hast 14 offene Aufgaben" | "Jetzt: Steuerunterlagen sortieren (10 min)" |
| "Streak verloren" | *(gibt es nicht)* |
| "Produktivität: 34 % 📉" | "Kapazität 34 — heute wird weniger gezeigt" |
| "Du solltest …" | "Regel R-050: …" |
| "Schon wieder verschoben" | *(kommentarlos übernehmen)* |

Nie: Schuld, Vergleich, Bewertung, Ausrufezeichen-Motivation. AXIOM ist ein Werkzeug, kein Coach.

---

## Befehle

Alle aus der Projektwurzel, sofern nicht anders vermerkt.

```bash
# Prüfen — muss immer grün sein
dart run tools/bin/validate_rules.dart rules      # Regelwerk
dart run tools/bin/check_layering.dart .          # Architekturgrenzen
(cd packages/axiom_core && dart analyze && dart test)
(cd packages/axiom_data && dart analyze && dart test)
(cd packages/axiom_app  && flutter analyze && flutter test)

# Regelwerk in die App-Assets spiegeln — VOR jedem App-Build
dart run tools/bin/sync_rules.dart

# Baseline auswerten (nach 14 Tagen). Schreibt nichts, schlaegt nur vor.
adb exec-out run-as de.atomfritte.axiom cat files/axiom.db > axiom.db
dart run tools/bin/calibrate.dart axiom.db

# Starten
(cd packages/axiom_app && flutter run -d linux)   # Desktop-Companion
(cd packages/axiom_app && flutter run -d <id>)    # Gerät, siehe adb devices

# Referenzbilder erneuern, wenn eine UI-Änderung beabsichtigt war
(cd packages/axiom_app && flutter test test/screenshot_test.dart --update-goldens)
```

Vor jedem Commit: Regelvalidator, Layering-Check, `analyze` und `test` in allen
drei Paketen.

**Regeltexte sind Nutzertexte.** `title` und `rationale` erscheinen im
Systeminspektor. Echte Umlaute, keine Ersatzschreibung — `language_test.dart`
prüft das. Die englischen Felder (`*_en`) sind davon ausgenommen und werden
stattdessen von `i18n_test.dart` geprüft.

---

## Tests

| Ebene | Datei | Prüft |
|---|---|---|
| Regeln | `axiom_core/test/` | Bedingungen, Cooldowns, Limits, Konfliktauflösung |
| Determinismus | `decision_resolver_test` | gleiche Eingabe → gleiche Ausgabe (ADR-0003) |
| Rebuild | `axiom_data/test/event_store_test` | Projektionen aus `events` neu aufbaubar |
| Regelwerk | `axiom_data/test/rule_source_test` | lädt das **echte** `rules/`-Verzeichnis |
| Verhalten | `axiom_app/test/app_test` | genau eine Handlung (G1), sichtbare Regel-ID (G2) |
| Sprache | `axiom_app/test/language_test` | keine Schuldsprache, echte Umlaute, kein Netzwerk |
| Übersetzung | `axiom_app/test/i18n_test` | jeder Text hat eine englische Fassung, gleiche Platzhalter, gleicher Ton |
| Systemanbindung | `axiom_app/test/platform_integration_test` | Manifest und Kotlin — die Ebene, durch die Widget-Tests fallen |
| Optik | `axiom_app/test/screenshot_test` | Referenzbilder in `test/screenshots/` |

Beim Schreiben von Tests: Prüfe **Verhalten und Wirkung**, nicht Implementierung.
Ein Test namens „zeigt nie mehrere Vorschläge zur Auswahl" ist mehr wert als einer,
der eine Methode aufruft — er hält ein Designgesetz fest, nicht eine Signatur.

Fällt ein Test um, prüfe zuerst, ob er eine echte Regression gefunden hat.
Golden-Bilder nur erneuern, wenn die Änderung beabsichtigt war.

---

## Datenschutz

Die Daten dokumentieren psychische Verfassung, Impulskontrolle, Substanzkonsum, Beziehungskonflikte
und Medikation. Entsprechend:

- **`INTERNET` ist deklariert** (ADR-0005, Expertenmodus). An die Stelle der früheren
  strukturellen Garantie tritt eine engere, getestete Zusage: **AXIOM ruft nichts von sich aus
  auf.** Kein HTTP-Client, keine ausgehende Verbindung, kein SDK, das eine aufbauen könnte —
  `language_test.dart` verbietet `package:http`, `HttpClient`, `Socket.connect`,
  `WebSocket.connect` und `dart:html` im gesamten App-Code. Die App **lauscht** nur, und nur
  solange der Expertenmodus eingeschaltet ist. **Eine Ausnahme:** Der Expertenmodus meldet sich
  per mDNS als `axiom.local` an — link-lokales Multicast, nur Name und IP, nur solange er läuft
  (ADR-0005 Punkt 2a). Genau eine Datei darf das, und ein Test hält die Liste kurz.
- Keine Telemetrie, kein Analytics-SDK, kein Crash-Reporting an Dritte. Nie. Auch nicht "anonym".
- **Noch nicht umgesetzt: SQLCipher, Schlüssel im Android Keystore, Biometrie-Gate.** Hier stand
  das jahrelang wie ein Zustand. Es ist ein Ziel: `SqliteEventStore` nimmt einen `encryptionKey`
  entgegen und setzt `PRAGMA key`, aber kein Aufrufer übergibt einen — `axiom.db` liegt im
  Klartext in `files/`, und einen Biometrie-Gate gibt es nicht. Solange das so ist, wird es
  **nirgendwo als vorhanden beschrieben**, auch nicht in der README. Siehe `docs/BACKLOG.md`.
  Wer den Schutz baut, streicht diesen Absatz — nicht vorher.
- `rules/personal/` und alle `*.axiom`-Exporte bleiben lokal.
- **Vor jedem `git push` prüfen, ob echte persönliche Daten im Diff sind.**

---

## Abgrenzung — verbindlich

AXIOM ist **kein Medizinprodukt, keine Diagnostik, keine Therapie**.

- Keine diagnostische Sprache, keine klinischen Schwellenwerte, kein Screening-Score.
- M13 (Med Window) protokolliert nur. **Nie** eine Dosis, Einnahmezeit oder Änderung empfehlen.
- Bei anhaltendem L3 (> 14 Tage): sichtbarer Hinweis, professionelle Abklärung zu erwägen.
- `load_index` misst einen Zustand. Er **diagnostiziert nichts**.

---

## Verbote

Nicht bauen, auch auf Nachfrage nicht — ohne dass die Entscheidung im jeweiligen Dokument
ausdrücklich revidiert wurde:

| ✗ | Grund |
|---|---|
| KI/LLM in der Entscheidungsschleife | verletzt G2, zerstört Auditierbarkeit |
| Plugin-System, Skripting-Layer, generische Automations-Engine | Meta-Work-Treibstoff (D3, R1) |
| Streaks mit Verlustmechanik, Punkte ohne reale Konsequenz | trifft D10, habituiert binnen Tagen |
| Social, Sharing, Leaderboards, Vergleich | trifft Rejection Sensitivity frontal (D10) |
| Cloud-Pflicht, Account-Zwang, Telemetrie | Datenhoheit (R6) |
| Schuldbasierte Erinnerungen und Formulierungen | erzeugt Vermeidung statt Handlung |
| Endlose Konfigurierbarkeit, Einstellungs-Wildwuchs | D3 |
| Ausgehende Netzwerkverbindungen jeder Art | ADR-0005: AXIOM lauscht, ruft nie |
| Expertenmodus ohne Anmeldung, oder Start beim Hochfahren / aus einem Dienst | ein offener Port mit Gesundheitsdaten. Mitstarten **mit der App** ist erlaubt und abschaltbar (ADR-0005 §3b) |
| Regeleditor ohne Schattenzeit oder ohne Pflicht-`rationale` | wäre reines Meta-Work-Vehikel (D3, R1) |
| Microservices, Multi-User, Rollen/Rechte | kein Anwendungsfall |
| UI-Redesign, bevor S1–S3 laufen | klassische Ausweichbaustelle |

---

## Umgang mit Feature-Wünschen

Der Systemizing-Drive des Zielprofils erzeugt laufend neue Systemideen — das ist Teil des
Profils (D3), nicht ein Mangel an Disziplin. Erwartete Haltung:

1. **Zuordnen:** Auf welches `D1`–`D12` zahlt das ein? Kein Bezug → nachfragen, nicht bauen.
2. **Einordnen:** Welche Stufe? Gehört es nach S3, wird es notiert, nicht gebaut.
3. **Widersprechen, wenn nötig:** Bei Konflikt mit G1–G4 oder einer Verbotsliste klar sagen —
   *einmal*, mit Begründung und Alternative.
4. **Dann ausführen:** Bestätigt der Nutzer nach dem Einwand, ist das seine Entscheidung. Umsetzen,
   vollständig, ohne erneutes Aufwärmen des Einwands.
5. **Notieren:** Abgelehnte oder verschobene Ideen kommen nach `docs/BACKLOG.md`, damit sie nicht
   verlorengehen und nicht im Kopf bleiben müssen (D9).

**Die nützlichste Frage in diesem Projekt lautet:**
> *Reduziert das die Last — oder erzeugt es nur ein interessanteres System?*
