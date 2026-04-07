import Foundation
import CoreLocation

// MARK: - APRS Packet Parsing

struct AprsPacket {
    let source: String
    let destination: String
    let path: [String]
    let payload: String
}

enum AprsPayload {
    case position(PositionPayload)
    case weather(WeatherPayload)
    case telemetry(TelemetryPayload)
    case message(MessagePayload)
    case unknown(String)
}

struct PositionPayload {
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    let altitude: CLLocationDistance?
    let timestamp: Date?
    let symbol: String
    let comment: String
}

struct WeatherPayload {
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    let timestamp: Date?
    let temperature: Double
    let humidity: Int
    let windSpeed: Double
    let windDirection: Int
    let rainLastHour: Double
    let rainLast24Hours: Double
    let rainSinceMidnight: Double
}

struct TelemetryPayload {
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    let timestamp: Date?
    let sensorData: [String: Double]
}

struct MessagePayload {
    let message: String
}

class AprsParser {
    func parse(packet: String) -> AprsPacket? {
        let components = packet.split(separator: ">")
        guard components.count == 3 else { return nil }
        
        let source = String(components[0])
        let pathComponents = components[1].split(separator: ",")
        let destination = String(pathComponents.first ?? "")
        let path = pathComponents.dropFirst().map { String($0) }
        let payload = String(components[2])
        
        return AprsPacket(source: source, destination: destination, path: path, payload: payload)
    }
    
    func parsePayload(_ payload: String) -> AprsPayload {
        if let positionPayload = parsePositionPayload(payload) {
            return .position(positionPayload)
        } else if let weatherPayload = parseWeatherPayload(payload) {
            return .weather(weatherPayload)
        } else if let telemetryPayload = parseTelemetryPayload(payload) {
            return .telemetry(telemetryPayload)
        } else if let messagePayload = parseMessagePayload(payload) {
            return .message(messagePayload)
        } else {
            return .unknown(payload)
        }
    }
    
    private func parsePositionPayload(_ payload: String) -> PositionPayload? {
        // Implement position payload parsing
        return nil
    }
    
    private func parseWeatherPayload(_ payload: String) -> WeatherPayload? {
        // Implement weather payload parsing
        return nil
    }
    
    private func parseTelemetryPayload(_ payload: String) -> TelemetryPayload? {
        // Implement telemetry payload parsing
        return nil
    }
    
    private func parseMessagePayload(_ payload: String) -> MessagePayload? {
        // Implement message payload parsing
        return nil
    }
}