// TerrainClassifier.swift — LiDAR point-cloud terrain type classification.
// Classifies voxel columns into: rock, vegetation, water, snow, sand, mud.
// Color-codes each class and estimates traversability (0-1, 1 = fully passable).

import Foundation
import SwiftUI
import CoreLocation

// MARK: - TerrainClass

enum TerrainClass: String, CaseIterable, Identifiable {
    case rock        = "Rock"
    case vegetation  = "Vegetation"
    case water       = "Water"
    case snow        = "Snow"
    case sand        = "Sand"
    case mud         = "Mud"
    case unknown     = "Unknown"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .rock:       return Color(red: 0.55, green: 0.50, blue: 0.45)  // gray-brown
        case .vegetation: return ZDDesign.forestGreen
        case .water:      return ZDDesign.cyanAccent
        case .snow:       return Color.white
        case .sand:       return Color(red: 0.93, green: 0.83, blue: 0.55)  // sand yellow
        case .mud:        return Color(red: 0.40, green: 0.26, blue: 0.13)  // dark brown
        case .unknown:    return Color.secondary
        }
    }

    /// 0-1: fraction of normal walking speed (1 = clear trail, 0 = impassable).
    var traversability: Double {
        switch self {
        case .rock:       return 0.55   // slow, footing risk
        case .vegetation: return 0.70   // slows movement, concealment
        case .water:      return 0.25   // obstacle unless shallow ford
        case .snow:       return 0.40   // deep snow degrades speed
        case .sand:       return 0.60   // energy-intensive
        case .mud:        return 0.30   // high slip / mire risk
        case .unknown:    return 0.50
        }
    }

    var icon: String {
        switch self {
        case .rock:       return "mountain.2.fill"
        case .vegetation: return "tree.fill"
        case .water:      return "drop.fill"
        case .snow:       return "snowflake"
        case .sand:       return "hurricane"
        case .mud:        return "humidity.fill"
        case .unknown:    return "questionmark.circle"
        }
    }

    var traversabilityLabel: String {
        switch traversability {
        case 0..<0.30: return "Impassable"
        case 0.30..<0.50: return "Very Difficult"
        case 0.50..<0.70: return "Difficult"
        case 0.70..<0.90: return "Moderate"
        default:           return "Easy"
        }
    }
}

// MARK: - ClassifiedVoxel

struct ClassifiedVoxel: Identifiable {
    let id = UUID()
    let position: SIMD3<Float>      // voxel centre (m)
    let terrainClass: TerrainClass
    let confidence: Float           // 0-1
}

// MARK: - ClassificationResult

struct ClassificationResult {
    let timestamp: Date
    let voxels: [ClassifiedVoxel]
    let classCounts: [TerrainClass: Int]
    let dominantClass: TerrainClass
    let overallTraversability: Double   // weighted avg by count

    var totalVoxels: Int { voxels.count }

    func fraction(of cls: TerrainClass) -> Double {
        guard totalVoxels > 0 else { return 0 }
        return Double(classCounts[cls] ?? 0) / Double(totalVoxels)
    }
}

// MARK: - TerrainClassifierEngine

enum TerrainClassifierEngine {

    static let voxelSize: Float = 0.25   // 25 cm voxels

    // MARK: Classify

    static func classify(points: [SIMD3<Float>],
                         temperature: Float? = nil,
                         hasRecentRain: Bool = false) -> ClassificationResult {
        guard !points.isEmpty else {
            return ClassificationResult(
                timestamp: Date(), voxels: [],
                classCounts: [:], dominantClass: .unknown,
                overallTraversability: 0.5
            )
        }

        // Build voxel map: key = floor(point/voxelSize)
        var voxelMap: [SIMD3<Int32>: [SIMD3<Float>]] = [:]
        for p in points {
            let key = SIMD3<Int32>(Int32(floor(p.x / voxelSize)),
                                   Int32(floor(p.y / voxelSize)),
                                   Int32(floor(p.z / voxelSize)))
            voxelMap[key, default: []].append(p)
        }

        // For each voxel, compute features then classify
        var classified: [ClassifiedVoxel] = []
        var counts: [TerrainClass: Int] = [:]

        for (key, pts) in voxelMap {
            let centre = SIMD3<Float>(
                (Float(key.x) + 0.5) * voxelSize,
                (Float(key.y) + 0.5) * voxelSize,
                (Float(key.z) + 0.5) * voxelSize
            )
            let (cls, conf) = classifyVoxel(
                points: pts,
                centre: centre,
                temperature: temperature,
                hasRecentRain: hasRecentRain
            )
            classified.append(ClassifiedVoxel(position: centre, terrainClass: cls, confidence: conf))
            counts[cls, default: 0] += 1
        }

        // Dominant class by count
        let dominant = counts.max(by: { $0.value < $1.value })?.key ?? .unknown

        // Weighted traversability
        let total = classified.count
        let weighted = TerrainClass.allCases.reduce(0.0) {
            $0 + $1.traversability * Double(counts[$1] ?? 0) / Double(max(1, total))
        }

        return ClassificationResult(
            timestamp: Date(),
            voxels: classified,
            classCounts: counts,
            dominantClass: dominant,
            overallTraversability: weighted
        )
    }

