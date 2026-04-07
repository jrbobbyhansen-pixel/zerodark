// BuildingExtractor.swift — Extract building footprints from wall-plane clusters
// Projects wall plane inliers onto ground plane, clusters with DBSCAN,
// computes 2D convex hull per cluster as building footprint

import Foundation
import simd

// MARK: - Building

struct ExtractedBuilding: Identifiable {
    let id = UUID()
    let footprint: [SIMD2<Float>]    // 2D convex hull (x, z) in world coords
    let height: Float                  // meters (max wall height)
    let wallCount: Int                 // number of wall planes in this cluster
    let centroid: SIMD2<Float>
    let area: Float                    // square meters
}

// MARK: - BuildingExtractor

class BuildingExtractor {

    /// DBSCAN clustering parameters
    var clusterEps: Float = 1.5        // max distance between points in a cluster (meters)
    var clusterMinPts: Int = 10        // minimum points to form a cluster

    // MARK: - Extract

    /// Extract building footprints from detected wall planes.
    /// Projects wall inlier points onto the XZ ground plane, clusters them,
    /// and computes convex hull per cluster.
    func extract(
        wallPlanes: [DetectedPlane],
        allPoints: [SIMD3<Float>]
    ) -> [ExtractedBuilding] {
        guard !wallPlanes.isEmpty else { return [] }

        // Collect all wall inlier points projected onto XZ plane
        var projectedPoints: [SIMD2<Float>] = []
        var heights: [Float] = []
        var planeAssignment: [Int] = [] // which plane each projected point came from

        for (planeIdx, plane) in wallPlanes.enumerated() {
            for idx in plane.inlierIndices {
                guard idx < allPoints.count else { continue }
                let p = allPoints[idx]
                projectedPoints.append(SIMD2(p.x, p.z))
                heights.append(p.y)
                planeAssignment.append(planeIdx)
            }
        }

        guard !projectedPoints.isEmpty else { return [] }

        // DBSCAN clustering on 2D projected points
        let clusters = dbscan(points: projectedPoints)

        // Build a building for each cluster
        var buildings: [ExtractedBuilding] = []

        for cluster in clusters {
            guard cluster.count >= clusterMinPts else { continue }

            let clusterPoints = cluster.map { projectedPoints[$0] }
            let clusterHeights = cluster.map { heights[$0] }
            let clusterPlanes = Set(cluster.map { planeAssignment[$0] })

            // Convex hull of 2D points
            let hull = convexHull2D(clusterPoints)
            guard hull.count >= 3 else { continue }

            // Centroid
            var centroid = SIMD2<Float>.zero
            for p in hull { centroid += p }
            centroid /= Float(hull.count)

            // Max height
            let maxHeight = clusterHeights.max() ?? 0

            // Area via shoelace formula
            let area = polygonArea(hull)

            buildings.append(ExtractedBuilding(
                footprint: hull,
                height: maxHeight,
                wallCount: clusterPlanes.count,
                centroid: centroid,
                area: area
            ))
        }

        return buildings.sorted { $0.area > $1.area }
    }

    // MARK: - DBSCAN

    /// Density-based clustering. Returns array of clusters (each cluster is array of point indices).
    private func dbscan(points: [SIMD2<Float>]) -> [[Int]] {
        let n = points.count
        var labels = [Int](repeating: -1, count: n) // -1 = unvisited
        var clusterId = 0

        // Build grid index for fast neighbor queries
        let grid = buildGrid2D(points)

        for i in 0..<n {
            guard labels[i] == -1 else { continue }

            let neighbors = rangeQuery(i, points: points, grid: grid)
            if neighbors.count < clusterMinPts {
                labels[i] = -2 // Noise
                continue
            }

            labels[i] = clusterId
            var seeds = neighbors
            var seedIdx = 0

            while seedIdx < seeds.count {
                let q = seeds[seedIdx]
                seedIdx += 1

                if labels[q] == -2 { labels[q] = clusterId } // Noise becomes border
                guard labels[q] == -1 else { continue } // Skip already assigned

                labels[q] = clusterId
                let qNeighbors = rangeQuery(q, points: points, grid: grid)
                if qNeighbors.count >= clusterMinPts {
                    seeds.append(contentsOf: qNeighbors)
                }
            }

            clusterId += 1
        }

        // Group by cluster label
        var clusters: [[Int]] = Array(repeating: [], count: clusterId)
        for (i, label) in labels.enumerated() where label >= 0 {
            clusters[label].append(i)
        }

        return clusters.filter { !$0.isEmpty }
    }

    private struct GridKey2D: Hashable { let x: Int, z: Int }

    private func buildGrid2D(_ points: [SIMD2<Float>]) -> [GridKey2D: [Int]] {
        var grid: [GridKey2D: [Int]] = [:]
        for (i, p) in points.enumerated() {
            let key = GridKey2D(x: Int(floor(p.x / clusterEps)), z: Int(floor(p.y / clusterEps)))
            grid[key, default: []].append(i)
        }
        return grid
    }

    private func rangeQuery(_ idx: Int, points: [SIMD2<Float>], grid: [GridKey2D: [Int]]) -> [Int] {
        let p = points[idx]
        let cx = Int(floor(p.x / clusterEps))
        let cz = Int(floor(p.y / clusterEps))
        var neighbors: [Int] = []

        for dx in -1...1 {
            for dz in -1...1 {
                guard let cell = grid[GridKey2D(x: cx + dx, z: cz + dz)] else { continue }
                for j in cell {
                    let d = simd_distance(p, points[j])
                    if d <= clusterEps { neighbors.append(j) }
                }
            }
        }
        return neighbors
    }

    // MARK: - 2D Convex Hull (Andrew's Monotone Chain)

    private func convexHull2D(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
        let sorted = points.sorted { $0.x < $1.x || ($0.x == $1.x && $0.y < $1.y) }
        guard sorted.count >= 3 else { return sorted }

        var hull: [SIMD2<Float>] = []

        // Lower hull
        for p in sorted {
            while hull.count >= 2 && cross2D(hull[hull.count - 2], hull[hull.count - 1], p) <= 0 {
                hull.removeLast()
            }
            hull.append(p)
        }

        // Upper hull
        let lowerCount = hull.count + 1
        for p in sorted.reversed() {
            while hull.count >= lowerCount && cross2D(hull[hull.count - 2], hull[hull.count - 1], p) <= 0 {
                hull.removeLast()
            }
            hull.append(p)
        }

        hull.removeLast() // Remove last point (duplicate of first)
        return hull
    }

    private func cross2D(_ o: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    }

    private func polygonArea(_ hull: [SIMD2<Float>]) -> Float {
        guard hull.count >= 3 else { return 0 }
        var area: Float = 0
        for i in 0..<hull.count {
            let j = (i + 1) % hull.count
            area += hull[i].x * hull[j].y
            area -= hull[j].x * hull[i].y
        }
        return abs(area) / 2.0
    }
}
