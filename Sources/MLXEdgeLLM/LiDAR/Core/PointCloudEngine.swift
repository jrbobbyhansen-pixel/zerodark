// PointCloudEngine.swift — Point cloud processing: downsampling, filtering, PCA normal estimation
// Uses voxel grid for spatial indexing and k-nearest-neighbor normal computation

import Foundation
import simd
import Accelerate

// MARK: - PointCloudEngine

class PointCloudEngine {

    /// Voxel size for spatial indexing (meters)
    var voxelSize: Float = 0.1

    /// Number of neighbors for normal estimation
    var kNeighbors: Int = 8

    // MARK: - Voxel Grid

    private struct VoxelKey: Hashable {
        let x: Int, y: Int, z: Int

        init(_ point: SIMD3<Float>, size: Float) {
            x = Int(floor(point.x / size))
            y = Int(floor(point.y / size))
            z = Int(floor(point.z / size))
        }
    }

    // MARK: - Downsampling

    /// Voxel-grid downsampling: keep centroid of each occupied voxel.
    func downsample(_ points: [SIMD3<Float>], voxelSize: Float? = nil) -> [SIMD3<Float>] {
        let vs = voxelSize ?? self.voxelSize
        var buckets: [VoxelKey: (sum: SIMD3<Float>, count: Int)] = [:]

        for p in points {
            let key = VoxelKey(p, size: vs)
            if let existing = buckets[key] {
                buckets[key] = (existing.sum + p, existing.count + 1)
            } else {
                buckets[key] = (p, 1)
            }
        }

        return buckets.values.map { $0.sum / Float($0.count) }
    }

    // MARK: - Statistical Outlier Removal

    /// Remove points whose mean distance to k neighbors exceeds mean + stdMultiplier * std.
    func removeOutliers(_ points: [SIMD3<Float>], k: Int = 8, stdMultiplier: Float = 2.0) -> [SIMD3<Float>] {
        guard points.count > k else { return points }

        let grid = buildGrid(points)
        var meanDistances = [Float](repeating: 0, count: points.count)

        for (i, p) in points.enumerated() {
            let neighbors = findKNearest(p, in: grid, points: points, k: k, excludeIndex: i)
            let avgDist = neighbors.reduce(Float(0)) { $0 + simd_distance(p, points[$1]) } / Float(max(1, neighbors.count))
            meanDistances[i] = avgDist
        }

        let globalMean = meanDistances.reduce(0, +) / Float(points.count)
        let variance = meanDistances.reduce(Float(0)) { $0 + ($1 - globalMean) * ($1 - globalMean) } / Float(points.count)
        let threshold = globalMean + stdMultiplier * sqrt(variance)

        return points.enumerated().compactMap { meanDistances[$0.offset] <= threshold ? $0.element : nil }
    }

    // MARK: - Normal Estimation (PCA)

    /// Estimate surface normals using PCA on k-nearest-neighbor covariance matrices.
    /// Orients normals toward `viewpoint` (typically camera position).
    func estimateNormals(_ points: [SIMD3<Float>], viewpoint: SIMD3<Float> = .zero) -> [SIMD3<Float>] {
        guard !points.isEmpty else { return [] }

        let grid = buildGrid(points)
        var normals = [SIMD3<Float>](repeating: .zero, count: points.count)

        for (i, p) in points.enumerated() {
            let neighborIndices = findKNearest(p, in: grid, points: points, k: kNeighbors, excludeIndex: i)
            guard neighborIndices.count >= 3 else {
                normals[i] = SIMD3(0, 1, 0) // Default up if too few neighbors
                continue
            }

            // Compute centroid
            var centroid = SIMD3<Float>.zero
            for ni in neighborIndices { centroid += points[ni] }
            centroid += p
            centroid /= Float(neighborIndices.count + 1)

            // Build 3×3 covariance matrix
            var cov = simd_float3x3(0)
            let allPts = [p] + neighborIndices.map { points[$0] }
            for pt in allPts {
                let d = pt - centroid
                // Outer product: d * d^T
                cov[0] += SIMD3(d.x * d.x, d.x * d.y, d.x * d.z)
                cov[1] += SIMD3(d.y * d.x, d.y * d.y, d.y * d.z)
                cov[2] += SIMD3(d.z * d.x, d.z * d.y, d.z * d.z)
            }

            // Find eigenvector with smallest eigenvalue via power iteration on inverse
            // Approximate: compute cross product of two largest eigenvectors
            // Faster approach: the normal is the eigenvector of smallest eigenvalue
            let normal = smallestEigenvector(cov)

            // Orient toward viewpoint
            let toView = viewpoint - p
            if simd_dot(normal, toView) < 0 {
                normals[i] = -normal
            } else {
                normals[i] = normal
            }
        }

        return normals
    }

