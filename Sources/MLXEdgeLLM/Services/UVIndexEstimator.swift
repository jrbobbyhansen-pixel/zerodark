// UVIndexEstimator.swift — On-device UV-index estimate from solar elevation.
//
// Roadmap PR-C8 called for a UV index feature. ZeroDark is offline-first, so
// this estimator computes UV from solar elevation alone — no network weather
// call. The model is a simplified clear-sky approximation:
//
//     UV ≈ 12.5 × sin(solarElevation) × (1 − 0.5 × cloudCover)    [clamped ≥ 0]
//
// Where solarElevation is the sun's angle above the horizon in degrees.
// Cloud cover is a 0…1 input; callers that don't know it should pass 0.
// The 12.5 peak matches NOAA's midsummer clear-sky UV index ceiling.
//
// Output is a [0, 14] integer with standard WHO categories:
//
//     0–2   low
//     3–5   moderate
//     6–7   high
//     8–10  very high
//     11+   extreme
//
// This is deliberately NOT a substitute for a real UV-forecast service — it
// can't see aerosols, smoke plumes, or actual cloud state. Surfaces as a
// field hint, not a burn-time calculator.

import Foundation
import CoreLocation

public struct UVIndexEstimate: Equatable {
    public enum Category: String {
        case low, moderate, high, veryHigh, extreme

        public var displayName: String {
            switch self {
            case .low:      return "Low"
            case .moderate: return "Moderate"
            case .high:     return "High"
            case .veryHigh: return "Very High"
            case .extreme:  return "Extreme"
            }
        }

        public var burnRiskHint: String {
            switch self {
            case .low:      return "Minimal burn risk."
            case .moderate: return "Apply SPF 15+ for prolonged exposure."
            case .high:     return "SPF 30+ and a hat recommended."
            case .veryHigh: return "SPF 50+, hat, shade by 11–15 local."
            case .extreme:  return "Avoid direct sun; full cover required."
            }
        }
    }

    public let index: Int           // Rounded to the nearest integer.
    public let category: Category
    public let solarElevationDegrees: Double

    public init(index: Int, category: Category, solarElevationDegrees: Double) {
        self.index = index
        self.category = category
        self.solarElevationDegrees = solarElevationDegrees
    }
}

public enum UVIndexEstimator {
    /// Clear-sky UV estimate for a solar elevation (degrees above horizon).
    /// `cloudCover` is a 0…1 fraction (default 0 = clear sky).
    /// Elevations ≤ 0 produce UV = 0 (sun below horizon).
    public static func estimate(
        solarElevationDegrees elevation: Double,
        cloudCover: Double = 0
    ) -> UVIndexEstimate {
        let clampedCloud = max(0, min(1, cloudCover))
        let rawUV: Double
        if elevation <= 0 {
            rawUV = 0
        } else {
            let radians = elevation * .pi / 180.0
            rawUV = 12.5 * sin(radians) * (1 - 0.5 * clampedCloud)
        }
        let index = max(0, Int(rawUV.rounded()))
        return UVIndexEstimate(
            index: index,
            category: category(for: index),
            solarElevationDegrees: elevation
        )
    }

    /// Map a UV integer to the WHO category.
    public static func category(for index: Int) -> UVIndexEstimate.Category {
        switch index {
        case ..<3:   return .low
        case 3...5:  return .moderate
        case 6...7:  return .high
        case 8...10: return .veryHigh
        default:     return .extreme
        }
    }
}
