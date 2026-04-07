import Foundation
import SwiftUI
import CoreLocation
import ARKit

// MARK: - BeaconMode

class BeaconMode: ObservableObject {
    @Published var isBeaconing: Bool = false
    @Published var beaconInterval: TimeInterval = 10.0
    @Published var lastBeacon: BeaconData?
    
    private var locationManager: CLLocationManager
    private var timer: Timer?
    
    init() {
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startBeaconing() {
        guard CLLocationManager.locationServicesEnabled() else { return }
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        
        timer = Timer.scheduledTimer(timeInterval: beaconInterval, target: self, selector: #selector(sendBeacon), userInfo: nil, repeats: true)
        isBeaconing = true
    }
    
    func stopBeaconing() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        
        timer?.invalidate()
        timer = nil
        isBeaconing = false
    }
    
    @objc private func sendBeacon() {
        guard let location = locationManager.location, let heading = locationManager.heading else { return }
        
        let beacon = BeaconData(
            timestamp: Date(),
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            heading: heading.magneticHeading,
            speed: location.speed,
            batteryLevel: UIDevice.current.batteryLevel
        )
        
        lastBeacon = beacon
        // Implement sending beacon logic here
        print("Beacon sent: \(beacon)")
    }
}

// MARK: - BeaconData

struct BeaconData: Codable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let heading: Double
    let speed: Double
    let batteryLevel: Float
}

// MARK: - CLLocationManagerDelegate

extension BeaconMode: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Handle location updates if needed
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Handle heading updates if needed
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}