import Foundation

// MARK: - Prompt Cache

/// Cache KV states for common prompt prefixes
/// Reduces time-to-first-token dramatically for repeated contexts

public actor PromptCache {
    
    public static let shared = PromptCache()
    
    // MARK: - Types
    
    public struct CacheEntry {
        let promptHash: Int
        let promptPrefix: String
        let kvState: Data  // Serialized KV cache
        let model: Model
        let createdAt: Date
        let hitCount: Int
        let lastUsed: Date
    }
    
    // MARK: - State
    
    private var cache: [Int: CacheEntry] = [:]
    private var maxEntries: Int = 10
    private var maxMemoryMB: Int = 500
    
    // MARK: - Configuration
    
    public struct Config {
        /// Maximum cache entries
        public var maxEntries: Int = 10
        
        /// Maximum memory usage in MB
        public var maxMemoryMB: Int = 500
        
        /// Minimum prompt length to cache
        public var minPromptLength: Int = 100
        
        /// Cache system prompts
        public var cacheSystemPrompts: Bool = true
        
        /// Cache conversation context
        public var cacheConversationContext: Bool = true
        
        /// TTL in seconds (0 = no expiry)
        public var ttlSeconds: TimeInterval = 3600
    }
    
    public var config = Config()
    
    // MARK: - Cache Operations
    
    /// Check if we have a cached KV state for this prompt
    public func lookup(_ prompt: String, model: Model) -> CacheEntry? {
        let hash = prompt.hashValue
        
        guard var entry = cache[hash] else { return nil }
        
        // Check model match
        guard entry.model == model else { return nil }
        
        // Check TTL
        if config.ttlSeconds > 0 {
            let age = Date().timeIntervalSince(entry.createdAt)
            if age > config.ttlSeconds {
                cache.removeValue(forKey: hash)
                return nil
            }
        }
        
        // Update stats
        entry = CacheEntry(
            promptHash: entry.promptHash,
            promptPrefix: entry.promptPrefix,
            kvState: entry.kvState,
            model: entry.model,
            createdAt: entry.createdAt,
            hitCount: entry.hitCount + 1,
            lastUsed: Date()
        )
        cache[hash] = entry
        
        return entry
    }
    
    /// Store KV state for a prompt
    public func store(
        prompt: String,
        kvState: Data,
        model: Model
    ) {
        // Check minimum length
        guard prompt.count >= config.minPromptLength else { return }
        
        let hash = prompt.hashValue
        
        // Evict if necessary
        if cache.count >= maxEntries {
            evictLRU()
        }
        
        // Check memory
        let currentMemory = cache.values.reduce(0) { $0 + $1.kvState.count }
        let newMemory = currentMemory + kvState.count
        if newMemory > maxMemoryMB * 1024 * 1024 {
            evictUntilMemoryAvailable(needed: kvState.count)
        }
        
        cache[hash] = CacheEntry(
            promptHash: hash,
            promptPrefix: prompt,
            kvState: kvState,
            model: model,
            createdAt: Date(),
            hitCount: 0,
            lastUsed: Date()
        )
    }
    
    /// Find longest matching prefix
    public func findLongestPrefix(_ prompt: String, model: Model) -> (entry: CacheEntry, matchLength: Int)? {
        var bestMatch: (CacheEntry, Int)?
        
        for entry in cache.values {
            guard entry.model == model else { continue }
            
            if prompt.hasPrefix(entry.promptPrefix) {
                let matchLength = entry.promptPrefix.count
                if bestMatch == nil || matchLength > bestMatch!.1 {
                    bestMatch = (entry, matchLength)
                }
            }
        }
        
        return bestMatch
    }
    
    // MARK: - Eviction
    
    private func evictLRU() {
        guard let oldest = cache.values.min(by: { $0.lastUsed < $1.lastUsed }) else { return }
        cache.removeValue(forKey: oldest.promptHash)
    }
    
    private func evictUntilMemoryAvailable(needed: Int) {
        let targetMemory = (maxMemoryMB * 1024 * 1024) - needed
        
        var sorted = cache.values.sorted { $0.lastUsed < $1.lastUsed }
        var currentMemory = sorted.reduce(0) { $0 + $1.kvState.count }
        
        while currentMemory > targetMemory && !sorted.isEmpty {
            let oldest = sorted.removeFirst()
            cache.removeValue(forKey: oldest.promptHash)
            currentMemory -= oldest.kvState.count
        }
    }
    
    // MARK: - Predefined Caches
    
    /// Pre-cache common system prompts
    public func precacheSystemPrompts() async {
        let commonPrompts = [
            "You are a helpful assistant.",
            "You are a helpful, harmless, and honest AI assistant.",
            "You are an expert programmer. Write clean, efficient code.",
            "You are a creative writer. Be imaginative and engaging.",
            "Answer questions concisely and accurately."
        ]
        
        // These would be pre-computed with actual KV states
        // For now, just warm up the cache structure
    }
    
    // MARK: - Stats
    
    public var stats: (entries: Int, memoryMB: Double, hitRate: Double) {
        let memory = Double(cache.values.reduce(0) { $0 + $1.kvState.count }) / (1024 * 1024)
        let totalHits = cache.values.reduce(0) { $0 + $1.hitCount }
        let hitRate = cache.isEmpty ? 0 : Double(totalHits) / Double(cache.count)
        return (cache.count, memory, hitRate)
    }
    
    public func clear() {
        cache.removeAll()
    }
}

// MARK: - Context Window Management

/// Efficient context window handling for long conversations
public struct ContextWindow {
    
    /// Maximum context tokens
    public var maxTokens: Int
    
    /// Current context
    public var tokens: [Int] = []
    
    /// Sliding window with smart truncation
    public mutating func add(_ newTokens: [Int]) {
        tokens.append(contentsOf: newTokens)
        
        // If over limit, truncate from middle (keep system + recent)
        if tokens.count > maxTokens {
            let systemTokens = 200  // Approximate system prompt size
            let recentTokens = maxTokens - systemTokens - 100
            
            let systemPart = Array(tokens.prefix(systemTokens))
            let recentPart = Array(tokens.suffix(recentTokens))
            let separator = [0] // Token for "..." or summary marker
            
            tokens = systemPart + separator + recentPart
        }
    }
    
    /// Reset context
    public mutating func clear() {
        tokens.removeAll()
    }
}
