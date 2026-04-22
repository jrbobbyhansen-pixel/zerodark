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

    /// Dead-band distance (meters). A violation for a given fence/type
    /// combination is suppressed until the device moves farther than
    /// this from the point at which it last fired. Prevents a boundary
    /// flap from spamming the operator when the GPS is noisy right on
    /// the edge of a fence.
    public var hysteresisMeters: Double = 10.0

    private let locationManager = CLLocationManager()
    private let geofenceManager = GeofenceManager.shared
    private var isRunning = false

    /// Keyed by "\(fenceID):\(violationType)". Value is the coordinate at
    /// which that key last fired. Cleared when monitoring stops.
    private var lastViolationAt: [String: CLLocationCoordinate2D] = [:]

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10.0
    }

    private func hysteresisKey(for v: GeofenceViolation) -> String {
        "\(v.geofenceID.uuidString):\(v.violationType)"
    }

    /// Decide which of the raw violations actually warrant surfacing to
    /// the operator. Public + nonisolated so it can be unit-tested
    /// without spinning up a real CLLocationManager.
    public func filterWithHysteresis(
        _ raw: [GeofenceViolation],
        here: CLLocationCoordinate2D
    ) -> [GeofenceViolation] {
        var surfaced: [GeofenceViolation] = []
        for v in raw {
            let key = hysteresisKey(for: v)
            if let last = lastViolationAt[key] {
                let d = CLLocation(latitude: last.latitude, longitude: last.longitude)
                    .distance(from: CLLocation(latitude: here.latitude, longitude: here.longitude))
                if d < hysteresisMeters { continue }
            }
            lastViolationAt[key] = here
            surfaced.append(v)
        }
        return surfaced
    }

    /// Clear the hysteresis memory. Call when the set of active
    /// geofences changes or when the operator explicitly wants a fresh
    /// round of alerts.
    public func resetHysteresis() {
        lastViolationAt.removeAll()
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
        resetHysteresis()
    }

    // MARK: - CLLocationManagerDelegate

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        let coordinate = CodableCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)

        // Check position, then filter through the hysteresis dead-band so
        // a GPS flap on the edge of a fence doesn't repeatedly fire.
        let raw = geofenceManager.checkPosition(coordinate)
        let violations = filterWithHysteresis(raw, here: location.coordinate)

        if !violations.isEmpty {
            lastViolations = violations

            // Trigger haptic feedback
            let notificationGenerator = UINotificationFeedbackGenerator()
            notificationGenerator.notificationOccurred(.warning)

            // Log violations and post to event bus
            for violation in violations {
                ZDLog.safety.notice("geofence_violation type:\(violation.violationType, privacy: .public) name:\(violation.geofenceName, privacy: .public)")
                AppState.shared.navEventBus.send(.geofenceKeyRotated(fenceId: violation.geofenceID))
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    }
}
