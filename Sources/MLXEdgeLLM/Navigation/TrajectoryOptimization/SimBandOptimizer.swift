// SimBandOptimizer.swift — Elastic band trajectory optimizer (Boeing SimBand pattern)

import MapKit
import Foundation

/// Trajectory optimizer using elastic band method
public class SimBandOptimizer: TrajectoryOptimizerProtocol {
    private let iterations: Int = 10
    private let attractionWeight: Double = 0.5
    private let repulsionWeight: Double = 0.3
    private let repulsionRadius: Double = 5.0  // meters

    public init() {}

    /// Optimize path using elastic band forces
    public func optimize(path: NavPath, around map: GridMap) -> NavPath {
        guard path.waypoints.count > 2 else {
            return path
        }

        var waypoints = path.waypoints
        let origin = waypoints[0].coordinate

        // Iterate: apply attraction + repulsion forces
        for _ in 0..<iterations {
            for i in 1..<waypoints.count - 1 {
                let current = waypoints[i].coordinate
                let previous = waypoints[i - 1].coordinate
                let next = waypoints[i + 1].coordinate

                // Attraction force (toward original path)
                let attraction = midpoint(between: previous, and: next)
                let attrForce = vectorToward(from: current, to: attraction, weight: attractionWeight)

                // Repulsion force (away from obstacles)
                let cellCurrent = map.worldToGrid(current, origin: origin)
                var repulsion = (lat: 0.0, lon: 0.0)

                for dx in -2...2 {
                    for dy in -2...2 {
                        let checkCell = GridCell(cellCurrent.x + dx, cellCurrent.y + dy)
                        if !map.isWalkable(checkCell) {
                            let obstacle = map.gridToWorld(checkCell, origin: origin)
                            let dist = current.distance(to: obstacle)
                            if dist < repulsionRadius {
                                let force = vectorAwayFrom(from: current, to: obstacle, weight: repulsionWeight)
                                repulsion.lat += force.lat
                                repulsion.lon += force.lon
                            }
                        }
                    }
                }

                // Apply combined force
                let newLat = current.latitude + attrForce.lat + repulsion.lat
                let newLon = current.longitude + attrForce.lon + repulsion.lon
                let newCoord = CLLocationCoordinate2D(latitude: newLat, longitude: newLon)

                // Ensure still walkable
                let newCell = map.worldToGrid(newCoord, origin: origin)
                if map.isWalkable(newCell) {
                    waypoints[i] = NavWaypoint(
                        coordinate: newCoord,
                        heading: waypoints[i].heading,
                        name: waypoints[i].name
                    )
                }
            }
        }

        return NavPath(waypoints: waypoints)
    }

    /// Midpoint between two coordinates
    private func midpoint(between a: CLLocationCoordinate2D, and b: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (a.latitude + b.latitude) / 2,
            longitude: (a.longitude + b.longitude) / 2
        )
    }

    /// Vector force toward target (operates in meters, returns degree offsets)
    private func vectorToward(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        weight: Double
    ) -> (lat: Double, lon: Double) {
        let mPerDegLat = 111320.0
        let mPerDegLon = 111320.0 * cos(from.latitude * .pi / 180.0)

        // Convert delta to meters
        let dNorth = (to.latitude - from.latitude) * mPerDegLat
        let dEast = (to.longitude - from.longitude) * mPerDegLon
        let distMeters = sqrt(dNorth * dNorth + dEast * dEast)

        guard distMeters > 0.01 else { return (lat: 0, lon: 0) }

        // Force magnitude in meters, clamped to 1m per iteration
        let forceMag = min(weight * distMeters * 0.1, 1.0)
        let forceN = (dNorth / distMeters) * forceMag
        let forceE = (dEast / distMeters) * forceMag

        // Convert back to degrees
        return (lat: forceN / mPerDegLat, lon: forceE / max(mPerDegLon, 1.0))
    }

    /// Vector force away from obstacle (operates in meters, returns degree offsets)
    private func vectorAwayFrom(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        weight: Double
    ) -> (lat: Double, lon: Double) {
        let mPerDegLat = 111320.0
        let mPerDegLon = 111320.0 * cos(from.latitude * .pi / 180.0)

        // Convert delta to meters (pointing away from obstacle)
        let dNorth = (from.latitude - to.latitude) * mPerDegLat
        let dEast = (from.longitude - to.longitude) * mPerDegLon
        let distMeters = sqrt(dNorth * dNorth + dEast * dEast)

        guard distMeters > 0.01 else { return (lat: 0, lon: 0) }

        // Inverse-square repulsion, clamped to 0.5m per iteration
        let forceMag = min(weight / max(distMeters * distMeters, 0.01), 0.5)
        let forceN = (dNorth / distMeters) * forceMag
        let forceE = (dEast / distMeters) * forceMag

        // Convert back to degrees
        return (lat: forceN / mPerDegLat, lon: forceE / max(mPerDegLon, 1.0))
    }
}
