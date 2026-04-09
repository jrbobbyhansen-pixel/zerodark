// OpOrderBuilder.swift — Military Operations Order (OPORD) builder
// Exports to PDF (UIGraphicsPDFRenderer) + JSON for TAK ingestion
// Full 5-paragraph OPORD format: Situation, Mission, Execution, Support, Command

import Foundation
import SwiftUI
import UIKit

// MARK: - Mission Types

enum MissionType: String, CaseIterable, Codable {
    case reconnaissance = "Reconnaissance"
    case assault        = "Assault"
    case extraction     = "Extraction"
    case support        = "Support"
    case patrol         = "Patrol"
    case security       = "Security"
    case evacuation     = "Evacuation"
    case searchRescue   = "Search & Rescue"
}

// MARK: - Objective

struct Objective: Identifiable, Codable {
    let id: UUID
    let description: String
    let priority: Int
    let type: ObjectiveType

    enum ObjectiveType: String, Codable, CaseIterable {
        case primary    = "Primary"
        case secondary  = "Secondary"
        case tertiary   = "Tertiary"
    }

    init(description: String, priority: Int = 1, type: ObjectiveType = .primary) {
        self.id = UUID()
        self.description = description
        self.priority = priority
        self.type = type
    }
}

// MARK: - OpOrder

struct OpOrder: Codable {
    var orderNumber: String
    var classification: String
    var issuedBy: String
    var issuedAt: Date
    var missionType: MissionType
    var objectives: [Objective]

    // 5-paragraph OPORD
    var situation: String       // Para 1: Enemy/friendly forces, terrain, weather
    var mission: String         // Para 2: Who, what, where, when, why (5Ws)
    var execution: String       // Para 3: Concept of ops, tasks, coordinating instructions
    var serviceSupport: String  // Para 4: Logistics, medical, comms
    var commandSignal: String   // Para 5: Command relationships, signals, comms plan

    var acknowledgments: [String]

    init() {
        orderNumber = "OPORD-\(Int(Date().timeIntervalSince1970))"
        classification = "FOR OFFICIAL USE ONLY"
        issuedBy = AppConfig.deviceCallsign
        issuedAt = Date()
        missionType = .patrol
        objectives = []
        situation = ""
        mission = ""
        execution = ""
        serviceSupport = ""
        commandSignal = ""
        acknowledgments = []
    }
}

// MARK: - OpOrderBuilder

@MainActor
final class OpOrderBuilder: ObservableObject {
    static let shared = OpOrderBuilder()

    @Published var order = OpOrder()
    @Published var isSaving = false

    private init() {}

    // MARK: - Objective Management

    func addObjective(_ objective: Objective) {
        order.objectives.append(objective)
        order.objectives.sort { $0.priority < $1.priority }
    }

    func removeObjective(at offsets: IndexSet) {
        order.objectives.remove(atOffsets: offsets)
    }

    func trackAcknowledgment(_ callsign: String) {
        if !order.acknowledgments.contains(callsign) {
            order.acknowledgments.append(callsign)
        }
    }

    // MARK: - Export: Text

