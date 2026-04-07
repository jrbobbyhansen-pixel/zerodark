// HeightMeasure.swift — Ground-relative height measurement from LiDAR point cloud
// Uses ground plane (from ClutterFilter or RANSAC) as reference
// Supports full-scene and per-region height queries

import Foundation
import simd

// MARK: - HeightResult

struct HeightResult {
    let maxHeight: Float       // meters above ground
    let minHeight: Float       // meters (usually near 0 if ground is reference)
    let meanHeight: Float
    let groundElevation: Float // ground plane elevation at measurement location
    let pointCount: Int
}

// MARK: - HeightMeasure

class HeightMeasure {

    /// Measure maximum height of points relative to a ground plane.
    /// - Parameters:
    ///   - points: 3D point cloud
    ///   - groundPlaneY: Y-coordinate of ground plane (from ClutterFilter). If nil, uses min(y).
    static func measureHeight(
        points: [SIMD3<Float>],
        groundPlaneY: Float? = nil
    ) -> HeightResult {
        guard !points.isEmpty else {
            return HeightResult(maxHeight: 0, minHeight: 0, meanHeight: 0, groundElevation: 0, pointCount: 0)
        }

        let ys = points.map(\.y)
        let minY = ys.min()!
        let maxY = ys.max()!
        let meanY = ys.reduce(0, +) / Float(ys.count)

        let ground = groundPlaneY ?? minY

        return HeightResult(
            maxHeight: maxY - ground,
            minHeight: minY - ground,
            meanHeight: meanY - ground,
            groundElevation: ground,
            pointCount: points.count
        )
    }

    /// Measure height within a bounding box region.
    static func measureRegionHeight(
        points: [SIMD3<Float>],
        minBound: SIMD2<Float>,
        maxBound: SIMD2<Float>,
        groundPlaneY: Float? = nil
    ) -> HeightResult {
        let filtered = points.filter { p in
            p.x >= minBound.x && p.x <= maxBound.x &&
            p.z >= minBound.y && p.z <= maxBound.y
        }
        return measureHeight(points: filtered, groundPlaneY: groundPlaneY)
    }

    /// Measure height at a specific point (using nearest points within radius).
    static func measureHeightAt(
        position: SIMD2<Float>,
        radius: Float = 0.5,
        points: [SIMD3<Float>],
        groundPlaneY: Float? = nil
    ) -> HeightResult {
        let nearby = points.filter { p in
            let dx = p.x - position.x
            let dz = p.z - position.y
            return dx * dx + dz * dz <= radius * radius
        }
        return measureHeight(points: nearby, groundPlaneY: groundPlaneY)
    }

    /// Measure height per YOLO detection bounding box.
    /// Returns array of (detectionIndex, height) pairs.
    static func measureDetectionHeights(
        detections: [YOLODetection],
        pointCloud: [SIMD3<Float>],
        groundPlaneY: Float? = nil,
        radius: Float = 1.0
    ) -> [(index: Int, height: Float)] {
        var results: [(Int, Float)] = []

        for (i, detection) in detections.enumerated() {
            guard let pos3D = detection.position3D else { continue }
            let result = measureHeightAt(
                position: SIMD2(pos3D.x, pos3D.z),
                radius: radius,
                points: pointCloud,
                groundPlaneY: groundPlaneY
            )
            results.append((i, result.maxHeight))
        }

        return results
    }
}
