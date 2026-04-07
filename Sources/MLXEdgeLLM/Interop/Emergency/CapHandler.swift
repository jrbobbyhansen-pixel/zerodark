import Foundation
import SwiftUI
import CoreLocation

// MARK: - CAP Alert Handler

class CapHandler: ObservableObject {
    @Published var alerts: [CapAlert] = []
    
    func parseCapMessage(_ message: String) {
        // Parse the CAP message and create CapAlert instances
        // For simplicity, assume the message is a valid XML string
        if let data = message.data(using: .utf8) {
            let decoder = XMLDecoder()
            do {
                let capMessage = try decoder.decode(CapMessage.self, from: data)
                alerts.append(contentsOf: capMessage.alerts)
            } catch {
                print("Failed to parse CAP message: \(error)")
            }
        }
    }
    
    func generateCapMessage(for alert: CapAlert) -> String? {
        // Generate a CAP message from a CapAlert instance
        let encoder = XMLEncoder()
        encoder.outputFormatting = .prettyPrinted
        do {
            let data = try encoder.encode(alert)
            return String(data: data, encoding: .utf8)
        } catch {
            print("Failed to generate CAP message: \(error)")
            return nil
        }
    }
}

// MARK: - CAP Message Models

struct CapMessage: Codable {
    let alerts: [CapAlert]
}

struct CapAlert: Codable, Identifiable {
    let id: String
    let sender: String
    let sent: Date
    let status: String
    let msgType: String
    let scope: String
    let info: [CapInfo]
}

struct CapInfo: Codable {
    let category: String
    let event: String
    let urgency: String
    let severity: String
    let certainty: String
    let effective: Date?
    let expires: Date?
    let senderName: String
    let headline: String
    let description: String
    let instruction: String?
    let parameters: [CapParameter]?
    let area: [CapArea]?
}

struct CapParameter: Codable {
    let valueName: String
    let value: String
}

struct CapArea: Codable {
    let areaDesc: String
    let polygon: [CLLocationCoordinate2D]?
    let circle: [CLLocationCoordinate2D]?
    let geocode: [CapGeocode]?
}

struct CapGeocode: Codable {
    let valueName: String
    let value: String
}

// MARK: - XMLDecoder and XMLEncoder

extension XMLDecoder {
    convenience init() {
        self.init()
        self.dateDecodingStrategy = .iso8601
    }
}

extension XMLEncoder {
    convenience init() {
        self.init()
        self.dateEncodingStrategy = .iso8601
    }
}