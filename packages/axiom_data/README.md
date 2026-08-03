# axiom_data — Infrastruktur

Implementiert die Ports aus `axiom_core`. Darf `axiom_core` kennen, nie umgekehrt.

| Datei | Inhalt |
|---|---|
| `sqlite_event_store.dart` | Append-only Events, Projektionen, Entscheidungs-Log, Meta-Guard-Nutzung |
| `yaml_rule_source.dart` | Regelwerk laden und validieren, Overlay `personal` über `core` |
| `signal_aggregator.dart` | Event-Strom → `Signals` für den StateDeriver, inklusive Konfidenz |

## Schema

Aktuell **v2**. Migrationen sind vorwärtsgerichtet, mit Test pro Schritt.

- **v1** — events, tasks, decisions, usage_log, settings
- **v2** — `events.seq`: monotone Einfügereihenfolge.
  Ohne sie entschied bei identischem Zeitstempel der Zufallsanteil der ULID
  über die Reihenfolge, und der Rebuild konnte `task_completed` vor
  `task_created` einsortieren.

## Garantien

- **Append-only.** Nie UPDATE, nie DELETE auf `events`. Korrekturen sind neue Events.
- **Rebuild.** Projektionstabellen löschen und aus `events` neu aufbauen ergibt
  denselben Zustand — als Testfall, nicht als Absichtserklärung.
- **Konfidenz.** Bei alten Daten sinkt sie; Regeln unterhalb der Schwelle
  feuern nicht. Lieber schweigen als raten (R8).

## Verschlüsselung

`SqliteEventStore.open(..., encryptionKey: ...)` setzt `PRAGMA key` für
SQLCipher. Ohne SQLCipher-Bibliothek läuft die Datenbank unverschlüsselt;
`isEncrypted` meldet den tatsächlichen Zustand, damit die App ihn anzeigen
statt annehmen kann.

## Tests

```bash
dart test
```

`rule_source_test.dart` lädt das **echte** Regelwerk aus `rules/` — bricht der
Test, ist das ausgelieferte Regelwerk kaputt, nicht der Test.
