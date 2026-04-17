// TriageSystem.swift — Interactive START/JumpSTART Triage Algorithm
// Walks through the decision tree: Walk → Breathe → Rate → Perfusion → Mental Status
// Tracks multiple casualties, color-coded priority, METHANE report export

import Foundation
import SwiftUI

// MARK: - Triage Category

enum TriageCategory: String, CaseIterable, Codable {
    case immediate = "IMMEDIATE"   // P1 — Red
    case delayed   = "DELAYED"     // P2 — Yellow
    case minor     = "MINOR"       // P3 — Green
    case expectant = "EXPECTANT"   // P4 — Black

    var color: Color {
        switch self {
        case .immediate: return .red
        case .delayed:   return .yellow
        case .minor:     return .green
        case .expectant: return .black
        }
    }

    var displayColor: Color {
        switch self {
        case .expectant: return .white
        default: return .black
        }
    }

    var icon: String {
        switch self {
        case .immediate: return "exclamationmark.triangle.fill"
        case .delayed:   return "clock.fill"
        case .minor:     return "figure.walk"
        case .expectant: return "xmark.circle.fill"
        }
    }

    var description: String {
        switch self {
        case .immediate: return "Life-threatening, survivable with immediate intervention"
        case .delayed:   return "Serious but can wait 4+ hours"
        case .minor:     return "Walking wounded — ambulatory"
        case .expectant: return "Unsurvivable or deceased"
        }
    }
}

// MARK: - Casualty

struct Casualty: Identifiable, Codable {
    let id: UUID
    var label: String
    var category: TriageCategory
    var notes: String
    var taggedAt: Date

    init(label: String, category: TriageCategory, notes: String = "") {
        self.id = UUID()
        self.label = label
        self.category = category
        self.notes = notes
        self.taggedAt = Date()
    }
}

// MARK: - START Triage Step

enum StartTriageStep: String {
    case canWalk       = "Can the patient walk?"
    case isBreathing   = "Is the patient breathing?"
    case repositioned  = "After repositioning airway, breathing now?"
    case respRate      = "Respiratory rate > 30/min?"
    case perfusion     = "Radial pulse absent OR cap refill > 2 sec?"
    case mentalStatus  = "Can the patient follow simple commands?"
    case complete      = "Triage Complete"
}

// MARK: - TriageSystem

@MainActor
final class TriageSystem: ObservableObject {
    static let shared = TriageSystem()

    @Published var casualties: [Casualty] = []

    var counts: [TriageCategory: Int] {
        Dictionary(grouping: casualties, by: \.category).mapValues(\.count)
    }

    func addCasualty(_ casualty: Casualty) {
        casualties.append(casualty)
        AuditLogger.shared.log(.triagePerformed, detail: "tagged:\(casualty.label) → \(casualty.category.rawValue)")
    }

    func removeCasualty(at offsets: IndexSet) {
        casualties.remove(atOffsets: offsets)
    }

    func generateMETHANE(incidentType: String, location: String, hazards: String, access: String) -> String {
        let imm = counts[.immediate] ?? 0
        let del = counts[.delayed] ?? 0
        let min = counts[.minor] ?? 0
        let exp = counts[.expectant] ?? 0
        let total = casualties.count

        return """
        ═══════════════════════════════════
        METHANE INCIDENT REPORT
        ═══════════════════════════════════
        M — MAJOR INCIDENT DECLARED
        E — EXACT LOCATION: \(location.isEmpty ? "(Not specified)" : location)
        T — TYPE: \(incidentType.isEmpty ? "(Not specified)" : incidentType)
        H — HAZARDS: \(hazards.isEmpty ? "(None identified)" : hazards)
        A — ACCESS/EGRESS: \(access.isEmpty ? "(Not specified)" : access)
        N — NUMBER OF CASUALTIES: \(total)
            P1 IMMEDIATE (Red):   \(imm)
            P2 DELAYED (Yellow):  \(del)
            P3 MINOR (Green):     \(min)
            P4 EXPECTANT (Black): \(exp)
        E — EMERGENCY SERVICES: (Specify on scene/required)
        ═══════════════════════════════════
        """
    }
}

// MARK: - START Triage Flow View

struct StartTriageFlowView: View {
    @Environment(\.dismiss) private var dismiss: DismissAction
    @ObservedObject var system: TriageSystem

