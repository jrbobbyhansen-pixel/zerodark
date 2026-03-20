// GridMap.swift — Occupancy grid for path planning (Boeing Hybrid A* pattern)

import MapKit
import Foundation

/// Single grid cell
public struct GridCell: Equatable {
    public let x: Int
    public let y: Int

    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }

    /// Manhattan distance to another cell
    public func distance(to other: GridCell) -> Int {
        abs(x - other.x) + abs(y - other.y)
    }
}

/// Occupancy grid map for planning
public class GridMap {
    public let width: Int
    public let height: Int
    public let resolution: Double  // meters per cell

    private var occupancyGrid: [[Bool]]

    public init(width: Int, height: Int, resolution: Double = 0.5) {
        self.width = width
        self.height = height
        self.resolution = resolution
        self.occupancyGrid = Array(repeating: Array(repeating: false, count: width), count: height)
    }

    /// Get cell occupancy
    public func cellAt(_ cell: GridCell) -> Bool? {
        guard cell.x >= 0 && cell.x < width && cell.y >= 0 && cell.y < height else {
            return nil
        }
        return occupancyGrid[cell.y][cell.x]
    }

    /// Mark cell as occupied
    public func markOccupied(_ cell: GridCell) {
        guard cell.x >= 0 && cell.x < width && cell.y >= 0 && cell.y < height else {
            return
        }
        occupancyGrid[cell.y][cell.x] = true
    }

    /// Mark region as occupied (circle)
    public func markOccupied(_ center: GridCell, radius: Int) {
        let radiusSq = radius * radius

        for dy in -radius...radius {
            for dx in -radius...radius {
                if dx * dx + dy * dy <= radiusSq {
                    let x = center.x + dx
                    let y = center.y + dy
                    if x >= 0 && x < width && y >= 0 && y < height {
                        occupancyGrid[y][x] = true
                    }
                }
            }
        }
    }

    /// Convert world coordinate to grid cell
    public func worldToGrid(_ coord: CLLocationCoordinate2D, origin: CLLocationCoordinate2D) -> GridCell {
        let dx = (coord.longitude - origin.longitude) * 111000 / resolution  // ~111km per degree
        let dy = (coord.latitude - origin.latitude) * 111000 / resolution
        return GridCell(Int(round(dx)), Int(round(dy)))
    }

    /// Convert grid cell to world coordinate
    public func gridToWorld(_ cell: GridCell, origin: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let dlon = Double(cell.x) * resolution / 111000
        let dlat = Double(cell.y) * resolution / 111000
        return CLLocationCoordinate2D(
            latitude: origin.latitude + dlat,
            longitude: origin.longitude + dlon
        )
    }

    /// Check if cell is walkable (not occupied and within bounds)
    public func isWalkable(_ cell: GridCell) -> Bool {
        guard cell.x >= 0 && cell.x < width && cell.y >= 0 && cell.y < height else {
            return false
        }
        return !occupancyGrid[cell.y][cell.x]
    }

    /// Get neighbors (4-connectivity)
    public func neighbors(of cell: GridCell) -> [GridCell] {
        [
            GridCell(cell.x + 1, cell.y),
            GridCell(cell.x - 1, cell.y),
            GridCell(cell.x, cell.y + 1),
            GridCell(cell.x, cell.y - 1)
        ].filter { isWalkable($0) }
    }
}
