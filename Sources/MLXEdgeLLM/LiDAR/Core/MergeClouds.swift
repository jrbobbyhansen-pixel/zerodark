// MergeClouds.swift — Point-to-plane ICP for multi-scan registration
// Iteratively aligns a target point cloud to a base cloud using
// closest-point correspondences and least-squares rigid transform
// Post-merge voxel downsampling removes overlap duplicates

import Foundation
import simd

// MARK: - Merge Result

struct MergeResult {
    let mergedPoints: [SIMD3<Float>]
    let transform: simd_float4x4        // Final alignment transform applied to target
    let meanResidual: Float              // Final mean point-to-point distance
    let iterations: Int
    let overlap: Float                   // Fraction of target points that found correspondences
}

// MARK: - Quality Assessment

struct MergeQuality {
    let completeness: Float   // Fraction of space covered by merged cloud vs individual
    let accuracy: Float       // Inverse of mean residual (higher = better)
    let overlapRatio: Float   // How much the two clouds overlapped
}

// MARK: - PointCloudMerger

class PointCloudMerger {

    /// Maximum ICP iterations
    var maxIterations: Int = 50

    /// Convergence threshold (meters) for mean residual change
    var convergenceThreshold: Float = 0.001

    /// Maximum correspondence distance (meters)
    var maxCorrespondenceDistance: Float = 0.5

    /// Voxel size for post-merge downsampling (meters)
    var downsampleVoxelSize: Float = 0.02

    // MARK: - Merge

    /// Merge multiple point clouds into one using sequential pairwise ICP.
    func merge(clouds: [[SIMD3<Float>]]) -> MergeResult? {
        guard !clouds.isEmpty else { return nil }
        guard clouds.count >= 2 else {
            return MergeResult(mergedPoints: clouds[0], transform: matrix_identity_float4x4,
                             meanResidual: 0, iterations: 0, overlap: 1.0)
        }

        var base = clouds[0]
        var totalTransform = matrix_identity_float4x4
        var lastResult: MergeResult?

        for i in 1..<clouds.count {
            let result = alignAndMerge(base: base, target: clouds[i])
            base = result.mergedPoints
            totalTransform = result.transform * totalTransform
            lastResult = result
        }

        return lastResult
    }

    /// Align target cloud to base using ICP, then merge.
    func alignAndMerge(base: [SIMD3<Float>], target: [SIMD3<Float>]) -> MergeResult {
        // Build voxel grid index for base (fast nearest-neighbor)
        let baseGrid = buildVoxelGrid(base)

        var alignedTarget = target
        var transform = matrix_identity_float4x4
        var prevResidual: Float = .infinity
        var finalResidual: Float = .infinity
        var iterations = 0
        var correspondenceCount = 0

        for iter in 0..<maxIterations {
            iterations = iter + 1

            // Find correspondences: for each target point, find closest base point
            var srcPoints: [SIMD3<Float>] = []
            var dstPoints: [SIMD3<Float>] = []

            for tp in alignedTarget {
                if let closest = findClosest(tp, in: base, grid: baseGrid) {
                    let dist = simd_distance(tp, closest)
                    if dist <= maxCorrespondenceDistance {
                        srcPoints.append(tp)
                        dstPoints.append(closest)
                    }
                }
            }

            correspondenceCount = srcPoints.count
            guard correspondenceCount >= 3 else { break }

            // Compute mean residual
            var totalResidual: Float = 0
            for i in 0..<srcPoints.count {
                totalResidual += simd_distance(srcPoints[i], dstPoints[i])
            }
            finalResidual = totalResidual / Float(srcPoints.count)

            // Check convergence
            if abs(prevResidual - finalResidual) < convergenceThreshold { break }
            prevResidual = finalResidual

            // Compute optimal rigid transform (SVD-based)
            let stepTransform = computeRigidTransform(from: srcPoints, to: dstPoints)
            transform = stepTransform * transform

            // Apply transform to target
            alignedTarget = alignedTarget.map { applyTransform(stepTransform, to: $0) }
        }

        // Merge and downsample
        let merged = voxelDownsample(base + alignedTarget, voxelSize: downsampleVoxelSize)
        let overlap = Float(correspondenceCount) / Float(max(1, target.count))

        return MergeResult(
            mergedPoints: merged,
            transform: transform,
            meanResidual: finalResidual,
            iterations: iterations,
            overlap: overlap
        )
    }

    /// Assess the quality of a merge.
    func assessQuality(base: [SIMD3<Float>], target: [SIMD3<Float>], result: MergeResult) -> MergeQuality {
        let completeness = Float(result.mergedPoints.count) / Float(max(1, base.count + target.count))
        let accuracy = result.meanResidual > 0 ? min(1.0, 0.01 / result.meanResidual) : 1.0

        return MergeQuality(
            completeness: min(1.0, completeness * 2), // Expect ~50% overlap
            accuracy: accuracy,
            overlapRatio: result.overlap
        )
    }

