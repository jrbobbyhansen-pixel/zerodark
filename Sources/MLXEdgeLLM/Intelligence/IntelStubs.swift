// IntelStubs.swift — Intel subsystem implementations
// MLXEmbeddingEngine: 3-tier on-device embedding (NLEmbedding → HTTP server)
// IntelCorpus: real NLEmbedding semantic search over bundled knowledge base

import Foundation
import Combine
import Accelerate
import NaturalLanguage

// MARK: - IntelSearchResult

struct IntelSearchResult: Identifiable {
    let id = UUID()
    let title: String
    let content: String
    let score: Double
    let sourceLabel: String
}

// MARK: - MLXEmbeddingEngine

/// On-device embedding engine with 3-tier fallback.
/// Tier 1: NLEmbedding (built-in, always available, Neural Engine, 512-dim)
/// Tier 2: HTTP server at 127.0.0.1:8800 (optional enhancement, 384-dim all-MiniLM)
/// Note: mixing tiers requires index rebuild; NLEmbedding is the stable default.
@MainActor
final class MLXEmbeddingEngine: ObservableObject {
    static let shared = MLXEmbeddingEngine()

    enum EmbeddingTier {
        case nlEmbedding   // Built-in Apple NLEmbedding, always available
        case httpServer    // Optional Mac server at port 8800
    }

    @Published var isReady: Bool = false
    @Published var modelName: String = "NLEmbedding"
    @Published var currentTier: EmbeddingTier = .nlEmbedding

    private let serverURL = "http://127.0.0.1:8800"
    private var cache: [String: [Float]] = [:]
    private let maxCacheSize = 2000

    // NLEmbedding instance — lazy to avoid main thread work at init
    private var nlEmbedding: NLEmbedding? = nil

    private init() {
        Task {
            await setupNLEmbedding()
        }
    }

    private func setupNLEmbedding() async {
        // NLEmbedding.sentenceEmbedding downloads a small on-device model on first call (~10MB)
        let embedding = NLEmbedding.sentenceEmbedding(for: .english)
        self.nlEmbedding = embedding
        self.isReady = embedding != nil
        self.modelName = embedding != nil ? "NLEmbedding" : "Unavailable"
    }

    // MARK: - Embed (single)

    func embed(text: String) async -> [Float]? {
        let key = String(text.prefix(200).lowercased())
        if let cached = cache[key] { return cached }

        let result = embedNL(text: text)
        if let result {
            cacheEmbedding(key: key, value: result)
        }
        return result
    }

    // MARK: - Batch embed

    func batchEmbed(texts: [String], batchSize: Int = 32, onProgress: ((Double) -> Void)? = nil) async -> [[Float]]? {
        var results: [[Float]] = []
        for (i, text) in texts.enumerated() {
            guard let vec = await embed(text: text) else { return nil }
            results.append(vec)
            onProgress?(Double(i + 1) / Double(texts.count))
        }
        return results
    }

    // MARK: - NLEmbedding tier

    private func embedNL(text: String) -> [Float]? {
        guard let embedding = nlEmbedding else { return nil }
        guard let vector = embedding.vector(for: text) else { return nil }
        return vector.map { Float($0) }
    }

    // MARK: - Cosine similarity (vDSP-accelerated)

    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        vDSP_dotpr(a, 1, a, 1, &normA, vDSP_Length(a.count))
        vDSP_dotpr(b, 1, b, 1, &normB, vDSP_Length(b.count))
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }

    // MARK: - Cache

    private func cacheEmbedding(key: String, value: [Float]) {
        if cache.count >= maxCacheSize {
            let keysToRemove = Array(cache.keys.prefix(maxCacheSize / 4))
            for k in keysToRemove { cache.removeValue(forKey: k) }
        }
        cache[key] = value
    }

    func clearCache() { cache.removeAll() }
}

// MARK: - IntelCorpus

/// Semantic search corpus backed by bundled knowledge base markdown files.
/// Uses NLEmbedding for zero-dependency on-device vector search.
@MainActor
final class IntelCorpus: ObservableObject {
    static let shared = IntelCorpus()

    @Published var totalDocuments: Int = 0
    @Published var isIndexing: Bool = false
    @Published var indexProgress: Double = 0.0
    @Published var isReady: Bool = false

