// GaussianTrainer.swift — Incremental on-device training for 3D Gaussian Splatting
// Photometric loss on RGB + depth supervision from LiDAR within 5m
// Runs 100 iterations per frame at reduced resolution via Metal compute

import Foundation
import Metal
import simd
import Accelerate

// MARK: - GaussianTrainer

final class GaussianTrainer {

    private let cloud: GaussianCloud
    private let device: MTLDevice?
    private let trainingWidth: Int
    private let trainingHeight: Int

    // Training hyperparameters
    private let learningRatePosition: Float = 0.0001
    private let learningRateScale: Float = 0.001
    private let learningRateOpacity: Float = 0.01
    private let learningRateColor: Float = 0.005
    private let depthLossWeight: Float = 0.5

    // Densification
    private var gradientAccum: [Float] = []
    private var densifyInterval: Int = 500
    private(set) var iterationCount: Int = 0

    /// Current thermal-adjusted max iterations per frame (set by pipeline)
    var maxIterationsPerFrame: Int = 100

    // MARK: - Training control

    /// Gradient L2-norm cap per parameter group. Gradients above the cap are
    /// rescaled so the vector norm equals `gradientClipNorm`. Prevents runaway
    /// updates when the photometric loss lands on a pathological pixel.
    var gradientClipNorm: Float = 10.0

    /// Convergence: training exits early if the running mean of the last N
    /// per-iteration L2 losses changes by less than `convergenceEpsilon`
    /// across `convergenceWindow` iterations.
    var convergenceWindow: Int = 50
    var convergenceEpsilon: Float = 1.0e-5

    /// Rolling loss history for convergence detection. Capped at
    /// `convergenceWindow * 2` entries so memory stays bounded.
    private var lossHistory: [Float] = []

    /// Number of consecutive training steps skipped because they produced
    /// NaN / Inf. Surfaces for diagnostics.
    private(set) var skippedNaNSteps: Int = 0

    /// Becomes true when the training loop detects convergence. Callers can
    /// stop supplying new frames until a fresh scene arrives.
    private(set) var hasConverged: Bool = false

    init(cloud: GaussianCloud, device: MTLDevice?, trainingResolution: (width: Int, height: Int)) {
        self.cloud = cloud
        self.device = device
        self.trainingWidth = trainingResolution.width
        self.trainingHeight = trainingResolution.height
    }

    // MARK: - Training Step

    func trainStep(
        rgbBuffer: CVPixelBuffer,
        depthBuffer: CVPixelBuffer?,
        cameraTransform: simd_float4x4,
        intrinsics: simd_float3x3,
        lidarMaxRange: Float,
        iterations: Int? = nil
    ) {
        guard !cloud.gaussians.isEmpty else { return }
        let actualIterations = iterations ?? maxIterationsPerFrame
        guard actualIterations > 0 else { return } // Thermal shutdown

        let viewMatrix = cameraTransform.inverse
        let projMatrix = buildProjectionMatrix(intrinsics: intrinsics, width: trainingWidth, height: trainingHeight)
        let viewProj = projMatrix * viewMatrix

        // Downsample RGB to training resolution
        let targetRGB = downsamplePixelBuffer(rgbBuffer, toWidth: trainingWidth, height: trainingHeight)
        let targetDepth: [[Float]]? = depthBuffer.map { downsampleDepthBuffer($0, toWidth: trainingWidth, height: trainingHeight) }

        for _ in 0..<actualIterations {
            iterationCount += 1

            // Forward: rasterize gaussians to image
            let rendered = rasterize(viewProj: viewProj, viewMatrix: viewMatrix)

            // Compute per-gaussian gradients via photometric + depth loss
            let gradients = computeGradients(
                rendered: rendered,
                targetRGB: targetRGB,
                targetDepth: targetDepth,
                viewProj: viewProj,
                viewMatrix: viewMatrix,
                lidarMaxRange: lidarMaxRange
            )

            // NaN/Inf guard: if ANY gradient component is non-finite, the
            // rasterizer or loss math diverged. Skip the update and mark the
            // step as dropped. Continuing would corrupt the cloud forever.
            if hasNonFiniteGradient(gradients) {
                skippedNaNSteps += 1
                continue
            }

            // Gradient clipping — rescale any per-parameter vector whose L2
            // norm exceeds `gradientClipNorm`.
            let clipped = clipGradients(gradients)

            // Apply gradients (SGD)
            applyGradients(clipped)

            // Running loss — mean absolute color error across rendered image
            // (cheap proxy for MSE without another pass).
            let loss = meanAbsoluteLoss(rendered: rendered, targetRGB: targetRGB)
            if loss.isFinite {
                lossHistory.append(loss)
                if lossHistory.count > convergenceWindow * 2 {
                    lossHistory.removeFirst(lossHistory.count - convergenceWindow * 2)
                }
            }

            // Early-exit convergence: when the mean of the last window matches
            // the mean of the previous window within epsilon, we're done.
            if lossHistory.count >= convergenceWindow * 2 {
                let firstHalf = lossHistory.prefix(convergenceWindow)
                let secondHalf = lossHistory.suffix(convergenceWindow)
                let m1 = firstHalf.reduce(0, +) / Float(convergenceWindow)
                let m2 = secondHalf.reduce(0, +) / Float(convergenceWindow)
                if abs(m1 - m2) < convergenceEpsilon {
                    hasConverged = true
                    return
                }
            }

            // Periodic densification
            if iterationCount % densifyInterval == 0 {
                densifyAndPrune()
            }
        }
    }

