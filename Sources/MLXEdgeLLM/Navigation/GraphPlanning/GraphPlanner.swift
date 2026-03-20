// GraphPlanner.swift — Dijkstra's algorithm for graph planning (Boeing pattern)

import Foundation

/// Graph-based planner using Dijkstra's algorithm
@MainActor
public class GraphPlanner {
    public init() {}

    /// Plan route through graph from start to goal node ID
    public func plan(
        from startID: UUID,
        to goalID: UUID,
        graph: NavigationGraph
    ) -> [GraphNode]? {
        // Dijkstra's algorithm
        var distances: [UUID: Double] = [:]
        var previous: [UUID: UUID?] = [:]
        var unvisited = Set(graph.nodes.keys)

        // Initialize
        for nodeID in graph.nodes.keys {
            distances[nodeID] = nodeID == startID ? 0 : Double.infinity
            previous[nodeID] = nil
        }

        while !unvisited.isEmpty {
            // Find unvisited node with min distance
            guard let current = unvisited.min(by: { (distances[$0] ?? .infinity) < (distances[$1] ?? .infinity) }) else {
                break
            }

            unvisited.remove(current)

            if distances[current] == .infinity {
                break  // Unreachable
            }

            if current == goalID {
                return reconstructPath(from: startID, to: goalID, previous: previous, graph: graph)
            }

            // Relax edges from current
            for edge in graph.outgoingEdges(from: current) {
                let neighbor = edge.toID
                if unvisited.contains(neighbor) {
                    let newDist = (distances[current] ?? .infinity) + edge.weight
                    if newDist < (distances[neighbor] ?? .infinity) {
                        distances[neighbor] = newDist
                        previous[neighbor] = current
                    }
                }
            }
        }

        return nil  // No path found
    }

    /// Reconstruct path from start to goal
    private func reconstructPath(
        from startID: UUID,
        to goalID: UUID,
        previous: [UUID: UUID?],
        graph: NavigationGraph
    ) -> [GraphNode]? {
        var path: [GraphNode] = []
        var current: UUID? = goalID

        while let nodeID = current {
            if let node = graph.nodes[nodeID] {
                path.insert(node, at: 0)
            }

            if nodeID == startID {
                break
            }

            current = previous[nodeID] ?? nil
        }

        return path.isEmpty ? nil : path
    }
}
