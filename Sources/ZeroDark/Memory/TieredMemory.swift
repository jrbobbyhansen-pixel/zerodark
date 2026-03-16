// TieredMemory.swift
// Zero Dark - OpenViking-Inspired Tiered Memory System
// Created: 2026-03-15

import Foundation

// MARK: - Memory Tiers (L0/L1/L2)

/// L0: Ultra-compact summary (~100 tokens) - Always loaded
/// L1: Structured overview (~500 tokens) - Loaded on demand
/// L2: Full content - Loaded only when drilling down
public enum MemoryTier: String, Codable {
    case l0 = "summary"      // ~100 tokens, always in context
    case l1 = "overview"     // ~500 tokens, loaded when relevant
    case l2 = "full"         // Full content, loaded on explicit request
}

// MARK: - Memory Categories

public enum MemoryCategory: String, Codable, CaseIterable {
    // User scope
    case preferences    // Communication style, habits, likes/dislikes
    case entities       // People, projects, concepts the user mentions
    case events         // Decisions, milestones, important moments
    
    // Agent scope
    case cases          // Specific problem → solution records
    case patterns       // Reusable strategies that worked
    case skills         // Learned capabilities
}

// MARK: - Memory Entry

public struct MemoryEntry: Codable, Identifiable {
    public let id: UUID
    public let category: MemoryCategory
    public let createdAt: Date
    public var updatedAt: Date
    
    // Tiered content
    public var l0: String    // ~100 tokens - "User prefers concise responses"
    public var l1: String    // ~500 tokens - More detail + examples
    public var l2: String    // Full content - Complete history
    
    // Metadata
    public var accessCount: Int
    public var lastAccessed: Date
    public var tags: [String]
    
    public init(
        category: MemoryCategory,
        l0: String,
        l1: String,
        l2: String,
        tags: [String] = []
    ) {
        self.id = UUID()
        self.category = category
        self.createdAt = Date()
        self.updatedAt = Date()
        self.l0 = l0
        self.l1 = l1
        self.l2 = l2
        self.accessCount = 0
        self.lastAccessed = Date()
        self.tags = tags
    }
}

// MARK: - Memory Store

@MainActor
public class TieredMemoryStore: ObservableObject {
    @Published public private(set) var memories: [MemoryEntry] = []
    
    private let storageURL: URL
    private let maxL0TokensInContext = 2000  // Max tokens from L0 summaries
    private let maxL1TokensInContext = 4000  // Max tokens when including L1
    
