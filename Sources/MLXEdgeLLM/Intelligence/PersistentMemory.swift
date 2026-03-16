//
//  PersistentMemory.swift
//  ZeroDark
//
//  The memory system Siri wishes it had.
//  All on-device. All private. Actually remembers.
//
//  SQLite-based for portability and open source compatibility.
//

import Foundation
import SQLite3

// MARK: - Persistent Memory System

@MainActor
public class PersistentMemory: ObservableObject {
    public static let shared = PersistentMemory()
    
    private var db: OpaquePointer?
    private let dbPath: String
    
    // Published stats
    @Published public var conversationCount: Int = 0
    @Published public var messageCount: Int = 0
    @Published public var factCount: Int = 0
    @Published public var lastUpdated: Date?
    
    // MARK: - Initialization
    
    public init() {
        // Store in Documents for persistence and user access
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dbPath = documentsPath.appendingPathComponent("zerodark_memory.sqlite").path
        
        openDatabase()
        createTables()
        loadStats()
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    // MARK: - Database Setup
    
    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("❌ Failed to open database at \(dbPath)")
        } else {
            print("✅ Memory database opened at \(dbPath)")
        }
    }
    
    private func createTables() {
        // Conversations table
        let createConversations = """
        CREATE TABLE IF NOT EXISTS conversations (
            id TEXT PRIMARY KEY,
            title TEXT,
            created_at REAL,
            updated_at REAL
        );
        """
        
        // Messages table
        let createMessages = """
        CREATE TABLE IF NOT EXISTS messages (
            id TEXT PRIMARY KEY,
            conversation_id TEXT,
            role TEXT,
            content TEXT,
            tool_used TEXT,
            created_at REAL,
            FOREIGN KEY(conversation_id) REFERENCES conversations(id)
        );
        """
        
        // Knowledge graph - facts
        let createFacts = """
        CREATE TABLE IF NOT EXISTS facts (
            id TEXT PRIMARY KEY,
            category TEXT,
            subject TEXT,
            predicate TEXT,
            object TEXT,
            confidence REAL,
            source_message_id TEXT,
            created_at REAL,
            last_accessed REAL,
            access_count INTEGER DEFAULT 0
        );
        """
        
        // Knowledge graph - entities
        let createEntities = """
        CREATE TABLE IF NOT EXISTS entities (
            id TEXT PRIMARY KEY,
            name TEXT,
            type TEXT,
            attributes TEXT,
            created_at REAL
        );
        """
        
        // Full-text search index for messages
        let createFTS = """
        CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
            content,
            content=messages,
            content_rowid=rowid
        );
        """
        
        executeSQL(createConversations)
        executeSQL(createMessages)
        executeSQL(createFacts)
        executeSQL(createEntities)
        // FTS might fail on older iOS, that's ok
        executeSQL(createFTS)
        
        // Create indexes
        executeSQL("CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id);")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_facts_category ON facts(category);")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_facts_subject ON facts(subject);")
    }
    
    private func executeSQL(_ sql: String) {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) != SQLITE_DONE {
                // Ignore errors for FTS which might not be supported
            }
        }
        sqlite3_finalize(statement)
    }
    
    private func loadStats() {
        conversationCount = countTable("conversations")
        messageCount = countTable("messages")
        factCount = countTable("facts")
    }
    
    private func countTable(_ table: String) -> Int {
        var count = 0
        var statement: OpaquePointer?
        let sql = "SELECT COUNT(*) FROM \(table)"
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        return count
    }
    
    // MARK: - Conversation Management
    
    public func createConversation(title: String? = nil) -> String {
        let id = UUID().uuidString
        let now = Date().timeIntervalSince1970
        let actualTitle = title ?? "Conversation \(conversationCount + 1)"
        
        let sql = "INSERT INTO conversations (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, id, -1, nil)
            sqlite3_bind_text(statement, 2, actualTitle, -1, nil)
            sqlite3_bind_double(statement, 3, now)
            sqlite3_bind_double(statement, 4, now)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
        
        conversationCount += 1
        return id
    }
    
    public func getConversations(limit: Int = 50) -> [MemoryConversation] {
        var conversations: [MemoryConversation] = []
        let sql = "SELECT id, title, created_at, updated_at FROM conversations ORDER BY updated_at DESC LIMIT ?"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(limit))
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let title = String(cString: sqlite3_column_text(statement, 1))
                let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
                let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
                
                conversations.append(MemoryConversation(id: id, title: title, createdAt: createdAt, updatedAt: updatedAt))
            }
        }
        sqlite3_finalize(statement)
        return conversations
    }
    
    // MARK: - Message Management
    
    public func saveMessage(conversationId: String, role: String, content: String, toolUsed: String? = nil) {
        let id = UUID().uuidString
        let now = Date().timeIntervalSince1970
        
        let sql = "INSERT INTO messages (id, conversation_id, role, content, tool_used, created_at) VALUES (?, ?, ?, ?, ?, ?)"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, id, -1, nil)
            sqlite3_bind_text(statement, 2, conversationId, -1, nil)
            sqlite3_bind_text(statement, 3, role, -1, nil)
            sqlite3_bind_text(statement, 4, content, -1, nil)
            sqlite3_bind_text(statement, 5, toolUsed ?? "", -1, nil)
            sqlite3_bind_double(statement, 6, now)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
        
        // Update conversation timestamp
        let updateSQL = "UPDATE conversations SET updated_at = ? WHERE id = ?"
        if sqlite3_prepare_v2(db, updateSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_double(statement, 1, now)
            sqlite3_bind_text(statement, 2, conversationId, -1, nil)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
        
        messageCount += 1
        lastUpdated = Date()
        
        // Extract facts from user messages
        if role == "user" {
            Task {
                await extractFacts(from: content, messageId: id)
            }
        }
    }
    
    public func getMessages(conversationId: String) -> [MemoryMessage] {
        var messages: [MemoryMessage] = []
        let sql = "SELECT id, role, content, tool_used, created_at FROM messages WHERE conversation_id = ? ORDER BY created_at ASC"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, conversationId, -1, nil)
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let role = String(cString: sqlite3_column_text(statement, 1))
                let content = String(cString: sqlite3_column_text(statement, 2))
                let toolUsed = String(cString: sqlite3_column_text(statement, 3))
                let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
                
                messages.append(MemoryMessage(
                    id: id,
                    role: role,
                    content: content,
                    toolUsed: toolUsed.isEmpty ? nil : toolUsed,
                    createdAt: createdAt
                ))
            }
        }
        sqlite3_finalize(statement)
        return messages
    }
    
    // MARK: - Knowledge Graph
    
    public func saveFact(category: String, subject: String, predicate: String, object: String, confidence: Double = 1.0, sourceMessageId: String? = nil) {
        let id = UUID().uuidString
        let now = Date().timeIntervalSince1970
        
        // Check if similar fact exists
        let existingId = findSimilarFact(subject: subject, predicate: predicate)
        
        if let existing = existingId {
            // Update existing fact
            let sql = "UPDATE facts SET object = ?, confidence = ?, last_accessed = ?, access_count = access_count + 1 WHERE id = ?"
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, object, -1, nil)
                sqlite3_bind_double(statement, 2, confidence)
                sqlite3_bind_double(statement, 3, now)
                sqlite3_bind_text(statement, 4, existing, -1, nil)
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        } else {
            // Insert new fact
            let sql = "INSERT INTO facts (id, category, subject, predicate, object, confidence, source_message_id, created_at, last_accessed, access_count) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1)"
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, id, -1, nil)
                sqlite3_bind_text(statement, 2, category, -1, nil)
                sqlite3_bind_text(statement, 3, subject, -1, nil)
                sqlite3_bind_text(statement, 4, predicate, -1, nil)
                sqlite3_bind_text(statement, 5, object, -1, nil)
                sqlite3_bind_double(statement, 6, confidence)
                sqlite3_bind_text(statement, 7, sourceMessageId ?? "", -1, nil)
                sqlite3_bind_double(statement, 8, now)
                sqlite3_bind_double(statement, 9, now)
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
            factCount += 1
        }
    }
    
    private func findSimilarFact(subject: String, predicate: String) -> String? {
        let sql = "SELECT id FROM facts WHERE LOWER(subject) = LOWER(?) AND LOWER(predicate) = LOWER(?)"
        var statement: OpaquePointer?
        var result: String?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, subject, -1, nil)
            sqlite3_bind_text(statement, 2, predicate, -1, nil)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                result = String(cString: sqlite3_column_text(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        return result
    }
    
    public func getFacts(category: String? = nil, limit: Int = 50) -> [MemoryFact] {
        var facts: [MemoryFact] = []
        var sql = "SELECT id, category, subject, predicate, object, confidence, created_at FROM facts"
        if category != nil {
            sql += " WHERE category = ?"
        }
        sql += " ORDER BY last_accessed DESC LIMIT ?"
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            var paramIndex: Int32 = 1
            if let cat = category {
                sqlite3_bind_text(statement, paramIndex, cat, -1, nil)
                paramIndex += 1
            }
            sqlite3_bind_int(statement, paramIndex, Int32(limit))
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let cat = String(cString: sqlite3_column_text(statement, 1))
                let subject = String(cString: sqlite3_column_text(statement, 2))
                let predicate = String(cString: sqlite3_column_text(statement, 3))
                let object = String(cString: sqlite3_column_text(statement, 4))
                let confidence = sqlite3_column_double(statement, 5)
                let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
                
                facts.append(MemoryFact(
                    id: id,
                    category: cat,
                    subject: subject,
                    predicate: predicate,
                    object: object,
                    confidence: confidence,
                    createdAt: createdAt
                ))
            }
        }
        sqlite3_finalize(statement)
        return facts
    }
    
    // MARK: - Fact Extraction (Auto-learn from conversations)
    
    private func extractFacts(from text: String, messageId: String) async {
        let lower = text.lowercased()
        
        // Pattern: "My name is X" or "I'm X" or "I am X"
        if let match = lower.range(of: "my name is ") {
            let name = String(text[match.upperBound...]).components(separatedBy: CharacterSet.alphanumerics.inverted).first ?? ""
            if !name.isEmpty {
                saveFact(category: "personal", subject: "user", predicate: "name", object: name.capitalized, sourceMessageId: messageId)
            }
        }
        
        // Pattern: "I live in X" or "I'm from X"
        if let match = lower.range(of: "i live in ") ?? lower.range(of: "i'm from ") ?? lower.range(of: "i am from ") {
            let location = String(text[match.upperBound...]).components(separatedBy: CharacterSet.alphanumerics.inverted).prefix(3).joined(separator: " ")
            if !location.isEmpty {
                saveFact(category: "personal", subject: "user", predicate: "location", object: location.capitalized, sourceMessageId: messageId)
            }
        }
        
        // Pattern: "I work at X" or "I work for X"
        if let match = lower.range(of: "i work at ") ?? lower.range(of: "i work for ") {
            let company = String(text[match.upperBound...]).components(separatedBy: CharacterSet(charactersIn: ".,!?")).first ?? ""
            if !company.isEmpty {
                saveFact(category: "professional", subject: "user", predicate: "employer", object: company.trimmingCharacters(in: .whitespaces), sourceMessageId: messageId)
            }
        }
        
        // Pattern: "I like X" or "I love X" or "I prefer X"
        for trigger in ["i like ", "i love ", "i prefer "] {
            if let match = lower.range(of: trigger) {
                let thing = String(text[match.upperBound...]).components(separatedBy: CharacterSet(charactersIn: ".,!?")).first ?? ""
                if !thing.isEmpty && thing.count < 50 {
                    saveFact(category: "preferences", subject: "user", predicate: "likes", object: thing.trimmingCharacters(in: .whitespaces), sourceMessageId: messageId)
                }
            }
        }
        
        // Pattern: "I hate X" or "I don't like X"
        for trigger in ["i hate ", "i don't like ", "i dislike "] {
            if let match = lower.range(of: trigger) {
                let thing = String(text[match.upperBound...]).components(separatedBy: CharacterSet(charactersIn: ".,!?")).first ?? ""
                if !thing.isEmpty && thing.count < 50 {
                    saveFact(category: "preferences", subject: "user", predicate: "dislikes", object: thing.trimmingCharacters(in: .whitespaces), sourceMessageId: messageId)
                }
            }
        }
        
        // Pattern: "My X is Y" (e.g., "My birthday is March 15")
        let myPattern = try? NSRegularExpression(pattern: "my (\\w+) is ([\\w\\s]+)", options: .caseInsensitive)
        if let match = myPattern?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let subjectRange = Range(match.range(at: 1), in: text),
               let objectRange = Range(match.range(at: 2), in: text) {
                let subject = String(text[subjectRange])
                let object = String(text[objectRange]).components(separatedBy: CharacterSet(charactersIn: ".,!?")).first ?? ""
                if !subject.isEmpty && !object.isEmpty && object.count < 50 {
                    saveFact(category: "personal", subject: "user", predicate: subject.lowercased(), object: object.trimmingCharacters(in: .whitespaces), sourceMessageId: messageId)
                }
            }
        }
    }
    
    // MARK: - Search
    
    public func searchMessages(query: String, limit: Int = 20) -> [MemoryMessage] {
        var messages: [MemoryMessage] = []
        let sql = "SELECT id, role, content, tool_used, created_at FROM messages WHERE content LIKE ? ORDER BY created_at DESC LIMIT ?"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, "%\(query)%", -1, nil)
            sqlite3_bind_int(statement, 2, Int32(limit))
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let role = String(cString: sqlite3_column_text(statement, 1))
                let content = String(cString: sqlite3_column_text(statement, 2))
                let toolUsed = String(cString: sqlite3_column_text(statement, 3))
                let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
                
                messages.append(MemoryMessage(
                    id: id,
                    role: role,
                    content: content,
                    toolUsed: toolUsed.isEmpty ? nil : toolUsed,
                    createdAt: createdAt
                ))
            }
        }
        sqlite3_finalize(statement)
        return messages
    }
    
    public func searchFacts(query: String) -> [MemoryFact] {
        var facts: [MemoryFact] = []
        let sql = "SELECT id, category, subject, predicate, object, confidence, created_at FROM facts WHERE subject LIKE ? OR object LIKE ? ORDER BY last_accessed DESC LIMIT 20"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, "%\(query)%", -1, nil)
            sqlite3_bind_text(statement, 2, "%\(query)%", -1, nil)
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let category = String(cString: sqlite3_column_text(statement, 1))
                let subject = String(cString: sqlite3_column_text(statement, 2))
                let predicate = String(cString: sqlite3_column_text(statement, 3))
                let object = String(cString: sqlite3_column_text(statement, 4))
                let confidence = sqlite3_column_double(statement, 5)
                let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
                
                facts.append(MemoryFact(
                    id: id,
                    category: category,
                    subject: subject,
                    predicate: predicate,
                    object: object,
                    confidence: confidence,
                    createdAt: createdAt
                ))
            }
        }
        sqlite3_finalize(statement)
        return facts
    }
    
    // MARK: - Context Retrieval (for AI prompts)
    
    public func getRelevantContext(for query: String) -> String {
        var context = ""
        
        // Get relevant facts
        let facts = searchFacts(query: query)
        if !facts.isEmpty {
            context += "Known facts:\n"
            for fact in facts.prefix(5) {
                context += "- \(fact.subject) \(fact.predicate): \(fact.object)\n"
            }
            context += "\n"
        }
        
        // Get recent messages mentioning similar topics
        let messages = searchMessages(query: query, limit: 5)
        if !messages.isEmpty {
            context += "Previous relevant conversations:\n"
            for msg in messages {
                let role = msg.role == "user" ? "User" : "Assistant"
                let preview = String(msg.content.prefix(100))
                context += "- \(role): \(preview)...\n"
            }
        }
        
        return context
    }
    
    // MARK: - Export (for users to backup their data)
    
    public func exportToJSON() -> String {
        var export: [String: Any] = [:]
        
        // Export conversations
        var conversations: [[String: Any]] = []
        for conv in getConversations(limit: 1000) {
            let messages = getMessages(conversationId: conv.id)
            conversations.append([
                "id": conv.id,
                "title": conv.title,
                "created_at": conv.createdAt.timeIntervalSince1970,
                "messages": messages.map { [
                    "role": $0.role,
                    "content": $0.content,
                    "tool_used": $0.toolUsed ?? "",
                    "created_at": $0.createdAt.timeIntervalSince1970
                ]}
            ])
        }
        export["conversations"] = conversations
        
        // Export facts
        let facts = getFacts(limit: 1000)
        export["facts"] = facts.map { [
            "category": $0.category,
            "subject": $0.subject,
            "predicate": $0.predicate,
            "object": $0.object,
            "confidence": $0.confidence
        ]}
        
        export["exported_at"] = Date().timeIntervalSince1970
        export["version"] = "1.0"
        
        if let data = try? JSONSerialization.data(withJSONObject: export, options: .prettyPrinted),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{}"
    }
    
    // MARK: - Clear Data
    
    public func clearAllData() {
        executeSQL("DELETE FROM messages")
        executeSQL("DELETE FROM conversations")
        executeSQL("DELETE FROM facts")
        executeSQL("DELETE FROM entities")
        loadStats()
    }
}

// MARK: - Data Models

public struct MemoryConversation: Identifiable {
    public let id: String
    public let title: String
    public let createdAt: Date
    public let updatedAt: Date
}

public struct MemoryMessage: Identifiable {
    public let id: String
    public let role: String
    public let content: String
    public let toolUsed: String?
    public let createdAt: Date
}

public struct MemoryFact: Identifiable {
    public let id: String
    public let category: String
    public let subject: String
    public let predicate: String
    public let object: String
    public let confidence: Double
    public let createdAt: Date
    
    public var description: String {
        "\(subject) \(predicate) \(object)"
    }
}
