// AARBundle.swift — After Action Report bundle for DTN relay
// Conforms to DTNBundleable for store-and-forward delivery over mesh

import Foundation

struct AARBundle: DTNBundleable {
    let missionId: String
    let timestamp: Date
    let participants: [String]
    let summary: String
    let findings: [String]
    let recommendations: [String]

    var bundlePriority: DTNBundle.BundlePriority { .normal }
    var bundleTTL: TimeInterval { 86400 * 7 } // 7 days for AAR

    init(
        missionId: String = UUID().uuidString,
        participants: [String] = [],
        summary: String,
        findings: [String] = [],
        recommendations: [String] = []
    ) {
        self.missionId = missionId
        self.timestamp = Date()
        self.participants = participants
        self.summary = summary
        self.findings = findings
        self.recommendations = recommendations
    }

    /// Create a DTNBundle from this AAR for mesh relay
    func toDTNBundle() throws -> DTNBundle {
        let payload = try JSONEncoder().encode(self)
        return DTNBundle(
            destination: "all",
            payload: payload,
            priority: bundlePriority,
            ttl: bundleTTL
        )
    }
}