    // MARK: - Numerical safety helpers

    /// Returns true if ANY gradient component in any parameter group is
    /// non-finite (NaN or ±Inf). Used to skip diverged steps.
    private func hasNonFiniteGradient(_ gradients: [GaussianGradient]) -> Bool {
        for g in gradients {
            if !g.positionGrad.x.isFinite || !g.positionGrad.y.isFinite || !g.positionGrad.z.isFinite { return true }
            if !g.scaleGrad.x.isFinite    || !g.scaleGrad.y.isFinite    || !g.scaleGrad.z.isFinite    { return true }
            if !g.opacityGrad.isFinite                                                                { return true }
            if !g.colorGrad.x.isFinite    || !g.colorGrad.y.isFinite    || !g.colorGrad.z.isFinite    { return true }
        }
        return false
    }

    /// Clip each gradient vector to `gradientClipNorm` L2 norm.
    private func clipGradients(_ gradients: [GaussianGradient]) -> [GaussianGradient] {
        let maxNorm = gradientClipNorm
        return gradients.map { g in
            var out = g
            let posN = simd_length(g.positionGrad)
            if posN > maxNorm { out.positionGrad = g.positionGrad * (maxNorm / posN) }
            let scaN = simd_length(g.scaleGrad)
            if scaN > maxNorm { out.scaleGrad = g.scaleGrad * (maxNorm / scaN) }
            if abs(g.opacityGrad) > maxNorm { out.opacityGrad = g.opacityGrad > 0 ? maxNorm : -maxNorm }
            let colN = simd_length(g.colorGrad)
            if colN > maxNorm { out.colorGrad = g.colorGrad * (maxNorm / colN) }
            return out
        }
    }

    /// Cheap mean-absolute-error between rendered and target RGB. Used for
    /// convergence tracking; not the exact objective being optimized.
    private func meanAbsoluteLoss(
        rendered: [[RasterizedPixel]],
        targetRGB: [[SIMD3<Float>]]
    ) -> Float {
        var sum: Float = 0
        var count: Int = 0
        for y in 0..<trainingHeight {
            for x in 0..<trainingWidth {
                let r = rendered[y][x].color
                let t = targetRGB[y][x]
                let d = abs(r.x - t.x) + abs(r.y - t.y) + abs(r.z - t.z)
                if d.isFinite { sum += d; count += 1 }
            }
        }
        return count > 0 ? sum / Float(count) : 0
    }

    /// Reset convergence tracking when a fresh scene / camera pose arrives.
    /// Callers should invoke this on scan boundaries so convergence from a
    /// previous room doesn't short-circuit new training.
    func resetConvergence() {
        lossHistory.removeAll(keepingCapacity: true)
        hasConverged = false
    }

    // MARK: - Software Rasterizer (CPU fallback)

    private struct RasterizedPixel {
        var color: SIMD3<Float> = .zero
        var depth: Float = Float.greatestFiniteMagnitude
        var alpha: Float = 0
        var gaussianIndex: Int = -1
    }

