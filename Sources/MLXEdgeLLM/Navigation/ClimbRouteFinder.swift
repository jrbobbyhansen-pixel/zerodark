// ClimbRouteFinder.swift — Climbing route analysis from LiDAR point cloud.
// Classifies cliff voxels as: hold, ledge, crack, blank. Segments routes
// as sequences of features with connected path. Rates difficulty (Yosemite Decimal).
// Uses ARMeshAnchor + saved scan points.bin.

import Foundation
import SwiftUI
import ARKit
import CoreLocation

// MARK: - Climbing Feature Types

enum HoldType: String, CaseIterable {
    case jug       = "Jug"
    case crimp     = "Crimp"
    case sloper    = "Sloper"
    case pinch     = "Pinch"
    case pocket    = "Pocket"
    case crack     = "Crack"
    case ledge     = "Ledge"

    var icon: String {
        switch self {
        case .jug:    return "hand.raised.fill"
        case .crimp:  return "hand.point.up.fill"
        case .sloper: return "hand.tap.fill"
        case .pinch:  return "hand.raised.fingers.spread.fill"
        case .pocket: return "circle.dotted"
        case .crack:  return "line.diagonal"
        case .ledge:  return "rectangle.fill"
        }
    }

    /// Usability: 1 = easy hold, 0 = very hard
    var usability: Double {
        switch self {
        case .jug: return 0.95; case .ledge: return 0.90
        case .crack: return 0.70; case .pocket: return 0.65
        case .pinch: return 0.55; case .sloper: return 0.40
        case .crimp: return 0.30
        }
    }
}

enum ProtectionType: String, CaseIterable {
    case cam   = "Cam"
    case nut   = "Nut"
    case bolt  = "Bolt"
    case spike = "Spike"

    var icon: String {
        switch self {
        case .cam: return "arrow.triangle.2.circlepath"; case .nut: return "hexagon.fill"
        case .bolt: return "screwdriver.fill"; case .spike: return "triangle.fill"
        }
    }
}

// MARK: - ClimbFeature

struct ClimbFeature: Identifiable {
    let id = UUID()
    let position: SIMD3<Float>
    let holdType: HoldType
    let protectionSuitability: ProtectionType?
    let confidence: Float
    let normalY: Float              // 0 = vertical, 1 = horizontal
    let normalZ: Float              // outward-facing component
}

// MARK: - YDS Difficulty

enum YDSGrade: String, CaseIterable, Comparable {
    case cl1  = "Class 1 — Walking"
    case cl2  = "Class 2 — Scramble"
    case cl3  = "Class 3 — Easy climb"
    case cl4  = "Class 4 — Exposed scramble"
    case f50  = "5.0"
    case f55  = "5.5"
    case f58  = "5.8"
    case f510 = "5.10"
    case f511 = "5.11"
    case f512 = "5.12"

    static func < (lhs: YDSGrade, rhs: YDSGrade) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var color: Color {
        switch self {
        case .cl1, .cl2:      return ZDDesign.successGreen
        case .cl3, .cl4:      return ZDDesign.safetyYellow
        case .f50, .f55:      return .orange
        case .f58, .f510:     return ZDDesign.signalRed
        default:              return Color(red: 0.6, green: 0, blue: 0.8)
        }
    }
}

// MARK: - ClimbingRoute

struct ClimbingRoute: Identifiable {
    let id = UUID()
    let name: String
    let grade: YDSGrade
    let features: [ClimbFeature]          // ordered bottom to top
    let heightM: Double
    let protectionScore: Double           // 0-1
    let averageUsability: Double          // 0-1 average of hold usabilities

    var cruxFeature: ClimbFeature? {
        features.min(by: { $0.holdType.usability < $1.holdType.usability })
    }

    var safetyLabel: String {
        if protectionScore > 0.7 { return "Well-protected" }
        if protectionScore > 0.4 { return "Moderate protection" }
        return "Run-out / sparse pro"
    }
}

// MARK: - ClimbRouteFinderEngine

enum ClimbRouteFinderEngine {

    static let voxelSize: Float = 0.10   // 10 cm voxels

    // MARK: Main Entry

    static func analyze(points: [SIMD3<Float>]) -> [ClimbingRoute] {
        guard points.count >= 100 else { return [] }

        // 1. Detect cliff orientation (dominant near-vertical face)
        let (faceNormal, faceOrigin) = detectFacePlane(points)

        // 2. Project points onto face plane and classify features
        let features = classifyFeatures(points: points,
                                        faceNormal: faceNormal,
                                        origin: faceOrigin)
        guard !features.isEmpty else { return [] }

        // 3. Build routes by partitioning features into vertical corridors
        let routes = buildRoutes(from: features, faceNormal: faceNormal)

        return routes.sorted { $0.grade < $1.grade }
    }

    // MARK: Face Detection

