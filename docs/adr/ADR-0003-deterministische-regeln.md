# ADR-0003 — Deterministische Regeln statt Machine Learning

**Status:** akzeptiert · **Datum:** 2026-08-03

## Kontext

AXIOM muss aus einem Zustandsvektor ableiten, welche Handlung jetzt sinnvoll ist. Naheliegend wäre
ein gelerntes Modell: genug Signale, ein klares Feedback (`followed`/`rejected`) — ein
Standardproblem für überwachtes Lernen oder Bandit-Verfahren.

Der Nutzer ist technisch versiert, hat einen ausgeprägten Systemizing-Drive und würde ein
ML-Verfahren problemlos implementieren können. Ein LLM in der Entscheidungsschleife wäre technisch
ebenfalls trivial.

## Entscheidung

**Die Entscheidungsschleife ist ausschließlich regelbasiert und vollständig deterministisch.**

```
evaluate(state, ruleset) → decision      reine Funktion, keine Zufallsquelle, keine Netzwerkabfrage
```

Konfliktauflösung über eine **totale Ordnung** `(severity, priority, rule_id)`. Gleicher Zustand
plus gleiches Regelwerk ergibt immer dieselbe Entscheidung.

**Kein ML, kein LLM, keine Heuristik ohne sichtbare Formel** in der Entscheidungsschleife.

Zulässig, klar getrennt und als nicht-deterministisch gekennzeichnet:
- **Auswertung** — Muster in Baseline-Daten finden, Formelgewichte vorschlagen (S1/S2, offline,
  manuell angestoßen)
- **Formulierung** — Textvorschläge für die eigenen Checklisten in M6

Beide Fälle erzeugen **Vorschläge, die der Nutzer in eine Regel überführt**. Sie treffen nie selbst
eine Entscheidung.

## Begründung

**1. Auditierbarkeit ist bei diesem Profil kein Komfort, sondern die Adhärenzbedingung.**
Ein ausgeprägter Systemizer akzeptiert eine Anweisung, deren Herleitung er nachvollziehen kann.
Ein Blackbox-Vorschlag — auch ein besserer — wird geprüft, hinterfragt und bei der ersten
unerklärlichen Ausgabe dauerhaft verworfen. Ein System, das nicht benutzt wird, hat eine
Trefferquote von null. Das ist der entscheidende Punkt, nicht Modellgüte.

**2. Das Regelwerk ist selbst das Werkzeug.** Regeln zu schreiben, zu testen und zu verwerfen ist
eine legitime, produktive Beschäftigung für den Systemizing-Drive — auf der richtigen Ebene und
zeitlich begrenzt durch den Review-Slot (M12). Ein ML-Modell würde diesen Drive nicht bedienen,
sondern nur verlagern: statt Regeln zu schreiben, würde am Modell gebastelt — mit deutlich
schlechterem Kosten-Nutzen-Verhältnis (D3, R1).

**3. Datenlage.** Ein Nutzer, ~100 Events/Tag, hochgradig nichtstationäres Verhalten. Für
belastbares Lernen ist das zu wenig und zu instabil. Ein früh trainiertes Modell würde
Zufallsmuster der ersten Wochen zementieren.

**4. Fehlermodus.** Eine falsche Regel ist lesbar, lokalisierbar und in einer Zeile korrigierbar.
Ein falsch gelerntes Modell erzeugt unerklärliche Ausgaben, deren Ursache nicht auffindbar ist.
Bei einem System, das in Selbstregulation eingreift, ist Diagnostizierbarkeit wichtiger als
Vorhersagegüte.

**5. Determinismus ist Testvoraussetzung.** Golden-Szenarien — ganze simulierte Tage mit erwarteter
Entscheidungssequenz — funktionieren nur bei reproduzierbarer Auswertung. Ohne sie wären
Regelkonflikte praktisch nicht auffindbar.

## Konsequenzen

**Positiv:** Jede Ausgabe erklärbar. Regelwerk versioniert und diffbar. Vollständig testbar.
Keine Trainingsdaten, keine Modellpflege, keine Netzwerkabhängigkeit, keine Modell-Drift.

**Negativ:**
- Regeln müssen von Hand geschrieben und kalibriert werden. Die Startgewichte sind geraten —
  deshalb existiert die 14-tägige Baseline-Phase (S1) und die SHADOW-Phase pro Regel.
- Subtile Muster, die ein Modell fände, bleiben unentdeckt, bis sie im Review manuell auffallen.
  **Bewusst akzeptiert:** Ein nachvollziehbares, benutztes System schlägt ein optimales, verworfenes.
- Das Regelwerk kann wachsen und unübersichtlich werden. Gegenmaßnahme: Regelqualitäts-Metriken und
  der Pflicht-Rückbaupunkt im Quartalsreview ([06-METRIKEN](../06-METRIKEN.md)).

## Durchsetzung

- `axiom_core` hat keine Netzwerk- und keine ML-Abhängigkeit (statisch geprüft).
- `DateTime.now()` und `Random()` sind im Core verboten — nur über die Ports `Clock` / `Rng`.
- Determinismus-Test: dieselbe Event-Sequenz zweimal → identische Entscheidungsfolge.
- `rationale` ist Pflichtfeld jeder Regel; fehlt es, wird die Regel nicht geladen.
