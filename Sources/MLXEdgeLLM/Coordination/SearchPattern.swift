// SearchPattern.swift — SAR Search Pattern Generator + Sector Assignment + Coverage Tracking
// Patterns: parallel track (creeping line), expanding square, sector search, contour search.
// Assigns sectors to team members. Tracks per-sector coverage. Broadcasts via mesh.

import Foundation
import CoreLocation
import SwiftUI
import Combine

struct SearchPattern {
    enum PatternType: String, CaseIterable {
        case parallelTrack  = "Parallel Track"
        case expandingSquare = "Expanding Square"
        case sectorSearch   = "Sector Search"
        case contourSearch  = "Contour Search"
        // Legacy
        case creepingLine   = "Creeping Line"
        case sectorSweep    = "Sector Sweep"
    }

    let type: PatternType
    let waypoints: [CLLocationCoordinate2D]
    let coverageArea: Double                 // m²
    let estimatedDuration: TimeInterval
    let trackSpacing: Double                 // meters between parallel tracks
}

extension SearchPattern {
    /// Generate an expanding-square search pattern
    /// - Parameters:
    ///   - origin: Starting coordinate
    ///   - trackSpacing: Distance between search legs (meters)
    ///   - turns: Number of square perimeter traversals (default 4)
    /// - Returns: SearchPattern with ordered waypoints forming expanding squares
    static func expandingSquare(origin: CLLocationCoordinate2D, trackSpacing: Double, turns: Int = 4) -> SearchPattern {
        var waypoints: [CLLocationCoordinate2D] = [origin]

        let bearings: [Double] = [0, 90, 180, 270]  // N, E, S, W
        var currentPosition = origin
        var legLength = trackSpacing

        for turn in 0..<(turns * 4) {
            let bearing = bearings[turn % 4]

            // Add waypoint at end of leg
            let nextPosition = currentPosition.offsetBy(meters: legLength, bearing: bearing)
            waypoints.append(nextPosition)

            currentPosition = nextPosition

            // Increase leg length every 2 legs
            if (turn + 1) % 2 == 0 {
                legLength += trackSpacing
            }
        }

        let coverageArea = calculateCoverageArea(trackSpacing: trackSpacing, turns: turns)
        let estimatedDuration = TimeInterval(waypoints.count * 60)  // ~1 minute per waypoint at 1 m/s

        return SearchPattern(
            type: .expandingSquare,
            waypoints: waypoints,
            coverageArea: coverageArea,
            estimatedDuration: estimatedDuration,
            trackSpacing: trackSpacing
        )
    }

    /// Generate a creeping-line search pattern (parallel lanes)
    /// - Parameters:
    ///   - origin: Starting coordinate
    ///   - width: Total search area width (meters)
    ///   - legs: Number of parallel search legs
    ///   - legLength: Length of each search leg (meters)
    /// - Returns: SearchPattern with parallel waypoint tracks
    static func creepingLine(origin: CLLocationCoordinate2D, width: Double, legs: Int, legLength: Double) -> SearchPattern {
        var waypoints: [CLLocationCoordinate2D] = []

        let spacing = width / Double(legs)
        var currentLegStart = origin

        for leg in 0..<legs {
            // Alternate direction: odd legs go forward, even legs go backward
            let bearing = (leg % 2 == 0) ? 0.0 : 180.0  // N or S

            // Add waypoints along this leg
            var currentPosition = currentLegStart
            waypoints.append(currentPosition)

            // Create intermediate waypoints every 100m along leg
            let numWaypoints = Int(legLength / 100) + 1
            for i in 1...numWaypoints {
                let distance = min(Double(i) * 100, legLength)
                currentPosition = currentLegStart.offsetBy(meters: distance, bearing: bearing)
                waypoints.append(currentPosition)
            }

            // Move to next leg start (perpendicular to search direction)
            let perpendicularBearing = (leg % 2 == 0) ? 90.0 : 270.0  // E or W
            currentLegStart = currentLegStart.offsetBy(meters: spacing, bearing: perpendicularBearing)
        }

        let coverageArea = width * legLength
        let estimatedDuration = TimeInterval(waypoints.count * 60)

        return SearchPattern(
            type: .creepingLine,
            waypoints: waypoints,
            coverageArea: coverageArea,
            estimatedDuration: estimatedDuration,
            trackSpacing: spacing
        )
    }

