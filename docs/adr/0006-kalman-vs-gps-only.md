# ADR 0006 — Kalman-filtered dead-reckoning over GPS-only

**Status:** Accepted
**Date:** 2026-03-01

## Context

GPS is unreliable in the environments ZeroDark is designed for: under dense
canopy, in caves, inside buildings, in urban canyons. A GPS-only navigation
stack drops updates, jumps 50m on reacquisition, and fails silently.

## Decision

The nav stack (`DeadReckoningEngine` + `BreadcrumbEngine`) runs an
**extended Kalman filter** that fuses:

- **GPS** (CoreLocation) when available, weighted by reported accuracy.
- **Inertial** (CoreMotion) — accelerometer + gyro + pedometer for step
  detection.
- **Zero-velocity updates (ZUPT)** — when pedometer says the operator is
  still, snap velocity to zero and resample covariance.
- **Canopy detection** from raw GPS PDOP; drops GPS weight when under canopy.
- **Celestial fix** (`CelestialNavigator`) — rare, manual, but zero-bias.

## Consequences

- Position quality is a continuous value (EKF uncertainty radius) instead of
  a binary "have fix / no fix". UI surfaces the radius directly in
  `MapTabView` (`navState.ekfUncertainty`).
- Tests for nav correctness are harder — GPS simulation must model dropout
  patterns, not just steady fixes.
- Battery cost is higher: gyro sampling can't be cheaped out without
  breaking ZUPT.
- The EKF's process-noise parameters are tuned empirically. Changes require
  simulator runs against the `PureLogicTests` fixture set.

## When to revisit

If cheaper SoC-integrated sensor fusion becomes available through a new
iOS API (Sensor Kit variants, visual-inertial odometry upgrades), revisit
whether our hand-rolled EKF still adds value over the platform's defaults.
