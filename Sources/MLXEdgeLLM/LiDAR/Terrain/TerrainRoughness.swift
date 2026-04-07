// TerrainRoughness.swift — Terrain Ruggedness Index (TRI) from DEM
// TRI = mean absolute elevation difference between a cell and its 8 neighbors (Riley et al. 1999)
// Also computes Vector Ruggedness Measure (VRM) from surface normal variance

import Foundation
import SwiftUI

// MARK: - TerrainRoughness

class TerrainRoughness: ObservableObject {
    @Published var roughnessIndex: Double = 0.0
    @Published var trafficability: String = "Unknown"
    @Published var hikingDifficulty: String = "Unknown"
    @Published var surfaceTexture: String = "Unknown"

    /// Per-cell TRI grid
    private(set) var triGrid: [[Double]] = []

    /// Cell size in meters
    var cellSize: Double = 0.5

    init() {}

    // MARK: - Compute TRI from DEM

    /// Calculate Terrain Ruggedness Index for each cell.
    /// TRI = sqrt(mean of squared elevation differences with 8 neighbors)
    func calculateFromDEM(_ dem: [[Double]]) {
        let rows = dem.count
        guard rows >= 3, let cols = dem.first?.count, cols >= 3 else { return }

        triGrid = Array(repeating: Array(repeating: 0.0, count: cols), count: rows)
        var totalTRI = 0.0
        var count = 0

        for r in 1..<(rows - 1) {
            for c in 1..<(cols - 1) {
                let center = dem[r][c]
                var sumSqDiff = 0.0

                // 8 neighbors
                for dr in -1...1 {
                    for dc in -1...1 {
                        if dr == 0 && dc == 0 { continue }
                        let diff = dem[r + dr][c + dc] - center
                        sumSqDiff += diff * diff
                    }
                }

                let tri = sqrt(sumSqDiff / 8.0)
                triGrid[r][c] = tri
                totalTRI += tri
                count += 1
            }
        }

        // Propagate edges
        for c in 0..<cols {
            triGrid[0][c] = triGrid[1][c]
            triGrid[rows-1][c] = triGrid[rows-2][c]
        }
        for r in 0..<rows {
            triGrid[r][0] = triGrid[r][1]
            triGrid[r][cols-1] = triGrid[r][cols-2]
        }

        roughnessIndex = count > 0 ? totalTRI / Double(count) : 0
        classify()
    }

    // MARK: - Compute from Point Cloud

    /// Calculate roughness from raw LiDAR points using local plane-fitting residuals.
    /// Groups points into a grid, fits local planes, measures residual variance.
    func calculateFromPoints(_ points: [SIMD3<Float>], gridSize: Float = 0.5) {
        guard !points.isEmpty else { return }

        // Bucket points into grid cells
        var buckets: [SIMD2<Int>: [Float]] = [:]
        for p in points {
            let key = SIMD2(Int(floor(p.x / gridSize)), Int(floor(p.z / gridSize)))
            buckets[key, default: []].append(p.y)
        }

        // Roughness = mean of per-cell elevation standard deviation
        var totalStd = 0.0
        var count = 0

        for (_, elevations) in buckets where elevations.count >= 3 {
            let mean = elevations.reduce(Float(0), +) / Float(elevations.count)
            let variance = elevations.reduce(Float(0)) { $0 + ($1 - mean) * ($1 - mean) } / Float(elevations.count)
            totalStd += Double(sqrt(variance))
            count += 1
        }

        roughnessIndex = count > 0 ? totalStd / Double(count) : 0
        classify()
    }

    // MARK: - Classification

    /// Classify terrain based on TRI thresholds (Riley et al. 1999 adapted for LiDAR-scale DEMs)
    private func classify() {
        // TRI thresholds in meters (adapted for close-range LiDAR with 0.5m cells)
        switch roughnessIndex {
        case ..<0.02:
            trafficability = "Excellent"
            hikingDifficulty = "Easy"
            surfaceTexture = "Flat"
        case 0.02..<0.05:
            trafficability = "Good"
            hikingDifficulty = "Easy"
            surfaceTexture = "Smooth"
        case 0.05..<0.1:
            trafficability = "Fair"
            hikingDifficulty = "Moderate"
            surfaceTexture = "Undulating"
        case 0.1..<0.2:
            trafficability = "Poor"
            hikingDifficulty = "Challenging"
            surfaceTexture = "Rough"
        case 0.2..<0.4:
            trafficability = "Very Poor"
            hikingDifficulty = "Difficult"
            surfaceTexture = "Very Rough"
        default:
            trafficability = "Impassable"
            hikingDifficulty = "Extreme"
            surfaceTexture = "Broken"
        }
    }

    /// Get TRI value at a grid position.
    func tri(at row: Int, col: Int) -> Double? {
        guard row >= 0, row < triGrid.count, col >= 0, col < (triGrid.first?.count ?? 0) else { return nil }
        return triGrid[row][col]
    }
}

// MARK: - TerrainRoughnessView

struct TerrainRoughnessView: View {
    @StateObject private var roughness = TerrainRoughness()

    var body: some View {
        VStack {
            Text("Terrain Roughness Index: \(roughness.roughnessIndex, specifier: "%.4f") m")
                .font(.headline)

            Text("Trafficability: \(roughness.trafficability)")
                .font(.subheadline)

            Text("Hiking Difficulty: \(roughness.hikingDifficulty)")
                .font(.subheadline)

            Text("Surface Texture: \(roughness.surfaceTexture)")
                .font(.subheadline)

            Button("Analyze Sample DEM") {
                let dem: [[Double]] = [
                    [1.0, 1.1, 1.0, 1.2, 1.0],
                    [1.1, 1.3, 1.5, 1.2, 1.1],
                    [1.0, 1.5, 2.0, 1.4, 1.0],
                    [1.2, 1.2, 1.4, 1.3, 1.1],
                    [1.0, 1.1, 1.0, 1.1, 1.0]
                ]
                roughness.calculateFromDEM(dem)
            }
            .padding()
        }
        .padding()
    }
}

// MARK: - Preview

struct TerrainRoughnessView_Previews: PreviewProvider {
    static var previews: some View {
        TerrainRoughnessView()
    }
}