    /// Generate a sector-sweep search pattern (radial wedges)
    /// - Parameters:
    ///   - origin: Center/origin point
    ///   - radius: Search radius (meters)
    ///   - sectors: Number of radial wedges to sweep (default 8 for 45° sectors)
    /// - Returns: SearchPattern with concentric arc waypoints
    static func sectorSweep(origin: CLLocationCoordinate2D, radius: Double, sectors: Int = 8) -> SearchPattern {
        var waypoints: [CLLocationCoordinate2D] = [origin]

        let sectorAngle = 360.0 / Double(sectors)
        let radiusSteps = Int(radius / 500) + 1  // Create arcs at 500m intervals

        for step in 1...radiusSteps {
            let currentRadius = Double(step) * (radius / Double(radiusSteps))

            for sector in 0..<sectors {
                let bearing = Double(sector) * sectorAngle
                let position = origin.offsetBy(meters: currentRadius, bearing: bearing)
                waypoints.append(position)
            }
        }

        let coverageArea = Double.pi * radius * radius
        let estimatedDuration = TimeInterval(waypoints.count * 60)

        return SearchPattern(
            type: .sectorSweep,
            waypoints: waypoints,
            coverageArea: coverageArea,
            estimatedDuration: estimatedDuration,
            trackSpacing: radius / Double(sectors)
        )
    }

    private static func calculateCoverageArea(trackSpacing: Double, turns: Int) -> Double {
        // Approximate coverage for expanding square
        var totalArea: Double = 0
        var legLength = trackSpacing

        for turn in 0..<(turns * 4) {
            totalArea += legLength * trackSpacing
            if (turn + 1) % 2 == 0 {
                legLength += trackSpacing
            }
        }

        return totalArea
    }
}

// MARK: - CLLocationCoordinate2D Extension

extension CLLocationCoordinate2D {
    /// Calculate offset coordinate given distance and bearing
    /// - Parameters:
    ///   - meters: Distance in meters
    ///   - bearing: Direction in degrees (0=North, 90=East, 180=South, 270=West)
    /// - Returns: New coordinate offset by the given distance and bearing
    func offsetBy(meters: Double, bearing: Double) -> CLLocationCoordinate2D {
        let earthRadius = 6371000.0  // meters

        let latRad = latitude * .pi / 180.0
        let lonRad = longitude * .pi / 180.0
        let bearingRad = bearing * .pi / 180.0

        let angularDistance = meters / earthRadius

        let newLatRad = asin(
            sin(latRad) * cos(angularDistance) +
            cos(latRad) * sin(angularDistance) * cos(bearingRad)
        )

        let newLonRad = lonRad + atan2(
            sin(bearingRad) * sin(angularDistance) * cos(latRad),
            cos(angularDistance) - sin(latRad) * sin(newLatRad)
        )

        return CLLocationCoordinate2D(
            latitude: newLatRad * 180.0 / .pi,
            longitude: newLonRad * 180.0 / .pi
        )
    }

    /// Calculate distance to another coordinate using Haversine formula
    /// - Parameter other: Target coordinate
    /// - Returns: Distance in meters
    func haversineDistance(to other: CLLocationCoordinate2D) -> Double {
        let earthRadius = 6371000.0  // meters

        let lat1 = latitude * .pi / 180.0
        let lat2 = other.latitude * .pi / 180.0
        let deltaLat = (other.latitude - latitude) * .pi / 180.0
        let deltaLon = (other.longitude - longitude) * .pi / 180.0

        let a = sin(deltaLat / 2) * sin(deltaLat / 2) +
                cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return earthRadius * c
    }

