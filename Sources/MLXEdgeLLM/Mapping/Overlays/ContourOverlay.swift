// ContourOverlay.swift — Topographic Contour Lines from SRTM Data

import MapKit
import UIKit

/// Draws topographic contour lines on the map using SRTM elevation data
final class ContourOverlay: NSObject, MKOverlay {
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect
    let region: MKCoordinateRegion
    
    /// Contour interval in meters (default 50m = ~164ft)
    let contourInterval: Double
    
    /// Generated contour lines
    private(set) var contourLines: [ContourLine] = []
    
    init(region: MKCoordinateRegion, contourInterval: Double = 50.0) {
        self.region = region
        self.coordinate = region.center
        self.contourInterval = contourInterval
        
        // Calculate bounding rect
        let topLeft = MKMapPoint(CLLocationCoordinate2D(
            latitude: region.center.latitude + region.span.latitudeDelta / 2,
            longitude: region.center.longitude - region.span.longitudeDelta / 2
        ))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(
            latitude: region.center.latitude - region.span.latitudeDelta / 2,
            longitude: region.center.longitude + region.span.longitudeDelta / 2
        ))
        self.boundingMapRect = MKMapRect(
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        )
        
        super.init()
    }
    
    /// Load pre-computed contour lines (from ContourGeneratorEngine)
    func load(_ lines: [ContourLine]) {
        contourLines = lines
    }

    /// Generate contour lines from elevation data (call on background thread)
    func generateContours(resolution: Int = 50) {
        let engine = TerrainEngine.shared
        
        // Sample elevation grid
        var grid: [[Double]] = []
        let latStep = region.span.latitudeDelta / Double(resolution)
        let lonStep = region.span.longitudeDelta / Double(resolution)
        
        let startLat = region.center.latitude - region.span.latitudeDelta / 2
        let startLon = region.center.longitude - region.span.longitudeDelta / 2
        
        for row in 0..<resolution {
            var rowData: [Double] = []
            for col in 0..<resolution {
                let coord = CLLocationCoordinate2D(
                    latitude: startLat + Double(row) * latStep,
                    longitude: startLon + Double(col) * lonStep
                )
                let elev = engine.elevationAt(coordinate: coord) ?? 0
                rowData.append(elev)
            }
            grid.append(rowData)
        }
        
        // Find elevation range
        let allElevs = grid.flatMap { $0 }
        guard let minElev = allElevs.min(), let maxElev = allElevs.max() else { return }
        
        // Generate contour levels
        let startLevel = floor(minElev / contourInterval) * contourInterval
        let endLevel = ceil(maxElev / contourInterval) * contourInterval
        
        var lines: [ContourLine] = []
        
        var level = startLevel
        while level <= endLevel {
            let isMajor = Int(level) % Int(contourInterval * 5) == 0 // Every 5th line is major
            let segments = marchingSquares(grid: grid, level: level, resolution: resolution)
            
            for segment in segments {
                lines.append(ContourLine(
                    elevation: level,
                    points: segment,
                    isMajor: isMajor
                ))
            }
            
            level += contourInterval
        }
        
        self.contourLines = lines
    }
    
    /// Marching squares algorithm to extract contour segments
    private func marchingSquares(grid: [[Double]], level: Double, resolution: Int) -> [[(lat: Double, lon: Double)]] {
        var segments: [[(lat: Double, lon: Double)]] = []
        
        let latStep = region.span.latitudeDelta / Double(resolution)
        let lonStep = region.span.longitudeDelta / Double(resolution)
        let startLat = region.center.latitude - region.span.latitudeDelta / 2
        let startLon = region.center.longitude - region.span.longitudeDelta / 2
        
        for row in 0..<(resolution - 1) {
            for col in 0..<(resolution - 1) {
                // Get corner values
                let tl = grid[row + 1][col]
                let tr = grid[row + 1][col + 1]
                let br = grid[row][col + 1]
                let bl = grid[row][col]
                
                // Calculate case (0-15)
                var caseIndex = 0
                if tl >= level { caseIndex |= 8 }
                if tr >= level { caseIndex |= 4 }
                if br >= level { caseIndex |= 2 }
                if bl >= level { caseIndex |= 1 }
                
                // Skip if all same
                if caseIndex == 0 || caseIndex == 15 { continue }
                
                // Calculate cell bounds
                let cellLat = startLat + Double(row) * latStep
                let cellLon = startLon + Double(col) * lonStep
                
                // Interpolate edge crossings
                func lerp(_ v1: Double, _ v2: Double) -> Double {
                    guard v2 != v1 else { return 0.5 }
                    return (level - v1) / (v2 - v1)
                }
                
                let topT = lerp(tl, tr)
                let rightT = lerp(tr, br)
                let bottomT = lerp(bl, br)
                let leftT = lerp(tl, bl)
                
                let top = (lat: cellLat + latStep, lon: cellLon + topT * lonStep)
                let right = (lat: cellLat + (1 - rightT) * latStep, lon: cellLon + lonStep)
                let bottom = (lat: cellLat, lon: cellLon + bottomT * lonStep)
                let left = (lat: cellLat + (1 - leftT) * latStep, lon: cellLon)
                
                // Generate segments based on case
                switch caseIndex {
                case 1, 14: segments.append([left, bottom])
                case 2, 13: segments.append([bottom, right])
                case 3, 12: segments.append([left, right])
                case 4, 11: segments.append([top, right])
                case 5:
                    segments.append([left, top])
                    segments.append([bottom, right])
                case 6, 9: segments.append([top, bottom])
                case 7, 8: segments.append([left, top])
                case 10:
                    segments.append([top, right])
                    segments.append([left, bottom])
                default: break
                }
            }
        }
        
        return segments
    }
}

/// A single contour line at a specific elevation
struct ContourLine {
    let elevation: Double
    let points: [(lat: Double, lon: Double)]
    let isMajor: Bool
    
    var elevationFeet: Int {
        Int(elevation * 3.28084)
    }
}

// MARK: - Contour Overlay Renderer

final class ContourOverlayRenderer: MKOverlayRenderer {
    private let contourOverlay: ContourOverlay
    
    /// Colors for contour lines
    private let majorColor = UIColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 0.8)  // Brown
    private let minorColor = UIColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 0.4)  // Light brown
    
    init(overlay: ContourOverlay) {
        self.contourOverlay = overlay
        super.init(overlay: overlay)
    }
    
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        // Don't draw if too zoomed out
        let zoomLevel = log2(1 / zoomScale)
        guard zoomLevel > 10 else { return } // Only show when zoomed in enough
        
        for line in contourOverlay.contourLines {
            guard line.points.count >= 2 else { continue }
            
            // Set style based on major/minor
            if line.isMajor {
                context.setStrokeColor(majorColor.cgColor)
                context.setLineWidth(2.0 / zoomScale)
            } else {
                context.setStrokeColor(minorColor.cgColor)
                context.setLineWidth(1.0 / zoomScale)
            }
            
            // Draw the line
            context.beginPath()
            
            for (index, point) in line.points.enumerated() {
                let coord = CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
                let mapPoint = MKMapPoint(coord)
                let cgPoint = self.point(for: mapPoint)
                
                if index == 0 {
                    context.move(to: cgPoint)
                } else {
                    context.addLine(to: cgPoint)
                }
            }
            
            context.strokePath()
        }
    }
}
