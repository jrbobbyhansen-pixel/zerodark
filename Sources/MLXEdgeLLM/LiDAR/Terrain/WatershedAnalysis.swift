// WatershedAnalysis.swift — D8 flow direction and accumulation from DEM
// D8: each cell drains to its steepest downhill neighbor among 8 directions
// Flow accumulation: count of upstream cells draining through each cell
// Stream extraction: cells exceeding an accumulation threshold

import Foundation
import SwiftUI

// MARK: - D8 Direction

/// D8 flow directions encoded as power-of-2 bit flags (standard ESRI encoding)
/// 1=E, 2=SE, 4=S, 8=SW, 16=W, 32=NW, 64=N, 128=NE
struct D8Direction {
    static let E: UInt8   = 1
    static let SE: UInt8  = 2
    static let S: UInt8   = 4
    static let SW: UInt8  = 8
    static let W: UInt8   = 16
    static let NW: UInt8  = 32
    static let N: UInt8   = 64
    static let NE: UInt8  = 128
    static let SINK: UInt8 = 0 // Local minimum

    /// (row offset, col offset) for each direction
    static let offsets: [(dr: Int, dc: Int)] = [
        (0, 1), (1, 1), (1, 0), (1, -1),   // E, SE, S, SW
        (0, -1), (-1, -1), (-1, 0), (-1, 1) // W, NW, N, NE
    ]

    static let codes: [UInt8] = [1, 2, 4, 8, 16, 32, 64, 128]
}

// MARK: - WatershedAnalysis

class WatershedAnalysis: ObservableObject {
    @Published var streamCells: [(row: Int, col: Int, accumulation: Int)] = []
    @Published var sinkCount: Int = 0

    /// Flow direction grid (D8 encoded)
    private(set) var flowDirection: [[UInt8]] = []
    /// Flow accumulation grid (count of upstream cells)
    private(set) var flowAccumulation: [[Int]] = []

    /// Cell size in meters
    var cellSize: Double = 0.5

    /// Minimum accumulation threshold for stream extraction (number of cells)
    var streamThreshold: Int = 10

    // MARK: - Compute

    /// Run full D8 analysis: flow direction → flow accumulation → stream extraction.
    func analyze(dem: [[Double]]) {
        let rows = dem.count
        guard rows >= 3, let cols = dem.first?.count, cols >= 3 else { return }

        // Step 1: Compute D8 flow direction for each cell
        flowDirection = computeFlowDirection(dem: dem, rows: rows, cols: cols)

        // Step 2: Compute flow accumulation via recursive upstream counting
        flowAccumulation = computeFlowAccumulation(rows: rows, cols: cols)

        // Step 3: Extract stream cells above threshold
        extractStreams(rows: rows, cols: cols)
    }

    // MARK: - Flow Direction

    /// For each cell, find the neighbor with the steepest downhill slope and assign that direction.
    private func computeFlowDirection(dem: [[Double]], rows: Int, cols: Int) -> [[UInt8]] {
        var directions = Array(repeating: Array(repeating: D8Direction.SINK, count: cols), count: rows)
        sinkCount = 0

        let diag = sqrt(2.0) * cellSize

        for r in 0..<rows {
            for c in 0..<cols {
                var maxSlope = 0.0
                var bestDir: UInt8 = D8Direction.SINK

                for (i, offset) in D8Direction.offsets.enumerated() {
                    let nr = r + offset.dr
                    let nc = c + offset.dc
                    guard nr >= 0, nr < rows, nc >= 0, nc < cols else { continue }

                    let dist = (abs(offset.dr) + abs(offset.dc) == 2) ? diag : cellSize
                    let drop = dem[r][c] - dem[nr][nc]
                    let slope = drop / dist

                    if slope > maxSlope {
                        maxSlope = slope
                        bestDir = D8Direction.codes[i]
                    }
                }

                directions[r][c] = bestDir
                if bestDir == D8Direction.SINK { sinkCount += 1 }
            }
        }

        return directions
    }

    // MARK: - Flow Accumulation

