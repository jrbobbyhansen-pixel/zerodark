//
//  DeepIntelligence.swift
//  ZeroDark
//
//  What Siri wishes it had: proactive, learning, context-aware intelligence.
//  All on-device. All private. Actually useful.
//

import Foundation
import SQLite3

// MARK: - Deep Intelligence Engine

@MainActor
public class DeepIntelligence: ObservableObject {
    public static let shared = DeepIntelligence()
    
    private let memory = PersistentMemory.shared
    private var db: OpaquePointer?
    private let dbPath: String
    
    // Published state
    @Published public var habitCount: Int = 0
    @Published public var correctionCount: Int = 0
    @Published public var proactiveSuggestion: String?
    
    // MARK: - Initialization
    
    public init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dbPath = documentsPath.appendingPathComponent("zerodark_intelligence.sqlite").path
        
        openDatabase()
        createTables()
        loadStats()
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("❌ Failed to open intelligence database")
        }
    }
    
    private func createTables() {
        // Habits table - tracks patterns
        executeSQL("""
        CREATE TABLE IF NOT EXISTS habits (
            id TEXT PRIMARY KEY,
            pattern TEXT,
            action TEXT,
            frequency INTEGER DEFAULT 1,
            last_triggered REAL,
            day_of_week INTEGER,
            hour_of_day INTEGER,
            created_at REAL
        );
        """)
        
        // Corrections table - learns from mistakes
        executeSQL("""
        CREATE TABLE IF NOT EXISTS corrections (
            id TEXT PRIMARY KEY,
            original_query TEXT,
            original_response TEXT,
            corrected_response TEXT,
            correction_type TEXT,
            created_at REAL
        );
        """)
        
        // Context table - semantic relationships
        executeSQL("""
        CREATE TABLE IF NOT EXISTS context_links (
            id TEXT PRIMARY KEY,
            entity_a TEXT,
            relationship TEXT,
            entity_b TEXT,
            strength REAL DEFAULT 1.0,
            created_at REAL
        );
        """)
        
        // Interaction patterns - for proactive suggestions
        executeSQL("""
        CREATE TABLE IF NOT EXISTS interaction_patterns (
            id TEXT PRIMARY KEY,
            pattern_type TEXT,
            pattern_value TEXT,
            count INTEGER DEFAULT 1,
            last_seen REAL
        );
        """)
        
        // Create indexes
        executeSQL("CREATE INDEX IF NOT EXISTS idx_habits_dow ON habits(day_of_week);")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_habits_hour ON habits(hour_of_day);")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_patterns_type ON interaction_patterns(pattern_type);")
    }
    
    private func executeSQL(_ sql: String) {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }
    
    private func loadStats() {
        habitCount = countTable("habits")
        correctionCount = countTable("corrections")
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
    
    // MARK: - 1. HABIT DETECTION
    
    /// Track when user does something repeatedly
    public func trackInteraction(action: String, category: String) {
        let now = Date()
        let calendar = Calendar.current
        let dayOfWeek = calendar.component(.weekday, from: now)
        let hourOfDay = calendar.component(.hour, from: now)
        
        // Check if similar habit exists
        let pattern = "\(category)_\(dayOfWeek)_\(hourOfDay)"
        
        let checkSQL = "SELECT id, frequency FROM habits WHERE pattern = ?"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, checkSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, pattern, -1, nil)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                // Update existing
                let existingId = String(cString: sqlite3_column_text(statement, 0))
                let frequency = sqlite3_column_int(statement, 1)
                sqlite3_finalize(statement)
                
                let updateSQL = "UPDATE habits SET frequency = ?, last_triggered = ?, action = ? WHERE id = ?"
                if sqlite3_prepare_v2(db, updateSQL, -1, &statement, nil) == SQLITE_OK {
                    sqlite3_bind_int(statement, 1, frequency + 1)
                    sqlite3_bind_double(statement, 2, now.timeIntervalSince1970)
                    sqlite3_bind_text(statement, 3, action, -1, nil)
                    sqlite3_bind_text(statement, 4, existingId, -1, nil)
                    sqlite3_step(statement)
                }
            } else {
                sqlite3_finalize(statement)
                
                // Insert new
                let id = UUID().uuidString
                let insertSQL = "INSERT INTO habits (id, pattern, action, frequency, last_triggered, day_of_week, hour_of_day, created_at) VALUES (?, ?, ?, 1, ?, ?, ?, ?)"
                if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
                    sqlite3_bind_text(statement, 1, id, -1, nil)
                    sqlite3_bind_text(statement, 2, pattern, -1, nil)
                    sqlite3_bind_text(statement, 3, action, -1, nil)
                    sqlite3_bind_double(statement, 4, now.timeIntervalSince1970)
                    sqlite3_bind_int(statement, 5, Int32(dayOfWeek))
                    sqlite3_bind_int(statement, 6, Int32(hourOfDay))
                    sqlite3_bind_double(statement, 7, now.timeIntervalSince1970)
                    sqlite3_step(statement)
                }
                habitCount += 1
            }
        }
        sqlite3_finalize(statement)
    }
    
    /// Get proactive suggestion based on current time/patterns
    public func getProactiveSuggestion() -> String? {
        let now = Date()
        let calendar = Calendar.current
        let dayOfWeek = calendar.component(.weekday, from: now)
        let hourOfDay = calendar.component(.hour, from: now)
        
        // Find habits that match current time with frequency > 2
        let sql = "SELECT action, frequency FROM habits WHERE day_of_week = ? AND hour_of_day = ? AND frequency > 2 ORDER BY frequency DESC LIMIT 1"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(dayOfWeek))
            sqlite3_bind_int(statement, 2, Int32(hourOfDay))
            
            if sqlite3_step(statement) == SQLITE_ROW {
                let action = String(cString: sqlite3_column_text(statement, 0))
                let frequency = sqlite3_column_int(statement, 1)
                sqlite3_finalize(statement)
                
                proactiveSuggestion = "You often \(action) around this time (\(frequency)x)"
                return proactiveSuggestion
            }
        }
        sqlite3_finalize(statement)
        return nil
    }
    
    // MARK: - 2. LEARNING FROM CORRECTIONS
    
    /// Log when user corrects the AI
    public func logCorrection(originalQuery: String, originalResponse: String, correctedResponse: String, correctionType: String = "explicit") {
        let id = UUID().uuidString
        let now = Date().timeIntervalSince1970
        
        let sql = "INSERT INTO corrections (id, original_query, original_response, corrected_response, correction_type, created_at) VALUES (?, ?, ?, ?, ?, ?)"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, id, -1, nil)
            sqlite3_bind_text(statement, 2, originalQuery, -1, nil)
            sqlite3_bind_text(statement, 3, originalResponse, -1, nil)
            sqlite3_bind_text(statement, 4, correctedResponse, -1, nil)
            sqlite3_bind_text(statement, 5, correctionType, -1, nil)
            sqlite3_bind_double(statement, 6, now)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
        
        correctionCount += 1
        
        // Extract learning as a fact
        extractLearning(from: originalQuery, correction: correctedResponse)
    }
    
    /// Check if we have a correction for similar query
    public func getRelevantCorrection(for query: String) -> String? {
        // Simple keyword matching for efficiency
        let keywords = query.lowercased().components(separatedBy: .whitespaces).filter { $0.count > 3 }
        
        for keyword in keywords {
            let sql = "SELECT corrected_response FROM corrections WHERE original_query LIKE ? ORDER BY created_at DESC LIMIT 1"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, "%\(keyword)%", -1, nil)
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    let correction = String(cString: sqlite3_column_text(statement, 0))
                    sqlite3_finalize(statement)
                    return correction
                }
            }
            sqlite3_finalize(statement)
        }
        return nil
    }
    
    private func extractLearning(from query: String, correction: String) {
        // Extract preference from correction
        let lower = correction.lowercased()
        
        if lower.contains("prefer") || lower.contains("like") || lower.contains("want") {
            memory.saveFact(
                category: "learned_preferences",
                subject: "user",
                predicate: "prefers",
                object: correction.prefix(100).description
            )
        }
    }
    
    // MARK: - 3. SEMANTIC CONTEXT
    
    /// Link two entities together
    public func linkEntities(_ entityA: String, relationship: String, _ entityB: String, strength: Double = 1.0) {
        let id = UUID().uuidString
        let now = Date().timeIntervalSince1970
        
        // Check if link exists
        let checkSQL = "SELECT id, strength FROM context_links WHERE entity_a = ? AND entity_b = ?"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, checkSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, entityA.lowercased(), -1, nil)
            sqlite3_bind_text(statement, 2, entityB.lowercased(), -1, nil)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                // Strengthen existing link
                let existingId = String(cString: sqlite3_column_text(statement, 0))
                let currentStrength = sqlite3_column_double(statement, 1)
                sqlite3_finalize(statement)
                
                let newStrength = min(10.0, currentStrength + 0.5)
                let updateSQL = "UPDATE context_links SET strength = ?, relationship = ? WHERE id = ?"
                if sqlite3_prepare_v2(db, updateSQL, -1, &statement, nil) == SQLITE_OK {
                    sqlite3_bind_double(statement, 1, newStrength)
                    sqlite3_bind_text(statement, 2, relationship, -1, nil)
                    sqlite3_bind_text(statement, 3, existingId, -1, nil)
                    sqlite3_step(statement)
                }
            } else {
                sqlite3_finalize(statement)
                
                // Create new link
                let insertSQL = "INSERT INTO context_links (id, entity_a, relationship, entity_b, strength, created_at) VALUES (?, ?, ?, ?, ?, ?)"
                if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
                    sqlite3_bind_text(statement, 1, id, -1, nil)
                    sqlite3_bind_text(statement, 2, entityA.lowercased(), -1, nil)
                    sqlite3_bind_text(statement, 3, relationship, -1, nil)
                    sqlite3_bind_text(statement, 4, entityB.lowercased(), -1, nil)
                    sqlite3_bind_double(statement, 5, strength)
                    sqlite3_bind_double(statement, 6, now)
                    sqlite3_step(statement)
                }
            }
        }
        sqlite3_finalize(statement)
    }
    
    /// Get related entities
    public func getRelated(to entity: String) -> [(entity: String, relationship: String, strength: Double)] {
        var results: [(String, String, Double)] = []
        
        let sql = "SELECT entity_b, relationship, strength FROM context_links WHERE entity_a = ? ORDER BY strength DESC LIMIT 10"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, entity.lowercased(), -1, nil)
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let entityB = String(cString: sqlite3_column_text(statement, 0))
                let relationship = String(cString: sqlite3_column_text(statement, 1))
                let strength = sqlite3_column_double(statement, 2)
                results.append((entityB, relationship, strength))
            }
        }
        sqlite3_finalize(statement)
        
        return results
    }
    
    // MARK: - 4. SMART CONTEXT INJECTION
    
    /// Build context string for AI prompt enhancement
    public func buildContextFor(query: String) -> String {
        var context = ""
        
        // 1. Get relevant facts from memory
        let memoryContext = memory.getRelevantContext(for: query)
        if !memoryContext.isEmpty {
            context += memoryContext + "\n"
        }
        
        // 2. Check for relevant corrections
        if let correction = getRelevantCorrection(for: query) {
            context += "Note: User previously clarified: \(correction.prefix(100))\n"
        }
        
        // 3. Get related entities
        let keywords = query.lowercased().components(separatedBy: .whitespaces).filter { $0.count > 3 }
        for keyword in keywords.prefix(2) {
            let related = getRelated(to: keyword)
            if !related.isEmpty {
                for (entity, relationship, _) in related.prefix(2) {
                    context += "Context: \(keyword) \(relationship) \(entity)\n"
                }
            }
        }
        
        // 4. Add proactive suggestion if relevant
        if let suggestion = getProactiveSuggestion() {
            context += "Habit: \(suggestion)\n"
        }
        
        return context
    }
    
    // MARK: - 5. INTERACTION PATTERN TRACKING
    
    /// Track usage patterns
    public func trackPattern(_ type: String, value: String) {
        let sql = "INSERT INTO interaction_patterns (id, pattern_type, pattern_value, count, last_seen) VALUES (?, ?, ?, 1, ?) ON CONFLICT(id) DO UPDATE SET count = count + 1, last_seen = ?"
        
        // For SQLite without UPSERT, check and insert/update
        let checkSQL = "SELECT count FROM interaction_patterns WHERE pattern_type = ? AND pattern_value = ?"
        var statement: OpaquePointer?
        let now = Date().timeIntervalSince1970
        
        if sqlite3_prepare_v2(db, checkSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, type, -1, nil)
            sqlite3_bind_text(statement, 2, value, -1, nil)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                let count = sqlite3_column_int(statement, 0)
                sqlite3_finalize(statement)
                
                let updateSQL = "UPDATE interaction_patterns SET count = ?, last_seen = ? WHERE pattern_type = ? AND pattern_value = ?"
                if sqlite3_prepare_v2(db, updateSQL, -1, &statement, nil) == SQLITE_OK {
                    sqlite3_bind_int(statement, 1, count + 1)
                    sqlite3_bind_double(statement, 2, now)
                    sqlite3_bind_text(statement, 3, type, -1, nil)
                    sqlite3_bind_text(statement, 4, value, -1, nil)
                    sqlite3_step(statement)
                }
            } else {
                sqlite3_finalize(statement)
                
                let insertSQL = "INSERT INTO interaction_patterns (id, pattern_type, pattern_value, count, last_seen) VALUES (?, ?, ?, 1, ?)"
                if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
                    sqlite3_bind_text(statement, 1, UUID().uuidString, -1, nil)
                    sqlite3_bind_text(statement, 2, type, -1, nil)
                    sqlite3_bind_text(statement, 3, value, -1, nil)
                    sqlite3_bind_double(statement, 4, now)
                    sqlite3_step(statement)
                }
            }
        }
        sqlite3_finalize(statement)
    }
    
    /// Get most frequent patterns
    public func getTopPatterns(type: String, limit: Int = 5) -> [(value: String, count: Int)] {
        var results: [(String, Int)] = []
        
        let sql = "SELECT pattern_value, count FROM interaction_patterns WHERE pattern_type = ? ORDER BY count DESC LIMIT ?"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, type, -1, nil)
            sqlite3_bind_int(statement, 2, Int32(limit))
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let value = String(cString: sqlite3_column_text(statement, 0))
                let count = Int(sqlite3_column_int(statement, 1))
                results.append((value, count))
            }
        }
        sqlite3_finalize(statement)
        
        return results
    }
    
    // MARK: - Stats
    
    public func getStats() -> DeepIntelligenceStats {
        return DeepIntelligenceStats(
            habits: habitCount,
            corrections: correctionCount,
            contextLinks: countTable("context_links"),
            patterns: countTable("interaction_patterns")
        )
    }
}

// MARK: - Stats Model

public struct DeepIntelligenceStats {
    public let habits: Int
    public let corrections: Int
    public let contextLinks: Int
    public let patterns: Int
    
    public var total: Int {
        habits + corrections + contextLinks + patterns
    }
}
