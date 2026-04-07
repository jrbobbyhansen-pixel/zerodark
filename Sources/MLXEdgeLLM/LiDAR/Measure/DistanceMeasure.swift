// DistanceMeasure.swift — Distance measurement tools for LiDAR
// Computes horizontal, vertical, slope, and A* path distances between two points
// Path distance accounts for terrain elevation changes along the route

import Foundation
import simd
import ARKit

// MARK: - Distance Measurement Tool

class DistanceMeasure: ObservableObject {
    @Published var horizontalDistance: Double = 0.0
    @Published var verticalDistance: Double = 0.0
    @Published var slopeDistance: Double = 0.0
    @Published var pathDistance: Double = 0.0

    private var startPoint: ARAnchor?
    private var endPoint: ARAnchor?

    /// Elevation grid for A* path computation (set from performTerrainAnalysis)
    var elevationGrid: [SIMD2<Int>: Float]?
    var gridCellSize: Float = 0.5

    func setStartPoint(_ point: ARAnchor) {
        startPoint = point
    }

    func setEndPoint(_ point: ARAnchor) {
        endPoint = point
        calculateDistances()
    }

    private func calculateDistances() {
        guard let startPoint = startPoint, let endPoint = endPoint else { return }

        let start = startPoint.transform.columns.3
        let end = endPoint.transform.columns.3

        let dx = Double(start.x - end.x)
        let dy = Double(start.y - end.y)
        let dz = Double(start.z - end.z)

        horizontalDistance = sqrt(dx * dx + dz * dz)
        verticalDistance = abs(dy)
        slopeDistance = sqrt(dx * dx + dy * dy + dz * dz)
        pathDistance = calculatePathDistance(
            from: SIMD3(start.x, start.y, start.z),
            to: SIMD3(end.x, end.y, end.z)
        )
    }

    // MARK: - A* Path Distance

    /// Calculate terrain-following path distance using A* on the elevation grid.
    /// Falls back to slope distance if no grid is available.
    private func calculatePathDistance(from start: SIMD3<Float>, to end: SIMD3<Float>) -> Double {
        guard let grid = elevationGrid else {
            // Fallback: straight-line slope distance
            return Double(simd_distance(start, end))
        }

        let startCell = SIMD2<Int>(Int(floor(start.x / gridCellSize)), Int(floor(start.z / gridCellSize)))
        let endCell = SIMD2<Int>(Int(floor(end.x / gridCellSize)), Int(floor(end.z / gridCellSize)))

        guard grid[startCell] != nil, grid[endCell] != nil else {
            return Double(simd_distance(start, end))
        }

        // A* search
        let path = aStarSearch(from: startCell, to: endCell, grid: grid)

        guard path.count >= 2 else {
            return Double(simd_distance(start, end))
        }

        // Sum 3D distances along path
        var totalDist: Float = 0
        for i in 1..<path.count {
            let prev = path[i - 1]
            let curr = path[i]
            let prevElev = grid[prev] ?? 0
            let currElev = grid[curr] ?? 0

            let dx = Float(curr.x - prev.x) * gridCellSize
            let dz = Float(curr.y - prev.y) * gridCellSize
            let dy = currElev - prevElev

            totalDist += sqrt(dx * dx + dy * dy + dz * dz)
        }

        return Double(totalDist)
    }

    /// A* grid search with 8-connected neighbors.
    private func aStarSearch(from start: SIMD2<Int>, to end: SIMD2<Int>, grid: [SIMD2<Int>: Float]) -> [SIMD2<Int>] {
        struct Node: Comparable {
            let pos: SIMD2<Int>
            let fScore: Float
            static func < (lhs: Node, rhs: Node) -> Bool { lhs.fScore < rhs.fScore }
        }

        var openSet: [Node] = [Node(pos: start, fScore: 0)]
        var cameFrom: [SIMD2<Int>: SIMD2<Int>] = [:]
        var gScore: [SIMD2<Int>: Float] = [start: 0]

        let neighbors: [SIMD2<Int>] = [
            SIMD2(1, 0), SIMD2(-1, 0), SIMD2(0, 1), SIMD2(0, -1),
            SIMD2(1, 1), SIMD2(-1, 1), SIMD2(1, -1), SIMD2(-1, -1)
        ]

        func heuristic(_ a: SIMD2<Int>, _ b: SIMD2<Int>) -> Float {
            let dx = Float(a.x - b.x) * gridCellSize
            let dy = Float(a.y - b.y) * gridCellSize
            return sqrt(dx * dx + dy * dy)
        }

        while !openSet.isEmpty {
            // Find node with lowest fScore
            openSet.sort()
            let current = openSet.removeFirst()

            if current.pos == end {
                // Reconstruct path
                var path = [end]
                var node = end
                while let prev = cameFrom[node] {
                    path.insert(prev, at: 0)
                    node = prev
                }
                return path
            }

            let currentElev = grid[current.pos] ?? 0
            let currentG = gScore[current.pos] ?? .infinity

            for offset in neighbors {
                let neighbor = current.pos &+ offset
                guard let neighborElev = grid[neighbor] else { continue }

                // Edge cost: 3D distance between cells
                let dx = Float(offset.x) * gridCellSize
                let dz = Float(offset.y) * gridCellSize
                let dy = neighborElev - currentElev
                let edgeCost = sqrt(dx * dx + dy * dy + dz * dz)

                // Penalize steep slopes
                let slopePenalty: Float = abs(dy) > 0.5 ? 1.5 : 1.0

                let tentativeG = currentG + edgeCost * slopePenalty

                if tentativeG < (gScore[neighbor] ?? .infinity) {
                    cameFrom[neighbor] = current.pos
                    gScore[neighbor] = tentativeG
                    let f = tentativeG + heuristic(neighbor, end)
                    openSet.append(Node(pos: neighbor, fScore: f))
                }
            }
        }

        return [] // No path found
    }
}

// MARK: - Static Measurement Helpers

extension DistanceMeasure {
    /// Direct distance between two 3D points.
    static func directDistance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        simd_distance(a, b)
    }

    /// Horizontal distance (ignoring Y).
    static func horizontalDistance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let dx = a.x - b.x
        let dz = a.z - b.z
        return sqrt(dx * dx + dz * dz)
    }

    /// Vertical distance (Y only).
    static func verticalDistance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        abs(a.y - b.y)
    }
}

// MARK: - SwiftUI View

struct DistanceMeasureView: View {
    @StateObject private var viewModel = DistanceMeasure()

    var body: some View {
        VStack {
            Text("Horizontal: \(viewModel.horizontalDistance, specifier: "%.2f") m")
            Text("Vertical: \(viewModel.verticalDistance, specifier: "%.2f") m")
            Text("Slope: \(viewModel.slopeDistance, specifier: "%.2f") m")
            Text("Path: \(viewModel.pathDistance, specifier: "%.2f") m")
        }
        .padding()
    }
}

// MARK: - Preview

struct DistanceMeasureView_Previews: PreviewProvider {
    static var previews: some View {
        DistanceMeasureView()
    }
}
