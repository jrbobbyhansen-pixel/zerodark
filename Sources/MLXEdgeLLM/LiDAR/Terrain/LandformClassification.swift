// LandformClassification.swift — Topographic Position Index (TPI) based landform classification
// TPI = elevation of cell minus mean elevation of neighborhood
// Combined with slope to classify: ridge, valley, upper/mid/lower slope, flat
// Based on Weiss (2001) and Jenness (2006) landform classification schemes

import Foundation
import SwiftUI

// MARK: - Landform Types

enum LandformType: String, CaseIterable, Codable {
    case ridge          // TPI > +1 SD
    case upperSlope     // TPI 0.5–1 SD, slope > threshold
    case openSlope      // TPI near 0, slope > threshold
    case flat           // TPI near 0, slope ≤ threshold
    case lowerSlope     // TPI -0.5 to -1 SD, slope > threshold
    case valley         // TPI < -1 SD
    case saddle         // TPI near 0, high curvature
}

struct LandformClassification {
    let type: LandformType
    let confidence: Double
    let tpi: Double
}

// MARK: - Terrain Analyzer

class TerrainAnalyzer: ObservableObject {
    @Published var landformGrid: [[LandformClassification?]] = []
    @Published var dominantLandform: LandformClassification?

    /// Neighborhood radius in cells for TPI computation
    var neighborRadius: Int = 3

    /// Cell size in meters
    var cellSize: Double = 0.5

    /// Slope threshold for flat vs slope classification (degrees)
    var slopeThreshold: Double = 5.0

    // MARK: - TPI Computation

    /// Classify every cell in the DEM using Topographic Position Index + slope.
    func classifyTerrain(from dem: [[Double]]) {
        let rows = dem.count
        guard rows >= 3, let cols = dem.first?.count, cols >= 3 else { return }

        // Step 1: Compute TPI for each cell
        var tpiGrid = Array(repeating: Array(repeating: 0.0, count: cols), count: rows)
        var allTPI: [Double] = []

        for r in 0..<rows {
            for c in 0..<cols {
                let tpi = computeTPI(dem: dem, row: r, col: c, rows: rows, cols: cols)
                tpiGrid[r][c] = tpi
                allTPI.append(tpi)
            }
        }

        // Step 2: Compute TPI statistics for standardization
        let meanTPI = allTPI.reduce(0, +) / Double(allTPI.count)
        let variance = allTPI.reduce(0.0) { $0 + ($1 - meanTPI) * ($1 - meanTPI) } / Double(allTPI.count)
        let stdTPI = sqrt(variance)

        // Step 3: Compute slope grid using central differences
        let slopeCalc = SlopeAspectCalculator()
        slopeCalc.cellSize = cellSize
        slopeCalc.calculateSlopeAndAspect(from: dem)

        // Step 4: Classify each cell
        landformGrid = Array(repeating: Array(repeating: nil, count: cols), count: rows)
        var typeCounts: [LandformType: Int] = [:]

        for r in 0..<rows {
            for c in 0..<cols {
                let tpi = tpiGrid[r][c]
                let stdTPI_val = stdTPI > 1e-10 ? (tpi - meanTPI) / stdTPI : 0
                let slope = slopeCalc.slopeGrid.isEmpty ? 0 : slopeCalc.slopeGrid[r][c]

                let (type, confidence) = classifyCell(standardizedTPI: stdTPI_val, slopeDeg: slope)
                let classification = LandformClassification(type: type, confidence: confidence, tpi: tpi)
                landformGrid[r][c] = classification
                typeCounts[type, default: 0] += 1
            }
        }

        // Dominant landform = most common
        if let dominant = typeCounts.max(by: { $0.value < $1.value }) {
            let totalCells = rows * cols
            dominantLandform = LandformClassification(
                type: dominant.key,
                confidence: Double(dominant.value) / Double(totalCells),
                tpi: meanTPI
            )
        }
    }

