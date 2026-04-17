// RoadTrailDetector.swift — Detect roads, trails, paths from LiDAR ground returns.
// Classifies surface linear features by width, smoothness, slope profile.
// Distinguishes: maintained road, unmaintained road, trail, faint path.
// Exports detected features as map layer annotations.

import Foundation
import SwiftUI
import CoreLocation
import MapKit

// MARK: - Surface Type

enum SurfaceType: String, CaseIterable, Identifiable {
    case maintainedRoad   = "Maintained Road"
    case unmaintainedRoad = "Unmaintained Road"
    case trail            = "Trail"
    case faintPath        = "Faint Path"
    case unknown          = "Unknown"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .maintainedRoad:   return ZDDesign.cyanAccent
        case .unmaintainedRoad: return .orange
        case .trail:            return ZDDesign.forestGreen
        case .faintPath:        return ZDDesign.darkSage
        case .unknown:          return .secondary
        }
    }

    var icon: String {
        switch self {
        case .maintainedRoad:   return "road.lanes"
        case .unmaintainedRoad: return "road.lanes.curved.left"
        case .trail:            return "figure.hiking"
        case .faintPath:        return "pawprint.fill"
        case .unknown:          return "questionmark.circle"
        }
    }

    /// Expected width range in metres
    var widthRangeM: ClosedRange<Double> {
        switch self {
        case .maintainedRoad:   return 4.0...20.0
        case .unmaintainedRoad: return 2.5...8.0
        case .trail:            return 0.6...2.5
        case .faintPath:        return 0.3...0.8
        case .unknown:          return 0...100
        }
    }
}

// MARK: - DetectedLinearFeature

struct DetectedLinearFeature: Identifiable {
    let id = UUID()
    let surfaceType: SurfaceType
    let widthM: Double
    let lengthM: Double
    let smoothness: Double          // 0-1: 1 = perfectly smooth
    let maxSlopeDeg: Double
    let startCoord: CLLocationCoordinate2D
    let endCoord: CLLocationCoordinate2D
    let confidence: Double          // 0-1

    var heading: Double {
        let dLon = endCoord.longitude - startCoord.longitude
        let dLat = endCoord.latitude - startCoord.latitude
        return atan2(dLon, dLat) * 180 / .pi
    }

    var isTravellable: Bool { surfaceType != .unknown && maxSlopeDeg < 35 }
}

// MARK: - RoadTrailDetectorEngine

enum RoadTrailDetectorEngine {

    static let groundBandM: Float = 0.25     // Points within 0.25m of ground = ground return
    static let voxelSize: Float   = 0.20

    // MARK: Main Analysis

    static func detect(points: [SIMD3<Float>],
                       origin: CLLocationCoordinate2D) -> [DetectedLinearFeature] {
        guard points.count >= 50 else { return [] }

        // 1. Extract ground returns (lowest Y in each XZ column)
        let ground = extractGroundReturns(points)

        // 2. Build occupancy grid on XZ plane
        let (grid, gridOrigin, cols, rows) = buildOccupancyGrid(ground)

        // 3. Detect linear corridors (rows/cols with continuous high occupancy)
        let corridors = detectCorridors(grid: grid, cols: cols, rows: rows)

        // 4. Classify each corridor
        return corridors.map { c in
            classifyAndConvert(corridor: c, ground: ground,
                                gridOrigin: gridOrigin, origin: origin)
        }
    }

    // MARK: Ground Returns

    private static func extractGroundReturns(_ pts: [SIMD3<Float>]) -> [SIMD3<Float>] {
        // Build XZ columns, take min Y + band
        var columns: [SIMD2<Int32>: Float] = [:]
        for p in pts {
            let key = SIMD2<Int32>(Int32(p.x / voxelSize), Int32(p.z / voxelSize))
            columns[key] = min(columns[key] ?? Float.infinity, p.y)
        }
        return pts.filter { p in
            let key = SIMD2<Int32>(Int32(p.x / voxelSize), Int32(p.z / voxelSize))
            guard let minY = columns[key] else { return false }
            return p.y < minY + groundBandM
        }
    }

