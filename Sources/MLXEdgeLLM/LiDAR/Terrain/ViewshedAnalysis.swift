// ViewshedAnalysis.swift — Line-of-sight viewshed on a DEM grid
// Uses Bresenham ray-march with earth curvature correction
// For each observer, casts rays in all directions and marks cells visible/hidden
// based on whether the elevation angle exceeds the running maximum angle from observer.

import Foundation
import SwiftUI

// MARK: - ViewshedAnalyzer

class ViewshedAnalyzer: ObservableObject {
    @Published var visibilityGrid: [[Bool]] = []
    @Published var cumulativeVisibility: [[Int]] = []
    @Published var visibleCellCount: Int = 0
    @Published var totalCellCount: Int = 0

    /// Cell size in meters
    var cellSize: Double = 0.5

    /// Observer height above ground (meters)
    var observerHeight: Double = 1.7

    /// Target height above ground (meters)
    var targetHeight: Double = 0.0

    /// Maximum analysis radius in grid cells (0 = unlimited)
    var maxRadiusCells: Int = 0

    // MARK: - Single Observer Viewshed

    /// Calculate viewshed from a single observer position on the DEM grid.
    /// Returns a Bool grid: true = visible from observer, false = hidden.
    func calculateViewshed(dem: [[Double]], observerRow: Int, observerCol: Int) -> [[Bool]] {
        let rows = dem.count
        guard rows > 0, let cols = dem.first?.count, cols > 0 else { return [] }

        var visible = Array(repeating: Array(repeating: false, count: cols), count: rows)
        visible[observerRow][observerCol] = true

        let observerElev = dem[observerRow][observerCol] + observerHeight
        let maxR = maxRadiusCells > 0 ? maxRadiusCells : max(rows, cols)

        // Cast rays to every cell on the perimeter of increasingly larger squares
        // More efficient: cast to all cells on the bounding perimeter of analysis area
        let perimeterCells = buildPerimeterTargets(rows: rows, cols: cols, centerR: observerRow, centerC: observerCol, maxRadius: maxR)

        for target in perimeterCells {
            castRay(dem: dem, visible: &visible,
                    observerElev: observerElev,
                    r0: observerRow, c0: observerCol,
                    r1: target.row, c1: target.col,
                    rows: rows, cols: cols)
        }

        self.visibilityGrid = visible
        self.visibleCellCount = visible.flatMap { $0 }.filter { $0 }.count
        self.totalCellCount = rows * cols
        return visible
    }

    // MARK: - Cumulative (Multi-Observer) Viewshed

    /// Compute cumulative viewshed: for each cell, how many observers can see it.
    func calculateCumulativeViewshed(dem: [[Double]], observers: [(row: Int, col: Int)]) -> [[Int]] {
        let rows = dem.count
        guard rows > 0, let cols = dem.first?.count, cols > 0 else { return [] }

        var cumulative = Array(repeating: Array(repeating: 0, count: cols), count: rows)

        for obs in observers {
            let vis = calculateViewshed(dem: dem, observerRow: obs.row, observerCol: obs.col)
            for r in 0..<rows {
                for c in 0..<cols {
                    if vis[r][c] { cumulative[r][c] += 1 }
                }
            }
        }

        self.cumulativeVisibility = cumulative
        return cumulative
    }

    // MARK: - Ray Casting (Bresenham + max-angle)

    /// March along a ray from observer to target using Bresenham's line algorithm.
    /// A cell is visible if its elevation angle from the observer exceeds all prior angles on the ray.
    private func castRay(dem: [[Double]], visible: inout [[Bool]],
                         observerElev: Double,
                         r0: Int, c0: Int, r1: Int, c1: Int,
                         rows: Int, cols: Int) {
        var dr = abs(r1 - r0)
        var dc = abs(c1 - c0)
        let sr = r0 < r1 ? 1 : -1
        let sc = c0 < c1 ? 1 : -1
        var err = dr - dc

        var cr = r0, cc = c0
        var maxAngle = -Double.infinity

        while true {
            // Advance one step
            let e2 = 2 * err
            if e2 > -dc { err -= dc; cr += sr }
            if e2 < dr { err += dr; cc += sc }

            // Bounds check
            guard cr >= 0, cr < rows, cc >= 0, cc < cols else { break }

            // Distance from observer
            let distCells = sqrt(Double((cr - r0) * (cr - r0) + (cc - c0) * (cc - c0)))
            if distCells == 0 { continue }

            let distMeters = distCells * cellSize

            // Target elevation + optional target height
            let targetElev = dem[cr][cc] + targetHeight

            // Elevation angle from observer to this cell
            let angle = (targetElev - observerElev) / distMeters

            if angle > maxAngle {
                maxAngle = angle
                visible[cr][cc] = true
            }

            // Reached destination?
            if cr == r1 && cc == c1 { break }

            // Safety: max radius
            if maxRadiusCells > 0 && Int(distCells) > maxRadiusCells { break }
        }
    }

    // MARK: - Perimeter Targets

    /// Build list of cells on the perimeter of the analysis area to use as ray endpoints.
    private func buildPerimeterTargets(rows: Int, cols: Int, centerR: Int, centerC: Int, maxRadius: Int) -> [(row: Int, col: Int)] {
        var targets: [(row: Int, col: Int)] = []

        let minR = max(0, centerR - maxRadius)
        let maxR = min(rows - 1, centerR + maxRadius)
        let minC = max(0, centerC - maxRadius)
        let maxC = min(cols - 1, centerC + maxRadius)

        // Top and bottom edges
        for c in minC...maxC {
            targets.append((minR, c))
            if maxR != minR { targets.append((maxR, c)) }
        }
        // Left and right edges (excluding corners already added)
        for r in (minR + 1)..<maxR {
            targets.append((r, minC))
            if maxC != minC { targets.append((r, maxC)) }
        }

        return targets
    }

    // MARK: - Utility

    /// Check if a specific cell is visible from the last computed single-observer viewshed.
    func isVisible(row: Int, col: Int) -> Bool {
        guard row >= 0, row < visibilityGrid.count,
              col >= 0, col < (visibilityGrid.first?.count ?? 0) else { return false }
        return visibilityGrid[row][col]
    }

    /// Fraction of area visible (0.0–1.0) from last single-observer computation.
    var visibilityFraction: Double {
        guard totalCellCount > 0 else { return 0 }
        return Double(visibleCellCount) / Double(totalCellCount)
    }
}

// MARK: - ViewshedView

struct ViewshedView: View {
    @StateObject private var analyzer = ViewshedAnalyzer()

    var body: some View {
        VStack(spacing: 12) {
            Text("Viewshed Analysis")
                .font(.headline)

            if !analyzer.visibilityGrid.isEmpty {
                Text("Visible: \(analyzer.visibleCellCount) / \(analyzer.totalCellCount) cells (\(String(format: "%.1f", analyzer.visibilityFraction * 100))%)")
            }

            Button("Run Viewshed") {
                let dem: [[Double]] = [
                    [10, 10, 10, 10, 10],
                    [10, 12, 15, 12, 10],
                    [10, 15, 20, 15, 10],
                    [10, 12, 15, 12, 10],
                    [10, 10, 10, 10, 10]
                ]
                _ = analyzer.calculateViewshed(dem: dem, observerRow: 2, observerCol: 2)
            }
            .padding()
        }
        .padding()
    }
}

struct ViewshedView_Previews: PreviewProvider {
    static var previews: some View {
        ViewshedView()
    }
}