    public init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.storageURL = documents.appendingPathComponent("zerodark_memory.json")
        loadFromDisk()
    }
    
    // MARK: - Context Building (The Key Innovation)
    
    /// Build context string using tiered loading
    /// - Parameter query: Optional query to determine relevance
    /// - Parameter maxTokens: Maximum tokens to include
    /// - Returns: Context string with tiered memory
    public func buildContext(for query: String? = nil, maxTokens: Int = 2000) -> String {
        var context = "## Memory Context\n\n"
        var tokenCount = 0
        
        // Always include all L0 summaries (they're tiny)
        let l0Section = buildL0Section()
        context += l0Section
        tokenCount += estimateTokens(l0Section)
        
        // If we have a query, find relevant memories and include their L1
        if let query = query, tokenCount < maxTokens {
            let relevant = findRelevantMemories(for: query, limit: 5)
            for memory in relevant {
                if tokenCount + estimateTokens(memory.l1) < maxTokens {
                    context += "\n### \(memory.category.rawValue.capitalized): \(memory.l0)\n"
                    context += memory.l1 + "\n"
                    tokenCount += estimateTokens(memory.l1)
                    
                    // Mark as accessed
                    markAccessed(memory.id)
                }
            }
        }
        
        return context
    }
    
    /// Build minimal L0-only context (for quick responses)
    private func buildL0Section() -> String {
        var section = "### Quick Memory (L0)\n"
        
        for category in MemoryCategory.allCases {
            let categoryMemories = memories.filter { $0.category == category }
            if !categoryMemories.isEmpty {
                section += "**\(category.rawValue.capitalized):** "
                section += categoryMemories.map { $0.l0 }.joined(separator: "; ")
                section += "\n"
            }
        }
        
        return section
    }
    
    /// Find memories relevant to a query (simple keyword matching for now)
    private func findRelevantMemories(for query: String, limit: Int) -> [MemoryEntry] {
        let queryWords = query.lowercased().split(separator: " ").map(String.init)
        
        return memories
            .map { memory -> (MemoryEntry, Int) in
                let content = "\(memory.l0) \(memory.l1) \(memory.tags.joined(separator: " "))".lowercased()
                let score = queryWords.reduce(0) { $0 + (content.contains($1) ? 1 : 0) }
                return (memory, score)
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }
    
    /// Get full L2 content for a specific memory (explicit drill-down)
    public func getFullContent(for memoryId: UUID) -> String? {
        guard let memory = memories.first(where: { $0.id == memoryId }) else {
            return nil
        }
        markAccessed(memoryId)
        return memory.l2
    }
    
    // MARK: - Memory Management
    
    /// Add a new memory with automatic tier generation
    public func addMemory(
        category: MemoryCategory,
        fullContent: String,
        tags: [String] = []
    ) {
        // Generate tiered summaries (in production, use LLM)
        let l0 = generateL0(from: fullContent)
        let l1 = generateL1(from: fullContent)
        
        let entry = MemoryEntry(
            category: category,
            l0: l0,
            l1: l1,
            l2: fullContent,
            tags: tags
        )
        
        memories.append(entry)
        saveToDisk()
    }
    
    /// Update existing memory (merges new info)
    public func updateMemory(id: UUID, newContent: String) {
        guard let index = memories.firstIndex(where: { $0.id == id }) else { return }
        
        // Append to L2, regenerate L0/L1
        memories[index].l2 += "\n\n---\n\n" + newContent
        memories[index].l0 = generateL0(from: memories[index].l2)
        memories[index].l1 = generateL1(from: memories[index].l2)
        memories[index].updatedAt = Date()
        
        saveToDisk()
    }
    
    private func markAccessed(_ id: UUID) {
        guard let index = memories.firstIndex(where: { $0.id == id }) else { return }
        memories[index].accessCount += 1
        memories[index].lastAccessed = Date()
    }
    
    // MARK: - Tier Generation (Simple for now, LLM in production)
    
    private func generateL0(from content: String) -> String {
        // Simple: first sentence or first 100 chars
        let sentences = content.components(separatedBy: ". ")
        if let first = sentences.first, first.count <= 150 {
            return first + "."
        }
        return String(content.prefix(100)) + "..."
    }
    
    private func generateL1(from content: String) -> String {
        // Simple: first 500 chars or first few sentences
        if content.count <= 500 {
            return content
        }
        return String(content.prefix(500)) + "..."
    }
    
    private func estimateTokens(_ text: String) -> Int {
        // Rough estimate: 1 token ≈ 4 characters
        return text.count / 4
    }
    
    // MARK: - Persistence
    
    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(memories)
            try data.write(to: storageURL)
        } catch {
            print("Failed to save memories: \(error)")
        }
    }
    
    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            memories = try JSONDecoder().decode([MemoryEntry].self, from: data)
        } catch {
            print("Failed to load memories: \(error)")
        }
    }
}

// MARK: - Memory Extractor (Extract memories from conversations)

public class MemoryExtractor {
    
    /// Extract potential memories from a conversation turn
    /// In production, this would use the LLM to categorize
    public func extractMemories(
        userMessage: String,
        assistantResponse: String
    ) -> [(category: MemoryCategory, content: String, tags: [String])] {
        var extracted: [(MemoryCategory, String, [String])] = []
        
        // Simple keyword-based extraction (LLM in production)
        let combined = "\(userMessage) \(assistantResponse)".lowercased()
        
        // Detect preferences
        if combined.contains("i prefer") || combined.contains("i like") || combined.contains("i want") {
            extracted.append((.preferences, userMessage, ["user-preference"]))
        }
        
        // Detect entities (names, projects)
        let entityPatterns = ["project", "app", "company", "person", "team"]
        for pattern in entityPatterns {
            if combined.contains(pattern) {
                extracted.append((.entities, userMessage, [pattern]))
                break
            }
        }
        
        // Detect events/decisions
        if combined.contains("decided") || combined.contains("milestone") || combined.contains("completed") {
            extracted.append((.events, userMessage, ["decision"]))
        }
        
        // Detect patterns (successful solutions)
        if combined.contains("worked") || combined.contains("solution") || combined.contains("fixed") {
            extracted.append((.patterns, assistantResponse, ["solution"]))
        }
        
        return extracted
    }
}

// MARK: - Session Compressor (Compress old messages)

public class SessionCompressor {
    private let memoryStore: TieredMemoryStore
    private let extractor = MemoryExtractor()
    
    public init(memoryStore: TieredMemoryStore) {
        self.memoryStore = memoryStore
    }
    
    /// Compress a conversation session, extracting durable memories
    @MainActor
    public func compressSession(messages: [(role: String, content: String)]) {
        // Extract memories from conversation pairs
        for i in stride(from: 0, to: messages.count - 1, by: 2) {
            let userMsg = messages[i].content
            let assistantMsg = i + 1 < messages.count ? messages[i + 1].content : ""
            
            let extracted = extractor.extractMemories(
                userMessage: userMsg,
                assistantResponse: assistantMsg
            )
            
            for (category, content, tags) in extracted {
                memoryStore.addMemory(category: category, fullContent: content, tags: tags)
            }
        }
    }
}