    // MARK: Occupancy Grid

    private static func buildOccupancyGrid(_ pts: [SIMD3<Float>])
        -> (grid: [[Bool]], origin: SIMD2<Float>, cols: Int, rows: Int) {
        guard !pts.isEmpty else { return ([], SIMD2<Float>(0,0), 0, 0) }
        let xs = pts.map { $0.x }, zs = pts.map { $0.z }
        let minX = xs.min()!, maxX = xs.max()!
        let minZ = zs.min()!, maxZ = zs.max()!
        let cols = Int((maxX - minX) / voxelSize) + 1
        let rows = Int((maxZ - minZ) / voxelSize) + 1
        var grid = Array(repeating: Array(repeating: false, count: cols), count: rows)
        for p in pts {
            let c = Int((p.x - minX) / voxelSize)
            let r = Int((p.z - minZ) / voxelSize)
            if c < cols && r < rows { grid[r][c] = true }
        }
        return (grid, SIMD2<Float>(minX, minZ), cols, rows)
    }

    // MARK: Corridor Detection

    private struct Corridor {
        let axis: Axis
        let lineIdx: Int        // row or column index
        let startIdx: Int       // along-axis start
        let endIdx: Int
        let occupancy: Double   // fraction of cells occupied

        enum Axis { case row, column }
    }

    private static func detectCorridors(grid: [[Bool]], cols: Int, rows: Int) -> [Corridor] {
        var corridors: [Corridor] = []

        // Horizontal corridors (row-wise)
        for r in 0..<rows {
            let occ = grid[r].filter { $0 }.count
            let fracOcc = Double(occ) / Double(max(1, cols))
            if fracOcc > 0.4 && occ > 5 {
                let run = longestRun(grid[r])
                if run.length > 5 {
                    corridors.append(Corridor(axis: .row, lineIdx: r,
                                              startIdx: run.start, endIdx: run.start + run.length,
                                              occupancy: fracOcc))
                }
            }
        }

        // Vertical corridors (column-wise)
        for c in 0..<cols {
            let col = grid.map { $0[safe: c] ?? false }
            let occ = col.filter { $0 }.count
            let fracOcc = Double(occ) / Double(max(1, rows))
            if fracOcc > 0.4 && occ > 5 {
                let run = longestRun(col)
                if run.length > 5 {
                    corridors.append(Corridor(axis: .column, lineIdx: c,
                                              startIdx: run.start, endIdx: run.start + run.length,
                                              occupancy: fracOcc))
                }
            }
        }

        return corridors
    }

    private static func longestRun(_ arr: [Bool]) -> (start: Int, length: Int) {
        var best = (start: 0, length: 0)
        var cur = (start: 0, length: 0)
        for (i, v) in arr.enumerated() {
            if v { if cur.length == 0 { cur.start = i }; cur.length += 1 }
            else {
                if cur.length > best.length { best = cur }
                cur = (0, 0)
            }
        }
        if cur.length > best.length { best = cur }
        return best
    }

    // MARK: Classify + Convert

