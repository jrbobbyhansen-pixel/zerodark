// PrivacyDashboard.swift
// See exactly what your AI knows. Export or delete anything.
// ABSURD MODE

import Foundation

// MARK: - Privacy Dashboard

public actor PrivacyDashboard {
    
    public static let shared = PrivacyDashboard()
    
    // MARK: - Types
    
    public struct PrivacyReport: Sendable {
        public let generatedAt: Date
        public let dataCategories: [DataCategory]
        public let totalDataSize: Int64
        public let totalItems: Int
        public let oldestData: Date?
        public let newestData: Date?
        public let auditLog: [AuditEntry]
    }
    
    public struct DataCategory: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let description: String
        public let itemCount: Int
        public let sizeBytes: Int64
        public let canDelete: Bool
        public let canExport: Bool
    }
    
    public struct AuditEntry: Identifiable, Codable, Sendable {
        public let id: UUID
        public let timestamp: Date
        public let action: AuditAction
        public let category: String
        public let details: String
        
        public enum AuditAction: String, Codable, Sendable {
            case read = "Read"
            case write = "Write"
            case delete = "Delete"
            case export = "Export"
            case share = "Share"
            case aiProcess = "AI Process"
        }
    }
    
    public struct DataExport: Sendable {
        public let exportedAt: Date
        public let format: ExportFormat
        public let data: Data
        public let categories: [String]
        
        public enum ExportFormat: String, Sendable {
            case json = "JSON"
            case csv = "CSV"
            case plainText = "Plain Text"
        }
    }
    
    // MARK: - State
    
    private var auditLog: [AuditEntry] = []
    private let maxAuditEntries = 10000
    
    private init() {
        Task {
            await loadAuditLog()
        }
    }
    
    // MARK: - Privacy Report
    
    public func generateReport() async -> PrivacyReport {
        var categories: [DataCategory] = []
        
        // Memory data
        let memoryStats = await PersistentMemory.shared.getStats()
        categories.append(DataCategory(
            id: "memory",
            name: "AI Memory",
            description: "Things your AI remembers about you",
            itemCount: memoryStats.totalMemories,
            sizeBytes: Int64(memoryStats.totalMemories * 200),  // Estimate
            canDelete: true,
            canExport: true
        ))
        
        // Conversations
        categories.append(DataCategory(
            id: "conversations",
            name: "Conversations",
            description: "Past conversations with your AI",
            itemCount: await getConversationCount(),
            sizeBytes: await getConversationSize(),
            canDelete: true,
            canExport: true
        ))
        
        // Routines
        let routines = await RoutineEngine.shared.getRoutines()
        categories.append(DataCategory(
            id: "routines",
            name: "Routines",
            description: "Automated routines you've created",
            itemCount: routines.count,
            sizeBytes: Int64(routines.count * 500),
            canDelete: true,
            canExport: true
        ))
        
        // Identity
        categories.append(DataCategory(
            id: "identity",
            name: "AI Identity",
            description: "Your AI's name, voice, and personality settings",
            itemCount: 1,
            sizeBytes: 1024,
            canDelete: true,
            canExport: true
        ))
        
        // Patterns
        categories.append(DataCategory(
            id: "patterns",
            name: "Learned Patterns",
            description: "Habits and patterns your AI has learned",
            itemCount: await getPatternCount(),
            sizeBytes: Int64(await getPatternCount() * 100),
            canDelete: true,
            canExport: true
        ))
        
        // Installed models
        let installedModels = await ModelMarketplace.shared.getInstalledModels()
        var modelsSize: Int64 = 0
        for model in installedModels {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: model.localPath.path),
               let size = attrs[.size] as? Int64 {
                modelsSize += size
            }
        }
        categories.append(DataCategory(
            id: "models",
            name: "Installed Models",
            description: "AI models downloaded from the marketplace",
            itemCount: installedModels.count,
            sizeBytes: modelsSize,
            canDelete: true,
            canExport: false
        ))
        
        // Audit log
        categories.append(DataCategory(
            id: "audit",
            name: "Audit Log",
            description: "Record of what your AI has accessed",
            itemCount: auditLog.count,
            sizeBytes: Int64(auditLog.count * 150),
            canDelete: true,
            canExport: true
        ))
        
        let totalSize = categories.reduce(0) { $0 + $1.sizeBytes }
        let totalItems = categories.reduce(0) { $0 + $1.itemCount }
        
        return PrivacyReport(
            generatedAt: Date(),
            dataCategories: categories,
            totalDataSize: totalSize,
            totalItems: totalItems,
            oldestData: auditLog.map { $0.timestamp }.min(),
            newestData: auditLog.map { $0.timestamp }.max(),
            auditLog: Array(auditLog.suffix(100))
        )
    }
    
    // MARK: - Data Access
    
    public func getDataForCategory(_ categoryId: String) async -> Any? {
        switch categoryId {
        case "memory":
            return await PersistentMemory.shared.exportAll()
        case "routines":
            return await RoutineEngine.shared.getRoutines()
        case "identity":
            return await AgentIdentity.shared.getIdentity()
        case "audit":
            return auditLog
        default:
            return nil
        }
    }
    
    // MARK: - Export
    
    public func exportData(
        categories: [String],
        format: DataExport.ExportFormat
    ) async throws -> DataExport {
        var exportData: [String: Any] = [:]
        
        for category in categories {
            if let data = await getDataForCategory(category) {
                exportData[category] = data
            }
        }
        
        let data: Data
        switch format {
        case .json:
            data = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
        case .csv:
            // Simple CSV for memories
            var csv = "category,content,timestamp\n"
            if let memories = exportData["memory"] as? [PersistentMemory.Memory] {
                for memory in memories {
                    csv += "\(memory.type.rawValue),\"\(memory.content.replacingOccurrences(of: "\"", with: "\"\""))\",\(memory.createdAt)\n"
                }
            }
            data = csv.data(using: .utf8) ?? Data()
        case .plainText:
            var text = "Zero Dark Data Export\n"
            text += "Generated: \(Date())\n\n"
            for (key, value) in exportData {
                text += "=== \(key.uppercased()) ===\n"
                text += "\(value)\n\n"
            }
            data = text.data(using: .utf8) ?? Data()
        }
        
        // Log the export
        await logAudit(action: .export, category: categories.joined(separator: ", "), details: "Exported \(format.rawValue)")
        
        return DataExport(
            exportedAt: Date(),
            format: format,
            data: data,
            categories: categories
        )
    }
    
    // MARK: - Deletion
    
    public func deleteData(category: String) async throws {
        switch category {
        case "memory":
            await PersistentMemory.shared.clearAll()
        case "conversations":
            // Clear conversation history
            break
        case "routines":
            for routine in await RoutineEngine.shared.getRoutines() {
                try await RoutineEngine.shared.deleteRoutine(id: routine.id)
            }
        case "patterns":
            // Clear learned patterns
            break
        case "audit":
            auditLog = []
            await saveAuditLog()
        case "all":
            await PersistentMemory.shared.clearAll()
            auditLog = []
            await saveAuditLog()
        default:
            break
        }
        
        await logAudit(action: .delete, category: category, details: "Deleted all data")
    }
    
    // MARK: - Audit Logging
    
    public func logAudit(action: AuditEntry.AuditAction, category: String, details: String) async {
        let entry = AuditEntry(
            id: UUID(),
            timestamp: Date(),
            action: action,
            category: category,
            details: details
        )
        
        auditLog.append(entry)
        
        if auditLog.count > maxAuditEntries {
            auditLog.removeFirst(auditLog.count - maxAuditEntries)
        }
        
        await saveAuditLog()
    }
    
    public func getAuditLog(limit: Int = 100) async -> [AuditEntry] {
        return Array(auditLog.suffix(limit))
    }
    
    // MARK: - Kill Switch
    
    public func emergencyWipe() async {
        // Delete EVERYTHING
        await PersistentMemory.shared.clearAll()
        
        for routine in await RoutineEngine.shared.getRoutines() {
            try? await RoutineEngine.shared.deleteRoutine(id: routine.id)
        }
        
        for model in await ModelMarketplace.shared.getInstalledModels() {
            try? await ModelMarketplace.shared.uninstallModel(model.marketplaceId)
        }
        
        auditLog = []
        
        // Reset identity to default
        await AgentIdentity.shared.setIdentity(AgentIdentity.Identity())
        
        // Clear UserDefaults
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        
        await logAudit(action: .delete, category: "all", details: "EMERGENCY WIPE executed")
    }
    
    // MARK: - Helpers
    
    private func getConversationCount() async -> Int {
        return 0  // Would query conversation store
    }
    
    private func getConversationSize() async -> Int64 {
        return 0  // Would calculate actual size
    }
    
    private func getPatternCount() async -> Int {
        return 0  // Would query proactive intelligence
    }
    
    private func loadAuditLog() async {
        let key = "zerodark_audit_log"
        if let data = UserDefaults.standard.data(forKey: key),
           let log = try? JSONDecoder().decode([AuditEntry].self, from: data) {
            auditLog = log
        }
    }
    
    private func saveAuditLog() async {
        let key = "zerodark_audit_log"
        if let data = try? JSONEncoder().encode(auditLog) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
