// HlzFinder.swift — Helicopter Landing Zone analysis using SRTM terrain data
// Searches a grid around the user's position, scores each candidate via TerrainEngine.hlzScore(),
// ranks by score, and presents results with tactical guidance.

import Foundation
import SwiftUI
import CoreLocation
import MapKit

// MARK: - HLZCandidate

struct HLZCandidate: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let assessment: HLZAssessment
    let bearingFromUser: Double    // degrees true from search center
    let distanceFromUser: Double   // meters

    /// Tier 0–3 for quick visual classification
    var tier: Int {
        switch assessment.score {
        case 80...: return 0   // Excellent
        case 60..<80: return 1 // Good
        case 40..<60: return 2 // Marginal
        default: return 3      // Poor/Unusable
        }
    }

    var tierColor: Color {
        switch tier {
        case 0: return .green
        case 1: return Color(red: 0.4, green: 0.8, blue: 0.2)
        case 2: return .orange
        default: return .red
        }
    }

    var tierLabel: String { assessment.scoreDescription }
}

// MARK: - HLZ Search Config

struct HLZSearchConfig {
    /// Radius to search around center (meters). Default 300m = ~10 rotor diameters.
    var searchRadius: Double = 300
    /// Grid spacing between candidate points (meters). Default 30m = SRTM cell size.
    var gridSpacing: Double = 30
    /// Radius of each candidate LZ to evaluate (meters). Default 20m = UH-60 rotor disc ÷ 2.
    var lzRadius: Double = 20
    /// Minimum score to include in results (0–100).
    var minimumScore: Double = 20
    /// Maximum candidates to return.
    var maxCandidates: Int = 10
}

// MARK: - HLZFinderEngine

@MainActor
class HLZFinderEngine: ObservableObject {
    static let shared = HLZFinderEngine()

    @Published var candidates: [HLZCandidate] = []
    @Published var isSearching: Bool = false
    @Published var searchCenter: CLLocationCoordinate2D?
    @Published var bestCandidate: HLZCandidate?

    private init() {}

    /// Search for HLZ candidates around a center coordinate.
    func search(
        around center: CLLocationCoordinate2D,
        config: HLZSearchConfig = HLZSearchConfig()
    ) {
        isSearching = true
        searchCenter = center
        candidates = []

        Task.detached(priority: .userInitiated) { [center, config] in
            var results: [HLZCandidate] = []
            let engine = TerrainEngine.shared

            let metersPerDegLat = 111_320.0
            let metersPerDegLon = 111_320.0 * cos(center.latitude * .pi / 180)

            let steps = Int(config.searchRadius / config.gridSpacing)

            for row in -steps...steps {
                for col in -steps...steps {
                    let eastM  = Double(col) * config.gridSpacing
                    let northM = Double(row) * config.gridSpacing

                    // Skip if outside circular search radius
                    let dist = sqrt(eastM * eastM + northM * northM)
                    guard dist <= config.searchRadius else { continue }

                    let lat = center.latitude  + northM / metersPerDegLat
                    let lon = center.longitude + eastM  / metersPerDegLon
                    let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)

                    let assessment = engine.hlzScore(center: coord, radiusMeters: config.lzRadius)
                    guard assessment.score >= config.minimumScore else { continue }

                    let bearing = atan2(eastM, northM) * 180 / .pi
                    let candidate = HLZCandidate(
                        coordinate: coord,
                        assessment: assessment,
                        bearingFromUser: (bearing + 360).truncatingRemainder(dividingBy: 360),
                        distanceFromUser: dist
                    )
                    results.append(candidate)
                }
            }

            // Sort by score descending, deduplicate nearby zones (>= 30m apart)
            results.sort { $0.assessment.score > $1.assessment.score }
            var deduplicated: [HLZCandidate] = []
            for candidate in results {
                let tooClose = deduplicated.contains { existing in
                    let dx = (existing.coordinate.latitude - candidate.coordinate.latitude) * metersPerDegLat
                    let dy = (existing.coordinate.longitude - candidate.coordinate.longitude) * metersPerDegLon
                    return sqrt(dx*dx + dy*dy) < config.gridSpacing * 1.5
                }
                if !tooClose {
                    deduplicated.append(candidate)
                }
                if deduplicated.count >= config.maxCandidates { break }
            }

            await MainActor.run { [weak self] in
                self?.candidates = deduplicated
                self?.bestCandidate = deduplicated.first
                self?.isSearching = false
            }
        }
    }
}

// MARK: - HLZ Finder View

