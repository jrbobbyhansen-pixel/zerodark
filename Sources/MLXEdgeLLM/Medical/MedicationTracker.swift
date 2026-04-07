import Foundation
import SwiftUI

// MARK: - MedicationTracker

class MedicationTracker: ObservableObject {
    @Published var medications: [Medication] = []
    @Published var allergies: [String] = []
    
    func addMedication(drug: String, dose: String, route: String, time: Date, patient: String) {
        let medication = Medication(drug: drug, dose: dose, route: route, time: time, patient: patient)
        medications.append(medication)
        checkForDrugInteractions(medication)
        checkForAllergies(medication)
    }
    
    func checkForDrugInteractions(_ medication: Medication) {
        // Placeholder for drug interaction logic
        print("Checking for drug interactions with \(medication.drug)")
    }
    
    func checkForAllergies(_ medication: Medication) {
        // Placeholder for allergy check logic
        if allergies.contains(medication.drug) {
            print("Allergy alert for \(medication.drug)")
        }
    }
    
    func exportMedications() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        
        var exportString = "Medication Tracker Export\n"
        for medication in medications {
            exportString += "\(medication.drug), \(medication.dose), \(medication.route), \(formatter.string(from: medication.time)), \(medication.patient)\n"
        }
        return exportString
    }
}

// MARK: - Medication

struct Medication: Identifiable {
    let id = UUID()
    let drug: String
    let dose: String
    let route: String
    let time: Date
    let patient: String
}

// MARK: - MedicationTrackerView

struct MedicationTrackerView: View {
    @StateObject private var viewModel = MedicationTracker()
    
    var body: some View {
        NavigationView {
            VStack {
                List(viewModel.medications) { medication in
                    MedicationRow(medication: medication)
                }
                .navigationTitle("Medication Tracker")
                
                Button(action: {
                    // Placeholder for adding medication logic
                    viewModel.addMedication(drug: "Ibuprofen", dose: "200mg", route: "Oral", time: Date(), patient: "John Doe")
                }) {
                    Text("Add Medication")
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Placeholder for export logic
                        let exportData = viewModel.exportMedications()
                        print(exportData)
                    }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

// MARK: - MedicationRow

struct MedicationRow: View {
    let medication: Medication
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(medication.drug)
                    .font(.headline)
                Text("Dose: \(medication.dose)")
                Text("Route: \(medication.route)")
                Text("Time: \(medication.time, style: .date)")
                Text("Patient: \(medication.patient)")
            }
        }
    }
}

// MARK: - Preview

struct MedicationTrackerView_Previews: PreviewProvider {
    static var previews: some View {
        MedicationTrackerView()
    }
}