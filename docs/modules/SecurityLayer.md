# Security + SecurityLayer

App lock, mesh crypto, safety monitor, geofencing, audit log.

## Entry points

- **`AppLockManager.shared`** — biometric + PIN + duress PIN; lockout
  ladder after repeated failures (PR-B4). Minimum 6-digit PIN enforced
  via `AppLockManager.isAcceptablePin(_:)`.
- **`MeshCryptoManager`** — AES-256-GCM envelope for mesh payloads.
  `SessionKeyManager` rotates keys; `PinnedURLSession` pins TLS for
  controlled egress to known endpoints.
- **`RuntimeSafetyMonitor.shared`** — watches safety invariants. See
  [ADR 0005](../adr/0005-nasa-ogma-safety.md).
- **`GeofenceMonitor.shared`** — continuous boundary monitoring with
  10 m hysteresis dead-band (PR-C10).
- **`AuditLogger.shared`** — append-only audit trail on disk, used by
  every security-critical path (lock, duress, threat classify, etc.).

## Error reporting

All recoverable failures in this domain go through
`ErrorReporter.shared.report(category: .safety | .crypto | .safety)` so
the operator sees them as toasts when `userMessage` is provided, and
audit-only otherwise (`ErrorReport` keeps the full record either way).

## File protection

Every write here uses `[.atomic, .completeFileProtection]`. See the
`PrivacyInfo.xcprivacy` Required-Reason API declarations for the file-
timestamp / disk-space / bootTime uses.

## Cross-references

- App-lock hardening: PR-B4, `AppLockTests.swift`.
- Geofence hysteresis: PR-C10, `GeofenceMonitorTests.swift`.
- MainActor singleton convention: [ADR 0003](../adr/0003-mainactor-singletons.md).

## Testing

`MeshCryptoTests` (roundtrip), `AppLockTests` (PIN policy + lockout),
`GeofenceTests` (containment), `GeofenceMonitorTests` (hysteresis).
