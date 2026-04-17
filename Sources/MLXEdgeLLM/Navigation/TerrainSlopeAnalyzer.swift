// TerrainSlopeAnalyzer.swift — LiDAR point cloud → DEM → Horn's slope/aspect (spec 001)
// Bridges LiDARCaptureEngine point cloud to SlopeAspectCalculator.
// Two input modes:
//   1. LiDAR: build DEM from point cloud (cell = max Y over XZ grid)
//   2. SRTM: use TerrainEngine elevation tiles for GPS-located terrain
// Results exposed for color-coded overlay and hazard reporting.

import Foundation
import SwiftUI
import simd
import CoreLocation

// MARK: - Slope Zone

struct SlopeZone: Identifiable {
    let id = UUID()
    let row: Int
    let col: Int
    let slopeDeg: Double
    let aspectDeg: Double
    var isHazardous: Bool { slopeDeg >= 30 }

    var hazardColor: Color {
        switch slopeDeg {
        case ..<15:     return .green
        case 15..<30:   return .yellow
        case 30..<45:   return Color.orange
        default:        return .red
        }
    }

    var aspectCardinal: String {
        guard aspectDeg >= 0 else { return "Flat" }
        let dirs = ["N","NE","E","SE","S","SW","W","NW","N"]
        return dirs[Int((aspectDeg + 22.5) / 45.0) % 8]
    }
}

// MARK: - Analysis Result

struct TerrainSlopeResult {
    let zones: [SlopeZone]
    let meanSlope: Double
    let meanAspect: Double
    let hazardClassification: String
    let hazardCount: Int
    let gridRows: Int
    let gridCols: Int
    let cellSizeM: Double
    let source: Source

    enum Source { case lidar, srtm }

    var hazardFraction: Double {
        guard !zones.isEmpty else { return 0 }
        return Double(hazardCount) / Double(zones.count)
    }
}

// MARK: - ViewModel

@MainActor
final class TerrainSlopeAnalyzerViewModel: ObservableObject {
    @Published var result: TerrainSlopeResult?
    @Published var isAnalyzing = false
    @Published var errorMessage: String?

    private let calculator = SlopeAspectCalculator()

    /// Cell size for DEM grid (meters). Smaller = finer detail, more computation.
    var cellSizeM: Double = 0.5

    /// Slope threshold for hazardous classification (degrees).
    var hazardThresholdDeg: Double = 30.0

    // MARK: - LiDAR Mode

    /// Analyze slope from a LiDAR point cloud.
    /// Points in ARKit world space: +X east, +Y up, -Z north.
    func analyze(pointCloud: [SIMD3<Float>]) {
        guard !pointCloud.isEmpty else {
            errorMessage = "No point cloud data available"
            return
        }
        isAnalyzing = true
        errorMessage = nil
        result = nil

        Task.detached(priority: .userInitiated) { [weak self, cellSizeM = cellSizeM] in
            guard let self else { return }
            let dem = buildDEM(from: pointCloud, cellSize: Float(cellSizeM))
            await MainActor.run {
                self.runCalculator(dem: dem, cellSize: cellSizeM, source: .lidar)
            }
        }
    }

    /// Analyze slope from SRTM elevation data at a GPS coordinate (50×50 cell window).
    func analyze(coordinate: CLLocationCoordinate2D) async {
        guard TerrainEngine.shared.hasTile(for: coordinate) else {
            errorMessage = "No SRTM tile available for this location. Download offline maps first."
            return
        }
        isAnalyzing = true
        errorMessage = nil
        result = nil

        let window = 50  // 50×50 cells at 30m SRTM = 1.5km × 1.5km
        if let dem = TerrainEngine.shared.elevationGrid(around: coordinate, windowCells: window) {
            runCalculator(dem: dem, cellSize: 30.0, source: .srtm)  // SRTM = 30m/cell
        } else {
            isAnalyzing = false
            errorMessage = "Failed to extract elevation grid"
        }
    }

    // MARK: - Private

    private func runCalculator(dem: [[Double]], cellSize: Double, source: TerrainSlopeResult.Source) {
        calculator.cellSize = cellSize
        calculator.calculateSlopeAndAspect(from: dem)

        let rows = calculator.slopeGrid.count
        let cols = calculator.slopeGrid.first?.count ?? 0

        var zones: [SlopeZone] = []
        var hazardCount = 0

        for r in 0..<rows {
            for c in 0..<cols {
                let slope = calculator.slopeGrid[r][c]
                let aspect = calculator.aspectGrid[r][c]
                let zone = SlopeZone(row: r, col: c, slopeDeg: slope, aspectDeg: aspect)
                zones.append(zone)
                if zone.isHazardous { hazardCount += 1 }
            }
        }

        result = TerrainSlopeResult(
            zones: zones,
            meanSlope: calculator.slopeAngle,
            meanAspect: calculator.aspect,
            hazardClassification: calculator.hazardClassification,
            hazardCount: hazardCount,
            gridRows: rows,
            gridCols: cols,
            cellSizeM: cellSize,
            source: source
        )
        isAnalyzing = false
    }
}

