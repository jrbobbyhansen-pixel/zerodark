// GraphEdge.swift — Connection between waypoints (Boeing graph_map pattern)

import Foundation

/// Edge type classification
public enum EdgeType: String, Codable {
    case direct = "direct"
    case viaCheckpoint = "via_checkpoint"
    case restricted = "restricted"
}

/// Edge connecting two nodes
public struct GraphEdge: Identifiable, Codable {
    public let id: UUID
    public let fromID: UUID
    public let toID: UUID
    public let weight: Double  // meters or time
    public let edgeType: EdgeType

    public init(
        id: UUID = UUID(),
        fromID: UUID,
        toID: UUID,
        weight: Double,
        edgeType: EdgeType = .direct
    ) {
        self.id = id
        self.fromID = fromID
        self.toID = toID
        self.weight = weight
        self.edgeType = edgeType
    }
}
