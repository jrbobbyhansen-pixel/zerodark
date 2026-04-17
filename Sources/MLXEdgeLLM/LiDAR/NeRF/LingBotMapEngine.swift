// LingBotMapEngine.swift — Protocol + voxel fallback for LingBot-Map streaming 3D reconstruction
//
// LingBot-Map (April 2026) insight: autoregressive streaming state + Geometric Context Attention.
// This protocol abstracts the backend so VoxelStreamMap runs today and LingBotCoreMLEngine
// slots in with a single line change when .mlpackage weights ship.

import Foundation
import simd

// MARK: - Protocol

/// Backend-agnostic streaming 3D reconstruction engine.
/// Current backend: VoxelLingBotEngine (TSDF + GCA keyframes, Metal-accelerated).
/// Future backend: LingBotCoreMLEngine (uncomment when CoreML weights ship).
protocol LingBotMapEngine: AnyObject, Sendable {
    /// Ingest one processed frame into the streaming map state.
    /// Must be safe to call from a non-main, non-UI thread.
    func integrateFrame(
        points: [SIMD3<Float>],
        normals: [SIMD3<Float>]?,
        cameraTransform: simd_float4x4,
        intrinsics: simd_float3x3,
        timestamp: Float
    ) async

    /// Query current cover candidates without blocking the frame loop.
    /// Returns (worldPosition, protectionScore 0–1).
    func queryCoverCandidates() -> [(position: SIMD3<Float>, protection: Float)]

    /// Filename (not full path) of the serialized voxel map in the scan directory.
    /// Nil until the first snapshot is written.
    var streamingMapRef: String? { get }

    /// Approximate wall-clock time (ms) spent in the last integrateFrame call.
    var lastFrameMs: Double { get }
}

// MARK: - Voxel Fallback (active today)

/// Wraps VoxelStreamMap to satisfy LingBotMapEngine. This is what runs in production
/// until CoreML weights are available.
final class VoxelLingBotEngine: LingBotMapEngine, @unchecked Sendable {

    let map: VoxelStreamMap   // internal — allows snapshotToDisk from saveScanAsync
    private(set) var lastFrameMs: Double = 0

    init(config: VoxelStreamMap.Config = .init()) {
        self.map = VoxelStreamMap(config: config)
    }

    func integrateFrame(
        points: [SIMD3<Float>],
        normals: [SIMD3<Float>]?,
        cameraTransform: simd_float4x4,
        intrinsics: simd_float3x3,
        timestamp: Float
    ) async {
        let t0 = Date()
        map.integrateFrame(
            points: points,
            cameraTransform: cameraTransform,
            timestamp: timestamp
        )
        lastFrameMs = Date().timeIntervalSince(t0) * 1000
    }

    func queryCoverCandidates() -> [(position: SIMD3<Float>, protection: Float)] {
        map.queryCoverCandidates()
    }

    var streamingMapRef: String? {
        map.snapshotURL()?.lastPathComponent
    }
}

// MARK: - CoreML Stub (uncomment when LingBot-Map weights ship)
//
// Swap-in procedure:
//  1. Add LingBotMap.mlpackage to Xcode bundle and ArmDeviceView download row.
//  2. Uncomment LingBotCoreMLEngine below, implement integrateFrame against
//     the generated LingBotMapModel class from the .mlpackage.
//  3. In LiDARCaptureEngine.startScan(), change ONE line:
//       self.lingBotEngine = VoxelLingBotEngine(config: ...)
//     to:
//       self.lingBotEngine = LingBotCoreMLEngine()
//  4. Nothing else changes — protocol surface is frozen.
//
// Input format (LingBot-Map paper spec):
//   - Point cloud encoded as 518×378 depth feature map (MLMultiArray, Float32)
//   - Camera pose as 4×4 matrix (MLMultiArray)
//   - Previous compact state from last inference (autoregressive input)
//   - Outputs: updated compact state + surface logits (cover/threat classification)

/*
import CoreML

final class LingBotCoreMLEngine: LingBotMapEngine, @unchecked Sendable {

    private var model: LingBotMapModel?   // MLModel subclass generated from .mlpackage
    private var compactState: MLMultiArray?
    private(set) var lastFrameMs: Double = 0
    private var _streamingMapRef: String?
    var streamingMapRef: String? { _streamingMapRef }

    init() {
        // Load from Documents/Models/lingbot/ (downloaded via ArmDeviceView)
        let modelsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models/lingbot")
        let packageURL = modelsDir.appendingPathComponent("LingBotMap.mlpackage")
        if let compiledURL = try? MLModel.compileModel(at: packageURL),
           let loaded = try? LingBotMapModel(contentsOf: compiledURL) {
            self.model = loaded
        }
    }

    func integrateFrame(
        points: [SIMD3<Float>],
        normals: [SIMD3<Float>]?,
        cameraTransform: simd_float4x4,
        intrinsics: simd_float3x3,
        timestamp: Float
    ) async {
        guard let model else { return }
        let t0 = Date()

        // 1. Encode points as 518×378 depth feature map
        // let depthFeature = encodePoints(points, intrinsics: intrinsics)

        // 2. Encode camera pose
        // let poseFeature = encodePose(cameraTransform)

        // 3. Run inference: prediction updates compact state + outputs surface logits
        // let input = LingBotMapModelInput(depthMap: depthFeature, pose: poseFeature, state: compactState)
        // let output = try? model.prediction(input: input)
        // compactState = output?.updatedState

        // 4. Decode surface logits → cover/threat positions
        // (implementation depends on model output spec)

        lastFrameMs = Date().timeIntervalSince(t0) * 1000
    }

    func queryCoverCandidates() -> [(position: SIMD3<Float>, protection: Float)] {
        // Decode from compactState when model is available
        return []
    }
}
*/
