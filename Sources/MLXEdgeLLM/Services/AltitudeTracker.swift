import Foundation
import CoreLocation
import SwiftUI

class AltitudeTracker: ObservableObject {
    @Published private(set) var currentAltitude: CLLocationDistance = 0
    @Published private(set) var timeAtAltitudeBands: [AltitudeBand: TimeInterval] = [:]
    @Published private(set) var acclimatizationSchedule: [String] = []
    @Published private(set) var amsRiskAssessment: String = ""
    @Published private(set) var ascentRateWarnings: [String] = []

    private var locationManager: CLLocationManager
    private var lastAltitudeUpdate: Date?
    private var ascentRateThreshold: CLLocationDistance = 100 // meters per minute

    init() {
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func updateAltitude(_ altitude: CLLocationDistance) {
        let currentTime = Date()
        let timeSinceLastUpdate = lastAltitudeUpdate?.timeIntervalSince(currentTime) ?? 0

        if timeSinceLastUpdate > 0 {
            let ascentRate = (altitude - currentAltitude) / timeSinceLastUpdate
            if ascentRate > ascentRateThreshold {
                ascentRateWarnings.append("Warning: High ascent rate detected (\(ascentRate) m/min)")
            }
        }

        currentAltitude = altitude
        updateAltitudeBands()
        updateAcclimatizationSchedule()
        updateAMSAssessment()
        lastAltitudeUpdate = currentTime
    }

    private func updateAltitudeBands() {
        let band = AltitudeBand(for: currentAltitude)
        timeAtAltitudeBands[band, default: 0] += 1
    }

    private func updateAcclimatizationSchedule() {
        acclimatizationSchedule = AltitudeAcclimatizationSchedule.recommendations(for: timeAtAltitudeBands)
    }

    private func updateAMSAssessment() {
        amsRiskAssessment = AMSRiskAssessment.assessRisk(for: currentAltitude, timeAtAltitudeBands: timeAtAltitudeBands)
    }
}

extension AltitudeTracker: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        updateAltitude(location.altitude)
    }
}

enum AltitudeBand {
    case lowAltitude
    case moderateAltitude
    case highAltitude
    case veryHighAltitude

    init(for altitude: CLLocationDistance) {
        switch altitude {
        case 0...2000:
            self = .lowAltitude
        case 2001...5000:
            self = .moderateAltitude
        case 5001...8000:
            self = .highAltitude
        default:
            self = .veryHighAltitude
        }
    }
}

struct AltitudeAcclimatizationSchedule {
    static func recommendations(for timeAtAltitudeBands: [AltitudeBand: TimeInterval]) -> [String] {
        var recommendations: [String] = []

        if let lowAltitudeTime = timeAtAltitudeBands[.lowAltitude], lowAltitudeTime > 0 {
            recommendations.append("Continue gradual ascent.")
        }

        if let moderateAltitudeTime = timeAtAltitudeBands[.moderateAltitude], moderateAltitudeTime > 0 {
            recommendations.append("Monitor for AMS symptoms.")
        }

        if let highAltitudeTime = timeAtAltitudeBands[.highAltitude], highAltitudeTime > 0 {
            recommendations.append("Consider descending if symptoms appear.")
        }

        if let veryHighAltitudeTime = timeAtAltitudeBands[.veryHighAltitude], veryHighAltitudeTime > 0 {
            recommendations.append("Immediate descent recommended.")
        }

        return recommendations
    }
}

struct AMSRiskAssessment {
    static func assessRisk(for altitude: CLLocationDistance, timeAtAltitudeBands: [AltitudeBand: TimeInterval]) -> String {
        if altitude > 5000 {
            return "High risk of AMS. Monitor closely."
        } else if altitude > 2000 {
            return "Moderate risk of AMS. Stay hydrated and acclimatize slowly."
        } else {
            return "Low risk of AMS."
        }
    }
}