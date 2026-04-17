// NavigationGraph.swift — Persistent waypoint graph (Boeing graph_map pattern)

import Foundation
import Observation

/// Main navigation graph for Dijkstra planning
@MainActor
public class NavigationGraph: NSObject, ObservableObject {
    @Published public var nodes: [UUID: GraphNode] = [:]
    @Published public var edges: [UUID: GraphEdge] = [:]

    private let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private var graphFile: URL { documentsPath.appendingPathComponent("nav_graph.json") }

    public override init() {
        super.init()
        loadGraph()
    }

    /// Add node to graph
    public func addNode(_ node: GraphNode) {
        nodes[node.id] = node
        saveGraph()
    }

    /// Add edge to graph
    public func addEdge(_ edge: GraphEdge) {
        edges[edge.id] = edge
        saveGraph()
    }

    /// Remove node and its edges
    public func removeNode(id: UUID) {
        nodes.removeValue(forKey: id)
        edges = edges.filter { $0.value.fromID != id && $0.value.toID != id }
        saveGraph()
    }

    /// Remove edge
    public func removeEdge(id: UUID) {
        edges.removeValue(forKey: id)
        saveGraph()
    }

    /// Get outgoing edges from node
    public func outgoingEdges(from nodeID: UUID) -> [GraphEdge] {
        edges.values.filter { $0.fromID == nodeID }
    }

    /// Get incoming edges to node
    public func incomingEdges(to nodeID: UUID) -> [GraphEdge] {
        edges.values.filter { $0.toID == nodeID }
    }

    // MARK: - Dijkstra Path Finding

    /// Find the lowest-cost path from `fromID` to `toID` using Dijkstra's algorithm.
    /// Edge weight represents cost (distance in meters or travel time).
    /// - Returns: Ordered array of nodes from source to destination, or `nil` if no path exists.
    public func findPath(from fromID: UUID, to toID: UUID) -> [GraphNode]? {
        guard nodes[fromID] != nil, nodes[toID] != nil else { return nil }
        if fromID == toID { return nodes[fromID].map { [$0] } }

        // Priority queue entry: (cost, nodeID)
        var dist: [UUID: Double] = [fromID: 0]
        var prev: [UUID: UUID] = [:]
        // Simple min-heap via sorted array (graph is small — hundreds of nodes max)
        var queue: [(cost: Double, id: UUID)] = [(0, fromID)]

        while !queue.isEmpty {
            // Pop minimum-cost entry
            queue.sort { $0.cost < $1.cost }
            let (currentCost, currentID) = queue.removeFirst()

            if currentID == toID { break }

            // Skip stale queue entries
            if currentCost > (dist[currentID] ?? .infinity) { continue }

            for edge in outgoingEdges(from: currentID) {
                // Skip restricted edges
                if edge.edgeType == .restricted { continue }

                let newCost = currentCost + edge.weight
                if newCost < (dist[edge.toID] ?? .infinity) {
                    dist[edge.toID] = newCost
                    prev[edge.toID] = currentID
                    queue.append((newCost, edge.toID))
                }
            }
        }

        // Reconstruct path by walking prev[] backwards
        guard dist[toID] != nil else { return nil }

        var path: [GraphNode] = []
        var current: UUID? = toID
        while let nodeID = current {
            guard let node = nodes[nodeID] else { break }
            path.insert(node, at: 0)
            current = prev[nodeID]
        }

        // Validate path starts from source
        guard path.first?.id == fromID else { return nil }
        return path
    }

    /// Persist to file
    private func saveGraph() {
        let data = GraphData(nodes: Array(nodes.values), edges: Array(edges.values))

        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: graphFile)
        }
    }

    /// Load from file
    private func loadGraph() {
        guard let data = try? Data(contentsOf: graphFile),
              let decoded = try? JSONDecoder().decode(GraphData.self, from: data) else {
            return
        }

        nodes = decoded.nodes.reduce(into: [:]) { $0[$1.id] = $1 }
        edges = decoded.edges.reduce(into: [:]) { $0[$1.id] = $1 }
    }

    /// Codable wrapper
    private struct GraphData: Codable {
        let nodes: [GraphNode]
        let edges: [GraphEdge]
    }
}
