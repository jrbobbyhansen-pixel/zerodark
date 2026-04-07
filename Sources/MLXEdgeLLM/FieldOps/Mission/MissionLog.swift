import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - MissionLog

class MissionLog: ObservableObject {
    @Published private(set) var entries: [MissionLogEntry] = []
    
    func logEvent(_ event: String, at location: CLLocationCoordinate2D? = nil, with decision: String? = nil, communication: String? = nil) {
        let entry = MissionLogEntry(event: event, location: location, decision: decision, communication: communication)
        entries.append(entry)
    }
    
    func exportLog() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        
        var logString = "Mission Log Export\n"
        for entry in entries {
            logString += "Timestamp: \(formatter.string(from: entry.timestamp))\n"
            logString += "Event: \(entry.event)\n"
            if let location = entry.location {
                logString += "Location: \(location.latitude), \(location.longitude)\n"
            }
            if let decision = entry.decision {
                logString += "Decision: \(decision)\n"
            }
            if let communication = entry.communication {
                logString += "Communication: \(communication)\n"
            }
            logString += "-------------------------\n"
        }
        return logString
    }
}

// MARK: - MissionLogEntry

struct MissionLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let event: String
    let location: CLLocationCoordinate2D?
    let decision: String?
    let communication: String?
    
    init(event: String, location: CLLocationCoordinate2D? = nil, decision: String? = nil, communication: String? = nil) {
        self.timestamp = Date()
        self.event = event
        self.location = location
        self.decision = decision
        self.communication = communication
    }
}

// MARK: - MissionLogView

struct MissionLogView: View {
    @StateObject private var missionLog = MissionLog()
    
    var body: some View {
        VStack {
            List(missionLog.entries) { entry in
                MissionLogEntryView(entry: entry)
            }
            .listStyle(PlainListStyle())
            
            Button("Export Log") {
                let logString = missionLog.exportLog()
                // Handle export, e.g., save to file or share
                print(logString)
            }
            .padding()
        }
        .navigationTitle("Mission Log")
    }
}

// MARK: - MissionLogEntryView

struct MissionLogEntryView: View {
    let entry: MissionLogEntry
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Event: \(entry.event)")
                .font(.headline)
            if let location = entry.location {
                Text("Location: \(location.latitude), \(location.longitude)")
                    .font(.subheadline)
            }
            if let decision = entry.decision {
                Text("Decision: \(decision)")
                    .font(.subheadline)
            }
            if let communication = entry.communication {
                Text("Communication: \(communication)")
                    .font(.subheadline)
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(8)
        .shadow(radius: 2)
    }
}

// MARK: - Preview

struct MissionLogView_Previews: PreviewProvider {
    static var previews: some View {
        MissionLogView()
    }
}