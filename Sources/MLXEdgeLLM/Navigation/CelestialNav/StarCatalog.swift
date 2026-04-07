// StarCatalog.swift — Bright star catalog for celestial navigation (NASA COTS-Star-Tracker pattern)

import Foundation

/// Bright star entry
public struct StarEntry {
    public let name: String
    public let rightAscension: Double  // Degrees, 0-360
    public let declination: Double  // Degrees, -90 to +90
    public let magnitude: Double  // Brightness

    public init(name: String, ra: Double, dec: Double, magnitude: Double) {
        self.name = name
        self.rightAscension = ra
        self.declination = dec
        self.magnitude = magnitude
    }
}

/// Star catalog with 12 bright navigational stars
public class StarCatalog {
    public static let shared = StarCatalog()

    private let brightStars: [StarEntry] = [
        StarEntry(name: "Polaris", ra: 37.95, dec: 89.26, magnitude: 1.98),
        StarEntry(name: "Sirius", ra: 101.29, dec: -16.71, magnitude: -1.46),
        StarEntry(name: "Canopus", ra: 95.99, dec: -52.70, magnitude: -0.72),
        StarEntry(name: "Rigil Kentaurus", ra: 219.90, dec: -60.84, magnitude: -0.27),
        StarEntry(name: "Arcturus", ra: 213.92, dec: 19.18, magnitude: -0.04),
        StarEntry(name: "Vega", ra: 279.23, dec: 38.78, magnitude: 0.03),
        StarEntry(name: "Capella", ra: 79.17, dec: 45.99, magnitude: 0.08),
        StarEntry(name: "Rigel", ra: 78.63, dec: -8.20, magnitude: 0.13),
        StarEntry(name: "Procyon", ra: 114.83, dec: 5.23, magnitude: 0.38),
        StarEntry(name: "Achernar", ra: 24.43, dec: -57.27, magnitude: 0.45),
        StarEntry(name: "Aldebaran", ra: 68.98, dec: 16.51, magnitude: 0.87),
        StarEntry(name: "Antares", ra: 247.35, dec: -26.43, magnitude: 0.96)
    ]

    /// Get stars visible from observer's latitude and camera heading
    /// - Parameters:
    ///   - heading: camera/device heading in degrees (0-360)
    ///   - latitude: observer's geographic latitude in degrees (-90 to +90)
    /// - Returns: stars that are above the horizon and within ±60° of heading
    public func visibleStars(heading: Double, latitude: Double) -> [StarEntry] {
        brightStars.filter { star in
            // Heading filter: star RA within ±60° of device heading
            let headingDiff = abs(star.rightAscension - heading)
            let adjustedHeadingDiff = min(headingDiff, 360 - headingDiff)

            // Visibility check: star is above horizon at this latitude
            // A star is circumpolar (always visible) if dec > 90 - |lat|
            // A star never rises if dec < -(90 - |lat|)
            // Otherwise it rises and sets — approximate: visible if dec > lat - 90
            let minVisibleDec = latitude - 90.0

            return adjustedHeadingDiff <= 60 && star.declination > minVisibleDec
        }
    }
}
