// LiDARIntelBridge.swift — Wires MLX phi-3.5 inference to LiDAR scan results
// Generates natural-language tactical assessments from scan data post-scan (not per-frame)

import Foundation

@MainActor
final class LiDARIntelBridge {
    static let shared = LiDARIntelBridge()

    private let engine = LocalInferenceEngine.shared

    private init() {}

    // MARK: - Assessment Generation

    /// Generate a natural-language tactical assessment from a completed scan.
    /// Only runs if the MLX model is loaded; otherwise returns a rule-based fallback.
    func generateAssessment(
        threats: [SceneTag.TaggedThreat],
        covers: [SceneTag.TaggedCover],
        tacticalAnalysis: TacticalAnalysis?,
        terrainAnalysis: TerrainAnalysis?
    ) async -> String {
        guard engine.modelState == .ready else {
            return buildRuleBasedAssessment(threats: threats, covers: covers, tacticalAnalysis: tacticalAnalysis)
        }

        let prompt = buildPrompt(threats: threats, covers: covers, tacticalAnalysis: tacticalAnalysis, terrainAnalysis: terrainAnalysis)

        return await withCheckedContinuation { continuation in
            var result = ""
            engine.generate(
                prompt: prompt,
                maxTokens: 256,
                onToken: { token in
                    result += token
                },
                onComplete: {
                    let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: trimmed.isEmpty ? "Assessment unavailable." : trimmed)
                }
            )
        }
    }

    // MARK: - Prompt Construction

    private func buildPrompt(
        threats: [SceneTag.TaggedThreat],
        covers: [SceneTag.TaggedCover],
        tacticalAnalysis: TacticalAnalysis?,
        terrainAnalysis: TerrainAnalysis?
    ) -> String {
        var lines: [String] = ["TACTICAL LiDAR SCAN DATA:"]

        // Threats
        if threats.isEmpty {
            lines.append("- No threats detected")
        } else {
            lines.append("- \(threats.count) threat(s) detected:")
            for t in threats.prefix(10) {
                let dist = t.distance.map { String(format: "%.1fm", $0) } ?? "unknown"
                lines.append("  * \(t.className) (\(t.category)) at \(dist), conf \(String(format: "%.0f%%", t.confidence * 100)), level \(t.level)/4")
            }
        }

        // Covers
        if covers.isEmpty {
            lines.append("- No cover positions identified")
        } else {
            lines.append("- \(covers.count) cover position(s):")
            for c in covers.prefix(8) {
                lines.append("  * \(c.type), protection \(String(format: "%.0f%%", c.protection * 100))")
            }
        }

        // Tactical summary
        if let tac = tacticalAnalysis {
            lines.append("- Risk score: \(String(format: "%.1f", tac.riskScore))/10")
            lines.append("- Observation posts: \(tac.observationPosts.count)")
            lines.append("- Approach routes: \(tac.approachRoutes.count)")
            lines.append("- Escape routes: \(tac.escapeRoutes.count)")
        }

        // Terrain
        if let terrain = terrainAnalysis {
            lines.append("- Cover positions from terrain: \(terrain.coverPositions.count)")
            if !terrain.routeOptions.isEmpty {
                lines.append("- Movement routes: \(terrain.routeOptions.count)")
            }
        }

        lines.append("")
        lines.append("Provide a 3-sentence tactical assessment: (1) immediate threats and their priority, (2) recommended cover position and movement, (3) suggested next action. Be direct and specific.")

        return lines.joined(separator: "\n")
    }

    // MARK: - Rule-Based Fallback

    private func buildRuleBasedAssessment(
        threats: [SceneTag.TaggedThreat],
        covers: [SceneTag.TaggedCover],
        tacticalAnalysis: TacticalAnalysis?
    ) -> String {
        var parts: [String] = []

        // Threats
        let criticalThreats = threats.filter { $0.level >= 3 }
        let totalThreats = threats.count

        if criticalThreats.isEmpty && totalThreats == 0 {
            parts.append("No immediate threats detected in scan area.")
        } else if !criticalThreats.isEmpty {
            let nearest = criticalThreats.compactMap(\.distance).min()
            let distStr = nearest.map { String(format: " at %.1fm", $0) } ?? ""
            parts.append("\(criticalThreats.count) critical threat(s)\(distStr) — immediate action required.")
        } else {
            parts.append("\(totalThreats) low-level detection(s) in scan area — maintain awareness.")
        }

        // Cover
        let goodCover = covers.filter { $0.protection > 0.6 }
        if goodCover.isEmpty {
            parts.append("No reliable cover positions identified — consider repositioning.")
        } else {
            parts.append("\(goodCover.count) solid cover position(s) available.")
        }

        // Risk
        if let risk = tacticalAnalysis?.riskScore {
            if risk > 7 {
                parts.append("High risk environment (\(String(format: "%.1f", risk))/10) — recommend withdrawal or reinforcement.")
            } else if risk > 4 {
                parts.append("Moderate risk (\(String(format: "%.1f", risk))/10) — proceed with caution.")
            } else {
                parts.append("Low risk (\(String(format: "%.1f", risk))/10) — area appears secure.")
            }
        }

        return parts.joined(separator: " ")
    }
}
