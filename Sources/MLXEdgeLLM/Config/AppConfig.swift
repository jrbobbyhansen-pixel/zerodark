// AppConfig.swift — Runtime configuration constants
// Set these before production deployment

import Foundation
import UIKit

enum AppConfig {
    // TAK Server
    static let defaultTAKPort: UInt16 = 8087
    static let defaultTAKTLSPort: UInt16 = 8089

    // Third-party API keys (nil = use public demo tier with rate limits)
    static var nasaApiKey: String? = nil        // https://api.nasa.gov/
    static var waqiApiKey: String? = nil        // https://waqi.info/

    // Device identity
    static var deviceCallsign: String {
        UIDevice.current.name
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    // OSM tile server
    static let osmTileURLTemplate = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
}
