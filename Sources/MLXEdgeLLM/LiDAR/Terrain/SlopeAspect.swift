// SlopeAspect.swift — Horn's method slope & aspect from DEM grid
// Uses 3×3 finite-difference kernel (Horn 1981) for robust gradient estimation
// Input: [[Double]] DEM where grid[row][col] = elevation

import Foundation
import SwiftUI

// MARK: - SlopeAspectCalculator

class SlopeAspectCalculator: ObservableObject {
    @Published var slopeAngle: Double = 0.0
    @Published var aspect: Double = 0.0
    @Published var statisticsByZone: [String: (slope: Double, aspect: Double)] = [:]
    @Published var hazardClassification: String = ""

    /// Per-cell slope grid (degrees), same dimensions as input DEM
    private(set) var slopeGrid: [[Double]] = []
    /// Per-cell aspect grid (degrees clockwise from north), same dimensions as input DEM
    private(set) var aspectGrid: [[Double]] = []

    /// Cell size in meters (distance between adjacent grid cells)
    var cellSize: Double = 0.5

    // MARK: - Horn's Method

    /// Calculate slope and aspect for every cell using Horn's 3×3 weighted finite differences.
    /// Sets slopeGrid, aspectGrid, and summary statistics.
    func calculateSlopeAndAspect(from dem: [[Double]]) {
        let rows = dem.count
        guard rows >= 3, let cols = dem.first?.count, cols >= 3 else { return }

        slopeGrid = Array(repeating: Array(repeating: 0.0, count: cols), count: rows)
        aspectGrid = Array(repeating: Array(repeating: -1.0, count: cols), count: rows)

        var totalSlope = 0.0
        var totalAspect = 0.0
        var count = 0

        for r in 1..<(rows - 1) {
            for c in 1..<(cols - 1) {
                // Horn's 3×3 kernel
                //  a b c
                //  d e f
                //  g h i
                let a = dem[r-1][c-1], b = dem[r-1][c], cc = dem[r-1][c+1]
                let d = dem[r][c-1],                     f = dem[r][c+1]
                let g = dem[r+1][c-1], h = dem[r+1][c], i = dem[r+1][c+1]

                // dz/dx = ((c + 2f + i) - (a + 2d + g)) / (8 * cellSize)
                let dzdx = ((cc + 2*f + i) - (a + 2*d + g)) / (8.0 * cellSize)
                // dz/dy = ((g + 2h + i) - (a + 2b + c)) / (8 * cellSize)
                let dzdy = ((g + 2*h + i) - (a + 2*b + cc)) / (8.0 * cellSize)

                let slopeRad = atan(sqrt(dzdx * dzdx + dzdy * dzdy))
                let slopeDeg = slopeRad * 180.0 / .pi

                // Aspect: degrees clockwise from north (0° = north, 90° = east)
                var aspectDeg: Double
                if dzdx == 0 && dzdy == 0 {
                    aspectDeg = -1  // Flat
                } else {
                    aspectDeg = atan2(-dzdy, dzdx) * 180.0 / .pi
                    // Convert from math angle (CCW from east) to compass bearing (CW from north)
                    aspectDeg = 90.0 - aspectDeg
                    if aspectDeg < 0 { aspectDeg += 360 }
                    if aspectDeg >= 360 { aspectDeg -= 360 }
                }

                slopeGrid[r][c] = slopeDeg
                aspectGrid[r][c] = aspectDeg

                totalSlope += slopeDeg
                if aspectDeg >= 0 { totalAspect += aspectDeg }
                count += 1
            }
        }

        // Copy edge cells from nearest interior neighbor
        propagateEdges(grid: &slopeGrid, rows: rows, cols: cols)
        propagateEdges(grid: &aspectGrid, rows: rows, cols: cols)

        // Summary statistics
        if count > 0 {
            slopeAngle = totalSlope / Double(count)
            aspect = totalAspect / Double(count)
        }
        updateStatisticsByZone(rows: rows, cols: cols)
        classifyHazards()
    }

    // MARK: - Zone Statistics

    /// Divide grid into quadrants (NW, NE, SW, SE) and compute mean slope/aspect per zone.
    private func updateStatisticsByZone(rows: Int, cols: Int) {
        statisticsByZone.removeAll()
        let midR = rows / 2, midC = cols / 2

        let zones: [(String, ClosedRange<Int>, ClosedRange<Int>)] = [
            ("NW", 0...midR, 0...midC),
            ("NE", 0...midR, midC...(cols-1)),
            ("SW", midR...(rows-1), 0...midC),
            ("SE", midR...(rows-1), midC...(cols-1))
        ]

        for (name, rRange, cRange) in zones {
            var sSum = 0.0, aSum = 0.0, n = 0
            for r in rRange {
                for c in cRange where c < cols && r < rows {
                    sSum += slopeGrid[r][c]
                    if aspectGrid[r][c] >= 0 { aSum += aspectGrid[r][c] }
                    n += 1
                }
            }
            if n > 0 {
                statisticsByZone[name] = (slope: sSum / Double(n), aspect: aSum / Double(n))
            }
        }
    }

    // MARK: - Hazard Classification

    /// Classify terrain hazard based on average slope.
    /// <15° = Low, 15-30° = Moderate, 30-45° = High, >45° = Extreme
    private func classifyHazards() {
        switch slopeAngle {
        case ..<15: hazardClassification = "Low"
        case 15..<30: hazardClassification = "Moderate"
        case 30..<45: hazardClassification = "High"
        default: hazardClassification = "Extreme"
        }
    }

    // MARK: - Helpers

    /// Fill border cells by copying nearest computed interior cell.
    private func propagateEdges(grid: inout [[Double]], rows: Int, cols: Int) {
        for c in 0..<cols {
            grid[0][c] = grid[1][c]
            grid[rows-1][c] = grid[rows-2][c]
        }
        for r in 0..<rows {
            grid[r][0] = grid[r][1]
            grid[r][cols-1] = grid[r][cols-2]
        }
    }

    /// Get slope at a specific grid position.
    func slope(at row: Int, col: Int) -> Double? {
        guard row >= 0, row < slopeGrid.count, col >= 0, col < (slopeGrid.first?.count ?? 0) else { return nil }
        return slopeGrid[row][col]
    }

    /// Get aspect at a specific grid position.
    func aspect(at row: Int, col: Int) -> Double? {
        guard row >= 0, row < aspectGrid.count, col >= 0, col < (aspectGrid.first?.count ?? 0) else { return nil }
        return aspectGrid[row][col]
    }
}

// MARK: - SlopeAspectView

struct SlopeAspectView: View {
    @StateObject private var calculator = SlopeAspectCalculator()

    var body: some View {
        VStack {
            Text("Slope Angle: \(calculator.slopeAngle, specifier: "%.2f")°")
                .font(.headline)
            Text("Aspect: \(calculator.aspect, specifier: "%.2f")°")
                .font(.headline)
            Text("Hazard Classification: \(calculator.hazardClassification)")
                .font(.headline)
            Button("Calculate Slope and Aspect") {
                let dem = [[0.0, 1.0, 2.0], [1.0, 2.0, 3.0], [2.0, 3.0, 4.0]]
                calculator.calculateSlopeAndAspect(from: dem)
            }
            .padding()
        }
        .padding()
    }
}

// MARK: - SlopeAspectPreview

struct SlopeAspectView_Previews: PreviewProvider {
    static var previews: some View {
        SlopeAspectView()
    }
}
