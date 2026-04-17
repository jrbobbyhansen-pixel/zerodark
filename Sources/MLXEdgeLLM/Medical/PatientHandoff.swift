// PatientHandoff.swift — SBAR Patient Handoff Report
// Situation → Background → Assessment → Recommendation
// Tracks vitals history, treatments, exports formatted report

import Foundation
import SwiftUI

// MARK: - Handoff Models

struct HandoffVital: Identifiable, Codable {
    let id: UUID
    let type: String
    let value: String
    let timestamp: Date

    init(type: String, value: String) {
        self.id = UUID()
        self.type = type
        self.value = value
        self.timestamp = Date()
    }
}

struct HandoffTreatment: Identifiable, Codable {
    let id: UUID
    let description: String
    let provider: String
    let timestamp: Date

    init(description: String, provider: String = AppConfig.deviceCallsign) {
        self.id = UUID()
        self.description = description
        self.provider = provider
        self.timestamp = Date()
    }
}

// MARK: - PatientHandoffViewModel

@MainActor
final class PatientHandoffViewModel: ObservableObject {
    @Published var patientName = ""
    @Published var patientAge = ""
    @Published var gender = ""
    @Published var mechanism = ""

    // SBAR fields
    @Published var situation = ""      // S — What's happening right now
    @Published var background = ""     // B — Relevant history, allergies, meds
    @Published var assessment = ""     // A — What I think is wrong
    @Published var recommendation = "" // R — What I need / suggest

    @Published var vitals: [HandoffVital] = []
    @Published var treatments: [HandoffTreatment] = []
    @Published var exportURL: URL?

    func addVital(type: String, value: String) {
        guard !type.isEmpty, !value.isEmpty else { return }
        vitals.append(HandoffVital(type: type, value: value))
    }

    func addTreatment(description: String) {
        guard !description.isEmpty else { return }
        treatments.append(HandoffTreatment(description: description))
    }

    func formattedSBAR() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        var report = """
        ═══════════════════════════════════
        SBAR PATIENT HANDOFF
        ═══════════════════════════════════
        Patient: \(patientName.isEmpty ? "(Unknown)" : patientName)
        Age: \(patientAge.isEmpty ? "UNK" : patientAge)  Gender: \(gender.isEmpty ? "UNK" : gender)
        Mechanism: \(mechanism.isEmpty ? "(Not specified)" : mechanism)
        Report Time: \(formatter.string(from: Date()))
        From: \(AppConfig.deviceCallsign)

        ── S — SITUATION ──
        \(situation.isEmpty ? "(Not specified)" : situation)

        ── B — BACKGROUND ──
        \(background.isEmpty ? "(Not specified)" : background)

        ── A — ASSESSMENT ──
        \(assessment.isEmpty ? "(Not specified)" : assessment)

        ── R — RECOMMENDATION ──
        \(recommendation.isEmpty ? "(Not specified)" : recommendation)

        """

        if !vitals.isEmpty {
            report += "── VITAL SIGNS HISTORY ──\n"
            for v in vitals {
                report += "  \(formatter.string(from: v.timestamp)): \(v.type) = \(v.value)\n"
            }
            report += "\n"
        }

        if !treatments.isEmpty {
            report += "── TREATMENTS ──\n"
            for t in treatments {
                report += "  \(formatter.string(from: t.timestamp)): \(t.description) (by \(t.provider))\n"
            }
            report += "\n"
        }

        report += "═══════════════════════════════════"
        return report
    }

    func export() {
        let report = formattedSBAR()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("SBAR_Handoff.txt")
        try? report.write(to: tempURL, atomically: true, encoding: .utf8)
        exportURL = tempURL
        AuditLogger.shared.log(.reportExported, detail: "SBAR handoff exported")
    }
}

// MARK: - PatientHandoffView

struct PatientHandoffView: View {
    @StateObject private var vm = PatientHandoffViewModel()
    @State private var showAddVital = false
    @State private var showAddTreatment = false
    @State private var newVitalType = ""
    @State private var newVitalValue = ""
    @State private var newTreatment = ""

    var body: some View {
        Form {
            Section("Patient Info") {
                TextField("Name / ID", text: $vm.patientName)
                HStack {
                    TextField("Age", text: $vm.patientAge).keyboardType(.numberPad).frame(width: 60)
                    Picker("Gender", selection: $vm.gender) {
                        Text("—").tag("")
                        Text("M").tag("M")
                        Text("F").tag("F")
                    }.pickerStyle(.segmented)
                }
                TextField("Mechanism of Injury", text: $vm.mechanism)
            }

            Section("S — Situation") {
                TextEditor(text: $vm.situation).frame(minHeight: 50)
                    .font(.body)
            }

            Section("B — Background") {
                TextEditor(text: $vm.background).frame(minHeight: 50)
                    .font(.body)
            }

            Section("A — Assessment") {
                TextEditor(text: $vm.assessment).frame(minHeight: 50)
                    .font(.body)
            }

            Section("R — Recommendation") {
                TextEditor(text: $vm.recommendation).frame(minHeight: 50)
                    .font(.body)
            }

            // Vitals
            Section("Vital Signs (\(vm.vitals.count))") {
                ForEach(vm.vitals) { v in
                    HStack {
                        Text(v.type).font(.caption.bold())
                        Text(v.value).font(.caption)
                        Spacer()
                        Text(v.timestamp, style: .time).font(.caption2).foregroundColor(.secondary)
                    }
                }
                HStack {
                    TextField("Type (HR, BP...)", text: $newVitalType).frame(maxWidth: 100)
                    TextField("Value", text: $newVitalValue)
                    Button {
                        vm.addVital(type: newVitalType, value: newVitalValue)
                        newVitalType = ""; newVitalValue = ""
                    } label: {
                        Image(systemName: "plus.circle.fill").foregroundColor(ZDDesign.cyanAccent)
                    }
                    .disabled(newVitalType.isEmpty || newVitalValue.isEmpty)
                }
            }

            // Treatments
            Section("Treatments (\(vm.treatments.count))") {
                ForEach(vm.treatments) { t in
                    HStack {
                        Text(t.description).font(.caption)
                        Spacer()
                        Text(t.timestamp, style: .time).font(.caption2).foregroundColor(.secondary)
                    }
                }
                HStack {
                    TextField("Treatment description", text: $newTreatment)
                    Button {
                        vm.addTreatment(description: newTreatment)
                        newTreatment = ""
                    } label: {
                        Image(systemName: "plus.circle.fill").foregroundColor(ZDDesign.cyanAccent)
                    }
                    .disabled(newTreatment.isEmpty)
                }
            }

            Section {
                Button {
                    vm.export()
                } label: {
                    Label("Export SBAR Handoff", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ZDDesign.cyanAccent)
            }
        }
        .navigationTitle("Patient Handoff")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $vm.exportURL) { url in
            ShareSheet(items: [url])
        }
    }
}

#Preview {
    NavigationStack { PatientHandoffView() }
}
