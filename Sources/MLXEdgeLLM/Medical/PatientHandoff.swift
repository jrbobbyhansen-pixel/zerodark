import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - PatientHandoff

struct PatientHandoff: Codable {
    var patientName: String
    var patientID: String
    var age: Int
    var gender: String
    var vitalsHistory: [Vital]
    var treatments: [Treatment]
    var mechanism: String
    var location: CLLocationCoordinate2D
    var timestamp: Date
    
    // MARK: - Codable Conformance
    
    enum CodingKeys: String, CodingKey {
        case patientName
        case patientID
        case age
        case gender
        case vitalsHistory
        case treatments
        case mechanism
        case location
        case timestamp
    }
}

// MARK: - Vital

struct Vital: Codable {
    var type: String
    var value: Double
    var unit: String
    var timestamp: Date
}

// MARK: - Treatment

struct Treatment: Codable {
    var type: String
    var dosage: String
    var administeredBy: String
    var timestamp: Date
}

// MARK: - PatientHandoffViewModel

class PatientHandoffViewModel: ObservableObject {
    @Published var patientName: String = ""
    @Published var patientID: String = ""
    @Published var age: Int = 0
    @Published var gender: String = ""
    @Published var vitalsHistory: [Vital] = []
    @Published var treatments: [Treatment] = []
    @Published var mechanism: String = ""
    @Published var location: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    @Published var timestamp: Date = Date()
    
    func addVital(_ vital: Vital) {
        vitalsHistory.append(vital)
    }
    
    func addTreatment(_ treatment: Treatment) {
        treatments.append(treatment)
    }
    
    func exportHandoff() -> PatientHandoff {
        return PatientHandoff(
            patientName: patientName,
            patientID: patientID,
            age: age,
            gender: gender,
            vitalsHistory: vitalsHistory,
            treatments: treatments,
            mechanism: mechanism,
            location: location,
            timestamp: timestamp
        )
    }
}

// MARK: - PatientHandoffView

struct PatientHandoffView: View {
    @StateObject private var viewModel = PatientHandoffViewModel()
    
    var body: some View {
        VStack {
            Form {
                Section(header: Text("Patient Information")) {
                    TextField("Patient Name", text: $viewModel.patientName)
                    TextField("Patient ID", text: $viewModel.patientID)
                    TextField("Age", value: $viewModel.age, formatter: NumberFormatter())
                    TextField("Gender", text: $viewModel.gender)
                }
                
                Section(header: Text("Vitals History")) {
                    ForEach(viewModel.vitalsHistory, id: \.timestamp) { vital in
                        HStack {
                            Text("\(vital.type): \(vital.value) \(vital.unit)")
                            Spacer()
                            Text(vital.timestamp, style: .date)
                        }
                    }
                    Button(action: {
                        // Add new vital
                    }) {
                        Text("Add Vital")
                    }
                }
                
                Section(header: Text("Treatments")) {
                    ForEach(viewModel.treatments, id: \.timestamp) { treatment in
                        HStack {
                            Text("\(treatment.type): \(treatment.dosage) by \(treatment.administeredBy)")
                            Spacer()
                            Text(treatment.timestamp, style: .date)
                        }
                    }
                    Button(action: {
                        // Add new treatment
                    }) {
                        Text("Add Treatment")
                    }
                }
                
                Section(header: Text("Mechanism")) {
                    TextEditor(text: $viewModel.mechanism)
                }
                
                Section(header: Text("Location")) {
                    Map(coordinateRegion: .constant(MKCoordinateRegion(center: viewModel.location, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))))
                }
            }
            
            Button(action: {
                // Export handoff
                let handoff = viewModel.exportHandoff()
                // Export logic here
            }) {
                Text("Export Handoff")
            }
            .padding()
        }
        .navigationTitle("Patient Handoff")
    }
}

// MARK: - Preview

struct PatientHandoffView_Previews: PreviewProvider {
    static var previews: some View {
        PatientHandoffView()
    }
}