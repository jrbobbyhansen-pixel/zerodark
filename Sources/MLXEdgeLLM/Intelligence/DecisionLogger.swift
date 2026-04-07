import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - DecisionLogger

class DecisionLogger: ObservableObject {
    @Published private(set) var logs: [DecisionLogEntry] = []
    
    func logDecision(reason: String, inputs: [String: Any], outputs: [String: Any]) {
        let entry = DecisionLogEntry(reason: reason, inputs: inputs, outputs: outputs)
        logs.append(entry)
    }
    
    func getLogEntry(at index: Int) -> DecisionLogEntry? {
        guard index >= 0 && index < logs.count else { return nil }
        return logs[index]
    }
}

// MARK: - DecisionLogEntry

struct DecisionLogEntry: Identifiable, Codable {
    let id = UUID()
    let timestamp: Date
    let reason: String
    let inputs: [String: Any]
    let outputs: [String: Any]
    
    init(reason: String, inputs: [String: Any], outputs: [String: Any]) {
        self.timestamp = Date()
        self.reason = reason
        self.inputs = inputs
        self.outputs = outputs
    }
}

// MARK: - DecisionLogView

struct DecisionLogView: View {
    @StateObject private var logger = DecisionLogger()
    
    var body: some View {
        List(logger.logs) { entry in
            VStack(alignment: .leading) {
                Text("Reason: \(entry.reason)")
                    .font(.headline)
                Text("Timestamp: \(entry.timestamp, style: .date)")
                    .font(.subheadline)
                Text("Inputs: \(entry.inputs.description)")
                    .font(.caption)
                Text("Outputs: \(entry.outputs.description)")
                    .font(.caption)
            }
        }
        .navigationTitle("Decision Log")
        .toolbar {
            Button(action: {
                logger.logs.removeAll()
            }) {
                Label("Clear Log", systemImage: "trash")
            }
        }
    }
}

// MARK: - Preview

struct DecisionLogView_Previews: PreviewProvider {
    static var previews: some View {
        DecisionLogView()
    }
}