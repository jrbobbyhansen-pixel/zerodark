import Foundation
import Accelerate

// MARK: - Embedding Engine

/// On-device vector embeddings for RAG
/// Semantic search, clustering, similarity — all local

public actor EmbeddingEngine {
    
    public static let shared = EmbeddingEngine()
    
    // MARK: - Embedding Models
    
    public enum EmbeddingModel: String, CaseIterable {
        case bgeSmall = "bge-small-en-v1.5"     // 33M params, 384 dims
        case bgeMicro = "bge-micro-v2"          // 17M params, 384 dims
        case allMiniLM = "all-MiniLM-L6-v2"     // 22M params, 384 dims
        case nomic = "nomic-embed-text-v1.5"    // 137M params, 768 dims
        
        public var dimensions: Int {
            switch self {
            case .bgeSmall, .bgeMicro, .allMiniLM: return 384
            case .nomic: return 768
            }
        }
        
        public var sizeMB: Int {
            switch self {
            case .bgeMicro: return 70
            case .allMiniLM: return 90
            case .bgeSmall: return 130
            case .nomic: return 550
            }
        }
    }
    
    // MARK: - State
    
    private var currentModel: EmbeddingModel?
    private var isLoaded: Bool = false
    
    // MARK: - Generate Embeddings
    
    /// Embed a single text
    public func embed(_ text: String, model: EmbeddingModel = .bgeSmall) async throws -> [Float] {
        try await ensureLoaded(model)
        
        // Simplified embedding generation
        // Real implementation would use MLX model
        
        // For now, generate deterministic pseudo-embedding based on text
        var embedding = [Float](repeating: 0, count: model.dimensions)
        
        let hash = text.hashValue
        for i in 0..<model.dimensions {
            let seed = hash ^ (i * 31)
            embedding[i] = Float(seed % 1000) / 1000.0 - 0.5
        }
        
        // Normalize
        normalize(&embedding)
        
        return embedding
    }
    
    /// Embed multiple texts (batched for efficiency)
    public func embedBatch(_ texts: [String], model: EmbeddingModel = .bgeSmall) async throws -> [[Float]] {
        try await ensureLoaded(model)
        
        var embeddings: [[Float]] = []
        
        for text in texts {
            let embedding = try await embed(text, model: model)
            embeddings.append(embedding)
        }
        
        return embeddings
    }
    
    private func ensureLoaded(_ model: EmbeddingModel) async throws {
        if currentModel == model && isLoaded {
            return
        }
        
        // Load model (placeholder)
        currentModel = model
        isLoaded = true
    }
    
    // MARK: - Similarity
    
    /// Cosine similarity between two embeddings
    public func similarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        
        var dotProduct: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        
        return dotProduct // Assuming normalized vectors
    }
    
    /// Find most similar embeddings
    public func findSimilar(
        query: [Float],
        candidates: [[Float]],
        topK: Int = 5
    ) -> [(index: Int, score: Float)] {
        var scores: [(Int, Float)] = []
        
        for (index, candidate) in candidates.enumerated() {
            let score = similarity(query, candidate)
            scores.append((index, score))
        }
        
        return scores
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map { $0 }
    }
    
    // MARK: - Vector Math
    
    private func normalize(_ vector: inout [Float]) {
        var norm: Float = 0
        vDSP_svesq(vector, 1, &norm, vDSP_Length(vector.count))
        norm = sqrt(norm)
        
        if norm > 0 {
            var scale = 1.0 / norm
            vDSP_vsmul(vector, 1, &scale, &vector, 1, vDSP_Length(vector.count))
        }
    }
    
    /// Average multiple embeddings
    public func average(_ embeddings: [[Float]]) -> [Float] {
        guard let first = embeddings.first else { return [] }
        
        var result = [Float](repeating: 0, count: first.count)
        
        for embedding in embeddings {
            for (i, value) in embedding.enumerated() {
                result[i] += value
            }
        }
        
        let scale = 1.0 / Float(embeddings.count)
        vDSP_vsmul(result, 1, [scale], &result, 1, vDSP_Length(result.count))
        
        normalize(&result)
        
        return result
    }
}

