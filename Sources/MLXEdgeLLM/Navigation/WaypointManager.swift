import Foundation
import SwiftUI
import CoreLocation

// MARK: - Waypoint Types
enum WaypointType: String, Codable {
    case hazard
    case cache
    case objective
}

// MARK: - Waypoint Coordinates
struct WaypointCoordinates: Codable {
    var latitude: Double
    var longitude: Double
    
    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
    
    init?(mgrs: String) {
        guard let coordinate = MGRSConverter.toCLLocationCoordinate2D(mgrs) else { return nil }
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
    
    init?(utm: String) {
        guard let coordinate = UTMConverter.toCLLocationCoordinate2D(utm) else { return nil }
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
    
    var mgrs: String {
        MGRSConverter.fromCLLocationCoordinate2D(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
    }
    
    var utm: String {
        UTMConverter.fromCLLocationCoordinate2D(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
    }
}

// MARK: - Waypoint
struct NavWaypoint: Identifiable, Codable {
    let id = UUID()
    var name: String
    var coordinates: WaypointCoordinates
    var type: WaypointType
    var description: String?
}

// MARK: - WaypointManager
class WaypointManager: ObservableObject {
    @Published var waypoints: [NavWaypoint] = []
    
    func addNavWaypoint(_ waypoint: NavWaypoint) {
        waypoints.append(waypoint)
    }
    
    func updateNavWaypoint(_ waypoint: NavWaypoint) {
        if let index = waypoints.firstIndex(where: { $0.id == waypoint.id }) {
            waypoints[index] = waypoint
        }
    }
    
    func deleteNavWaypoint(_ waypoint: NavWaypoint) {
        waypoints.removeAll { $0.id == waypoint.id }
    }
    
    func importGPX(from url: URL) async throws {
        let data = try Data(contentsOf: url)
        let waypoints = try GPXParser.parse(data: data)
        self.waypoints.append(contentsOf: waypoints)
    }
    
    func exportGPX(to url: URL) async throws {
        let data = try GPXParser.generate(from: waypoints)
        try data.write(to: url)
    }
}

// MARK: - GPXParser — Real GPX 1.1 XML Parsing

class GPXParser: NSObject, XMLParserDelegate {

    static func parse(data: Data) throws -> [NavWaypoint] {
        let parser = GPXParser()
        return parser.parseGPX(data: data)
    }

    static func generate(from waypoints: [NavWaypoint]) throws -> Data {
        var gpx = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        gpx += "<gpx version=\"1.1\" creator=\"ZeroDark\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n"
        for wp in waypoints {
            gpx += "  <wpt lat=\"\(wp.coordinates.latitude)\" lon=\"\(wp.coordinates.longitude)\">\n"
            gpx += "    <name>\(escapeXML(wp.name))</name>\n"
            if let desc = wp.description { gpx += "    <desc>\(escapeXML(desc))</desc>\n" }
            gpx += "    <type>\(wp.type.rawValue)</type>\n"
            gpx += "  </wpt>\n"
        }
        gpx += "</gpx>\n"
        return gpx.data(using: .utf8) ?? Data()
    }

    private static func escapeXML(_ str: String) -> String {
        str.replacingOccurrences(of: "&", with: "&amp;")
           .replacingOccurrences(of: "<", with: "&lt;")
           .replacingOccurrences(of: ">", with: "&gt;")
    }

    // Instance parsing
    private var waypoints: [NavWaypoint] = []
    private var currentElement = ""
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentName = ""
    private var currentDesc = ""
    private var currentType = ""
    private var inWpt = false

    private func parseGPX(data: Data) -> [NavWaypoint] {
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = self
        xmlParser.parse()
        return waypoints
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "wpt" || elementName == "rtept" || elementName == "trkpt" {
            inWpt = true
            currentLat = Double(attributes["lat"] ?? "")
            currentLon = Double(attributes["lon"] ?? "")
            currentName = ""
            currentDesc = ""
            currentType = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inWpt else { return }
        switch currentElement {
        case "name": currentName += string.trimmingCharacters(in: .whitespacesAndNewlines)
        case "desc": currentDesc += string.trimmingCharacters(in: .whitespacesAndNewlines)
        case "type": currentType += string.trimmingCharacters(in: .whitespacesAndNewlines)
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if (elementName == "wpt" || elementName == "rtept" || elementName == "trkpt") && inWpt {
            if let lat = currentLat, let lon = currentLon {
                let type = WaypointType(rawValue: currentType) ?? .objective
                waypoints.append(NavWaypoint(
                    name: currentName.isEmpty ? "WP\(waypoints.count + 1)" : currentName,
                    coordinates: WaypointCoordinates(latitude: lat, longitude: lon),
                    type: type,
                    description: currentDesc.isEmpty ? nil : currentDesc
                ))
            }
            inWpt = false
        }
        currentElement = ""
    }
}

// MARK: - UTMConverter — WGS84 Transverse Mercator

struct UTMConverter {
    private static let a = 6_378_137.0        // WGS84 semi-major axis
    private static let f = 1.0 / 298.257223563 // WGS84 flattening
    private static let k0 = 0.9996            // UTM scale factor
    private static let e = sqrt(2 * f - f * f)
    private static let e2 = e * e

    static func fromCLLocationCoordinate2D(_ coord: CLLocationCoordinate2D) -> String {
        let lat = coord.latitude
        let lon = coord.longitude
        let zone = Int((lon + 180) / 6) + 1
        let lonOrigin = Double((zone - 1) * 6 - 180 + 3)

        let latRad = lat * .pi / 180
        let lonRad = (lon - lonOrigin) * .pi / 180

        let N = a / sqrt(1 - e2 * sin(latRad) * sin(latRad))
        let T = tan(latRad) * tan(latRad)
        let C = (e2 / (1 - e2)) * cos(latRad) * cos(latRad)
        let A = cos(latRad) * lonRad

        let M = a * ((1 - e2/4 - 3*e2*e2/64 - 5*e2*e2*e2/256) * latRad
                    - (3*e2/8 + 3*e2*e2/32 + 45*e2*e2*e2/1024) * sin(2*latRad)
                    + (15*e2*e2/256 + 45*e2*e2*e2/1024) * sin(4*latRad)
                    - (35*e2*e2*e2/3072) * sin(6*latRad))

        var easting = k0 * N * (A + (1-T+C)*A*A*A/6 + (5-18*T+T*T+72*C-58*(e2/(1-e2)))*A*A*A*A*A/120) + 500000
        var northing = k0 * (M + N*tan(latRad)*(A*A/2 + (5-T+9*C+4*C*C)*A*A*A*A/24 + (61-58*T+T*T+600*C-330*(e2/(1-e2)))*A*A*A*A*A*A/720))
        if lat < 0 { northing += 10_000_000 }

        let band = lat >= 0 ? "N" : "S"
        return String(format: "%d%@ %.0f %.0f", zone, band, easting, northing)
    }

    static func toCLLocationCoordinate2D(_ utm: String) -> CLLocationCoordinate2D? {
        // Parse "14N 500000 3500000" format
        let parts = utm.components(separatedBy: " ")
        guard parts.count >= 3 else { return nil }
        let zoneStr = parts[0]
        guard let easting = Double(parts[1]), let northing = Double(parts[2]) else { return nil }

        let zoneDigits = zoneStr.filter(\.isNumber)
        let bandLetter = zoneStr.filter(\.isLetter)
        guard let zone = Int(zoneDigits) else { return nil }
        let isNorth = bandLetter.uppercased() != "S"

        let lonOrigin = Double((zone - 1) * 6 - 180 + 3) * .pi / 180
        let e1 = (1 - sqrt(1 - e2)) / (1 + sqrt(1 - e2))

        var adjustedNorthing = northing
        if !isNorth { adjustedNorthing -= 10_000_000 }

        let M = adjustedNorthing / k0
        let mu = M / (a * (1 - e2/4 - 3*e2*e2/64 - 5*e2*e2*e2/256))
        let phi1 = mu + (3*e1/2 - 27*e1*e1*e1/32)*sin(2*mu) + (21*e1*e1/16 - 55*e1*e1*e1*e1/32)*sin(4*mu)
                    + (151*e1*e1*e1/96)*sin(6*mu) + (1097*e1*e1*e1*e1/512)*sin(8*mu)

        let N1 = a / sqrt(1 - e2 * sin(phi1) * sin(phi1))
        let T1 = tan(phi1) * tan(phi1)
        let C1 = (e2 / (1 - e2)) * cos(phi1) * cos(phi1)
        let R1 = a * (1 - e2) / pow(1 - e2 * sin(phi1) * sin(phi1), 1.5)
        let D = (easting - 500000) / (N1 * k0)

        let ep2 = e2 / (1 - e2)
        let latTerm1 = D * D / 2
        let latTerm2 = (5 + 3*T1 + 10*C1 - 4*C1*C1 - 9*ep2) * pow(D, 4) / 24
        let latTerm3 = (61 + 90*T1 + 298*C1 + 45*T1*T1 - 252*ep2 - 3*C1*C1) * pow(D, 6) / 720
        let lat = phi1 - (N1 * tan(phi1) / R1) * (latTerm1 - latTerm2 + latTerm3)

        let lonTerm1 = D
        let lonTerm2 = (1 + 2*T1 + C1) * pow(D, 3) / 6
        let lonTerm3 = (5 - 2*C1 + 28*T1 - 3*C1*C1 + 8*ep2 + 24*T1*T1) * pow(D, 5) / 120
        let lon = (lonTerm1 - lonTerm2 + lonTerm3) / cos(phi1)

        return CLLocationCoordinate2D(latitude: lat * 180 / .pi, longitude: (lonOrigin + lon) * 180 / .pi)
    }
}

// MARK: - MGRSConverter (delegates to Navigation/MGRSConverter for forward, UTM for reverse)
// Note: The primary MGRSConverter.toMGRS() is in Navigation/MGRSConverter.swift
// This version provides the reverse (MGRS string → coordinate) which the other file lacks

extension MGRSConverter {
    /// Forward: coordinate → MGRS string (delegates to existing toMGRS)
    static func fromCLLocationCoordinate2D(_ coordinate: CLLocationCoordinate2D) -> String {
        toMGRS(coordinate: coordinate, precision: 5)
    }

    /// Reverse: MGRS string → coordinate
    static func toCLLocationCoordinate2D(_ mgrs: String) -> CLLocationCoordinate2D? {
        parseMGRS(mgrs)
    }

    /// Parse MGRS string → lat/lon
    /// MGRS format: "14RPU1234567890" or "14R PU 12345 67890"
    static func parseMGRS(_ mgrs: String) -> CLLocationCoordinate2D? {
        let cleaned = mgrs.replacingOccurrences(of: " ", with: "").uppercased()
        guard cleaned.count >= 5 else { return nil }

        // Extract zone number (1-2 digits) + band letter
        var idx = cleaned.startIndex
        var zoneStr = ""
        while idx < cleaned.endIndex && cleaned[idx].isNumber {
            zoneStr.append(cleaned[idx])
            idx = cleaned.index(after: idx)
        }
        guard let zone = Int(zoneStr), zone >= 1, zone <= 60 else { return nil }
        guard idx < cleaned.endIndex else { return nil }
        let band = cleaned[idx]
        idx = cleaned.index(after: idx)

        // 100km square ID (2 letters)
        guard cleaned.distance(from: idx, to: cleaned.endIndex) >= 2 else { return nil }
        idx = cleaned.index(idx, offsetBy: 2)

        // Remaining digits: split in half for easting/northing
        let digits = String(cleaned[idx...])
        guard digits.count >= 2, digits.count % 2 == 0 else { return nil }
        let half = digits.count / 2
        let eastingStr = String(digits.prefix(half))
        let northingStr = String(digits.suffix(half))

        // Scale to meters based on precision
        let scale = pow(10.0, Double(5 - half))
        guard let eastingVal = Double(eastingStr), let northingVal = Double(northingStr) else { return nil }
        let easting = eastingVal * scale + 500000  // Approximate — center of zone
        let northing = northingVal * scale

        let isNorth = band >= "N"
        let utmString = "\(zone)\(isNorth ? "N" : "S") \(Int(easting)) \(Int(northing))"
        return UTMConverter.toCLLocationCoordinate2D(utmString)
    }
}