    /// Calculate bearing to another coordinate
    /// - Parameter other: Target coordinate
    /// - Returns: Bearing in degrees (0-360)
    func bearing(to other: CLLocationCoordinate2D) -> Double {
        let lat1 = latitude * .pi / 180.0
        let lat2 = other.latitude * .pi / 180.0
        let deltaLon = (other.longitude - longitude) * .pi / 180.0

        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let bearing = atan2(y, x) * 180.0 / .pi

        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }
}

// MARK: - LandSAR Probability Model

/// A single cell in the probability-of-area grid
struct POACell: Identifiable {
    let id = UUID()
    var coordinate: CLLocationCoordinate2D
    var gridX: Int
    var gridY: Int
    var probability: Double           // P(subject in this cell) — sums to 1.0 across all cells
    var hasBeenSearched: Bool = false
    var detectionProbability: Double = 0.0  // POD achieved when this cell was searched

    /// Probability of Containment — updated after each search via Bayes
    var poc: Double { probability * (1.0 - detectionProbability) }
}

/// Lost subject type and statistical search behavior
enum SAR_SubjectType: String, CaseIterable {
    case lostHiker    = "Lost Hiker"
    case injured      = "Injured Person"
    case dementia     = "Dementia/Alzheimer's"
    case child        = "Lost Child"
    case despondent   = "Despondent Subject"

    /// Travel tendency radius in meters (statistical baseline from ISRID database)
    var typicalRadius: Double {
        switch self {
        case .lostHiker:   return 3000
        case .injured:     return 500
        case .dementia:    return 1500
        case .child:       return 500
        case .despondent:  return 2000
        }
    }

    /// Whether subject tends toward concealment (affects terrain weighting)
    var seeksConcealment: Bool {
        switch self {
        case .despondent: return true
        default: return false
        }
    }
}

/// Bayesian probability-of-area search model based on LandSAR methodology
@MainActor
class LandSARSearchModel: ObservableObject {
    @Published var cells: [POACell] = []
    @Published var totalPOC: Double = 1.0  // Starts at 1.0, decreases as cells are searched
    @Published var recommendedCell: POACell? = nil

    private var gridRows = 0
    private var gridCols = 0

    /// Initialize a probability grid centered on lastKnownPoint
    func initializeGrid(
        center: CLLocationCoordinate2D,
        radiusMeters: Double,
        cellSizeMeters: Double = 100,
        subjectType: SAR_SubjectType
    ) {
        cells = []
        let latDelta = (cellSizeMeters / 111_320)
        let lonDelta = (cellSizeMeters / (111_320 * cos(center.latitude * .pi / 180)))
        let steps = Int(radiusMeters / cellSizeMeters)
        gridRows = steps * 2 + 1
        gridCols = steps * 2 + 1

        var rawCells: [(POACell, Double)] = []

        for row in -steps...steps {
            for col in -steps...steps {
                let coord = CLLocationCoordinate2D(
                    latitude:  center.latitude  + Double(row) * latDelta,
                    longitude: center.longitude + Double(col) * lonDelta
                )
                let distMeters = center.haversineDistance(to: coord)
                // Gaussian distribution centered on LKP, weighted by subject type radius
                let sigma = subjectType.typicalRadius
                let weight = exp(-(distMeters * distMeters) / (2 * sigma * sigma))
                let cell = POACell(
                    coordinate: coord,
                    gridX: col + steps,
                    gridY: row + steps,
                    probability: 0
                )
                rawCells.append((cell, weight))
            }
        }

        // Normalize so probabilities sum to 1.0
        let totalWeight = rawCells.map(\.1).reduce(0, +)
        cells = rawCells.map { (cell, weight) in
            var c = cell
            c.probability = totalWeight > 0 ? weight / totalWeight : 0
            return c
        }

        updateRecommendation()
    }

