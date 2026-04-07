// HybridSearchIndex.swift — Vector Index Builder for Multi-Modal RAG
// ZeroDark Intel Tab v6.0

import Foundation

actor HybridSearchIndex {
    static let shared = HybridSearchIndex()

    private(set) var isIndexed: Bool = false
    private(set) var indexProgress: Double = 0.0
    private(set) var documentCount: Int = 0

    private let indexVersionKey = "hybridSearchIndexVersion"
    private let currentVersion = "v6.0"

    // MARK: - Full Index Build

    func buildIndex(
        chunks: [KnowledgeChunk],
        corpus: TacticalCorpus,
        lessons: [Lesson],
        photoAnalyses: [(id: String, text: String, metadata: [String: String])]
    ) async throws {
        var allTexts: [String] = []
        var allMeta: [(documentId: String, sourceType: EmbeddedVector.SourceType, metadata: [String: String])] = []

        // 1. Knowledge base chunks
        for chunk in chunks {
            allTexts.append(chunk.content)
            allMeta.append((
                documentId: chunk.id.uuidString,
                sourceType: .knowledgeBase,
                metadata: ["title": chunk.title, "category": chunk.category.rawValue]
            ))
        }

        // 2. Tactical corpus documents
        let corpusDocs = await MainActor.run { corpus.allDocuments() }
        for doc in corpusDocs {
            allTexts.append("\(doc.key): \(doc.content)")
            allMeta.append((
                documentId: "corpus-\(doc.key)",
                sourceType: .tacticalCorpus,
                metadata: ["key": doc.key, "category": doc.category]
            ))
        }

        // 3. Lessons learned
        for lesson in lessons {
            let text = "\(lesson.scenario) — \(lesson.topic): \(lesson.outcome). \(lesson.details)"
            allTexts.append(text)
            allMeta.append((
                documentId: lesson.id.uuidString,
                sourceType: .lessonLearned,
                metadata: ["scenario": lesson.scenario, "topic": lesson.topic]
            ))
        }

        // 4. Photo analyses
        for photo in photoAnalyses {
            allTexts.append(photo.text)
            allMeta.append((
                documentId: photo.id,
                sourceType: .photoIntel,
                metadata: photo.metadata
            ))
        }

        guard !allTexts.isEmpty else { return }

        // Batch embed via MainActor-isolated engine
        let embeddings = await MainActor.run {
            MLXEmbeddingEngine.shared
        }
        guard let embedded = await embeddings.batchEmbed(
            texts: allTexts,
            batchSize: 32,
            onProgress: { [weak self] progress in
                Task { await self?.updateProgress(progress) }
            }
        ) else { return }

        // Build vectors
        var vectors: [EmbeddedVector] = []
        for (i, embedding) in embedded.enumerated() {
            vectors.append(EmbeddedVector(
                data: embedding,
                documentId: allMeta[i].documentId,
                sourceType: allMeta[i].sourceType,
                metadata: allMeta[i].metadata
            ))
        }

        // Store via MainActor-isolated store
        await MainActor.run {
            let store = EmbeddedVectorStore.shared
            store.clear()
            store.addVectors(vectors)
            store.save()
        }

        documentCount = allTexts.count
        isIndexed = true
        indexProgress = 1.0
        UserDefaults.standard.set(currentVersion, forKey: indexVersionKey)
    }

    // MARK: - Incremental Add

    func addToIndex(
        text: String,
        sourceType: EmbeddedVector.SourceType,
        documentId: String,
        metadata: [String: String]
    ) async throws {
        let engine = await MainActor.run { MLXEmbeddingEngine.shared }
        guard let embedding = await engine.embed(text: text) else { return }

        let vector = EmbeddedVector(
            data: embedding,
            documentId: documentId,
            sourceType: sourceType,
            metadata: metadata
        )

        await MainActor.run {
            let store = EmbeddedVectorStore.shared
            store.addVector(vector)
            store.save()
        }

        documentCount += 1
    }

    // MARK: - Remove from Index

    func removeFromIndex(documentId: String) async {
        await MainActor.run {
            let store = EmbeddedVectorStore.shared
            store.removeVectors(forDocumentId: documentId)
            store.save()
        }
        let count = await MainActor.run { EmbeddedVectorStore.shared.count }
        documentCount = count
    }

    func needsReindex() -> Bool {
        let savedVersion = UserDefaults.standard.string(forKey: indexVersionKey)
        return savedVersion != currentVersion || !isIndexed
    }

    private func updateProgress(_ progress: Double) {
        indexProgress = progress
    }
}
