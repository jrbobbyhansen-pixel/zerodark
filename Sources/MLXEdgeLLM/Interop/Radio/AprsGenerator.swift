import Foundation
import CoreLocation

// MARK: - APRS Packet Generation

struct AprsPacket {
    let header: String
    let body: String
    let checksum: String
    
    var fullPacket: String {
        return "\(header)\(body)*\(checksum)"
    }
}

class AprsGenerator {
    private let callsign: String
    private let latitude: Double
    private let longitude: Double
    private let altitude: Double
    
    init(callsign: String, latitude: Double, longitude: Double, altitude: Double) {
        self.callsign = callsign
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }
    
    func generatePositionReport() -> AprsPacket {
        let latitudeString = formatLatitude(latitude)
        let longitudeString = formatLongitude(longitude)
        let altitudeString = String(format: "%.0f", altitude)
        let body = "\(latitudeString)N/\(longitudeString)W/\(altitudeString)A"
        let checksum = calculateChecksum(header: callsign, body: body)
        return AprsPacket(header: callsign, body: body, checksum: checksum)
    }
    
    func generateMessage(to: String, message: String) -> AprsPacket {
        let body = ">\(to):\(message)"
        let checksum = calculateChecksum(header: callsign, body: body)
        return AprsPacket(header: callsign, body: body, checksum: checksum)
    }
    
    func generateObject(name: String, latitude: Double, longitude: Double, altitude: Double) -> AprsPacket {
        let latitudeString = formatLatitude(latitude)
        let longitudeString = formatLongitude(longitude)
        let altitudeString = String(format: "%.0f", altitude)
        let body = ":\(name),\(latitudeString)N/\(longitudeString)W/\(altitudeString)A"
        let checksum = calculateChecksum(header: callsign, body: body)
        return AprsPacket(header: callsign, body: body, checksum: checksum)
    }
    
    private func formatLatitude(_ latitude: Double) -> String {
        let degrees = Int(latitude)
        let minutes = (latitude - Double(degrees)) * 60
        return String(format: "%02d%05.2f", degrees, minutes)
    }
    
    private func formatLongitude(_ longitude: Double) -> String {
        let degrees = Int(longitude)
        let minutes = (longitude - Double(degrees)) * 60
        return String(format: "%03d%05.2f", degrees, minutes)
    }
    
    private func calculateChecksum(header: String, body: String) -> String {
        let data = (header + body).data(using: .ascii)!
        let checksum = data.reduce(0) { $0 ^ $1 }
        return String(format: "%02X", checksum)
    }
}

// MARK: - Example Usage

// let aprsGenerator = AprsGenerator(callsign: "ZERODARK", latitude: 37.7749, longitude: -122.4194, altitude: 100)
// let positionReport = aprsGenerator.generatePositionReport()
// print(positionReport.fullPacket)