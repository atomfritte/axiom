# Persönliche Regeln

**Dieses Verzeichnis ist git-ignoriert. Hier liegen private Daten.**

Regeln in `rules/personal/` überschreiben gleichnamige IDs aus `rules/core/` vollständig
(Overlay-Semantik). Neue IDs werden additiv geladen.

## Was hierher gehört

Alles, was konkrete persönliche Trigger enthält:

- Beträge und Konten (`Kauf > 200 €`, bestimmte Händler, Wallets)
- Substanzen, Mengen, Zeiten
- Namen von Personen, Konfliktmuster, Beziehungskontexte
- Berufliche Details, Arbeitgeber, Projekte
- Medizinische Angaben (M13)
- Die eigenen Prüf-Checklisten für den Impulse Interceptor (M6)

## Beispiel

```yaml
# rules/personal/impulse.yaml
- id: R-200
  title: "Cooldown vor grösseren Anschaffungen"
  deficit: D5
  rationale: >
    Selbst gesetzte Regel im ruhigen Zustand. Der Impulsdurchbruch
    überlebt 15 Minuten Latenz meistens nicht.
  when:
    all:
      - regulation: { lt: 60 }
  then:
    action: start_cooldown
    params:
      threshold_eur: 200
      cooldown_min: 15
      checklist:
        - "Kannte ich das Produkt vor heute?"
        - "Was genau löst es, das ich gestern noch nicht lösen musste?"
        - "Kaufe ich das Ding oder das Gefühl?"
        - "Wie sehe ich das in 4 Wochen?"
  priority: 85
  severity: enforce      # selbst autorisiert — Vertrag mit dem Vergangenheits-Ich
  cooldown: { minutes: 0 }
```

## Warum die Checkliste selbst geschrieben sein muss

Ein Systemizer bricht ungern eine Regel, die er selbst gesetzt hat. Eine vorgegebene Checkliste
ist eine fremde Anweisung und wird weggeklickt. Eine selbst formulierte ist ein Vertrag — und
genau das ist der Wirkmechanismus von M6.

Die Checkliste im ruhigen Zustand schreiben. Nicht im Impuls.

## Regeln für dieses Verzeichnis

- **Nie committen.** `.gitignore` deckt das ab — vor jedem `git push` trotzdem den Diff prüfen.
- **Nie in Beispiele oder Dokumentation übernehmen.**
- Beim Export (`.axiom`) sind diese Regeln enthalten — Export bleibt verschlüsselt und lokal.
