// TrailDifficulty.swift — Trail difficulty scoring from terrain data
// Uses TerrainEngine.routeDifficultyScore() for overall assessment +
// per-segment slope/terrain classification for difficulty profile

import Foundation
import SwiftUI
import CoreLocation
import Charts

// MARK: - Difficulty Scale (1–5, Yosemite-inspired tactically adapted)

enum DifficultyLevel: Int, CaseIterable {
    case easy        = 1
    case moderate    = 2
    case hard        = 3
    case veryHard    = 4
    case extreme     = 5

    var label: String {
        switch self {
        case .easy:     return "Easy"
        case .moderate: return "Moderate"
        case .hard:     return "Hard"
        case .veryHard: return "Very Hard"
        case .extreme:  return "Extreme"
        }
    }

    var color: Color {
        switch self {
        case .easy:     return .green
        case .moderate: return Color(red: 0.4, green: 0.8, blue: 0.2)
        case .hard:     return .yellow
        case .veryHard: return .orange
        case .extreme:  return .red
        }
    }

    var icon: String {
        switch self {
        case .easy:     return "figure.walk"
        case .moderate: return "figure.hiking"
        case .hard:     return "mountain.2.fill"
        case .veryHard: return "exclamationmark.triangle.fill"
        case .extreme:  return "xmark.octagon.fill"
        }
    }
}

// MARK: - Trail Segment

struct TrailSegment: Identifiable {
    let id = UUID()
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
    let distanceM: Double
    let slopeDeg: Double
    let terrainType: TerrainCoverType
    let difficulty: DifficultyLevel
    let elevationGainM: Double

    static func rate(slopeDeg: Double, terrain: TerrainCoverType) -> DifficultyLevel {
        // Base from slope
        var baseLevel: Int
        switch slopeDeg {
        case ..<5:   baseLevel = 1
        case 5..<15: baseLevel = 2
        case 15..<25: baseLevel = 3
        case 25..<35: baseLevel = 4
        default:     baseLevel = 5
        }
        // Terrain modifier
        switch terrain {
        case .rocky, .rugged: baseLevel = min(5, baseLevel + 1)
        case .woodland:       baseLevel = min(5, baseLevel + 0)
        case .openGround:     break
        case .unknown:        break
        }
        return DifficultyLevel(rawValue: baseLevel) ?? .extreme
    }
}

// MARK: - Trail Route

struct TrailRoute: Identifiable {
    let id = UUID()
    let segments: [TrailSegment]
    let overallDifficulty: RouteDifficulty

    var difficultyProfile: [DifficultyLevel] { segments.map(\.difficulty) }

    var totalDistanceM: Double { segments.map(\.distanceM).reduce(0, +) }
    var totalElevationGainM: Double { segments.map { max(0, $0.elevationGainM) }.reduce(0, +) }

    var maxDifficulty: DifficultyLevel {
        segments.map(\.difficulty).max(by: { $0.rawValue < $1.rawValue }) ?? .easy
    }
}

// MARK: - TrailDifficulty (legacy compatibility shim)

struct TrailDifficulty {
    let slope: Double
    let exposure: Double
    let terrainRoughness: Double

    var difficulty: Int {
        let slopeFactor = max(0, min(1, slope / 50.0))
        let exposureFactor = max(0, min(1, exposure / 10.0))
        let terrainFactor = max(0, min(1, terrainRoughness / 5.0))
        return Int(round((slopeFactor + exposureFactor + terrainFactor) / 3.0 * 5))
    }
}

// MARK: - Trail Difficulty Scorer

@MainActor
class TrailDifficultyScorer: ObservableObject {
    static let shared = TrailDifficultyScorer()

    @Published var currentRoute: TrailRoute? = nil
    @Published var isScoring: Bool = false

    private init() {}

    /// Score a route from ordered coordinates.
    /// Samples slope + terrain at each segment midpoint using TerrainEngine.
    func score(
        waypoints: [CLLocationCoordinate2D],
        sampleIntervalM: Double = 50
    ) async -> TrailRoute? {
        guard waypoints.count >= 2 else { return nil }
        isScoring = true

        let result: TrailRoute? = await Task.detached(priority: .userInitiated) { [waypoints] in
            let engine = TerrainEngine.shared
            var segments: [TrailSegment] = []

            for i in 0..<waypoints.count - 1 {
                let start = waypoints[i]
                let end   = waypoints[i + 1]

                let midLat = (start.latitude  + end.latitude)  / 2
                let midLon = (start.longitude + end.longitude) / 2
                let mid = CLLocationCoordinate2D(latitude: midLat, longitude: midLon)

                let dist = CLLocation(latitude: start.latitude, longitude: start.longitude)
                    .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))

                let slope   = engine.slopeAt(coordinate: mid) ?? 0
                let terrain = engine.coverTerrainClassification(at: mid)
                let startE  = engine.elevationAt(coordinate: start) ?? 0
                let endE    = engine.elevationAt(coordinate: end)   ?? 0
                let gain    = endE - startE

                let level = TrailSegment.rate(slopeDeg: slope, terrain: terrain)
                segments.append(TrailSegment(
                    start: start,
                    end: end,
                    distanceM: dist,
                    slopeDeg: slope,
                    terrainType: terrain,
                    difficulty: level,
                    elevationGainM: gain
                ))
            }

