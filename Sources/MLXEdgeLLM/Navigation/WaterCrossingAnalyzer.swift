// WaterCrossingAnalyzer.swift — Water crossing identification from terrain data
// Uses SRTM DEM + D8 watershed analysis to find stream corridors,
// identifies crossing candidates (narrow pinch points, gentle banks), rates each.

import Foundation
import SwiftUI
import CoreLocation
import MapKit

// MARK: - Water Crossing Candidate

struct WaterCrossing: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let score: Double               // 0–100
    let approachSlopeDeg: Double    // approaching bank slope
    let departureSlopeDeg: Double   // departing bank slope
    let accumulation: Int           // D8 flow accumulation proxy for flow volume
    let estimatedWidthM: Double     // estimated stream width (derived from accumulation)
    let distanceFromUserM: Double

    var safetyLabel: String {
        switch score {
        case 75...: return "Safe Crossing"
        case 50..<75: return "Caution"
        case 25..<50: return "Difficult"
        default: return "Dangerous"
        }
    }

    var safetyColor: Color {
        switch score {
        case 75...: return .green
        case 50..<75: return .yellow
        case 25..<50: return .orange
        default: return .red
        }
    }
}

// MARK: - WaterCrossingAnalyzer

@MainActor
final class WaterCrossingAnalyzer: ObservableObject {
    static let shared = WaterCrossingAnalyzer()

    @Published var crossings: [WaterCrossing] = []
    @Published var isAnalyzing: Bool = false
    @Published var streamCellCount: Int = 0

    /// SRTM cell spacing: ~30m per cell
    private let cellSpacingM: Double = 30.0

    private init() {}

    // MARK: - Public API

    func analyze(around coordinate: CLLocationCoordinate2D, windowCells: Int = 50) {
        isAnalyzing = true
        crossings = []

        Task.detached(priority: .userInitiated) { [coordinate, windowCells] in
            let results = await self.runAnalysis(center: coordinate, windowCells: windowCells)

            await MainActor.run { [weak self] in
                self?.crossings = results
                self?.isAnalyzing = false
            }
        }
    }

    // MARK: - Analysis Pipeline

