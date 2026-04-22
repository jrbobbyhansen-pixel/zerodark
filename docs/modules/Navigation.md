# Navigation

Nav stack for ZeroDark — dead-reckoning, breadcrumbs, path planning, celestial
fixes, and the MGRS/GARS overlays for the Map tab.

## Entry points

- **`DeadReckoningEngine.shared`** — owns the EKF state, fuses GPS + IMU
  + ZUPT. Published `isActive`, `confidenceRadius`.
- **`BreadcrumbEngine.shared`** — `startRecording()` / `stopRecording()`, trail
  as `[NavTrailPoint]`.
- **`CelestialNavigator.shared`** — sextant-style fixes from sun/star
  detection. See `App/CelestialNavSheet.swift` for the UI.
- **`HybridAStarPlanner`** — path planning with turning radius + heading cost.
  Caps out at `maxIterations` (PR-C10).
- **`MGRSConverter`, `MGRSGridLines`** — lat/lon ↔ MGRS + on-map gridline
  geometry (extracted in PR-B6).

## Persistence

- `NavLogStore` stores `NavLogEntry` JSON in `Documents/NavLogs/` (currently
  orphan — not in build target; see PR-C1 notes).
- `BreadcrumbEngine` persists trail points per session.
- `ScanOverlay` data lives under `Documents/ScanOverlays/`.

## Cross-references

- EKF + hybrid nav rationale: [ADR 0006](../adr/0006-kalman-vs-gps-only.md).
- `HybridAStarPlanner` cycle/iteration safety: PR-C10.
- `GeofenceMonitor` (nav-adjacent) hysteresis: PR-C10.

## Testing

Pure-logic tests live in `Tests/MLXEdgeLLMTests/PureLogicTests.swift`
(haversine, bearing, Pareto, BM25, MinHeap). MGRS tests in
`MGRSGridLinesTests.swift`. Geofence containment + monitor hysteresis in
`GeofenceTests.swift` + `GeofenceMonitorTests.swift`.
