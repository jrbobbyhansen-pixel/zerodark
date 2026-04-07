// CutFillAnalysis.swift — Volume difference between two DEM surfaces
// Computes cut (material to remove) and fill (material to add) volumes
// using cell-by-cell elevation differencing × cell area
// Common use: compare existing terrain to a design surface

import Foundation
import SwiftUI

// MARK: - CutFillResult

struct CutFillResult {
    let cutVolume: Double    // cubic meters (positive = material to remove)
    let fillVolume: Double   // cubic meters (positive = material to add)
    let netVolume: Double    // cut - fill (positive = net removal)
    let cutArea: Double      // square meters of area requiring cut
    let fillArea: Double     // square meters of area requiring fill
    let balanceRow: Int?     // Grid position closest to zero net difference
    let balanceCol: Int?

    /// Per-cell difference grid (positive = cut needed, negative = fill needed)
    let differenceGrid: [[Double]]
}

// MARK: - CutFillAnalysis

class CutFillAnalysis: ObservableObject {
    @Published var cutVolume: Double = 0.0
    @Published var fillVolume: Double = 0.0
    @Published var netVolume: Double = 0.0
    @Published var cutArea: Double = 0.0
    @Published var fillArea: Double = 0.0

    /// Cell size in meters
    var cellSize: Double = 0.5

    // MARK: - Compute

    /// Calculate cut and fill volumes between two DEM grids of the same dimensions.
    /// `existing` = current terrain surface, `design` = target surface.
    /// Cut = existing above design, fill = existing below design.
    func calculate(existing: [[Double]], design: [[Double]]) -> CutFillResult? {
        let rows = existing.count
        guard rows > 0, let cols = existing.first?.count, cols > 0 else { return nil }
        guard design.count == rows, design.first?.count == cols else { return nil }

        let cellArea = cellSize * cellSize
        var totalCut = 0.0
        var totalFill = 0.0
        var cutCells = 0
        var fillCells = 0
        var minAbsDiff = Double.infinity
        var balanceR: Int?
        var balanceC: Int?

        var diffGrid = Array(repeating: Array(repeating: 0.0, count: cols), count: rows)

        for r in 0..<rows {
            for c in 0..<cols {
                let diff = existing[r][c] - design[r][c]
                diffGrid[r][c] = diff

                if diff > 0 {
                    totalCut += diff * cellArea
                    cutCells += 1
                } else if diff < 0 {
                    totalFill += abs(diff) * cellArea
                    fillCells += 1
                }

                if abs(diff) < minAbsDiff {
                    minAbsDiff = abs(diff)
                    balanceR = r
                    balanceC = c
                }
            }
        }

        cutVolume = totalCut
        fillVolume = totalFill
        netVolume = totalCut - totalFill
        cutArea = Double(cutCells) * cellArea
        fillArea = Double(fillCells) * cellArea

        return CutFillResult(
            cutVolume: totalCut,
            fillVolume: totalFill,
            netVolume: totalCut - totalFill,
            cutArea: Double(cutCells) * cellArea,
            fillArea: Double(fillCells) * cellArea,
            balanceRow: balanceR,
            balanceCol: balanceC,
            differenceGrid: diffGrid
        )
    }

    /// Calculate volume between a DEM and a flat reference plane.
    func calculateAgainstPlane(dem: [[Double]], referenceElevation: Double) -> CutFillResult? {
        let rows = dem.count
        guard rows > 0, let cols = dem.first?.count, cols > 0 else { return nil }

        let design = Array(repeating: Array(repeating: referenceElevation, count: cols), count: rows)
        return calculate(existing: dem, design: design)
    }
}

// MARK: - CutFillAnalysisView

struct CutFillAnalysisView: View {
    @StateObject private var viewModel = CutFillAnalysis()

    var body: some View {
        VStack {
            Text("Cut Volume: \(viewModel.cutVolume, specifier: "%.2f") m³")
            Text("Fill Volume: \(viewModel.fillVolume, specifier: "%.2f") m³")
            Text("Net: \(viewModel.netVolume, specifier: "%.2f") m³")
            Text("Cut Area: \(viewModel.cutArea, specifier: "%.1f") m²")
            Text("Fill Area: \(viewModel.fillArea, specifier: "%.1f") m²")

            Button("Calculate Sample") {
                let existing: [[Double]] = [
                    [5.0, 5.2, 5.5, 5.3, 5.0],
                    [5.1, 5.8, 6.2, 5.9, 5.1],
                    [5.3, 6.0, 7.0, 6.1, 5.2],
                    [5.1, 5.7, 6.0, 5.6, 5.0],
                    [5.0, 5.1, 5.3, 5.1, 5.0]
                ]
                _ = viewModel.calculateAgainstPlane(dem: existing, referenceElevation: 5.5)
            }
            .padding()
        }
        .padding()
    }
}

// MARK: - Preview

struct CutFillAnalysisView_Previews: PreviewProvider {
    static var previews: some View {
        CutFillAnalysisView()
    }
}
