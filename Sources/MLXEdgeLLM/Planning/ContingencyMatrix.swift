// ContingencyMatrix.swift — If/Then contingency planning
// Define trigger conditions and response actions for mission planning

import Foundation
import SwiftUI

// MARK: - Models

struct ContingencyPlan: Identifiable, Codable {
    let id: UUID
    var trigger: String           // "If..."
    var response: String          // "Then..."
    var responsible: String       // Who executes
    var priority: ContingencyPriority
    var isTriggered: Bool

    init(trigger: String, response: String, responsible: String = "", priority: ContingencyPriority = .standard) {
        self.id = UUID()
        self.trigger = trigger
        self.response = response
        self.responsible = responsible
        self.priority = priority
        self.isTriggered = false
    }
}

enum ContingencyPriority: String, CaseIterable, Codable {
    case standard = "Standard"
    case high     = "High"
    case critical = "Critical"

    var color: Color {
        switch self {
        case .standard: return .blue
        case .high:     return .orange
        case .critical: return .red
        }
    }
}

// MARK: - ContingencyMatrix

@MainActor
final class ContingencyMatrix: ObservableObject {
    @Published var plans: [ContingencyPlan] = []

    private let persistURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("contingencies.json")
    }()

    init() { load() }

    func add(trigger: String, response: String, responsible: String, priority: ContingencyPriority) {
        guard !trigger.isEmpty, !response.isEmpty else { return }
        plans.append(ContingencyPlan(trigger: trigger, response: response, responsible: responsible, priority: priority))
        save()
    }

    func remove(at offsets: IndexSet) {
        plans.remove(atOffsets: offsets)
        save()
    }

    func markTriggered(_ plan: ContingencyPlan) {
        guard let idx = plans.firstIndex(where: { $0.id == plan.id }) else { return }
        plans[idx].isTriggered = true
        save()

        // Fire in-app alert
        NotificationCenter.default.post(
            name: Notification.Name("ZD.inAppAlert"),
            object: nil,
            userInfo: [
                "title": "Contingency Triggered",
                "body": "IF: \(plan.trigger) → THEN: \(plan.response)",
                "severity": plan.priority == .critical ? "critical" : "warning"
            ]
        )
        AuditLogger.shared.log(.credentialAccess, detail: "contingency_triggered:\(plan.trigger)")
    }

    func exportText() -> String {
        var text = "CONTINGENCY MATRIX\n══════════════════\n\n"
        for (i, p) in plans.enumerated() {
            let status = p.isTriggered ? "[TRIGGERED]" : "[READY]"
            text += "\(i+1). [\(p.priority.rawValue.uppercased())] \(status)\n"
            text += "   IF: \(p.trigger)\n"
            text += "   THEN: \(p.response)\n"
            text += "   WHO: \(p.responsible.isEmpty ? "(Unassigned)" : p.responsible)\n\n"
        }
        return text
    }

    func share() {
        let text = exportText()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Contingencies.txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.rootViewController?
            .present(av, animated: true)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(plans) else { return }
        try? data.write(to: persistURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: persistURL),
              let loaded = try? JSONDecoder().decode([ContingencyPlan].self, from: data) else { return }
        plans = loaded
    }
}

// MARK: - ContingencyMatrixView

struct ContingencyMatrixView: View {
    @StateObject private var matrix = ContingencyMatrix()
    @State private var showAdd = false
    @State private var newTrigger = ""
    @State private var newResponse = ""
    @State private var newResponsible = ""
    @State private var newPriority: ContingencyPriority = .standard

    var body: some View {
        Form {
            if !matrix.plans.isEmpty {
                Section("Contingencies (\(matrix.plans.count))") {
                    ForEach(matrix.plans) { plan in
                        HStack(spacing: 12) {
                            Circle().fill(plan.priority.color).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("IF:").font(.caption.bold()).foregroundColor(.secondary)
                                    Text(plan.trigger).font(.subheadline)
                                }
                                HStack {
                                    Text("THEN:").font(.caption.bold()).foregroundColor(.secondary)
                                    Text(plan.response).font(.subheadline)
                                }
                                if !plan.responsible.isEmpty {
                                    Text("Responsible: \(plan.responsible)")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if plan.isTriggered {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(ZDDesign.signalRed)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if !plan.isTriggered {
                                Button {
                                    matrix.markTriggered(plan)
                                } label: {
                                    Label("Trigger", systemImage: "bolt.fill")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                    .onDelete { matrix.remove(at: $0) }
                }

                Section {
                    Button { matrix.share() } label: {
                        Label("Export Contingencies", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                }
            }

            Section("Add Contingency") {
                TextField("IF... (trigger condition)", text: $newTrigger)
                TextField("THEN... (response action)", text: $newResponse)
                TextField("Responsible (optional)", text: $newResponsible)
                Picker("Priority", selection: $newPriority) {
                    ForEach(ContingencyPriority.allCases, id: \.self) { Text($0.rawValue) }
                }
                Button {
                    matrix.add(trigger: newTrigger, response: newResponse, responsible: newResponsible, priority: newPriority)
                    newTrigger = ""; newResponse = ""; newResponsible = ""
                } label: {
                    Label("Add Contingency", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(ZDDesign.safetyYellow)
                .disabled(newTrigger.isEmpty || newResponse.isEmpty)
            }
        }
        .navigationTitle("Contingency Matrix")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack { ContingencyMatrixView() }
}
