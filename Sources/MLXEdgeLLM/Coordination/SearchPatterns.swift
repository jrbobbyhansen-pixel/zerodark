import Foundation
import SwiftUI
import CoreLocation

// MARK: - Search Patterns

struct SearchPatternGenerator {
    func generateParallelTrack(start: CLLocationCoordinate2D, end: CLLocationCoordinate2D, numberOfTracks: Int) -> [CLLocationCoordinate2D] {
        var pattern: [CLLocationCoordinate2D] = []
        let distance = start.distance(from: end)
        let bearing = start.bearing(to: end)
        
        for i in 0..<numberOfTracks {
            let offset = CLLocation(latitude: start.latitude, longitude: start.longitude)
                .coordinate(atDistance: distance * Double(i) / Double(numberOfTracks), andBearing: bearing)
            pattern.append(offset)
        }
        
        return pattern
    }
    
    func generateExpandingSquare(center: CLLocationCoordinate2D, sideLength: CLLocationDistance) -> [CLLocationCoordinate2D] {
        var pattern: [CLLocationCoordinate2D] = []
        let halfSide = sideLength / 2.0
        
        // Top left
        pattern.append(center.coordinate(atDistance: halfSide, andBearing: 225))
        // Top right
        pattern.append(center.coordinate(atDistance: halfSide, andBearing: 315))
        // Bottom right
        pattern.append(center.coordinate(atDistance: halfSide, andBearing: 45))
        // Bottom left
        pattern.append(center.coordinate(atDistance: halfSide, andBearing: 135))
        
        return pattern
    }
    
    func generateSectorSearch(center: CLLocationCoordinate2D, radius: CLLocationDistance, numberOfSectors: Int) -> [CLLocationCoordinate2D] {
        var pattern: [CLLocationCoordinate2D] = []
        let sectorAngle = 360.0 / Double(numberOfSectors)
        
        for i in 0..<numberOfSectors {
            let bearing = sectorAngle * Double(i)
            pattern.append(center.coordinate(atDistance: radius, andBearing: bearing))
        }
        
        return pattern
    }
    
    func generateContourSearch(start: CLLocationCoordinate2D, end: CLLocationCoordinate2D, numberOfPoints: Int) -> [CLLocationCoordinate2D] {
        var pattern: [CLLocationCoordinate2D] = []
        let distance = start.distance(from: end)
        let bearing = start.bearing(to: end)
        
        for i in 0..<numberOfPoints {
            let offset = CLLocation(latitude: start.latitude, longitude: start.longitude)
                .coordinate(atDistance: distance * Double(i) / Double(numberOfPoints), andBearing: bearing)
            pattern.append(offset)
        }
        
        return pattern
    }
}

// MARK: - CLLocationCoordinate2D Extensions

extension CLLocationCoordinate2D {
    func coordinate(atDistance distance: CLLocationDistance, andBearing bearing: CLLocationDirection) -> CLLocationCoordinate2D {
        let latDist = distance * cos(bearing.toRadians())
        let lonDist = distance * sin(bearing.toRadians())
        
        let lat = self.latitude + (latDist / 111320)
        let lon = self.longitude + (lonDist / (111320 * cos(self.latitude.toRadians())))
        
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    func bearing(to location: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = self.latitude.toRadians()
        let lon1 = self.longitude.toRadians()
        let lat2 = location.latitude.toRadians()
        let lon2 = location.longitude.toRadians()
        
        let dLon = lon2 - lon1
        
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radiansBearing = atan2(y, x)
        
        return radiansBearing.toDegrees()
    }
}

// MARK: - Double Extensions

extension Double {
    func toRadians() -> Double {
        return self * .pi / 180
    }
    
    func toDegrees() -> Double {
        return self * 180 / .pi
    }
}

// MARK: - Sector Assignment

class SectorAssignment: ObservableObject {
    @Published var sectors: [String: CLLocationCoordinate2D] = [:]
    
    func assignSectors(pattern: [CLLocationCoordinate2D], teamMembers: [String]) {
        for (index, member) in teamMembers.enumerated() {
            if index < pattern.count {
                sectors[member] = pattern[index]
            }
        }
    }
}

// MARK: - Coverage Tracking

class CoverageTracker: ObservableObject {
    @Published var coveredAreas: [CLLocationCoordinate2D] = []
    
    func trackCoverage(location: CLLocationCoordinate2D) {
        coveredAreas.append(location)
    }
}