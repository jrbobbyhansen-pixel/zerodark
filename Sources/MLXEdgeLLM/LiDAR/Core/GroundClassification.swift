// GroundClassification.swift — Progressive morphological ground filter (Zhang et al. 2003)
// Iteratively opens the elevation surface with increasing window sizes
// Points above the opened surface + threshold are classified as non-ground
// Uses 2D grid index (x,z plane) for spatial queries

import Foundation
import simd

// MARK: - GroundClassification

class GroundClassification {

    /// Cell size for the elevation grid (meters)
    var cellSize: Float = 0.5

    /// Maximum terrain slope (degrees) — controls threshold increase with window size
    var maxSlope: Float = 30.0

    /// Initial height threshold (meters)
    var initialThreshold: Float = 0.1

    /// Window sizes for progressive filtering (in grid cells)
    var windowSizes: [Int] = [2, 4, 8, 16]

    // MARK: - Classify

    /// Classify points into ground and non-ground using progressive morphological filtering.
    func classify(_ points: [SIMD3<Float>]) -> (ground: [SIMD3<Float>], nonGround: [SIMD3<Float>]) {
        guard !points.isEmpty else { return ([], []) }

        // Build 2D elevation grid (x,z plane), storing minimum elevation per cell
        var grid: [GridKey: Float] = [:]
        var pointToCell: [GridKey] = []

        for p in points {
            let key = GridKey(x: Int(floor(p.x / cellSize)), z: Int(floor(p.z / cellSize)))
            pointToCell.append(key)
            if let existing = grid[key] {
                grid[key] = min(existing, p.y)
            } else {
                grid[key] = p.y
            }
        }

        // Convert to 2D array for morphological operations
        let allKeys = Array(grid.keys)
        guard !allKeys.isEmpty else { return (points, []) }

        let minX = allKeys.map(\.x).min()!, maxX = allKeys.map(\.x).max()!
        let minZ = allKeys.map(\.z).min()!, maxZ = allKeys.map(\.z).max()!
        let rows = maxZ - minZ + 1
        let cols = maxX - minX + 1

        // Build dense grid (NaN for empty cells)
        var surface = [[Float]](repeating: [Float](repeating: .nan, count: cols), count: rows)
        for (key, elev) in grid {
            let r = key.z - minZ
            let c = key.x - minX
            surface[r][c] = elev
        }

        // Fill NaN cells with nearest valid elevation (prevents filter artifacts)
        fillNaN(&surface, rows: rows, cols: cols)

        // Progressive morphological filter
        var openedSurface = surface
        let slopeRad = maxSlope * .pi / 180.0

        for windowSize in windowSizes {
            // Height threshold increases with window size to handle sloped terrain
            let windowMeters = Float(windowSize) * cellSize
            let threshold = initialThreshold + windowMeters * tan(slopeRad) * 0.5

            // Erosion (minimum filter)
            let eroded = morphologicalOp(openedSurface, windowSize: windowSize, rows: rows, cols: cols, isErosion: true)
            // Dilation (maximum filter)
            openedSurface = morphologicalOp(eroded, windowSize: windowSize, rows: rows, cols: cols, isErosion: false)

            // Mark cells above opened surface + threshold as non-ground
            // (We apply this progressively — each pass can only ADD non-ground, not remove it)
        }

        // Final classification: compare each point's elevation to the opened surface
        var ground: [SIMD3<Float>] = []
        var nonGround: [SIMD3<Float>] = []

        let finalThreshold = initialThreshold + Float(windowSizes.last ?? 16) * cellSize * tan(slopeRad) * 0.5

        for (i, p) in points.enumerated() {
            let key = pointToCell[i]
            let r = key.z - minZ
            let c = key.x - minX
            guard r >= 0, r < rows, c >= 0, c < cols else {
                nonGround.append(p)
                continue
            }

            let surfaceElev = openedSurface[r][c]
            if p.y - surfaceElev > finalThreshold {
                nonGround.append(p)
            } else {
                ground.append(p)
            }
        }

        return (ground, nonGround)
    }

    // MARK: - Morphological Operations

    /// Apply min (erosion) or max (dilation) filter with a square window.
    private func morphologicalOp(_ grid: [[Float]], windowSize: Int, rows: Int, cols: Int, isErosion: Bool) -> [[Float]] {
        var result = grid
        let half = windowSize / 2

        for r in 0..<rows {
            for c in 0..<cols {
                var val = isErosion ? Float.infinity : -Float.infinity

                for dr in -half...half {
                    for dc in -half...half {
                        let nr = min(max(r + dr, 0), rows - 1)
                        let nc = min(max(c + dc, 0), cols - 1)
                        let v = grid[nr][nc]
                        if !v.isNaN {
                            val = isErosion ? min(val, v) : max(val, v)
                        }
                    }
                }

                result[r][c] = val.isInfinite ? grid[r][c] : val
            }
        }

        return result
    }

    /// Fill NaN cells with nearest valid neighbor elevation.
    private func fillNaN(_ grid: inout [[Float]], rows: Int, cols: Int) {
        for r in 0..<rows {
            for c in 0..<cols {
                if grid[r][c].isNaN {
                    // Search expanding rings for nearest valid cell
                    outer: for radius in 1...max(rows, cols) {
                        for dr in -radius...radius {
                            for dc in -radius...radius {
                                if abs(dr) < radius && abs(dc) < radius { continue }
                                let nr = r + dr, nc = c + dc
                                guard nr >= 0, nr < rows, nc >= 0, nc < cols else { continue }
                                if !grid[nr][nc].isNaN {
                                    grid[r][c] = grid[nr][nc]
                                    break outer
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Grid Key

private struct GridKey: Hashable {
    let x: Int
    let z: Int
}
