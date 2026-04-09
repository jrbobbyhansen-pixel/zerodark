// ActivityFeed.swift — App-Wide Activity Logging
// Tracks all significant actions for operational awareness

import Foundation
import SwiftUI

enum ActivityType: String, Codable {
    case locationShared
    case waypointCreated
    case waypointDeleted
    case lidarScanCompleted
    case meshJoined
    case meshLeft
    case peerConnected
    case peerDisconnected
    case messageReceived
    case messageSent
    case sosTriggered
    case sosReceived
    case hapticSent
    case hapticReceived
    case reportCreated
    case incidentCreated
    case patternGenerated
    case geofenceDeny
    case cotRelayed
    case aarCreated
    case dtnDelivered
}

struct ActivityItem: Identifiable, Codable {
    let id: UUID
    let type: ActivityType
    let message: String
    let timestamp: Date

    var icon: String {
        switch type {
        case .locationShared: return "location.fill"
        case .waypointCreated, .waypointDeleted: return "mappin"
        case .lidarScanCompleted: return "cube.fill"
        case .meshJoined, .meshLeft: return "antenna.radiowaves.left.and.right"
        case .peerConnected, .peerDisconnected: return "person.fill"
        case .messageReceived, .messageSent: return "bubble.left.fill"
        case .sosTriggered, .sosReceived: return "exclamationmark.triangle.fill"
        case .hapticSent, .hapticReceived: return "hand.tap.fill"
        case .reportCreated: return "doc.text.fill"
        case .incidentCreated: return "exclamationmark.circle.fill"
        case .patternGenerated: return "map.fill"
        case .geofenceDeny: return "shield.slash.fill"
        case .cotRelayed: return "arrow.triangle.branch"
        case .aarCreated: return "doc.badge.clock.fill"
        case .dtnDelivered: return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch type {
        case .sosTriggered, .sosReceived: return ZDDesign.signalRed
        case .hapticReceived: return .orange
        case .peerDisconnected, .meshLeft: return ZDDesign.mediumGray
        case .geofenceDeny: return ZDDesign.signalRed
        case .dtnDelivered: return ZDDesign.successGreen
        default: return ZDDesign.cyanAccent
        }
    }
}

@MainActor
final class ActivityFeed: ObservableObject {
    static let shared = ActivityFeed()

    @Published var items: [ActivityItem] = []

    private let maxItems = 100
    private let storageKey = "activity_feed"

    private init() {
        loadFromStorage()
    }

    func log(_ type: ActivityType, message: String) {
        let item = ActivityItem(
            id: UUID(),
            type: type,
            message: message,
            timestamp: Date()
        )

        items.insert(item, at: 0)

        // Trim if too many
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }

        saveToStorage()
    }

    func exportLogs() -> URL? {
        let text = items.map { item in
            "[\(item.timestamp.ISO8601Format())] \(item.type.rawValue): \(item.message)"
        }.joined(separator: "\n")

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("zerodark_activity_\(Date().ISO8601Format()).log")

        do {
            try text.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            return nil
        }
    }

    private func saveToStorage() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadFromStorage() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([ActivityItem].self, from: data) {
            items = saved
        }
    }
}
