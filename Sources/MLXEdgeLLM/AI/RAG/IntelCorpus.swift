// IntelCorpus.swift — Multi-Modal RAG Fusion Coordinator
// ZeroDark Intel Tab v6.0
//
// Fuses: KnowledgeRAG + TacticalCorpus + LessonsLearnedDb + PhotoIntel
// into a unified hybrid search across all intelligence sources.

import Foundation
import SwiftUI
import Combine

// MARK: - Multi-Modal Search Result

struct MultiModalResult: Identifiable {
    let id: UUID
    let content: String
    let title: String
    let source: EmbeddedVector.SourceType
    let score: Double
    let matchType: ScoredChunk.MatchType
    let metadata: [String: String]

    var sourceLabel: String {
        switch source {
        case .knowledgeBase:   return "Field Manual"
        case .tacticalCorpus:  return "Tactical Corpus"
        case .lessonLearned:   return "Lessons Learned"
        case .photoIntel:      return "Photo Intel"
        }
    }

    var sourceIcon: String {
        switch source {
        case .knowledgeBase:   return "book.fill"
        case .tacticalCorpus:  return "shield.fill"
        case .lessonLearned:   return "lightbulb.fill"
        case .photoIntel:      return "camera.fill"
        }
    }

    var sourceColor: Color {
        switch source {
        case .knowledgeBase:   return ZDDesign.skyBlue
        case .tacticalCorpus:  return ZDDesign.safetyYellow
        case .lessonLearned:   return ZDDesign.successGreen
        case .photoIntel:      return ZDDesign.sunsetOrange
        }
    }
}

// MARK: - Intel Corpus

@MainActor
final class IntelCorpus: ObservableObject {
    static let shared = IntelCorpus()

    @Published var totalDocuments: Int = 0
    @Published var isIndexing: Bool = false
    @Published var indexProgress: Double = 0.0
    @Published var isReady: Bool = false

    private let knowledgeRAG = KnowledgeRAG.shared
    private let tacticalCorpus = TacticalCorpus.shared
    private let lessonsDb = LessonsLearnedDb()
    private let vectorStore = EmbeddedVectorStore.shared
    private let embeddingEngine = MLXEmbeddingEngine.shared

