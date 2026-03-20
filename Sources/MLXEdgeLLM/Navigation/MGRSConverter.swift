// MGRSConverter.swift — Military Grid Reference System Coordinate Conversion

import Foundation
import CoreLocation

struct MGRSConverter {
    /// Convert WGS84 coordinate to MGRS string
    /// Example: 37.7749°N, 122.4194°W → "10S EG 37565 90587"
    static func toMGRS(coordinate: CLLocationCoordinate2D, precision: Int = 5) -> String {
        // 1. Convert lat/lon to UTM zone, band, easting, northing
        let (zone, band, easting, northing) = latLonToUTM(lat: coordinate.latitude, lon: coordinate.longitude)

        // 2. Identify 100km grid square letters
        let (e100k, n100k) = utm100kLetters(zone: zone, easting: easting, northing: northing)

        // 3. Format to precision (1=10km, 2=1km, 3=100m, 4=10m, 5=1m)
        let divisor = pow(10.0, Double(5 - precision))
        let e = Int(easting.truncatingRemainder(dividingBy: 100000) / divisor)
        let n = Int(northing.truncatingRemainder(dividingBy: 100000) / divisor)
        let fmt = "%0\(precision)d"

        return "\(zone)\(band) \(e100k)\(n100k) \(String(format: fmt, e)) \(String(format: fmt, n))"
    }

    // MARK: - UTM Conversion

    private static func latLonToUTM(lat: Double, lon: Double) -> (zone: Int, band: String, easting: Double, northing: Double) {
        let zone = Int((lon + 180) / 6) + 1

        // Latitude bands (C-X, excluding I and O)
        let bands = "CDEFGHJKLMNPQRSTUVWX"
        let bandIdx = Int((lat + 80) / 8)
        let band = String(bands[bands.index(bands.startIndex, offsetBy: min(bandIdx, bands.count - 1))])

        // WGS84 ellipsoid parameters
        let a = 6378137.0  // semi-major axis (meters)
        let f = 1.0 / 298.257223563  // flattening
        let b = a * (1 - f)
        let e2 = (a * a - b * b) / (a * a)  // first eccentricity squared
        let n = (a - b) / (a + b)
        let k0 = 0.9996  // scale factor
        let E0 = 500000.0  // false easting

        let latRad = lat * .pi / 180
        let lonRad = lon * .pi / 180
        let lonOriginRad = Double((zone - 1) * 6 - 180 + 3) * .pi / 180

        let N = a / sqrt(1 - e2 * sin(latRad) * sin(latRad))
        let T = tan(latRad) * tan(latRad)
        let C = e2 / (1 - e2) * cos(latRad) * cos(latRad)
        let A = cos(latRad) * (lonRad - lonOriginRad)

        let M = a * ((1 - e2/4 - 3*e2*e2/64) * latRad
                     - (3*e2/8 + 3*e2*e2/32) * sin(2*latRad)
                     + (15*e2*e2/256) * sin(4*latRad))

        let easting = k0 * N * (A + (1 - T + C) * A*A*A/6
                               + (5 - 18*T + T*T) * A*A*A*A*A/120) + E0
        var northing = k0 * (M + N * tan(latRad) * (A*A/2
                             + (5 - T + 9*C + 4*C*C) * A*A*A*A/24
                             + (61 - 58*T + T*T) * A*A*A*A*A*A/720))
        if lat < 0 { northing += 10_000_000 }

        return (zone, band, easting, northing)
    }

    private static func utm100kLetters(zone: Int, easting: Double, northing: Double) -> (String, String) {
        // MGRS 100km grid square letter sets
        let setNum = (zone - 1) % 6 + 1

        let eLetter: String
        let nLetter: String

        // Easting letters (8-letter patterns cycling)
        let eLetters = ["ABCDEFGH", "JKLMNPQR", "STUVWXYZ"]
        let eIndex = Int(easting / 100000) - 1
        if eIndex >= 0 && eIndex < 8 {
            let pattern = eLetters[(setNum - 1) % 3]
            eLetter = String(pattern[pattern.index(pattern.startIndex, offsetBy: eIndex)])
        } else {
            eLetter = "?"
        }

        // Northing letters (20-letter pattern, cycling)
        let nLettersN = "FGHJKLMNPQRSTUVABCDE"
        let nLettersS = "ABCDEFGHJKLMNPQRSTUV"
        let nPattern = northing >= 0 ? nLettersN : nLettersS
        let nIndex = Int(northing / 100000) % 20
        nLetter = String(nPattern[nPattern.index(nPattern.startIndex, offsetBy: nIndex)])

        return (eLetter, nLetter)
    }
}