    /// After searching a cell, update all probabilities via Bayes theorem
    /// pod: probability of detection — 0.0 (no search) to 1.0 (thorough search)
    func markCellSearched(cellId: UUID, pod: Double) {
        guard let idx = cells.firstIndex(where: { $0.id == cellId }) else { return }
        cells[idx].hasBeenSearched = true
        cells[idx].detectionProbability = pod

        // Bayesian update: P(subject in unsearched cells) increases
        // P(not found | searched cell i) = 1 - POD_i * P_i
        let pNotFound = 1.0 - pod * cells[idx].probability
        guard pNotFound > 0 else { return }

        for i in cells.indices where i != idx {
            cells[i].probability = cells[i].probability / pNotFound
        }
        cells[idx].probability = cells[idx].probability * (1.0 - pod) / pNotFound

        // Renormalize
        let total = cells.map(\.probability).reduce(0, +)
        if total > 0 { cells = cells.map { var c = $0; c.probability /= total; return c } }

        totalPOC = cells.map(\.poc).reduce(0, +)
        updateRecommendation()
    }

    /// Returns cells sorted by highest remaining probability (optimal search order)
    func recommendedSearchSequence() -> [POACell] {
        cells.filter { !$0.hasBeenSearched }.sorted { $0.probability > $1.probability }
    }

    private func updateRecommendation() {
        recommendedCell = recommendedSearchSequence().first
    }
}

// MARK: - Additional Patterns

extension SearchPattern {
    /// Parallel track (creeping line alias) — sweeps a rectangular search area.
    static func parallelTrack(origin: CLLocationCoordinate2D, widthM: Double, lengthM: Double, trackSpacing: Double) -> SearchPattern {
        return creepingLine(origin: origin, width: widthM, legs: max(2, Int(widthM / trackSpacing)), legLength: lengthM)
    }

    /// Sector search — divides a circular area into wedges radiating from center.
    /// Each wedge is one team's assigned sector.
    static func sectorSearch(origin: CLLocationCoordinate2D, radius: Double, sectors: Int) -> SearchPattern {
        return sectorSweep(origin: origin, radius: radius, sectors: sectors)
    }

    /// Contour search — follows a fixed bearing with parallel lateral offset tracks,
    /// approximating terrain-following when combined with real elevation data.
    static func contourSearch(origin: CLLocationCoordinate2D, bearingDeg: Double, trackSpacing: Double, numTracks: Int, legLengthM: Double) -> SearchPattern {
        var waypoints: [CLLocationCoordinate2D] = []
        let perpendicularBearing = (bearingDeg + 90).truncatingRemainder(dividingBy: 360)

        for track in 0..<numTracks {
            let lateralOffset = Double(track) * trackSpacing
            let trackStart = origin.offsetBy(meters: lateralOffset, bearing: perpendicularBearing)
            let forwardBearing = track % 2 == 0 ? bearingDeg : (bearingDeg + 180).truncatingRemainder(dividingBy: 360)
            waypoints.append(trackStart)
            waypoints.append(trackStart.offsetBy(meters: legLengthM, bearing: forwardBearing))
        }

        return SearchPattern(
            type: .contourSearch,
            waypoints: waypoints,
            coverageArea: trackSpacing * Double(numTracks) * legLengthM,
            estimatedDuration: TimeInterval(waypoints.count * 90),
            trackSpacing: trackSpacing
        )
    }
}

// MARK: - Assigned Sector

struct AssignedSector: Identifiable {
    let id: UUID = UUID()
    let callsign: String     // peer name or "Self"
    let sectorIndex: Int
    let waypoints: [CLLocationCoordinate2D]
    var isComplete: Bool = false
    var completedAt: Date?
}

// MARK: - SearchPatternManager

@MainActor
class SearchPatternManager: ObservableObject {
    static let shared = SearchPatternManager()