    private func rasterize(viewProj: simd_float4x4, viewMatrix: simd_float4x4) -> [[RasterizedPixel]] {
        var image = [[RasterizedPixel]](
            repeating: [RasterizedPixel](repeating: RasterizedPixel(), count: trainingWidth),
            count: trainingHeight
        )

        // Sort gaussians by depth (back to front for alpha compositing)
        let sorted = cloud.gaussians.enumerated()
            .map { (index: $0.offset, gaussian: $0.element, depth: projectDepth($0.element.position, viewMatrix: viewMatrix)) }
            .filter { $0.depth > 0.1 } // Behind camera clip
            .sorted { $0.depth > $1.depth } // Back to front

        for entry in sorted {
            let g = entry.gaussian
            let projected = viewProj * SIMD4<Float>(g.position, 1.0)
            guard projected.w > 0 else { continue }

            let ndc = SIMD2<Float>(projected.x / projected.w, projected.y / projected.w)
            let screenX = Int((ndc.x * 0.5 + 0.5) * Float(trainingWidth))
            let screenY = Int((1.0 - (ndc.y * 0.5 + 0.5)) * Float(trainingHeight))

            // Splat radius based on scale and depth
            let radius = max(1, Int(simd_length(g.scale) * Float(trainingWidth) / entry.depth))
            let opacity = sigmoid(g.opacity)

            for dy in -radius...radius {
                for dx in -radius...radius {
                    let px = screenX + dx
                    let py = screenY + dy
                    guard px >= 0, px < trainingWidth, py >= 0, py < trainingHeight else { continue }

                    // Gaussian falloff
                    let dist2 = Float(dx * dx + dy * dy)
                    let sigma2 = Float(radius * radius) * 0.5
                    let weight = opacity * exp(-dist2 / (2 * sigma2))

                    // Alpha compositing
                    let existing = image[py][px]
                    let newAlpha = existing.alpha + weight * (1.0 - existing.alpha)
                    let blendWeight = weight * (1.0 - existing.alpha)

                    image[py][px].color = existing.color + blendWeight * g.color
                    image[py][px].alpha = newAlpha
                    image[py][px].depth = min(existing.depth, entry.depth)
                    image[py][px].gaussianIndex = entry.index
                }
            }
        }

        return image
    }

    // MARK: - Gradient Computation

    private struct GaussianGradient {
        var positionGrad: SIMD3<Float> = .zero
        var scaleGrad: SIMD3<Float> = .zero
        var opacityGrad: Float = 0
        var colorGrad: SIMD3<Float> = .zero
    }

    private func computeGradients(
        rendered: [[RasterizedPixel]],
        targetRGB: [[SIMD3<Float>]],
        targetDepth: [[Float]]?,
        viewProj: simd_float4x4,
        viewMatrix: simd_float4x4,
        lidarMaxRange: Float
    ) -> [GaussianGradient] {
        var gradients = [GaussianGradient](repeating: GaussianGradient(), count: cloud.count)

        for y in 0..<trainingHeight {
            for x in 0..<trainingWidth {
                let pixel = rendered[y][x]
                guard pixel.gaussianIndex >= 0 && pixel.gaussianIndex < cloud.count else { continue }

                // Photometric loss gradient (L2)
                let colorDiff = pixel.color - targetRGB[y][x]
                gradients[pixel.gaussianIndex].colorGrad += colorDiff * 2.0

                // Depth loss (only within LiDAR range)
                if let targetDepth, targetDepth[y][x] < lidarMaxRange && pixel.depth < 100 {
                    let depthDiff = pixel.depth - targetDepth[y][x]
                    gradients[pixel.gaussianIndex].positionGrad += SIMD3<Float>(0, 0, depthDiff * depthLossWeight)
                }
            }
        }

        return gradients
    }

    // MARK: - Gradient Application

    private func applyGradients(_ gradients: [GaussianGradient]) {
        for i in 0..<min(gradients.count, cloud.gaussians.count) {
            let grad = gradients[i]

            cloud.gaussians[i].position -= learningRatePosition * grad.positionGrad
            cloud.gaussians[i].scale -= learningRateScale * grad.scaleGrad
            cloud.gaussians[i].opacity -= learningRateOpacity * grad.opacityGrad
            cloud.gaussians[i].color -= learningRateColor * grad.colorGrad

            // Clamp scale to prevent degenerate gaussians
            cloud.gaussians[i].scale = simd_max(cloud.gaussians[i].scale, SIMD3<Float>(repeating: 0.001))
        }
    }

