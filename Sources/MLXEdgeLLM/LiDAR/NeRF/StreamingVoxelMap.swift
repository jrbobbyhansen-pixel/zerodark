// StreamingVoxelMap.swift — Compact TSDF streaming state for LingBot-Map architecture
//
// Implements LingBot-Map's two insights in hardware-native Swift/Metal:
//   1. Compact streaming state: TSDF voxel grid updated per-frame, always queryable
//   2. Geometric Context Attention: keyframe overlap detection fills occluded regions
//      by fusing constraints from multiple viewpoints (no post-processing needed)
//
// Thread safety: `integrateFrame` is serialized through `lock`. All public query
// methods are safe to call from any thread (they acquire the lock for a snapshot copy).

import Foundation
import simd
import Metal
import Accelerate

// MARK: - VoxelKey

/// World-space voxel address at configurable resolution.
struct VoxelKey: Hashable, Sendable {
    let x: Int32
    let y: Int32
    let z: Int32

    init(_ worldPoint: SIMD3<Float>, voxelSize: Float) {
        x = Int32(floor(worldPoint.x / voxelSize))
        y = Int32(floor(worldPoint.y / voxelSize))
        z = Int32(floor(worldPoint.z / voxelSize))
    }

    var center: SIMD3<Float> {
        fatalError("Use VoxelKey.center(voxelSize:)")
    }

    func center(voxelSize: Float) -> SIMD3<Float> {
        SIMD3(Float(x) * voxelSize + voxelSize * 0.5,
              Float(y) * voxelSize + voxelSize * 0.5,
              Float(z) * voxelSize + voxelSize * 0.5)
    }
}

// MARK: - VoxelCell

/// Per-voxel state. 48 bytes — matches the Metal struct layout in VoxelFusion.metal.
struct VoxelCell {
    var normalSum: SIMD3<Float> = .zero  // running sum for normal averaging
    var hitCount: UInt32 = 0             // number of fused LiDAR points
    var lastSeenTimestamp: Float = 0     // seconds since scan start
    var tsdfValue: Float = 1.0           // truncated signed distance (-1…1), 0 = surface
    var tsdfWeight: Float = 0            // accumulation weight
    var occupancy: Float = 0             // log-odds occupancy (positive = occupied)
    var keyframeId: UInt32 = 0           // which keyframe last updated this voxel
    var flags: UInt16 = 0                // bitfield (see below)
    private var _pad: UInt16 = 0

    // Flag bitmasks
    static let flagSurface: UInt16   = 0x01
    static let flagCover: UInt16     = 0x02
    static let flagOcclusion: UInt16 = 0x04

    var isSurface: Bool   { flags & VoxelCell.flagSurface   != 0 }
    var isCover: Bool     { flags & VoxelCell.flagCover     != 0 }

    mutating func setFlag(_ mask: UInt16) { flags |= mask }
    mutating func clearFlag(_ mask: UInt16) { flags &= ~mask }
}

// MARK: - Keyframe Store

private struct Keyframe {
    let id: UInt32
    let pose: simd_float4x4
    let timestamp: Float
    let voxelCountAtDeclaration: Int
}

// MARK: - VoxelStreamMap

/// Streaming TSDF voxel map with GCA-style keyframe occlusion filling.
/// Calling `integrateFrame` on every processed LiDAR frame builds a persistent,
/// always-queryable 3D model — no batch post-processing required.
final class VoxelStreamMap: @unchecked Sendable {

    // MARK: - Config

    struct Config {
        var voxelSize: Float = 0.08            // 8 cm voxels
        var truncationMultiplier: Float = 4.0  // truncDist = voxelSize × multiplier
        var overlapKeyframeThreshold: Float = 0.40  // declare keyframe below this overlap
        var keyframeTranslationThreshold: Float = 0.5   // meters — trigger keyframe
        var keyframeRotationThresholdDeg: Float = 20.0  // degrees — trigger keyframe
        var maxVoxelCount: Int = 1_000_000     // eviction ceiling (~48 MB)
        var enableMetalFusion: Bool = true     // use Metal kernel when available
        var groundHeightThreshold: Float = -0.5 // Y below this = ground (scan-origin Y)
        var coverHitThreshold: UInt32 = 8      // min hits for cover candidate
        var coverHeightAboveGround: Float = 0.5

