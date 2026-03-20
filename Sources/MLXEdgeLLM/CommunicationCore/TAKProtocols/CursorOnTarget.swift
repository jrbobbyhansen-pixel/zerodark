// CursorOnTarget.swift — Cursor-on-Target (CoT) XML Protocol Encoder/Decoder
// Implements ATAK-CIV CoT XML schema for TAK interoperability

import Foundation

// MARK: - CoT Event Type Hierarchy

enum CoTEventType: String {
    // Atom (physical entity)
    case friendlyGround = "a-f-G"           // Friendly ground unit
    case friendlyAir = "a-f-A"              // Friendly air unit
    case friendly = "a-f"                   // Generic friendly

    case hostileGround = "a-h-G"            // Hostile ground unit
    case hostileAir = "a-h-A"               // Hostile air unit
    case hostile = "a-h"                    // Generic hostile

    case unknownGround = "a-u-G"            // Unknown ground unit
    case unknown = "a-u"                    // Generic unknown

    case neutral = "a-n-G"                  // Neutral

    // Bits (file/data)
    case marker = "b-m-p-s-p-i"             // Spot/point of interest (for SOS/markers)
    case chat = "b-f-t-c"                   // Chat message

    // Tasking/control
    case ping = "t-x-c-t"                   // Connectivity ping
    case pong = "t-x-c-t-r"                 // Connectivity pong/reply
    case takControl = "t-x-takp-v"          // TAK protocol support

    // Emergency
    case sos = "b-a-o-tbl-sos"              // Emergency/SOS marker (9-1-1)

    // Custom
    case custom = "custom"

    var description: String {
        switch self {
        case .friendlyGround: return "Friendly Ground Unit"
        case .hostile: return "Hostile"
        case .sos: return "Emergency/SOS"
        case .marker: return "Point of Interest"
        default: return self.rawValue
        }
    }

    static func from(string: String) -> CoTEventType {
        return CoTEventType(rawValue: string) ?? .custom
    }
}

// MARK: - CoT Event Structures

struct CoTEvent: Codable {
    let uid: String                         // Unique event identifier (UUID format recommended)
    let type: String                        // CoT type string (e.g., "a-f-G")
    let how: String                         // How obtained: "m-g" (machine-generated), "h-g-i-g-o" (human)
    let time: Date                          // Event send time (UTC)
    let start: Date                         // Event validity start (UTC)
    let stale: Date                         // Event expiry/stale time (UTC)

    // Point location (required)
    var lat: Double                         // Latitude decimal degrees WGS-84
    var lon: Double                         // Longitude decimal degrees WGS-84
    var hae: Double                         // Height above ellipsoid (meters); 9999999 = unknown
    var ce: Double                          // Circular error (meters); 9999999 = unknown
    var le: Double                          // Linear error (meters); 9999999 = unknown

    // Detail sub-elements (optional)
    var detail: CoTDetail?

    init(uid: String = UUID().uuidString,
         type: String = "a-f-G",
         how: String = "m-g",
         time: Date = Date(),
         start: Date = Date(),
         stale: Date = Date(timeIntervalSinceNow: 300), // 5 minutes default
         lat: Double = 0,
         lon: Double = 0,
         hae: Double = 9999999,
         ce: Double = 9999999,
         le: Double = 9999999,
         detail: CoTDetail? = nil) {
        self.uid = uid
        self.type = type
        self.how = how
        self.time = time
        self.start = start
        self.stale = stale
        self.lat = lat
        self.lon = lon
        self.hae = hae
        self.ce = ce
        self.le = le
        self.detail = detail
    }
}

struct CoTDetail: Codable {
    var contact: CoTContact?
    var status: CoTStatus?
    var takv: CoTTakv?
    var track: CoTTrack?
    var group: CoTGroup?
    var xmlDetail: String?                  // Remaining unmapped XML

    init(contact: CoTContact? = nil,
         status: CoTStatus? = nil,
         takv: CoTTakv? = nil,
         track: CoTTrack? = nil,
         group: CoTGroup? = nil,
         xmlDetail: String? = nil) {
        self.contact = contact
        self.status = status
        self.takv = takv
        self.track = track
        self.group = group
        self.xmlDetail = xmlDetail
    }
}

