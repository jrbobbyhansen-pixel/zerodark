// NavigationTypes.swift — Shared navigation data types (Boeing modular pattern)

import MapKit
import Foundation

/// Navigation pose: position, heading, and velocity
public struct NavPose {
    public let coordinate: CLLocationCoordinate2D
    public let heading: Double  // Degrees, 0-360
    public let speed: Double  // m/s

    public init(coordinate: CLLocationCoordinate2D, heading: Double, speed: Double) {
        self.coordinate = coordinate
        self.heading = heading.truncatingRemainder(dividingBy: 360)
        self.speed = max(0, speed)
    }
}

/// Navigation waypoint with optional metadata
public struct NavWaypoint: Identifiable, Codable {
    public let id: UUID
    public let coordinate: CLLocationCoordinate2D
    public let heading: Double?  // Optional desired heading at waypoint
    public let name: String?

    public init(coordinate: CLLocationCoordinate2D, heading: Double? = nil, name: String? = nil) {
        self.id = UUID()
        self.coordinate = coordinate
        self.heading = heading
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case id, heading, name
        case latitude, longitude
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        heading = try container.decodeIfPresent(Double.self, forKey: .heading)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        let lat = try container.decode(Double.self, forKey: .latitude)
        let lon = try container.decode(Double.self, forKey: .longitude)
        coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(heading, forKey: .heading)
        try container.encode(name, forKey: .name)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
    }
}

/// Navigation path: ordered list of waypoints
public struct NavPath {
    public let waypoints: [NavWaypoint]
    public let distanceMeters: Double

    public init(waypoints: [NavWaypoint]) {
        self.waypoints = waypoints

        var distance = 0.0
        for i in 0..<waypoints.count - 1 {
            let from = waypoints[i].coordinate
            let to = waypoints[i + 1].coordinate
            distance += from.distance(to: to)
        }
        self.distanceMeters = distance
    }
}

/// Navigation control command output
public struct NavCommand {
    public let desiredSpeed: Double  // m/s
    public let desiredHeading: Double  // Degrees
    public let turnRate: Double  // Degrees per second

    public init(desiredSpeed: Double, desiredHeading: Double, turnRate: Double) {
        self.desiredSpeed = max(0, desiredSpeed)
        self.desiredHeading = desiredHeading.truncatingRemainder(dividingBy: 360)
        self.turnRate = turnRate
    }
}

/// Navigation status and mode
public enum NavStatus {
    case idle
    case planning
    case executing(currentWaypoint: Int, totalWaypoints: Int, distanceRemaining: Double)
    case completed
    case error(String)
}