// MARK: - Point Cloud → DEM

/// Rasterise a LiDAR point cloud onto a regular XZ grid.
/// Each cell stores the maximum Y value of points within it (ARKit: Y = up = elevation).
/// Missing cells are filled by nearest occupied neighbor.
private func buildDEM(from points: [SIMD3<Float>], cellSize: Float) -> [[Double]] {
    guard !points.isEmpty else { return [] }

    let xs = points.map { $0.x }
    let zs = points.map { $0.z }
    let minX = xs.min()!, maxX = xs.max()!
    let minZ = zs.min()!, maxZ = zs.max()!

    let cols = max(3, Int(ceil((maxX - minX) / cellSize)) + 1)
    let rows = max(3, Int(ceil((maxZ - minZ) / cellSize)) + 1)

    // Fill cells with max Y
    var grid = Array(repeating: Array(repeating: Double.nan, count: cols), count: rows)
    for p in points {
        let c = Int((p.x - minX) / cellSize)
        let r = Int((p.z - minZ) / cellSize)
        guard r >= 0, r < rows, c >= 0, c < cols else { continue }
        let y = Double(p.y)
        if grid[r][c].isNaN || y > grid[r][c] {
            grid[r][c] = y
        }
    }

    // Fill NaN holes with nearest occupied neighbor (BFS from occupied cells)
    fillHoles(grid: &grid, rows: rows, cols: cols)
    return grid
}

/// Fill NaN cells via nearest-neighbor propagation (iterative flood fill).
private func fillHoles(grid: inout [[Double]], rows: Int, cols: Int) {
    var changed = true
    let maxPasses = 10
    var pass = 0
    while changed && pass < maxPasses {
        changed = false
        pass += 1
        for r in 0..<rows {
            for c in 0..<cols {
                guard grid[r][c].isNaN else { continue }
                var sum = 0.0
                var count = 0
                let neighbors = [(r-1,c),(r+1,c),(r,c-1),(r,c+1)]
                for (nr, nc) in neighbors {
                    guard nr >= 0, nr < rows, nc >= 0, nc < cols, !grid[nr][nc].isNaN else { continue }
                    sum += grid[nr][nc]
                    count += 1
                }
                if count > 0 {
                    grid[r][c] = sum / Double(count)
                    changed = true
                }
            }
        }
    }
    // Any remaining NaN → 0 (flat)
    for r in 0..<rows {
        for c in 0..<cols {
            if grid[r][c].isNaN { grid[r][c] = 0 }
        }
    }
}

// MARK: - TerrainEngine DEM Extension

extension TerrainEngine {
    /// Sample a windowCells × windowCells elevation grid centered on `coordinate`.
    /// Uses the public `elevationAt` API so no private tile access is needed.
    /// Returns nil if no elevation data is available for the region.
    func elevationGrid(around coordinate: CLLocationCoordinate2D, windowCells: Int) -> [[Double]]? {
        // SRTM3: ~30m/cell ≈ 0.000278° per cell
        let cellSpacingDeg = 30.0 / 111_320.0
        let half = Double(windowCells) / 2.0

        var grid: [[Double]] = []
        var hasData = false

        for r in 0..<windowCells {
            var row: [Double] = []
            for c in 0..<windowCells {
                let lat = coordinate.latitude  + (half - Double(r)) * cellSpacingDeg
                let lon = coordinate.longitude + (Double(c) - half) * cellSpacingDeg
                let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                if let elev = elevationAt(coordinate: coord) {
                    row.append(elev)
                    hasData = true
                } else {
                    row.append(0)
                }
            }
            grid.append(row)
        }

        return hasData ? grid : nil
    }
}

// MARK: - TerrainSlopeAnalyzerView

struct TerrainSlopeAnalyzerView: View {
    @StateObject private var viewModel = TerrainSlopeAnalyzerViewModel()
    let pointCloud: [SIMD3<Float>]

    var body: some View {
        NavigationStack {
            ZStack {
                ZDDesign.darkBackground.ignoresSafeArea()

                if viewModel.isAnalyzing {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(ZDDesign.cyanAccent)
                        Text("Analyzing terrain...")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                } else if let result = viewModel.result {
                    ScrollView {
                        VStack(spacing: ZDDesign.spacing16) {
                            SlopeSummaryCard(result: result)
                            SlopeGridView(result: result)
                            QuadrantBreakdown(result: result)
                            if result.hazardCount > 0 {
                                HazardZoneList(result: result)
                            }
                        }
                        .padding()
                    }
                } else if let error = viewModel.errorMessage {
                    ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
                }
            }
            .navigationTitle("Terrain Slope")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                viewModel.analyze(pointCloud: pointCloud)
            }
        }
    }
}

// MARK: - Summary Card

