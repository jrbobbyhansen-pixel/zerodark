// VectorStore.swift — Vector Storage with Cosine Similarity Search
// ZeroDark Intel Tab v6.0

import Foundation
import Accelerate

// MARK: - Legacy Vector (backward compat)

struct Vector: Codable, Identifiable {
    let id: UUID
    let data: [Double]

    init(id: UUID = UUID(), data: [Double]) {
        self.id = id
        self.data = data
    }

    func distance(to other: Vector) -> Double {
        guard data.count == other.data.count else { return .greatestFiniteMagnitude }
        return sqrt(data.enumerated().map { pow($0.element - other.data[$0.offset], 2) }.reduce(0, +))
    }
}

// MARK: - Embedded Vector (v6 — Float + metadata)

struct EmbeddedVector: Codable, Identifiable {
    let id: UUID
    let data: [Float]
    let documentId: String
    let sourceType: SourceType
    let metadata: [String: String]

    enum SourceType: String, Codable, CaseIterable, Hashable {
        case knowledgeBase
        case tacticalCorpus
        case lessonLearned
        case photoIntel
    }

    init(id: UUID = UUID(), data: [Float], documentId: String,
         sourceType: SourceType, metadata: [String: String] = [:]) {
        self.id = id
        self.data = data
        self.documentId = documentId
        self.sourceType = sourceType
        self.metadata = metadata
    }

    func cosineSimilarity(to query: [Float]) -> Float {
        MLXEmbeddingEngine.cosineSimilarity(data, query)
    }
}

// MARK: - Embedded Vector Store

@MainActor
final class EmbeddedVectorStore: ObservableObject {
    static let shared = EmbeddedVectorStore()

    @Published private(set) var vectors: [EmbeddedVector] = []
    @Published var isLoaded: Bool = false

    private let fileManager = FileManager.default
    private let fileName = "embedded_vectors.json"

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent(fileName)
    }

    private init() {
        loadVectors()
    }

    // MARK: - CRUD

    func addVector(_ vector: EmbeddedVector) {
        vectors.append(vector)
    }

    func addVectors(_ newVectors: [EmbeddedVector]) {
        vectors.append(contentsOf: newVectors)
    }

    func removeVectors(forDocumentId documentId: String) {
        vectors.removeAll { $0.documentId == documentId }
    }

    func removeVectors(forSourceType sourceType: EmbeddedVector.SourceType) {
        vectors.removeAll { $0.sourceType == sourceType }
    }

    func clear() {
        vectors.removeAll()
    }

    // MARK: - Similarity Search

    func searchBySimilarity(query: [Float], topK: Int = 5,
                            sourceFilter: EmbeddedVector.SourceType? = nil) -> [(EmbeddedVector, Float)] {
        let candidates: [EmbeddedVector]
        if let filter = sourceFilter {
            candidates = vectors.filter { $0.sourceType == filter }
        } else {
            candidates = vectors
        }

        guard !candidates.isEmpty else { return [] }

        // Brute-force cosine scan — fast enough for <10K vectors with Accelerate
        return candidates
            .map { ($0, $0.cosineSimilarity(to: query)) }
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map { $0 }
    }

    // MARK: - Persistence

    func save() {
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(vectors)
            try data.write(to: fileURL)
        } catch {
            print("[VectorStore] Failed to save: \(error)")
        }
    }

    func loadVectors() {
        let decoder = JSONDecoder()
        guard fileManager.fileExists(atPath: fileURL.path) else {
            isLoaded = true
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            vectors = try decoder.decode([EmbeddedVector].self, from: data)
        } catch {
            print("[VectorStore] Failed to load: \(error)")
        }
        isLoaded = true
    }

    // MARK: - Stats

    var count: Int { vectors.count }

    func count(for sourceType: EmbeddedVector.SourceType) -> Int {
        vectors.filter { $0.sourceType == sourceType }.count
    }
}

// MARK: - Legacy VectorStore (backward compat)

class VectorStore: ObservableObject {
    @Published private(set) var vectors: [Vector] = []
    private let fileManager = FileManager.default
    private let directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private let fileName = "vectors.json"

    init() {
        loadVectors()
    }

    func addVector(_ vector: Vector) {
        vectors.append(vector)
        saveVectors()
    }

    func updateVector(at index: Int, with vector: Vector) {
        guard index < vectors.count else { return }
        vectors[index] = vector
        saveVectors()
    }

    func deleteVector(at index: Int) {
        guard index < vectors.count else { return }
        vectors.remove(at: index)
        saveVectors()
    }

    func searchVectors(bySimilarity to: Vector, filter: (Vector) -> Bool) -> [Vector] {
        vectors.filter(filter).sorted { $0.distance(to: to) < $1.distance(to: to) }
    }

    private func saveVectors() {
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(vectors)
            let fileURL = directoryURL.appendingPathComponent(fileName)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save vectors: \(error)")
        }
    }

    private func loadVectors() {
        let decoder = JSONDecoder()
        let fileURL = directoryURL.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                vectors = try decoder.decode([Vector].self, from: data)
            } catch {
                print("Failed to load vectors: \(error)")
            }
        }
    }
}
