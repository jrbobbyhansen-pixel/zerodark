// FastLibraryService.swift — Blazing Fast PDF Search with BM25

import Foundation
import PDFKit
import Combine

// MARK: - Models

struct LibraryDocument: Identifiable, Codable {
    let id: String
    let title: String
    let filename: String
    let pageCount: Int
    let dateAdded: Date
    var isIndexed: Bool
}

struct TextChunk: Codable, Identifiable {
    let id: String
    let docId: String
    let docTitle: String
    let page: Int
    let content: String
    var score: Float = 0
}

// MARK: - Fast Library Service

@MainActor
final class FastLibraryService: ObservableObject {
    static let shared = FastLibraryService()

    // MARK: - Published State
    @Published var documents: [LibraryDocument] = []
    @Published var searchResults: [TextChunk] = []
    @Published var isIndexing = false
    @Published var indexProgress: Double = 0
    @Published var isReady = false

    // MARK: - Search Data
    private var chunks: [TextChunk] = []
    private var invertedIndex: [String: [Int]] = [:]  // term → chunk indices
    private var chunkLengths: [Int] = []
    private var avgLength: Double = 500

    // MARK: - File Paths
    private let libraryDir: URL
    private let cacheDir: URL
    private let chunksFile: URL
    private let indexFile: URL
    private let docsFile: URL

    // MARK: - Configuration
    private let chunkSize = 400          // Characters per chunk
    private let chunkOverlap = 50        // Overlap for context
    private let minWordLength = 3        // Skip tiny words

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        libraryDir = docs.appendingPathComponent("Library", isDirectory: true)
        cacheDir = docs.appendingPathComponent("LibraryCache", isDirectory: true)
        chunksFile = cacheDir.appendingPathComponent("chunks.json")
        indexFile = cacheDir.appendingPathComponent("inverted_index.json")
        docsFile = cacheDir.appendingPathComponent("documents.json")

        try? FileManager.default.createDirectory(at: libraryDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        // Load cached data
        loadCache()
    }

    // MARK: - Public API

    /// Initialize library - call on app launch
    func initialize() async {
        // Scan for new PDFs
        scanLibrary()

        // Check if we need to index
        let unindexed = documents.filter { !$0.isIndexed }
        if !unindexed.isEmpty {
            await indexDocuments(unindexed)
        }

        // Build inverted index if not loaded
        if invertedIndex.isEmpty && !chunks.isEmpty {
            buildInvertedIndex()
        }

        isReady = true
    }

    /// Fast search - returns results in <50ms
    func search(_ query: String, limit: Int = 10) -> [TextChunk] {
        let startTime = CFAbsoluteTimeGetCurrent()

        guard !query.isEmpty, !chunks.isEmpty else { return [] }

        let terms = tokenize(query)
        guard !terms.isEmpty else { return [] }

        // BM25 parameters (tuned for short documents)
        let k1 = 1.2
        let b = 0.75
        let N = Double(chunks.count)

        // Score accumulator
        var scores: [Int: Double] = [:]

        for term in terms {
            guard let indices = invertedIndex[term], !indices.isEmpty else { continue }

            let n = Double(indices.count)
            let idf = log((N - n + 0.5) / (n + 0.5) + 1.0)

            for idx in indices {
                guard idx < chunks.count, idx < chunkLengths.count else { continue }

                let docLen = Double(chunkLengths[idx])
                let tf = termFrequency(term, in: chunks[idx].content)

                let score = idf * ((tf * (k1 + 1)) / (tf + k1 * (1 - b + b * docLen / avgLength)))
                scores[idx, default: 0] += score
            }
        }

        // Get top results
        let results = scores
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .compactMap { idx, score -> TextChunk? in
                guard idx < chunks.count else { return nil }
                var chunk = chunks[idx]
                chunk.score = Float(score)
                return chunk
            }

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("[FastLibrary] Search '\(query)' returned \(results.count) results in \(String(format: "%.1f", elapsed))ms")

        return Array(results)
    }

    /// Perform search and update published results
    func performSearch(_ query: String) {
        searchResults = search(query)
    }

    /// Get document by ID
    func document(id: String) -> LibraryDocument? {
        documents.first { $0.id == id }
    }

    /// Get PDF URL for document
    func pdfURL(for doc: LibraryDocument) -> URL? {
        let url = libraryDir.appendingPathComponent(doc.filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Indexing

    /// Scan library directory for PDFs
    func scanLibrary() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: libraryDir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return }

        let pdfFiles = files.filter { $0.pathExtension.lowercased() == "pdf" }

        for fileURL in pdfFiles {
            let filename = fileURL.lastPathComponent

            // Skip if already tracked
            if documents.contains(where: { $0.filename == filename }) {
                continue
            }

            // Get page count
            var pageCount = 0
            if let doc = PDFDocument(url: fileURL) {
                pageCount = doc.pageCount
            }

            let doc = LibraryDocument(
                id: UUID().uuidString,
                title: cleanTitle(filename),
                filename: filename,
                pageCount: pageCount,
                dateAdded: Date(),
                isIndexed: false
            )

            documents.append(doc)
        }

        saveDocuments()
    }