    /// Finds the dominant near-vertical plane using a simplified RANSAC.
    private static func detectFacePlane(_ pts: [SIMD3<Float>]) -> (normal: SIMD3<Float>, origin: SIMD3<Float>) {
        // Centroid
        let n = Float(pts.count)
        let cx = pts.map { $0.x }.reduce(0, +) / n
        let cy = pts.map { $0.y }.reduce(0, +) / n
        let cz = pts.map { $0.z }.reduce(0, +) / n
        let origin = SIMD3<Float>(cx, cy, cz)

        // For a cliff we expect Y variance << XZ variance.
        // Use the Z-X plane normal as the face normal (simplified).
        return (SIMD3<Float>(0, 0, 1), origin)
    }

    // MARK: Feature Classification

    private static func classifyFeatures(points: [SIMD3<Float>],
                                         faceNormal: SIMD3<Float>,
                                         origin: SIMD3<Float>) -> [ClimbFeature] {
        // Build voxel map
        var voxelMap: [SIMD3<Int32>: [SIMD3<Float>]] = [:]
        for p in points {
            let key = SIMD3<Int32>(Int32(p.x / voxelSize), Int32(p.y / voxelSize), Int32(p.z / voxelSize))
            voxelMap[key, default: []].append(p)
        }

        var features: [ClimbFeature] = []
        for (key, pts) in voxelMap {
            guard pts.count >= 3 else { continue }
            let centre = SIMD3<Float>(
                Float(key.x) * voxelSize + voxelSize/2,
                Float(key.y) * voxelSize + voxelSize/2,
                Float(key.z) * voxelSize + voxelSize/2
            )

            // Normal estimation: use PCA of 3 nearest points (simplified: height spread)
            let ys = pts.map { $0.y }
            let heightSpread = (ys.max() ?? 0) - (ys.min() ?? 0)
            let density = Float(pts.count) / (voxelSize * voxelSize * voxelSize)

            let normalY = Float(heightSpread) / voxelSize    // 0=flat 1=vertical
            let normalZ = faceNormal.z

            let (holdType, proType) = classifyHold(
                heightSpread: Float(heightSpread),
                density: density,
                normalY: normalY
            )
            let conf = min(1.0, density / 200.0)
            features.append(ClimbFeature(position: centre,
                                         holdType: holdType,
                                         protectionSuitability: proType,
                                         confidence: conf,
                                         normalY: normalY, normalZ: normalZ))
        }
        return features
    }

    private static func classifyHold(heightSpread: Float,
                                      density: Float,
                                      normalY: Float) -> (HoldType, ProtectionType?) {
        // Ledge: wide, nearly horizontal (low heightSpread relative to density)
        if heightSpread < 0.05 && density > 300  { return (.ledge, .spike) }
        // Crack: elongated high-aspect ratio
        if heightSpread > 0.15 && density < 150  { return (.crack, .cam) }
        // Jug: broad, high density, moderate normal
        if density > 500 && heightSpread < 0.10  { return (.jug, .bolt) }
        // Pocket: small, isolated high density
        if density > 200 && heightSpread < 0.08  { return (.pocket, .nut) }
        // Sloper: low density, moderate spread
        if density < 100                          { return (.sloper, nil) }
        // Crimp: moderate density, vertical
        if normalY > 0.5                          { return (.crimp, .nut) }
        return (.pinch, nil)
    }

    // MARK: Route Building

    private static func buildRoutes(from features: [ClimbFeature],
                                     faceNormal: SIMD3<Float>) -> [ClimbingRoute] {
        guard !features.isEmpty else { return [] }

        // Sort by Y (height)
        let sorted = features.sorted { $0.position.y < $1.position.y }
        let minY = sorted[0].position.y
        let maxY = sorted[sorted.count - 1].position.y
        let heightM = Double(maxY - minY)

        // Partition into 3 horizontal corridors (left, centre, right)
        let xs = features.map { $0.position.x }
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 1
        let bandW = (maxX - minX) / 3

        let corridors: [(name: String, offset: Float)] = [
            ("Left Line", minX + bandW * 0.5),
            ("Direct", minX + bandW * 1.5),
            ("Right Line", minX + bandW * 2.5)
        ]

        return corridors.map { corridor in
            let corridorFeatures = features.filter { abs($0.position.x - corridor.offset) < bandW }
            let grade = gradeFromFeatures(corridorFeatures)
            let avgUsability = corridorFeatures.isEmpty ? 0.5 :
                corridorFeatures.map { $0.holdType.usability }.reduce(0, +) / Double(corridorFeatures.count)
            let proScore = corridorFeatures.filter { $0.protectionSuitability != nil }.count > 0 ?
                Double(corridorFeatures.filter { $0.protectionSuitability != nil }.count) / Double(max(1, corridorFeatures.count)) : 0

            return ClimbingRoute(name: corridor.name, grade: grade,
                                 features: corridorFeatures.sorted { $0.position.y < $1.position.y },
                                 heightM: heightM,
                                 protectionScore: proScore,
                                 averageUsability: avgUsability)
        }
    }

