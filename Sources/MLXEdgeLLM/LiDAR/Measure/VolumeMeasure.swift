// VolumeMeasure.swift — 3D convex hull volume from point cloud
// Uses incremental convex hull construction, then computes volume via
// signed tetrahedra decomposition: V = (1/6) × |Σ dot(v0, cross(v1, v2))|

import Foundation
import simd

// MARK: - VolumeResult

struct VolumeResult {
    let volume: Float          // cubic meters
    let surfaceArea: Float     // square meters
    let accuracy: Float        // 0.0–1.0 confidence estimate
    let hullPointCount: Int
}

// MARK: - VolumeMeasure

class VolumeMeasure {

    /// Calculate the convex hull volume of a set of 3D points.
    /// Returns volume in cubic meters plus accuracy estimate.
    static func calculateVolume(from points: [SIMD3<Float>]) -> VolumeResult {
        guard points.count >= 4 else {
            return VolumeResult(volume: 0, surfaceArea: 0, accuracy: 0, hullPointCount: points.count)
        }

        // Build convex hull faces using incremental algorithm
        let faces = buildConvexHull(points)
        guard !faces.isEmpty else {
            return VolumeResult(volume: 0, surfaceArea: 0, accuracy: 0, hullPointCount: 0)
        }

        // Volume via signed tetrahedra from origin
        var totalVolume: Float = 0
        var totalArea: Float = 0
        var hullVertices = Set<Int>()

        for face in faces {
            let v0 = points[face.0]
            let v1 = points[face.1]
            let v2 = points[face.2]

            // Signed volume of tetrahedron formed with origin
            totalVolume += simd_dot(v0, simd_cross(v1, v2))

            // Triangle area
            let edge1 = v1 - v0
            let edge2 = v2 - v0
            totalArea += simd_length(simd_cross(edge1, edge2)) * 0.5

            hullVertices.insert(face.0)
            hullVertices.insert(face.1)
            hullVertices.insert(face.2)
        }

        let volume = abs(totalVolume) / 6.0

        // Accuracy heuristic: more points relative to hull size = higher confidence
        let pointDensity = Float(points.count) / max(totalArea, 0.01)
        let accuracy = min(1.0, pointDensity / 100.0) // 100 pts/m² = full confidence

        return VolumeResult(
            volume: volume,
            surfaceArea: totalArea,
            accuracy: accuracy,
            hullPointCount: hullVertices.count
        )
    }

    /// Calculate volume of points within a bounding box region.
    static func calculateRegionVolume(points: [SIMD3<Float>], minBound: SIMD3<Float>, maxBound: SIMD3<Float>) -> VolumeResult {
        let filtered = points.filter { p in
            p.x >= minBound.x && p.x <= maxBound.x &&
            p.y >= minBound.y && p.y <= maxBound.y &&
            p.z >= minBound.z && p.z <= maxBound.z
        }
        return calculateVolume(from: filtered)
    }

    // MARK: - Convex Hull (Incremental)

    /// Build convex hull faces. Returns array of (i0, i1, i2) index triples.
    private static func buildConvexHull(_ points: [SIMD3<Float>]) -> [(Int, Int, Int)] {
        guard points.count >= 4 else { return [] }

        // Find initial tetrahedron from 4 non-coplanar points
        guard let seed = findInitialTetrahedron(points) else { return [] }

        var faces = seed
        var visible: [(Int, Int, Int)]
        var horizon: [(Int, Int)]

        for pi in 0..<points.count {
            // Skip points already in the hull seed
            if faces.contains(where: { $0.0 == pi || $0.1 == pi || $0.2 == pi }) { continue }

            let p = points[pi]

            // Find faces visible from this point
            visible = []
            for face in faces {
                let v0 = points[face.0], v1 = points[face.1], v2 = points[face.2]
                let normal = simd_cross(v1 - v0, v2 - v0)
                if simd_dot(normal, p - v0) > 1e-6 {
                    visible.append(face)
                }
            }

            if visible.isEmpty { continue }

            // Find horizon edges (edges shared by exactly one visible face)
            horizon = []
            for face in visible {
                let edges = [(face.0, face.1), (face.1, face.2), (face.2, face.0)]
                for edge in edges {
                    let reversed = (edge.1, edge.0)
                    let isShared = visible.contains { other in
                        guard other.0 != face.0 || other.1 != face.1 || other.2 != face.2 else { return false }
                        let otherEdges = [(other.0, other.1), (other.1, other.2), (other.2, other.0)]
                        return otherEdges.contains { $0.0 == reversed.0 && $0.1 == reversed.1 }
                    }
                    if !isShared {
                        horizon.append(edge)
                    }
                }
            }

            // Remove visible faces
            faces.removeAll { face in
                visible.contains { $0.0 == face.0 && $0.1 == face.1 && $0.2 == face.2 }
            }

            // Add new faces from horizon edges to point
            for edge in horizon {
                faces.append((edge.0, edge.1, pi))
            }
        }

        return faces
    }

    /// Find 4 non-coplanar points to seed the hull.
    private static func findInitialTetrahedron(_ points: [SIMD3<Float>]) -> [(Int, Int, Int)]? {
        guard points.count >= 4 else { return nil }

        // Find two points that are far apart
        let i0 = 0
        var i1 = 1
        var maxDist: Float = 0
        for i in 1..<points.count {
            let d = simd_distance(points[i0], points[i])
            if d > maxDist { maxDist = d; i1 = i }
        }

        // Find point farthest from line i0-i1
        let lineDir = simd_normalize(points[i1] - points[i0])
        var i2 = 0
        var maxLineDist: Float = 0
        for i in 0..<points.count where i != i0 && i != i1 {
            let v = points[i] - points[i0]
            let proj = simd_dot(v, lineDir) * lineDir
            let dist = simd_length(v - proj)
            if dist > maxLineDist { maxLineDist = dist; i2 = i }
        }

        // Find point farthest from plane i0-i1-i2
        let planeNormal = simd_normalize(simd_cross(points[i1] - points[i0], points[i2] - points[i0]))
        var i3 = 0
        var maxPlaneDist: Float = 0
        for i in 0..<points.count where i != i0 && i != i1 && i != i2 {
            let dist = abs(simd_dot(points[i] - points[i0], planeNormal))
            if dist > maxPlaneDist { maxPlaneDist = dist; i3 = i }
        }

        guard maxPlaneDist > 1e-6 else { return nil }

        // Orient faces so normals point outward
        let centroid = (points[i0] + points[i1] + points[i2] + points[i3]) / 4.0

        var faces = [
            (i0, i1, i2), (i0, i2, i3), (i0, i3, i1), (i1, i3, i2)
        ]

        // Fix winding
        for f in 0..<faces.count {
            let v0 = points[faces[f].0], v1 = points[faces[f].1], v2 = points[faces[f].2]
            let normal = simd_cross(v1 - v0, v2 - v0)
            let toCenter = centroid - v0
            if simd_dot(normal, toCenter) > 0 {
                faces[f] = (faces[f].0, faces[f].2, faces[f].1) // Flip winding
            }
        }

        return faces
    }
}
