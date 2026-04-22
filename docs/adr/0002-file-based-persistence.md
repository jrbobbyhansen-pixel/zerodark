# ADR 0002 — File-based persistence over CoreData / SwiftData

**Status:** Accepted
**Date:** 2026-03-01

## Context

ZeroDark persists dozens of model types (IncidentLogEntry, NavTrailPoint,
CasualtyCard, ScanOverlay, TacticalWaypoint, DTNBundle, …). Two obvious
choices:

1. **CoreData / SwiftData** — managed object graph, migrations, schema versioning.
2. **Codable JSON files in Documents/** — one file per record or per store.

## Decision

Per-record (or per-store) Codable JSON files in Documents/, atomic writes with
`.completeFileProtection`.

## Why not CoreData / SwiftData

- Migrations are in-house, field-by-field, easy to audit. A schema change is a
  diff on one model file + a manual migration function.
- Mesh transport sends the same Codable payloads over the wire, so we don't
  translate between an in-memory NSManagedObject and a wire format.
- Test fixtures are plain `JSONEncoder().encode(…)` blobs — no in-memory
  Core Data stack to spin up.
- File protection class is explicit and uniform
  (`[.atomic, .completeFileProtection]`).

## Consequences

- Versioning is our problem. PR-C2 introduced `Versioned<T>` + `SchemaMigratable`
  as the common envelope; new persisted models should opt in.
- No free queries. When a store needs filtering, we build it with `Array.filter`
  or a purpose-built index (`IncidentLogStore.byDate`, etc.).
- Unbounded-growth bugs are more likely without an ORM-level cap. Every store
  needs its own retention policy (PR-C1 handles ScanStorage; others are open).
- Concurrency is on us. Stores are `@MainActor` + `ObservableObject` by
  default; file I/O offloads to a private actor when it's hot.

## When to revisit

If we hit >50 k records in any single store and query latency becomes
operator-visible, move that one store onto SQLite directly (GRDB). Do not
adopt CoreData — migrations and XCTest interactions are still worse than
rolling our own.