private struct SlopeSummaryCard: View {
    let result: TerrainSlopeResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Slope Analysis", systemImage: "mountain.2.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ZDDesign.cyanAccent)
                Spacer()
                Text(result.source == .lidar ? "LiDAR" : "SRTM")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(4)
            }

            HStack(spacing: 24) {
                VStack(alignment: .leading) {
                    Text("\(result.meanSlope, specifier: "%.1f")°")
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(slopeColor(result.meanSlope))
                    Text("mean slope")
                        .font(.caption).foregroundColor(.secondary)
                }
                VStack(alignment: .leading) {
                    Text(result.meanAspect >= 0 ? "\(Int(result.meanAspect))°" : "Flat")
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text("aspect")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(result.hazardClassification)
                        .font(.caption.weight(.bold))
                        .foregroundColor(hazardClassColor(result.hazardClassification))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(hazardClassColor(result.hazardClassification).opacity(0.15))
                        .cornerRadius(6)
                    Text("\(result.hazardCount) hazardous cells")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private func slopeColor(_ deg: Double) -> Color {
        switch deg {
        case ..<15:   return .green
        case 15..<30: return .yellow
        case 30..<45: return .orange
        default:      return .red
        }
    }

    private func hazardClassColor(_ cls: String) -> Color {
        switch cls {
        case "Low":      return .green
        case "Moderate": return .yellow
        case "High":     return .orange
        default:         return .red
        }
    }
}

// MARK: - Slope Grid Heatmap

private struct SlopeGridView: View {
    let result: TerrainSlopeResult

    // Downsample to 20×20 max for display
    private var displayZones: [[SlopeZone]] {
        let displayRows = min(result.gridRows, 20)
        let displayCols = min(result.gridCols, 20)
        let rStride = max(1, result.gridRows / displayRows)
        let cStride = max(1, result.gridCols / displayCols)
        var grid: [[SlopeZone]] = []
        var r = 0
        while r < result.gridRows {
            var row: [SlopeZone] = []
            var c = 0
            while c < result.gridCols {
                let idx = r * result.gridCols + c
                if idx < result.zones.count {
                    row.append(result.zones[idx])
                }
                c += cStride
            }
            if !row.isEmpty { grid.append(row) }
            r += rStride
        }
        return grid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SLOPE HEATMAP")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            let grid = displayZones
            VStack(spacing: 1) {
                ForEach(Array(grid.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 1) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, zone in
                            Rectangle()
                                .fill(zone.hazardColor.opacity(0.85))
                                .frame(maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
            .cornerRadius(8)

            HStack(spacing: 16) {
                ForEach([("<15° Safe", Color.green), ("15-30° Moderate", Color.yellow),
                         ("30-45° High", Color.orange), (">45° Extreme", Color.red)],
                        id: \.0) { label, color in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
                        Text(label).font(.system(size: 9)).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }
}

// MARK: - Quadrant Breakdown

private struct QuadrantBreakdown: View {
    let result: TerrainSlopeResult

    private func stats(for quadrant: String) -> (slope: Double, aspect: Double) {
        let rows = result.gridRows, cols = result.gridCols
        let midR = rows / 2, midC = cols / 2
        let (rRange, cRange): (ClosedRange<Int>, ClosedRange<Int>) = {
            switch quadrant {
            case "NW": return (0...midR, 0...midC)
            case "NE": return (0...midR, midC...(cols-1))
            case "SW": return (midR...(rows-1), 0...midC)
            default:   return (midR...(rows-1), midC...(cols-1))
            }
        }()
        var sSum = 0.0, aSum = 0.0, n = 0
        for r in rRange {
            for c in cRange {
                let idx = r * cols + c
                guard idx < result.zones.count else { continue }
                sSum += result.zones[idx].slopeDeg
                if result.zones[idx].aspectDeg >= 0 { aSum += result.zones[idx].aspectDeg }
                n += 1
            }
        }
        return n > 0 ? (sSum/Double(n), aSum/Double(n)) : (0, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BY QUADRANT")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(["NW","NE","SW","SE"], id: \.self) { q in
                    let s = stats(for: q)
                    HStack {
                        Text(q).font(.caption.weight(.bold)).foregroundColor(ZDDesign.cyanAccent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(s.slope, specifier: "%.1f")°")
                                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            Text(s.aspect >= 0 ? "Aspect \(Int(s.aspect))°" : "Flat")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(ZDDesign.darkBackground)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }
}

// MARK: - Hazard Zone List

private struct HazardZoneList: View {
    let result: TerrainSlopeResult

    private var topHazards: [SlopeZone] {
        result.zones
            .filter { $0.isHazardous }
            .sorted { $0.slopeDeg > $1.slopeDeg }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("HAZARDOUS SLOPES (>30°)", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(.orange)

            ForEach(topHazards) { zone in
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(zone.hazardColor)
                        .font(.caption)
                    Text("\(zone.slopeDeg, specifier: "%.1f")°")
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .foregroundColor(.white)
                    Text("facing \(zone.aspectCardinal)")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text("R\(zone.row) C\(zone.col)")
                        .font(.caption2.monospaced()).foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                Divider().background(Color.white.opacity(0.06))
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }
}