    @Published var currentPattern: SearchPattern?
    @Published var assignments: [AssignedSector] = []
    @Published var searchOrigin: CLLocationCoordinate2D = CLLocationCoordinate2D()

    private let meshPrefix = "[search-assign]"

    private init() {}

    // MARK: - Generate + Assign

    func generate(
        type: SearchPattern.PatternType,
        origin: CLLocationCoordinate2D,
        trackSpacing: Double = 50,
        radius: Double = 500,
        sectors: Int = 8,
        widthM: Double = 400,
        lengthM: Double = 400
    ) {
        searchOrigin = origin
        let pattern: SearchPattern
        switch type {
        case .parallelTrack, .creepingLine:
            pattern = .parallelTrack(origin: origin, widthM: widthM, lengthM: lengthM, trackSpacing: trackSpacing)
        case .expandingSquare:
            pattern = .expandingSquare(origin: origin, trackSpacing: trackSpacing)
        case .sectorSearch, .sectorSweep:
            pattern = .sectorSearch(origin: origin, radius: radius, sectors: sectors)
        case .contourSearch:
            pattern = .contourSearch(origin: origin, bearingDeg: 0, trackSpacing: trackSpacing, numTracks: Int(widthM / trackSpacing), legLengthM: lengthM)
        }
        currentPattern = pattern
        assignSectors(pattern: pattern)
    }

    private func assignSectors(pattern: SearchPattern) {
        // Build team: self + mesh peers
        var team: [String] = [AppConfig.deviceCallsign]
        team += MeshService.shared.peers.filter { $0.status != .offline }.map { $0.name }

        guard !team.isEmpty, !pattern.waypoints.isEmpty else { assignments = []; return }

        // Divide waypoints into equal chunks per team member
        let chunkSize = max(1, (pattern.waypoints.count + team.count - 1) / team.count)
        assignments = team.enumerated().compactMap { idx, callsign in
            let start = idx * chunkSize
            guard start < pattern.waypoints.count else { return nil }
            let end = min(start + chunkSize, pattern.waypoints.count)
            let slice = Array(pattern.waypoints[start..<end])
            return AssignedSector(callsign: callsign, sectorIndex: idx, waypoints: slice)
        }

        broadcastAssignments()
    }

    // MARK: - Coverage

    func markComplete(sectorId: UUID) {
        if let idx = assignments.firstIndex(where: { $0.id == sectorId }) {
            assignments[idx].isComplete = true
            assignments[idx].completedAt = Date()
        }
    }

    var coveragePercent: Double {
        guard !assignments.isEmpty else { return 0 }
        return Double(assignments.filter(\.isComplete).count) / Double(assignments.count) * 100
    }

    // MARK: - Mesh Broadcast

    private func broadcastAssignments() {
        guard MeshService.shared.isActive else { return }
        let assignmentMap = assignments.map { a in
            [
                "callsign": a.callsign,
                "sectorIndex": a.sectorIndex,
                "waypoints": a.waypoints.map { ["lat": $0.latitude, "lon": $0.longitude] }
            ] as [String: Any]
        }
        if let data = try? JSONSerialization.data(withJSONObject: assignmentMap),
           let json = String(data: data, encoding: .utf8) {
            MeshService.shared.sendText(meshPrefix + json)
        }
    }
}

// MARK: - SearchPatternView

struct SearchPatternView: View {
    @ObservedObject private var manager = SearchPatternManager.shared
    @State private var patternType: SearchPattern.PatternType = .parallelTrack
    @State private var trackSpacing: Double = 50
    @State private var radiusM: Double = 500
    @State private var widthM: Double = 400
    @State private var lengthM: Double = 400
    @State private var sectors: Double = 8
    @Environment(\.dismiss) private var dismiss