    /// Count upstream cells for each cell by following flow direction pointers.
    /// Uses iterative topological sort approach to avoid stack overflow on large grids.
    private func computeFlowAccumulation(rows: Int, cols: Int) -> [[Int]] {
        var acc = Array(repeating: Array(repeating: 1, count: cols), count: rows) // Each cell counts itself
        var inDegree = Array(repeating: Array(repeating: 0, count: cols), count: rows)

        // Build in-degree: how many cells flow INTO each cell
        for r in 0..<rows {
            for c in 0..<cols {
                if let (nr, nc) = targetCell(r: r, c: c, rows: rows, cols: cols) {
                    inDegree[nr][nc] += 1
                }
            }
        }

        // Topological sort: start from cells with no inflow (headwaters)
        var queue: [(Int, Int)] = []
        for r in 0..<rows {
            for c in 0..<cols {
                if inDegree[r][c] == 0 {
                    queue.append((r, c))
                }
            }
        }

        var idx = 0
        while idx < queue.count {
            let (r, c) = queue[idx]
            idx += 1

            if let (nr, nc) = targetCell(r: r, c: c, rows: rows, cols: cols) {
                acc[nr][nc] += acc[r][c]
                inDegree[nr][nc] -= 1
                if inDegree[nr][nc] == 0 {
                    queue.append((nr, nc))
                }
            }
        }

        return acc
    }

    /// Find the cell that (r,c) drains to based on its flow direction.
    private func targetCell(r: Int, c: Int, rows: Int, cols: Int) -> (Int, Int)? {
        let dir = flowDirection[r][c]
        guard dir != D8Direction.SINK else { return nil }

        for (i, code) in D8Direction.codes.enumerated() {
            if dir == code {
                let nr = r + D8Direction.offsets[i].dr
                let nc = c + D8Direction.offsets[i].dc
                if nr >= 0 && nr < rows && nc >= 0 && nc < cols {
                    return (nr, nc)
                }
                return nil
            }
        }
        return nil
    }

    // MARK: - Stream Extraction

    private func extractStreams(rows: Int, cols: Int) {
        streamCells = []
        for r in 0..<rows {
            for c in 0..<cols {
                if flowAccumulation[r][c] >= streamThreshold {
                    streamCells.append((r, c, flowAccumulation[r][c]))
                }
            }
        }
        streamCells.sort { $0.accumulation > $1.accumulation }
    }

    /// Get the maximum accumulation value (pour point).
    var maxAccumulation: Int {
        flowAccumulation.flatMap { $0 }.max() ?? 0
    }

    /// Get accumulation at a specific cell.
    func accumulation(at row: Int, col: Int) -> Int? {
        guard row >= 0, row < flowAccumulation.count,
              col >= 0, col < (flowAccumulation.first?.count ?? 0) else { return nil }
        return flowAccumulation[row][col]
    }
}

// MARK: - SwiftUI View

struct WatershedAnalysisView: View {
    @StateObject private var viewModel = WatershedAnalysis()

    var body: some View {
        VStack {
            Text("Watershed Analysis")
                .font(.headline)

            if !viewModel.flowAccumulation.isEmpty {
                Text("Max accumulation: \(viewModel.maxAccumulation) cells")
                Text("Stream cells (>\(viewModel.streamThreshold)): \(viewModel.streamCells.count)")
                Text("Sinks (local minima): \(viewModel.sinkCount)")
            }

            Button("Analyze Sample DEM") {
                let dem: [[Double]] = [
                    [10, 9, 8, 7, 6],
                    [10, 8, 6, 5, 5],
                    [10, 7, 4, 3, 4],
                    [10, 8, 5, 2, 3],
                    [10, 9, 7, 4, 5]
                ]
                viewModel.streamThreshold = 3
                viewModel.analyze(dem: dem)
            }
            .padding()
        }
        .padding()
    }
}

// MARK: - Preview

struct WatershedAnalysisView_Previews: PreviewProvider {
    static var previews: some View {
        WatershedAnalysisView()
    }
}
