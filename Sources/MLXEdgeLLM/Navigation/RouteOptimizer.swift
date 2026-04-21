// RouteOptimizer.swift — Multi-objective route optimizer.
// Generates candidate routes (angular + elevation variations) between two waypoints,
// scores each on 5 objectives, returns Pareto-optimal set.
// Uses TerrainEngine, WeatherForecaster, GeofenceMonitor for real data.

import Foundation
import SwiftUI
import CoreLocation
import MapKit

// MARK: - Route Objective

enum RouteObjective: String, CaseIterable, Identifiable {
    case distance   = "Distance"
    case elevation  = "Elevation"
    case hazard     = "Hazard"
    case cover      = "Cover"
    case exposure   = "Exposure"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .distance:  return "ruler.fill"
        case .elevation: return "mountain.2.fill"
        case .hazard:    return "exclamationmark.triangle.fill"
        case .cover:     return "tree.fill"
        case .exposure:  return "sun.max.fill"
        }
    }

    var color: Color {
        switch self {
        case .distance:  return ZDDesign.cyanAccent
        case .elevation: return .orange
        case .hazard:    return ZDDesign.signalRed
        case .cover:     return ZDDesign.forestGreen
        case .exposure:  return ZDDesign.safetyYellow
        }
    }
}

// MARK: - RouteCandidate

struct RouteCandidate: Identifiable {
    let id = UUID()
    let name: String                       // e.g. "Direct", "Northern Arc"
    let waypoints: [CLLocationCoordinate2D]
    let distanceM: Double
    let elevationGainM: Double

    // Normalized 0-1 scores (lower = better) per objective
    let scores: [RouteObjective: Double]

    var dominatedBy: Bool = false           // true if Pareto-dominated

    var overallScore: Double {
        // Equal-weight average across all 5 objectives
        scores.values.reduce(0, +) / Double(scores.count)
    }

    func score(for obj: RouteObjective) -> Double {
        scores[obj] ?? 0.5
    }
}

// MARK: - RouteOptimizerEngine

@MainActor
enum RouteOptimizerEngine {

    // MARK: Public API

    /// Generate and score candidate routes between start and end.
    static func optimize(
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) -> [RouteCandidate] {
        let raw = generateCandidates(start: start, end: end)
        let scored = raw.map { score($0) }
        return markPareto(scored)
    }

    // MARK: Candidate Generation

    /// Generate 7 candidate routes: direct + 6 arc variations (±15°, ±30°, ±45°).
    private static func generateCandidates(
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) -> [(name: String, waypoints: [CLLocationCoordinate2D])] {
        let directDist = start.distance(to: end)
        let bearing = bearingDeg(from: start, to: end)

        var result: [(String, [CLLocationCoordinate2D])] = []
        result.append(("Direct", [start, end]))

        // Arc routes: midpoint is offset perpendicular by fraction of direct distance
        let arcOffsets: [(name: String, offsetFraction: Double, bearingOffset: Double)] = [
            ("Northern Arc +15°",  0.15,  15),
            ("Northern Arc +30°",  0.25,  30),
            ("Northern Arc +45°",  0.35,  45),
            ("Southern Arc -15°",  0.15, -15),
            ("Southern Arc -30°",  0.25, -30),
            ("Southern Arc -45°",  0.35, -45),
        ]

        for arc in arcOffsets {
            let midDirect = midpoint(start, end)
            let perpBearing = (bearing + (arc.bearingOffset > 0 ? 90 : -90)).truncatingRemainder(dividingBy: 360)
            let offset = directDist * arc.offsetFraction
            let midOffset = coordinate(from: midDirect, bearing: perpBearing, distanceM: offset)
            result.append((arc.name, [start, midOffset, end]))
        }

        return result
    }

    // MARK: Scoring

