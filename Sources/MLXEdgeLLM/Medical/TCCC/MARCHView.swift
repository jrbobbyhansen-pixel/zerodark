// MARCHView.swift — UI for walking an operator through the MARCH primary survey
// and filling out a TCCC casualty card.

import SwiftUI

public struct MARCHView: View {
    @StateObject private var vm = MARCHViewModel()
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                identitySection
                surveySection
                interventionsSection
                vitalsSection
                notesSection
                saveSection
            }
            .navigationTitle("MARCH")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Identity

    private var identitySection: some View {
        Section("Identity") {
            TextField("Callsign", text: $vm.card.callsign)
                .accessibilityLabel("Casualty callsign")
            TextField("Unit", text: $vm.card.unit)
                .accessibilityLabel("Casualty unit")
            TextField("Mechanism of injury", text: $vm.card.mechanism)
                .accessibilityLabel("Mechanism of injury")
            DatePicker("Time of injury", selection: $vm.card.timeOfInjury)
        }
    }

    // MARK: - Survey

    private var surveySection: some View {
        Section("Primary Survey — MARCH") {
            ForEach(MARCHStep.allCases) { step in
                DisclosureGroup {
                    ForEach(step.questions) { q in
                        questionRow(step: step, q: q)
                    }
                } label: {
                    HStack {
                        Text("\(step.letter) — \(step.title)").font(.headline)
                        Spacer()
                        let count = vm.findings(for: step).count
                        if count > 0 {
                            Text("\(count)").font(.caption).padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.red.opacity(0.2)))
                                .foregroundColor(.red)
                        }
                    }
                }
            }
        }
    }

    private func questionRow(step: MARCHStep, q: MARCHQuestion) -> some View {
        let picked = vm.card.findings.contains(q.positive)
        return HStack {
            Text(q.prompt).font(.subheadline)
            Spacer()
            Picker("", selection: Binding(
                get: { picked ? "Yes" : "No" },
                set: { newValue in
                    let answer = (newValue == "Yes")
                    let fire = q.invertLogic ? !answer : answer
                    vm.setFinding(q.positive, present: fire)
                }
            )) {
                Text("No").tag("No")
                Text("Yes").tag("Yes")
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
        }
    }

    // MARK: - Interventions

    private var interventionsSection: some View {
        Section("Indicated Interventions") {
            let interventions = vm.indicatedInterventions
            if interventions.isEmpty {
                Text("No findings yet — walk the survey above.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(interventions, id: \.self) { intervention in
                    let done = vm.card.interventionsLogged.contains { $0.intervention == intervention }
                    Button {
                        vm.toggleIntervention(intervention)
                    } label: {
                        HStack {
                            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(done ? .green : .secondary)
                            Text(intervention.displayName)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }
                    .accessibilityLabel("\(intervention.displayName) \(done ? "completed" : "pending")")
                }
            }
        }
    }

    // MARK: - Vitals

    private var vitalsSection: some View {
        Section("Vitals") {
            Button {
                vm.appendVitals()
            } label: {
                Label("Record vitals snapshot", systemImage: "waveform.path.ecg")
            }
            if vm.card.vitals.isEmpty {
                Text("No vitals recorded yet.").font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(vm.card.vitals.sorted(by: { $0.timestamp > $1.timestamp })) { snap in
                    HStack {
                        Text(snap.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                        Spacer()
                        if let hr = snap.heartRate  { Text("HR \(hr)") }
                        if let bp = snap.systolicBP { Text("BP \(bp)") }
                        if let sp = snap.spo2       { Text("SpO₂ \(sp)") }
                        if let rr = snap.respirationRate { Text("RR \(rr)") }
                        if let g  = snap.gcs        { Text("GCS \(g)") }
                    }
                    .font(.caption)
                }
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        Section("Notes") {
            TextField("Additional notes", text: $vm.card.notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    // MARK: - Save

    private var saveSection: some View {
        Section {
            Button {
                vm.save()
                dismiss()
            } label: {
                Label("Save Casualty Card", systemImage: "tray.and.arrow.down.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - ViewModel

@MainActor
final class MARCHViewModel: ObservableObject {
    @Published var card = CasualtyCard()

    func findings(for step: MARCHStep) -> [MARCHFinding] {
        let stepFindings = Set(step.questions.map(\.positive))
        return card.findings.filter { stepFindings.contains($0) }
    }

    var indicatedInterventions: [MARCHIntervention] {
        var seen = Set<MARCHIntervention>()
        var out: [MARCHIntervention] = []
        for finding in card.findings {
            for intervention in finding.indicatedInterventions {
                if seen.insert(intervention).inserted {
                    out.append(intervention)
                }
            }
        }
        return out
    }

    func setFinding(_ f: MARCHFinding, present: Bool) {
        if present {
            if !card.findings.contains(f) { card.findings.append(f) }
        } else {
            card.findings.removeAll { $0 == f }
        }
    }

    func toggleIntervention(_ i: MARCHIntervention) {
        if let idx = card.interventionsLogged.firstIndex(where: { $0.intervention == i }) {
            card.interventionsLogged.remove(at: idx)
        } else {
            card.interventionsLogged.append(
                CasualtyCard.LoggedIntervention(intervention: i, performedBy: AppConfig.deviceCallsign)
            )
        }
    }

    func appendVitals() {
        // Stub for now — in a real medic UI we'd present a form; seeding an
        // empty snapshot is useful as a "begin recording" tick.
        card.vitals.append(CasualtyCard.VitalsSnapshot())
    }

    func save() {
        CasualtyCardStore.shared.upsert(card)
    }
}