    /// Index documents (extract text, chunk, build index)
    private func indexDocuments(_ docs: [LibraryDocument]) async {
        isIndexing = true
        indexProgress = 0

        let total = docs.count
        var processed = 0

        for doc in docs {
            guard let url = pdfURL(for: doc),
                  let pdf = PDFDocument(url: url) else {
                processed += 1
                continue
            }

            // Extract text from all pages
            var fullText = ""
            for i in 0..<pdf.pageCount {
                if let page = pdf.page(at: i), let text = page.string {
                    fullText += "\n[PAGE:\(i + 1)]\n\(text)"
                }
            }

            // Create chunks
            let docChunks = createChunks(text: fullText, docId: doc.id, docTitle: doc.title)
            chunks.append(contentsOf: docChunks)

            // Mark as indexed
            if let idx = documents.firstIndex(where: { $0.id == doc.id }) {
                documents[idx].isIndexed = true
            }

            processed += 1
            indexProgress = Double(processed) / Double(total)
        }

        // Build inverted index
        buildInvertedIndex()

        // Save everything
        saveChunks()
        saveInvertedIndex()
        saveDocuments()

        isIndexing = false
        indexProgress = 1.0

        print("[FastLibrary] Indexed \(docs.count) documents, \(chunks.count) total chunks")
    }

    /// Create text chunks with page tracking
    private func createChunks(text: String, docId: String, docTitle: String) -> [TextChunk] {
        var result: [TextChunk] = []
        var currentPage = 1
        var position = text.startIndex

        while position < text.endIndex {
            // Check for page marker
            let remaining = String(text[position...])
            if remaining.hasPrefix("[PAGE:") {
                if let endBracket = remaining.firstIndex(of: "]") {
                    let pageStr = remaining[remaining.index(remaining.startIndex, offsetBy: 6)..<endBracket]
                    if let page = Int(pageStr) {
                        currentPage = page
                    }
                    position = text.index(position, offsetBy: text.distance(from: remaining.startIndex, to: endBracket) + 1)
                    continue
                }
            }

            // Get chunk text
            let endOffset = min(chunkSize, text.distance(from: position, to: text.endIndex))
            var endPos = text.index(position, offsetBy: endOffset)

            // Try to break at sentence boundary
            if endPos < text.endIndex {
                let searchStart = text.index(endPos, offsetBy: -min(50, endOffset), limitedBy: position) ?? position
                let range = searchStart..<endPos
                if let periodIdx = text[range].lastIndex(of: ".") {
                    endPos = text.index(after: periodIdx)
                }
            }

            let chunkText = String(text[position..<endPos])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\[PAGE:\\d+\\]", with: "", options: .regularExpression)

            if chunkText.count > 20 {  // Skip tiny chunks
                let chunk = TextChunk(
                    id: "\(docId)_\(result.count)",
                    docId: docId,
                    docTitle: docTitle,
                    page: currentPage,
                    content: chunkText
                )
                result.append(chunk)
            }

            // Move position with overlap
            let moveDistance = max(1, endOffset - chunkOverlap)
            position = text.index(position, offsetBy: min(moveDistance, text.distance(from: position, to: text.endIndex)))
        }

        return result
    }

    /// Build inverted index for O(1) term lookups
    private func buildInvertedIndex() {
        let startTime = CFAbsoluteTimeGetCurrent()

        invertedIndex.removeAll(keepingCapacity: true)
        chunkLengths.removeAll(keepingCapacity: true)

        var totalLength = 0

        for (idx, chunk) in chunks.enumerated() {
            let words = tokenize(chunk.content)
            chunkLengths.append(words.count)
            totalLength += words.count

            for word in Set(words) {
                invertedIndex[word, default: []].append(idx)
            }
        }

        avgLength = chunks.isEmpty ? 500 : Double(totalLength) / Double(chunks.count)

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("[FastLibrary] Built inverted index with \(invertedIndex.count) terms in \(String(format: "%.1f", elapsed))ms")
    }

    // MARK: - Text Processing

    /// Tokenize text into searchable terms
    private func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= minWordLength }
    }

    /// Count term frequency
    private func termFrequency(_ term: String, in text: String) -> Double {
        let lower = text.lowercased()
        var count = 0
        var searchRange = lower.startIndex..<lower.endIndex

        while let range = lower.range(of: term, options: [], range: searchRange) {
            count += 1
            searchRange = range.upperBound..<lower.endIndex
        }

        return Double(count)
    }

    /// Clean filename to title
    private func cleanTitle(_ filename: String) -> String {
        filename
            .replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    // MARK: - Persistence

    private func loadCache() {
        // Load documents
        if let data = try? Data(contentsOf: docsFile),
           let saved = try? JSONDecoder().decode([LibraryDocument].self, from: data) {
            documents = saved
        }

        // Load chunks
        if let data = try? Data(contentsOf: chunksFile),
           let saved = try? JSONDecoder().decode([TextChunk].self, from: data) {
            chunks = saved
            chunkLengths = chunks.map { tokenize($0.content).count }
            avgLength = chunks.isEmpty ? 500 : Double(chunkLengths.reduce(0, +)) / Double(chunks.count)
        }

        // Load inverted index
        if let data = try? Data(contentsOf: indexFile),
           let saved = try? JSONDecoder().decode([String: [Int]].self, from: data) {
            invertedIndex = saved
        }
    }

    private func saveDocuments() {
        if let data = try? JSONEncoder().encode(documents) {
            try? data.write(to: docsFile)
        }
    }

    private func saveChunks() {
        if let data = try? JSONEncoder().encode(chunks) {
            try? data.write(to: chunksFile)
        }
    }

    private func saveInvertedIndex() {
        if let data = try? JSONEncoder().encode(invertedIndex) {
            try? data.write(to: indexFile)
        }
    }
}
