// ThreatClassifier.swift — AI-powered threat classification (Boeing SDR-Hazards + Phi-3.5)

import Foundation

/// Threat classification singleton
@MainActor
public class ThreatClassifier: ObservableObject {
    public static let shared = ThreatClassifier()

    @Published public var reports: [ThreatReport] = []
    @Published public var isClassifying: Bool = false

    private init() {}

    /// Classify a free-text threat report using Phi-3.5
    public func classify(text: String, source: String, location: CodableCoordinate? = nil) async -> ThreatReport {
        isClassifying = true
        defer { isClassifying = false }

        // Build prompt for threat classification
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

        // Call Phi-3.5 via LocalInferenceEngine
        await LocalInferenceEngine.shared.generate(
            prompt: prompt,
            maxTokens: 100,
            onToken: { token in
                outputTokens += token
            },
            onComplete: {
                // Parse JSON response from accumulated tokens
                if let jsonData = outputTokens.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let cat = json["category"] as? String,
                   let conf = json["confidence"] as? Double {
                    classifiedCategory = cat
                    confidence = conf
                }
            }
        )

        let report = ThreatReport(
            source: source,
            text: text,
            category: classifiedCategory,
            confidence: confidence,
            location: location
        )

        // Store report
        reports.append(report)

        // Persist
        saveReports()

        return report
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

    /// Persist reports to Documents
    private func saveReports() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let reportsFile = documentsPath.appendingPathComponent("threat_reports.json")

        if let jsonData = try? JSONEncoder().encode(reports) {
            try? jsonData.write(to: reportsFile)
        }
    }

    /// Load reports from Documents
    public func loadReports() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let reportsFile = documentsPath.appendingPathComponent("threat_reports.json")

        if let jsonData = try? Data(contentsOf: reportsFile),
           let decoded = try? JSONDecoder().decode([ThreatReport].self, from: jsonData) {
            self.reports = decoded
        }
    }
}
