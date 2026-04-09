// IntelStubs.swift — Minimal interfaces for IntelCorpus, VerifyPipeline, MLXEmbeddingEngine
// Full RAG pipeline implementations deferred until all dependencies are wired

import Foundation
import Combine

// MARK: - IntelCorpus (stub)

@MainActor
final class IntelCorpus: ObservableObject {
    static let shared = IntelCorpus()

    @Published var totalDocuments: Int = 0
    @Published var isIndexing: Bool = false
    @Published var indexProgress: Double = 0.0
    @Published var isReady: Bool = false

    private init() {}

    func indexAllSources() async {
        // Full hybrid RRF indexing deferred
        isReady = true
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
}

// MARK: - VerifyPipeline (stub)

@MainActor
final class VerifyPipeline: ObservableObject {
    static let shared = VerifyPipeline()

    private init() {}

    func verify(claim: String) async -> VerificationResult {
        VerificationResult(isVerified: false, confidence: 0, sources: [], explanation: "Verification pipeline not yet initialized")
    }
}

// MARK: - VerificationResult

struct VerificationResult {
    let isVerified: Bool
    let confidence: Double
    let sources: [String]
    let explanation: String
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

@MainActor
final class EmbeddedVectorStore: ObservableObject {
    static let shared = EmbeddedVectorStore()

    private init() {}
}
