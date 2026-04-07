// CurvatureAnalysis.swift — Profile and plan curvature from DEM
// Uses Evans-Young second-derivative method on 3×3 neighborhoods
// Profile curvature = curvature in the steepest-descent direction (controls flow acceleration)
// Plan curvature = curvature perpendicular to slope (controls flow convergence/divergence)

import Foundation
import SwiftUI

// MARK: - CurvatureResult

struct CurvatureResult {
    let row: Int
    let col: Int
    let profile: Double   // Positive = convex (accelerating flow), Negative = concave (decelerating)
    let plan: Double       // Positive = divergent, Negative = convergent
    let general: Double    // Mean curvature (Laplacian)
}

// MARK: - CurvatureAnalysis

class CurvatureAnalysis: ObservableObject {
    @Published var profileCurvature: [[Double]] = []
    @Published var planCurvature: [[Double]] = []
    @Published var generalCurvature: [[Double]] = []

    /// Cell size in meters
    var cellSize: Double = 0.5

    // MARK: - Compute

    /// Calculate profile, plan, and general curvature for every interior cell.
    /// Uses Evans-Young method: fit a quadratic surface z = ax² + by² + cxy + dx + ey + f
    /// to each 3×3 neighborhood using finite differences.
    func calculateCurvature(from dem: [[Double]]) -> [CurvatureResult] {
        let rows = dem.count
        guard rows >= 3, let cols = dem.first?.count, cols >= 3 else { return [] }

        profileCurvature = Array(repeating: Array(repeating: 0.0, count: cols), count: rows)
        planCurvature = Array(repeating: Array(repeating: 0.0, count: cols), count: rows)
        generalCurvature = Array(repeating: Array(repeating: 0.0, count: cols), count: rows)

        var results: [CurvatureResult] = []
        let h = cellSize

        for r in 1..<(rows - 1) {
            for c in 1..<(cols - 1) {
                // 3×3 neighborhood
                let z1 = dem[r-1][c-1], z2 = dem[r-1][c], z3 = dem[r-1][c+1]
                let z4 = dem[r][c-1],   z5 = dem[r][c],   z6 = dem[r][c+1]
                let z7 = dem[r+1][c-1], z8 = dem[r+1][c], z9 = dem[r+1][c+1]

                // First derivatives (central differences)
                let p = (z6 - z4) / (2.0 * h)   // dz/dx
                let q = (z2 - z8) / (2.0 * h)   // dz/dy (note: row 0 = north = +y)

                // Second derivatives
                let r2 = (z6 - 2*z5 + z4) / (h * h)       // d²z/dx²
                let s = (z3 - z1 - z9 + z7) / (4.0 * h * h) // d²z/dxdy
                let t = (z2 - 2*z5 + z8) / (h * h)         // d²z/dy²

                let pq2 = p*p + q*q

                // General (mean) curvature = negative Laplacian
                let general = -(r2 + t)

                var profile = 0.0
                var plan = 0.0

                if pq2 > 1e-10 {
                    // Profile curvature (in direction of steepest descent)
                    profile = -(r2 * p*p + 2*s * p*q + t * q*q) / (pq2 * sqrt(1 + pq2))
                    // Plan curvature (perpendicular to slope)
                    plan = -(r2 * q*q - 2*s * p*q + t * p*p) / pow(pq2, 1.5)
                }

                profileCurvature[r][c] = profile
                planCurvature[r][c] = plan
                generalCurvature[r][c] = general

                results.append(CurvatureResult(row: r, col: c, profile: profile, plan: plan, general: general))
            }
        }

        // Propagate edges
        propagateEdges(&profileCurvature, rows: rows, cols: cols)
        propagateEdges(&planCurvature, rows: rows, cols: cols)
        propagateEdges(&generalCurvature, rows: rows, cols: cols)

        return results
    }

    // MARK: - Feature Detection

    /// Find ridges: cells where profile curvature is strongly convex (positive) and plan is divergent (positive).
    func findRidges(threshold: Double = 0.01) -> [(row: Int, col: Int)] {
        var ridges: [(Int, Int)] = []
        for r in 0..<profileCurvature.count {
            for c in 0..<(profileCurvature[r].count) {
                if profileCurvature[r][c] > threshold && planCurvature[r][c] > threshold {
                    ridges.append((r, c))
                }
            }
        }
        return ridges
    }

    /// Find valleys: cells where profile curvature is concave (negative) and plan is convergent (negative).
    func findValleys(threshold: Double = -0.01) -> [(row: Int, col: Int)] {
        var valleys: [(Int, Int)] = []
        for r in 0..<profileCurvature.count {
            for c in 0..<(profileCurvature[r].count) {
                if profileCurvature[r][c] < threshold && planCurvature[r][c] < threshold {
                    valleys.append((r, c))
                }
            }
        }
        return valleys
    }

    // MARK: - Helpers

    private func propagateEdges(_ grid: inout [[Double]], rows: Int, cols: Int) {
        guard rows >= 2, cols >= 2 else { return }
        for c in 0..<cols {
            grid[0][c] = grid[1][c]
            grid[rows-1][c] = grid[rows-2][c]
        }
        for r in 0..<rows {
            grid[r][0] = grid[r][1]
            grid[r][cols-1] = grid[r][cols-2]
        }
    }
}

// MARK: - CurvatureAnalysisView

struct CurvatureAnalysisView: View {
    @StateObject private var viewModel = CurvatureAnalysis()

    var body: some View {
        VStack {
            Text("Curvature Analysis")
                .font(.largeTitle)
                .padding()

            if !viewModel.profileCurvature.isEmpty {
                let ridges = viewModel.findRidges()
                let valleys = viewModel.findValleys()
                Text("Ridges: \(ridges.count) cells")
                Text("Valleys: \(valleys.count) cells")
            }

            Button("Analyze Sample DEM") {
                let dem: [[Double]] = [
                    [10, 12, 14, 12, 10],
                    [12, 16, 20, 16, 12],
                    [14, 20, 25, 20, 14],
                    [12, 16, 20, 16, 12],
                    [10, 12, 14, 12, 10]
                ]
                _ = viewModel.calculateCurvature(from: dem)
            }
            .padding()
        }
        .padding()
    }
}

// MARK: - Preview

struct CurvatureAnalysisView_Previews: PreviewProvider {
    static var previews: some View {
        CurvatureAnalysisView()
    }
}
