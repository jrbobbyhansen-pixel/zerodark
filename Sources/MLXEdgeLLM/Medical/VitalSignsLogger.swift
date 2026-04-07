import Foundation
import SwiftUI
import Combine

// MARK: - Vital Signs Logger

class VitalSignsLogger: ObservableObject {
    @Published var pulse: Int = 0
    @Published var respiration: Int = 0
    @Published var bloodPressure: (systolic: Int, diastolic: Int) = (0, 0)
    @Published var spo2: Int = 0
    @Published var gcs: Int = 0
    @Published var pupils: String = "Equal and Reactive"
    
    @Published var logEntries: [VitalSignLogEntry] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Simulate periodic updates for demonstration purposes
        Timer.publish(every: 10, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.logCurrentVitalSigns()
            }
            .store(in: &cancellables)
    }
    
    func logCurrentVitalSigns() {
        let entry = VitalSignLogEntry(
            timestamp: Date(),
            pulse: pulse,
            respiration: respiration,
            bloodPressure: bloodPressure,
            spo2: spo2,
            gcs: gcs,
            pupils: pupils
        )
        logEntries.append(entry)
        
        // Check for deterioration and alert if necessary
        checkForDeterioration(entry)
    }
    
    private func checkForDeterioration(_ entry: VitalSignLogEntry) {
        // Example alert logic
        if entry.pulse < 60 || entry.pulse > 100 {
            print("Alert: Pulse out of normal range")
        }
        if entry.respiration < 12 || entry.respiration > 20 {
            print("Alert: Respiration out of normal range")
        }
        if entry.bloodPressure.systolic < 90 || entry.bloodPressure.systolic > 140 || entry.bloodPressure.diastolic < 60 || entry.bloodPressure.diastolic > 90 {
            print("Alert: Blood Pressure out of normal range")
        }
        if entry.spo2 < 95 {
            print("Alert: SpO2 out of normal range")
        }
        if entry.gcs < 15 {
            print("Alert: GCS out of normal range")
        }
    }
}

// MARK: - Vital Sign Log Entry

struct VitalSignLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let pulse: Int
    let respiration: Int
    let bloodPressure: (systolic: Int, diastolic: Int)
    let spo2: Int
    let gcs: Int
    let pupils: String
}

// MARK: - SwiftUI View

struct VitalSignsLoggerView: View {
    @StateObject private var logger = VitalSignsLogger()
    
    var body: some View {
        VStack {
            HStack {
                Text("Pulse: \(logger.pulse)")
                Text("Respiration: \(logger.respiration)")
            }
            HStack {
                Text("Blood Pressure: \(logger.bloodPressure.systolic)/\(logger.bloodPressure.diastolic)")
                Text("SpO2: \(logger.spo2)%")
            }
            HStack {
                Text("GCS: \(logger.gcs)")
                Text("Pupils: \(logger.pupils)")
            }
            
            Divider()
            
            List(logger.logEntries) { entry in
                VStack(alignment: .leading) {
                    Text("Timestamp: \(entry.timestamp, formatter: dateFormatter)")
                    Text("Pulse: \(entry.pulse)")
                    Text("Respiration: \(entry.respiration)")
                    Text("Blood Pressure: \(entry.bloodPressure.systolic)/\(entry.bloodPressure.diastolic)")
                    Text("SpO2: \(entry.spo2)%")
                    Text("GCS: \(entry.gcs)")
                    Text("Pupils: \(entry.pupils)")
                }
            }
        }
        .padding()
        .navigationTitle("Vital Signs Logger")
    }
}

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()

// MARK: - Preview

struct VitalSignsLoggerView_Previews: PreviewProvider {
    static var previews: some View {
        VitalSignsLoggerView()
    }
}