struct CoTContact: Codable {
    let callsign: String
    let endpoint: String?                   // Format: "host:port:proto" (optional)
}

struct CoTStatus: Codable {
    let battery: Int                        // Battery percentage (0-100)
}

struct CoTTakv: Codable {
    let device: String
    let platform: String
    let os: String
    let version: String
}

struct CoTTrack: Codable {
    let speed: Double                       // meters per second
    let course: Double                      // degrees (0-360)
}

struct CoTGroup: Codable {
    let name: String
    let role: String
}

// MARK: - CoT Encoder

final class CoTEncoder {
    static let shared = CoTEncoder()

    private lazy var dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private init() {}

    /// Encode a CoT event to XML Data
    func encode(_ event: CoTEvent) -> Data {
        var xml = "<?xml version='1.0' encoding='UTF-8' standalone='yes'?>\n"

        let timeStr = dateFormatter.string(from: event.time)
        let startStr = dateFormatter.string(from: event.start)
        let staleStr = dateFormatter.string(from: event.stale)

        xml += "<event"
        xml += " version=\"2.0\""
        xml += " uid=\"\(xmlEscape(event.uid))\""
        xml += " type=\"\(xmlEscape(event.type))\""
        xml += " time=\"\(timeStr)\""
        xml += " start=\"\(startStr)\""
        xml += " stale=\"\(staleStr)\""
        xml += " how=\"\(xmlEscape(event.how))\""
        xml += ">\n"

        // Point element
        xml += "  <point"
        xml += " lat=\"\(formatCoordinate(event.lat))\""
        xml += " lon=\"\(formatCoordinate(event.lon))\""
        xml += " hae=\"\(formatNumber(event.hae))\""
        xml += " ce=\"\(formatNumber(event.ce))\""
        xml += " le=\"\(formatNumber(event.le))\""
        xml += "/>\n"

        // Detail element
        if let detail = event.detail {
            xml += encodeDetail(detail)
        }

        xml += "</event>"

        return xml.data(using: .utf8) ?? Data()
    }

    private func encodeDetail(_ detail: CoTDetail) -> String {
        var xml = "  <detail>\n"

        if let contact = detail.contact {
            xml += "    <contact"
            xml += " callsign=\"\(xmlEscape(contact.callsign))\""
            if let endpoint = contact.endpoint {
                xml += " endpoint=\"\(xmlEscape(endpoint))\""
            }
            xml += "/>\n"
        }

        if let status = detail.status {
            xml += "    <status battery=\"\(status.battery)\"/>\n"
        }

        if let takv = detail.takv {
            xml += "    <takv"
            xml += " device=\"\(xmlEscape(takv.device))\""
            xml += " platform=\"\(xmlEscape(takv.platform))\""
            xml += " os=\"\(xmlEscape(takv.os))\""
            xml += " version=\"\(xmlEscape(takv.version))\""
            xml += "/>\n"
        }

        if let track = detail.track {
            xml += "    <track"
            xml += " speed=\"\(formatNumber(track.speed))\""
            xml += " course=\"\(formatNumber(track.course))\""
            xml += "/>\n"
        }

        if let group = detail.group {
            xml += "    <__group"
            xml += " name=\"\(xmlEscape(group.name))\""
            xml += " role=\"\(xmlEscape(group.role))\""
            xml += "/>\n"
        }

        if let xmlDetail = detail.xmlDetail {
            xml += xmlDetail
        }

        xml += "  </detail>\n"
        return xml
    }

    private func xmlEscape(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func formatCoordinate(_ value: Double) -> String {
        return String(format: "%.8f", value)
    }

    private func formatNumber(_ value: Double) -> String {
        if value == 9999999 {
            return "9999999"
        }
        return String(value)
    }
}

// MARK: - CoT Decoder

final class CoTDecoder: NSObject, XMLParserDelegate {
    static let shared = CoTDecoder()

