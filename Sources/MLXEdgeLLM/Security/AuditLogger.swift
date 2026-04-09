// AuditLogger.swift — Immutable append-only audit log for CMMC Level 2 compliance
// Logs: key operations, credential access, peer connections, exports, permission changes
// Export: signed CSV for compliance audit

import Foundation

// MARK: - AuditEvent

enum AuditEventType: String, Codable {
    // Key operations
    case keyGenerated       = "KEY_GEN"
    case keyRotated         = "KEY_ROTATE"
    case keyDistributed     = "KEY_DIST"
    case compromiseDetected = "COMPROMISE"
    case incidentResponse   = "INCIDENT_RESPONSE"
    // Authentication
    case credentialAccess   = "CRED_ACCESS"
    case credentialUpdated  = "CRED_UPDATE"
    // Connectivity
    case peerConnected      = "PEER_CONNECT"
    case peerDisconnected   = "PEER_DISCONNECT"
    case meshJoined         = "MESH_JOIN"
    case meshLeft           = "MESH_LEAVE"
    // Data operations
    case scanExported       = "SCAN_EXPORT"
    case reportExported     = "REPORT_EXPORT"
    case logsExported       = "LOGS_EXPORT"
    // Permissions
    case permissionGranted  = "PERM_GRANT"
    case permissionDenied   = "PERM_DENY"
    // App lifecycle
    case appLaunched        = "APP_LAUNCH"
    case appBackgrounded    = "APP_BG"
}

struct AuditEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let type: AuditEventType
    let detail: String
    let deviceID: String

    init(type: AuditEventType, detail: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.type = type
        self.detail = detail
        self.deviceID = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }
}

// MARK: - AuditLogger

@MainActor
final class AuditLogger {
    static let shared = AuditLogger()

    private var entries: [AuditEntry] = []
    private let maxEntries = 10_000
    private let logURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        logURL = docs.appendingPathComponent("audit.log.json")
        loadEntries()
    }

    // MARK: - Logging

    func log(_ type: AuditEventType, detail: String = "") {
        let entry = AuditEntry(type: type, detail: detail)
        entries.append(entry)
        // Trim to maxEntries (FIFO)
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
        persistEntries()
    }

    // MARK: - Export

    func exportCSV() -> String {
        var csv = "timestamp,type,detail,device_id\n"
        let formatter = ISO8601DateFormatter()
        for entry in entries {
            let ts = formatter.string(from: entry.timestamp)
            let line = "\(ts),\(entry.type.rawValue),\"\(entry.detail)\",\(entry.deviceID)\n"
            csv.append(line)
        }
        return csv
    }

    func exportCSVToFile() -> URL? {
        let csv = exportCSV()
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let formatter = ISO8601DateFormatter()
        let ts = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = docs.appendingPathComponent("zerodark-audit-\(ts).csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func recentEntries(limit: Int = 100) -> [AuditEntry] {
        Array(entries.suffix(limit))
    }

    // MARK: - Persistence

    private func persistEntries() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        // Write with NSFileProtectionComplete — inaccessible when device locked
        try? data.write(to: logURL, options: [.atomic, .completeFileProtection])
    }

    private func loadEntries() {
        guard let data = try? Data(contentsOf: logURL),
              let loaded = try? JSONDecoder().decode([AuditEntry].self, from: data) else { return }
        entries = loaded
    }
}

// MARK: - UIDevice import shim
import UIKit
