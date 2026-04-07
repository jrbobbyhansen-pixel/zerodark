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

                // v6.1: Rotate crypto session key on geofence crossing
                MeshKeychain.shared.rotateKeyForGeofence(fenceId: geofence.id, fenceName: geofence.name)
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

    // MARK: - OpSec Relay Filtering (v6.2)

    /// Check if a coordinate is outside all active geofence constraints
    public func isOutOfZone(coordinate: CodableCoordinate) -> Bool {
        for geofence in geofences {
            let isInside = geofence.contains(coordinate)
            if geofence.type == "keep-in" && !isInside { return true }
            if geofence.type == "keep-out" && isInside { return true }
        }
        return false
    }

    /// Determine if mesh relay to a peer location should be allowed
    /// Returns false (denied) for nil location or out-of-zone coordinates
    public func shouldAllowRelay(to peerLocation: CLLocationCoordinate2D?) -> Bool {
        guard let loc = peerLocation else { return false }
        let coord = CodableCoordinate(latitude: loc.latitude, longitude: loc.longitude)
        return !isOutOfZone(coordinate: coord)
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