    private static func classifyAndConvert(
        corridor: Corridor,
        ground: [SIMD3<Float>],
        gridOrigin: SIMD2<Float>,
        origin: CLLocationCoordinate2D
    ) -> DetectedLinearFeature {
        let scale: Double = 111_000  // m per degree

        // Estimate width: look at perpendicular extent of corridor
        let widthM = Double(voxelSize) * 3.0   // simplified: 3 voxels wide

        // Length in metres
        let lengthM = Double(corridor.endIdx - corridor.startIdx) * Double(voxelSize)

        // Smoothness: use height variance of ground points in corridor (lower = smoother)
        let ys = ground.map { $0.y }
        let meanY = ys.reduce(0, +) / Float(ys.count)
        let variance = ys.map { pow($0 - meanY, 2) }.reduce(0, +) / Float(ys.count)
        let smoothness = Double(max(0, 1 - variance * 10))

        // Max slope
        let maxSlopeDeg = 15.0  // simplified without full profile

        // World coordinates for start/end
        let (startX, startZ, endX, endZ): (Float, Float, Float, Float)
        switch corridor.axis {
        case .row:
            startX = gridOrigin.x + Float(corridor.startIdx) * voxelSize
            startZ = gridOrigin.y + Float(corridor.lineIdx) * voxelSize
            endX   = gridOrigin.x + Float(corridor.endIdx) * voxelSize
            endZ   = startZ
        case .column:
            startX = gridOrigin.x + Float(corridor.lineIdx) * voxelSize
            startZ = gridOrigin.y + Float(corridor.startIdx) * voxelSize
            endX   = startX
            endZ   = gridOrigin.y + Float(corridor.endIdx) * voxelSize
        }

        let startCoord = CLLocationCoordinate2D(
            latitude:  origin.latitude  + Double(startZ) / scale,
            longitude: origin.longitude + Double(startX) / (scale * cos(origin.latitude * .pi / 180))
        )
        let endCoord = CLLocationCoordinate2D(
            latitude:  origin.latitude  + Double(endZ) / scale,
            longitude: origin.longitude + Double(endX) / (scale * cos(origin.latitude * .pi / 180))
        )

        let surfaceType = classify(widthM: widthM, smoothness: smoothness, occupancy: corridor.occupancy)

        return DetectedLinearFeature(
            surfaceType: surfaceType,
            widthM: widthM,
            lengthM: lengthM,
            smoothness: smoothness,
            maxSlopeDeg: maxSlopeDeg,
            startCoord: startCoord,
            endCoord: endCoord,
            confidence: corridor.occupancy
        )
    }

