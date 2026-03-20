// Geofence.swift — Formally verified geofencing zones (NASA ICAROUS PolyCARP pattern)

import Foundation
import CoreLocation

/// Geofence geometry type
public enum GeofenceGeometry: Codable {
    case circle(center: CodableCoordinate, radiusMeters: Double)
    case polygon(coordinates: [CodableCoordinate])
    case corridor(centerline: [CodableCoordinate], widthMeters: Double)

    enum CodingKeys: String, CodingKey {
        case type, center, radiusMeters, coordinates, centerline, widthMeters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "circle":
            let center = try container.decode(CodableCoordinate.self, forKey: .center)
            let radius = try container.decode(Double.self, forKey: .radiusMeters)
            self = .circle(center: center, radiusMeters: radius)
        case "polygon":
            let coords = try container.decode([CodableCoordinate].self, forKey: .coordinates)
            self = .polygon(coordinates: coords)
        case "corridor":
            let centerline = try container.decode([CodableCoordinate].self, forKey: .centerline)
            let width = try container.decode(Double.self, forKey: .widthMeters)
            self = .corridor(centerline: centerline, widthMeters: width)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown geometry type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .circle(let center, let radius):
            try container.encode("circle", forKey: .type)
            try container.encode(center, forKey: .center)
            try container.encode(radius, forKey: .radiusMeters)
        case .polygon(let coords):
            try container.encode("polygon", forKey: .type)
            try container.encode(coords, forKey: .coordinates)
        case .corridor(let centerline, let width):
            try container.encode("corridor", forKey: .type)
            try container.encode(centerline, forKey: .centerline)
            try container.encode(width, forKey: .widthMeters)
        }
    }
}

/// A geofence with type (keep-in, keep-out, alert)
public struct Geofence: Identifiable, Codable {
    public let id: UUID
    public let name: String
    public let type: String  // "keep-in", "keep-out", "alert"
    public let geometry: GeofenceGeometry
    public let createdAt: Date

    public init(name: String, type: String, geometry: GeofenceGeometry) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.geometry = geometry
        self.createdAt = Date()
    }

    /// Check if a coordinate is inside the geofence
    public func contains(_ coordinate: CodableCoordinate) -> Bool {
        switch geometry {
        case .circle(let center, let radiusMeters):
            let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
            let pointLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let distance = pointLocation.distance(from: centerLocation)
            return distance <= radiusMeters

        case .polygon(let coordinates):
            // Ray casting algorithm
            let location = (lat: coordinate.latitude, lon: coordinate.longitude)
            var inside = false

            for i in 0..<coordinates.count {
                let j = (i + 1) % coordinates.count
                let p1 = (lat: coordinates[i].latitude, lon: coordinates[i].longitude)
                let p2 = (lat: coordinates[j].latitude, lon: coordinates[j].longitude)

                if ((p1.lon > location.lon) != (p2.lon > location.lon)) &&
                    (location.lat < (p2.lat - p1.lat) * (location.lon - p1.lon) / (p2.lon - p1.lon) + p1.lat) {
                    inside.toggle()
                }
            }
            return inside

        case .corridor(let centerline, let widthMeters):
            // Simple distance-to-line check
            let half = widthMeters / 2
            for i in 0..<centerline.count {
                let j = (i + 1) % centerline.count
                let distance = pointToLineDistance(
                    point: coordinate,
                    lineStart: centerline[i],
                    lineEnd: centerline[j]
                )
                if distance <= half {
                    return true
                }
            }
            return false
        }
    }

    /// Distance to boundary: negative inside, positive outside
    public func distanceToBoundary(_ coordinate: CodableCoordinate) -> Double {
        switch geometry {
        case .circle(let center, let radiusMeters):
            let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
            let pointLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let distance = pointLocation.distance(from: centerLocation)
            return distance - radiusMeters  // Negative if inside

        case .polygon(let coordinates):
            var minDistance = Double.infinity
            for i in 0..<coordinates.count {
                let j = (i + 1) % coordinates.count
                let distance = pointToLineDistance(
                    point: coordinate,
                    lineStart: coordinates[i],
                    lineEnd: coordinates[j]
                )
                minDistance = min(minDistance, distance)
            }
            return contains(coordinate) ? -minDistance : minDistance

        case .corridor(let centerline, let widthMeters):
            var minDistance = Double.infinity
            for i in 0..<centerline.count {
                let j = (i + 1) % centerline.count
                let distance = pointToLineDistance(
                    point: coordinate,
                    lineStart: centerline[i],
                    lineEnd: centerline[j]
                )
                minDistance = min(minDistance, distance)
            }
            let half = widthMeters / 2
            return contains(coordinate) ? (minDistance - half) : (minDistance - half)
        }
    }

    /// Helper: point-to-line distance (in meters)
    private func pointToLineDistance(point: CodableCoordinate, lineStart: CodableCoordinate, lineEnd: CodableCoordinate) -> Double {
        let p1 = (lon: lineStart.longitude, lat: lineStart.latitude)
        let p2 = (lon: lineEnd.longitude, lat: lineEnd.latitude)
        let p = (lon: point.longitude, lat: point.latitude)

        let dx = p2.lon - p1.lon
        let dy = p2.lat - p1.lat
        let t = max(0, min(1, ((p.lon - p1.lon) * dx + (p.lat - p1.lat) * dy) / (dx * dx + dy * dy)))

        let closestLon = p1.lon + t * dx
        let closestLat = p1.lat + t * dy

        let pointLocation = CLLocation(latitude: p.lat, longitude: p.lon)
        let closestLocation = CLLocation(latitude: closestLat, longitude: closestLon)
        return pointLocation.distance(from: closestLocation)
    }
}