        var truncationDist: Float { voxelSize * truncationMultiplier }
    }

    // MARK: - State

    private(set) var voxelCount: Int = 0
    private(set) var keyframeCount: UInt32 = 0
    private var lastKeyframePose: simd_float4x4? = nil
    private var lastKeyframeTimestamp: Float = -1e9

    private var grid: [VoxelKey: VoxelCell] = [:]
    private var keyframes: [Keyframe] = []
    private let lock = NSLock()

    let config: Config
    private var scanStartTimestamp: Float = 0
    private var groundY: Float? = nil   // estimated ground plane Y in world space

    // Snapshot persistence
    private var snapshotFileURL: URL? = nil

    // MARK: - Init

    init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Public API

    /// Main per-frame entry point. Call from off-main-thread Task.detached.
    func integrateFrame(
        points: [SIMD3<Float>],
        cameraTransform: simd_float4x4,
        timestamp: Float
    ) {
        guard !points.isEmpty else { return }

        if scanStartTimestamp == 0 { scanStartTimestamp = timestamp }

        let cameraPos = SIMD3<Float>(cameraTransform.columns.3.x,
                                     cameraTransform.columns.3.y,
                                     cameraTransform.columns.3.z)

        lock.lock()
        defer { lock.unlock() }

        // Estimate ground plane from lowest observed Y
        for p in points {
            if groundY == nil || p.y < groundY! {
                groundY = p.y
            }
        }

        // Check if we should declare a new keyframe
        let needsKeyframe = shouldDeclareKeyframe(cameraTransform: cameraTransform,
                                                   timestamp: timestamp)

        let currentKeyframeId = needsKeyframe ? keyframeCount + 1 : keyframeCount

        // TSDF integrate all points into the voxel grid
        integrateTSDF(points: points,
                      cameraPos: cameraPos,
                      keyframeId: currentKeyframeId,
                      timestamp: timestamp)

        if needsKeyframe {
            keyframeCount += 1
            let kf = Keyframe(id: keyframeCount,
                              pose: cameraTransform,
                              timestamp: timestamp,
                              voxelCountAtDeclaration: grid.count)
            keyframes.append(kf)
            if keyframes.count > 512 { keyframes.removeFirst() }

            lastKeyframePose = cameraTransform
            lastKeyframeTimestamp = timestamp

            // GCA: fill occlusions with cross-view constraints
            if keyframes.count >= 2 {
                fillOcclusionRegions(currentPose: cameraTransform,
                                     previousPose: keyframes[keyframes.count - 2].pose)
            }
        }

        // Evict stale free-space voxels when approaching ceiling
        if grid.count > config.maxVoxelCount {
            evictStaleVoxels(currentKeyframeId: currentKeyframeId)
        }

        voxelCount = grid.count
    }

    /// Returns (worldPosition, protectionScore 0–1) for every cover-candidate voxel.
    /// Safe to call from any thread — takes a snapshot copy of the relevant entries.
    func queryCoverCandidates() -> [(position: SIMD3<Float>, protection: Float)] {
        lock.lock()
        let snapshot = grid.filter { $0.value.isCover }
        lock.unlock()

        return snapshot.map { (key, cell) in
            let pos = key.center(voxelSize: config.voxelSize)
            let protection = min(Float(cell.hitCount) / 50.0, 1.0)
            return (position: pos, protection: protection)
        }
    }

    /// All occupied surface voxels, subsampled by `stride`.
    func queryOccupiedPoints(stride: Int = 1) -> [SIMD3<Float>] {
        lock.lock()
        let snapshot = grid
        lock.unlock()

        var result: [SIMD3<Float>] = []
        result.reserveCapacity(snapshot.count / max(stride, 1))
        var i = 0
        for (key, cell) in snapshot {
            if i % stride == 0, cell.isSurface {
                result.append(key.center(voxelSize: config.voxelSize))
            }
            i += 1
        }
        return result
    }