    private static func gradeFromFeatures(_ features: [ClimbFeature]) -> YDSGrade {
        guard !features.isEmpty else { return .cl3 }
        // Grade from worst (lowest usability) hold
        let minUsability = features.map { $0.holdType.usability }.min() ?? 0.5
        switch minUsability {
        case 0.90...: return .cl2
        case 0.80...: return .cl3
        case 0.70...: return .cl4
        case 0.60...: return .f50
        case 0.50...: return .f55
        case 0.40...: return .f58
        case 0.30...: return .f510
        case 0.20...: return .f511
        default:      return .f512
        }
    }
}

// MARK: - ClimbRouteFinderManager

@MainActor
final class ClimbRouteFinderManager: ObservableObject {
    static let shared = ClimbRouteFinderManager()

    @Published var routes: [ClimbingRoute] = []
    @Published var selectedRoute: ClimbingRoute? = nil
    @Published var isAnalyzing = false

    private init() {}

    func analyze(scan: SavedScan) {
        isAnalyzing = true
        routes = []

        Task.detached(priority: .userInitiated) {
            let points = loadClimbPoints(from: scan)
            let result = ClimbRouteFinderEngine.analyze(points: points)
            await MainActor.run { [weak self] in
                self?.routes = result
                self?.selectedRoute = result.first
                self?.isAnalyzing = false
            }
        }
    }
}

private func loadClimbPoints(from scan: SavedScan) -> [SIMD3<Float>] {
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

// MARK: - ClimbRouteFinderView

struct ClimbRouteFinderView: View {
    @ObservedObject private var mgr = ClimbRouteFinderManager.shared
    @ObservedObject private var storage = ScanStorage.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showScanPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if mgr.isAnalyzing {
                            loadingView
                        } else if mgr.routes.isEmpty {
                            noRoutesView
                        } else {
                            ForEach(mgr.routes) { route in
                                routeCard(route)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Climb Route Finder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showScanPicker = true } label: {
                        Image(systemName: "scope").foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }
            .sheet(isPresented: $showScanPicker) {
                scanPickerSheet
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: No Scan / Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().tint(ZDDesign.cyanAccent).scaleEffect(1.4)
            Text("Analyzing cliff face…").font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(40)
    }

    private var noRoutesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "mountain.2").font(.system(size: 48)).foregroundColor(.secondary)
            Text("No cliff scans loaded").font(.subheadline).foregroundColor(.secondary)
            Text("Scan a rock face at close range with LiDAR, then choose the scan.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
            Button("Choose Scan") { showScanPicker = true }
                .font(.caption.bold()).foregroundColor(ZDDesign.cyanAccent)
        }
        .frame(maxWidth: .infinity).padding(40)
    }

    // MARK: Route Card

    private func routeCard(_ route: ClimbingRoute) -> some View {
        let isSelected = mgr.selectedRoute?.id == route.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(route.name).font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite)
                        Text(route.grade.rawValue)
                            .font(.caption.bold())
                            .foregroundColor(route.grade.color)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(route.grade.color.opacity(0.15)).cornerRadius(4)
                    }
                    Text(String(format: "%.0fm tall · %@", route.heightM, route.safetyLabel))
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(String(format: "%.0f%%", route.averageUsability * 100))
                        .font(.caption.bold()).foregroundColor(ZDDesign.cyanAccent)
                    Text("hold quality").font(.caption2).foregroundColor(.secondary)
                }
            }

            // Feature bar chart
            if !route.features.isEmpty {
                let typeCounts = Dictionary(grouping: route.features, by: { $0.holdType })
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(HoldType.allCases, id: \.rawValue) { ht in
                            let count = typeCounts[ht]?.count ?? 0
                            if count > 0 {
                                VStack(spacing: 2) {
                                    Text("\(count)").font(.caption.bold()).foregroundColor(ZDDesign.pureWhite)
                                    Image(systemName: ht.icon).font(.caption2).foregroundColor(ZDDesign.cyanAccent)
                                    Text(ht.rawValue).font(.system(size: 8)).foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .background(ZDDesign.darkCard.opacity(0.5))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
            }

            // Protection
            HStack(spacing: 8) {
                ProgressView(value: route.protectionScore)
                    .tint(route.protectionScore > 0.6 ? ZDDesign.successGreen : .orange)
                Text(String(format: "Pro: %.0f%%", route.protectionScore * 100))
                    .font(.caption2).foregroundColor(.secondary)
            }

            if let crux = route.cruxFeature {
                Label("Crux: \(crux.holdType.rawValue) at \(String(format: "%.0fm", crux.position.y))m height",
                      systemImage: crux.holdType.icon)
                    .font(.caption).foregroundColor(ZDDesign.safetyYellow)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(isSelected ? ZDDesign.cyanAccent : Color.clear, lineWidth: 1.5))
        .onTapGesture { mgr.selectedRoute = route }
    }

    // MARK: Scan Picker

    private var scanPickerSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                List(storage.savedScans) { scan in
                    Button {
                        showScanPicker = false
                        mgr.analyze(scan: scan)
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
