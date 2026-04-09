// MedicationTracker.swift — TCCC-aligned medication logging with drug interaction + allergy enforcement
// Drug interaction table covers common field medications (opioids, antibiotics, hemostatics, analgesics)
// CRITICAL: checkForDrugInteractions + checkForAllergies BLOCK addMedication if hazard found

import Foundation
import SwiftUI
import UserNotifications

// MARK: - Medication

struct Medication: Identifiable, Codable {
    let id: UUID
    let drug: String
    let dose: String
    let route: String
    let time: Date
    let patient: String

    init(drug: String, dose: String, route: String, time: Date, patient: String) {
        self.id = UUID()
        self.drug = drug.lowercased()
        self.dose = dose
        self.route = route
        self.time = time
        self.patient = patient
    }
}

// MARK: - MedicationError

enum MedicationError: LocalizedError {
    case drugInteraction(drug1: String, drug2: String, severity: String, effect: String)
    case allergyConflict(drug: String, allergen: String)

    var errorDescription: String? {
        switch self {
        case .drugInteraction(let d1, let d2, let sev, let effect):
            return "⚠️ INTERACTION [\(sev.uppercased())]: \(d1) + \(d2)\n\(effect)"
        case .allergyConflict(let drug, let allergen):
            return "🚨 ALLERGY ALERT: \(drug) matches listed allergen '\(allergen)'"
        }
    }
}

// MARK: - Drug Interaction Entry

private struct InteractionEntry {
    let drugs: Set<String>
    let severity: String    // "CRITICAL", "MAJOR", "MODERATE"
    let effect: String
}

// MARK: - MedicationTracker

@MainActor
final class MedicationTracker: ObservableObject {
    static let shared = MedicationTracker()

    @Published var medications: [Medication] = []
    @Published var allergies: [String] = []
    @Published var lastAlert: String? = nil

    // MARK: - Add Medication (enforced pre-flight)

    /// Throws `MedicationError` if interaction or allergy detected.
    /// Caller must present error to user and require explicit override before proceeding.
    func addMedication(drug: String, dose: String, route: String, time: Date = Date(), patient: String) throws {
        let normalized = drug.lowercased().trimmingCharacters(in: .whitespaces)
        let med = Medication(drug: normalized, dose: dose, route: route, time: time, patient: patient)

        // Pre-flight 1: allergy check
        if let allergyError = allergyCheck(for: med) {
            lastAlert = allergyError.localizedDescription
            throw allergyError
        }

        // Pre-flight 2: interaction check against all existing meds for same patient
        let patientMeds = medications.filter { $0.patient == patient }
        if let interactionError = interactionCheck(for: med, against: patientMeds) {
            lastAlert = interactionError.localizedDescription
            throw interactionError
        }

        medications.append(med)
        lastAlert = nil
    }

    /// Non-throwing wrapper: returns MedicationError if safety check fails, nil on success
    func tryAddMedication(drug: String, dose: String, route: String, patient: String) -> MedicationError? {
        do {
            try addMedication(drug: drug, dose: dose, route: route, patient: patient)
            return nil
        } catch let err as MedicationError {
            return err
        } catch {
            return nil
        }
    }

    /// Force-add bypassing safety checks — requires explicit user override confirmation
    func forceAddMedication(drug: String, dose: String, route: String, time: Date = Date(), patient: String) {
        let normalized = drug.lowercased().trimmingCharacters(in: .whitespaces)
        let med = Medication(drug: normalized, dose: dose, route: route, time: time, patient: patient)
        medications.append(med)
        AuditLogger.shared.log(.medicationAdded, detail: "OVERRIDE: \(normalized) for \(patient)")
    }

    // MARK: - Allergy Check

    private func allergyCheck(for med: Medication) -> MedicationError? {
        for allergen in allergies {
            let a = allergen.lowercased()
            if med.drug.contains(a) || a.contains(med.drug) {
                return .allergyConflict(drug: med.drug, allergen: allergen)
            }
        }
        // Cross-reactivity: penicillin family triggers cephalosporin check
        if med.drug.contains("penicillin") || med.drug.contains("amoxicillin") || med.drug.contains("ampicillin") {
            if allergies.map({ $0.lowercased() }).contains(where: { $0.contains("cephalosporin") || $0.contains("cefaz") || $0.contains("cefalex") }) {
                return .allergyConflict(drug: med.drug, allergen: "cephalosporin cross-reactivity")
            }
        }
        return nil
    }

    // MARK: - Drug Interaction Check

