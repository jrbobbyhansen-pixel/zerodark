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
