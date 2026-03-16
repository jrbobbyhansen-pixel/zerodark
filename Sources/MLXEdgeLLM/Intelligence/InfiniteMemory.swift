//
//  InfiniteMemory.swift
//  ZeroDark
//
//  Inspired by Claude-Mem but way more advanced.
//  True infinite memory with automatic learning, consolidation, and forgetting.
//

import SwiftUI
import Foundation
import SQLite3
import NaturalLanguage
import Accelerate

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: INFINITE MEMORY ARCHITECTURE
// MARK: ═══════════════════════════════════════════════════════════════════

/*
 Human memory has 3 systems:
 1. EPISODIC — Specific experiences ("I talked to Bobby about X on Tuesday")
 2. SEMANTIC — Facts and knowledge ("Bobby likes duck hunting")
 3. PROCEDURAL — How to do things ("When Bobby says 'handle it', just do it")
 
 This system implements all three, plus:
 - Automatic extraction from conversations
 - Memory consolidation (compress old memories)
 - Importance scoring (forget unimportant stuff)
 - Relevant retrieval (pull only what matters NOW)
 - Continuous learning (patterns → rules)
*/

// MARK: - Memory Types

struct EpisodicMemory: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let summary: String           // What happened
    let participants: [String]    // Who was involved
    let topics: [String]          // What it was about
    let emotionalValence: Float   // -1 (negative) to +1 (positive)
    let importance: Float         // 0 to 1
    var accessCount: Int          // How often retrieved
    var lastAccessed: Date
    let embedding: [Float]        // For similarity search
}

struct SemanticMemory: Identifiable, Codable {
    let id: UUID
    let fact: String              // The knowledge
    let category: String          // Type of fact (person, preference, rule, etc.)
    let confidence: Float         // How certain (0-1)
    let sources: [UUID]           // Which episodes taught this
    var contradictions: Int       // Times contradicted
    var confirmations: Int        // Times confirmed
    let createdAt: Date
    var lastConfirmed: Date
    let embedding: [Float]
}

struct ProceduralMemory: Identifiable, Codable {
    let id: UUID
    let trigger: String           // When to apply ("Bobby says 'handle it'")
    let action: String            // What to do ("Make the decision autonomously")
    let examples: [UUID]          // Episodes that taught this
    var successCount: Int         // Times it worked
    var failureCount: Int         // Times it failed
    let createdAt: Date
    var lastUsed: Date
}

// MARK: - Memory System

@MainActor
class InfiniteMemorySystem: ObservableObject {
    static let shared = InfiniteMemorySystem()
    
    // Memory stores
    @Published var episodicCount = 0
    @Published var semanticCount = 0
    @Published var proceduralCount = 0
    @Published var totalTokensSaved = 0
    @Published var compressionRatio: Double = 1.0
    
    // Database
    private var db: OpaquePointer?
    private let dbPath: String
    private let embeddingDim = 384
    
    // Config
    private let maxEpisodicMemories = 10000
    private let consolidationThreshold = 100  // Episodes before consolidation
    private let importanceDecay: Float = 0.95  // Daily decay for unused memories
    private let retrievalLimit = 10
    