    // MARK: - Densification

    private func densifyAndPrune() {
        // Remove near-transparent gaussians
        cloud.pruneByOpacity(threshold: 0.005)

        // Split large gaussians that span too much area
        var toAdd: [Gaussian3D] = []
        for i in 0..<cloud.gaussians.count {
            let g = cloud.gaussians[i]
            let maxScale = simd_max(g.scale.x, simd_max(g.scale.y, g.scale.z))
            if maxScale > 0.1 && !cloud.isFull { // > 10cm splat
                // Split into two smaller gaussians
                let offset = g.scale * 0.5
                var g1 = g
                var g2 = g
                g1.position += SIMD3<Float>(offset.x, 0, 0)
                g2.position -= SIMD3<Float>(offset.x, 0, 0)
                g1.scale *= 0.5
                g2.scale *= 0.5
                cloud.gaussians[i] = g1
                toAdd.append(g2)
            }
        }

        for g in toAdd where !cloud.isFull {
            cloud.gaussians.append(g)
        }
    }

    // MARK: - Helpers

    private func projectDepth(_ position: SIMD3<Float>, viewMatrix: simd_float4x4) -> Float {
        let viewPos = viewMatrix * SIMD4<Float>(position, 1.0)
        return -viewPos.z // ARKit: -z is forward
    }

    private func sigmoid(_ x: Float) -> Float {
        1.0 / (1.0 + exp(-x))
    }

    private func buildProjectionMatrix(intrinsics: simd_float3x3, width: Int, height: Int) -> simd_float4x4 {
        let fx = intrinsics[0][0]
        let fy = intrinsics[1][1]
        let cx = intrinsics[2][0]
        let cy = intrinsics[2][1]
        let near: Float = 0.1
        let far: Float = 30.0

        // Scale intrinsics to training resolution
        let scaleX = Float(width) / (cx * 2)
        let scaleY = Float(height) / (cy * 2)
        let fxs = fx * scaleX
        let fys = fy * scaleY

        return simd_float4x4(columns: (
            SIMD4<Float>(2 * fxs / Float(width), 0, 0, 0),
            SIMD4<Float>(0, 2 * fys / Float(height), 0, 0),
            SIMD4<Float>(0, 0, -(far + near) / (far - near), -1),
            SIMD4<Float>(0, 0, -2 * far * near / (far - near), 0)
        ))
    }

    private func downsamplePixelBuffer(_ buffer: CVPixelBuffer, toWidth width: Int, height: Int) -> [[SIMD3<Float>]] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let srcWidth = CVPixelBufferGetWidth(buffer)
        let srcHeight = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        var result = [[SIMD3<Float>]](
            repeating: [SIMD3<Float>](repeating: .zero, count: width),
            count: height
        )

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return result }
        let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)

        for y in 0..<height {
            let srcY = y * srcHeight / height
            for x in 0..<width {
                let srcX = x * srcWidth / width
                let offset = srcY * bytesPerRow + srcX * 4
                let r = Float(ptr[offset]) / 255.0
                let g = Float(ptr[offset + 1]) / 255.0
                let b = Float(ptr[offset + 2]) / 255.0
                result[y][x] = SIMD3<Float>(r, g, b)
            }
        }

        return result
    }

    private func downsampleDepthBuffer(_ buffer: CVPixelBuffer, toWidth width: Int, height: Int) -> [[Float]] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let srcWidth = CVPixelBufferGetWidth(buffer)
        let srcHeight = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        var result = [[Float]](
            repeating: [Float](repeating: Float.greatestFiniteMagnitude, count: width),
            count: height
        )

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return result }

        for y in 0..<height {
            let srcY = y * srcHeight / height
            for x in 0..<width {
                let srcX = x * srcWidth / width
                let offset = srcY * bytesPerRow + srcX * MemoryLayout<Float32>.size
                let ptr = baseAddress.advanced(by: offset).assumingMemoryBound(to: Float32.self)
                result[y][x] = ptr.pointee
            }
        }

        return result
    }
}
