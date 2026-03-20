// TerrainMeshGenerator.swift — SRTM → SCN Mesh with Color-Ramped Terrain

import SceneKit
import MapKit

final class TerrainMeshGenerator {

    /// Sample elevation at a grid of points within the region
    static func elevationGrid(for region: MKCoordinateRegion, resolution: Int = 150) -> [[Double]] {
        let engine = TerrainEngine.shared
        var grid: [[Double]] = []

        let latStep = region.span.latitudeDelta / Double(resolution - 1)
        let lonStep = region.span.longitudeDelta / Double(resolution - 1)

        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2

        for row in 0..<resolution {
            var rowData: [Double] = []
            let lat = minLat + Double(row) * latStep

            for col in 0..<resolution {
                let lon = minLon + Double(col) * lonStep
                let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                let elev = engine.elevationAt(coordinate: coord) ?? 0
                rowData.append(elev)
            }
            grid.append(rowData)
        }

        return grid
    }

    /// Build 3D terrain mesh from elevation grid
    static func buildGeometry(grid: [[Double]], exaggeration: Float = 1.5) -> SCNGeometry {
        let rows = grid.count
        let cols = grid[0].count

        // Find elevation range for normalization
        let allElevations = grid.flatMap { $0 }
        let minElev = Float(allElevations.min() ?? 0)
        let maxElev = Float(allElevations.max() ?? 1000)
        let elevRange = max(maxElev - minElev, 1.0)  // Avoid division by zero

        // Generate vertices
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var texCoords: [CGPoint] = []

        let meshWidth: Float = 100.0
        let meshHeight: Float = 100.0

        for row in 0..<rows {
            for col in 0..<cols {
                let x = Float(col) / Float(cols - 1) * meshWidth - meshWidth / 2
                let z = Float(row) / Float(rows - 1) * meshHeight - meshHeight / 2
                let y = (Float(grid[row][col]) - minElev) / elevRange * 10.0 * exaggeration

                vertices.append(SCNVector3(x, y, z))
                texCoords.append(CGPoint(x: Double(col) / Double(cols - 1), y: Double(row) / Double(rows - 1)))
            }
        }

        // Calculate normals
        for row in 0..<rows {
            for col in 0..<cols {
                let normal = calcNormal(grid: grid, row: row, col: col, minElev: minElev, elevRange: elevRange, exaggeration: exaggeration)
                normals.append(normal)
            }
        }

        // Generate triangle indices
        var indices: [Int32] = []
        for row in 0..<(rows - 1) {
            for col in 0..<(cols - 1) {
                let topLeft = Int32(row * cols + col)
                let topRight = topLeft + 1
                let bottomLeft = Int32((row + 1) * cols + col)
                let bottomRight = bottomLeft + 1

                // Two triangles per quad
                indices.append(contentsOf: [topLeft, bottomLeft, topRight])
                indices.append(contentsOf: [topRight, bottomLeft, bottomRight])
            }
        }

        // Create geometry sources
        let vertexSource = SCNGeometrySource(vertices: vertices)
        let normalSource = SCNGeometrySource(normals: normals)
        let texCoordSource = SCNGeometrySource(textureCoordinates: texCoords)

        // Create geometry element
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)

        // Create geometry
        let geometry = SCNGeometry(sources: [vertexSource, normalSource, texCoordSource], elements: [element])

        // Apply terrain material with color-ramped texture and contour lines
        let material = SCNMaterial()
        material.diffuse.contents = generateTextureWithContours(grid: grid, minElev: minElev, maxElev: maxElev)
        material.isDoubleSided = true
        material.lightingModel = .physicallyBased  // Better lighting response
        material.roughness.contents = 0.8  // Matte terrain look
        geometry.materials = [material]

