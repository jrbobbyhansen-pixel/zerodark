# ADR 0001 — Offline-first architecture

**Status:** Accepted
**Date:** 2026-03-01

## Context

ZeroDark targets tactical / SAR operators who routinely work with no cellular
or Wi-Fi coverage for hours at a time. Every external-network round-trip is a
liability: a feature that silently stops working in a dead zone is worse than
no feature at all.

## Decision

**Everything is offline-first.** Network access is additive, never required.

- **AI inference** runs on-device via MLX (Phi-3.5 and friends). No cloud LLM.
- **Maps** come from on-disk tile packs (PMTiles) with SRTM terrain cached locally.
  See also ADR 0002.
- **Peer comms** go over Multipeer (Bluetooth + peer-to-peer Wi-Fi). No TAK
  server dependency for basic ops.
- **Weather, threat feeds, SRTM** are cached aggressively; the
  `IntegrationHealthMonitor` (PR-B5) makes the offline/degraded state visible
  to operators instead of silently failing open.

## Consequences

- Binary size is large (~several hundred MB with models + tile packs). We
  accept this; operators cannot download on-site.
- Every network call must degrade gracefully. `try?` silently dropping a
  failed request is a banned pattern — use `ErrorReporter` (PR-A5) so the
  operator sees what's unavailable.
- Cloud-only features (Firebase Crashlytics, etc.) stay in scaffold form
  until a clear offline story exists (local breadcrumb buffer + sync on
  reconnect).
