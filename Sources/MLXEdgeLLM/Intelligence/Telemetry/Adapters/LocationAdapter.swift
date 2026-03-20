// LocationAdapter.swift — GPS telemetry adapter

import Foundation
import CoreLocation

class LocationTelemetryAdapter: BaseTelemetryAdapter, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()

    override init(objectType: TelemetryObjectType) {
        super.init(objectType: objectType)
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10.0  // Update every 10 meters
    }

    override func start() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }

    override func stop() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Emit JSON-serializable telemetry
        let data: [String: Double] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "altitude": location.altitude,
            "accuracy": location.horizontalAccuracy,
            "speed": location.speed >= 0 ? location.speed : 0
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: data),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            emit(.string(jsonString))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        emit(.double(newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silent fail; telemetry continues
    }
}
