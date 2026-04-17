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
        get {
            UserDefaults.standard.string(forKey: "deviceCallsign") ??
            UIDevice.current.name
                .replacingOccurrences(of: " ", with: "-")
                .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "deviceCallsign")
        }
    }

    // Tile server — OpenFreeMap (free, no API key, App Store-safe, allows offline use)
    // Raster PNG tiles: https://tile.openfreemap.org/{z}/{x}/{y}.png
    // Fallback: OpenStreetMap (https://tile.openstreetmap.org/{z}/{x}/{y}.png — ToS restricts bulk use)
    static let osmTileURLTemplate = "https://tile.openfreemap.org/{z}/{x}/{y}.png"
}