    /// Compute TPI: cell elevation minus mean of circular neighborhood.
    private func computeTPI(dem: [[Double]], row: Int, col: Int, rows: Int, cols: Int) -> Double {
        let center = dem[row][col]
        var sum = 0.0
        var count = 0

        let rSq = neighborRadius * neighborRadius
        for dr in -neighborRadius...neighborRadius {
            for dc in -neighborRadius...neighborRadius {
                if dr == 0 && dc == 0 { continue }
                if dr * dr + dc * dc > rSq { continue } // Circular neighborhood
                let nr = row + dr, nc = col + dc
                guard nr >= 0, nr < rows, nc >= 0, nc < cols else { continue }
                sum += dem[nr][nc]
                count += 1
            }
        }

        return count > 0 ? center - sum / Double(count) : 0
    }

    /// Classify a cell based on standardized TPI and local slope.
    private func classifyCell(standardizedTPI: Double, slopeDeg: Double) -> (LandformType, Double) {
        let absTPI = abs(standardizedTPI)

        if standardizedTPI > 1.0 {
            return (.ridge, min(1.0, absTPI / 2.0))
        } else if standardizedTPI < -1.0 {
            return (.valley, min(1.0, absTPI / 2.0))
        } else if standardizedTPI > 0.5 && slopeDeg > slopeThreshold {
            return (.upperSlope, 0.5 + absTPI * 0.3)
        } else if standardizedTPI < -0.5 && slopeDeg > slopeThreshold {
            return (.lowerSlope, 0.5 + absTPI * 0.3)
        } else if absTPI <= 0.5 && slopeDeg > slopeThreshold {
            return (.openSlope, 0.7)
        } else {
            return (.flat, max(0.5, 1.0 - slopeDeg / slopeThreshold))
        }
    }

    /// Get classification at a specific grid position.
    func classification(at row: Int, col: Int) -> LandformClassification? {
        guard row >= 0, row < landformGrid.count, col >= 0, col < (landformGrid.first?.count ?? 0) else { return nil }
        return landformGrid[row][col]
    }

    /// Count cells by landform type.
    func landformDistribution() -> [LandformType: Int] {
        var dist: [LandformType: Int] = [:]
        for row in landformGrid {
            for cell in row {
                if let c = cell {
                    dist[c.type, default: 0] += 1
                }
            }
        }
        return dist
    }
}

// MARK: - SwiftUI View

struct TerrainView: View {
    @StateObject private var terrainAnalyzer = TerrainAnalyzer()

    var body: some View {
        VStack {
            if let landform = terrainAnalyzer.dominantLandform {
                Text("Dominant: \(landform.type.rawValue)")
                    .font(.headline)
                Text("Confidence: \(String(format: "%.0f%%", landform.confidence * 100))")
                    .font(.subheadline)
            } else {
                Text("Analyzing terrain...")
                    .font(.body)
            }

            if !terrainAnalyzer.landformGrid.isEmpty {
                let dist = terrainAnalyzer.landformDistribution()
                ForEach(LandformType.allCases, id: \.self) { type in
                    if let count = dist[type], count > 0 {
                        HStack {
                            Text(type.rawValue.capitalized)
                            Spacer()
                            Text("\(count) cells")
                        }
                        .font(.caption)
                    }
                }
            }

            Button("Classify Sample DEM") {
                let dem: [[Double]] = [
                    [10, 10, 10, 10, 10, 10, 10],
                    [10, 11, 12, 13, 12, 11, 10],
                    [10, 12, 15, 18, 15, 12, 10],
                    [10, 13, 18, 25, 18, 13, 10],
                    [10, 12, 15, 18, 15, 12, 10],
                    [10, 11, 12, 13, 12, 11, 10],
                    [10, 10, 10, 10, 10, 10, 10]
                ]
                terrainAnalyzer.classifyTerrain(from: dem)
            }
            .padding()
        }
        .padding()
    }
}
