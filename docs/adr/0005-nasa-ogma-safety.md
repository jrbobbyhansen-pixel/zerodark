# ADR 0005 — NASA OGMA-pattern runtime safety monitor

**Status:** Accepted
**Date:** 2026-03-01

## Context

Tactical apps that run AI inference on-device can degrade silently: a model
that starts hallucinating, a mesh crypto layer that fails to rotate session
keys, a geofence that stops updating. Operators need to know — loudly — when
a safety-critical invariant has been violated.

NASA's OGMA (Ogma: Online Generation of Monitors Automatically) pattern uses
runtime assertions on top of a formal safety property catalog — monitors
watch invariants and surface violations to a central handler instead of
crashing the process.

## Decision

ZeroDark adopts the OGMA pattern via `RuntimeSafetyMonitor`:

- **Safety properties** are declared in
  `SecurityLayer/SafetyMonitor/SafetyProperty.swift` as typed invariants
  (e.g. "session key rotation every N messages",  "geofence updates within
  N seconds of location updates", "model inference below N s per request").
- **Monitor handlers** fire on violation — surface to `ErrorReporter`
  (PR-A5), log to the audit trail, and can trigger recovery actions
  (restart mesh, reload model, etc.).
- **The monitor never crashes the app.** Violations are observable first,
  recoverable second, fatal never.

## Consequences

- Adding a safety-critical code path means writing the property + the monitor
  at the same time, not "eventually." PR reviewers check for this.
- The safety monitor itself is under-tested compared to what OGMA wants; this
  is acknowledged debt. A future PR should add property-based fuzz tests.
- Violations that aren't currently actionable are still logged — operators
  can't act on them, but post-mission review + telemetry pick them up.

## References

- [NASA OGMA](https://github.com/nasa/ogma)
- Implementation: `SecurityLayer/SafetyMonitor/RuntimeSafetyMonitor.swift`
