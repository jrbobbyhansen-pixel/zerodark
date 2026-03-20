// HybridAStarPlanner.swift — Hybrid A* path planner (Boeing pattern)

import MapKit
import Foundation

/// Hybrid A* node for search
private struct AStarNode {
    let cell: GridCell
    let heading: Double  // degrees
    let gCost: Double  // cost from start
    let hCost: Double  // heuristic to goal

    var fCost: Double { gCost + hCost }
}

/// Hybrid A* path planner
public class HybridAStarPlanner: PathPlannerProtocol {
    private let turningRadius: Double = 5.0  // meters (tight tactical turning)

    public init() {}

    /// Plan path using Hybrid A*
    public func plan(from start: NavPose, to goal: NavWaypoint, using map: GridMap) async -> NavPath? {
        let startCell = map.worldToGrid(start.coordinate, origin: start.coordinate)
        let goalCell = map.worldToGrid(goal.coordinate, origin: start.coordinate)

        guard map.isWalkable(startCell) && map.isWalkable(goalCell) else {
            return nil
        }

        // Priority queue: maintain sorted by fCost
        var openSet: [AStarNode] = [
            AStarNode(
                cell: startCell,
                heading: start.heading,
                gCost: 0,
                hCost: heuristic(from: startCell, to: goalCell)
            )
        ]
        var closedSet: Set<String> = []

        while !openSet.isEmpty {
            // Pop lowest fCost node
            let current = openSet.removeFirst()
            let key = "\(current.cell.x),\(current.cell.y),\(Int(current.heading))"

            if closedSet.contains(key) {
                continue
            }
            closedSet.insert(key)

            // Check if goal reached
            if current.cell.distance(to: goalCell) <= 2 {
                return reconstructPath(from: start, to: goal, using: map)
            }

            // Explore neighbors: 3 heading changes × 2 speeds
            for headingDelta in [-30.0, 0.0, 30.0] {
                for stepSize in [1, 2] {
                    let newHeading = (current.heading + headingDelta).truncatingRemainder(dividingBy: 360)
                    let radians = newHeading * .pi / 180.0

                    // Forward motion
                    let dx = Int(Double(stepSize) * cos(radians))
                    let dy = Int(Double(stepSize) * sin(radians))
                    let nextCell = GridCell(current.cell.x + dx, current.cell.y + dy)

                    guard map.isWalkable(nextCell) else {
                        continue
                    }

                    let headingCost = abs(headingDelta) * 0.1  // Slight penalty for turning
                    let newGCost = current.gCost + Double(stepSize) + headingCost
                    let newHCost = heuristic(from: nextCell, to: goalCell)

                    let neighbor = AStarNode(
                        cell: nextCell,
                        heading: newHeading,
                        gCost: newGCost,
                        hCost: newHCost
                    )

                    // Insert maintaining sorted order
                    let insertIdx = openSet.firstIndex(where: { $0.fCost > neighbor.fCost }) ?? openSet.count
                    openSet.insert(neighbor, at: insertIdx)
                }
            }
        }

        return nil  // No path found
    }

    /// Euclidean heuristic
    private func heuristic(from: GridCell, to: GridCell) -> Double {
        let dx = Double(to.x - from.x)
        let dy = Double(to.y - from.y)
        return sqrt(dx * dx + dy * dy)
    }

    /// Reconstruct path (simple waypoint-based)
    private func reconstructPath(from start: NavPose, to goal: NavWaypoint, using map: GridMap) -> NavPath {
        // Return simple direct path for now (full path extraction would require tracking parent nodes)
        let waypoints = [
            NavWaypoint(coordinate: start.coordinate, heading: start.heading),
            NavWaypoint(coordinate: goal.coordinate, heading: goal.heading, name: goal.name)
        ]
        return NavPath(waypoints: waypoints)
    }
}
