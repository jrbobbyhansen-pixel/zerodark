// VerifyPipeline.swift — AI Output Verification Pipeline
// ZeroDark Intel Tab v6.0
//
// Three-stage verification (<50ms, no LLM):
// 1. Sentence-level grounding against source chunks
// 2. Safety keyword filter for critical domains
// 3. Contradiction detection (negation pattern matching)

import Foundation

// MARK: - Verification Result

struct VerificationResult {
    let isVerified: Bool
    let confidence: Double             // 0-1
    let groundedClaims: [String]       // Claims supported by sources
    let ungroundedClaims: [String]     // Claims NOT in sources
    let flags: [VerificationFlag]
    let suggestedDisclaimer: String?

    var badgeColor: String {
        if isVerified && confidence > 0.8 { return "green" }
        if confidence > 0.5 { return "yellow" }
        return "red"
    }

    static let unverified = VerificationResult(
        isVerified: false, confidence: 0,
        groundedClaims: [], ungroundedClaims: [],
        flags: [.lowConfidence],
        suggestedDisclaimer: "This response could not be verified against source material."
    )
}

enum VerificationFlag: String, Hashable {
    case grounded           // Claim matches source material
    case ungrounded         // No source support
    case contradictory      // Contradicts source
    case safetyRisk         // Potentially dangerous advice
    case outdatedSource     // Source may be stale
    case lowConfidence      // Model confidence below threshold
}

// MARK: - Verify Pipeline

final class VerifyPipeline: ObservableObject {
    static let shared = VerifyPipeline()

    private let groundingThreshold: Double = 0.4 // BM25 overlap threshold
    private let safetyDomains: Set<String> = [
        "tourniquet", "cpr", "bleeding", "wound", "fracture", "poison",
        "explosive", "detonation", "ied", "mine",
        "bearing", "azimuth", "coordinates", "grid",
        "dosage", "medication", "injection", "airway"
    ]
    private let negationPatterns = [
        "do not", "don't", "never", "avoid", "stop", "cease",
        "prohibited", "forbidden", "dangerous to", "fatal if"
    ]

    private let knowledgeRAG = KnowledgeRAG.shared

    private init() {}

    // MARK: - Full Verification

    func verify(response: String, query: String,
                sourceResults: [MultiModalResult]) -> VerificationResult {
        let sentences = splitSentences(response)
        guard !sentences.isEmpty else { return .unverified }

        var groundedClaims: [String] = []
        var ungroundedClaims: [String] = []
        var flags: [VerificationFlag] = []

        let sourceTexts = sourceResults.map { $0.content.lowercased() }
        let sourceJoined = sourceTexts.joined(separator: " ")

        // Stage 1: Sentence-level grounding
        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > 10 else { continue } // Skip trivial fragments

            let overlap = computeOverlap(sentence: trimmed.lowercased(), sources: sourceTexts)
            if overlap >= groundingThreshold {
                groundedClaims.append(trimmed)
                flags.append(.grounded)
            } else {
                ungroundedClaims.append(trimmed)
                flags.append(.ungrounded)
            }
        }

        // Stage 2: Safety domain check
        let responseLower = response.lowercased()
        let touchesSafety = safetyDomains.contains { responseLower.contains($0) }
        var disclaimer: String? = nil

        if touchesSafety && !ungroundedClaims.isEmpty {
            flags.append(.safetyRisk)
            disclaimer = "This response contains safety-critical advice that could not be fully verified against source material. Cross-reference with official protocols."
        }

        // Stage 3: Contradiction detection
        for sentence in sentences {
            let sentenceLower = sentence.lowercased()
            for pattern in negationPatterns {
                if sentenceLower.contains(pattern) {
                    // Check if source says the opposite
                    let actionAfterNegation = extractActionAfterNegation(sentenceLower, pattern: pattern)
                    if !actionAfterNegation.isEmpty {
                        // Check if sources recommend this action (contradiction)
                        let sourceRecommends = sourceJoined.contains(actionAfterNegation)
                            && !sourceJoined.contains(pattern + " " + actionAfterNegation)
                        if sourceRecommends {
                            flags.append(.contradictory)
                        }
                    }
                }
            }
        }

        // Calculate confidence
        let totalClaims = groundedClaims.count + ungroundedClaims.count
        let confidence: Double
        if totalClaims == 0 {
            confidence = 0.5
        } else {
            confidence = Double(groundedClaims.count) / Double(totalClaims)
        }

        let isVerified = confidence >= 0.6 && !flags.contains(.contradictory)

        return VerificationResult(
            isVerified: isVerified,
            confidence: confidence,
            groundedClaims: groundedClaims,
            ungroundedClaims: ungroundedClaims,
            flags: Array(Set(flags)),
            suggestedDisclaimer: disclaimer
        )
    }

    // MARK: - Quick Verify (for streaming)

    func quickVerify(sentence: String, sourceTexts: [String]) -> VerificationFlag {
        let sentenceLower = sentence.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard sentenceLower.count > 10 else { return .grounded }

        let overlap = computeOverlap(sentence: sentenceLower, sources: sourceTexts)
        if overlap >= groundingThreshold {
            return .grounded
        }

        // Check safety domain
        if safetyDomains.contains(where: { sentenceLower.contains($0) }) {
            return .safetyRisk
        }

        return .ungrounded
    }

    // MARK: - Helpers

    private func splitSentences(_ text: String) -> [String] {
        // Split on sentence-ending punctuation
        let pattern = "[.!?]\\s+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [text]
        }
        let range = NSRange(text.startIndex..., in: text)
        var sentences: [String] = []
        var lastEnd = text.startIndex

        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let matchRange = match?.range,
                  let swiftRange = Range(matchRange, in: text) else { return }
            let sentence = String(text[lastEnd..<swiftRange.upperBound])
            sentences.append(sentence)
            lastEnd = swiftRange.upperBound
        }

        // Add remaining text
        if lastEnd < text.endIndex {
            sentences.append(String(text[lastEnd...]))
        }

        return sentences.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func computeOverlap(sentence: String, sources: [String]) -> Double {
        // Tokenize sentence into meaningful words
        let words = tokenize(sentence)
        guard !words.isEmpty else { return 0 }

        // Check how many words appear in any source
        var matchCount = 0
        for word in words {
            if sources.contains(where: { $0.contains(word) }) {
                matchCount += 1
            }
        }

        return Double(matchCount) / Double(words.count)
    }

    private func tokenize(_ text: String) -> [String] {
        let stopWords: Set<String> = [
            "the", "and", "for", "with", "this", "that", "from", "are", "was",
            "will", "can", "not", "but", "you", "your", "have", "they", "their",
            "when", "then", "into", "over", "each", "only", "also", "both",
            "been", "more", "very", "should", "would", "could", "may", "might"
        ]
        return text.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }

    private func extractActionAfterNegation(_ text: String, pattern: String) -> String {
        guard let range = text.range(of: pattern) else { return "" }
        let after = text[range.upperBound...]
            .trimmingCharacters(in: .whitespaces)
        // Take up to 4 words after the negation
        let words = after.split(separator: " ").prefix(4)
        return words.joined(separator: " ")
    }
}