            let overall = engine.routeDifficultyScore(route: waypoints)
            return TrailRoute(segments: segments, overallDifficulty: overall)
        }.value

        currentRoute = result
        isScoring = false
        return result
    }
}

// MARK: - Trail Difficulty View

struct TrailDifficultyView: View {
    let waypoints: [CLLocationCoordinate2D]
    @ObservedObject private var scorer = TrailDifficultyScorer.shared
    @State private var route: TrailRoute? = nil
    @Environment(\.dismiss) private var dismiss

    init(waypoints: [CLLocationCoordinate2D] = []) {
        self.waypoints = waypoints
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Group {
                    if scorer.isScoring {
                        scoringView
                    } else if let route {
                        routeView(route)
                    } else {
                        emptyView
                    }
                }
            }
            .navigationTitle("Trail Difficulty")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            }
            .onAppear {
                guard !waypoints.isEmpty else { return }
                Task {
                    route = await scorer.score(waypoints: waypoints)
                }
            }
        }
    }

    private var scoringView: some View {
        VStack(spacing: 16) {
            ProgressView().tint(ZDDesign.cyanAccent).scaleEffect(1.5)
            Text("Scoring terrain…").font(.subheadline).foregroundColor(.secondary)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.hiking").font(.system(size: 44)).foregroundColor(.secondary)
            Text("No Route Loaded").font(.headline)
            Text("Set waypoints in the Planner tab to analyze trail difficulty.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }.padding()
    }

    private func routeView(_ route: TrailRoute) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                overallCard(route)
                difficultyProfileChart(route)
                segmentList(route)
            }
            .padding()
        }
    }

    private func overallCard(_ route: TrailRoute) -> some View {
        HStack(spacing: 16) {
            Image(systemName: route.overallDifficulty.classification.icon)
                .font(.system(size: 36))
                .foregroundColor(route.maxDifficulty.color)

            VStack(alignment: .leading, spacing: 4) {
                Text(route.overallDifficulty.summary)
                    .font(.subheadline.bold())
                    .foregroundColor(ZDDesign.pureWhite)
                HStack(spacing: 12) {
                    Label(String(format: "%.0fm", route.totalDistanceM), systemImage: "ruler")
                    Label(String(format: "+%.0fm", route.totalElevationGainM), systemImage: "arrow.up.right")
                    Label("\(route.segments.count) segs", systemImage: "point.topleft.filled.down.to.point.bottomright.curvepath")
                }
                .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(10)
    }

    private func difficultyProfileChart(_ route: TrailRoute) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Difficulty Profile")
                .font(.caption.bold()).foregroundColor(.secondary).padding(.horizontal, 4)

            Chart {
                ForEach(Array(route.segments.enumerated()), id: \.offset) { idx, seg in
                    BarMark(
                        x: .value("Segment", idx + 1),
                        y: .value("Difficulty", seg.difficulty.rawValue)
                    )
                    .foregroundStyle(seg.difficulty.color)
                }
                RuleMark(y: .value("Easy", 1)).foregroundStyle(.green.opacity(0.3)).lineStyle(StrokeStyle(dash: [4, 3]))
            }
            .chartYScale(domain: 0...5)
            .chartXAxisLabel("Segment")
            .chartYAxisLabel("Level")
            .frame(height: 120)
            .padding()
            .background(ZDDesign.darkCard)
            .cornerRadius(10)
        }
    }

    private func segmentList(_ route: TrailRoute) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Segments")
                .font(.caption.bold()).foregroundColor(.secondary).padding(.horizontal, 4)

            ForEach(Array(route.segments.enumerated()), id: \.element.id) { idx, seg in
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(seg.difficulty.color.opacity(0.2)).frame(width: 32, height: 32)
                        Text("\(idx + 1)").font(.caption.bold()).foregroundColor(seg.difficulty.color)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(seg.difficulty.label).font(.subheadline.bold()).foregroundColor(seg.difficulty.color)
                            Spacer()
                            Label(String(format: "%.0fm", seg.distanceM), systemImage: "ruler")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        HStack(spacing: 10) {
                            Label(String(format: "%.0f°", seg.slopeDeg), systemImage: "angle")
                            Label(seg.terrainType.rawValue, systemImage: "map")
                            if seg.elevationGainM > 0.5 {
                                Label(String(format: "+%.0fm", seg.elevationGainM), systemImage: "arrow.up.right")
                            }
                        }
                        .font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding(10)
                .background(ZDDesign.darkCard)
                .cornerRadius(8)
            }
        }
    }
}