    // MARK: - Spatial Index

    private func buildGrid(_ points: [SIMD3<Float>]) -> [VoxelKey: [Int]] {
        var grid: [VoxelKey: [Int]] = [:]
        for (i, p) in points.enumerated() {
            let key = VoxelKey(p, size: voxelSize)
            grid[key, default: []].append(i)
        }
        return grid
    }

    private func findKNearest(_ point: SIMD3<Float>, in grid: [VoxelKey: [Int]], points: [SIMD3<Float>], k: Int, excludeIndex: Int) -> [Int] {
        let centerKey = VoxelKey(point, size: voxelSize)
        var candidates: [(index: Int, dist: Float)] = []

        // Search expanding neighborhood until we have enough candidates
        for radius in 0...3 {
            for dx in -radius...radius {
                for dy in -radius...radius {
                    for dz in -radius...radius {
                        // Only check cells on the shell of this radius (optimization)
                        if radius > 0 && abs(dx) < radius && abs(dy) < radius && abs(dz) < radius { continue }
                        let key = VoxelKey(x: centerKey.x + dx, y: centerKey.y + dy, z: centerKey.z + dz)
                        guard let indices = grid[key] else { continue }
                        for idx in indices where idx != excludeIndex {
                            let d = simd_distance_squared(point, points[idx])
                            candidates.append((idx, d))
                        }
                    }
                }
            }
            if candidates.count >= k { break }
        }

        candidates.sort { $0.dist < $1.dist }
        return Array(candidates.prefix(k).map(\.index))
    }

    // MARK: - Eigenvector (smallest eigenvalue of 3×3)

    /// Find the eigenvector corresponding to the smallest eigenvalue of a symmetric 3×3 matrix.
    /// Uses the characteristic equation for 3×3 symmetric matrices.
    private func smallestEigenvector(_ m: simd_float3x3) -> SIMD3<Float> {
        // For a 3×3 symmetric matrix, compute eigenvalues analytically
        let a = m[0][0], b = m[1][1], c = m[2][2]
        let d = m[0][1], e = m[1][2], f = m[0][2]

        let p1 = d*d + f*f + e*e
        if p1 < 1e-10 {
            // Matrix is diagonal
            let eigenvalues = [a, b, c]
            let minIdx = eigenvalues.enumerated().min(by: { $0.element < $1.element })!.offset
            var v = SIMD3<Float>.zero
            v[minIdx] = 1
            return v
        }

        let q = (a + b + c) / 3.0
        let p2 = (a - q)*(a - q) + (b - q)*(b - q) + (c - q)*(c - q) + 2*p1
        let p = sqrt(p2 / 6.0)

        // B = (1/p) * (A - q*I)
        var B = m
        B[0][0] -= q; B[1][1] -= q; B[2][2] -= q
        B[0] /= p; B[1] /= p; B[2] /= p

        let detB = B[0][0] * (B[1][1]*B[2][2] - B[1][2]*B[2][1])
                 - B[0][1] * (B[1][0]*B[2][2] - B[1][2]*B[2][0])
                 + B[0][2] * (B[1][0]*B[2][1] - B[1][1]*B[2][0])
        let r = detB / 2.0

        let phi: Float
        if r <= -1 {
            phi = .pi / 3.0
        } else if r >= 1 {
            phi = 0
        } else {
            phi = acos(r) / 3.0
        }

        // Eigenvalues in decreasing order
        let eig0 = q + 2 * p * cos(phi)
        let eig2 = q + 2 * p * cos(phi + (2.0 * .pi / 3.0))
        // Smallest eigenvalue is eig2

        // Compute eigenvector for smallest eigenvalue via (A - λI)
        var shifted = m
        shifted[0][0] -= eig2; shifted[1][1] -= eig2; shifted[2][2] -= eig2

        // Cross product of two rows gives the eigenvector direction
        let row0 = SIMD3(shifted[0][0], shifted[0][1], shifted[0][2])
        let row1 = SIMD3(shifted[1][0], shifted[1][1], shifted[1][2])
        var normal = simd_cross(row0, row1)
        let len = simd_length(normal)
        if len > 1e-8 {
            normal /= len
        } else {
            // Fallback: try other row pair
            let row2 = SIMD3(shifted[2][0], shifted[2][1], shifted[2][2])
            normal = simd_cross(row0, row2)
            let len2 = simd_length(normal)
            normal = len2 > 1e-8 ? normal / len2 : SIMD3(0, 1, 0)
        }

        return normal
    }

    // MARK: - Convenience initializer for VoxelKey with explicit components

    private init() {}
    static let shared = PointCloudEngine()
}

private extension PointCloudEngine.VoxelKey {
    init(x: Int, y: Int, z: Int) {
        self.x = x
        self.y = y
        self.z = z
    }
}