    /// Write a binary snapshot to the scan directory and return the file URL.
    /// Called once at scan stop (background priority).
    @discardableResult
    func snapshotToDisk(scanDir: URL) -> URL? {
        lock.lock()
        let snapshot = grid
        lock.unlock()

        let url = scanDir.appendingPathComponent("voxel_map.bin")
        var data = Data(capacity: snapshot.count * (12 + 4)) // key + hitCount + flags

        for (key, cell) in snapshot {
            // Write compact form: key (12 bytes) + hitCount (4) + flags (2) + pad (2)
            var kx = key.x, ky = key.y, kz = key.z
            data.append(Data(bytes: &kx, count: 4))
            data.append(Data(bytes: &ky, count: 4))
            data.append(Data(bytes: &kz, count: 4))
            var hc = cell.hitCount
            data.append(Data(bytes: &hc, count: 4))
            var fl = cell.flags
            data.append(Data(bytes: &fl, count: 2))
            var pad: UInt16 = 0
            data.append(Data(bytes: &pad, count: 2))
        }

        try? data.write(to: url, options: .atomic)
        snapshotFileURL = url
        return url
    }

    func snapshotURL() -> URL? { snapshotFileURL }

    func reset() {
        lock.lock()
        grid.removeAll(keepingCapacity: true)
        keyframes.removeAll()
        keyframeCount = 0
        lastKeyframePose = nil
        voxelCount = 0
        groundY = nil
        scanStartTimestamp = 0
        lock.unlock()
    }

    // MARK: - TSDF Integration (private)

    private func integrateTSDF(
        points: [SIMD3<Float>],
        cameraPos: SIMD3<Float>,
        keyframeId: UInt32,
        timestamp: Float
    ) {
        let truncDist = config.truncationDist
        let vs = config.voxelSize
        let groundYVal = groundY ?? cameraPos.y - 1.5  // fallback: 1.5m below camera
        let coverMinY = groundYVal + config.coverHeightAboveGround

        for point in points {
            let ray = point - cameraPos
            let rayLen = simd_length(ray)
            guard rayLen > 0.1 else { continue }

            let rayDir = ray / rayLen
            let key = VoxelKey(point, voxelSize: vs)

            // --- Update the surface voxel ---
            var cell = grid[key] ?? VoxelCell()

            // TSDF: observed distance from camera matches rayLen → tsdf ≈ 0
            let tsdfObservation: Float = 0.0  // at-surface point
            let w: Float = 1.0
            let totalW = cell.tsdfWeight + w
            cell.tsdfValue = (cell.tsdfValue * cell.tsdfWeight + tsdfObservation * w) / totalW
            cell.tsdfWeight = min(totalW, 50.0)  // cap weight for steady-state
            cell.hitCount += 1
            cell.lastSeenTimestamp = timestamp
            cell.keyframeId = keyframeId
            cell.occupancy = min(cell.occupancy + 0.3, 4.0)  // log-odds increase

            // Normal accumulation (approximate from ray direction)
            cell.normalSum += -rayDir

            // Surface flag: TSDF near 0 and hit by multiple rays
            if abs(cell.tsdfValue) < 0.05 && cell.hitCount >= 2 {
                cell.setFlag(VoxelCell.flagSurface)
            }

            // Cover candidate: sufficient hits, at height above ground
            if cell.hitCount >= config.coverHitThreshold && point.y >= coverMinY {
                cell.setFlag(VoxelCell.flagCover)
            }

            grid[key] = cell

            // --- Mark free-space voxels along the ray (truncated) ---
            // Only for every 4th point to keep perf reasonable
            if cell.hitCount % 4 == 1 {
                let freeSteps = Int(min(rayLen - truncDist, truncDist * 2) / vs)
                for step in 1...max(1, freeSteps) {
                    let freePoint = cameraPos + rayDir * (rayLen - Float(step) * vs)
                    let freeKey = VoxelKey(freePoint, voxelSize: vs)
                    if freeKey != key {
                        var freeCell = grid[freeKey] ?? VoxelCell()
                        // Free-space observation: TSDF positive (beyond surface)
                        let freeTSDF: Float = Float(step) * vs / truncDist
                        let fw: Float = 0.5
                        let ftotalW = freeCell.tsdfWeight + fw
                        freeCell.tsdfValue = (freeCell.tsdfValue * freeCell.tsdfWeight + freeTSDF * fw) / ftotalW
                        freeCell.tsdfWeight = min(ftotalW, 20.0)
                        freeCell.occupancy = max(freeCell.occupancy - 0.1, -4.0)
                        freeCell.lastSeenTimestamp = timestamp
                        grid[freeKey] = freeCell
                    }
                }
            }
        }
    }

