import Foundation
import CoreLocation

// MARK: - NMEA Sentence Parser

struct NmeaParser {
    func parse(_ sentence: String) -> NmeaSentence? {
        let components = sentence.components(separatedBy: ",")
        guard components.count > 0 else { return nil }
        
        let type = components[0]
        
        switch type {
        case "$GPGGA":
            return parseGGA(components)
        case "$GPRMC":
            return parseRMC(components)
        case "$GPGSA":
            return parseGSA(components)
        case "$GPGSV":
            return parseGSV(components)
        default:
            return nil
        }
    }
    
    private func parseGGA(_ components: [String]) -> NmeaSentence? {
        guard components.count >= 15 else { return nil }
        
        let time = components[1]
        let latitude = parseLatitude(components[2], hemisphere: components[3])
        let longitude = parseLongitude(components[4], hemisphere: components[5])
        let quality = Int(components[6]) ?? 0
        let satellites = Int(components[7]) ?? 0
        let hdop = Double(components[8]) ?? 0.0
        let altitude = Double(components[9]) ?? 0.0
        let geoidHeight = Double(components[11]) ?? 0.0
        
        return GGA(time: time, latitude: latitude, longitude: longitude, quality: quality, satellites: satellites, hdop: hdop, altitude: altitude, geoidHeight: geoidHeight)
    }
    
    private func parseRMC(_ components: [String]) -> NmeaSentence? {
        guard components.count >= 12 else { return nil }
        
        let time = components[1]
        let status = components[2]
        let latitude = parseLatitude(components[3], hemisphere: components[4])
        let longitude = parseLongitude(components[5], hemisphere: components[6])
        let speed = Double(components[7]) ?? 0.0
        let course = Double(components[8]) ?? 0.0
        let date = components[9]
        let magneticVariation = Double(components[10]) ?? 0.0
        let magneticVariationDirection = components[11]
        
        return RMC(time: time, status: status, latitude: latitude, longitude: longitude, speed: speed, course: course, date: date, magneticVariation: magneticVariation, magneticVariationDirection: magneticVariationDirection)
    }
    
    private func parseGSA(_ components: [String]) -> NmeaSentence? {
        guard components.count >= 18 else { return nil }
        
        let mode1 = components[1]
        let mode2 = components[2]
        let satellites = (3..<15).compactMap { Int(components[$0]) }
        let pdop = Double(components[15]) ?? 0.0
        let hdop = Double(components[16]) ?? 0.0
        let vdop = Double(components[17]) ?? 0.0
        
        return GSA(mode1: mode1, mode2: mode2, satellites: satellites, pdop: pdop, hdop: hdop, vdop: vdop)
    }
    
    private func parseGSV(_ components: [String]) -> NmeaSentence? {
        guard components.count >= 4 else { return nil }
        
        let totalMessages = Int(components[1]) ?? 0
        let messageNumber = Int(components[2]) ?? 0
        let satellitesInView = Int(components[3]) ?? 0
        let satellites = (4..<components.count).compactMap { parseGSVSatellite(components[$0]) }
        
        return GSV(totalMessages: totalMessages, messageNumber: messageNumber, satellitesInView: satellitesInView, satellites: satellites)
    }
    
    private func parseGSVSatellite(_ component: String) -> GSV.Satellite? {
        guard component.count == 30 else { return nil }
        
        let prn = Int(component.prefix(2)) ?? 0
        let elevation = Int(component.dropFirst(2).prefix(3)) ?? 0
        let azimuth = Int(component.dropFirst(5).prefix(3)) ?? 0
        let snr = Int(component.dropFirst(8).prefix(2)) ?? 0
        
        return GSV.Satellite(prn: prn, elevation: elevation, azimuth: azimuth, snr: snr)
    }
    
    private func parseLatitude(_ value: String, hemisphere: String) -> CLLocationDegrees {
        guard let degrees = Double(value.prefix(2)), let minutes = Double(value.dropFirst(2)) else { return 0.0 }
        let latitude = degrees + minutes / 60.0
        return hemisphere == "S" ? -latitude : latitude
    }
    
    private func parseLongitude(_ value: String, hemisphere: String) -> CLLocationDegrees {
        guard let degrees = Double(value.prefix(3)), let minutes = Double(value.dropFirst(3)) else { return 0.0 }
        let longitude = degrees + minutes / 60.0
        return hemisphere == "W" ? -longitude : longitude
    }
}

// MARK: - NMEA Sentence Types

enum NmeaSentence {
    case gga(GGA)
    case rmc(RMC)
    case gsa(GSA)
    case gsv(GSV)
}

struct GGA: NmeaSentence {
    let time: String
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    let quality: Int
    let satellites: Int
    let hdop: Double
    let altitude: Double
    let geoidHeight: Double
}

struct RMC: NmeaSentence {
    let time: String
    let status: String
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    let speed: Double
    let course: Double
    let date: String
    let magneticVariation: Double
    let magneticVariationDirection: String
}

struct GSA: NmeaSentence {
    let mode1: String
    let mode2: String
    let satellites: [Int]
    let pdop: Double
    let hdop: Double
    let vdop: Double
}

struct GSV: NmeaSentence {
    let totalMessages: Int
    let messageNumber: Int
    let satellitesInView: Int
    let satellites: [Satellite]
    
    struct Satellite {
        let prn: Int
        let elevation: Int
        let azimuth: Int
        let snr: Int
    }
}