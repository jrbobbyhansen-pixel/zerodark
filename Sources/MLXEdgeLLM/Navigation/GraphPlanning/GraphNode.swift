// GraphNode.swift — Waypoint node for Dijkstra planning (Boeing graph_map pattern)

import Foundation

/// Graph node representing a waypoint
public struct GraphNode: Identifiable, Codable {
    public let id: UUID
    public let coordinate: CodableCoordinate
    public let name: String?
    public let priority: Int  // For prioritizing in multi-agent scenarios

    public init(id: UUID = UUID(), coordinate: CodableCoordinate, name: String? = nil, priority: Int = 0) {
        self.id = id
        self.coordinate = coordinate
        self.name = name
        self.priority = priority
    }
}

/// Make CodableCoordinate hashable and equatable for use in graph collections
extension CodableCoordinate: Hashable, Equatable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(latitude)
        hasher.combine(longitude)
    }

    public static func == (lhs: CodableCoordinate, rhs: CodableCoordinate) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}
