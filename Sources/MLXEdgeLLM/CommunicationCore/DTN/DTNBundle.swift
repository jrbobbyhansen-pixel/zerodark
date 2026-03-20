// DTNBundle.swift — A delay-tolerant network bundle (NASA HDTN pattern)

import Foundation
import UIKit

/// A delay-tolerant network bundle (NASA HDTN pattern)
public struct DTNBundle: Codable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let expiresAt: Date
    public let source: String           // Sender peer ID
    public let destination: String      // "all" or specific peer ID
    public let priority: BundlePriority
    public let payload: Data
    public var deliveryAttempts: Int
    public var lastAttemptAt: Date?
    public var deliveredAt: Date?

    public enum BundlePriority: Int, Codable, Comparable {
        case bulk = 0
        case normal = 1
        case expedited = 2
        case critical = 3

        public static func < (lhs: BundlePriority, rhs: BundlePriority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public var isExpired: Bool {
        Date() > expiresAt
    }

    public var isDelivered: Bool {
        deliveredAt != nil
    }

    public init(
        destination: String,
        payload: Data,
        priority: BundlePriority = .normal,
        ttl: TimeInterval = 86400  // Default 24 hours (HDTN pattern)
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.expiresAt = Date().addingTimeInterval(ttl)
        self.source = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        self.destination = destination
        self.priority = priority
        self.payload = payload
        self.deliveryAttempts = 0
        self.lastAttemptAt = nil
        self.deliveredAt = nil
    }
}

/// Wrapper for message types that can be bundled
public protocol DTNBundleable: Codable {
    var bundlePriority: DTNBundle.BundlePriority { get }
    var bundleTTL: TimeInterval { get }
}

extension DTNBundleable {
    public var bundlePriority: DTNBundle.BundlePriority { .normal }
    public var bundleTTL: TimeInterval { 86400 } // 24 hours default
}
