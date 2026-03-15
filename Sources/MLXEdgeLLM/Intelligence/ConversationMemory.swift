import Foundation

// MARK: - Conversation Memory

/// Long-term memory that persists across sessions
public actor ConversationMemory {
    
    // MARK: - Types
    
    public struct Memory: Codable, Identifiable {
        public let id: UUID
        public let content: String
        public let type: MemoryType
        public let importance: Float
        public let createdAt: Date
        public var lastAccessedAt: Date
        public var accessCount: Int
        public let relatedTopics: [String]
        
        public enum MemoryType: String, Codable {
            case fact = "Fact"
            case preference = "Preference"
            case instruction = "Instruction"
            case context = "Context"
            case correction = "Correction"
        }
    }
    
    public struct UserProfile: Codable {
        public var name: String?
        public var preferences: [String: String]
        public var interests: [String]
        public var communicationStyle: CommunicationStyle
        public var expertise: [String: ExpertiseLevel]
        
        public enum CommunicationStyle: String, Codable {
            case concise
            case detailed
            case casual
            case formal
        }
        
        public enum ExpertiseLevel: String, Codable {
            case beginner
            case intermediate
            case expert
        }
        
        public init() {
            self.preferences = [:]
            self.interests = []
            self.communicationStyle = .detailed
            self.expertise = [:]
        }
    }
    
    // MARK: - State
    
    private var memories: [Memory] = []
    private var userProfile = UserProfile()
    private let maxMemories = 1000
    private let memoryFile: URL
    private let profileFile: URL
    
    // MARK: - Init
    
    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZeroDark", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        
        self.memoryFile = base.appendingPathComponent("memories.json")
        self.profileFile = base.appendingPathComponent("profile.json")
        
        Task { await loadFromDisk() }
    }
    
    // MARK: - Add Memory
    
    public func remember(
        _ content: String,
        type: Memory.MemoryType,
        importance: Float = 0.5,
        topics: [String] = []
    ) {
        let memory = Memory(
            id: UUID(),
            content: content,
            type: type,
            importance: importance,
            createdAt: Date(),
            lastAccessedAt: Date(),
            accessCount: 1,
            relatedTopics: topics
        )
        
        memories.append(memory)
        
        // Prune if over limit
        if memories.count > maxMemories {
            pruneMemories()
        }
        
        Task { await saveToDisk() }
    }
    
    // MARK: - Recall
    
    public func recall(
        query: String,
        limit: Int = 5,
        types: [Memory.MemoryType]? = nil
    ) -> [Memory] {
        let queryWords = Set(query.lowercased().split(separator: " ").map(String.init))
        
        var filtered = memories
        
        // Filter by type if specified
        if let types = types {
            filtered = filtered.filter { types.contains($0.type) }
        }
        
        // Score by relevance
        let scored: [(Memory, Float)] = filtered.map { memory in
            var score: Float = 0
            
            // Word overlap
            let memoryWords = Set(memory.content.lowercased().split(separator: " ").map(String.init))
            let overlap = Float(queryWords.intersection(memoryWords).count)
            score += overlap * 0.3
            
            // Topic match
            let queryTopics = Set(queryWords)
            let topicOverlap = Float(queryTopics.intersection(Set(memory.relatedTopics.map { $0.lowercased() })).count)
            score += topicOverlap * 0.4
            
            // Importance
            score += memory.importance * 0.2
            
            // Recency
            let daysSinceAccess = Date().timeIntervalSince(memory.lastAccessedAt) / 86400
            let recencyBoost = max(0, 1 - Float(daysSinceAccess) / 30)
            score += recencyBoost * 0.1
            
            // Frequency
            let frequencyBoost = min(Float(memory.accessCount) / 10, 1.0)
            score += frequencyBoost * 0.1
            
            return (memory, score)
        }
        
        // Sort by score and take top
        let results = scored
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
        
        // Update access stats
        for result in results {
            if let index = memories.firstIndex(where: { $0.id == result.id }) {
                memories[index].lastAccessedAt = Date()
                memories[index].accessCount += 1
            }
        }
        
        return Array(results)
    }
    
    // MARK: - Profile
    
    public func updateProfile(_ update: (inout UserProfile) -> Void) {
        update(&userProfile)
        Task { await saveToDisk() }
    }
    
    public func getProfile() -> UserProfile {
        userProfile
    }
    
    // MARK: - Context Building
    
    public func buildContext(for query: String, maxTokens: Int = 500) -> String {
        let relevantMemories = recall(query: query, limit: 10)
        
        var context = ""
        var tokenCount = 0
        
        // Add user profile summary
        if let name = userProfile.name {
            context += "User: \(name)\n"
            tokenCount += 5
        }
        
        if !userProfile.interests.isEmpty {
            context += "Interests: \(userProfile.interests.prefix(5).joined(separator: ", "))\n"
            tokenCount += 10
        }
        
        context += "Communication style: \(userProfile.communicationStyle.rawValue)\n"
        tokenCount += 5
        
        // Add relevant memories
        if !relevantMemories.isEmpty {
            context += "\nRelevant context:\n"
            tokenCount += 5
            
            for memory in relevantMemories {
                let memoryTokens = memory.content.count / 4
                if tokenCount + memoryTokens > maxTokens { break }
                
                context += "- [\(memory.type.rawValue)] \(memory.content)\n"
                tokenCount += memoryTokens + 2
            }
        }
        
        return context
    }
    
    // MARK: - Extract & Learn
    
    public func extractAndLearn(from conversation: String) {
        let lines = conversation.components(separatedBy: .newlines)
        
        for line in lines {
            let lower = line.lowercased()
            
            // Detect preferences
            if lower.contains("i prefer") || lower.contains("i like") || lower.contains("i want") {
                remember(line, type: .preference, importance: 0.7)
            }
            
            // Detect corrections
            if lower.contains("actually") || lower.contains("no, ") || lower.contains("that's wrong") {
                remember(line, type: .correction, importance: 0.8)
            }
            
            // Detect instructions
            if lower.contains("always ") || lower.contains("never ") || lower.contains("remember to") {
                remember(line, type: .instruction, importance: 0.9)
            }
            
            // Detect name
            if lower.contains("my name is") || lower.contains("i'm called") || lower.contains("call me") {
                let words = line.split(separator: " ")
                if let nameIndex = words.firstIndex(where: { $0.lowercased() == "is" || $0.lowercased() == "called" }) {
                    let nextIndex = words.index(after: nameIndex)
                    if nextIndex < words.endIndex {
                        let name = String(words[nextIndex]).trimmingCharacters(in: .punctuationCharacters)
                        updateProfile { $0.name = name }
                    }
                }
            }
        }
    }
    
    // MARK: - Pruning
    
    private func pruneMemories() {
        // Score memories for importance
        let scored: [(Int, Float)] = memories.enumerated().map { index, memory in
            var score: Float = memory.importance
            
            // Boost recent
            let daysSinceCreated = Date().timeIntervalSince(memory.createdAt) / 86400
            score += max(0, 1 - Float(daysSinceCreated) / 90)
            
            // Boost frequently accessed
            score += min(Float(memory.accessCount) / 20, 0.5)
            
            // Boost instructions and corrections
            if memory.type == .instruction || memory.type == .correction {
                score += 0.3
            }
            
            return (index, score)
        }
        
        // Keep top memories
        let keepCount = maxMemories - 100
        let keepIndices = Set(
            scored.sorted { $0.1 > $1.1 }
                .prefix(keepCount)
                .map { $0.0 }
        )
        
        memories = memories.enumerated()
            .filter { keepIndices.contains($0.offset) }
            .map { $0.element }
    }
    
    // MARK: - Persistence
    
    private func saveToDisk() async {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        if let memoryData = try? encoder.encode(memories) {
            try? memoryData.write(to: memoryFile)
        }
        
        if let profileData = try? encoder.encode(userProfile) {
            try? profileData.write(to: profileFile)
        }
    }
    
    private func loadFromDisk() async {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        if let memoryData = try? Data(contentsOf: memoryFile),
           let loaded = try? decoder.decode([Memory].self, from: memoryData) {
            memories = loaded
        }
        
        if let profileData = try? Data(contentsOf: profileFile),
           let loaded = try? decoder.decode(UserProfile.self, from: profileData) {
            userProfile = loaded
        }
    }
    
    // MARK: - Stats
    
    public var stats: (total: Int, byType: [Memory.MemoryType: Int]) {
        var byType: [Memory.MemoryType: Int] = [:]
        for memory in memories {
            byType[memory.type, default: 0] += 1
        }
        return (memories.count, byType)
    }
    
    public func clear() {
        memories.removeAll()
        userProfile = UserProfile()
        Task { await saveToDisk() }
    }
}