    // RRF constant
    private let rrfK: Double = 60.0

    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupLessonObserver()
        Task { await indexAllSources() }
    }

    // MARK: - Index All Sources

    func indexAllSources() async {
        guard !isIndexing else { return }
        isIndexing = true
        indexProgress = 0.0

        // Wait for knowledge base to load
        while !knowledgeRAG.isLoaded {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        do {
            try await HybridSearchIndex.shared.buildIndex(
                chunks: knowledgeRAG.allChunks,
                corpus: tacticalCorpus,
                lessons: lessonsDb.lessons,
                photoAnalyses: [] // Photos indexed live as they come in
            )

            totalDocuments = await HybridSearchIndex.shared.documentCount
            isReady = true
        } catch {
            print("[IntelCorpus] Index build failed: \(error)")
        }

        isIndexing = false
        indexProgress = 1.0

        AppState.shared.postIntelEvent(.corpusReindexed(documentCount: totalDocuments))
    }

    // MARK: - Multi-Modal Hybrid Search

    func search(query: String, topK: Int = 5,
                sources: Set<EmbeddedVector.SourceType>? = nil) async -> [MultiModalResult] {
        // 1. BM25 keyword search across knowledge base
        let bm25Results = knowledgeRAG.search(query: query, topK: topK * 2)

        // 2. Vector search across ALL sources
        var vectorResults: [(EmbeddedVector, Float)] = []
        if let queryEmbedding = await embeddingEngine.embed(text: query) {
            if let sources {
                // Search each requested source type
                for source in sources {
                    let hits = vectorStore.searchBySimilarity(
                        query: queryEmbedding, topK: topK, sourceFilter: source
                    )
                    vectorResults.append(contentsOf: hits)
                }
                // Re-sort by similarity
                vectorResults.sort { $0.1 > $1.1 }
            } else {
                // Search all sources
                vectorResults = vectorStore.searchBySimilarity(
                    query: queryEmbedding, topK: topK * 2
                )
            }
        }

        // 3. RRF fusion across both result sets
        return fuseResults(bm25: bm25Results, vector: vectorResults, topK: topK)
    }

    private func fuseResults(
        bm25: [KnowledgeChunk],
        vector: [(EmbeddedVector, Float)],
        topK: Int
    ) -> [MultiModalResult] {
        var scores: [String: Double] = [:]
        var resultMap: [String: MultiModalResult] = [:]
        var inBM25: Set<String> = []
        var inVector: Set<String> = []

        // BM25 results (all from knowledge base)
        for (rank, chunk) in bm25.enumerated() {
            let key = chunk.id.uuidString
            let rrfScore = 1.0 / (rrfK + Double(rank + 1))
            scores[key, default: 0] += rrfScore
            inBM25.insert(key)

            if resultMap[key] == nil {
                resultMap[key] = MultiModalResult(
                    id: chunk.id,
                    content: chunk.content,
                    title: chunk.title,
                    source: .knowledgeBase,
                    score: 0,
                    matchType: .keyword,
                    metadata: ["category": chunk.category.rawValue, "filename": chunk.filename]
                )
            }
        }

        // Vector results (any source)
        for (rank, (embVec, similarity)) in vector.enumerated() {
            let key = embVec.documentId
            let rrfScore = 1.0 / (rrfK + Double(rank + 1))
            scores[key, default: 0] += rrfScore
            inVector.insert(key)

            if resultMap[key] == nil {
                resultMap[key] = MultiModalResult(
                    id: embVec.id,
                    content: resolveContent(for: embVec),
                    title: embVec.metadata["title"] ?? embVec.metadata["key"] ?? "Intel",
                    source: embVec.sourceType,
                    score: Double(similarity),
                    matchType: .semantic,
                    metadata: embVec.metadata
                )
            }
        }

        // Sort by fused score
        return scores
            .sorted { $0.value > $1.value }
            .prefix(topK)
            .compactMap { (key, score) -> MultiModalResult? in
                guard var result = resultMap[key] else { return nil }
                let matchType: ScoredChunk.MatchType
                if inBM25.contains(key) && inVector.contains(key) {
                    matchType = .hybrid
                } else if inVector.contains(key) {
                    matchType = .semantic
                } else {
                    matchType = .keyword
                }
                result = MultiModalResult(
                    id: result.id,
                    content: result.content,
                    title: result.title,
                    source: result.source,
                    score: score,
                    matchType: matchType,
                    metadata: result.metadata
                )
                return result
            }
    }

    // MARK: - Content Resolution

    private func resolveContent(for vector: EmbeddedVector) -> String {
        switch vector.sourceType {
        case .knowledgeBase:
            return knowledgeRAG.allChunks
                .first { $0.id.uuidString == vector.documentId }?.content ?? ""

        case .tacticalCorpus:
            let key = vector.metadata["key"] ?? ""
            let docs = tacticalCorpus.allDocuments()
            return docs.first { $0.key == key }?.content ?? ""

        case .lessonLearned:
            return lessonsDb.lessons
                .first { $0.id.uuidString == vector.documentId }
                .map { "\($0.scenario) — \($0.topic): \($0.outcome). \($0.details)" } ?? ""

        case .photoIntel:
            return vector.metadata["analysis"] ?? ""
        }
    }

    // MARK: - Live Ingestion

    func ingestPhotoAnalysis(photoId: UUID, analysisText: String,
                             metadata: [String: String]) async {
        var meta = metadata
        meta["analysis"] = analysisText

        do {
            try await HybridSearchIndex.shared.addToIndex(
                text: analysisText,
                sourceType: .photoIntel,
                documentId: photoId.uuidString,
                metadata: meta
            )
            totalDocuments += 1
            AppState.shared.postIntelEvent(.photoAnalyzed(photoId: photoId, summary: String(analysisText.prefix(100))))
        } catch {
            print("[IntelCorpus] Photo ingest failed: \(error)")
        }
    }

    func ingestLesson(_ lesson: Lesson) async {
        let text = "\(lesson.scenario) — \(lesson.topic): \(lesson.outcome). \(lesson.details)"
        do {
            try await HybridSearchIndex.shared.addToIndex(
                text: text,
                sourceType: .lessonLearned,
                documentId: lesson.id.uuidString,
                metadata: ["scenario": lesson.scenario, "topic": lesson.topic]
            )
            totalDocuments += 1
            AppState.shared.postIntelEvent(.lessonAdded(scenario: lesson.scenario))
        } catch {
            print("[IntelCorpus] Lesson ingest failed: \(error)")
        }
    }

    // MARK: - Lesson Observer

    private func setupLessonObserver() {
        NotificationCenter.default.publisher(for: .lessonAdded)
            .compactMap { $0.object as? Lesson }
            .sink { [weak self] lesson in
                Task { await self?.ingestLesson(lesson) }
            }
            .store(in: &cancellables)
    }

    // MARK: - Build Context for LLM

    func buildContext(for query: String, maxWords: Int = 600) async -> String {
        let results = await search(query: query, topK: 5)
        guard !results.isEmpty else { return "" }

        var context = "RELEVANT INTELLIGENCE:\n\n"
        var words = 0
        for result in results {
            let w = result.content.split(separator: " ").count
            if words + w > maxWords { break }
            context += "[\(result.title)] (\(result.sourceLabel), \(result.matchType.rawValue))\n\(result.content)\n\n"
            words += w
        }
        return context
    }
}
