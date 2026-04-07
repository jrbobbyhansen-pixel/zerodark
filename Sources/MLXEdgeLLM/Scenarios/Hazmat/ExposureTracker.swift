import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - Models

struct ExposureRecord: Identifiable, Codable {
    let id = UUID()
    let location: CLLocationCoordinate2D
    let ppeLevel: PPELevel
    let symptoms: [Symptom]
    let entryTime: Date
    let exitTime: Date?
    
    enum PPELevel: String, Codable {
        case none, basic, advanced
    }
    
    enum Symptom: String, Codable {
        case headache, nausea, dizziness, rash
    }
}

// MARK: - View Models

class ExposureTrackerViewModel: ObservableObject {
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var ppeLevel: ExposureRecord.PPELevel = .none
    @Published var symptoms: [ExposureRecord.Symptom] = []
    @Published var exposureRecords: [ExposureRecord] = []
    @Published var isRecording: Bool = false
    
    private var entryTime: Date?
    
    func startRecording() {
        entryTime = Date()
        isRecording = true
    }
    
    func stopRecording() {
        if let entryTime = entryTime {
            let record = ExposureRecord(
                location: currentLocation ?? CLLocationCoordinate2D(),
                ppeLevel: ppeLevel,
                symptoms: symptoms,
                entryTime: entryTime,
                exitTime: Date()
            )
            exposureRecords.append(record)
        }
        isRecording = false
    }
    
    func addSymptom(_ symptom: ExposureRecord.Symptom) {
        if !symptoms.contains(symptom) {
            symptoms.append(symptom)
        }
    }
    
    func removeSymptom(_ symptom: ExposureRecord.Symptom) {
        symptoms.removeAll { $0 == symptom }
    }
}

// MARK: - Views

struct ExposureTrackerView: View {
    @StateObject private var viewModel = ExposureTrackerViewModel()
    
    var body: some View {
        VStack {
            HStack {
                Text("PPE Level")
                Picker("PPE Level", selection: $viewModel.ppeLevel) {
                    ForEach(ExposureRecord.PPELevel.allCases, id: \.self) { level in
                        Text(level.rawValue.capitalized)
                    }
                }
            }
            
            HStack {
                Text("Symptoms")
                ForEach(ExposureRecord.Symptom.allCases, id: \.self) { symptom in
                    Button(action: {
                        if viewModel.symptoms.contains(symptom) {
                            viewModel.removeSymptom(symptom)
                        } else {
                            viewModel.addSymptom(symptom)
                        }
                    }) {
                        Text(symptom.rawValue.capitalized)
                            .padding()
                            .background(viewModel.symptoms.contains(symptom) ? Color.blue : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
            }
            
            Button(action: {
                if viewModel.isRecording {
                    viewModel.stopRecording()
                } else {
                    viewModel.startRecording()
                }
            }) {
                Text(viewModel.isRecording ? "Stop Recording" : "Start Recording")
                    .padding()
                    .background(viewModel.isRecording ? Color.red : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            
            List(viewModel.exposureRecords) { record in
                VStack(alignment: .leading) {
                    Text("Location: \(record.location.latitude), \(record.location.longitude)")
                    Text("PPE Level: \(record.ppeLevel.rawValue.capitalized)")
                    Text("Symptoms: \(record.symptoms.map { $0.rawValue.capitalized }.joined(separator: ", "))")
                    Text("Time: \(record.entryTime, style: .date) - \(record.exitTime?.formatted(date: .long, time: .short) ?? "Ongoing")")
                }
            }
        }
        .padding()
        .onAppear {
            // Start location updates
        }
        .onDisappear {
            // Stop location updates
        }
    }
}

// MARK: - Previews

struct ExposureTrackerView_Previews: PreviewProvider {
    static var previews: some View {
        ExposureTrackerView()
    }
}