    @State private var step: StartTriageStep = .canWalk
    @State private var casualtyLabel = ""
    @State private var result: TriageCategory?
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let result {
                    // Result screen
                    VStack(spacing: 16) {
                        Image(systemName: result.icon)
                            .font(.system(size: 60))
                            .foregroundColor(result.color)
                        Text(result.rawValue)
                            .font(.system(size: 32, weight: .black, design: .monospaced))
                            .foregroundColor(result.color)
                        Text(result.description)
                            .font(.subheadline).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        TextField("Casualty ID / Name", text: $casualtyLabel)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal, 40)

                        Button {
                            let label = casualtyLabel.isEmpty ? "Casualty \(system.casualties.count + 1)" : casualtyLabel
                            system.addCasualty(Casualty(label: label, category: result, notes: notes))
                            dismiss()
                        } label: {
                            Label("Tag & Save", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(result.color)
                        .padding(.horizontal, 40)
                    }
                } else {
                    // Question screen
                    Spacer()
                    Text("START TRIAGE")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)

                    Text(step.rawValue)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    HStack(spacing: 20) {
                        Button {
                            advanceYes()
                        } label: {
                            Label("YES", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)

                        Button {
                            advanceNo()
                        } label: {
                            Label("NO", systemImage: "xmark")
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                    .padding(.horizontal)
                    Spacer()
                }
            }
            .padding()
            .navigationTitle("START Triage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // START Algorithm Decision Tree
    private func advanceYes() {
        switch step {
        case .canWalk:      result = .minor               // Walking = P3
        case .isBreathing:  step = .respRate               // Breathing → check rate
        case .repositioned: step = .respRate               // Breathing after reposition → check rate
        case .respRate:     result = .immediate            // Rate >30 = P1
        case .perfusion:    result = .immediate            // No radial pulse = P1
        case .mentalStatus: result = .delayed              // Follows commands = P2
        case .complete:     break
        }
    }

    private func advanceNo() {
        switch step {
        case .canWalk:      step = .isBreathing            // Can't walk → check breathing
        case .isBreathing:  step = .repositioned           // Not breathing → reposition airway
        case .repositioned: result = .expectant            // Still not breathing after reposition = P4
        case .respRate:     step = .perfusion              // Rate ≤30 → check perfusion
        case .perfusion:    step = .mentalStatus           // Pulse present → check mental
        case .mentalStatus: result = .immediate            // Can't follow commands = P1
        case .complete:     break
        }
    }
}

// MARK: - TriageView

struct TriageView: View {
    @ObservedObject private var system = TriageSystem.shared
    @State private var showTriageFlow = false
    @State private var showMETHANE = false
    @State private var incidentType = ""
    @State private var location = ""
    @State private var hazards = ""
    @State private var access = ""

    var body: some View {
        Form {
            // Summary counts
            Section("Casualty Count") {
                HStack(spacing: 0) {
                    ForEach(TriageCategory.allCases, id: \.self) { cat in
                        VStack(spacing: 4) {
                            Text("\(system.counts[cat] ?? 0)")
                                .font(.title2.bold())
                            Text(cat.rawValue.prefix(3))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(cat.color.opacity(0.2))
                        .foregroundColor(cat == .expectant ? .primary : cat.color)
                    }
                }
                .cornerRadius(8)
            }

            // START Triage button
            Section {
                Button {
                    showTriageFlow = true
                } label: {
                    Label("Run START Triage", systemImage: "stethoscope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ZDDesign.signalRed)
            }

            // Casualty list
            if !system.casualties.isEmpty {
                Section("Tagged Casualties (\(system.casualties.count))") {
                    ForEach(system.casualties) { cas in
                        HStack(spacing: 12) {
                            Circle().fill(cas.category.color).frame(width: 14, height: 14)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cas.label).font(.headline)
                                Text(cas.category.rawValue)
                                    .font(.caption.bold())
                                    .foregroundColor(cas.category.color)
                            }
                            Spacer()
                            Text(cas.taggedAt, style: .time).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .onDelete { system.removeCasualty(at: $0) }
                }

                Section {
                    Button {
                        showMETHANE = true
                    } label: {
                        Label("Generate METHANE Report", systemImage: "doc.text.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle("START Triage")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showTriageFlow) {
            StartTriageFlowView(system: system)
        }
        .sheet(isPresented: $showMETHANE) {
            METHANEReportSheet(system: system)
        }
    }
}

// MARK: - METHANE Report Sheet

private struct METHANEReportSheet: View {
    @ObservedObject var system: TriageSystem
    @Environment(\.dismiss) private var dismiss: DismissAction
    @State private var incidentType = ""
    @State private var location = ""
    @State private var hazards = ""
    @State private var access = ""
    @State private var shareURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("Incident Details") {
                    TextField("Type of incident", text: $incidentType)
                    TextField("Exact location / grid", text: $location)
                    TextField("Hazards", text: $hazards)
                    TextField("Access / egress routes", text: $access)
                }

                Section {
                    Button {
                        let report = system.generateMETHANE(
                            incidentType: incidentType,
                            location: location,
                            hazards: hazards,
                            access: access
                        )
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("METHANE.txt")
                        try? report.write(to: tempURL, atomically: true, encoding: .utf8)
                        shareURL = tempURL
                    } label: {
                        Label("Export METHANE Report", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ZDDesign.cyanAccent)
                }
            }
            .navigationTitle("METHANE Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $shareURL) { url in
                ShareSheet(items: [url])
            }
        }
    }
}

#Preview {
    NavigationStack { TriageView() }
}