    func exportOrderText() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        var text = "\(order.classification)\n\n"
        text += "OPERATIONS ORDER \(order.orderNumber)\n"
        text += "Issued by: \(order.issuedBy)\n"
        text += "DTG: \(formatter.string(from: order.issuedAt))\n"
        text += "Mission Type: \(order.missionType.rawValue)\n\n"
        text += "PARAGRAPH 1 — SITUATION\n\(order.situation.isEmpty ? "(Not specified)" : order.situation)\n\n"
        text += "PARAGRAPH 2 — MISSION\n\(order.mission.isEmpty ? "(Not specified)" : order.mission)\n\n"
        text += "PARAGRAPH 3 — EXECUTION\n"
        if !order.objectives.isEmpty {
            text += "Objectives:\n"
            for (i, obj) in order.objectives.enumerated() {
                text += "  \(i+1). [\(obj.type.rawValue)] \(obj.description)\n"
            }
            text += "\n"
        }
        text += order.execution.isEmpty ? "(Not specified)\n\n" : "\(order.execution)\n\n"
        text += "PARAGRAPH 4 — SERVICE & SUPPORT\n\(order.serviceSupport.isEmpty ? "(Not specified)" : order.serviceSupport)\n\n"
        text += "PARAGRAPH 5 — COMMAND & SIGNAL\n\(order.commandSignal.isEmpty ? "(Not specified)" : order.commandSignal)\n\n"
        if !order.acknowledgments.isEmpty {
            text += "ACKNOWLEDGED BY: \(order.acknowledgments.joined(separator: ", "))\n"
        }
        text += "\n\(order.classification)"
        return text
    }

    // MARK: - Export: PDF

    func exportOrderPDF() -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842)) // A4

        return renderer.pdfData { ctx in
            ctx.beginPage()

            let titleAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 16),
                .foregroundColor: UIColor.black
            ]
            let bodyAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: UIColor.black
            ]
            let headerAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 12),
                .foregroundColor: UIColor.black
            ]

            let margin: CGFloat = 40
            var y: CGFloat = margin

            func drawText(_ text: String, attrs: [NSAttributedString.Key: Any], maxWidth: CGFloat = 515) -> CGFloat {
                let str = NSAttributedString(string: text, attributes: attrs)
                let rect = CGRect(x: margin, y: y, width: maxWidth, height: 600)
                str.draw(in: rect)
                let size = str.boundingRect(with: CGSize(width: maxWidth, height: 600), options: [.usesLineFragmentOrigin], context: nil)
                return size.height + 6
            }

            y += drawText(order.classification, attrs: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.red])
            y += drawText("OPERATIONS ORDER \(order.orderNumber)", attrs: titleAttr)
            y += drawText("Issued by: \(order.issuedBy)", attrs: bodyAttr)
            y += 10

            let paragraphs: [(String, String)] = [
                ("1. SITUATION", order.situation),
                ("2. MISSION", order.mission),
                ("3. EXECUTION", buildExecutionText()),
                ("4. SERVICE & SUPPORT", order.serviceSupport),
                ("5. COMMAND & SIGNAL", order.commandSignal),
            ]

            for (header, body) in paragraphs {
                if y > 780 { ctx.beginPage(); y = margin }
                y += drawText(header, attrs: headerAttr)
                y += drawText(body.isEmpty ? "(Not specified)" : body, attrs: bodyAttr)
                y += 8
            }

            if !order.acknowledgments.isEmpty {
                if y > 760 { ctx.beginPage(); y = margin }
                y += drawText("ACKNOWLEDGED BY: \(order.acknowledgments.joined(separator: ", "))", attrs: bodyAttr)
            }

            y += 10
            drawText(order.classification, attrs: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.red])
        }
    }

    private func buildExecutionText() -> String {
        var text = order.execution
        if !order.objectives.isEmpty {
            text = "Objectives:\n" + order.objectives.enumerated()
                .map { "  \($0+1). [\($1.type.rawValue)] \($1.description)" }
                .joined(separator: "\n")
            if !order.execution.isEmpty { text += "\n\n" + order.execution }
        }
        return text
    }

    // MARK: - Export: JSON (TAK-compatible)

    func exportOrderJSON() -> Data? {
        try? JSONEncoder().encode(order)
    }

    // MARK: - Share

    func presentShareSheet(from viewController: UIViewController? = nil) {
        isSaving = true
        defer { isSaving = false }

        let tempDir = FileManager.default.temporaryDirectory
        let ts = Int(Date().timeIntervalSince1970)

        // PDF
        let pdfURL = tempDir.appendingPathComponent("OPORD-\(ts).pdf")
        try? exportOrderPDF().write(to: pdfURL)

        // JSON
        let jsonURL = tempDir.appendingPathComponent("OPORD-\(ts).json")
        if let jsonData = exportOrderJSON() { try? jsonData.write(to: jsonURL) }

        var items: [Any] = [pdfURL]
        if FileManager.default.fileExists(atPath: jsonURL.path) { items.append(jsonURL) }

        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        let vc = viewController ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.rootViewController
        vc?.present(av, animated: true)

        AuditLogger.shared.log(.reportExported, detail: "OPORD \(order.orderNumber) PDF+JSON")
    }
}

// MARK: - OpOrderBuilderView

struct OpOrderBuilderView: View {
    @StateObject private var vm = OpOrderBuilder.shared
    @State private var newObjective = ""
    @State private var objectiveType: Objective.ObjectiveType = .primary

    var body: some View {
        List {
            Section("Order Identity") {
                LabeledContent("Order #", value: vm.order.orderNumber)
                    .font(.caption.monospaced())
                Picker("Mission Type", selection: $vm.order.missionType) {
                    ForEach(MissionType.allCases, id: \.self) { type in Text(type.rawValue) }
                }
            }

            Section("Situation (Para 1)") {
                TextEditor(text: $vm.order.situation)
                    .frame(minHeight: 80)
                    .font(.body)
            }

            Section("Mission (Para 2)") {
                TextEditor(text: $vm.order.mission)
                    .frame(minHeight: 80)
            }

            Section("Objectives") {
                ForEach(vm.order.objectives) { obj in
                    HStack {
                        Text("[\(obj.type.rawValue)]").font(.caption).foregroundColor(.secondary)
                        Text(obj.description)
                    }
                }
                .onDelete { vm.removeObjective(at: $0) }

                HStack {
                    TextField("New objective", text: $newObjective)
                    Picker("", selection: $objectiveType) {
                        ForEach(Objective.ObjectiveType.allCases, id: \.self) { t in Text(t.rawValue.prefix(3)) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 100)
                    Button {
                        vm.addObjective(Objective(description: newObjective, type: objectiveType))
                        newObjective = ""
                    } label: {
                        Image(systemName: "plus.circle.fill").foregroundColor(ZDDesign.cyanAccent)
                    }
                    .disabled(newObjective.isEmpty)
                }
            }

            Section("Execution (Para 3)") {
                TextEditor(text: $vm.order.execution).frame(minHeight: 60)
            }

            Section("Service & Support (Para 4)") {
                TextEditor(text: $vm.order.serviceSupport).frame(minHeight: 60)
            }

            Section("Command & Signal (Para 5)") {
                TextEditor(text: $vm.order.commandSignal).frame(minHeight: 60)
            }

            Section {
                Button {
                    vm.presentShareSheet()
                } label: {
                    Label("Export OPORD (PDF + JSON)", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ZDDesign.cyanAccent)
                .disabled(vm.isSaving)
            }
        }
        .navigationTitle("Op Order Builder")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack { OpOrderBuilderView() }
}
