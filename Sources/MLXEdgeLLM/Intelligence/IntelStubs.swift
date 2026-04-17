// IntelStubs.swift — Minimal interfaces for IntelCorpus, VerifyPipeline, MLXEmbeddingEngine
// Full RAG pipeline implementations deferred until all dependencies are wired

import Foundation
import Combine

// MARK: - IntelCorpus (stub)

struct IntelSearchResult: Identifiable {
    let id = UUID()
    let title: String
    let content: String
    let score: Double
    let sourceLabel: String
}

@MainActor
final class IntelCorpus: ObservableObject {
    static let shared = IntelCorpus()

    @Published var totalDocuments: Int = 0
    @Published var isIndexing: Bool = false
    @Published var indexProgress: Double = 0.0
    @Published var isReady: Bool = false

    private init() {}

    func indexAllSources() async {
        isReady = true
    }

    func search(query: String, topK: Int = 5) async -> [IntelSearchResult] {
        return []
    }

    func buildContext(for query: String) async -> String {
        return ""
    }

    func ingestPhotoAnalysis(photoId: UUID, analysisText: String, metadata: [String: String]) async {
        totalDocuments += 1
    }
}

// MARK: - MLXEmbeddingEngine (stub)

@MainActor
final class MLXEmbeddingEngine: ObservableObject {
    static let shared = MLXEmbeddingEngine()

    @Published var isReady: Bool = false
    @Published var modelName: String = "none"

    private init() {}

    func batchEmbed(texts: [String], batchSize: Int = 32, onProgress: ((Double) -> Void)? = nil) async -> [[Float]]? {
        return nil
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

    func save() {
        // Persistence deferred
    }
}
