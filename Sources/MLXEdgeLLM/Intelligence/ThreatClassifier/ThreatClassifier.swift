// ThreatClassifier.swift — AI-powered threat classification (Boeing SDR-Hazards + Phi-3.5)
//
// PR-A4 additions:
//  - Per-category confidence thresholds (editable in Settings). Classifications
//    below threshold are auto-filtered so the operator sees only actionable
//    reports.
//  - False-positive suppress-list. When an operator marks a report as
//    false-positive, a short signature (category + normalized-text-hash) is
//    added to the suppress list for 1 hour. Any new classification matching
//    the signature is auto-resolved with .suppressed.
//  - `markFalsePositive(_:)` + `unsuppress(_:)` operator controls.
//  - All classifications + suppression actions logged to AuditLogger for
//    retraining export.

import Foundation
import CryptoKit

/// Threat classification singleton
@MainActor
public class ThreatClassifier: ObservableObject {
    public static let shared = ThreatClassifier()

    @Published public var reports: [ThreatReport] = []
    @Published public var isClassifying: Bool = false

    /// Per-category confidence threshold. Classifications below threshold
    /// are marked as .belowThreshold and do not surface to the operator by
    /// default. Editable in Settings > Threat classifier.
    @Published public var thresholds: [String: Double] = [
        "none":            1.0,   // never surface "none" at any confidence
        "environmental":   0.50,
        "personnel":       0.65,
        "equipment":       0.50,
        "chemical":        0.55,
        "biological":      0.55,
        "radiological":    0.55,
        "explosive":       0.70,
        "intelligence":    0.50
    ]

    /// Signatures of recently-suppressed classifications. Each signature
    /// auto-expires after `suppressWindow`. Persisted to disk.
    @Published public private(set) var suppressedSignatures: [SuppressEntry] = []
    public var suppressWindow: TimeInterval = 60 * 60 * 1  // 1 hour

    public struct SuppressEntry: Codable, Identifiable {
        public let id: UUID
        public let category: String
        public let textHash: String
        public let addedAt: Date
        public init(id: UUID = .init(), category: String, textHash: String, addedAt: Date = .init()) {
            self.id = id; self.category = category; self.textHash = textHash; self.addedAt = addedAt
        }
    }

    private init() {
        loadSuppressList()
    }

    /// Classify a free-text threat report using Phi-3.5
    public func classify(text: String, source: String, location: CodableCoordinate? = nil) async -> ThreatReport {
        isClassifying = true
        defer { isClassifying = false }

        let prompt = """
        Classify the following threat report into ONE of these categories: none, environmental, personnel, \
        equipment, chemical, biological, radiological, explosive, intelligence.

        Also provide a confidence score from 0 to 1.

        Report: "\(text)"

        Respond ONLY with JSON in this format:
        {
            "category": "category_name",
            "confidence": 0.85
        }
        """

        var classifiedCategory = "none"
        var confidence = 0.0
        var outputTokens = ""

        await LocalInferenceEngine.shared.generate(
            prompt: prompt,
            maxTokens: 100,
            onToken: { token in
                outputTokens += token
            },
            onComplete: {
                if let jsonData = outputTokens.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let cat = json["category"] as? String,
                   let conf = json["confidence"] as? Double {
                    classifiedCategory = cat
                    confidence = conf
                }
            }
        )

        // Apply threshold + suppress-list filtering before surfacing.
        let threshold = thresholds[classifiedCategory] ?? 0.5
        let passesThreshold = confidence >= threshold

        pruneExpiredSuppressions()
        let textHash = Self.hash(text: text)
        let isSuppressed = suppressedSignatures.contains(where: {
            $0.category == classifiedCategory && $0.textHash == textHash
        })

        var report = ThreatReport(
            source: source,
            text: text,
            category: classifiedCategory,
            confidence: confidence,
            location: location
        )
        if isSuppressed {
            report.resolved = true
            report.resolution = "suppressed (operator-flagged false positive)"
        } else if !passesThreshold {
            report.resolved = true
            report.resolution = String(format: "below %s threshold (%.2f < %.2f)",
                                       classifiedCategory, confidence, threshold)
        }

        reports.append(report)
        AuditLogger.shared.log(
            .observationLogged,
            detail: "threat_classify cat:\(classifiedCategory) conf:\(String(format: "%.2f", confidence)) " +
                    "passed:\(passesThreshold) suppressed:\(isSuppressed)"
        )
        saveReports()
        return report
    }

    /// Mark a report as a false positive. Records a suppression signature so
    /// future similar reports are auto-resolved for `suppressWindow`.
    public func markFalsePositive(_ report: ThreatReport) {
        guard let idx = reports.firstIndex(where: { $0.id == report.id }) else { return }
        reports[idx].resolved = true
        reports[idx].resolution = "false positive — operator flagged"

        let sig = SuppressEntry(
            category: report.category,
            textHash: Self.hash(text: report.text)
        )
        suppressedSignatures.append(sig)

        AuditLogger.shared.log(
            .observationLogged,
            detail: "threat_false_positive cat:\(report.category) hash:\(sig.textHash)"
        )
        saveReports()
        saveSuppressList()
    }

    /// Remove a suppression signature (operator wants the class of reports
    /// to resurface).
    public func unsuppress(_ entry: SuppressEntry) {
        suppressedSignatures.removeAll { $0.id == entry.id }
        saveSuppressList()
    }

    /// Update the confidence threshold for a category.
    public func setThreshold(_ value: Double, for category: String) {
        thresholds[category] = max(0, min(1, value))
    }

    /// Get reports by category
    public func reports(for category: ReportedThreatCategory) -> [ThreatReport] {
        reports.filter { $0.category == category.rawValue && !$0.resolved }
    }

    /// Mark report as resolved
    public func resolve(_ report: ThreatReport) {
        if let index = reports.firstIndex(where: { $0.id == report.id }) {
            reports[index].resolved = true
            saveReports()
        }
    }

    /// Unresolved threat count
    public var unresolvedCount: Int {
        reports.filter { !$0.resolved }.count
    }

    // MARK: - Persistence

    private func saveReports() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("threat_reports.json")
        if let data = try? JSONEncoder().encode(reports) {
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }

    public func loadReports() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("threat_reports.json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([ThreatReport].self, from: data) {
            self.reports = decoded
        }
    }

    private func saveSuppressList() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("threat_suppress_list.json")
        if let data = try? JSONEncoder().encode(suppressedSignatures) {
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }

    private func loadSuppressList() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("threat_suppress_list.json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([SuppressEntry].self, from: data) {
            self.suppressedSignatures = decoded
        }
        pruneExpiredSuppressions()
    }

    private func pruneExpiredSuppressions() {
        let cutoff = Date().addingTimeInterval(-suppressWindow)
        let before = suppressedSignatures.count
        suppressedSignatures.removeAll { $0.addedAt < cutoff }
        if suppressedSignatures.count != before { saveSuppressList() }
    }

    // MARK: - Helpers

    /// Normalized hash of the report text. Lowercased, whitespace-collapsed,
    /// SHA-256 → first 16 hex chars. Keeps false-positive matching tolerant
    /// to trivial reformatting without false-negatives on semantically
    /// identical reports.
    private static func hash(text: String) -> String {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