    private func interactionCheck(for med: Medication, against existing: [Medication]) -> MedicationError? {
        for existingMed in existing {
            let pair = Set([med.drug, existingMed.drug])
            if let interaction = interactionTable.first(where: {
                $0.drugs.isSubset(of: pair) || pair.isSubset(of: $0.drugs) || pairMatches($0.drugs, pair: pair)
            }) {
                return .drugInteraction(
                    drug1: med.drug,
                    drug2: existingMed.drug,
                    severity: interaction.severity,
                    effect: interaction.effect
                )
            }
        }
        return nil
    }

    private func pairMatches(_ tableDrugs: Set<String>, pair: Set<String>) -> Bool {
        // fuzzy match: table entry "morphine" matches "morphine sulfate" etc.
        for tableDrug in tableDrugs {
            for pairDrug in pair {
                if pairDrug.contains(tableDrug) || tableDrug.contains(pairDrug) {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Drug Interaction Table (field-relevant medications)

    private let interactionTable: [InteractionEntry] = [
        // Opioid combinations
        .init(drugs: ["morphine", "ketamine"],           severity: "MAJOR",    effect: "Enhanced CNS/respiratory depression. Monitor airway closely."),
        .init(drugs: ["morphine", "benzodiazepine"],     severity: "CRITICAL", effect: "Severe respiratory depression, apnea risk. Avoid unless intubated."),
        .init(drugs: ["fentanyl", "benzodiazepine"],     severity: "CRITICAL", effect: "Synergistic CNS/respiratory depression. High apnea risk."),
        .init(drugs: ["fentanyl", "ketamine"],           severity: "MAJOR",    effect: "Additive CNS depression. Titrate carefully."),
        .init(drugs: ["naloxone", "morphine"],           severity: "MAJOR",    effect: "Naloxone reverses opioid analgesia. Use only for overdose."),
        .init(drugs: ["naloxone", "fentanyl"],           severity: "MAJOR",    effect: "Naloxone reverses fentanyl. May precipitate acute withdrawal."),
        // Antibiotic + anticoagulant
        .init(drugs: ["metronidazole", "warfarin"],      severity: "CRITICAL", effect: "Metronidazole potentiates warfarin — major bleeding risk."),
        .init(drugs: ["ciprofloxacin", "warfarin"],      severity: "MAJOR",    effect: "Fluoroquinolone increases INR. Monitor bleeding."),
        .init(drugs: ["doxycycline", "warfarin"],        severity: "MODERATE", effect: "Increased anticoagulant effect. Watch for bleeding."),
        // Hemostatic agents
        .init(drugs: ["tranexamic acid", "warfarin"],    severity: "MODERATE", effect: "TXA reduces fibrinolysis; may increase clot risk."),
        .init(drugs: ["tranexamic acid", "heparin"],     severity: "MAJOR",    effect: "Antagonistic effects on coagulation. Avoid concurrent use."),
        // Vasopressors
        .init(drugs: ["epinephrine", "beta blocker"],    severity: "CRITICAL", effect: "Epinephrine efficacy blocked; paradoxical bradycardia possible."),
        .init(drugs: ["norepinephrine", "maoi"],         severity: "CRITICAL", effect: "Hypertensive crisis risk. Avoid in MAOI patients."),
        // Analgesics
        .init(drugs: ["ketorolac", "aspirin"],           severity: "MAJOR",    effect: "Additive GI bleeding risk. Avoid combination."),
        .init(drugs: ["ketorolac", "warfarin"],          severity: "CRITICAL", effect: "NSAID + anticoagulant: major hemorrhage risk."),
        .init(drugs: ["ibuprofen", "warfarin"],          severity: "CRITICAL", effect: "NSAID potentiates anticoagulation. Avoid."),
        // Antibiotics combined
        .init(drugs: ["gentamicin", "furosemide"],       severity: "MAJOR",    effect: "Additive nephrotoxicity and ototoxicity."),
        .init(drugs: ["amoxicillin", "methotrexate"],    severity: "MAJOR",    effect: "Penicillins reduce methotrexate clearance — toxicity risk."),
        // Sedation
        .init(drugs: ["diazepam", "alcohol"],            severity: "CRITICAL", effect: "Fatal CNS/respiratory depression at any dose combination."),
        .init(drugs: ["midazolam", "alcohol"],           severity: "CRITICAL", effect: "Fatal CNS/respiratory depression."),
        // Cardiac
        .init(drugs: ["amiodarone", "digoxin"],          severity: "MAJOR",    effect: "Amiodarone doubles digoxin levels — toxicity risk."),
        .init(drugs: ["amiodarone", "warfarin"],         severity: "CRITICAL", effect: "Amiodarone greatly potentiates anticoagulation."),
        // Hypoglycemics
        .init(drugs: ["insulin", "alcohol"],             severity: "CRITICAL", effect: "Severe hypoglycemia risk. Monitor glucose closely."),
        .init(drugs: ["metformin", "alcohol"],           severity: "MAJOR",    effect: "Lactic acidosis risk with heavy alcohol use."),
    ]

    // MARK: - Export

    func exportMedications() -> String {
        let formatter = ISO8601DateFormatter()
        var export = "MEDICATION LOG EXPORT\n"
        export += "Generated: \(formatter.string(from: Date()))\n\n"
        export += "Drug,Dose,Route,Time,Patient\n"
        for med in medications {
            export += "\(med.drug),\(med.dose),\(med.route),\(formatter.string(from: med.time)),\(med.patient)\n"
        }
        return export
    }
}

// MARK: - MedicationTrackerView

struct MedicationTrackerView: View {
    @StateObject private var tracker = MedicationTracker.shared
    @State private var showAddSheet = false
    @State private var alertError: MedicationError? = nil
    @State private var pendingMedication: PendingMed? = nil

    var body: some View {
        NavigationStack {
            List {
                if tracker.medications.isEmpty {
                    ContentUnavailableView(
                        "No Medications Logged",
                        systemImage: "pills.circle",
                        description: Text("Tap + to add a medication for a patient.")
                    )
                } else {
                    ForEach(tracker.medications) { med in
                        MedicationRow(medication: med)
                    }
                }
            }
            .navigationTitle("Medication Log")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(ZDDesign.cyanAccent)
                    }
                    .accessibilityLabel("Add medication")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        let data = tracker.exportMedications()
                        let url = FileManager.default.temporaryDirectory
                            .appendingPathComponent("medications-\(Int(Date().timeIntervalSince1970)).csv")
                        try? data.write(to: url, atomically: true, encoding: .utf8)
                        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                        UIApplication.shared.connectedScenes
                            .compactMap { $0 as? UIWindowScene }
                            .first?.windows.first?.rootViewController?
                            .present(av, animated: true)
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddMedicationSheet { drug, dose, route, patient in
                    if let err = tracker.tryAddMedication(drug: drug, dose: dose, route: route, patient: patient) {
                        pendingMedication = PendingMed(drug: drug, dose: dose, route: route, patient: patient)
                        alertError = err
                    } else {
                        showAddSheet = false
                    }
                }
            }
            .alert(item: $alertError) { err in
                Alert(
                    title: Text("Safety Warning"),
                    message: Text(err.localizedDescription),
                    primaryButton: .destructive(Text("Override & Add")) {
                        if let p = pendingMedication {
                            tracker.forceAddMedication(drug: p.drug, dose: p.dose, route: p.route, patient: p.patient)
                        }
                        pendingMedication = nil
                        showAddSheet = false
                    },
                    secondaryButton: .cancel(Text("Cancel")) {
                        pendingMedication = nil
                    }
                )
            }
        }
    }
}

private struct PendingMed {
    let drug, dose, route, patient: String
}

extension MedicationError: Identifiable {
    var id: String { localizedDescription ?? "" }
}

// MARK: - MedicationRow

struct MedicationRow: View {
    let medication: Medication
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(medication.drug.capitalized)
                    .font(.headline)
                Spacer()
                Text(medication.time, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 12) {
                Label(medication.dose, systemImage: "drop.fill")
                    .font(.caption).foregroundColor(.secondary)
                Label(medication.route, systemImage: "arrow.right.circle")
                    .font(.caption).foregroundColor(.secondary)
            }
            Text("Patient: \(medication.patient)")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - AddMedicationSheet

struct AddMedicationSheet: View {
    let onAdd: (String, String, String, String) -> Void

    @State private var drug = ""
    @State private var dose = ""
    @State private var route = "IV"
    @State private var patient = ""
    @Environment(\.dismiss) private var dismiss: DismissAction

    private let routes = ["IV", "IM", "PO", "SQ", "IN", "IO", "SL", "TD"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication") {
                    TextField("Drug name", text: $drug)
                        .autocapitalization(.words)
                    TextField("Dose (e.g. 10mg)", text: $dose)
                    Picker("Route", selection: $route) {
                        ForEach(routes, id: \.self) { Text($0) }
                    }
                }
                Section("Patient") {
                    TextField("Patient callsign / name", text: $patient)
                }
                Section {
                    Text("Safety checks will run automatically. Override is available but requires confirmation.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Add Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") { onAdd(drug, dose, route, patient) }
                        .disabled(drug.isEmpty || dose.isEmpty || patient.isEmpty)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