    private func runAnalysis(
        center: CLLocationCoordinate2D,
        windowCells: Int
    ) async -> [WaterCrossing] {
        // 1. Get SRTM elevation grid
        guard let dem = TerrainEngine.shared.elevationGrid(around: center, windowCells: windowCells) else {
            return []
        }

        let rows = dem.count
        guard rows > 0, let cols = dem.first?.count, cols > 0 else { return [] }

        // 2. Run D8 watershed analysis
        let watershed = WatershedAnalysis()
        watershed.cellSize = cellSpacingM
        watershed.streamThreshold = 5   // 5 cells × 30m = 150m drainage area → small stream
        watershed.analyze(dem: dem)

        await MainActor.run { [weak self] in
            self?.streamCellCount = watershed.streamCells.count
        }

        guard !watershed.streamCells.isEmpty else { return [] }

        // 3. Build accumulation grid for quick lookup
        let accGrid = watershed.flowAccumulation

        // 4. Find crossing candidates (local stream minima — pinch points)
        // A pinch point = stream cell whose accumulation is locally minimal (narrow part)
        var candidates: [WaterCrossing] = []

        let metersPerDegLat = 111_320.0
        let metersPerDegLon = 111_320.0 * cos(center.latitude * .pi / 180)
        let half = Double(windowCells) / 2.0
        let cellDegLat = cellSpacingM / metersPerDegLat
        let cellDegLon = cellSpacingM / metersPerDegLon

        for cell in watershed.streamCells {
            let r = cell.row, c = cell.col, acc = cell.accumulation
            guard r >= 1, r < rows - 1, c >= 1, c < cols - 1 else { continue }

            // Only consider pinch points: local minimum accumulation among stream neighbors
            let neighbors8 = [
                (r-1, c), (r+1, c), (r, c-1), (r, c+1),
                (r-1,c-1),(r-1,c+1),(r+1,c-1),(r+1,c+1)
            ]
            let streamNeighborAccs = neighbors8.compactMap { (nr, nc) -> Int? in
                guard nr >= 0, nr < rows, nc >= 0, nc < cols else { return nil }
                return accGrid[nr][nc] >= watershed.streamThreshold ? accGrid[nr][nc] : nil
            }
            guard !streamNeighborAccs.isEmpty else { continue }

            // Pinch point: accumulation is not more than 1.5× the minimum neighbor
            // (i.e. not a wide main channel)
            let minNeighborAcc = streamNeighborAccs.min() ?? acc
            guard acc <= Int(Double(minNeighborAcc) * 1.5) + 2 else { continue }

            // 5. Compute bank approach/departure slopes (perpendicular to flow)
            // Use elevation difference across the stream corridor (2 cells on each side)
            let bankOffset = 2
            let upBankR = max(0, r - bankOffset)
            let downBankR = min(rows - 1, r + bankOffset)
            let leftBankC = max(0, c - bankOffset)
            let rightBankC = min(cols - 1, c + bankOffset)

            let northElev = dem[upBankR][c]
            let southElev = dem[downBankR][c]
            let westElev  = dem[r][leftBankC]
            let eastElev  = dem[r][rightBankC]
            let streamElev = dem[r][c]

            let nsDistance = Double(bankOffset) * cellSpacingM
            let ewDistance = Double(bankOffset) * cellSpacingM

            // Approach slope = steepest bank approach
            let approachSlopes = [
                atan2(abs(northElev - streamElev), nsDistance) * 180 / .pi,
                atan2(abs(southElev - streamElev), nsDistance) * 180 / .pi,
                atan2(abs(westElev  - streamElev), ewDistance) * 180 / .pi,
                atan2(abs(eastElev  - streamElev), ewDistance) * 180 / .pi
            ]
            let approachSlope  = approachSlopes.min() ?? 90
            let departureSlope = approachSlopes.sorted()[1]  // second-lowest = departure

            // 6. Estimate stream width from accumulation (empirical: ~0.5 * sqrt(acc) meters)
            let estimatedWidth = max(1.0, 0.5 * sqrt(Double(acc)))

            // 7. Score: lower is better for slope, lower width = safer
            // Score = 100 - slope penalty - width penalty
            let slopePenalty = min(60, (approachSlope + departureSlope) / 2 * 2)
            let widthPenalty  = min(30, estimatedWidth * 2)
            let accPenalty    = min(10, Double(acc) / 10)
            let score = max(0, 100 - slopePenalty - widthPenalty - accPenalty)

            // 8. Convert grid (row, col) → geo coordinate
            // Row increases downward (south) from center; col increases eastward
            let northOffset = (half - Double(r)) * cellDegLat
            let eastOffset  = (Double(c) - half) * cellDegLon
            let lat = center.latitude  + northOffset
            let lon = center.longitude + eastOffset

            // 9. Distance from user
            let northM = northOffset * metersPerDegLat
            let eastM  = eastOffset  * metersPerDegLon
            let dist = sqrt(northM * northM + eastM * eastM)

            let crossing = WaterCrossing(
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                score: score,
                approachSlopeDeg: approachSlope,
                departureSlopeDeg: departureSlope,
                accumulation: acc,
                estimatedWidthM: estimatedWidth,
                distanceFromUserM: dist
            )
            candidates.append(crossing)
        }

        // Sort by score descending, deduplicate within 60m, cap at 8
        candidates.sort { $0.score > $1.score }
        var deduped: [WaterCrossing] = []
        for c in candidates {
            let tooClose = deduped.contains { existing in
                let dlat = (existing.coordinate.latitude  - c.coordinate.latitude)  * metersPerDegLat
                let dlon = (existing.coordinate.longitude - c.coordinate.longitude) * metersPerDegLon
                return sqrt(dlat*dlat + dlon*dlon) < 60
            }
            if !tooClose { deduped.append(c) }
            if deduped.count >= 8 { break }
        }
        return deduped
    }
}

