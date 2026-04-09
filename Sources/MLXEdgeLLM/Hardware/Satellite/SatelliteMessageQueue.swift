import Foundation
import SwiftUI

// MARK: - SatelliteMessageQueue

class SatelliteMessageQueue: ObservableObject {
    @Published private(set) var messages: [SatelliteMessage] = []
    
    private let maxMessageLength: Int = 1000
    private let compressionThreshold: Int = 500
    
    func enqueue(_ message: String, priority: MessagePriority) {
        let trimmedMessage = String(message.prefix(maxMessageLength))
        let compressedMessage = shouldCompress(trimmedMessage) ? compress(trimmedMessage) : trimmedMessage
        let satelliteMessage = SatelliteMessage(content: compressedMessage, priority: priority)
        
        messages.append(satelliteMessage)
        messages.sort { $0.priority.rawValue < $1.priority.rawValue }
    }
    
    func dequeue() -> SatelliteMessage? {
        guard !messages.isEmpty else { return nil }
        return messages.removeFirst()
    }
    
    func confirmDelivery(of message: SatelliteMessage) {
        // Placeholder for delivery confirmation logic
    }
    
    private func shouldCompress(_ message: String) -> Bool {
        message.count > compressionThreshold
    }
    
    private func compress(_ message: String) -> String {
        // Placeholder for compression logic
        return message
    }
}

// MARK: - SatelliteMessage

struct SatelliteMessage: Identifiable {
    let id = UUID()
    let content: String
    let priority: MessagePriority
}

// MARK: - MessagePriority

enum MessagePriority: Int, Comparable {
    case low
    case medium
    case high
    
    static func < (lhs: MessagePriority, rhs: MessagePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}