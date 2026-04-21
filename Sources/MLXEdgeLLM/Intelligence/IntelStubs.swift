// IntelStubs.swift — Intel subsystem implementations
// MLXEmbeddingEngine: 3-tier on-device embedding (NLEmbedding → HTTP server)
// IntelCorpus: real NLEmbedding semantic search over bundled knowledge base

import Foundation
import Combine
import Accelerate
import NaturalLanguage
import CryptoKit

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

    // MARK: - Incremental indexing

    /// Cache file on disk. Contains `{signature, chunks}`. On cold start we
    /// re-use it if and only if the signature matches the current bundle.
    private var cacheURL: URL {
        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IntelCorpus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("index.json")
    }

    /// Codable wire format for the persisted index.
    private struct CachedIndex: Codable {
        let signature: String
        let chunks: [CachedChunk]
    }
    private struct CachedChunk: Codable {
        let id: String
        let title: String
        let content: String
        let embedding: [Float]
    }

    /// SHA-256 over the sorted list of bundled .md file paths + their byte
    /// contents. Any content change flips the signature and invalidates the
    /// cache. Empty bundle → empty signature, loaded state is empty-but-ready.
    private func computeBundleSignature(paths: [String]) -> String {
        let sorted = paths.sorted()
        var hasher = SHA256()
        for p in sorted {
            hasher.update(data: Data(p.utf8))
            if let data = try? Data(contentsOf: URL(fileURLWithPath: p)) {
                hasher.update(data: data)
            }
        }
        let digest = hasher.finalize()
        return Data(digest).base64EncodedString()
    }

    func indexAllSources() async {
        guard !isIndexing else { return }
        isIndexing = true
        indexProgress = 0
        defer { isIndexing = false }

        let mdFiles = Bundle.main.paths(forResourcesOfType: "md", inDirectory: nil)
        let signature = computeBundleSignature(paths: mdFiles)

        // Fast path: in-memory already populated and bundle unchanged.
        if isReady, signature == currentSignature { return }

        // Disk cache path: if the persisted index matches the current bundle
        // signature, rehydrate from it — no re-embedding needed.
        if let cached = loadCachedIndex(), cached.signature == signature {
            self.index = cached.chunks.map {
                IndexedChunk(id: $0.id, title: $0.title, content: $0.content, embedding: $0.embedding)
            }
            self.totalDocuments = index.count
            self.currentSignature = signature
            self.indexProgress = 1.0
            self.isReady = true
            return
        }

        // Full rebuild path.
        guard !mdFiles.isEmpty else {
            index = []
            totalDocuments = 0
            currentSignature = signature
            isReady = true
            return
        }

        var chunks: [(title: String, content: String)] = []
        for path in mdFiles {
            let title = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
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
        currentSignature = signature
        isReady = true
        persistCachedIndex(signature: signature, chunks: built)
    }

    /// In-memory record of which bundle signature the current `index` was built against.
    private var currentSignature: String = ""

    private func loadCachedIndex() -> CachedIndex? {
        guard FileManager.default.fileExists(atPath: cacheURL.path),
              let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode(CachedIndex.self, from: data) else { return nil }
        return decoded
    }

    private func persistCachedIndex(signature: String, chunks: [IndexedChunk]) {
        let payload = CachedIndex(
            signature: signature,
            chunks: chunks.map {
                CachedChunk(id: $0.id, title: $0.title, content: $0.content, embedding: $0.embedding)
            }
        )
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: cacheURL, options: .atomic)
        }
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

/// Three-stage, <50ms, no-LLM verification of generated responses against retrieval
/// source chunks. Ported from AI/RAG/VerifyPipeline.swift to operate on
/// IntelSearchResult — the type IntelTabView already uses.
///
/// Stage 1: Sentence-level BM25-ish grounding (token overlap vs. source chunks).
/// Stage 2: Safety-domain keyword flag — when the response touches
///          medical/tactical/coord-sensitive topics AND has ungrounded claims,
///          attach a disclaimer.
/// Stage 3: Contradiction detection — if the response says "don't X" but the
///          sources recommend X, flag as contradictory.
@MainActor
final class VerifyPipeline: ObservableObject {
    static let shared = VerifyPipeline()

    private let groundingThreshold: Double = 0.4
    private let minVerifiedConfidence: Double = 0.6