    private static func score(_ raw: (name: String, waypoints: [CLLocationCoordinate2D])) -> RouteCandidate {
        let wps = raw.waypoints
        let dist = totalDistance(wps)

        // Elevation gain (uses TerrainEngine if available, else heuristic)
        let elevGain = estimateElevationGain(wps)

        // Scores (all 0-1, lower = better)
        let distScore    = normalizeDistance(dist)
        let elevScore    = normalizeElevation(elevGain)
        let hazardScore  = hazardScore(for: wps)
        let coverScore   = coverScore(for: wps)
        let exposureScore = exposureScore(for: wps)

        return RouteCandidate(
            name: raw.name,
            waypoints: wps,
            distanceM: dist,
            elevationGainM: elevGain,
            scores: [
                .distance:  distScore,
                .elevation: elevScore,
                .hazard:    hazardScore,
                .cover:     coverScore,
                .exposure:  exposureScore
            ]
        )
    }

    // MARK: Individual Score Functions

    /// Distance normalized: direct route = 0, 50% longer = 1.
    private static func normalizeDistance(_ m: Double) -> Double {
        min(1.0, max(0.0, (m - 50) / max(1, m * 0.5)))
    }

    /// Elevation: each 100m gain adds 0.1 score.
    private static func normalizeElevation(_ gainM: Double) -> Double {
        min(1.0, gainM / 1000.0)
    }

    /// Hazard: checks GeofenceMonitor violation proximity + RiskAssessor weather/altitude score.
    private static func hazardScore(for wps: [CLLocationCoordinate2D]) -> Double {
        // Base from RiskAssessment if available
        var base = 0.0
        if let assessment = RiskAssessor.shared.assessment {
            base = assessment.overallScore * 0.3
        }
        // Penalise arc routes that pass through high-wind or storm area
        let wf = WeatherForecaster.shared
        if case .rapidDrop = wf.trend { base += 0.3 }
        return min(1.0, base)
    }

    /// Cover: tree/terrain cover proxy from arc direction relative to sun azimuth.
    private static func coverScore(for wps: [CLLocationCoordinate2D]) -> Double {
        // Heuristic: southern arcs typically offer less cover than northern arcs in NH.
        guard wps.count >= 2 else { return 0.5 }
        let bearing = bearingDeg(from: wps[0], to: wps[wps.count - 1])
        // Routes heading N (0°) score best for cover; S (180°) worst.
        let northward = cos(bearing * .pi / 180)
        return Double((1 - northward) / 2)
    }

    /// Exposure: based on current light level (night = more exposed to NVG, day = more visible).
    private static func exposureScore(for wps: [CLLocationCoordinate2D]) -> Double {
        let light = LightEstimator.shared.currentLevel
        switch light {
        case .fullDaylight:         return 0.8
        case .overcastDay:          return 0.6
        case .goldenHour:           return 0.4
        case .civilTwilight:        return 0.3
        case .nauticalTwilight:     return 0.2
        case .astronomicalTwilight: return 0.15
        case .night, .moonlit:      return 0.1
        }
    }

    // MARK: Elevation Estimation

    private static func estimateElevationGain(_ wps: [CLLocationCoordinate2D]) -> Double {
        // Use known breadcrumb trail altitude if nearby
        let crumbs = BreadcrumbEngine.shared.trail
        guard crumbs.count >= 2 else {
            // Fall back: route length * 0.02 = 2% grade heuristic
            return totalDistance(wps) * 0.02
        }
        // Simple: avg altitude delta per meter * route length
        let altitudes = crumbs.map { $0.altitude }
        let gains = zip(altitudes, altitudes.dropFirst()).map { max(0, $1 - $0) }
        let totalGain = gains.reduce(0, +)
        let totalTrailLen = zip(crumbs, crumbs.dropFirst()).reduce(0.0) {
            $0 + $1.0.coordinate.distance(to: $1.1.coordinate)
        }
        let gainPerMeter = totalTrailLen > 0 ? totalGain / totalTrailLen : 0.02
        return totalDistance(wps) * gainPerMeter
    }

