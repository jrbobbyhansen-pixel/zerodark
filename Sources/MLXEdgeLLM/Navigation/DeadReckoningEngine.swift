import Foundation
import SwiftUI
import CoreLocation
import ARKit

// MARK: - DeadReckoningEngine

class DeadReckoningEngine: ObservableObject {
    @Published var heading: CLLocationDirection = 0
    @Published var paceCount: Int = 0
    @Published var estimatedPosition: CLLocationCoordinate2D?
    @Published var confidenceRadius: CLLocationDistance = 0
    
    private var lastKnownPosition: CLLocationCoordinate2D?
    private var lastPaceTime: Date?
    private let paceDistance: CLLocationDistance = 0.762 // Approximate distance of one pace in meters
    private let confidenceRadiusGrowthRate: CLLocationDistance = 0.1 // Growth rate of confidence radius per second
    
    private var timer: Timer?
    
    init() {
        startTimer()
    }
    
    deinit {
        stopTimer()
    }
    
    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateConfidenceRadius()
        }
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    func updateHeading(_ newHeading: CLLocationDirection) {
        heading = newHeading
    }
    
    func recordPace() {
        paceCount += 1
        updateEstimatedPosition()
        lastPaceTime = Date()
    }
    
    private func updateEstimatedPosition() {
        guard let lastKnownPosition, let lastPaceTime else { return }
        
        let timeSinceLastPace = Date().timeIntervalSince(lastPaceTime)
        let distanceTraveled = paceCount * paceDistance
        let headingRadians = heading.degreesToRadians
        
        let newLatitude = lastKnownPosition.latitude + (distanceTraveled * cos(headingRadians) / CLLocationDistance(111320))
        let newLongitude = lastKnownPosition.longitude + (distanceTraveled * sin(headingRadians) / CLLocationDistance(111320) / cos(lastKnownPosition.latitude.degreesToRadians))
        
        estimatedPosition = CLLocationCoordinate2D(latitude: newLatitude, longitude: newLongitude)
    }
    
    private func updateConfidenceRadius() {
        confidenceRadius += confidenceRadiusGrowthRate
    }
}

// MARK: - Extensions

extension CLLocationDirection {
    var degreesToRadians: Double {
        return Double(self) * .pi / 180
    }
}

extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        let location1 = CLLocation(latitude: self.latitude, longitude: self.longitude)
        let location2 = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return location1.distance(from: location2)
    }
}