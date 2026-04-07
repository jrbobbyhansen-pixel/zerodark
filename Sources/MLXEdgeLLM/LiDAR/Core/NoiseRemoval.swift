import Foundation
import ARKit

// MARK: - Noise Removal Filter

struct PointCloud {
    var points: [SCNVector3]
}

class NoiseRemovalFilter {
    
    // MARK: - Statistical Outlier Removal
    
    func statisticalOutlierRemoval(pointCloud: PointCloud, meanK: Int, stdDevMulThresh: Float) -> PointCloud {
        guard meanK > 0 else { return pointCloud }
        
        var filteredPoints: [SCNVector3] = []
        let kNearestNeighbors = KNearestNeighbors(points: pointCloud.points)
        
        for point in pointCloud.points {
            let neighbors = kNearestNeighbors.findNearestNeighbors(of: point, k: meanK)
            let distances = neighbors.map { distance(from: point, to: $0) }
            let meanDistance = distances.reduce(0, +) / Float(distances.count)
            let stdDev = sqrt(distances.reduce(0) { $0 + pow($1 - meanDistance, 2) } / Float(distances.count))
            
            if distance(from: point, to: meanDistance) < stdDev * stdDevMulThresh {
                filteredPoints.append(point)
            }
        }
        
        return PointCloud(points: filteredPoints)
    }
    
    // MARK: - Radius Outlier Removal
    
    func radiusOutlierRemoval(pointCloud: PointCloud, radius: Float, minNeighbors: Int) -> PointCloud {
        guard radius > 0, minNeighbors > 0 else { return pointCloud }
        
        var filteredPoints: [SCNVector3] = []
        let kNearestNeighbors = KNearestNeighbors(points: pointCloud.points)
        
        for point in pointCloud.points {
            let neighbors = kNearestNeighbors.findNearestNeighbors(of: point, radius: radius)
            if neighbors.count >= minNeighbors {
                filteredPoints.append(point)
            }
        }
        
        return PointCloud(points: filteredPoints)
    }
    
    // MARK: - Helper Methods
    
    private func distance(from point1: SCNVector3, to point2: SCNVector3) -> Float {
        return sqrt(pow(point1.x - point2.x, 2) + pow(point1.y - point2.y, 2) + pow(point1.z - point2.z, 2))
    }
}

// MARK: - K-Nearest Neighbors

class KNearestNeighbors {
    private let points: [SCNVector3]
    
    init(points: [SCNVector3]) {
        self.points = points
    }
    
    func findNearestNeighbors(of point: SCNVector3, k: Int) -> [SCNVector3] {
        let sortedPoints = points.sorted { distance(from: point, to: $0) < distance(from: point, to: $1) }
        return Array(sortedPoints.prefix(k))
    }
    
    func findNearestNeighbors(of point: SCNVector3, radius: Float) -> [SCNVector3] {
        return points.filter { distance(from: point, to: $0) <= radius }
    }
}