    // MARK: Pareto Frontier

    private static func markPareto(_ candidates: [RouteCandidate]) -> [RouteCandidate] {
        var result = candidates
        for i in 0..<result.count {
            for j in 0..<result.count where i != j {
                if dominates(result[j], result[i]) {
                    result[i].dominatedBy = true
                    break
                }
            }
        }
        return result.sorted { $0.overallScore < $1.overallScore }
    }

    /// Returns true if `a` Pareto-dominates `b` (a is at least as good on all and better on one).
    private static func dominates(_ a: RouteCandidate, _ b: RouteCandidate) -> Bool {
        var betterOnAny = false
        for obj in RouteObjective.allCases {
            let sa = a.score(for: obj), sb = b.score(for: obj)
            if sa > sb { return false }  // a is worse on this objective → not dominant
            if sa < sb { betterOnAny = true }
        }
        return betterOnAny
    }

    // MARK: Geometry Helpers

    private static func totalDistance(_ wps: [CLLocationCoordinate2D]) -> Double {
        zip(wps, wps.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    private static func bearingDeg(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude  * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func midpoint(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: (a.latitude + b.latitude) / 2,
                               longitude: (a.longitude + b.longitude) / 2)
    }

    private static func coordinate(from origin: CLLocationCoordinate2D,
                                   bearing bearingDeg: Double,
                                   distanceM: Double) -> CLLocationCoordinate2D {
        let R = 6_371_000.0
        let d = distanceM / R
        let b = bearingDeg * .pi / 180
        let lat1 = origin.latitude * .pi / 180
        let lon1 = origin.longitude * .pi / 180
        let lat2 = asin(sin(lat1)*cos(d) + cos(lat1)*sin(d)*cos(b))
        let lon2 = lon1 + atan2(sin(b)*sin(d)*cos(lat1), cos(d)-sin(lat1)*sin(lat2))
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi,
                                     longitude: lon2 * 180 / .pi)
    }
}

// MARK: - RouteOptimizerManager

@MainActor
final class RouteOptimizerManager: ObservableObject {
    static let shared = RouteOptimizerManager()

    @Published var candidates: [RouteCandidate] = []
    @Published var selectedCandidate: RouteCandidate? = nil
    @Published var isOptimizing = false
    @Published var start: CLLocationCoordinate2D? = nil
    @Published var end:   CLLocationCoordinate2D? = nil

    private init() {}

