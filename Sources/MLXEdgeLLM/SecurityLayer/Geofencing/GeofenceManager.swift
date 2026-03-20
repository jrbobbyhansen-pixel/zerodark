// GeofenceManager.swift — Geofence management with file persistence

import Foundation
import CoreLocation

/// Geofence violation event
public struct GeofenceViolation: Identifiable {
    public let id = UUID()
    public let geofenceID: UUID
    public let geofenceName: String
    public let timestamp: Date
    public let coordinate: CodableCoordinate
    public let violationType: String  // "entry", "exit", "boundary"
}

/// Geofence status
public enum GeofenceStatus {
    case safe
    case warning
    case violation
}

/// Geofence manager singleton
@MainActor
public class GeofenceManager: ObservableObject {
    public static let shared = GeofenceManager()

    @Published public var geofences: [Geofence] = []
    @Published public var violations: [GeofenceViolation] = []

    private let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    private init() {
        loadGeofences()
    }

    /// Add a new geofence
    public func add(_ geofence: Geofence) {
        geofences.append(geofence)
        saveGeofences()
    }

    /// Remove a geofence
    public func remove(_ geofence: Geofence) {
        geofences.removeAll { $0.id == geofence.id }
        saveGeofences()
    }

    /// Check position against all geofences
    public func checkPosition(_ coordinate: CodableCoordinate) -> [GeofenceViolation] {
        var newViolations: [GeofenceViolation] = []

        for geofence in geofences {
            let isInside = geofence.contains(coordinate)
            let isKeepIn = geofence.type == "keep-in"
            let isKeepOut = geofence.type == "keep-out"

            // Determine violation
            if (isKeepIn && !isInside) || (isKeepOut && isInside) {
                let violation = GeofenceViolation(
                    geofenceID: geofence.id,
                    geofenceName: geofence.name,
                    timestamp: Date(),
                    coordinate: coordinate,
                    violationType: isInside ? "entry" : "exit"
                )
                newViolations.append(violation)
                violations.append(violation)
            }
        }

        // Trim violations list (keep last 100)
        if violations.count > 100 {
            violations = Array(violations.suffix(100))
        }

        return newViolations
    }

    /// Get status for a coordinate
    public func status(for coordinate: CodableCoordinate) -> GeofenceStatus {
        let violations = checkPosition(coordinate)
        if violations.isEmpty {
            return .safe
        } else {
            return .violation
        }
    }

    /// Save geofences to Documents
    private func saveGeofences() {
        let geofencesFile = documentsPath.appendingPathComponent("geofences.json")
        if let jsonData = try? JSONEncoder().encode(geofences) {
            try? jsonData.write(to: geofencesFile)
        }
    }

    /// Load geofences from Documents
    private func loadGeofences() {
        let geofencesFile = documentsPath.appendingPathComponent("geofences.json")
        if let jsonData = try? Data(contentsOf: geofencesFile),
           let decoded = try? JSONDecoder().decode([Geofence].self, from: jsonData) {
            self.geofences = decoded
        }
    }
}
