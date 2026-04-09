import Foundation
import SwiftUI
import CoreLocation

// MARK: - ConfinedSpaceEntryManager

class ConfinedSpaceEntryManager: ObservableObject {
    @Published var atmosphericData: AtmosphericData = .init()
    @Published var entryPermit: EntryPermit? = nil
    @Published var rescuePlan: RescuePlan? = nil
    @Published var attendantChecklist: AttendantChecklist = .init()
    @Published var timeTracking: TimeTracking = .init()
    
    func requestEntryPermit(location: CLLocationCoordinate2D) async {
        // Simulate permit request
        let permit = EntryPermit(location: location, status: .approved)
        entryPermit = permit
    }
    
    func generateRescuePlan(location: CLLocationCoordinate2D) {
        // Simulate rescue plan generation
        let plan = RescuePlan(location: location, steps: ["Step 1", "Step 2", "Step 3"])
        rescuePlan = plan
    }
    
    func updateAtmosphericData(data: AtmosphericData) {
        atmosphericData = data
    }
    
    func updateAttendantChecklist(checklist: AttendantChecklist) {
        attendantChecklist = checklist
    }
    
    func startTrackingTime() {
        timeTracking.startTime = Date()
    }
    
    func stopTrackingTime() {
        timeTracking.endTime = Date()
    }
}

// MARK: - Data Models

struct AtmosphericData {
    var oxygenLevel: Double = 21.0
    var carbonDioxideLevel: Double = 0.04
    var temperature: Double = 20.0
    var humidity: Double = 50.0
}

struct EntryPermit {
    let location: CLLocationCoordinate2D
    let status: PermitStatus
}

enum PermitStatus {
    case pending
    case approved
    case denied
}

struct RescuePlan {
    let location: CLLocationCoordinate2D
    let steps: [String]
}

struct AttendantChecklist {
    var safetyGear: Bool = false
    var communicationEquipment: Bool = false
    var emergencyProcedures: Bool = false
}

struct TimeTracking {
    var startTime: Date?
    var endTime: Date?
}

// MARK: - SwiftUI View

struct ConfinedSpaceView: View {
    @StateObject private var manager = ConfinedSpaceEntryManager()
    let location: CLLocationCoordinate2D
    
    var body: some View {
        VStack {
            Text("Confined Space Entry Management")
                .font(.largeTitle)
                .padding()
            
            Group {
                Text("Oxygen Level: \(manager.atmosphericData.oxygenLevel)%")
                Text("CO2 Level: \(manager.atmosphericData.carbonDioxideLevel)%")
                Text("Temperature: \(manager.atmosphericData.temperature)°C")
                Text("Humidity: \(manager.atmosphericData.humidity)%")
            }
            .padding()
            
            Button("Request Entry Permit") {
                Task {
                    await manager.requestEntryPermit(location: location)
                }
            }
            .padding()
            
            if let permit = manager.entryPermit {
                Text("Entry Permit: \(permit.status.rawValue)")
                    .padding()
            }
            
            Button("Generate Rescue Plan") {
                manager.generateRescuePlan(location: location)
            }
            .padding()
            
            if let plan = manager.rescuePlan {
                VStack {
                    Text("Rescue Plan")
                    ForEach(plan.steps, id: \.self) { step in
                        Text(step)
                    }
                }
                .padding()
            }
            
            Group {
                Toggle("Safety Gear", isOn: $manager.attendantChecklist.safetyGear)
                Toggle("Communication Equipment", isOn: $manager.attendantChecklist.communicationEquipment)
                Toggle("Emergency Procedures", isOn: $manager.attendantChecklist.emergencyProcedures)
            }
            .padding()
            
            Button("Start Time Tracking") {
                manager.startTrackingTime()
            }
            .padding()
            
            Button("Stop Time Tracking") {
                manager.stopTrackingTime()
            }
            .padding()
            
            if let startTime = manager.timeTracking.startTime, let endTime = manager.timeTracking.endTime {
                Text("Time Spent: \(endTime.timeIntervalSince(startTime)) seconds")
                    .padding()
            }
        }
        .padding()
    }
}

// MARK: - Preview

struct ConfinedSpaceView_Previews: PreviewProvider {
    static var previews: some View {
        ConfinedSpaceView(location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194))
    }
}