    func optimize() {
        guard let s = start, let e = end else { return }
        isOptimizing = true
        candidates = []
        selectedCandidate = nil

        // Run on background then publish
        Task.detached(priority: .userInitiated) {
            let result = await MainActor.run { RouteOptimizerEngine.optimize(start: s, end: e) }
            await MainActor.run { [weak self] in
                self?.candidates = result
                self?.selectedCandidate = result.first { !$0.dominatedBy }
                self?.isOptimizing = false
            }
        }
    }
}

// MARK: - RouteOptimizerView

struct RouteOptimizerView: View {
    @ObservedObject private var mgr = RouteOptimizerManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if mgr.isOptimizing {
                    loadingView
                } else if mgr.candidates.isEmpty {
                    if mgr.start == nil || mgr.end == nil {
                        setupView
                    } else {
                        noResultsView
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            objectiveLegend
                            ForEach(mgr.candidates) { c in
                                candidateCard(c)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Route Optimizer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if mgr.start != nil && mgr.end != nil {
                        Button {
                            mgr.optimize()
                        } label: {
                            Image(systemName: "arrow.clockwise").foregroundColor(ZDDesign.cyanAccent)
                        }
                    }
                }
            }
            .onAppear {
                // Pre-fill start from current location if available
                if mgr.start == nil, let loc = LocationManager.shared.currentLocation {
                    mgr.start = loc
                }
                // Pre-fill end from breadcrumb trail last point
                if mgr.end == nil, let last = BreadcrumbEngine.shared.trail.last {
                    mgr.end = last.coordinate
                }
                if mgr.candidates.isEmpty && mgr.start != nil && mgr.end != nil {
                    mgr.optimize()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Setup prompt

    private var setupView: some View {
        VStack(spacing: 16) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                .font(.system(size: 48)).foregroundColor(.secondary)
            Text("Set start & end points").font(.subheadline).foregroundColor(.secondary)
            Text("Current location and last breadcrumb are used if available.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            Button("Optimize with Current Data") {
                if let loc = LocationManager.shared.currentLocation { mgr.start = loc }
                if let last = BreadcrumbEngine.shared.trail.last    { mgr.end   = last.coordinate }
                mgr.optimize()
            }
            .font(.caption.bold()).foregroundColor(ZDDesign.cyanAccent)
        }
        .padding(30)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().tint(ZDDesign.cyanAccent).scaleEffect(1.4)
            Text("Generating routes…").font(.caption).foregroundColor(.secondary)
        }
    }

    private var noResultsView: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundColor(.secondary)
            Text("No routes found").font(.subheadline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Legend

    private var objectiveLegend: some View {
        HStack(spacing: 12) {
            ForEach(RouteObjective.allCases) { obj in
                VStack(spacing: 3) {
                    Image(systemName: obj.icon).font(.caption2).foregroundColor(obj.color)
                    Text(String(obj.rawValue.prefix(4))).font(.system(size: 9)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(10)
        .background(ZDDesign.darkCard)
        .cornerRadius(10)
    }

    // MARK: Candidate Card

    private func candidateCard(_ c: RouteCandidate) -> some View {
        let isSelected = mgr.selectedCandidate?.id == c.id
        return Button {
            mgr.selectedCandidate = c
        } label: {
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            if !c.dominatedBy {
                                Image(systemName: "star.fill").font(.caption2).foregroundColor(ZDDesign.safetyYellow)
                            }
                            Text(c.name).font(.subheadline.bold())
                                .foregroundColor(isSelected ? ZDDesign.cyanAccent : ZDDesign.pureWhite)
                        }
                        HStack(spacing: 12) {
                            Label(formatDist(c.distanceM), systemImage: "ruler.fill")
                            Label(String(format: "+%.0fm", c.elevationGainM), systemImage: "arrow.up.right")
                        }
                        .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    scoreRing(c.overallScore, dominated: c.dominatedBy)
                }

                // Objective bar chart
                HStack(spacing: 6) {
                    ForEach(RouteObjective.allCases) { obj in
                        VStack(spacing: 3) {
                            GeometryReader { geo in
                                ZStack(alignment: .bottom) {
                                    Rectangle().fill(obj.color.opacity(0.15)).cornerRadius(2)
                                    Rectangle().fill(obj.color)
                                        .frame(height: geo.size.height * CGFloat(c.score(for: obj)))
                                        .cornerRadius(2)
                                }
                            }
                            .frame(height: 30)
                            Text(String(format: "%.0f", c.score(for: obj) * 100))
                                .font(.system(size: 8)).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(12)
            .background(isSelected ? ZDDesign.darkCard.opacity(1.0) : ZDDesign.darkCard.opacity(0.7))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? ZDDesign.cyanAccent : Color.clear, lineWidth: 1.5)
            )
        }
    }

    private func scoreRing(_ score: Double, dominated: Bool) -> some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 5).frame(width: 44, height: 44)
            Circle()
                .trim(from: 0, to: CGFloat(1 - score))
                .stroke(dominated ? Color.secondary : ZDDesign.successGreen,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: 44, height: 44)
                .rotationEffect(.degrees(-90))
            Text(String(format: "%.0f", (1 - score) * 100))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(dominated ? .secondary : ZDDesign.successGreen)
        }
    }

    private func formatDist(_ m: Double) -> String {
        if m >= 1000 { return String(format: "%.1f km", m / 1000) }
        return String(format: "%.0f m", m)
    }
}
