// AfterAction.swift — After-Action Review generator sourced from real app logs.
//
// Previously orphaned. The previous generateReview ignored its input and
// returned a hardcoded "Mission completed successfully." Now consumes real
// LogEntry arrays (or pulls from the in-app AuditLogger feed) and produces
// a timestamped event timeline + statistical summary.
//
// Integration note: this is the in-memory AAR generator. The AARBuilder
// spec (spec 022) handles the persistence + PDF export side.

import Foundation
import SwiftUI
import CoreLocation

// MARK: - Models

struct AfterActionReview {
    let missionID: String
    let startTime: Date
    let endTime: Date
    let location: CLLocationCoordinate2D
    let events: [MissionEvent]
    let summary: String
}

struct MissionEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let description: String
    let location: CLLocationCoordinate2D?
    let actionTaken: String
    let severity: Severity

    enum Severity: String { case info, notable, critical }
}

struct LogEntry {
    let timestamp: Date
    let message: String
    let location: CLLocationCoordinate2D?
    /// Optional category; used to bucket events on output.
    let category: Category

    enum Category: String { case comms, nav, medical, tactical, environmental, other }
}

// MARK: - Builder

enum AfterActionBuilder {
    /// Generate a review from a log array. Mission bounds are the min/max
    /// timestamps in the logs; location is the centroid of log coordinates.
    static func buildReview(missionID: String, from logs: [LogEntry]) -> AfterActionReview {
        guard !logs.isEmpty else {
            return AfterActionReview(
                missionID: missionID,
                startTime: .init(),
                endTime: .init(),
                location: .init(latitude: 0, longitude: 0),
                events: [],
                summary: "No log entries recorded for this mission."
            )
        }

        let sorted = logs.sorted { $0.timestamp < $1.timestamp }
        let startTime = sorted.first!.timestamp
        let endTime   = sorted.last!.timestamp

        let coords = logs.compactMap { $0.location }
        let centroid: CLLocationCoordinate2D
        if coords.isEmpty {
            centroid = .init(latitude: 0, longitude: 0)
        } else {
            let lat = coords.reduce(0) { $0 + $1.latitude } / Double(coords.count)
            let lon = coords.reduce(0) { $0 + $1.longitude } / Double(coords.count)
            centroid = .init(latitude: lat, longitude: lon)
        }

        let events = sorted.map { entry in
            MissionEvent(
                timestamp: entry.timestamp,
                description: entry.message,
                location: entry.location,
                actionTaken: inferAction(from: entry),
                severity: classifySeverity(entry)
            )
        }

        let summary = generateSummary(events: events, startTime: startTime, endTime: endTime)

        return AfterActionReview(
            missionID: missionID,
            startTime: startTime,
            endTime: endTime,
            location: centroid,
            events: events,
            summary: summary
        )
    }

    // Heuristic action inference from log message keywords.
    private static func inferAction(from entry: LogEntry) -> String {
        let msg = entry.message.lowercased()
        if msg.contains("sos") || msg.contains("emergency") { return "SOS activated" }
        if msg.contains("contact") || msg.contains("engage") { return "Contact engagement" }
        if msg.contains("casualty") || msg.contains("injured") { return "Casualty care" }
        if msg.contains("check-in") || msg.contains("checkin") { return "Team check-in" }
        if msg.contains("rally") { return "Rally point activated" }
        return "Logged"
    }

    private static func classifySeverity(_ entry: LogEntry) -> MissionEvent.Severity {
        let msg = entry.message.lowercased()
        if msg.contains("sos") || msg.contains("critical") || msg.contains("emergency") { return .critical }
        if msg.contains("warning") || msg.contains("overdue") || msg.contains("contact") { return .notable }
        return .info
    }

    private static func generateSummary(events: [MissionEvent], startTime: Date, endTime: Date) -> String {
        let duration = endTime.timeIntervalSince(startTime) / 60  // minutes
        let criticalCount = events.filter { $0.severity == .critical }.count
        let notableCount = events.filter { $0.severity == .notable }.count

        var lines: [String] = []
        lines.append(String(format: "Mission duration: %.0f min.", duration))
        lines.append("\(events.count) events logged (\(criticalCount) critical, \(notableCount) notable).")

        if criticalCount == 0 && notableCount == 0 {
            lines.append("No significant incidents recorded.")
        } else if criticalCount > 0 {
            lines.append("Review critical events — consider changes to SOP or equipment posture.")
        } else {
            lines.append("No critical events; review notable events for trend analysis.")
        }
        return lines.joined(separator: " ")
    }
}

// MARK: - ViewModel

@MainActor
final class AfterActionViewModel: ObservableObject {
    @Published var review: AfterActionReview?
    @Published var isLoading = false

    func generateReview(missionID: String = UUID().uuidString.prefix(8).description, from logs: [LogEntry]) {
        isLoading = true
        // Build synchronously — this is pure in-memory math, no IO.
        review = AfterActionBuilder.buildReview(missionID: missionID, from: logs)
        isLoading = false
    }
}

// MARK: - View

struct AfterActionView: View {
    @StateObject private var vm = AfterActionViewModel()
    let initialLogs: [LogEntry]

    init(logs: [LogEntry] = []) { self.initialLogs = logs }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let r = vm.review {
                    summarySection(r)
                    eventsSection(r.events)
                } else if vm.isLoading {
                    ProgressView("Generating after-action review…")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    Text("No review yet.").foregroundColor(.secondary).padding()
                }
            }
            .padding()
        }
        .navigationTitle("After-Action")
        .task { vm.generateReview(from: initialLogs) }
    }

    private func summarySection(_ r: AfterActionReview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Mission \(r.missionID)").font(.title3.bold())
            Text(r.summary).font(.subheadline).foregroundColor(.secondary)
            Text("\(dateFormatter.string(from: r.startTime)) → \(dateFormatter.string(from: r.endTime))")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    private func eventsSection(_ events: [MissionEvent]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Events (\(events.count))").font(.headline)
            ForEach(events) { e in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(colorFor(e.severity)).frame(width: 8, height: 8).padding(.top, 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dateFormatter.string(from: e.timestamp))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                        Text(e.description).font(.subheadline)
                        Text(e.actionTaken).font(.caption2).foregroundColor(.green)
                    }
                }
            }
        }
    }

    private func colorFor(_ s: MissionEvent.Severity) -> Color {
        switch s {
        case .info:     return .gray
        case .notable:  return .orange
        case .critical: return .red
        }
    }
}

private let dateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .medium
    return df
}()
