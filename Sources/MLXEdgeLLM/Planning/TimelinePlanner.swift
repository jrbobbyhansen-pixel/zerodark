// TimelinePlanner.swift — Mission Timeline with phase tracking + sharing

import Foundation
import SwiftUI

// MARK: - MissionPhase

struct MissionPhase: Identifiable, Codable {
    let id: UUID
    var name: String
    var plannedStart: Date
    var noLaterThan: Date
    var actualStart: Date?
    var actualEnd: Date?
    var notes: String

    init(name: String, plannedStart: Date, noLaterThan: Date, notes: String = "") {
        self.id = UUID()
        self.name = name
        self.plannedStart = plannedStart
        self.noLaterThan = noLaterThan
        self.notes = notes
    }

    var isOverdue: Bool {
        guard actualStart == nil else { return false }
        return Date() > noLaterThan
    }

    var isActive: Bool {
        actualStart != nil && actualEnd == nil
    }

    var statusLabel: String {
        if let end = actualEnd { return "Complete" }
        if actualStart != nil { return "In Progress" }
        if isOverdue { return "OVERDUE" }
        return "Pending"
    }

    var statusColor: Color {
        if actualEnd != nil { return .green }
        if actualStart != nil { return ZDDesign.cyanAccent }
        if isOverdue { return .red }
        return .secondary
    }
}

// MARK: - TimelineViewModel

@MainActor
final class TimelineViewModel: ObservableObject {
    @Published var phases: [MissionPhase] = []
    @Published var exportURL: URL?

    func addPhase(name: String, plannedStart: Date, noLaterThan: Date, notes: String = "") {
        guard !name.isEmpty else { return }
        phases.append(MissionPhase(name: name, plannedStart: plannedStart, noLaterThan: noLaterThan, notes: notes))
        phases.sort { $0.plannedStart < $1.plannedStart }
    }

    func startPhase(_ phase: MissionPhase) {
        guard let idx = phases.firstIndex(where: { $0.id == phase.id }) else { return }
        phases[idx].actualStart = Date()
    }

    func completePhase(_ phase: MissionPhase) {
        guard let idx = phases.firstIndex(where: { $0.id == phase.id }) else { return }
        phases[idx].actualEnd = Date()
    }

    func remove(at offsets: IndexSet) {
        phases.remove(atOffsets: offsets)
    }

    func shareTimeline() {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        var text = "MISSION TIMELINE\n═══════════════\n\n"
        for (i, p) in phases.enumerated() {
            text += "\(i+1). \(p.name) [\(p.statusLabel)]\n"
            text += "   Planned: \(formatter.string(from: p.plannedStart))\n"
            text += "   NLT: \(formatter.string(from: p.noLaterThan))\n"
            if let start = p.actualStart {
                text += "   Actual Start: \(formatter.string(from: start))\n"
            }
            if let end = p.actualEnd {
                text += "   Completed: \(formatter.string(from: end))\n"
            }
            if !p.notes.isEmpty { text += "   Notes: \(p.notes)\n" }
            text += "\n"
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MissionTimeline.txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        exportURL = url
    }
}

// MARK: - TimelineView (renamed from TimelinePlanner to avoid name conflict)

struct TimelinePlannerView: View {
    @StateObject private var vm = TimelineViewModel()
    @State private var showAdd = false
    @State private var newName = ""
    @State private var newStart = Date()
    @State private var newNLT = Date().addingTimeInterval(3600)
    @State private var newNotes = ""

    var body: some View {
        List {
            if !vm.phases.isEmpty {
                Section("Phases (\(vm.phases.count))") {
                    ForEach(vm.phases) { phase in
                        HStack(spacing: 12) {
                            Circle().fill(phase.statusColor).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(phase.name).font(.headline)
                                Text(phase.statusLabel)
                                    .font(.caption.bold())
                                    .foregroundColor(phase.statusColor)
                                if phase.isActive, let start = phase.actualStart {
                                    Text("Started \(start, style: .relative) ago")
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if phase.actualStart == nil {
                                Button("Start") { vm.startPhase(phase) }
                                    .buttonStyle(.bordered).tint(ZDDesign.cyanAccent).controlSize(.small)
                            } else if phase.actualEnd == nil {
                                Button("Done") { vm.completePhase(phase) }
                                    .buttonStyle(.bordered).tint(.green).controlSize(.small)
                            } else {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            }
                        }
                    }
                    .onDelete { vm.remove(at: $0) }
                }

                Section {
                    Button { vm.shareTimeline() } label: {
                        Label("Share Timeline", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                }
            }

            Section("Add Phase") {
                TextField("Phase name", text: $newName)
                DatePicker("Planned Start", selection: $newStart, displayedComponents: [.date, .hourAndMinute])
                DatePicker("No Later Than", selection: $newNLT, displayedComponents: [.date, .hourAndMinute])
                TextField("Notes (optional)", text: $newNotes)
                Button {
                    vm.addPhase(name: newName, plannedStart: newStart, noLaterThan: newNLT, notes: newNotes)
                    newName = ""; newNotes = ""
                    newStart = Date()
                    newNLT = Date().addingTimeInterval(3600)
                } label: {
                    Label("Add Phase", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(ZDDesign.cyanAccent)
                .disabled(newName.isEmpty)
            }
        }
        .navigationTitle("Mission Timeline")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $vm.exportURL) { url in
            ShareSheet(items: [url])
        }
    }
}

#Preview {
    NavigationStack { TimelinePlannerView() }
}