    // MARK: Per-Voxel Classification

    /// Feature-based rule classifier using point density, height spread, planarity.
    private static func classifyVoxel(
        points: [SIMD3<Float>],
        centre: SIMD3<Float>,
        temperature: Float?,
        hasRecentRain: Bool
    ) -> (TerrainClass, Float) {

        let n = points.count
        let ys = points.map { $0.y }
        let heightSpread = (ys.max() ?? 0) - (ys.min() ?? 0)
        let density = Float(n) / (voxelSize * voxelSize * voxelSize)

        // Planarity: low spread + high density = flat surface (water, snow, sand, rock slab)
        let isFlat = heightSpread < 0.05

        // Height relative to ground: y < -0.1 = depression (water/mud candidate)
        let isDepression = centre.y < -0.1

        // High vertical spread + moderate density = vegetation
        let isVegetation = heightSpread > 0.3 && density < 500

        // Very high density + low spread = solid rock/concrete slab
        let isSolid = density > 800 && heightSpread < 0.10

        // Temperature-based: <0°C → snow candidate if flat
        let isColdEnough = (temperature ?? 15) < 2.0

        // Rain → mud candidate in depressions
        let isMudCandidate = hasRecentRain && isDepression

        if isMudCandidate {
            return (.mud, 0.72)
        }
        if isVegetation {
            return (.vegetation, 0.78)
        }
        if isColdEnough && isFlat {
            return (.snow, 0.65)
        }
        if isSolid {
            return (.rock, 0.82)
        }
        if isDepression && !isColdEnough {
            return (.water, 0.70)
        }
        if isFlat && density < 200 {
            // Low density flat = likely sand or loose surface
            return (.sand, 0.60)
        }
        return (.unknown, 0.40)
    }
}

// MARK: - TerrainClassifierManager

@MainActor
final class TerrainClassifierManager: ObservableObject {
    static let shared = TerrainClassifierManager()

    @Published var result: ClassificationResult? = nil
    @Published var isClassifying = false

    private init() {}

    func classify(from scan: SavedScan) {
        isClassifying = true
        result = nil

        Task.detached(priority: .userInitiated) {
            let points = loadPoints(from: scan)
            // Get temperature from TempLogger
            let tempC = await MainActor.run { TempLogger.shared.readings.last?.celsius }
            let rain = await MainActor.run {
                if case .rapidDrop = WeatherForecaster.shared.trend { return true }
                return false
            }
            let res = TerrainClassifierEngine.classify(
                points: points,
                temperature: tempC.map { Float($0) },
                hasRecentRain: rain
            )
            await MainActor.run { [weak self] in
                self?.result = res
                self?.isClassifying = false
            }
        }
    }

    func classifyFromCurrentBreadcrumbs() {
        isClassifying = true
        result = nil

        Task.detached(priority: .userInitiated) {
            // Convert breadcrumb trail to rough point cloud (flat surface approximation)
            let crumbs = await MainActor.run { BreadcrumbEngine.shared.trail }
            guard !crumbs.isEmpty else {
                await MainActor.run { [weak self] in self?.isClassifying = false }
                return
            }
            let origin = crumbs[0].coordinate
            let scale: Double = 111_000
            let points: [SIMD3<Float>] = crumbs.map { c in
                let x = Float((c.coordinate.longitude - origin.longitude) * scale * cos(origin.latitude * .pi / 180))
                let y = Float(c.altitude - crumbs[0].altitude)
                let z = Float(-(c.coordinate.latitude - origin.latitude) * scale)
                return SIMD3<Float>(x, y, z)
            }
            let tempC = await MainActor.run { TempLogger.shared.readings.last?.celsius }
            let rain = await MainActor.run {
                if case .rapidDrop = WeatherForecaster.shared.trend { return true }
                return false
            }
            let res = TerrainClassifierEngine.classify(
                points: points,
                temperature: tempC.map { Float($0) },
                hasRecentRain: rain
            )
            await MainActor.run { [weak self] in
                self?.result = res
                self?.isClassifying = false
            }
        }
    }
}