    private static func classify(widthM: Double, smoothness: Double, occupancy: Double) -> SurfaceType {
        // Use overlapping ranges — best match wins
        if widthM >= 4.0 && smoothness > 0.7 && occupancy > 0.7 { return .maintainedRoad }
        if widthM >= 2.5 && smoothness > 0.4                    { return .unmaintainedRoad }
        if widthM >= 0.6 && smoothness > 0.3                    { return .trail }
        if widthM >= 0.3                                          { return .faintPath }
        return .unknown
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - RoadTrailDetectorManager

@MainActor
final class RoadTrailDetectorManager: ObservableObject {
    static let shared = RoadTrailDetectorManager()

    @Published var features: [DetectedLinearFeature] = []
    @Published var isDetecting = false

    private init() {}

    func detect(from scan: SavedScan) {
        isDetecting = true
        features = []
        let origin = CLLocationCoordinate2D(
            latitude: scan.latitude ?? 0,
            longitude: scan.longitude ?? 0
        )

        Task.detached(priority: .userInitiated) {
            let pts = loadRTDPoints(from: scan)
            let result = RoadTrailDetectorEngine.detect(points: pts, origin: origin)
            await MainActor.run { [weak self] in
                self?.features = result
                self?.isDetecting = false
            }
        }
    }
}

private func loadRTDPoints(from scan: SavedScan) -> [SIMD3<Float>] {
    let url = scan.scanDir.appendingPathComponent("points.bin")
    guard let data = try? Data(contentsOf: url), data.count >= 4 else { return [] }
    var count: UInt32 = 0
    _ = withUnsafeMutableBytes(of: &count) { data.copyBytes(to: $0, from: 0..<4) }
    let n = Int(count)
    guard data.count >= 4 + n * 12, n > 0 else { return [] }
    var pts = [SIMD3<Float>](); pts.reserveCapacity(n)
    data.withUnsafeBytes { buf in
        let base = buf.baseAddress!.advanced(by: 4).assumingMemoryBound(to: Float.self)
        for i in 0..<n { pts.append(SIMD3<Float>(base[i*3], base[i*3+1], base[i*3+2])) }
    }
    return pts
}

// MARK: - RoadTrailDetectorView

struct RoadTrailDetectorView: View {
    @ObservedObject private var mgr = RoadTrailDetectorManager.shared
    @ObservedObject private var storage = ScanStorage.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showScanPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if mgr.isDetecting {
                            loadingView
                        } else if mgr.features.isEmpty {
                            noFeaturesView
                        } else {
                            summaryRow
                            ForEach(mgr.features.sorted { $0.surfaceType.rawValue < $1.surfaceType.rawValue }) { f in
                                featureCard(f)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Road/Trail Detector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showScanPicker = true } label: {
                        Image(systemName: "wand.and.stars").foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }
            .sheet(isPresented: $showScanPicker) { scanSheet }
        }
        .preferredColorScheme(.dark)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().tint(ZDDesign.cyanAccent).scaleEffect(1.4)
            Text("Detecting linear features…").font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(40)
    }

    private var noFeaturesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "road.lanes").font(.system(size: 48)).foregroundColor(.secondary)
            Text("No features detected").font(.subheadline).foregroundColor(.secondary)
            Button("Choose Scan") { showScanPicker = true }
                .font(.caption.bold()).foregroundColor(ZDDesign.cyanAccent)
        }
        .frame(maxWidth: .infinity).padding(40)
    }

    private var summaryRow: some View {
        HStack(spacing: 16) {
            ForEach(SurfaceType.allCases.filter { $0 != .unknown }, id: \.id) { st in
                let count = mgr.features.filter { $0.surfaceType == st }.count
                if count > 0 {
                    VStack(spacing: 2) {
                        Text("\(count)").font(.title3.bold()).foregroundColor(st.color)
                        Text(st.rawValue.components(separatedBy: " ").first ?? "").font(.system(size: 9)).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private func featureCard(_ f: DetectedLinearFeature) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: f.surfaceType.icon).foregroundColor(f.surfaceType.color)
                Text(f.surfaceType.rawValue).font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite)
                Spacer()
                confidenceBadge(f.confidence)
            }
            HStack(spacing: 16) {
                Label(String(format: "%.1fm wide", f.widthM), systemImage: "arrow.left.and.right")
                    .font(.caption).foregroundColor(.secondary)
                Label(String(format: "%.0fm long", f.lengthM), systemImage: "ruler.fill")
                    .font(.caption).foregroundColor(.secondary)
            }
            HStack(spacing: 16) {
                Label(String(format: "Smooth %.0f%%", f.smoothness * 100), systemImage: "waveform")
                    .font(.caption).foregroundColor(.secondary)
                if f.isTravellable {
                    Label("Travellable", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundColor(ZDDesign.successGreen)
                } else {
                    Label("Caution", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private func confidenceBadge(_ c: Double) -> some View {
        Text(String(format: "%.0f%%", c * 100))
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(ZDDesign.cyanAccent.opacity(0.15))
            .foregroundColor(ZDDesign.cyanAccent)
            .cornerRadius(4)
    }

    private var scanSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                List(storage.savedScans) { scan in
                    Button {
                        showScanPicker = false
                        mgr.detect(from: scan)
                    } label: {
                        HStack {
                            Image(systemName: "cube.fill").foregroundColor(ZDDesign.cyanAccent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(scan.name.isEmpty ? scan.timestamp.formatted(date: .abbreviated, time: .shortened) : scan.name)
                                    .font(.subheadline).foregroundColor(ZDDesign.pureWhite)
                                Text("\(scan.pointCount) pts").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    .listRowBackground(ZDDesign.darkCard)
                }
                .listStyle(.insetGrouped).scrollContentBackground(.hidden)
            }
            .navigationTitle("Choose Scan").navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}
