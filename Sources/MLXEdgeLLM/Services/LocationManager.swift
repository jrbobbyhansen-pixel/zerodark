// LocationManager.swift — Persistent location tracking singleton
import Foundation
import CoreLocation

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()

    @Published var currentLocation: CLLocationCoordinate2D?
    
    /// Returns current location or last known, never hardcoded cities
    var locationOrDefault: CLLocationCoordinate2D {
        currentLocation ?? lastKnownLocation ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }
    
    /// Persisted last known location (survives app restart)
    private(set) var lastKnownLocation: CLLocationCoordinate2D? {
        get {
            guard let lat = UserDefaults.standard.object(forKey: "lastKnownLat") as? Double,
                  let lon = UserDefaults.standard.object(forKey: "lastKnownLon") as? Double else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        set {
            if let coord = newValue {
                UserDefaults.standard.set(coord.latitude, forKey: "lastKnownLat")
                UserDefaults.standard.set(coord.longitude, forKey: "lastKnownLon")
            }
        }
    }

    private let manager = CLLocationManager()

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            LocationManager.shared.currentLocation = loc.coordinate
            LocationManager.shared.lastKnownLocation = loc.coordinate
        }
    }
}
