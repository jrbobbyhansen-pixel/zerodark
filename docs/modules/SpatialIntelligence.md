# SpatialIntelligence + LiDAR

LiDAR capture, mesh analysis, scan storage, 3D export.

## Entry points

- **`LiDARCaptureEngine.shared`** — ARKit-backed scan session. Two modes
  (QuickScan + ReconWalk). Emits `lastScanResult` with
  meshAnchors + pointCloud on completion.
- **`LiDARExportWriters`** — pure functions for PLY binary +
  USDZ export, extracted in PR-B7 from the engine.
- **`ScanStorage.shared`** — on-disk index of saved scans. 10 GB storage
  cap with oldest-first eviction (PR-C1).
- **`TacticalRoomAnalyzer`** — classifies scan points into entries / cover /
  targets; drives the Room Intel report.
- **`VoxelFusion.metal`** — GPU shader for merging streaming point clouds
  into a voxel grid (kept in `LiDAR/NeRF/`).
- **`GaussianTrainer`** — training loop with NaN guards + plateau
  convergence (PR-A2).

## File layout

- `Sources/MLXEdgeLLM/SpatialIntelligence/LiDAR/` — capture + storage.
- `Sources/MLXEdgeLLM/LiDAR/` — analysis + NeRF/Gaussian.
- `Sources/MLXEdgeLLM/SpatialIntelligence/` — higher-level geometry helpers
  (`AreaCalculator`, `DistanceBearing`, `ElevationProfile`, etc.).

## Testing

`LiDARExportWritersTests` covers binary point-cloud round-trip (empty,
single, multi-point, chunk boundary). USDZ path is not covered — needs
real `ARMeshAnchor` objects which can't be synthesized in tests.
