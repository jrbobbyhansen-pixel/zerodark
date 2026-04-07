import Foundation
import SwiftUI
import CoreLocation

// MARK: - MoonPhaseService

final class MoonPhaseService: ObservableObject {
    @Published private(set) var moonPhase: MoonPhase?
    @Published private(set) var moonrise: Date?
    @Published private(set) var moonset: Date?
    @Published private(set) var illumination: Double = 0.0
    @Published private(set) var moonAngle: Double = 0.0

    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?

    init() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func updateMoonPhase() {
        guard let location = currentLocation else { return }
        let moonPhaseInfo = calculateMoonPhase(for: location.coordinate)
        moonPhase = moonPhaseInfo.phase
        moonrise = moonPhaseInfo.moonrise
        moonset = moonPhaseInfo.moonset
        illumination = moonPhaseInfo.illumination
        moonAngle = moonPhaseInfo.angle
    }

    private func calculateMoonPhase(for coordinate: CLLocationCoordinate2D) -> MoonPhaseInfo {
        // Placeholder for actual moon phase calculation logic
        // This should be replaced with actual astronomical calculations
        let phase = MoonPhase.new
        let moonrise = Date()
        let moonset = Date()
        let illumination = 0.5
        let angle = 45.0
        return MoonPhaseInfo(phase: phase, moonrise: moonrise, moonset: moonset, illumination: illumination, angle: angle)
    }
}

// MARK: - CLLocationManagerDelegate

extension MoonPhaseService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        updateMoonPhase()
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}

// MARK: - MoonPhase

enum MoonPhase: String, Codable {
    case new = "New Moon"
    case waxingCrescent = "Waxing Crescent"
    case firstQuarter = "First Quarter"
    case waxingGibbous = "Waxing Gibbous"
    case full = "Full Moon"
    case waningGibbous = "Waning Gibbous"
    case lastQuarter = "Last Quarter"
    case waningCrescent = "Waning Crescent"
}

// MARK: - MoonPhaseInfo

struct MoonPhaseInfo: Codable {
    let phase: MoonPhase
    let moonrise: Date
    let moonset: Date
    let illumination: Double
    let angle: Double
}