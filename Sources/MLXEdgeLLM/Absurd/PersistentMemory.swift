// PersistentMemory.swift
// Your AI remembers EVERYTHING — across sessions, forever
// ABSURD MODE

import Foundation
import CoreData

// MARK: - Persistent Memory System

public actor PersistentMemory {
    
    public static let shared = PersistentMemory()
    
    // MARK: - Memory Types
    
    public struct Memory: Codable, Identifiable, Sendable {
        public let id: UUID
        public let content: String
        public let type: MemoryType
        public let importance: Float  // 0.0 - 1.0
        public let embedding: [Float]?  // For semantic search
        public let createdAt: Date
        public var lastAccessedAt: Date
        public var accessCount: Int
        public let metadata: [String: String]
        
        public init(content: String, type: MemoryType, importance: Float = 0.5, metadata: [String: String] = [:]) {
            self.id = UUID()
            self.content = content
            self.type = type
            self.importance = importance
            self.embedding = nil
            self.createdAt = Date()
            self.lastAccessedAt = Date()
            self.accessCount = 0
            self.metadata = metadata
        }
    }
    
    public enum MemoryType: String, Codable, Sendable {
        case fact = "fact"                    // "User's name is Bobby"
        case preference = "preference"        // "Prefers morning meetings"
        case conversation = "conversation"    // Past conversation context
        case task = "task"                    // Things they asked to do
        case relationship = "relationship"   // People they mention
        case project = "project"              // Work they're doing
        case habit = "habit"                  // Patterns we've learned
        case instruction = "instruction"      // "Always greet me with..."
        case temporal = "temporal"            // Time-based memories
    }
    
    // MARK: - Storage
    
    private var memories: [Memory] = []
    private let storageKey = "zerodark_persistent_memory"
    private let maxMemories = 10000
    
    private init() {
        Task {
            await loadMemories()
        }
    }
    
    // MARK: - Core API
    
    /// Remember something new
    public func remember(_ content: String, type: MemoryType, importance: Float = 0.5, metadata: [String: String] = [:]) async {
        let memory = Memory(content: content, type: type, importance: importance, metadata: metadata)
        memories.append(memory)
        
        // Prune if too many
        if memories.count > maxMemories {
            await pruneMemories()
        }
        
        await saveMemories()
    }
    
    /// Recall memories matching a query
    public func recall(query: String, limit: Int = 10) async -> [Memory] {
        // Simple keyword matching (in production: use embeddings)
        let queryWords = Set(query.lowercased().components(separatedBy: .whitespaces))
        
        var scored: [(Memory, Int)] = []
        for memory in memories {
            let memoryWords = Set(memory.content.lowercased().components(separatedBy: .whitespaces))
            let overlap = queryWords.intersection(memoryWords).count
            if overlap > 0 {
                scored.append((memory, overlap))
            }
        }
        
        // Sort by relevance and importance
        scored.sort { ($0.1, $0.0.importance) > ($1.1, $1.0.importance) }
        
        // Update access timestamps
        let results = Array(scored.prefix(limit).map { $0.0 })
        for result in results {
            await touchMemory(id: result.id)
        }
        
        return results
    }
    
    /// Recall memories by type
    public func recall(type: MemoryType, limit: Int = 10) async -> [Memory] {
        return Array(memories.filter { $0.type == type }.prefix(limit))
    }
    
    /// Forget a specific memory
    public func forget(id: UUID) async {
        memories.removeAll { $0.id == id }
        await saveMemories()
    }
    
    /// Forget all memories of a type
    public func forgetAll(type: MemoryType) async {
        memories.removeAll { $0.type == type }
        await saveMemories()
    }
    
    /// Get all memories for export
    public func exportAll() async -> [Memory] {
        return memories
    }
    
    /// Clear all memories
    public func clearAll() async {
        memories = []
        await saveMemories()
    }
    
    // MARK: - Smart Features
    
    /// Extract and remember facts from a conversation
    public func learnFromConversation(_ userMessage: String, _ assistantResponse: String) async {
        // Pattern matching for facts
        let patterns: [(String, MemoryType)] = [
            ("my name is", .fact),
            ("i am", .fact),
            ("i prefer", .preference),
            ("i like", .preference),
            ("i don't like", .preference),
            ("i hate", .preference),
            ("remind me", .instruction),
            ("always", .instruction),
            ("never", .instruction),
            ("i work", .fact),
            ("my job", .fact),
            ("i live", .fact),
        ]
        
        let lower = userMessage.lowercased()
        for (pattern, type) in patterns {
            if lower.contains(pattern) {
                await remember(userMessage, type: type, importance: 0.7)
                break
            }
        }
    }
    
    /// Get context for a new conversation
    public func getContext(for topic: String? = nil) async -> String {
        var context = "USER MEMORY CONTEXT:\n"
        
        // Always include facts and preferences
        let facts = await recall(type: .fact, limit: 5)
        let prefs = await recall(type: .preference, limit: 5)
        let instructions = await recall(type: .instruction, limit: 3)
        
        for fact in facts {
            context += "- Fact: \(fact.content)\n"
        }
        for pref in prefs {
            context += "- Preference: \(pref.content)\n"
        }
        for inst in instructions {
            context += "- Instruction: \(inst.content)\n"
        }
        
        // If topic provided, include relevant memories
        if let topic = topic {
            let relevant = await recall(query: topic, limit: 5)
            for mem in relevant {
                context += "- Related: \(mem.content)\n"
            }
        }
        
        return context
    }
    
    // MARK: - Private Helpers
    
    private func touchMemory(id: UUID) async {
        if let index = memories.firstIndex(where: { $0.id == id }) {
            memories[index].lastAccessedAt = Date()
            memories[index].accessCount += 1
        }
    }
    
    private func pruneMemories() async {
        // Remove least important, least accessed memories
        memories.sort { mem1, mem2 in
            let score1 = mem1.importance * Float(mem1.accessCount + 1)
            let score2 = mem2.importance * Float(mem2.accessCount + 1)
            return score1 > score2
        }
        memories = Array(memories.prefix(maxMemories / 2))
    }
    
    private func saveMemories() async {
        if let data = try? JSONEncoder().encode(memories) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func loadMemories() async {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let loaded = try? JSONDecoder().decode([Memory].self, from: data) {
            memories = loaded
        }
    }
}

// MARK: - Memory Stats

extension PersistentMemory {
    
    public struct Stats: Sendable {
        public let totalMemories: Int
        public let byType: [MemoryType: Int]
        public let oldestMemory: Date?
        public let newestMemory: Date?
        public let mostAccessed: Memory?
    }
    
    public func getStats() async -> Stats {
        var byType: [MemoryType: Int] = [:]
        for memory in memories {
            byType[memory.type, default: 0] += 1
        }
        
        let sorted = memories.sorted { $0.accessCount > $1.accessCount }
        
        return Stats(
            totalMemories: memories.count,
            byType: byType,
            oldestMemory: memories.map { $0.createdAt }.min(),
            newestMemory: memories.map { $0.createdAt }.max(),
            mostAccessed: sorted.first
        )
    }
}
