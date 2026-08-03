# ADR-0002 — Local-first, Event-Sourcing, kein Netzwerk in S1–S3

**Status:** akzeptiert, Punkt 2 abgelöst durch [ADR-0005](ADR-0005-expertenmodus.md)
· **Datum:** 2026-08-03

> **Nachtrag 2026-08-03:** Punkt 2 gilt nicht mehr. Mit dem Expertenmodus (ADR-0005) wird
> `INTERNET` deklariert. An die Stelle der strukturellen Garantie tritt eine engere, getestete
> Zusage: AXIOM lauscht, ruft aber nichts von sich aus auf. Punkte 1, 3 und 4 bleiben unverändert.

## Kontext

AXIOM speichert Daten über psychische Verfassung, Impulskontrolle, Substanzkonsum,
Beziehungskonflikte und ggf. Medikation. Der Nutzer kann selbst hosten oder rein lokal betreiben.

Zwei Anforderungen stehen scheinbar im Konflikt:
- **Maximaler Datenschutz** — der Schaden bei Leck ist sehr hoch (R6)
- **Rückwirkende Regelanalyse** — *"hätte R-042 in neuer Fassung letzten Dienstag anders
  entschieden?"* — die Voraussetzung dafür, dass das Regelwerk empirisch verbesserbar ist statt
  nur gefühlt

## Entscheidung

**1. Local-first ohne Ausnahme.** Alle Daten liegen auf dem Gerät, verschlüsselt (SQLCipher,
Schlüssel im Android Keystore, Biometrie-Gate). Kein Account, kein Backend, keine Cloud.

**2. `INTERNET` wird in S1–S3 nicht im Android-Manifest deklariert.**
Damit ist auf Betriebssystemebene ausgeschlossen, dass Daten das Gerät verlassen — unabhängig von
jedem Bug, jeder transitiven Abhängigkeit und jedem Versehen. Das ist erheblich stärker als jede
Zusicherung im Code.

**3. Event Sourcing als Speicherform.** Append-only Events sind die Quelle der Wahrheit. Zustand,
Aufgaben und Metriken sind Projektionen und jederzeit neu berechenbar.

**4. Sync erst ab S4, optional, E2E-verschlüsselt.** Der Server sieht ausschließlich Chiffrat.
Selbst gehostet, Docker, ohne Account-Konzept.

## Begründung

**Zu 2 — kein INTERNET-Permission:** Der übliche Weg wäre eine Zusicherung ("wir senden nichts").
Bei Gesundheitsdaten dieser Sensibilität ist eine strukturelle Garantie einer Absichtserklärung
vorzuziehen. Die Kosten sind null, solange kein Sync existiert. Zusätzlicher Nebeneffekt: Analytics-
oder Crash-Reporting-SDKs können nicht versehentlich über eine Abhängigkeit hereinkommen — sie
würden schlicht nicht funktionieren.

**Zu 3 — Event Sourcing für einen Ein-Nutzer-Fall:** Auf den ersten Blick Über-Engineering (R9).
Es trägt aber drei Dinge, die ohne es nicht gehen:
- Rückwirkende Regelauswertung gegen historische Zustände — die Grundlage empirischer
  Regelverbesserung ([04-REGELWERK §6](../04-REGELWERK.md))
- Formel-Rekalibrierung nach der Baseline-Phase (die Gewichte in `weights.yaml` sind geraten und
  müssen an echten Daten nachjustiert werden — dafür braucht es die Rohsignale)
- Vollständiger Export in offenem Format (NDJSON), unabhängig von AXIOM lesbar

Ohne Event Sourcing wäre das Regelwerk nicht empirisch verbesserbar, sondern nur gefühlt — und ein
Systemizer würde ein System, dessen Regeln nur gefühlt sind, zu Recht verwerfen.

## Konsequenzen

**Positiv:** Strukturelle Datenschutzgarantie. Volle Offline-Fähigkeit. Regelwerk empirisch
verbesserbar. Nutzer besitzt seine Daten vollständig.

**Negativ:**
- Kein automatisches Cloud-Backup. Der Nutzer muss selbst exportieren. → Erinnerung im Monatsreview.
- Geräteverlust = Datenverlust, wenn kein Export existiert. Bewusst akzeptiert.
- Speicherwachstum durch Events. Bei realistischem Volumen (< 100 Events/Tag) irrelevant:
  ~5 MB/Jahr.
- Ab S4 muss `INTERNET` nachträglich hinzugefügt werden — dann mit expliziter Nutzerentscheidung
  und eigenem ADR.

## Verifikation

- Rebuild-Test: Projektionstabellen löschen → aus `events` neu aufbauen → identischer Zustand.
- Statischer Check: kein Netzwerkzugriff in `axiom_core`.
- Manifest-Check im CI: `INTERNET` darf in S1–S3 nicht auftauchen.