    // MARK: - SVD Rigid Transform

    /// Compute the rigid transform [R|t] that best aligns source points to destination points.
    /// Uses Kabsch algorithm: center both sets, compute cross-covariance, SVD → rotation.
    private func computeRigidTransform(from src: [SIMD3<Float>], to dst: [SIMD3<Float>]) -> simd_float4x4 {
        let n = Float(src.count)

        // Centroids
        var srcCentroid = SIMD3<Float>.zero
        var dstCentroid = SIMD3<Float>.zero
        for i in 0..<src.count {
            srcCentroid += src[i]
            dstCentroid += dst[i]
        }
        srcCentroid /= n
        dstCentroid /= n

        // Cross-covariance matrix H = Σ (src_i - centroid_src)(dst_i - centroid_dst)^T
        var h = simd_float3x3(0)
        for i in 0..<src.count {
            let s = src[i] - srcCentroid
            let d = dst[i] - dstCentroid
            h[0] += SIMD3(s.x * d.x, s.x * d.y, s.x * d.z)
            h[1] += SIMD3(s.y * d.x, s.y * d.y, s.y * d.z)
            h[2] += SIMD3(s.z * d.x, s.z * d.y, s.z * d.z)
        }

        // For a 3×3 matrix, approximate SVD via polar decomposition:
        // R = H × (H^T × H)^(-1/2)
        // Simplified: use iterative approach
        let rotation = polarDecomposition(h)
        let translation = dstCentroid - rotation * srcCentroid

        // Build 4×4 transform
        var result = simd_float4x4(1)
        result[0] = SIMD4(rotation[0], 0)
        result[1] = SIMD4(rotation[1], 0)
        result[2] = SIMD4(rotation[2], 0)
        result[3] = SIMD4(translation, 1)
        return result
    }

    /// Extract rotation matrix via polar decomposition (iterative).
    private func polarDecomposition(_ m: simd_float3x3) -> simd_float3x3 {
        var r = m
        for _ in 0..<20 {
            let rInvT = r.inverse.transpose
            r = (r + rInvT) * 0.5

            // Check convergence
            let diff = r - (r + rInvT) * 0.5
            let norm = diff[0].x * diff[0].x + diff[1].y * diff[1].y + diff[2].z * diff[2].z
            if norm < 1e-10 { break }
        }
        return r
    }

    // MARK: - Spatial Index

    private struct VoxelKey: Hashable {
        let x: Int, y: Int, z: Int
    }

    private func buildVoxelGrid(_ points: [SIMD3<Float>]) -> [VoxelKey: [Int]] {
        let size = maxCorrespondenceDistance
        var grid: [VoxelKey: [Int]] = [:]
        for (i, p) in points.enumerated() {
            let key = VoxelKey(x: Int(floor(p.x / size)), y: Int(floor(p.y / size)), z: Int(floor(p.z / size)))
            grid[key, default: []].append(i)
        }
        return grid
    }

    private func findClosest(_ point: SIMD3<Float>, in base: [SIMD3<Float>], grid: [VoxelKey: [Int]]) -> SIMD3<Float>? {
        let size = maxCorrespondenceDistance
        let cx = Int(floor(point.x / size))
        let cy = Int(floor(point.y / size))
        let cz = Int(floor(point.z / size))

        var bestDist: Float = .infinity
        var bestPoint: SIMD3<Float>?

        for dx in -1...1 {
            for dy in -1...1 {
                for dz in -1...1 {
                    guard let indices = grid[VoxelKey(x: cx + dx, y: cy + dy, z: cz + dz)] else { continue }
                    for idx in indices {
                        let d = simd_distance_squared(point, base[idx])
                        if d < bestDist {
                            bestDist = d
                            bestPoint = base[idx]
                        }
                    }
                }
            }
        }

        return bestPoint
    }

    // MARK: - Helpers

    private func applyTransform(_ t: simd_float4x4, to p: SIMD3<Float>) -> SIMD3<Float> {
        let h = t * SIMD4(p, 1)
        return SIMD3(h.x, h.y, h.z)
    }

    private func voxelDownsample(_ points: [SIMD3<Float>], voxelSize: Float) -> [SIMD3<Float>] {
        var buckets: [VoxelKey: (sum: SIMD3<Float>, count: Int)] = [:]
        for p in points {
            let key = VoxelKey(x: Int(floor(p.x / voxelSize)), y: Int(floor(p.y / voxelSize)), z: Int(floor(p.z / voxelSize)))
            if let existing = buckets[key] {
                buckets[key] = (existing.sum + p, existing.count + 1)
            } else {
                buckets[key] = (p, 1)
            }
        }
        return buckets.values.map { $0.sum / Float($0.count) }
    }
}
