// GaussianSplatEngine.swift — 3D Gaussian Splatting for LiDAR range extension
// Uses LiDAR points as initialization, RGB frames for photometric training beyond 5m
// Targets 20m+ effective range from native ~5m LiDAR

import Foundation
import Metal
import MetalKit
import simd

// MARK: - Gaussian Primitive

struct Gaussian3D {
    var position: SIMD3<Float>          // World-space center
    var scale: SIMD3<Float>             // Axis-aligned scale (log-space stored)
    var rotation: simd_quatf            // Orientation quaternion
    var opacity: Float                  // Sigmoid-space opacity
    var color: SIMD3<Float>             // SH degree-0 (single RGB color)
    var confidence: Float               // 1.0 for LiDAR-seeded, 0.0-1.0 for extrapolated

    var covariance: simd_float3x3 {
        let R = simd_float3x3(rotation)
        let S = simd_float3x3(diagonal: scale * scale)
        return R * S * R.transpose
    }

    static let zero = Gaussian3D(
        position: .zero, scale: SIMD3<Float>(0.01, 0.01, 0.01),
        rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
        opacity: 0.5, color: SIMD3<Float>(0.5, 0.5, 0.5), confidence: 0
    )
}

// MARK: - Gaussian Cloud

final class GaussianCloud {
    var gaussians: [Gaussian3D]
    let maxCount: Int

    init(maxCount: Int) {
        self.maxCount = maxCount
        self.gaussians = []
        self.gaussians.reserveCapacity(maxCount)
    }

    var count: Int { gaussians.count }
    var isFull: Bool { count >= maxCount }

    func addFromLiDAR(points: [SIMD3<Float>], colors: [SIMD3<Float>]? = nil) {
        let remaining = maxCount - count
        guard remaining > 0 else { return }

        let toAdd = min(points.count, remaining)
        for i in 0..<toAdd {
            let color = colors?[i] ?? SIMD3<Float>(0.5, 0.5, 0.5)
            let gaussian = Gaussian3D(
                position: points[i],
                scale: SIMD3<Float>(0.02, 0.02, 0.02), // 2cm initial radius
                rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                opacity: 0.8,
                color: color,
                confidence: 1.0 // LiDAR-verified
            )
            gaussians.append(gaussian)
        }
    }

    func addExtrapolated(position: SIMD3<Float>, color: SIMD3<Float>, initialScale: Float = 0.05) {
        guard !isFull else { return }
        gaussians.append(Gaussian3D(
            position: position,
            scale: SIMD3<Float>(repeating: initialScale),
            rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            opacity: 0.3, // Lower initial opacity for unverified
            color: color,
            confidence: 0.0
        ))
    }

    func pruneByOpacity(threshold: Float = 0.01) {
        gaussians.removeAll { sigmoid($0.opacity) < threshold }
    }

    private func sigmoid(_ x: Float) -> Float {
        1.0 / (1.0 + exp(-x))
    }
}

// MARK: - GaussianSplatEngine

@MainActor
final class GaussianSplatEngine: ObservableObject {

    @Published private(set) var gaussianCount: Int = 0
    @Published private(set) var isTraining = false
    @Published private(set) var trainingIterations: Int = 0

    let cloud: GaussianCloud
    let trainer: GaussianTrainer
    let extrapolator: DepthExtrapolator

    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let capability: DeviceCapability

    init(capability: DeviceCapability = .current) {
        self.capability = capability
        self.device = MTLCreateSystemDefaultDevice()
        self.commandQueue = device?.makeCommandQueue()

        self.cloud = GaussianCloud(maxCount: capability.maxGaussians)
        self.trainer = GaussianTrainer(
            cloud: cloud,
            device: device,
            trainingResolution: capability.gaussianTrainingResolution
        )
        self.extrapolator = DepthExtrapolator(cloud: cloud, device: device)
    }

    // MARK: - Seed from LiDAR

    /// Initialize gaussians from LiDAR point cloud (within 5m range)
    func seedFromLiDAR(points: [SIMD3<Float>], colors: [SIMD3<Float>]? = nil) {
        // Subsample if too many points
        let targetSeedCount = capability.maxGaussians / 2 // Reserve half for extrapolation
        let stride = max(1, points.count / targetSeedCount)

        var seedPoints: [SIMD3<Float>] = []
        var seedColors: [SIMD3<Float>]? = colors != nil ? [] : nil

        for i in Swift.stride(from: 0, to: points.count, by: stride) {
            seedPoints.append(points[i])
            if let colors { seedColors?.append(colors[i]) }
        }

        cloud.addFromLiDAR(points: seedPoints, colors: seedColors)
        gaussianCount = cloud.count
    }

    // MARK: - Training Step

    /// Run one incremental training step using an RGB frame and LiDAR depth
    func train(
        rgbBuffer: CVPixelBuffer,
        depthBuffer: CVPixelBuffer?,
        cameraTransform: simd_float4x4,
        intrinsics: simd_float3x3,
        lidarMaxRange: Float = 5.0
    ) {
        guard !cloud.gaussians.isEmpty else { return }
        isTraining = true

        trainer.trainStep(
            rgbBuffer: rgbBuffer,
            depthBuffer: depthBuffer,
            cameraTransform: cameraTransform,
            intrinsics: intrinsics,
            lidarMaxRange: lidarMaxRange,
            iterations: 100
        )

        trainingIterations += 100
        gaussianCount = cloud.count
        isTraining = false
    }

    // MARK: - Range Extension

    /// Extract extended-range points by rendering depth from gaussians beyond LiDAR range
    func extendedPoints(
        cameraTransform: simd_float4x4,
        intrinsics: simd_float3x3,
        lidarMaxRange: Float = 5.0,
        maxExtendedRange: Float = 20.0
    ) -> [SIMD3<Float>] {
        return extrapolator.extractExtendedPoints(
            cameraTransform: cameraTransform,
            intrinsics: intrinsics,
            minRange: lidarMaxRange,
            maxRange: maxExtendedRange
        )
    }

    // MARK: - Maintenance

    func prune() {
        cloud.pruneByOpacity(threshold: 0.01)
        gaussianCount = cloud.count
    }

    func reset() {
        cloud.gaussians.removeAll()
        gaussianCount = 0
        trainingIterations = 0
    }
}
