import Foundation
import SwiftUI
import CoreLocation

// MARK: - TemperatureLogger

final class TemperatureLogger: ObservableObject {
    @Published private(set) var temperatureReadings: [TemperatureReading] = []
    @Published private(set) var predictedLow: Double?
    @Published private(set) var coldInjuryRisk: ColdInjuryRisk = .none

    private let locationManager = CLLocationManager()
    private var lastManualInput: Date?

    init() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func logTemperature(_ temperature: Double, isManual: Bool = false) {
        let reading = TemperatureReading(temperature: temperature, date: Date(), isManual: isManual)
        temperatureReadings.append(reading)
        updatePredictedLow()
        assessColdInjuryRisk()
        if isManual {
            lastManualInput = Date()
        }
    }

    private func updatePredictedLow() {
        guard let latestReading = temperatureReadings.last else { return }
        // Simple prediction logic: assume the lowest temperature in the last 24 hours
        let twentyFourHoursAgo = Calendar.current.date(byAdding: .hour, value: -24, to: Date()) ?? Date()
        let recentReadings = temperatureReadings.filter { $0.date > twentyFourHoursAgo }
        predictedLow = recentReadings.min(by: { $0.temperature < $1.temperature })?.temperature
    }

    private func assessColdInjuryRisk() {
        guard let latestReading = temperatureReadings.last else { return }
        coldInjuryRisk = ColdInjuryRisk(forTemperature: latestReading.temperature)
    }
}

// MARK: - TemperatureReading

struct TemperatureReading: Identifiable {
    let id = UUID()
    let temperature: Double
    let date: Date
    let isManual: Bool
}

// MARK: - ColdInjuryRisk

enum ColdInjuryRisk: String, Identifiable {
    case none = "None"
    case mild = "Mild"
    case moderate = "Moderate"
    case severe = "Severe"

    var id: String { self.rawValue }

    init(forTemperature temperature: Double) {
        switch temperature {
        case ...0:
            self = .severe
        case 0...5:
            self = .moderate
        case 5...10:
            self = .mild
        default:
            self = .none
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension TemperatureLogger: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // Fetch temperature from location if needed
        // For simplicity, we assume manual input for temperature
    }
}