// ClutterFilter.swift — Statistical outlier removal + RANSAC ground plane + intensity gating
// Removes environmental noise (rain, dust, reflections) and separates ground from objects

import Foundation
import simd
import Accelerate

// MARK: - Filtered Cloud

struct FilteredCloud {
    let objectPoints: [SIMD3<Float>]
    let groundPoints: [SIMD3<Float>]
    let removedCount: Int
    let groundPlane: GroundPlane?
}

struct GroundPlane {
    let normal: SIMD3<Float>
    let distance: Float  // signed distance from origin

    func distanceToPoint(_ point: SIMD3<Float>) -> Float {
        simd_dot(normal, point) + distance
    }
}

// MARK: - ClutterFilter

final class ClutterFilter {

    struct Config {
        var intensityThreshold: Float = 0.08     // Minimum point intensity
        var voxelSize: Float = 0.05              // 5cm voxels for SOR
        var sorSigmaMultiplier: Float = 2.0      // Reject voxels > N sigma from mean
        var sorMinNeighbors: Int = 3             // Minimum neighbors per voxel
        var ransacIterations: Int = 100          // RANSAC iterations for ground plane
        var ransacInlierThreshold: Float = 0.05  // 5cm inlier distance
        var groundThickness: Float = 0.10        // Points within 10cm of ground = ground
    }

    private let config: Config

    init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Main Filter Pipeline

    /// Runs the full 3-stage clutter filter pipeline
    func filter(points: [SIMD3<Float>], intensities: [Float]? = nil) -> FilteredCloud {
        guard !points.isEmpty else {
            return FilteredCloud(objectPoints: [], groundPoints: [], removedCount: 0, groundPlane: nil)
        }

        let startCount = points.count

        // Stage 1: Intensity gate
        var filtered: [SIMD3<Float>]
        if let intensities, intensities.count == points.count {
            filtered = zip(points, intensities)
                .filter { $0.1 > config.intensityThreshold }
                .map { $0.0 }
        } else {
            filtered = points
        }

        // Stage 2: Voxel-based statistical outlier removal
        filtered = statisticalOutlierRemoval(filtered)

        // Stage 3: RANSAC ground plane
        let plane = ransacGroundPlane(filtered)

        var objectPoints: [SIMD3<Float>] = []
        var groundPoints: [SIMD3<Float>] = []
        objectPoints.reserveCapacity(filtered.count)

        if let plane {
            for point in filtered {
                if abs(plane.distanceToPoint(point)) < config.groundThickness {
                    groundPoints.append(point)
                } else {
                    objectPoints.append(point)
                }
            }
        } else {
            objectPoints = filtered
        }

        return FilteredCloud(
            objectPoints: objectPoints,
            groundPoints: groundPoints,
            removedCount: startCount - objectPoints.count - groundPoints.count,
            groundPlane: plane
        )
    }

    // MARK: - Statistical Outlier Removal (Voxel-accelerated)

    private func statisticalOutlierRemoval(_ points: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard points.count > config.sorMinNeighbors else { return points }

        // Build voxel grid
        let invVoxel = 1.0 / config.voxelSize
        var voxelMap: [VoxelKey: [Int]] = [:]

        for (i, point) in points.enumerated() {
            let key = VoxelKey(
                x: Int(floor(point.x * invVoxel)),
                y: Int(floor(point.y * invVoxel)),
                z: Int(floor(point.z * invVoxel))
            )
            voxelMap[key, default: []].append(i)
        }

        // Compute neighbor count for each voxel (26-connected neighborhood)
        var voxelNeighborCounts: [VoxelKey: Int] = [:]
        for key in voxelMap.keys {
            var count = 0
            for dx in -1...1 {
                for dy in -1...1 {
                    for dz in -1...1 {
                        if dx == 0 && dy == 0 && dz == 0 { continue }
                        let neighbor = VoxelKey(x: key.x + dx, y: key.y + dy, z: key.z + dz)
                        if voxelMap[neighbor] != nil { count += 1 }
                    }
                }
            }
            voxelNeighborCounts[key] = count
        }

        // Compute mean and std of neighbor counts
        let counts = Array(voxelNeighborCounts.values).map { Double($0) }
        let mean = counts.reduce(0, +) / Double(counts.count)
        let variance = counts.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(counts.count)
        let stddev = sqrt(variance)
        let threshold = mean - Double(config.sorSigmaMultiplier) * stddev

        // Keep points in voxels with enough neighbors
        var result: [SIMD3<Float>] = []
        result.reserveCapacity(points.count)

        for (key, indices) in voxelMap {
            let neighborCount = voxelNeighborCounts[key] ?? 0
            if Double(neighborCount) >= threshold && neighborCount >= config.sorMinNeighbors {
                for idx in indices {
                    result.append(points[idx])
                }
            }
        }

        return result
    }

    // MARK: - RANSAC Ground Plane

    private func ransacGroundPlane(_ points: [SIMD3<Float>]) -> GroundPlane? {
        guard points.count >= 3 else { return nil }

        var bestPlane: GroundPlane?
        var bestInlierCount = 0
        let threshold = config.ransacInlierThreshold

        for _ in 0..<config.ransacIterations {
            // Sample 3 random points
            let i0 = Int.random(in: 0..<points.count)
            var i1 = Int.random(in: 0..<points.count)
            while i1 == i0 { i1 = Int.random(in: 0..<points.count) }
            var i2 = Int.random(in: 0..<points.count)
            while i2 == i0 || i2 == i1 { i2 = Int.random(in: 0..<points.count) }

            let p0 = points[i0]
            let p1 = points[i1]
            let p2 = points[i2]

            // Compute plane normal via cross product
            let v1 = p1 - p0
            let v2 = p2 - p0
            var normal = simd_cross(v1, v2)
            let normLen = simd_length(normal)
            guard normLen > 1e-6 else { continue }
            normal /= normLen

            // Ensure normal points upward (y-up convention)
            if normal.y < 0 { normal = -normal }

            // Plane equation: dot(normal, point) + d = 0
            let d = -simd_dot(normal, p0)

            // Count inliers
            var inlierCount = 0
            for point in points {
                if abs(simd_dot(normal, point) + d) < threshold {
                    inlierCount += 1
                }
            }

            if inlierCount > bestInlierCount {
                bestInlierCount = inlierCount
                bestPlane = GroundPlane(normal: normal, distance: d)
            }
        }

        // Require at least 10% of points to be ground inliers
        guard bestInlierCount > points.count / 10 else { return nil }
        return bestPlane
    }
}

// MARK: - Voxel Key

private struct VoxelKey: Hashable {
    let x: Int
    let y: Int
    let z: Int
}
