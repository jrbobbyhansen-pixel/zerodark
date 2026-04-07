import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - CommsAudit

class CommsAudit: ObservableObject {
    @Published var logs: [CommsLogEntry] = []
    
    func logEntry(_ entry: CommsLogEntry) {
        DispatchQueue.main.async {
            self.logs.append(entry)
        }
    }
}

// MARK: - CommsLogEntry

struct CommsLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let action: CommsAction
    let metadata: [String: Any]
}

// MARK: - CommsAction

enum CommsAction {
    case connectionAttempted
    case connectionEstablished
    case connectionFailed
    case dataSent
    case dataReceived
    case disconnectionAttempted
    case disconnectionEstablished
}

// MARK: - CommsAuditView

struct CommsAuditView: View {
    @StateObject private var audit = CommsAudit()
    
    var body: some View {
        List(audit.logs) { entry in
            VStack(alignment: .leading) {
                Text(entry.action.description)
                    .font(.headline)
                Text("Timestamp: \(entry.timestamp, formatter: dateFormatter)")
                    .font(.subheadline)
                ForEach(entry.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    Text("\(key): \(value.description)")
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Comms Audit")
    }
}

// MARK: - DateFormatter

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    return formatter
}()

// MARK: - Preview

struct CommsAuditView_Previews: PreviewProvider {
    static var previews: some View {
        CommsAuditView()
    }
}