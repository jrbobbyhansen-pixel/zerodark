// ThreatReport.swift — AI-classified threat report

import Foundation

/// A threat report with AI classification
public struct ThreatReport: Identifiable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let source: String            // Reporter ID
    public let text: String              // Original report text
    public let category: String          // ThreatCategory rawValue
    public let confidence: Double        // 0.0 to 1.0
    public let location: CodableCoordinate?
    public var resolved: Bool = false
    /// Human-readable reason the report was resolved — e.g. "false positive",
    /// "below threshold", "suppressed", or an operator note. Optional so
    /// historical reports persisted without this field still decode cleanly.
    public var resolution: String?

    public init(
        source: String,
        text: String,
        category: String,
        confidence: Double,
        location: CodableCoordinate? = nil,
        resolution: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.source = source
        self.text = text
        self.category = category
        self.confidence = confidence
        self.location = location
        self.resolution = resolution
    }
}
