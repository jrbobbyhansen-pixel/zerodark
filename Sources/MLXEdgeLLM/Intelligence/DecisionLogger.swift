// DecisionLogger.swift — AI decision audit trail
// Logs inference decisions with reasoning for review and accountability

import Foundation
import SwiftUI

// MARK: - DecisionLogEntry

struct DecisionLogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let reason: String
    let context: String    // What inputs were considered
    let outcome: String    // What was decided/output
    let confidence: Double // 0-1 confidence level

    init(reason: String, context: String, outcome: String, confidence: Double = 1.0) {
        self.id = UUID()
        self.timestamp = Date()
        self.reason = reason
        self.context = context
        self.outcome = outcome
        self.confidence = min(1.0, max(0, confidence))
    }
}

// MARK: - DecisionLogger

@MainActor
final class DecisionLogger: ObservableObject {
    static let shared = DecisionLogger()

    @Published var logs: [DecisionLogEntry] = []

    private init() {}

    func logDecision(reason: String, context: String, outcome: String, confidence: Double = 1.0) {
        let entry = DecisionLogEntry(reason: reason, context: context, outcome: outcome, confidence: confidence)
        logs.append(entry)
        // Keep last 500 entries
        if logs.count > 500 { logs.removeFirst(logs.count - 500) }
    }

    func clear() {
        logs.removeAll()
    }

    func exportText() -> String {
        let fmt = ISO8601DateFormatter()
        var text = "DECISION LOG\n════════════\n\n"
        for entry in logs {
            text += "[\(fmt.string(from: entry.timestamp))] \(entry.reason)\n"
            text += "  Context: \(entry.context)\n"
            text += "  Outcome: \(entry.outcome)\n"
            text += "  Confidence: \(String(format: "%.0f", entry.confidence * 100))%\n\n"
        }
        return text
    }
}

// MARK: - DecisionLogView

struct DecisionLogView: View {
    @StateObject private var logger = DecisionLogger.shared

    var body: some View {
        List {
            if logger.logs.isEmpty {
                ContentUnavailableView("No Decisions Logged", systemImage: "brain", description: Text("AI decisions will appear here as they are made."))
            } else {
                ForEach(logger.logs.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.reason).font(.headline)
                            Spacer()
                            Text("\(String(format: "%.0f", entry.confidence * 100))%")
                                .font(.caption.bold())
                                .foregroundColor(entry.confidence > 0.7 ? .green : .orange)
                        }
                        Text(entry.context).font(.caption).foregroundColor(.secondary)
                        Text(entry.outcome).font(.caption)
                        Text(entry.timestamp, style: .relative).font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Decision Log")
        .toolbar {
            if !logger.logs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { logger.clear() } label: {
                        Label("Clear", systemImage: "trash")
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack { DecisionLogView() }
}