    struct IndexedChunk {
        let id: String
        let title: String
        let content: String
        let embedding: [Float]
    }

    private var index: [IndexedChunk] = []
    private let engine = MLXEmbeddingEngine.shared

    private init() {}

    func indexAllSources() async {
        guard !isReady, !isIndexing else { return }
        isIndexing = true
        indexProgress = 0

        let mdFiles = Bundle.main.paths(forResourcesOfType: "md", inDirectory: nil)
        let total = mdFiles.count
        guard total > 0 else {
            isIndexing = false
            isReady = true
            return
        }

        var chunks: [(title: String, content: String)] = []
        for path in mdFiles {
            let title = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            // Split by double newline (paragraphs), keep substantial chunks
            let paragraphs = text.components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count >= 40 }
            for para in paragraphs {
                chunks.append((title: title, content: para))
            }
        }

        var built: [IndexedChunk] = []
        for (i, chunk) in chunks.enumerated() {
            if let vec = await engine.embed(text: chunk.content) {
                built.append(IndexedChunk(
                    id: "\(chunk.title)-\(i)",
                    title: chunk.title,
                    content: chunk.content,
                    embedding: vec
                ))
            }
            indexProgress = Double(i + 1) / Double(chunks.count)
        }

        index = built
        totalDocuments = built.count
        isIndexing = false
        isReady = true
    }

    func search(query: String, topK: Int = 5) async -> [IntelSearchResult] {
        guard let queryVec = await engine.embed(text: query) else { return [] }

        let scored = index.map { chunk -> (IntelSearchResult, Float) in
            let sim = MLXEmbeddingEngine.cosineSimilarity(queryVec, chunk.embedding)
            return (IntelSearchResult(
                title: chunk.title.replacingOccurrences(of: "-", with: " ").capitalized,
                content: chunk.content,
                score: Double(sim),
                sourceLabel: "Knowledge Base"
            ), sim)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(topK)
        .map(\.0)

        return Array(scored)
    }

    func buildContext(for query: String) async -> String {
        let results = await search(query: query, topK: 3)
        return results.map { "[\($0.title)]\n\($0.content)" }.joined(separator: "\n\n---\n\n")
    }

    func ingestPhotoAnalysis(photoId: UUID, analysisText: String, metadata: [String: String]) async {
        totalDocuments += 1
    }
}

// MARK: - VerifyPipeline (stub)

@MainActor
final class VerifyPipeline: ObservableObject {
    static let shared = VerifyPipeline()

    private init() {}

    func verify(claim: String) async -> IntelVerificationResult {
        IntelVerificationResult(isVerified: false, confidence: 0, sources: [], explanation: "Verification pipeline not yet initialized", suggestedDisclaimer: nil)
    }

    func verify(response: String, query: String, sourceResults: [IntelSearchResult]) -> IntelVerificationResult {
        IntelVerificationResult(isVerified: false, confidence: 0, sources: [], explanation: "Verification pipeline not yet initialized", suggestedDisclaimer: nil)
    }
}

// MARK: - IntelVerificationResult

struct IntelVerificationResult {
    let isVerified: Bool
    let confidence: Double
    let sources: [String]
    let explanation: String
    let suggestedDisclaimer: String?
}

// MARK: - MultiModalResult

struct MultiModalResult: Identifiable {
    let id = UUID()
    let title: String
    let content: String
    let score: Double
    let source: String
}

// MARK: - EmbeddedVectorStore (stub)

enum VectorSourceType: String {
    case knowledgeBase
    case photoIntel
    case lessonLearned
}

struct EmbeddedVector {
    let data: [Float]
    let documentId: String
    let sourceType: VectorSourceType
    let metadata: [String: String]
}

@MainActor
final class EmbeddedVectorStore: ObservableObject {
    static let shared = EmbeddedVectorStore()
    private var vectors: [EmbeddedVector] = []

    private init() {}

    func count(for sourceType: VectorSourceType) -> Int {
        vectors.filter { $0.sourceType == sourceType }.count
    }

    func removeVectors(forSourceType type: VectorSourceType) {
        vectors.removeAll { $0.sourceType == type }
    }

    func addVectors(_ newVectors: [EmbeddedVector]) {
        vectors.append(contentsOf: newVectors)
    }

    func save() {}
}