// MARK: - Water Crossing Analyzer View

struct WaterCrossingAnalyzerView: View {
    @ObservedObject private var analyzer = WaterCrossingAnalyzer.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                Group {
                    if analyzer.isAnalyzing {
                        analyzingView
                    } else if analyzer.crossings.isEmpty && analyzer.streamCellCount == 0 {
                        noDataView
                    } else if analyzer.crossings.isEmpty {
                        noStreamView
                    } else {
                        crossingList
                    }
                }
            }
            .navigationTitle("Water Crossings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Rescan") {
                        if let loc = LocationManager.shared.currentLocation {
                            analyzer.analyze(around: loc)
                        }
                    }
                    .foregroundColor(ZDDesign.cyanAccent)
                }
            }
            .onAppear {
                if let loc = LocationManager.shared.currentLocation {
                    analyzer.analyze(around: loc)
                }
            }
        }
    }

    private var analyzingView: some View {
        VStack(spacing: 16) {
            ProgressView().tint(ZDDesign.cyanAccent).scaleEffect(1.5)
            Text("Analyzing watershed…")
                .font(.subheadline).foregroundColor(.secondary)
            Text("D8 flow direction → accumulation → stream extraction")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private var noDataView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.icloud").font(.system(size: 44)).foregroundColor(.orange)
            Text("No Terrain Data").font(.headline)
            Text("SRTM tiles not available for this area.\nDownload tiles in Settings → Terrain.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }.padding()
    }

    private var noStreamView: some View {
        VStack(spacing: 12) {
            Image(systemName: "drop.triangle").font(.system(size: 44)).foregroundColor(.blue)
            Text("No Stream Corridors Found").font(.headline)
            Text("No water features detected within analysis window.\nThis area may be well-drained or arid.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }.padding()
    }

    private var crossingList: some View {
        ScrollView {
            VStack(spacing: 10) {
                // Header stats
                statsHeader

                ForEach(analyzer.crossings) { crossing in
                    let rank = (analyzer.crossings.firstIndex(where: { $0.id == crossing.id }) ?? 0) + 1
                    WaterCrossingRow(rank: rank, crossing: crossing)
                }
            }
            .padding()
        }
    }

    private var statsHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(analyzer.crossings.count)")
                    .font(.title2.bold().monospaced()).foregroundColor(ZDDesign.cyanAccent)
                Text("candidates").font(.caption).foregroundColor(.secondary)
            }
            Divider().frame(height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(analyzer.streamCellCount)")
                    .font(.title2.bold().monospaced()).foregroundColor(.blue)
                Text("stream cells").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(10)
    }
}

// MARK: - Crossing Row

struct WaterCrossingRow: View {
    let rank: Int
    let crossing: WaterCrossing

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(crossing.safetyColor.opacity(0.2)).frame(width: 36, height: 36)
                Text("\(rank)").font(.subheadline.bold()).foregroundColor(crossing.safetyColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(crossing.safetyLabel).font(.subheadline.bold()).foregroundColor(crossing.safetyColor)
                    Spacer()
                    Text(String(format: "%.0f", crossing.score))
                        .font(.headline.bold().monospaced()).foregroundColor(crossing.safetyColor)
                }
                HStack(spacing: 10) {
                    Label(String(format: "~%.0fm wide", crossing.estimatedWidthM), systemImage: "arrow.left.and.right")
                    Label(String(format: "%.1f° slope", crossing.approachSlopeDeg), systemImage: "angle")
                    Label(String(format: "%.0fm away", crossing.distanceFromUserM), systemImage: "location")
                }
                .font(.caption).foregroundColor(.secondary)
                Text(String(format: "%.5f, %.5f",
                            crossing.coordinate.latitude,
                            crossing.coordinate.longitude))
                    .font(.caption2.monospaced()).foregroundColor(.secondary).textSelection(.enabled)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(10)
    }
}
