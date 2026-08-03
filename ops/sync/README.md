# Sync — optional, ab S4

**Nicht implementiert. Kein Blocker für S1–S3.**

Ein Gerät reicht zunächst. Sync wird erst gebaut, wenn der Linux-Companion (S3) läuft und
S1–S3 seit mindestens 8 Wochen stabil sind.

## Anforderungen, wenn es soweit ist

- **E2E-verschlüsselt.** Der Server sieht ausschließlich Chiffrat, nie Klartext.
- **Self-hosted**, Docker Compose, kein Account-Konzept.
- **Kein Zwang.** Die App muss ohne Sync vollständig funktionieren.
- Konfliktauflösung: Events sind append-only und ULID-sortiert — Merge ist eine Vereinigung,
  kein Konflikt. Projektionen werden lokal neu berechnet.

## Achtung

Ab S4 muss `INTERNET` im Android-Manifest deklariert werden. Damit entfällt die strukturelle
Datenschutzgarantie aus ADR-0002. Das ist eine bewusste Entscheidung und braucht ein eigenes ADR.