// Helper: load points.bin (same pattern as TerrainComparison)
private func loadPoints(from scan: SavedScan) -> [SIMD3<Float>] {
    let url = scan.scanDir.appendingPathComponent("points.bin")
    guard let data = try? Data(contentsOf: url), data.count >= 4 else { return [] }
    var count: UInt32 = 0
    _ = withUnsafeMutableBytes(of: &count) { data.copyBytes(to: $0, from: 0..<4) }
    let n = Int(count)
    guard data.count >= 4 + n * 12, n > 0 else { return [] }
    var pts = [SIMD3<Float>]()
    pts.reserveCapacity(n)
    data.withUnsafeBytes { buf in
        let base = buf.baseAddress!.advanced(by: 4).assumingMemoryBound(to: Float.self)
        for i in 0..<n { pts.append(SIMD3<Float>(base[i*3], base[i*3+1], base[i*3+2])) }
    }
    return pts
}

// MARK: - TerrainClassifierView

struct TerrainClassifierView: View {
    @ObservedObject private var mgr = TerrainClassifierManager.shared
    @ObservedObject private var storage = ScanStorage.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showScanPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if mgr.isClassifying {
                            loadingView
                        } else if let r = mgr.result {
                            summaryCard(r)
                            classBreakdownCard(r)
                            traversabilityCard(r)
                        } else {
                            noResultView
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Terrain Classifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Classify from Breadcrumbs") { mgr.classifyFromCurrentBreadcrumbs() }
                        Button("Choose Scan…") { showScanPicker = true }
                    } label: {
                        Image(systemName: "wand.and.stars").foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }
            .sheet(isPresented: $showScanPicker) {
                scanPickerSheet
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().tint(ZDDesign.cyanAccent).scaleEffect(1.4)
            Text("Classifying terrain…").font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(40)
    }

    private var noResultView: some View {
        VStack(spacing: 12) {
            Image(systemName: "mountain.2").font(.system(size: 48)).foregroundColor(.secondary)
            Text("No classification yet").font(.subheadline).foregroundColor(.secondary)
            Text("Tap  ✦  to classify from breadcrumbs or a saved scan.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(40)
    }

    // MARK: Summary

    private func summaryCard(_ r: ClassificationResult) -> some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DOMINANT TERRAIN").font(.caption.bold()).foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Image(systemName: r.dominantClass.icon).foregroundColor(r.dominantClass.color)
                        Text(r.dominantClass.rawValue)
                            .font(.system(size: 28, weight: .black))
                            .foregroundColor(r.dominantClass.color)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("OVERALL TRAVERSABILITY").font(.caption.bold()).foregroundColor(.secondary)
                    Text(String(format: "%.0f%%", r.overallTraversability * 100))
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(traversabilityColor(r.overallTraversability))
                }
            }
            Text(r.timestamp, style: .time)
                .font(.caption2).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text("\(r.totalVoxels) voxels classified")
                .font(.caption2).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: Class Breakdown

    private func classBreakdownCard(_ r: ClassificationResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TERRAIN BREAKDOWN").font(.caption.bold()).foregroundColor(.secondary)
            ForEach(TerrainClass.allCases.filter { ($0 != .unknown) && (r.classCounts[$0] ?? 0) > 0 }) { cls in
                let frac = r.fraction(of: cls)
                HStack(spacing: 10) {
                    Image(systemName: cls.icon).foregroundColor(cls.color).frame(width: 20)
                    Text(cls.rawValue).font(.caption.bold()).foregroundColor(ZDDesign.pureWhite).frame(width: 80, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(cls.color.opacity(0.15)).frame(height: 8)
                            RoundedRectangle(cornerRadius: 3).fill(cls.color)
                                .frame(width: geo.size.width * CGFloat(frac), height: 8)
                        }
                    }
                    .frame(height: 8)
                    Text(String(format: "%.0f%%", frac * 100))
                        .font(.caption2).foregroundColor(.secondary).frame(width: 32, alignment: .trailing)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: Traversability

    private func traversabilityCard(_ r: ClassificationResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRAVERSABILITY BY TERRAIN").font(.caption.bold()).foregroundColor(.secondary)
            ForEach(TerrainClass.allCases.filter { ($0 != .unknown) && (r.classCounts[$0] ?? 0) > 0 }) { cls in
                HStack(spacing: 10) {
                    Text(cls.rawValue).font(.caption).foregroundColor(.secondary).frame(width: 80, alignment: .leading)
                    Spacer()
                    Text(cls.traversabilityLabel)
                        .font(.caption.bold())
                        .foregroundColor(traversabilityColor(cls.traversability))
                    Text(String(format: "%.0f%%", cls.traversability * 100))
                        .font(.caption2).foregroundColor(.secondary).frame(width: 32, alignment: .trailing)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private func traversabilityColor(_ t: Double) -> Color {
        if t < 0.35 { return ZDDesign.signalRed }
        if t < 0.60 { return ZDDesign.safetyYellow }
        return ZDDesign.successGreen
    }

    // MARK: Scan Picker

    private var scanPickerSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                List(storage.savedScans) { scan in
                    Button {
                        showScanPicker = false
                        mgr.classify(from: scan)
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
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Choose Scan")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}
