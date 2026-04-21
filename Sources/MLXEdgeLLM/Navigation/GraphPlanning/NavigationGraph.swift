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

    /// Adjacency index rebuilt on demand: nodeID → outgoing edges. Much cheaper than
    /// filtering the full edges dict on every relax step during Dijkstra.
    private func buildAdjacency() -> [UUID: [GraphEdge]] {
        var adj: [UUID: [GraphEdge]] = [:]
        adj.reserveCapacity(nodes.count)
        for edge in edges.values {
            adj[edge.fromID, default: []].append(edge)
        }
        return adj
    }

    /// Find the lowest-cost path from `fromID` to `toID` using Dijkstra's algorithm
    /// backed by a binary min-heap. Complexity: O((V + E) log V).
    /// Edge weight represents cost (distance in meters or travel time).
    /// - Returns: Ordered array of nodes from source to destination, or `nil` if no path exists.
    public func findPath(from fromID: UUID, to toID: UUID) -> [GraphNode]? {
        guard nodes[fromID] != nil, nodes[toID] != nil else { return nil }
        if fromID == toID { return nodes[fromID].map { [$0] } }

        var dist: [UUID: Double] = [fromID: 0]
        var prev: [UUID: UUID] = [:]
        var heap = MinHeap<HeapEntry>()
        heap.push(HeapEntry(cost: 0, id: fromID))

        let adjacency = buildAdjacency()

        while let top = heap.pop() {
            let currentCost = top.cost
            let currentID = top.id

            if currentID == toID { break }

            // Skip stale heap entries (a cheaper path was found after this was enqueued)
            if currentCost > (dist[currentID] ?? .infinity) { continue }

            for edge in adjacency[currentID] ?? [] {
                if edge.edgeType == .restricted { continue }

                let newCost = currentCost + edge.weight
                if newCost < (dist[edge.toID] ?? .infinity) {
                    dist[edge.toID] = newCost
                    prev[edge.toID] = currentID
                    heap.push(HeapEntry(cost: newCost, id: edge.toID))
                }
            }
        }

        guard dist[toID] != nil else { return nil }

        var path: [GraphNode] = []
        var current: UUID? = toID
        while let nodeID = current {
            guard let node = nodes[nodeID] else { break }
            path.insert(node, at: 0)
            current = prev[nodeID]
        }

        guard path.first?.id == fromID else { return nil }
        return path
    }

    /// Heap entry for Dijkstra. Comparable by cost.
    private struct HeapEntry: Comparable {
        let cost: Double
        let id: UUID
        static func < (a: HeapEntry, b: HeapEntry) -> Bool { a.cost < b.cost }
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
