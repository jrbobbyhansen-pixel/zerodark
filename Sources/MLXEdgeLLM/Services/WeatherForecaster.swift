// WeatherForecaster.swift — Barometric pressure trend, hydration, sun/moon timing, pressure altitude
// v6.1: Real CMAltimeter baro, hydration calc, sunrise/sunset/twilight

import Foundation
import CoreLocation
import CoreMotion

enum ActivityLevel: String, CaseIterable {
    case rest = "Rest"
    case light = "Light"
    case moderate = "Moderate"
    case heavy = "Heavy"
    case extreme = "Extreme"
}

final class WeatherForecaster: ObservableObject {
    static let shared = WeatherForecaster()
    @Published private(set) var barometricPressureTrend: BarometricPressureTrend = .stable
    @Published private(set) var stormWarning: Bool = false
    @Published private(set) var pressureAltitudeMeters: Double = 0
    @Published private(set) var currentPressureHPa: Double = 1013.25
    @Published private(set) var relativeAltitudeMeters: Double = 0
    @Published private(set) var recommendedHydrationMl: Double = 0
    @Published private(set) var sunrise: Date?
    @Published private(set) var sunset: Date?
    @Published private(set) var civilTwilight: Date?

    private var pressureReadings: [(timestamp: Date, pressure: Double)] = []
    private let maxReadings = 60  // 1 hour at 1-minute intervals
    private let altimeter = CMAltimeter()
    private var currentLocation: CLLocationCoordinate2D?
    private var lastEphemerisUpdate: Date?

    init() {
        startBaroMonitoring()
    }

    // MARK: - Barometric Monitoring (real CMAltimeter)

    private func startBaroMonitoring() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }

        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
            guard let data, error == nil else { return }
            let pressureKPa = data.pressure.doubleValue
            let pressureHPa = pressureKPa * 10.0

            self?.currentPressureHPa = pressureHPa
            self?.relativeAltitudeMeters = data.relativeAltitude.doubleValue
            self?.pressureAltitudeMeters = self?.pressureAltitude(pressureHPa: pressureHPa) ?? 0
            self?.addPressureReading(pressureHPa)
        }
    }

    func stopBaroMonitoring() {
        altimeter.stopRelativeAltitudeUpdates()
    }

    func addPressureReading(_ pressure: Double) {
        pressureReadings.append((timestamp: Date(), pressure: pressure))
        if pressureReadings.count > maxReadings {
            pressureReadings.removeFirst()
        }
        analyzePressureTrend()
    }

    private func analyzePressureTrend() {
        guard pressureReadings.count >= 3 else {
            barometricPressureTrend = .stable
            stormWarning = false
            return
        }

        // Use readings from last 30 minutes for trend
        let cutoff = Date().addingTimeInterval(-1800)
        let recentReadings = pressureReadings.filter { $0.timestamp > cutoff }
        guard let first = recentReadings.first, let last = recentReadings.last else {
            barometricPressureTrend = .stable
            return
        }

        let trend = last.pressure - first.pressure
        if trend < -1.0 {  // >1 hPa drop in 30min = rapid drop
            barometricPressureTrend = .rapidDrop
            stormWarning = true
        } else if trend > 1.0 {
            barometricPressureTrend = .rapidRise
            stormWarning = false
        } else {
            barometricPressureTrend = .stable
            stormWarning = false
        }
    }

    // MARK: - Pressure Altitude

    /// Standard atmosphere barometric altitude
    /// QNH: sea-level pressure setting (default 1013.25 hPa)
    func pressureAltitude(pressureHPa: Double, qnhHPa: Double = 1013.25) -> Double {
        return 44330.0 * (1.0 - pow(pressureHPa / qnhHPa, 0.1903))
    }

    // MARK: - Hydration Calculator

    /// Calculate recommended hydration based on conditions and activity
    /// Returns milliliters per hour
    func calculateHydration(tempC: Double, activityLevel: ActivityLevel, durationHours: Double) -> Double {
        // Base rate: 250 mL/hr at rest in temperate conditions
        let baseRate: Double = 250.0

        // Temperature multiplier (exponential increase above 25C)
        let tempMultiplier: Double
        if tempC < 15 {
            tempMultiplier = 0.8
        } else if tempC < 25 {
            tempMultiplier = 1.0
        } else if tempC < 35 {
            tempMultiplier = 1.0 + (tempC - 25) * 0.1  // +10% per degree above 25
        } else {
            tempMultiplier = 2.0 + (tempC - 35) * 0.15  // aggressive above 35C
        }

        // Activity multiplier
        let activityMultiplier: Double
        switch activityLevel {
        case .rest: activityMultiplier = 1.0
        case .light: activityMultiplier = 1.5
        case .moderate: activityMultiplier = 2.0
        case .heavy: activityMultiplier = 3.0
        case .extreme: activityMultiplier = 4.0
        }

        let mlPerHour = baseRate * tempMultiplier * activityMultiplier
        recommendedHydrationMl = mlPerHour * durationHours
        return recommendedHydrationMl
    }

    // MARK: - Sun/Moon Timing

    /// Update location and refresh sunrise/sunset/twilight times
    func updateLocation(_ coordinate: CLLocationCoordinate2D) {
        currentLocation = coordinate
        refreshSunTimes()
    }

    private func refreshSunTimes() {
        guard let loc = currentLocation else { return }

        // Only recalculate once per hour
        if let lastUpdate = lastEphemerisUpdate,
           Date().timeIntervalSince(lastUpdate) < 3600 {
            return
        }

        Task { @MainActor in
            let celestial = CelestialNavigator.shared
            let times = celestial.sunTimes(date: Date(), latitude: loc.latitude, longitude: loc.longitude)
            self.sunrise = times.sunrise
            self.sunset = times.sunset
            self.civilTwilight = times.civilTwilight
            self.lastEphemerisUpdate = Date()
        }
    }
}

enum BarometricPressureTrend {
    case stable
    case rapidRise
    case rapidDrop
}