    private let displayTypes: [SearchPattern.PatternType] = [.parallelTrack, .expandingSquare, .sectorSearch, .contourSearch]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        configCard
                        if !manager.assignments.isEmpty {
                            coverageCard
                            sectorList
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Search Patterns")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Config Card

    private var configCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pattern Configuration")
                .font(.caption.bold()).foregroundColor(.secondary)

            Picker("Pattern", selection: $patternType) {
                ForEach(displayTypes, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch patternType {
            case .parallelTrack, .contourSearch, .creepingLine:
                paramRow("Track Spacing", value: $trackSpacing, range: 20...200, unit: "m")
                paramRow("Width", value: $widthM, range: 100...2000, unit: "m")
                paramRow("Length", value: $lengthM, range: 100...2000, unit: "m")
            case .expandingSquare:
                paramRow("Track Spacing", value: $trackSpacing, range: 20...200, unit: "m")
            case .sectorSearch, .sectorSweep:
                paramRow("Radius", value: $radiusM, range: 100...5000, unit: "m")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sectors: \(Int(sectors))").font(.caption).foregroundColor(.secondary)
                    Slider(value: $sectors, in: 4...16, step: 1)
                        .tint(ZDDesign.cyanAccent)
                }
            }

            Button {
                let origin = LocationManager.shared.currentLocation
                    ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
                manager.generate(
                    type: patternType,
                    origin: origin,
                    trackSpacing: trackSpacing,
                    radius: radiusM,
                    sectors: Int(sectors),
                    widthM: widthM,
                    lengthM: lengthM
                )
            } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("Generate & Assign").font(.headline.bold())
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(ZDDesign.cyanAccent)
                .cornerRadius(10)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(10)
    }

    private func paramRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        HStack {
            Text("\(label): \(Int(value.wrappedValue))\(unit)")
                .font(.caption).foregroundColor(.secondary).frame(minWidth: 130, alignment: .leading)
            Slider(value: value, in: range).tint(ZDDesign.cyanAccent)
        }
    }

    // MARK: - Coverage Card

    private var coverageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Coverage").font(.caption.bold()).foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", manager.coveragePercent))
                    .font(.title2.bold().monospaced())
                    .foregroundColor(coverageColor(manager.coveragePercent))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1)).frame(height: 8)
                    Capsule()
                        .fill(coverageColor(manager.coveragePercent))
                        .frame(width: geo.size.width * CGFloat(manager.coveragePercent / 100), height: 8)
                }
            }
            .frame(height: 8)
            HStack {
                Text("\(manager.assignments.filter(\.isComplete).count) / \(manager.assignments.count) sectors complete")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                if let p = manager.currentPattern {
                    Text(String(format: "%.0f m²", p.coverageArea))
                        .font(.caption.monospaced()).foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(10)
    }

    private func coverageColor(_ pct: Double) -> Color {
        switch pct {
        case 75...: return .green
        case 50..<75: return .yellow
        case 25..<50: return .orange
        default: return .red
        }
    }

    // MARK: - Sector List

    private var sectorList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sector Assignments").font(.caption.bold()).foregroundColor(.secondary)
            ForEach(manager.assignments) { sector in
                HStack(spacing: 12) {
                    Image(systemName: sector.isComplete ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(sector.isComplete ? .green : ZDDesign.cyanAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(sector.callsign).font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite)
                            Text("Sector \(sector.sectorIndex + 1)").font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text("\(sector.waypoints.count) wpts").font(.caption2.monospaced()).foregroundColor(.secondary)
                        }
                        if let done = sector.completedAt {
                            Text("Completed \(done, style: .relative) ago").font(.caption2).foregroundColor(.green)
                        }
                    }
                    if !sector.isComplete {
                        Button("Done") { manager.markComplete(sectorId: sector.id) }
                            .font(.caption.bold()).foregroundColor(.black)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(ZDDesign.cyanAccent).cornerRadius(6)
                    }
                }
                .padding(10)
                .background(ZDDesign.darkCard)
                .cornerRadius(8)
            }
        }
    }
}