    private let safetyDomains: Set<String> = [
        "tourniquet", "cpr", "bleeding", "wound", "fracture", "poison",
        "explosive", "detonation", "ied", "mine",
        "bearing", "azimuth", "coordinates", "grid",
        "dosage", "medication", "injection", "airway"
    ]
    private let negationPatterns: [String] = [
        "do not", "don't", "never", "avoid", "stop", "cease",
        "prohibited", "forbidden", "dangerous to", "fatal if"
    ]
    private let stopWords: Set<String> = [
        "the", "and", "for", "with", "this", "that", "from", "are", "was",
        "will", "can", "not", "but", "you", "your", "have", "they", "their",
        "when", "then", "into", "over", "each", "only", "also", "both",
        "been", "more", "very", "should", "would", "could", "may", "might"
    ]

    private init() {}

    // MARK: - Claim verification (one-shot)

    func verify(claim: String) async -> IntelVerificationResult {
        // No sources passed → we cannot ground anything.
        IntelVerificationResult(
            isVerified: false,
            confidence: 0,
            sources: [],
            explanation: "No source material supplied for verification.",
            suggestedDisclaimer: "This claim was not cross-checked against any source — treat as unverified."
        )
    }

    // MARK: - Response verification (RAG output)

    func verify(response: String, query: String, sourceResults: [IntelSearchResult]) -> IntelVerificationResult {
        let sentences = splitSentences(response)
        guard !sentences.isEmpty else {
            return IntelVerificationResult(
                isVerified: false,
                confidence: 0,
                sources: [],
                explanation: "Response had no analyzable sentences.",
                suggestedDisclaimer: nil
            )
        }

        let sourceTexts = sourceResults.map { $0.content.lowercased() }
        let sourceJoined = sourceTexts.joined(separator: " ")
        let sourceLabels = sourceResults.map { $0.sourceLabel }

        // Stage 1: sentence-level grounding
        var grounded = 0
        var ungrounded = 0
        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > 10 else { continue }
            if computeOverlap(sentence: trimmed.lowercased(), sources: sourceTexts) >= groundingThreshold {
                grounded += 1
            } else {
                ungrounded += 1
            }
        }
        let totalClaims = grounded + ungrounded
        let confidence = totalClaims == 0 ? 0.5 : Double(grounded) / Double(totalClaims)

        // Stage 2: safety-domain disclaimer
        let responseLower = response.lowercased()
        let touchesSafety = safetyDomains.contains(where: { responseLower.contains($0) })
        var disclaimer: String? = nil
        if touchesSafety && ungrounded > 0 {
            disclaimer = "This response contains safety-critical advice that could not be fully verified against source material. Cross-reference with official protocols."
        }

        // Stage 3: contradiction detection
        var contradictory = false
        for sentence in sentences {
            let lower = sentence.lowercased()
            for pattern in negationPatterns where lower.contains(pattern) {
                let action = extractActionAfterNegation(lower, pattern: pattern)
                if !action.isEmpty {
                    let sourceRecommends = sourceJoined.contains(action)
                        && !sourceJoined.contains("\(pattern) \(action)")
                    if sourceRecommends { contradictory = true; break }
                }
            }
            if contradictory { break }
        }

        let isVerified = confidence >= minVerifiedConfidence && !contradictory

        let explanation: String
        if contradictory {
            explanation = "Response appears to contradict source material."
        } else if touchesSafety && ungrounded > 0 {
            explanation = "Safety-critical claims partially unverified (\(grounded)/\(totalClaims) grounded)."
        } else if totalClaims == 0 {
            explanation = "Response too short to verify."
        } else {
            explanation = "\(grounded)/\(totalClaims) claims grounded in sources."
        }

        return IntelVerificationResult(
            isVerified: isVerified,
            confidence: confidence,
            sources: Array(Set(sourceLabels)),
            explanation: explanation,
            suggestedDisclaimer: disclaimer
        )
    }

    // MARK: - Helpers

    private func splitSentences(_ text: String) -> [String] {
        let pattern = "[.!?]\\s+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [text] }
        let range = NSRange(text.startIndex..., in: text)
        var sentences: [String] = []
        var lastEnd = text.startIndex
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let r = match?.range, let sr = Range(r, in: text) else { return }
            sentences.append(String(text[lastEnd..<sr.upperBound]))
            lastEnd = sr.upperBound
        }
        if lastEnd < text.endIndex { sentences.append(String(text[lastEnd...])) }
        return sentences.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func computeOverlap(sentence: String, sources: [String]) -> Double {
        let words = tokenize(sentence)
        guard !words.isEmpty else { return 0 }
        var matches = 0
        for word in words where sources.contains(where: { $0.contains(word) }) { matches += 1 }
        return Double(matches) / Double(words.count)
    }

    private func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }

    private func extractActionAfterNegation(_ text: String, pattern: String) -> String {
        guard let range = text.range(of: pattern) else { return "" }
        let after = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return after.split(separator: " ").prefix(4).joined(separator: " ")
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
