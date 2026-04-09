import Foundation
import SwiftUI
import CoreLocation

// MARK: - DEM Generator

class DemGenerator: ObservableObject {
    @Published var elevationModel: [[Double]] = []
    @Published var resolution: Double = 1.0
    @Published var interpolationMethod: InterpolationMethod = .linear
    @Published var gapFilling: Bool = true
    
    enum InterpolationMethod: String, CaseIterable {
        case linear
        case cubic
    }
    
    func generateDEM(from points: [CLLocationCoordinate2D], bounds: (CLLocationCoordinate2D, CLLocationCoordinate2D)) {
        let (minCoord, maxCoord) = bounds
        let width = Int((maxCoord.longitude - minCoord.longitude) / resolution)
        let height = Int((maxCoord.latitude - minCoord.latitude) / resolution)
        
        var grid = Array(repeating: Array(repeating: Double.nan, count: width), count: height)
        
        for point in points {
            let x = Int((point.longitude - minCoord.longitude) / resolution)
            let y = Int((point.latitude - minCoord.latitude) / resolution)
            if x >= 0 && x < width && y >= 0 && y < height {
                grid[y][x] = point.altitude
            }
        }
        
        if gapFilling {
            fillGaps(in: &grid)
        }
        
        interpolate(grid: &grid)
        
        elevationModel = grid
    }
    
    private func fillGaps(in grid: inout [[Double]]) {
        let width = grid[0].count
        let height = grid.count
        
        for y in 0..<height {
            for x in 0..<width {
                if Double.isNaN(grid[y][x]) {
                    var neighbors: [Double] = []
                    for dy in -1...1 {
                        for dx in -1...1 {
                            let nx = x + dx
                            let ny = y + dy
                            if nx >= 0 && nx < width && ny >= 0 && ny < height {
                                if !Double.isNaN(grid[ny][nx]) {
                                    neighbors.append(grid[ny][nx])
                                }
                            }
                        }
                    }
                    if !neighbors.isEmpty {
                        grid[y][x] = neighbors.average
                    }
                }
            }
        }
    }
    
    private func interpolate(grid: inout [[Double]]) {
        let width = grid[0].count
        let height = grid.count
        
        for y in 0..<height {
            for x in 0..<width {
                if Double.isNaN(grid[y][x]) {
                    var neighbors: [(Int, Int, Double)] = []
                    for dy in -1...1 {
                        for dx in -1...1 {
                            let nx = x + dx
                            let ny = y + dy
                            if nx >= 0 && nx < width && ny >= 0 && ny < height {
                                if !Double.isNaN(grid[ny][nx]) {
                                    neighbors.append((nx, ny, grid[ny][nx]))
                                }
                            }
                        }
                    }
                    if !neighbors.isEmpty {
                        switch interpolationMethod {
                        case .linear:
                            grid[y][x] = neighbors.map { $0.2 }.average
                        case .cubic:
                            grid[y][x] = cubicInterpolation(neighbors: neighbors, x: x, y: y)
                        }
                    }
                }
            }
        }
    }
    
    private func cubicInterpolation(neighbors: [(Int, Int, Double)], x: Int, y: Int) -> Double {
        // Implement cubic interpolation logic here
        return neighbors.map { $0.2 }.average
    }
}

extension Array where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0.0 }
        return reduce(0, +) / Double(count)
    }
}