    init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dbPath = documentsPath.appendingPathComponent("zerodark_memory.sqlite").path
        setupDatabase()
        loadCounts()
    }
    
    private func setupDatabase() {
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return }
        
        let schema = """
        -- Episodic memories (experiences)
        CREATE TABLE IF NOT EXISTS episodic (
            id TEXT PRIMARY KEY,
            timestamp REAL,
            summary TEXT,
            participants TEXT,  -- JSON array
            topics TEXT,        -- JSON array
            emotional_valence REAL,
            importance REAL,
            access_count INTEGER DEFAULT 0,
            last_accessed REAL,
            embedding BLOB
        );
        
        -- Semantic memories (facts)
        CREATE TABLE IF NOT EXISTS semantic (
            id TEXT PRIMARY KEY,
            fact TEXT,
            category TEXT,
            confidence REAL,
            sources TEXT,       -- JSON array of episode IDs
            contradictions INTEGER DEFAULT 0,
            confirmations INTEGER DEFAULT 0,
            created_at REAL,
            last_confirmed REAL,
            embedding BLOB
        );
        
        -- Procedural memories (rules)
        CREATE TABLE IF NOT EXISTS procedural (
            id TEXT PRIMARY KEY,
            trigger TEXT,
            action TEXT,
            examples TEXT,      -- JSON array of episode IDs
            success_count INTEGER DEFAULT 0,
            failure_count INTEGER DEFAULT 0,
            created_at REAL,
            last_used REAL
        );
        
        -- Working memory (current context)
        CREATE TABLE IF NOT EXISTS working_memory (
            id TEXT PRIMARY KEY,
            content TEXT,
            added_at REAL,
            expires_at REAL
        );
        
        -- Memory indices
        CREATE INDEX IF NOT EXISTS idx_episodic_time ON episodic(timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_episodic_importance ON episodic(importance DESC);
        CREATE INDEX IF NOT EXISTS idx_semantic_category ON semantic(category);
        CREATE INDEX IF NOT EXISTS idx_semantic_confidence ON semantic(confidence DESC);
        """
        
        sqlite3_exec(db, schema, nil, nil, nil)
    }
    
    private func loadCounts() {
        episodicCount = countRows("episodic")
        semanticCount = countRows("semantic")
        proceduralCount = countRows("procedural")
    }
    
    private func countRows(_ table: String) -> Int {
        var stmt: OpaquePointer?
        let sql = "SELECT COUNT(*) FROM \(table)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }
    
    // MARK: - Store Conversation
    
    /// Store a conversation and extract memories
    func processConversation(
        messages: [(role: String, content: String)],
        participants: [String] = ["user", "assistant"]
    ) async {
        // 1. Create episodic memory (the experience)
        let episode = await createEpisode(messages: messages, participants: participants)
        
        // 2. Extract semantic memories (facts)
        let facts = await extractFacts(from: messages)
        for fact in facts {
            await storeFact(fact, source: episode.id)
        }
        
        // 3. Extract procedural memories (rules)
        let rules = await extractRules(from: messages)
        for rule in rules {
            await storeRule(rule, example: episode.id)
        }
        
        // 4. Update counts
        loadCounts()
        
        // 5. Check if consolidation needed
        if episodicCount >= consolidationThreshold {
            Task { await consolidateMemories() }
        }
    }
    
    private func createEpisode(
        messages: [(role: String, content: String)],
        participants: [String]
    ) async -> EpisodicMemory {
        // Summarize the conversation
        let fullText = messages.map { "\($0.role): \($0.content)" }.joined(separator: "\n")
        let summary = await summarize(fullText)
        
        // Extract topics
        let topics = await extractTopics(from: fullText)
        
        // Analyze emotional valence
        let valence = analyzeEmotion(fullText)
        
        // Calculate importance
        let importance = calculateImportance(messages: messages, topics: topics)
        
        // Generate embedding
        let embedding = await generateEmbedding(summary)
        
        let episode = EpisodicMemory(
            id: UUID(),
            timestamp: Date(),
            summary: summary,
            participants: participants,
            topics: topics,
            emotionalValence: valence,
            importance: importance,
            accessCount: 0,
            lastAccessed: Date(),
            embedding: embedding
        )
        
        // Store in database
        await storeEpisode(episode)
        episodicCount += 1
        
        return episode
    }
    
    private func storeEpisode(_ episode: EpisodicMemory) async {
        let sql = """
        INSERT INTO episodic (id, timestamp, summary, participants, topics, 
                              emotional_valence, importance, access_count, last_accessed, embedding)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        
        sqlite3_bind_text(stmt, 1, episode.id.uuidString, -1, nil)
        sqlite3_bind_double(stmt, 2, episode.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, episode.summary, -1, nil)
        
        let participantsJSON = try? JSONEncoder().encode(episode.participants)
        sqlite3_bind_text(stmt, 4, participantsJSON.flatMap { String(data: $0, encoding: .utf8) } ?? "[]", -1, nil)
        
        let topicsJSON = try? JSONEncoder().encode(episode.topics)
        sqlite3_bind_text(stmt, 5, topicsJSON.flatMap { String(data: $0, encoding: .utf8) } ?? "[]", -1, nil)
        
        sqlite3_bind_double(stmt, 6, Double(episode.emotionalValence))
        sqlite3_bind_double(stmt, 7, Double(episode.importance))
        sqlite3_bind_int(stmt, 8, Int32(episode.accessCount))
        sqlite3_bind_double(stmt, 9, episode.lastAccessed.timeIntervalSince1970)
        
        episode.embedding.withUnsafeBytes { ptr in
            sqlite3_bind_blob(stmt, 10, ptr.baseAddress, Int32(ptr.count), nil)
        }
        
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }
    
    // MARK: - Extract Memories
    
    private func extractFacts(from messages: [(role: String, content: String)]) async -> [ExtractedFact] {
        let prompt = """
        Extract factual information from this conversation that should be remembered long-term.
        
        Conversation:
        \(messages.map { "\($0.role): \($0.content)" }.joined(separator: "\n"))
        
        Extract facts in these categories:
        - person: Facts about people (preferences, relationships, roles)
        - preference: User preferences and likes/dislikes
        - decision: Decisions made
        - rule: Rules or guidelines established
        - knowledge: Domain knowledge shared
        
        Format each fact as: CATEGORY|FACT|CONFIDENCE
        Example: person|Bobby prefers direct communication|0.9
        
        Only extract clearly stated facts with high confidence.
        """
        
        let response = await callModel(prompt)
        
        // Parse response
        var facts: [ExtractedFact] = []
        for line in response.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "|")
            if parts.count >= 3,
               let confidence = Float(parts[2].trimmingCharacters(in: .whitespaces)) {
                facts.append(ExtractedFact(
                    category: parts[0].trimmingCharacters(in: .whitespaces),
                    fact: parts[1].trimmingCharacters(in: .whitespaces),
                    confidence: confidence
                ))
            }
        }
        
        return facts
    }
    
    private func extractRules(from messages: [(role: String, content: String)]) async -> [ExtractedRule] {
        let prompt = """
        Extract behavioral rules or patterns from this conversation.
        A rule is: IF [trigger condition] THEN [action to take]
        
        Conversation:
        \(messages.map { "\($0.role): \($0.content)" }.joined(separator: "\n"))
        
        Format: TRIGGER|ACTION
        Example: User says 'handle it'|Make the decision autonomously without asking
        
        Only extract clear patterns that should be applied in future conversations.
        """
        
        let response = await callModel(prompt)
        
        var rules: [ExtractedRule] = []
        for line in response.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "|")
            if parts.count >= 2 {
                rules.append(ExtractedRule(
                    trigger: parts[0].trimmingCharacters(in: .whitespaces),
                    action: parts[1].trimmingCharacters(in: .whitespaces)
                ))
            }
        }
        
        return rules
    }
    
    private func storeFact(_ fact: ExtractedFact, source: UUID) async {
        // Check for existing similar fact
        let embedding = await generateEmbedding(fact.fact)
        let existing = await findSimilarFact(embedding: embedding, threshold: 0.9)
        
        if let existingFact = existing {
            // Update existing: increment confirmations
            let sql = "UPDATE semantic SET confirmations = confirmations + 1, last_confirmed = ? WHERE id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
            sqlite3_bind_text(stmt, 2, existingFact.uuidString, -1, nil)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        } else {
            // Insert new fact
            let id = UUID()
            let sql = """
            INSERT INTO semantic (id, fact, category, confidence, sources, created_at, last_confirmed, embedding)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, nil)
            sqlite3_bind_text(stmt, 2, fact.fact, -1, nil)
            sqlite3_bind_text(stmt, 3, fact.category, -1, nil)
            sqlite3_bind_double(stmt, 4, Double(fact.confidence))
            sqlite3_bind_text(stmt, 5, "[\"\(source.uuidString)\"]", -1, nil)
            sqlite3_bind_double(stmt, 6, Date().timeIntervalSince1970)
            sqlite3_bind_double(stmt, 7, Date().timeIntervalSince1970)
            
            embedding.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, 8, ptr.baseAddress, Int32(ptr.count), nil)
            }
            
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
            semanticCount += 1
        }
    }
    
    private func storeRule(_ rule: ExtractedRule, example: UUID) async {
        // Check for existing similar rule
        let existing = await findSimilarRule(trigger: rule.trigger)
        
        if let existingId = existing {
            // Update: add example, increment success
            let sql = "UPDATE procedural SET success_count = success_count + 1, last_used = ? WHERE id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
            sqlite3_bind_text(stmt, 2, existingId.uuidString, -1, nil)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        } else {
            // Insert new rule
            let id = UUID()
            let sql = """
            INSERT INTO procedural (id, trigger, action, examples, created_at, last_used)
            VALUES (?, ?, ?, ?, ?, ?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, nil)
            sqlite3_bind_text(stmt, 2, rule.trigger, -1, nil)
            sqlite3_bind_text(stmt, 3, rule.action, -1, nil)
            sqlite3_bind_text(stmt, 4, "[\"\(example.uuidString)\"]", -1, nil)
            sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)
            sqlite3_bind_double(stmt, 6, Date().timeIntervalSince1970)
            
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
            proceduralCount += 1
        }
    }
    
    // MARK: - Retrieve Memories
    
    /// Get relevant context for a query
    func retrieveContext(for query: String, limit: Int = 10) async -> RetrievedContext {
        let queryEmbedding = await generateEmbedding(query)
        
        // 1. Find relevant episodic memories
        let episodes = await retrieveEpisodes(embedding: queryEmbedding, limit: limit)
        
        // 2. Find relevant semantic memories
        let facts = await retrieveFacts(embedding: queryEmbedding, limit: limit)
        
        // 3. Find applicable procedural memories
        let rules = await retrieveRules(for: query)
        
        // 4. Calculate token savings
        let fullContextTokens = episodes.reduce(0) { $0 + estimateTokens($1.summary) }
        let compressedTokens = estimateTokens(buildContextString(episodes: episodes, facts: facts, rules: rules))
        totalTokensSaved += (fullContextTokens - compressedTokens)
        compressionRatio = Double(fullContextTokens) / Double(max(1, compressedTokens))
        
        return RetrievedContext(
            episodes: episodes,
            facts: facts,
            rules: rules,
            contextString: buildContextString(episodes: episodes, facts: facts, rules: rules)
        )
    }
    
    private func retrieveEpisodes(embedding: [Float], limit: Int) async -> [EpisodicMemory] {
        let sql = "SELECT * FROM episodic ORDER BY importance DESC LIMIT 100"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        
        var results: [(memory: EpisodicMemory, score: Double)] = []
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            // Get embedding
            let blobPtr = sqlite3_column_blob(stmt, 9)
            let blobSize = sqlite3_column_bytes(stmt, 9)
            
            guard let ptr = blobPtr else { continue }
            let memoryEmbedding = Array(UnsafeBufferPointer(
                start: ptr.assumingMemoryBound(to: Float.self),
                count: Int(blobSize) / MemoryLayout<Float>.size
            ))
            
            let similarity = cosineSimilarity(embedding, memoryEmbedding)
            
            if similarity > 0.5 {  // Threshold
                let memory = EpisodicMemory(
                    id: UUID(uuidString: String(cString: sqlite3_column_text(stmt, 0)))!,
                    timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                    summary: String(cString: sqlite3_column_text(stmt, 2)),
                    participants: (try? JSONDecoder().decode([String].self, from: Data(String(cString: sqlite3_column_text(stmt, 3)).utf8))) ?? [],
                    topics: (try? JSONDecoder().decode([String].self, from: Data(String(cString: sqlite3_column_text(stmt, 4)).utf8))) ?? [],
                    emotionalValence: Float(sqlite3_column_double(stmt, 5)),
                    importance: Float(sqlite3_column_double(stmt, 6)),
                    accessCount: Int(sqlite3_column_int(stmt, 7)),
                    lastAccessed: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8)),
                    embedding: memoryEmbedding
                )
                results.append((memory, similarity))
            }
        }
        
        sqlite3_finalize(stmt)
        
        // Update access counts
        for result in results.prefix(limit) {
            await updateAccessCount(episodeId: result.memory.id)
        }
        
        return results
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0.memory }
    }
    
    private func retrieveFacts(embedding: [Float], limit: Int) async -> [SemanticMemory] {
        let sql = "SELECT * FROM semantic ORDER BY confidence DESC LIMIT 50"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        
        var results: [(memory: SemanticMemory, score: Double)] = []
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let blobPtr = sqlite3_column_blob(stmt, 8)
            let blobSize = sqlite3_column_bytes(stmt, 8)
            
            guard let ptr = blobPtr else { continue }
            let memoryEmbedding = Array(UnsafeBufferPointer(
                start: ptr.assumingMemoryBound(to: Float.self),
                count: Int(blobSize) / MemoryLayout<Float>.size
            ))
            
            let similarity = cosineSimilarity(embedding, memoryEmbedding)
            
            if similarity > 0.6 {
                let memory = SemanticMemory(
                    id: UUID(uuidString: String(cString: sqlite3_column_text(stmt, 0)))!,
                    fact: String(cString: sqlite3_column_text(stmt, 1)),
                    category: String(cString: sqlite3_column_text(stmt, 2)),
                    confidence: Float(sqlite3_column_double(stmt, 3)),
                    sources: [],
                    contradictions: Int(sqlite3_column_int(stmt, 5)),
                    confirmations: Int(sqlite3_column_int(stmt, 6)),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7)),
                    lastConfirmed: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7)),
                    embedding: memoryEmbedding
                )
                results.append((memory, similarity))
            }
        }
        
        sqlite3_finalize(stmt)
        
        return results
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0.memory }
    }
    
    private func retrieveRules(for query: String) async -> [ProceduralMemory] {
        // Simple keyword matching for rules
        let sql = "SELECT * FROM procedural WHERE success_count > failure_count"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        
        var rules: [ProceduralMemory] = []
        let queryLower = query.lowercased()
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let trigger = String(cString: sqlite3_column_text(stmt, 1))
            
            // Check if query might trigger this rule
            let triggerWords = trigger.lowercased().components(separatedBy: .whitespaces)
            let matches = triggerWords.filter { queryLower.contains($0) }.count
            
            if matches >= 2 {  // At least 2 matching words
                rules.append(ProceduralMemory(
                    id: UUID(uuidString: String(cString: sqlite3_column_text(stmt, 0)))!,
                    trigger: trigger,
                    action: String(cString: sqlite3_column_text(stmt, 2)),
                    examples: [],
                    successCount: Int(sqlite3_column_int(stmt, 4)),
                    failureCount: Int(sqlite3_column_int(stmt, 5)),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6)),
                    lastUsed: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))
                ))
            }
        }
        
        sqlite3_finalize(stmt)
        return rules
    }
    
    // MARK: - Memory Consolidation
    
    /// Compress old memories, extract patterns
    func consolidateMemories() async {
        // 1. Identify old, low-importance episodic memories
        let cutoffDate = Date().addingTimeInterval(-7 * 24 * 3600)  // 1 week old
        
        let sql = """
        SELECT id, summary, topics FROM episodic 
        WHERE timestamp < ? AND importance < 0.5 AND access_count < 3
        ORDER BY timestamp ASC
        LIMIT 50
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_double(stmt, 1, cutoffDate.timeIntervalSince1970)
        
        var toConsolidate: [(id: String, summary: String, topics: [String])] = []
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let summary = String(cString: sqlite3_column_text(stmt, 1))
            let topics = (try? JSONDecoder().decode([String].self, from: Data(String(cString: sqlite3_column_text(stmt, 2)).utf8))) ?? []
            toConsolidate.append((id, summary, topics))
        }
        sqlite3_finalize(stmt)
        
        guard !toConsolidate.isEmpty else { return }
        
        // 2. Group by topic and create consolidated memories
        var topicGroups: [String: [(id: String, summary: String)]] = [:]
        for item in toConsolidate {
            for topic in item.topics {
                topicGroups[topic, default: []].append((item.id, item.summary))
            }
        }
        
        // 3. Create consolidated semantic memories from groups
        for (topic, items) in topicGroups where items.count >= 3 {
            let combinedSummary = items.map { $0.summary }.joined(separator: " | ")
            let consolidatedFact = await summarize("Consolidate these related memories about \(topic): \(combinedSummary)")
            
            await storeFact(
                ExtractedFact(category: "consolidated", fact: consolidatedFact, confidence: 0.7),
                source: UUID()
            )
        }
        
        // 4. Delete consolidated episodic memories
        for item in toConsolidate {
            let deleteSql = "DELETE FROM episodic WHERE id = ?"
            var deleteStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, deleteSql, -1, &deleteStmt, nil) == SQLITE_OK else { continue }
            sqlite3_bind_text(deleteStmt, 1, item.id, -1, nil)
            sqlite3_step(deleteStmt)
            sqlite3_finalize(deleteStmt)
        }
        
        loadCounts()
    }
    
    /// Apply forgetting curve to unaccessed memories
    func applyForgetting() async {
        let sql = """
        UPDATE episodic 
        SET importance = importance * ?
        WHERE last_accessed < ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        
        sqlite3_bind_double(stmt, 1, Double(importanceDecay))
        sqlite3_bind_double(stmt, 2, Date().addingTimeInterval(-24 * 3600).timeIntervalSince1970)
        
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        
        // Delete very low importance memories
        let deleteSql = "DELETE FROM episodic WHERE importance < 0.1"
        sqlite3_exec(db, deleteSql, nil, nil, nil)
        
        loadCounts()
    }
    
    // MARK: - Helpers
    
    private func buildContextString(
        episodes: [EpisodicMemory],
        facts: [SemanticMemory],
        rules: [ProceduralMemory]
    ) -> String {
        var context = ""
        
        if !facts.isEmpty {
            context += "## Known Facts\n"
            for fact in facts {
                context += "- \(fact.fact) (confidence: \(Int(fact.confidence * 100))%)\n"
            }
            context += "\n"
        }
        
        if !rules.isEmpty {
            context += "## Active Rules\n"
            for rule in rules {
                context += "- IF \(rule.trigger) THEN \(rule.action)\n"
            }
            context += "\n"
        }
        
        if !episodes.isEmpty {
            context += "## Recent Relevant Conversations\n"
            for episode in episodes.prefix(5) {
                let date = DateFormatter.localizedString(from: episode.timestamp, dateStyle: .short, timeStyle: .short)
                context += "- [\(date)] \(episode.summary)\n"
            }
        }
        
        return context
    }
    
    private func summarize(_ text: String) async -> String {
        let prompt = "Summarize this in 1-2 sentences, keeping key facts: \(text.prefix(2000))"
        return await callModel(prompt)
    }
    
    private func extractTopics(from text: String) async -> [String] {
        let prompt = "Extract 2-4 main topics from this text as a comma-separated list: \(text.prefix(1000))"
        let response = await callModel(prompt)
        return response.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    
    private func analyzeEmotion(_ text: String) -> Float {
        // Simple sentiment using NaturalLanguage
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        
        var totalScore: Double = 0
        var count = 0
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .sentence, scheme: .sentimentScore) { tag, _ in
            if let tag = tag, let score = Double(tag.rawValue) {
                totalScore += score
                count += 1
            }
            return true
        }
        
        return count > 0 ? Float(totalScore / Double(count)) : 0
    }
    
    private func calculateImportance(messages: [(role: String, content: String)], topics: [String]) -> Float {
        var importance: Float = 0.5  // Base
        
        // More messages = more important
        importance += min(Float(messages.count) * 0.05, 0.2)
        
        // Certain topics are more important
        let importantTopics = ["decision", "money", "deadline", "priority", "urgent", "important"]
        let matchingTopics = topics.filter { topic in
            importantTopics.contains { topic.lowercased().contains($0) }
        }
        importance += Float(matchingTopics.count) * 0.1
        
        // Questions from user are important
        let questionCount = messages.filter { $0.content.contains("?") }.count
        importance += min(Float(questionCount) * 0.05, 0.15)
        
        return min(importance, 1.0)
    }
    
    private func generateEmbedding(_ text: String) async -> [Float] {
        var embedding = [Float](repeating: 0, count: embeddingDim)
        
        if let nlEmbedding = NLEmbedding.wordEmbedding(for: .english) {
            let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines).prefix(100)
            var count = 0
            
            for word in words {
                if let vector = nlEmbedding.vector(for: word) {
                    for i in 0..<min(vector.count, embeddingDim) {
                        embedding[i] += Float(vector[i])
                    }
                    count += 1
                }
            }
            
            if count > 0 {
                for i in 0..<embeddingDim {
                    embedding[i] /= Float(count)
                }
            }
        }
        
        // Normalize
        var norm: Float = 0
        vDSP_svesq(embedding, 1, &norm, vDSP_Length(embeddingDim))
        norm = sqrt(norm)
        if norm > 0 {
            var scale = 1.0 / norm
            vDSP_vsmul(embedding, 1, &scale, &embedding, 1, vDSP_Length(embeddingDim))
        }
        
        return embedding
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count else { return 0 }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        return Double(dot)
    }
    
    private func findSimilarFact(embedding: [Float], threshold: Double) async -> UUID? {
        let sql = "SELECT id, embedding FROM semantic"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let blobPtr = sqlite3_column_blob(stmt, 1)
            let blobSize = sqlite3_column_bytes(stmt, 1)
            
            guard let ptr = blobPtr else { continue }
            let existing = Array(UnsafeBufferPointer(
                start: ptr.assumingMemoryBound(to: Float.self),
                count: Int(blobSize) / MemoryLayout<Float>.size
            ))
            
            if cosineSimilarity(embedding, existing) > threshold {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                sqlite3_finalize(stmt)
                return UUID(uuidString: id)
            }
        }
        
        sqlite3_finalize(stmt)
        return nil
    }
    
    private func findSimilarRule(trigger: String) async -> UUID? {
        let sql = "SELECT id, trigger FROM procedural"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        
        let triggerWords = Set(trigger.lowercased().components(separatedBy: .whitespaces))
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let existing = String(cString: sqlite3_column_text(stmt, 1))
            let existingWords = Set(existing.lowercased().components(separatedBy: .whitespaces))
            
            let overlap = triggerWords.intersection(existingWords)
            if overlap.count >= 3 {  // Similar enough
                let id = String(cString: sqlite3_column_text(stmt, 0))
                sqlite3_finalize(stmt)
                return UUID(uuidString: id)
            }
        }
        
        sqlite3_finalize(stmt)
        return nil
    }
    
    private func updateAccessCount(episodeId: UUID) async {
        let sql = "UPDATE episodic SET access_count = access_count + 1, last_accessed = ? WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
        sqlite3_bind_text(stmt, 2, episodeId.uuidString, -1, nil)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }
    
    private func estimateTokens(_ text: String) -> Int {
        return text.count / 4  // Rough estimate
    }
    
    private func callModel(_ prompt: String) async -> String {
        return await UnifiedInferenceEngine.shared.generate(prompt: prompt, maxTokens: 256)
    }
    
    struct ExtractedFact {
        let category: String
        let fact: String
        let confidence: Float
    }
    
    struct ExtractedRule {
        let trigger: String
        let action: String
    }
    
    struct RetrievedContext {
        let episodes: [EpisodicMemory]
        let facts: [SemanticMemory]
        let rules: [ProceduralMemory]
        let contextString: String
    }
}

// MARK: - Integration with ZeroDarkEngine

extension ZeroDarkEngine {
    /// Generate with infinite memory context
    func generateWithMemory(prompt: String, mode: InferenceMode? = nil) async -> ZeroDarkResult {
        let memory = InfiniteMemorySystem.shared
        
        // 1. Retrieve relevant context from memory
        let context = await memory.retrieveContext(for: prompt)
        
        // 2. Build augmented prompt
        let augmentedPrompt: String
        if !context.contextString.isEmpty {
            augmentedPrompt = """
            # Memory Context
            \(context.contextString)
            
            # Current Query
            \(prompt)
            """
        } else {
            augmentedPrompt = prompt
        }
        
        // 3. Generate with context
        var result = await generate(prompt: augmentedPrompt, mode: mode)
        
        // 4. Store this interaction as a new memory
        Task {
            await memory.processConversation(messages: [
                (role: "user", content: prompt),
                (role: "assistant", content: result.response)
            ])
        }
        
        return result
    }
}

// MARK: - Memory Dashboard View

struct MemoryDashboardView: View {
    @StateObject private var memory = InfiniteMemorySystem.shared
    
    var body: some View {
        List {
            Section("Memory Stats") {
                StatRow(label: "Episodic", value: "\(memory.episodicCount)")
                StatRow(label: "Semantic", value: "\(memory.semanticCount)")
                StatRow(label: "Procedural", value: "\(memory.proceduralCount)")
            }
            
            Section("Efficiency") {
                StatRow(label: "Tokens Saved", value: "\(memory.totalTokensSaved)")
                StatRow(label: "Compression", value: "\(memory.compressionRatio, specifier: "%.1f")x")
            }
            
            Section("Actions") {
                Button("Consolidate Memories") {
                    Task { await memory.consolidateMemories() }
                }
                Button("Apply Forgetting") {
                    Task { await memory.applyForgetting() }
                }
            }
        }
        .navigationTitle("Infinite Memory")
    }
}

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.cyan)
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    NavigationStack {
        MemoryDashboardView()
    }
}
