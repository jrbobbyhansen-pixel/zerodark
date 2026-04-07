// EmbeddingEngine.swift — MLX On-Device Embedding Engine
// ZeroDark Intel Tab v6.0

import Foundation
import Accelerate

// MARK: - MLX Embedding Engine

@MainActor
final class MLXEmbeddingEngine: ObservableObject {
    static let shared = MLXEmbeddingEngine()

    @Published var isReady: Bool = false
    @Published var isProcessing: Bool = false

    private let serverURL = "http://127.0.0.1:8800"
    private var cache: [String: [Float]] = [:]
    private let maxCacheSize = 2000

    private init() {
        Task { await checkServer() }
    }

    // MARK: - Server Health

    func checkServer() async {
        guard let url = URL(string: "\(serverURL)/health") else {
            isReady = false
            return
        }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            isReady = (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            isReady = false
        }
    }

    // MARK: - Single Embedding

    func embed(text: String) async -> [Float]? {
        let key = text.prefix(200).lowercased()
        if let cached = cache[String(key)] { return cached }

        guard let embedding = await fetchEmbeddings(texts: [text])?.first else {
            return nil
        }
        cacheEmbedding(key: String(key), value: embedding)
        return embedding
    }

    // MARK: - Batch Embedding

    func batchEmbed(texts: [String], batchSize: Int = 32,
                    onProgress: @escaping @MainActor (Double) -> Void) async -> [[Float]]? {
        isProcessing = true
        defer { isProcessing = false }

        var allEmbeddings: [[Float]] = []
        let total = texts.count

        for batchStart in stride(from: 0, to: total, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, total)
            let batch = Array(texts[batchStart..<batchEnd])

            // Check cache first
            var uncachedTexts: [String] = []
            var uncachedIndices: [Int] = []
            var batchResults: [[Float]?] = Array(repeating: nil, count: batch.count)

            for (i, text) in batch.enumerated() {
                let key = String(text.prefix(200).lowercased())
                if let cached = cache[key] {
                    batchResults[i] = cached
                } else {
                    uncachedTexts.append(text)
                    uncachedIndices.append(i)
                }
            }

            // Fetch uncached embeddings
            if !uncachedTexts.isEmpty {
                guard let fetched = await fetchEmbeddings(texts: uncachedTexts) else {
                    return nil
                }
                for (j, idx) in uncachedIndices.enumerated() {
                    batchResults[idx] = fetched[j]
                    let key = String(batch[idx].prefix(200).lowercased())
                    cacheEmbedding(key: key, value: fetched[j])
                }
            }

            allEmbeddings.append(contentsOf: batchResults.compactMap { $0 })

            await onProgress(Double(batchEnd) / Double(total))
        }

        return allEmbeddings.count == total ? allEmbeddings : nil
    }

    // MARK: - Similarity

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

    // MARK: - Network

    private func fetchEmbeddings(texts: [String]) async -> [[Float]]? {
        guard let url = URL(string: "\(serverURL)/v1/embeddings") else { return nil }

        let body: [String: Any] = [
            "input": texts,
            "model": "all-MiniLM-L6-v2"
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                isReady = false
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArray = json["data"] as? [[String: Any]] else {
                return nil
            }

            let embeddings = dataArray
                .sorted { ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0) }
                .compactMap { item -> [Float]? in
                    guard let embedding = item["embedding"] as? [Double] else { return nil }
                    return embedding.map { Float($0) }
                }

            isReady = true
            return embeddings.count == texts.count ? embeddings : nil
        } catch {
            isReady = false
            return nil
        }
    }

    // MARK: - Cache Management

    private func cacheEmbedding(key: String, value: [Float]) {
        if cache.count >= maxCacheSize {
            // Evict oldest entries (simple FIFO via random removal)
            let keysToRemove = Array(cache.keys.prefix(maxCacheSize / 4))
            for k in keysToRemove { cache.removeValue(forKey: k) }
        }
        cache[key] = value
    }

    func clearCache() {
        cache.removeAll()
    }
}
