// SafetyViolation.swift — Record of a safety property violation

import Foundation

/// Record of a safety property violation
public struct SafetyViolation: Identifiable, Codable {
    public let id: UUID
    public let property: String  // SafetyProperty.rawValue
    public let severity: Int     // ViolationSeverity.rawValue
    public let timestamp: Date
    public let details: String
    public var resolved: Bool
    public var resolvedAt: Date?
    public var handlerTriggered: Bool

    public init(property: SafetyProperty, details: String) {
        self.id = UUID()
        self.property = property.rawValue
        self.severity = property.severity.rawValue
        self.timestamp = Date()
        self.details = details
        self.resolved = false
        self.resolvedAt = nil
        self.handlerTriggered = false
    }
}