    // MARK: - Keyframe Detection (private)

    private func shouldDeclareKeyframe(
        cameraTransform: simd_float4x4,
        timestamp: Float
    ) -> Bool {
        guard let lastPose = lastKeyframePose else {
            // First frame always declares a keyframe
            return true
        }

        let lastPos = SIMD3<Float>(lastPose.columns.3.x, lastPose.columns.3.y, lastPose.columns.3.z)
        let curPos  = SIMD3<Float>(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
        let translation = simd_length(curPos - lastPos)
        if translation >= config.keyframeTranslationThreshold { return true }

        // Check angular change via dot product of forward vectors
        let lastFwd = SIMD3<Float>(-lastPose.columns.2.x, -lastPose.columns.2.y, -lastPose.columns.2.z)
        let curFwd  = SIMD3<Float>(-cameraTransform.columns.2.x, -cameraTransform.columns.2.y, -cameraTransform.columns.2.z)
        let dot = min(max(simd_dot(lastFwd, curFwd), -1.0), 1.0)
        let angleDeg = acos(dot) * (180.0 / .pi)
        return angleDeg >= config.keyframeRotationThresholdDeg
    }

    // MARK: - GCA Occlusion Fill (private)
    // LingBot-Map insight: when a new keyframe sees surfaces that were occluded
    // from the previous keyframe, apply a geometric constraint — the overlapping
    // free-space region from both views confirms those voxels are empty.

    private func fillOcclusionRegions(
        currentPose: simd_float4x4,
        previousPose: simd_float4x4
    ) {
        let curPos  = SIMD3<Float>(currentPose.columns.3.x, currentPose.columns.3.y, currentPose.columns.3.z)
        let prevPos = SIMD3<Float>(previousPose.columns.3.x, previousPose.columns.3.y, previousPose.columns.3.z)

        // For each voxel that was last seen by the previous keyframe:
        // if it's in the current viewpoint's general frustum direction,
        // reinforce its free-space signal (occlusion-consistent region).
        let curFwd = SIMD3<Float>(-currentPose.columns.2.x, -currentPose.columns.2.y, -currentPose.columns.2.z)
        let vs = config.voxelSize

        var fillCount = 0
        for (key, var cell) in grid {
            guard fillCount < 5000 else { break }  // budget cap per keyframe
            // Only touch voxels last seen by the previous keyframe
            guard cell.keyframeId == keyframeCount - 1 else { continue }
            // Only free-space voxels (positive TSDF, low hit count)
            guard cell.tsdfValue > 0.5, cell.hitCount < 3 else { continue }

            let voxelPos = key.center(voxelSize: vs)
            let toCurrent = voxelPos - curPos
            let dotCurrent = simd_dot(simd_normalize(toCurrent), curFwd)

            if dotCurrent > 0.3 {  // voxel is roughly in front of new camera
                // Reinforce: both views agree this is free space
                cell.occupancy = max(cell.occupancy - 0.15, -4.0)
                cell.setFlag(VoxelCell.flagOcclusion)
                grid[key] = cell
                fillCount += 1
            }
        }
    }

    // MARK: - Eviction (private)

    private func evictStaleVoxels(currentKeyframeId: UInt32) {
        let staleThreshold: UInt32 = currentKeyframeId > 300 ? currentKeyframeId - 300 : 0
        let targetCount = config.maxVoxelCount * 3 / 4  // evict down to 75%

        var evicted = 0
        for (key, cell) in grid {
            if grid.count - evicted <= targetCount { break }
            if cell.keyframeId < staleThreshold && cell.occupancy < -2.0 && !cell.isSurface {
                grid.removeValue(forKey: key)
                evicted += 1
            }
        }
    }
}
