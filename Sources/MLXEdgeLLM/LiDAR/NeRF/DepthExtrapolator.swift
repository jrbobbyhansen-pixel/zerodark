// DepthExtrapolator.swift — Extracts extended-range 3D points from trained gaussians
// Renders depth from gaussian model, masks LiDAR-covered region, converts to 3D points

import Foundation
import Metal
import simd

// MARK: - DepthExtrapolator

final class DepthExtrapolator {

    private let cloud: GaussianCloud
    private let device: MTLDevice?

    // Render resolution for depth extraction (quarter of camera resolution)
    private let renderWidth: Int = 480
    private let renderHeight: Int = 360

    init(cloud: GaussianCloud, device: MTLDevice?) {
        self.cloud = cloud
        self.device = device
    }

    // MARK: - Extended Point Extraction

    /// Render depth from gaussian model and extract points beyond LiDAR range.
    ///
    /// - Parameters:
    ///   - cameraTransform: Current camera pose in world space
    ///   - intrinsics: Camera intrinsic matrix
    ///   - minRange: LiDAR max range (points closer are already covered)
    ///   - maxRange: Maximum extrapolation range
    /// - Returns: Array of 3D world-space points in the extended range
    func extractExtendedPoints(
        cameraTransform: simd_float4x4,
        intrinsics: simd_float3x3,
        minRange: Float = 5.0,
        maxRange: Float = 20.0
    ) -> [SIMD3<Float>] {
        guard !cloud.gaussians.isEmpty else { return [] }

        let viewMatrix = cameraTransform.inverse

        // Render depth map from gaussians
        let depthMap = renderDepthMap(viewMatrix: viewMatrix, intrinsics: intrinsics)

        // Extract points only in the extended range (beyond LiDAR, within max)
        var extendedPoints: [SIMD3<Float>] = []
        extendedPoints.reserveCapacity(renderWidth * renderHeight / 16) // Sparse expectation

        // Scale intrinsics to render resolution
        let fx = intrinsics[0][0] * Float(renderWidth) / (intrinsics[2][0] * 2)
        let fy = intrinsics[1][1] * Float(renderHeight) / (intrinsics[2][1] * 2)
        let cx = Float(renderWidth) / 2.0
        let cy = Float(renderHeight) / 2.0

        // Subsample for performance (every 4th pixel)
        let step = 4
        for y in stride(from: 0, to: renderHeight, by: step) {
            for x in stride(from: 0, to: renderWidth, by: step) {
                let depth = depthMap[y][x]
                guard depth > minRange && depth < maxRange else { continue }

                // Unproject to camera space
                let camX = (Float(x) - cx) * depth / fx
                let camY = (Float(y) - cy) * depth / fy
                let camZ = -depth // ARKit: -z forward

                // Transform to world space
                let worldPoint = cameraTransform * SIMD4<Float>(camX, -camY, camZ, 1.0)
                extendedPoints.append(SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z))
            }
        }

        return extendedPoints
    }

    // MARK: - Depth Rendering

    private func renderDepthMap(viewMatrix: simd_float4x4, intrinsics: simd_float3x3) -> [[Float]] {
        var depthMap = [[Float]](
            repeating: [Float](repeating: Float.greatestFiniteMagnitude, count: renderWidth),
            count: renderHeight
        )

        // Scale intrinsics
        let fx = intrinsics[0][0] * Float(renderWidth) / (intrinsics[2][0] * 2)
        let fy = intrinsics[1][1] * Float(renderHeight) / (intrinsics[2][1] * 2)
        let cx = Float(renderWidth) / 2.0
        let cy = Float(renderHeight) / 2.0

        // Sort gaussians front-to-back for early depth rejection
        let sorted = cloud.gaussians
            .map { g -> (Gaussian3D, Float) in
                let viewPos = viewMatrix * SIMD4<Float>(g.position, 1.0)
                return (g, -viewPos.z)
            }
            .filter { $0.1 > 0.1 } // In front of camera
            .sorted { $0.1 < $1.1 } // Front to back

        for (gaussian, viewDepth) in sorted {
            let opacity = sigmoid(gaussian.opacity)
            guard opacity > 0.05 else { continue } // Skip nearly transparent

            // Project to screen
            let viewPos = viewMatrix * SIMD4<Float>(gaussian.position, 1.0)
            let screenX = Int(fx * viewPos.x / (-viewPos.z) + cx)
            let screenY = Int(fy * (-viewPos.y) / (-viewPos.z) + cy)

            // Splat radius
            let radius = max(1, Int(simd_length(gaussian.scale) * fx / viewDepth))

            for dy in -radius...radius {
                for dx in -radius...radius {
                    let px = screenX + dx
                    let py = screenY + dy
                    guard px >= 0, px < renderWidth, py >= 0, py < renderHeight else { continue }

                    // Gaussian weight
                    let dist2 = Float(dx * dx + dy * dy)
                    let sigma2 = Float(radius * radius) * 0.5
                    let weight = opacity * exp(-dist2 / (2 * sigma2))

                    guard weight > 0.1 else { continue }

                    // Update depth (closest gaussian wins)
                    if viewDepth < depthMap[py][px] {
                        depthMap[py][px] = viewDepth
                    }
                }
            }
        }

        return depthMap
    }

    // MARK: - Helpers

    private func sigmoid(_ x: Float) -> Float {
        1.0 / (1.0 + exp(-x))
    }
}
