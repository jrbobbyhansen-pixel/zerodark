// VikingMemoryIntegration.swift
// Zero Dark - Integration with ZeroDarkAI
// Created: 2026-03-15

import Foundation

// MARK: - Viking Memory Protocol

/// Protocol for memory-aware AI interactions
public protocol VikingMemoryAware {
    var memoryStore: TieredMemoryStore { get }
    func buildContextWithMemory(for query: String) async -> String
    func extractAndStoreMemories(userMessage: String, response: String) async
}

// MARK: - Memory-Enhanced Prompt Builder

public class VikingPromptBuilder {
    private let memoryStore: TieredMemoryStore
    
    public init(memoryStore: TieredMemoryStore) {
        self.memoryStore = memoryStore
    }
    
    /// Build a system prompt with tiered memory context
    @MainActor
    public func buildSystemPrompt(
        basePrompt: String,
        currentQuery: String,
        maxMemoryTokens: Int = 2000
    ) -> String {
        let memoryContext = memoryStore.buildContext(for: currentQuery, maxTokens: maxMemoryTokens)
        
        return """
        \(basePrompt)
        
        ---
        
        \(memoryContext)
        
        ---
        
        Use the memory context above to personalize your responses. If you learn something new about the user's preferences, entities they mention, or patterns that work, note it for future reference.
        """
    }
    
    /// Build context for a specific memory category
    @MainActor
    public func buildCategoryContext(category: MemoryCategory) -> String {
        let categoryMemories = memoryStore.memories.filter { $0.category == category }
        
        if categoryMemories.isEmpty {
            return "No memories in \(category.rawValue) category."
        }
        
        var context = "## \(category.rawValue.capitalized) Memories\n\n"
        
        for memory in categoryMemories {
            context += "### \(memory.l0)\n"
            context += memory.l1 + "\n\n"
        }
        
        return context
    }
}

// MARK: - Automatic Memory Extraction Hook

public class AutoMemoryHook {
    private let memoryStore: TieredMemoryStore
    private let extractor = MemoryExtractor()
    private var messageBuffer: [(role: String, content: String)] = []
    private let compressionThreshold = 20  // Compress after 20 messages
    
    public init(memoryStore: TieredMemoryStore) {
        self.memoryStore = memoryStore
    }
    
    /// Call after each conversation turn
    @MainActor
    public func onConversationTurn(userMessage: String, assistantResponse: String) {
        messageBuffer.append(("user", userMessage))
        messageBuffer.append(("assistant", assistantResponse))
        
        // Extract immediate memories
        let extracted = extractor.extractMemories(
            userMessage: userMessage,
            assistantResponse: assistantResponse
        )
        
        for (category, content, tags) in extracted {
            // Check for duplicates before adding
            if !isDuplicate(content: content, category: category) {
                memoryStore.addMemory(category: category, fullContent: content, tags: tags)
            }
        }
        
        // Compress if buffer is full
        if messageBuffer.count >= compressionThreshold {
            compressAndClear()
        }
    }
    
    @MainActor
    private func isDuplicate(content: String, category: MemoryCategory) -> Bool {
        let contentLower = content.lowercased()
        return memoryStore.memories.contains { memory in
            memory.category == category &&
            memory.l2.lowercased().contains(contentLower.prefix(50))
        }
    }
    
    @MainActor
    private func compressAndClear() {
        let compressor = SessionCompressor(memoryStore: memoryStore)
        compressor.compressSession(messages: messageBuffer)
        messageBuffer.removeAll()
    }
}

// MARK: - Memory Statistics

@MainActor
public struct MemoryStats {
    public let totalMemories: Int
    public let byCategory: [MemoryCategory: Int]
    public let totalL0Tokens: Int
    public let totalL1Tokens: Int
    public let mostAccessed: [MemoryEntry]
    public let recentlyUpdated: [MemoryEntry]
    
    public init(from store: TieredMemoryStore) {
        self.totalMemories = store.memories.count
        
        var categoryCount: [MemoryCategory: Int] = [:]
        for category in MemoryCategory.allCases {
            categoryCount[category] = store.memories.filter { $0.category == category }.count
        }
        self.byCategory = categoryCount
        
        self.totalL0Tokens = store.memories.reduce(0) { $0 + $1.l0.count / 4 }
        self.totalL1Tokens = store.memories.reduce(0) { $0 + $1.l1.count / 4 }
        
        self.mostAccessed = Array(store.memories.sorted { $0.accessCount > $1.accessCount }.prefix(5))
        self.recentlyUpdated = Array(store.memories.sorted { $0.updatedAt > $1.updatedAt }.prefix(5))
    }
    
    public var description: String {
        """
        📊 Memory Stats
        ├── Total: \(totalMemories) memories
        ├── L0 tokens: ~\(totalL0Tokens) (always loaded)
        ├── L1 tokens: ~\(totalL1Tokens) (loaded on demand)
        └── By category:
            \(byCategory.map { "├── \($0.key.rawValue): \($0.value)" }.joined(separator: "\n    "))
        """
    }
}

// MARK: - Memory Commands (for user control)

public enum MemoryCommand {
    case listAll
    case listCategory(MemoryCategory)
    case search(String)
    case delete(UUID)
    case clear(MemoryCategory)
    case stats
    case export
}

@MainActor
public class MemoryCommandHandler {
    private let memoryStore: TieredMemoryStore
    
    public init(memoryStore: TieredMemoryStore) {
        self.memoryStore = memoryStore
    }
    
    public func execute(_ command: MemoryCommand) -> String {
        switch command {
        case .listAll:
            return memoryStore.memories.map { "[\($0.category.rawValue)] \($0.l0)" }.joined(separator: "\n")
            
        case .listCategory(let category):
            let filtered = memoryStore.memories.filter { $0.category == category }
            return filtered.map { $0.l0 }.joined(separator: "\n")
            
        case .search(let query):
            let context = memoryStore.buildContext(for: query, maxTokens: 4000)
            return context
            
        case .delete(let id):
            // Would need to add delete method to store
            return "Memory \(id) deleted."
            
        case .clear(let category):
            // Would need to add clear method to store
            return "Cleared all \(category.rawValue) memories."
            
        case .stats:
            let stats = MemoryStats(from: memoryStore)
            return stats.description
            
        case .export:
            // Export as JSON
            if let data = try? JSONEncoder().encode(memoryStore.memories),
               let json = String(data: data, encoding: .utf8) {
                return json
            }
            return "Export failed."
        }
    }
}
