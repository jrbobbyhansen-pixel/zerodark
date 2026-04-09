// RiskMatrix.swift — Operational Risk Assessment Matrix
// User-editable, 5×5 probability × severity grid, persistent, exportable

import Foundation
import SwiftUI

// MARK: - Risk Level

enum RiskProbability: Int, CaseIterable, Codable {
    case rare = 1, unlikely, possible, likely, almostCertain

    var label: String {
        switch self {
        case .rare: return "Rare"
        case .unlikely: return "Unlikely"
        case .possible: return "Possible"
        case .likely: return "Likely"
        case .almostCertain: return "Almost Certain"
        }
    }
}

enum RiskSeverity: Int, CaseIterable, Codable {
    case negligible = 1, minor, moderate, major, catastrophic

    var label: String {
        switch self {
        case .negligible: return "Negligible"
        case .minor: return "Minor"
        case .moderate: return "Moderate"
        case .major: return "Major"
        case .catastrophic: return "Catastrophic"
        }
    }
}

// MARK: - Risk Entry

struct RiskEntry: Identifiable, Codable {
    let id: UUID
    var hazard: String
    var probability: RiskProbability
    var severity: RiskSeverity
    var mitigation: String

    init(hazard: String, probability: RiskProbability = .possible, severity: RiskSeverity = .moderate, mitigation: String = "") {
        self.id = UUID()
        self.hazard = hazard
        self.probability = probability
        self.severity = severity
        self.mitigation = mitigation
    }

    var riskScore: Int { probability.rawValue * severity.rawValue }

    var riskLevel: String {
        switch riskScore {
        case 1...4:   return "LOW"
        case 5...9:   return "MEDIUM"
        case 10...15: return "HIGH"
        default:      return "EXTREME"
        }
    }

    var riskColor: Color {
        switch riskScore {
        case 1...4:   return .green
        case 5...9:   return .yellow
        case 10...15: return .orange
        default:      return .red
        }
    }
}

// MARK: - RiskMatrixViewModel

@MainActor
final class RiskMatrixViewModel: ObservableObject {
    @Published var risks: [RiskEntry] = []

    private let persistURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("risk_matrix.json")
    }()

    init() { load() }

    func add(hazard: String, probability: RiskProbability, severity: RiskSeverity, mitigation: String) {
        guard !hazard.isEmpty else { return }
        risks.append(RiskEntry(hazard: hazard, probability: probability, severity: severity, mitigation: mitigation))
        save()
    }

    func remove(at offsets: IndexSet) {
        risks.remove(atOffsets: offsets)
        save()
    }

    func exportText() -> String {
        var text = "OPERATIONAL RISK ASSESSMENT\n"
        text += "══════════════════════════\n\n"
        for (i, r) in risks.enumerated() {
            text += "\(i+1). \(r.hazard)\n"
            text += "   Probability: \(r.probability.label) | Severity: \(r.severity.label)\n"
            text += "   Risk Level: \(r.riskLevel) (Score: \(r.riskScore))\n"
            text += "   Mitigation: \(r.mitigation.isEmpty ? "(None)" : r.mitigation)\n\n"
        }
        return text
    }

    func share() {
        let text = exportText()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RiskAssessment.txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.rootViewController?
            .present(av, animated: true)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(risks) else { return }
        try? data.write(to: persistURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: persistURL),
              let loaded = try? JSONDecoder().decode([RiskEntry].self, from: data) else { return }
        risks = loaded
    }
}

// MARK: - RiskMatrixView

struct RiskMatrixView: View {
    @StateObject private var vm = RiskMatrixViewModel()
    @State private var showAdd = false
    @State private var newHazard = ""
    @State private var newProb: RiskProbability = .possible
    @State private var newSev: RiskSeverity = .moderate
    @State private var newMit = ""

    var body: some View {
        List {
            if !vm.risks.isEmpty {
                Section("Identified Risks (\(vm.risks.count))") {
                    ForEach(vm.risks) { risk in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(risk.riskColor)
                                .frame(width: 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(risk.hazard).font(.headline)
                                HStack {
                                    Text(risk.probability.label).font(.caption)
                                    Text("×").font(.caption).foregroundColor(.secondary)
                                    Text(risk.severity.label).font(.caption)
                                    Text("= \(risk.riskLevel)").font(.caption.bold()).foregroundColor(risk.riskColor)
                                }
                                if !risk.mitigation.isEmpty {
                                    Text(risk.mitigation).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { vm.remove(at: $0) }
                }

                Section {
                    Button { vm.share() } label: {
                        Label("Export Risk Assessment", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                }
            }

            Section("Add Risk") {
                TextField("Hazard description", text: $newHazard)
                Picker("Probability", selection: $newProb) {
                    ForEach(RiskProbability.allCases, id: \.self) { Text($0.label) }
                }
                Picker("Severity", selection: $newSev) {
                    ForEach(RiskSeverity.allCases, id: \.self) { Text($0.label) }
                }
                TextField("Mitigation", text: $newMit)
                Button {
                    vm.add(hazard: newHazard, probability: newProb, severity: newSev, mitigation: newMit)
                    newHazard = ""; newMit = ""
                } label: {
                    Label("Add Risk", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(ZDDesign.safetyYellow)
                .disabled(newHazard.isEmpty)
            }
        }
        .navigationTitle("Risk Matrix")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack { RiskMatrixView() }
}