struct HLZFinderView: View {
    @ObservedObject private var engine = HLZFinderEngine.shared
    @State private var config = HLZSearchConfig()
    @State private var showConfig = false
    @State private var selectedCandidate: HLZCandidate?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if engine.isSearching {
                    searchingView
                } else if engine.candidates.isEmpty && engine.searchCenter != nil {
                    noResultsView
                } else {
                    candidateList
                }
            }
            .navigationTitle("HLZ Finder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Search") {
                        if let loc = LocationManager.shared.currentLocation {
                            engine.search(around: loc, config: config)
                        }
                    }
                    .fontWeight(.bold)
                    .foregroundColor(ZDDesign.cyanAccent)
                }
            }
            .onAppear {
                if let loc = LocationManager.shared.currentLocation {
                    engine.search(around: loc, config: config)
                }
            }
            .sheet(item: $selectedCandidate) { candidate in
                HLZDetailView(candidate: candidate)
                    .preferredColorScheme(.dark)
            }
        }
    }

    private var searchingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(ZDDesign.cyanAccent)
                .scaleEffect(1.5)
            Text("Scanning terrain…")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Checking slope, elevation, and approach paths")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundColor(.orange)
            Text("No Suitable HLZs Found")
                .font(.headline)
            Text("No zones with score ≥\(Int(config.minimumScore)) within \(Int(config.searchRadius))m.\nTry increasing search radius.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var candidateList: some View {
        ScrollView {
            VStack(spacing: 10) {
                // Best candidate banner
                if let best = engine.bestCandidate {
                    bestZoneBanner(candidate: best)
                }

                // All candidates
                ForEach(engine.candidates) { candidate in
                    let rank = (engine.candidates.firstIndex(where: { $0.id == candidate.id }) ?? 0) + 1
                    HLZCandidateRow(rank: rank, candidate: candidate)
                        .onTapGesture { selectedCandidate = candidate }
                }
            }
            .padding()
        }
    }

    private func bestZoneBanner(candidate: HLZCandidate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                Text("BEST HLZ")
                    .font(.caption.bold())
                    .foregroundColor(.yellow)
                Spacer()
                Text(String(format: "%.0f pts", candidate.assessment.score))
                    .font(.title3.bold().monospaced())
                    .foregroundColor(candidate.tierColor)
            }
            HStack(spacing: 16) {
                Label(String(format: "%.0fm away", candidate.distanceFromUser), systemImage: "location.fill")
                    .font(.caption)
                Label(String(format: "%.0f° T", candidate.bearingFromUser), systemImage: "compass.drawing")
                    .font(.caption)
                Label(String(format: "%.1f° slope", candidate.assessment.maxSlopeDeg), systemImage: "angle")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - Candidate Row

struct HLZCandidateRow: View {
    let rank: Int
    let candidate: HLZCandidate

    var body: some View {
        HStack(spacing: 12) {
            // Rank badge
            ZStack {
                Circle()
                    .fill(candidate.tierColor.opacity(0.2))
                    .frame(width: 36, height: 36)
                Text("\(rank)")
                    .font(.subheadline.bold())
                    .foregroundColor(candidate.tierColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(candidate.tierLabel)
                        .font(.subheadline.bold())
                        .foregroundColor(candidate.tierColor)
                    Spacer()
                    Text(String(format: "%.0f", candidate.assessment.score))
                        .font(.headline.bold().monospaced())
                        .foregroundColor(candidate.tierColor)
                }
                HStack(spacing: 10) {
                    Label(String(format: "%.1f°", candidate.assessment.maxSlopeDeg), systemImage: "angle")
                    Label(String(format: "%.0fm", candidate.distanceFromUser), systemImage: "location")
                    Label(String(format: "%.0f°", candidate.bearingFromUser), systemImage: "compass.drawing")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                if let factor = candidate.assessment.limitingFactor, !candidate.assessment.isFeasible {
                    Text(factor)
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(10)
    }
}

// MARK: - Detail Sheet

struct HLZDetailView: View {
    let candidate: HLZCandidate
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        // Score gauge
                        scoreGauge

                        // Metrics
                        metricsGrid

                        // Coordinates
                        coordinatesCard

                        // Tactical notes
                        if let factor = candidate.assessment.limitingFactor {
                            tacticalNote(factor)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(candidate.tierLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var scoreGauge: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: candidate.assessment.score / 100)
                    .stroke(candidate.tierColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(String(format: "%.0f", candidate.assessment.score))
                        .font(.system(size: 36, weight: .black, design: .monospaced))
                        .foregroundColor(candidate.tierColor)
                    Text("/ 100")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 120, height: 120)
            Text(candidate.tierLabel.uppercased())
                .font(.caption.bold())
                .foregroundColor(candidate.tierColor)
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            metricCard("Max Slope", value: String(format: "%.1f°", candidate.assessment.maxSlopeDeg),
                       limit: "< 7° required", ok: candidate.assessment.maxSlopeDeg < 7)
            metricCard("Elev Range", value: String(format: "%.1fm", candidate.assessment.elevationRangeM),
                       limit: "< 3m required", ok: candidate.assessment.elevationRangeM < 3)
            metricCard("Distance", value: String(format: "%.0fm", candidate.distanceFromUser),
                       limit: "from current pos", ok: true)
            metricCard("Bearing", value: String(format: "%.0f° T", candidate.bearingFromUser),
                       limit: "true north", ok: true)
        }
    }

    private func metricCard(_ label: String, value: String, limit: String, ok: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(ok ? .green : .orange)
            }
            Text(value)
                .font(.title3.bold().monospaced())
                .foregroundColor(ok ? ZDDesign.pureWhite : .orange)
            Text(limit)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(ZDDesign.darkCard)
        .cornerRadius(8)
    }

    private var coordinatesCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Coordinates", systemImage: "mappin.and.ellipse")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            Text(String(format: "%.6f, %.6f",
                        candidate.coordinate.latitude,
                        candidate.coordinate.longitude))
                .font(.body.monospaced())
                .foregroundColor(ZDDesign.cyanAccent)
                .textSelection(.enabled)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ZDDesign.darkCard)
        .cornerRadius(10)
    }

    private func tacticalNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(text)
                .font(.caption)
                .foregroundColor(.orange)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(10)
    }
}
