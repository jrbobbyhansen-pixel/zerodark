// GeofenceMonitor.swift — Continuous geofence monitoring with violation alerts

import Foundation
import CoreLocation
import UIKit

/// Geofence monitor singleton
@MainActor
public class GeofenceMonitor: NSObject, ObservableObject, CLLocationManagerDelegate {
    public static let shared = GeofenceMonitor()

    @Published public var isMonitoring: Bool = false
    @Published public var lastViolations: [GeofenceViolation] = []

    private let locationManager = CLLocationManager()
    private let geofenceManager = GeofenceManager.shared
    private var isRunning = false

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10.0
    }

    /// Start geofence monitoring
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        isMonitoring = true

        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    /// Stop geofence monitoring
    public func stop() {
        isRunning = false
        isMonitoring = false
        locationManager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        let coordinate = CodableCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)

        // Check position
        let violations = geofenceManager.checkPosition(coordinate)

        if !violations.isEmpty {
            lastViolations = violations

            // Trigger haptic feedback
            let notificationGenerator = UINotificationFeedbackGenerator()
            notificationGenerator.notificationOccurred(.warning)

            // Log violations
            for violation in violations {
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    }
}
