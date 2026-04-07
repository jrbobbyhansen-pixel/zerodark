import Foundation
import SwiftUI

// MARK: - EncryptionAuditLog

class EncryptionAuditLog: ObservableObject {
    @Published private(set) var entries: [AuditEntry] = []
    
    func logEncryptionOperation(operation: String, key: String, timestamp: Date = Date()) {
        let entry = AuditEntry(operation: operation, key: key, timestamp: timestamp)
        entries.append(entry)
    }
    
    func logKeyUsage(key: String, usage: String, timestamp: Date = Date()) {
        let entry = AuditEntry(operation: "Key Usage", key: key, details: usage, timestamp: timestamp)
        entries.append(entry)
    }
    
    func logComplianceReport(report: String, timestamp: Date = Date()) {
        let entry = AuditEntry(operation: "Compliance Report", details: report, timestamp: timestamp)
        entries.append(entry)
    }
    
    func logTamperDetection(event: String, timestamp: Date = Date()) {
        let entry = AuditEntry(operation: "Tamper Detection", details: event, timestamp: timestamp)
        entries.append(entry)
    }
}

// MARK: - AuditEntry

struct AuditEntry: Identifiable, Codable {
    let id = UUID()
    let operation: String
    let key: String?
    let details: String?
    let timestamp: Date
    
    init(operation: String, key: String? = nil, details: String? = nil, timestamp: Date) {
        self.operation = operation
        self.key = key
        self.details = details
        self.timestamp = timestamp
    }
}

// MARK: - Preview

struct EncryptionAuditLog_Previews: PreviewProvider {
    static var previews: some View {
        let auditLog = EncryptionAuditLog()
        auditLog.logEncryptionOperation(operation: "Encrypt", key: "key123")
        auditLog.logKeyUsage(key: "key123", usage: "Used for encryption")
        auditLog.logComplianceReport(report: "Compliance check passed")
        auditLog.logTamperDetection(event: "Tamper detected")
        
        List(auditLog.entries) { entry in
            VStack(alignment: .leading) {
                Text(entry.operation)
                    .font(.headline)
                if let key = entry.key {
                    Text("Key: \(key)")
                        .font(.subheadline)
                }
                if let details = entry.details {
                    Text("Details: \(details)")
                        .font(.subheadline)
                }
                Text("Timestamp: \(entry.timestamp, formatter: DateFormatter())")
                    .font(.caption)
            }
        }
        .padding()
    }
}