        return geometry
    }

    // MARK: - Private Helpers

    private static func calcNormal(grid: [[Double]], row: Int, col: Int, minElev: Float, elevRange: Float, exaggeration: Float) -> SCNVector3 {
        let rows = grid.count
        let cols = grid[0].count

        let left = col > 0 ? Float(grid[row][col - 1]) : Float(grid[row][col])
        let right = col < cols - 1 ? Float(grid[row][col + 1]) : Float(grid[row][col])
        let up = row > 0 ? Float(grid[row - 1][col]) : Float(grid[row][col])
        let down = row < rows - 1 ? Float(grid[row + 1][col]) : Float(grid[row][col])

        let dx = (right - left) / elevRange * 10.0 * exaggeration
        let dz = (down - up) / elevRange * 10.0 * exaggeration

        let normal = SCNVector3(-dx, 2.0, -dz)
        let length = sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z)

        return SCNVector3(normal.x / length, normal.y / length, normal.z / length)
    }

    private static func generateTexture(grid: [[Double]], minElev: Float, maxElev: Float) -> UIImage {
        let rows = grid.count
        let cols = grid[0].count
        let range = max(maxElev - minElev, 1.0)

        UIGraphicsBeginImageContext(CGSize(width: cols, height: rows))
        guard let context = UIGraphicsGetCurrentContext() else {
            return UIImage()
        }

        for row in 0..<rows {
            for col in 0..<cols {
                let normalized = (Float(grid[row][col]) - minElev) / range
                let color = terrainColor(normalized: normalized)
                context.setFillColor(color.cgColor)
                context.fill(CGRect(x: col, y: row, width: 1, height: 1))
            }
        }

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return image ?? UIImage()
    }

    private static func terrainColor(normalized: Float) -> UIColor {
        // High-contrast tactical terrain ramp optimized for night vision compatibility
        // Uses distinct color bands that are easy to distinguish
        
        switch normalized {
        case ..<0.05:
            // Deep valley / water - dark blue-green
            return UIColor(red: 0.05, green: 0.15, blue: 0.2, alpha: 1.0)
        case 0.05..<0.15:
            // Low elevation - dark green
            return UIColor(red: 0.1, green: 0.3, blue: 0.15, alpha: 1.0)
        case 0.15..<0.25:
            // Lower mid - forest green
            return UIColor(red: 0.15, green: 0.4, blue: 0.2, alpha: 1.0)
        case 0.25..<0.35:
            // Mid-low - bright green
            return UIColor(red: 0.3, green: 0.55, blue: 0.25, alpha: 1.0)
        case 0.35..<0.45:
            // Mid - yellow-green
            return UIColor(red: 0.5, green: 0.6, blue: 0.2, alpha: 1.0)
        case 0.45..<0.55:
            // Mid-upper - golden yellow
            return UIColor(red: 0.7, green: 0.6, blue: 0.2, alpha: 1.0)
        case 0.55..<0.65:
            // Upper-mid - orange tan
            return UIColor(red: 0.75, green: 0.5, blue: 0.25, alpha: 1.0)
        case 0.65..<0.75:
            // Upper - rust brown
            return UIColor(red: 0.6, green: 0.35, blue: 0.2, alpha: 1.0)
        case 0.75..<0.85:
            // High - dark brown
            return UIColor(red: 0.45, green: 0.25, blue: 0.15, alpha: 1.0)
        case 0.85..<0.95:
            // Very high - gray rock
            return UIColor(red: 0.55, green: 0.5, blue: 0.5, alpha: 1.0)
        default:
            // Peak - bright white with slight blue tint (snow)
            return UIColor(red: 0.95, green: 0.97, blue: 1.0, alpha: 1.0)
        }
    }
    
    /// Generate texture with contour lines for better elevation reading
    private static func generateTextureWithContours(grid: [[Double]], minElev: Float, maxElev: Float) -> UIImage {
        let rows = grid.count
        let cols = grid[0].count
        let range = max(maxElev - minElev, 1.0)
        
        // Calculate contour interval (roughly 10 contour lines)
        let contourInterval = Double(range) / 10.0
        
        UIGraphicsBeginImageContext(CGSize(width: cols, height: rows))
        guard let context = UIGraphicsGetCurrentContext() else {
            return UIImage()
        }

        for row in 0..<rows {
            for col in 0..<cols {
                let elev = grid[row][col]
                let normalized = (Float(elev) - minElev) / range
                var color = terrainColor(normalized: normalized)
                
                // Add contour lines - darken pixels near contour elevations
                let contourRemainder = elev.truncatingRemainder(dividingBy: contourInterval)
                let distanceToContour = min(contourRemainder, contourInterval - contourRemainder)
                
                // If close to a contour line, darken the color
                if distanceToContour < contourInterval * 0.08 {
                    color = color.darkened(by: 0.4)
                }
                
                context.setFillColor(color.cgColor)
                context.fill(CGRect(x: col, y: row, width: 1, height: 1))
            }
        }

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return image ?? UIImage()
    }
}

// MARK: - UIColor Extension for Darkening

private extension UIColor {
    func darkened(by factor: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(
            red: max(r - factor, 0),
            green: max(g - factor, 0),
            blue: max(b - factor, 0),
            alpha: a
        )
    }
}