// MARK: - Vector Store

/// Simple on-device vector database
public actor VectorStore {
    
    public static let shared = VectorStore()
    
    // MARK: - Types
    
    public struct Document: Codable, Identifiable {
        public let id: String
        public let content: String
        public let metadata: [String: String]
        public var embedding: [Float]?
        
        public init(id: String = UUID().uuidString, content: String, metadata: [String: String] = [:]) {
            self.id = id
            self.content = content
            self.metadata = metadata
        }
    }
    
    public struct SearchResult {
        public let document: Document
        public let score: Float
    }
    
    // MARK: - State
    
    private var documents: [String: Document] = [:]
    private var embeddings: [String: [Float]] = [:]
    
    // MARK: - Operations
    
    /// Add document to store
    public func add(_ document: Document) async throws {
        var doc = document
        
        // Generate embedding if not provided
        if doc.embedding == nil {
            let engine = await EmbeddingEngine.shared
            doc.embedding = try await engine.embed(doc.content)
        }
        
        documents[doc.id] = doc
        embeddings[doc.id] = doc.embedding
    }
    
    /// Add multiple documents
    public func addBatch(_ docs: [Document]) async throws {
        let engine = await EmbeddingEngine.shared
        let texts = docs.map { $0.content }
        let batchEmbeddings = try await engine.embedBatch(texts)
        
        for (doc, embedding) in zip(docs, batchEmbeddings) {
            var document = doc
            document.embedding = embedding
            documents[doc.id] = document
            embeddings[doc.id] = embedding
        }
    }
    
    /// Search for similar documents
    public func search(query: String, topK: Int = 5) async throws -> [SearchResult] {
        let engine = await EmbeddingEngine.shared
        let queryEmbedding = try await engine.embed(query)
        
        return search(embedding: queryEmbedding, topK: topK)
    }
    
    /// Search by embedding
    public func search(embedding: [Float], topK: Int = 5) -> [SearchResult] {
        let candidates = Array(embeddings.values)
        let ids = Array(embeddings.keys)
        
        let engine = EmbeddingEngine.shared
        
        var results: [SearchResult] = []
        
        for (id, docEmbedding) in embeddings {
            guard let doc = documents[id] else { continue }
            
            var dotProduct: Float = 0
            vDSP_dotpr(embedding, 1, docEmbedding, 1, &dotProduct, vDSP_Length(embedding.count))
            
            results.append(SearchResult(document: doc, score: dotProduct))
        }
        
        return results
            .sorted { $0.score > $1.score }
            .prefix(topK)
            .map { $0 }
    }
    
    /// Delete document
    public func delete(_ id: String) {
        documents.removeValue(forKey: id)
        embeddings.removeValue(forKey: id)
    }
    
    /// Clear all
    public func clear() {
        documents.removeAll()
        embeddings.removeAll()
    }
    
    // MARK: - Persistence
    
    public func save(to url: URL) throws {
        let data = try JSONEncoder().encode(Array(documents.values))
        try data.write(to: url)
    }
    
    public func load(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let docs = try JSONDecoder().decode([Document].self, from: data)
        
        for doc in docs {
            documents[doc.id] = doc
            embeddings[doc.id] = doc.embedding ?? []
        }
    }
    
    // MARK: - Stats
    
    public var count: Int { documents.count }
    
    public var memoryMB: Int {
        let embeddingBytes = embeddings.values.reduce(0) { $0 + $1.count * 4 }
        let contentBytes = documents.values.reduce(0) { $0 + $1.content.utf8.count }
        return (embeddingBytes + contentBytes) / (1024 * 1024)
    }
}