    private lazy var dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private var currentEvent: CoTEvent?
    private var currentDetail: CoTDetail?
    private var currentContact: CoTContact?
    private var currentStatus: CoTStatus?
    private var currentTakv: CoTTakv?
    private var currentTrack: CoTTrack?
    private var currentGroup: CoTGroup?

    private override init() {}

    func decode(_ data: Data) -> CoTEvent? {
        let parser = XMLParser(data: data)

        currentEvent = nil
        currentDetail = nil
        parser.delegate = self
        parser.parse()

        return currentEvent
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {

        switch elementName {
        case "event":
            let uid = attributeDict["uid"] ?? UUID().uuidString
            let type = attributeDict["type"] ?? "a-f-G"
            let how = attributeDict["how"] ?? "m-g"

            let time = parseDate(attributeDict["time"]) ?? Date()
            let start = parseDate(attributeDict["start"]) ?? Date()
            let stale = parseDate(attributeDict["stale"]) ?? Date(timeIntervalSinceNow: 300)

            currentEvent = CoTEvent(
                uid: uid,
                type: type,
                how: how,
                time: time,
                start: start,
                stale: stale
            )

        case "point":
            let lat = Double(attributeDict["lat"] ?? "0") ?? 0
            let lon = Double(attributeDict["lon"] ?? "0") ?? 0
            let hae = Double(attributeDict["hae"] ?? "9999999") ?? 9999999
            let ce = Double(attributeDict["ce"] ?? "9999999") ?? 9999999
            let le = Double(attributeDict["le"] ?? "9999999") ?? 9999999

            currentEvent?.lat = lat
            currentEvent?.lon = lon
            currentEvent?.hae = hae
            currentEvent?.ce = ce
            currentEvent?.le = le

        case "detail":
            currentDetail = CoTDetail()

        case "contact":
            let callsign = attributeDict["callsign"] ?? "Unknown"
            let endpoint = attributeDict["endpoint"]
            currentContact = CoTContact(callsign: callsign, endpoint: endpoint)

        case "status":
            let battery = Int(attributeDict["battery"] ?? "0") ?? 0
            currentStatus = CoTStatus(battery: battery)

        case "takv":
            let device = attributeDict["device"] ?? "Unknown"
            let platform = attributeDict["platform"] ?? "Unknown"
            let os = attributeDict["os"] ?? "Unknown"
            let version = attributeDict["version"] ?? "Unknown"
            currentTakv = CoTTakv(device: device, platform: platform, os: os, version: version)

        case "track":
            let speed = Double(attributeDict["speed"] ?? "0") ?? 0
            let course = Double(attributeDict["course"] ?? "0") ?? 0
            currentTrack = CoTTrack(speed: speed, course: course)

        case "__group":
            let name = attributeDict["name"] ?? "Unknown"
            let role = attributeDict["role"] ?? "Unknown"
            currentGroup = CoTGroup(name: name, role: role)

        default:
            break
        }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {

        switch elementName {
        case "contact":
            if var detail = currentDetail, let contact = currentContact {
                detail.contact = contact
                currentDetail = detail
            }
            currentContact = nil

        case "status":
            if var detail = currentDetail, let status = currentStatus {
                detail.status = status
                currentDetail = detail
            }
            currentStatus = nil

        case "takv":
            if var detail = currentDetail, let takv = currentTakv {
                detail.takv = takv
                currentDetail = detail
            }
            currentTakv = nil

        case "track":
            if var detail = currentDetail, let track = currentTrack {
                detail.track = track
                currentDetail = detail
            }
            currentTrack = nil

        case "__group":
            if var detail = currentDetail, let group = currentGroup {
                detail.group = group
                currentDetail = detail
            }
            currentGroup = nil

        case "detail":
            if let detail = currentDetail {
                var event = currentEvent ?? CoTEvent()
                event.detail = detail
                currentEvent = event
            }
            currentDetail = nil

        default:
            break
        }
    }

    private func parseDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        return dateFormatter.date(from: dateString)
    }
}
