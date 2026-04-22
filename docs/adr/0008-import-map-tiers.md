# ADR 0008 — Import-map tiers

**Status:** Accepted
**Date:** 2026-03-01

## Context

The codebase has ~700 Swift files grouped into domain folders (Navigation,
Intelligence, Medical, Mesh, etc.). Without a convention for which domain can
import which, we'd accrue cyclic dependencies and every refactor would need a
graph-analysis pass.

## Decision

**Four tiers, allowed to import only from their own tier or lower.**

| Tier | Examples | Can import |
|------|----------|------------|
| **0 Primitives** | `Diagnostics/LoggerConvenience.swift`, `Diagnostics/Versioned.swift`, `Hardware/Common/IOTimeout.swift` | Foundation, Combine, OSLog only |
| **1 Core** | `Security/*`, `SecurityLayer/*`, `Navigation/Core/*`, `Intelligence/ActionBoundary/*`, `CommunicationCore/DTN/*` | Tier 0 + each other |
| **2 Domains** | `Navigation/*`, `Intelligence/*`, `Medical/*`, `SpatialIntelligence/*`, `CommunicationCore/*`, `Scenarios/*` | Tier 0–1 |
| **3 UI + App** | `App/*`, `UI/*`, `Tier1/Features/*`, any View | Tier 0–2 |

## Consequences

- A Tier 1 module importing a Tier 2 module is a bug. Reviewers reject.
- Stores and services (tier 2) can depend on tier 1 primitives
  (ErrorReporter, AuditLogger, Versioned) but not on App / View layers.
- Tests can import any tier — `@testable import ZeroDark` ignores the rule.
- The rule is not automated yet. A pre-commit linter that walks `import`
  statements is a future item (part of P3).

## When to revisit

If the tier graph becomes denser than ~3 levels of conceptual dependency
(e.g. "Navigation depends on Scenarios now"), revisit whether the tier
boundaries still reflect the product structure.
