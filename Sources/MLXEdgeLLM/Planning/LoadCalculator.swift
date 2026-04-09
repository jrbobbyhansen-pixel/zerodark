// LoadCalculator.swift — Team load distribution calculator
// Tracks individual gear weight, flags overloads, suggests redistribution

import Foundation
import SwiftUI

// MARK: - Models

struct LoadCarrier: Identifiable, Equatable {
    let id: UUID
    var name: String
    var loadKg: Double
    var maxLoadKg: Double

    init(name: String, loadKg: Double = 0, maxLoadKg: Double = 30) {
        self.id = UUID()
        self.name = name
        self.loadKg = loadKg
        self.maxLoadKg = maxLoadKg
    }

    var isOverloaded: Bool { loadKg > maxLoadKg }
    var excessKg: Double { max(0, loadKg - maxLoadKg) }
    var remainingCapacity: Double { max(0, maxLoadKg - loadKg) }
    var loadPercent: Double { maxLoadKg > 0 ? (loadKg / maxLoadKg) * 100 : 0 }
}

struct RedistributionSuggestion: Identifiable {
    let id = UUID()
    let fromName: String
    let toName: String
    let weightKg: Double
}

// MARK: - LoadCalculator

@MainActor
final class LoadCalculator: ObservableObject {
    @Published var members: [LoadCarrier] = []
    @Published var suggestions: [RedistributionSuggestion] = []

    var overloadedMembers: [LoadCarrier] { members.filter { $0.isOverloaded } }
    var totalLoad: Double { members.reduce(0) { $0 + $1.loadKg } }
    var totalCapacity: Double { members.reduce(0) { $0 + $1.maxLoadKg } }

    func addMember(name: String, loadKg: Double, maxLoadKg: Double) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        members.append(LoadCarrier(name: name, loadKg: max(0, loadKg), maxLoadKg: max(1, maxLoadKg)))
    }

    func removeMember(at offsets: IndexSet) {
        members.remove(atOffsets: offsets)
        suggestions = []
    }

    func suggestRedistribution() {
        suggestions = []
        var working = members

        for i in working.indices where working[i].isOverloaded {
            var excess = working[i].excessKg
            for j in working.indices where i != j && working[j].remainingCapacity > 0 && excess > 0 {
                let transfer = min(excess, working[j].remainingCapacity)
                suggestions.append(RedistributionSuggestion(
                    fromName: working[i].name,
                    toName: working[j].name,
                    weightKg: transfer
                ))
                working[j].loadKg += transfer
                excess -= transfer
            }
        }
    }

    func exportText() -> String {
        var text = "LOAD DISTRIBUTION REPORT\n"
        text += "========================\n\n"
        for m in members {
            let status = m.isOverloaded ? "OVERLOADED" : "OK"
            text += "\(m.name): \(String(format: "%.1f", m.loadKg)) / \(String(format: "%.1f", m.maxLoadKg)) kg (\(String(format: "%.0f", m.loadPercent))%) — \(status)\n"
        }
        text += "\nTotal: \(String(format: "%.1f", totalLoad)) / \(String(format: "%.1f", totalCapacity)) kg\n"
        if !suggestions.isEmpty {
            text += "\nREDISTRIBUTION SUGGESTIONS:\n"
            for s in suggestions {
                text += "  Move \(String(format: "%.1f", s.weightKg)) kg from \(s.fromName) → \(s.toName)\n"
            }
        }
        return text
    }
}

// MARK: - LoadCalculatorView

struct LoadCalculatorView: View {
    @StateObject private var calc = LoadCalculator()
    @State private var newName = ""
    @State private var newLoad = ""
    @State private var newMax = "30"

    var body: some View {
        List {
            Section("Team Members") {
                ForEach(calc.members) { member in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.name).font(.headline)
                            ProgressView(value: min(member.loadPercent, 100), total: 100)
                                .tint(member.isOverloaded ? ZDDesign.signalRed : ZDDesign.successGreen)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("\(String(format: "%.1f", member.loadKg)) kg")
                                .font(.subheadline.bold())
                                .foregroundColor(member.isOverloaded ? ZDDesign.signalRed : .primary)
                            Text("/ \(String(format: "%.0f", member.maxLoadKg)) kg")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { calc.removeMember(at: $0) }
            }

            Section("Add Member") {
                TextField("Name", text: $newName)
                HStack {
                    TextField("Load (kg)", text: $newLoad).keyboardType(.decimalPad)
                    TextField("Max (kg)", text: $newMax).keyboardType(.decimalPad)
                }
                Button {
                    calc.addMember(name: newName, loadKg: Double(newLoad) ?? 0, maxLoadKg: Double(newMax) ?? 30)
                    newName = ""; newLoad = ""
                } label: {
                    Label("Add", systemImage: "plus.circle.fill").foregroundColor(ZDDesign.cyanAccent)
                }
                .disabled(newName.isEmpty)
            }

            if !calc.members.isEmpty {
                Section("Summary") {
                    LabeledContent("Total Load", value: "\(String(format: "%.1f", calc.totalLoad)) kg")
                    LabeledContent("Total Capacity", value: "\(String(format: "%.1f", calc.totalCapacity)) kg")
                    if !calc.overloadedMembers.isEmpty {
                        Text("\(calc.overloadedMembers.count) overloaded")
                            .foregroundColor(ZDDesign.signalRed)
                    }
                }

                Section {
                    Button {
                        calc.suggestRedistribution()
                    } label: {
                        Label("Suggest Redistribution", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ZDDesign.safetyYellow)
                    .disabled(calc.overloadedMembers.isEmpty)
                }
            }

            if !calc.suggestions.isEmpty {
                Section("Redistribution") {
                    ForEach(calc.suggestions) { s in
                        HStack {
                            Text(s.fromName).foregroundColor(ZDDesign.signalRed)
                            Image(systemName: "arrow.right").foregroundColor(.secondary)
                            Text(s.toName).foregroundColor(ZDDesign.successGreen)
                            Spacer()
                            Text("\(String(format: "%.1f", s.weightKg)) kg").font(.caption.bold())
                        }
                    }
                }

                Section {
                    Button {
                        let text = calc.exportText()
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("load_report.txt")
                        try? text.write(to: tempURL, atomically: true, encoding: .utf8)
                        let av = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
                        UIApplication.shared.connectedScenes
                            .compactMap { $0 as? UIWindowScene }
                            .first?.windows.first?.rootViewController?
                            .present(av, animated: true)
                    } label: {
                        Label("Export Report", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle("Load Calculator")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack { LoadCalculatorView() }
}
