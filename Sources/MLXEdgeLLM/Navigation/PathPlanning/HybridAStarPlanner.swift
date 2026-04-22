// HybridAStarPlanner.swift — Hybrid A* path planner (Boeing pattern)

import MapKit
import Foundation

/// Hybrid A* node for search
private struct AStarNode {
    let cell: GridCell
    let heading: Double  // degrees
    let gCost: Double  // cost from start
    let hCost: Double  // heuristic to goal
    let parentKey: String?  // key of parent node for path reconstruction

    var fCost: Double { gCost + hCost }
}

/// Hybrid A* path planner
public class HybridAStarPlanner: PathPlannerProtocol {
    private let turningRadius: Double = 5.0  // meters (tight tactical turning)

    /// Hard iteration cap. On a 10 000-cell map with 6 neighbor branches
    /// per expansion, the frontier can grow to tens of thousands before
    /// finding an unreachable goal. We abort with `nil` rather than
    /// letting the planner run away. 50 000 expansions is ~50 MB of peak
    /// frontier memory in the worst case.
    public var maxIterations: Int = 50_000

    public init() {}

    /// Plan path using Hybrid A*
    public func plan(from start: NavPose, to goal: NavWaypoint, using map: GridMap) async -> NavPath? {
        let startCell = map.worldToGrid(start.coordinate, origin: start.coordinate)
        let goalCell = map.worldToGrid(goal.coordinate, origin: start.coordinate)

        guard map.isWalkable(startCell) && map.isWalkable(goalCell) else {
            return nil
        }

        let startKey = "\(startCell.x),\(startCell.y),\(Int(start.heading))"

        // Priority queue: maintain sorted by fCost
        var openSet: [AStarNode] = [
            AStarNode(
                cell: startCell,
                heading: start.heading,
                gCost: 0,
                hCost: heuristic(from: startCell, to: goalCell),
                parentKey: nil
            )
        ]
        var closedSet: Set<String> = []
        var cameFrom: [String: AStarNode] = [:]

        // Store start node
        cameFrom[startKey] = openSet[0]

        var iterations = 0
        while !openSet.isEmpty {
            iterations += 1
            if iterations > maxIterations {
                ZDLog.navigation.error("HybridAStar aborted at iteration cap \(self.maxIterations, privacy: .public); goal may be unreachable")
                return nil
            }

            // Pop lowest fCost node
            let current = openSet.removeFirst()
            let key = "\(current.cell.x),\(current.cell.y),\(Int(current.heading))"

            if closedSet.contains(key) {
                continue
            }
            closedSet.insert(key)
            cameFrom[key] = current

            // Check if goal reached
            if current.cell.distance(to: goalCell) <= 2 {
                return reconstructPath(
                    goalKey: key,
                    cameFrom: cameFrom,
                    origin: start.coordinate,
                    goal: goal,
                    map: map
                )
            }

            // Explore neighbors: 3 heading changes × 2 speeds
            for headingDelta in [-30.0, 0.0, 30.0] {
                for stepSize in [1, 2] {
                    let newHeading = (current.heading + headingDelta + 360).truncatingRemainder(dividingBy: 360)
                    let radians = newHeading * .pi / 180.0

                    // Forward motion
                    let dx = Int(Double(stepSize) * cos(radians))
                    let dy = Int(Double(stepSize) * sin(radians))
                    let nextCell = GridCell(current.cell.x + dx, current.cell.y + dy)

                    guard map.isWalkable(nextCell) else {
                        continue
                    }

                    let neighborKey = "\(nextCell.x),\(nextCell.y),\(Int(newHeading))"
                    guard !closedSet.contains(neighborKey) else { continue }

                    let headingCost = abs(headingDelta) * 0.1  // Slight penalty for turning
                    let newGCost = current.gCost + Double(stepSize) + headingCost
                    let newHCost = heuristic(from: nextCell, to: goalCell)

                    // Skip if we already have a cheaper path to this node
                    if let existing = cameFrom[neighborKey], existing.gCost <= newGCost {
                        continue
                    }

                    let neighbor = AStarNode(
                        cell: nextCell,
                        heading: newHeading,
                        gCost: newGCost,
                        hCost: newHCost,
                        parentKey: key
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

    /// Reconstruct path by walking parent pointers from goal back to start
    private func reconstructPath(
        goalKey: String,
        cameFrom: [String: AStarNode],
        origin: CLLocationCoordinate2D,
        goal: NavWaypoint,
        map: GridMap
    ) -> NavPath {
        var cells: [GridCell] = []
        var currentKey: String? = goalKey

        // Walk back from goal to start via parent pointers
        while let key = currentKey, let node = cameFrom[key] {
            cells.append(node.cell)
            currentKey = node.parentKey
        }

        cells.reverse()

        // Simplify: skip cells that are collinear (reduce waypoint count)
        var simplified: [GridCell] = []
        for (i, cell) in cells.enumerated() {
            if i == 0 || i == cells.count - 1 {
                simplified.append(cell)
            } else {
                let prev = cells[i - 1]
                let next = cells[i + 1]
                let dx1 = cell.x - prev.x
                let dy1 = cell.y - prev.y
                let dx2 = next.x - cell.x
                let dy2 = next.y - cell.y
                // Keep if direction changes
                if dx1 != dx2 || dy1 != dy2 {
                    simplified.append(cell)
                }
            }
        }

        // Convert grid cells to world coordinates as NavWaypoints
        var waypoints: [NavWaypoint] = simplified.map { cell in
            let coord = map.gridToWorld(cell, origin: origin)
            return NavWaypoint(coordinate: coord)
        }

        // Ensure final waypoint matches the actual goal coordinate and metadata
        if !waypoints.isEmpty {
            waypoints[waypoints.count - 1] = NavWaypoint(
                coordinate: goal.coordinate,
                heading: goal.heading,
                name: goal.name
            )
        }

        return NavPath(waypoints: waypoints)
    }
}
