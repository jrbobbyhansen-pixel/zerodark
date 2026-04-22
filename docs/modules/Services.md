# Services

Runtime service layer: external integrations, environment estimators,
on-device background tasks.

## Entry points

- **`IntegrationHealthMonitor.shared`** — scheduled probes for SRTM /
  weather / TAK with per-service health publish (PR-B5). Register a
  probe at boot; probes are timeout-bounded (`withTimeout` from
  `Hardware/Common/IOTimeout.swift`).
- **`WeatherForecaster.shared`** — barometer + temperature + wind model;
  surfaces `barometricPressureTrend` consumed by NavTabView bottom bar.
- **`LocationManager.shared`** — thin wrapper over CoreLocation for
  components that just need the current coordinate.
- **`ActivityFeed.shared`** — in-memory ring buffer of operator-visible
  events (mesh joins, incidents, DTN delivery). Caps enforced.
- **`MeshService.shared`** — MultipeerKit-backed peer discovery + send.
  Delegates encryption to `MeshCryptoManager`.

## Conventions

Services are `@MainActor final class ObservableObject` with a `static let
shared` (see [ADR 0003](../adr/0003-mainactor-singletons.md)). Heavy I/O
goes into private actors or `Task`s.

## Error handling

Network-adjacent services route failures through
`ErrorReporter.shared.report(category: .network, …)`, with a user message
only when the failure is operator-actionable (dead endpoint, unreachable
peer). Cache paths that fail silently use `category: .storage` for audit.

## Retry

Network calls use `RetryPolicy` (PR-A5) — `.default`, `.aggressive`, or
`.gentle` preset depending on tolerance. Exponential backoff with jitter,
respects cancellation.

## Testing

`IntegrationHealthMonitorTests` exercises the probe state machine with
synthetic closures (no real network). `RetryPolicyTests` covers
success/failure/exhaustion/cancel paths.
