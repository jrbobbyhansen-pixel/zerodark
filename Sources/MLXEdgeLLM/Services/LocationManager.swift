// LocationManager.swift — Persistent location tracking singleton
import Foundation
import CoreLocation
import Security

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()

    @Published var currentLocation: CLLocationCoordinate2D?

    /// Returns current location or last known, never hardcoded cities
    var locationOrDefault: CLLocationCoordinate2D {
        currentLocation ?? lastKnownLocation ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }

    // MARK: - Keychain-backed last known location
    // Stored in Keychain with AfterFirstUnlockThisDeviceOnly — not included in backups,
    // not accessible pre-unlock, and excluded from iCloud sync.

    private static let keychainService = "com.zerodark.location"
    private static let keychainAccount = "lastKnownCoord"

    /// Persisted last known location (survives app restart, stored in Keychain)
    private(set) var lastKnownLocation: CLLocationCoordinate2D? {
        get {
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: Self.keychainService,
                kSecAttrAccount: Self.keychainAccount,
                kSecReturnData: true,
                kSecMatchLimit: kSecMatchLimitOne
            ]
            var result: AnyObject?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                  let data = result as? Data,
                  data.count == 16 else { return nil }
            let lat = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: Double.self) }
            let lon = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: Double.self) }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        set {
            guard let coord = newValue else { return }
            var data = Data(count: 16)
            data.withUnsafeMutableBytes {
                $0.storeBytes(of: coord.latitude,  toByteOffset: 0, as: Double.self)
                $0.storeBytes(of: coord.longitude, toByteOffset: 8, as: Double.self)
            }
            let attrs: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: Self.keychainService,
                kSecAttrAccount: Self.keychainAccount,
                kSecValueData: data,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            SecItemDelete(attrs as CFDictionary)
            SecItemAdd(attrs as CFDictionary, nil)
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

    /// Nudge the Core Location manager to produce a fresh position fix.
    /// Called by RuntimeSafetyMonitor when `positionKnown` violates.
    func forcePositionUpdate() {
        manager.stopUpdatingLocation()
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            LocationManager.shared.currentLocation = loc.coordinate
            LocationManager.shared.lastKnownLocation = loc.coordinate
        }
    }
}
