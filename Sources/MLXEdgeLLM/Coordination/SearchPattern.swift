// SearchPattern.swift — Geometric Search Pattern Generator
// Implements expanding-square, creeping-line, and sector-sweep search patterns

import Foundation
import CoreLocation

struct SearchPattern {
    enum PatternType {
        case expandingSquare
        case creepingLine
        case sectorSweep
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
