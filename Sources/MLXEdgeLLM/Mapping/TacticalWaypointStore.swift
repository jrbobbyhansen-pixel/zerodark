// TacticalWaypointStore.swift — Waypoint model and JSON persistence (Phase 15)

import Foundation
import CoreLocation
import MapKit

// MARK: - Tactical Marker Types

enum TacticalMarker: String, CaseIterable, Codable {
    case exit
    case rallyPoint
    case cover
    case chokepoint
    case cache
    case observation
    case safeHouse
    case water
    case hazard

    var hikingLabel: String {
        switch self {
        case .exit:         return "Trailhead"
        case .rallyPoint:   return "Viewpoint"
        case .cover:        return "Rest Area"
        case .chokepoint:   return "Trail Junction"
        case .cache:        return "Waypoint"
        case .observation:  return "Scenic Overlook"
        case .safeHouse:    return "Shelter"
        case .water:        return "Water Source"
        case .hazard:       return "Steep Terrain"
        }
    }

    var icon: String {
        switch self {
        case .exit:         return "figure.walk"
        case .rallyPoint:   return "mountain.2.fill"
        case .cover:        return "leaf.fill"
        case .chokepoint:   return "arrow.triangle.branch"
        case .cache:        return "mappin"
        case .observation:  return "binoculars.fill"
        case .safeHouse:    return "house.fill"
        case .water:        return "drop.fill"
        case .hazard:       return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Tactical Waypoint

struct TacticalWaypoint: Identifiable, Codable {
    let id: UUID
    let lat: Double
    let lon: Double
    let type: TacticalMarker
    let tacticalNotes: String
    let publicDescription: String
    let createdAt: Date
    let createdBy: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var displayLabel: String {
        type.hikingLabel
    }

    var tacticalLabel: String {
        "\(type.rawValue): \(tacticalNotes)"
    }
}

// MARK: - Waypoint Store

@MainActor
final class TacticalWaypointStore: ObservableObject {
    static let shared = TacticalWaypointStore()

    @Published var waypoints: [TacticalWaypoint] = []

    private let filename = "waypoints.json"

    init() {
        load()
    }

    func add(
        type: TacticalMarker,
        coordinate: CLLocationCoordinate2D,
        tacticalNotes: String,
        publicDescription: String,
        createdBy: String = AppConfig.deviceCallsign
    ) {
        let wp = TacticalWaypoint(
            id: UUID(),
            lat: coordinate.latitude,
            lon: coordinate.longitude,
            type: type,
            tacticalNotes: tacticalNotes,
            publicDescription: publicDescription,
            createdAt: Date(),
            createdBy: createdBy
        )
        waypoints.append(wp)
        save()
    }

    func remove(id: UUID) {
        waypoints.removeAll { $0.id == id }
        save()
    }

    private func load() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([TacticalWaypoint].self, from: data) {
            waypoints = loaded
        }
    }

    private func save() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(filename)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(waypoints) {
            try? data.write(to: url)
        }
    }

    func exportGPX() -> Data {
        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="ZeroDark Hiking">
        """
        for wp in waypoints {
            gpx += """
            <wpt lat="\(wp.lat)" lon="\(wp.lon)">
                <name>\(wp.displayLabel)</name>
                <desc>\(wp.publicDescription)</desc>
            </wpt>
            """
        }
        gpx += "</gpx>"
        return gpx.data(using: .utf8) ?? Data()
    }
}
