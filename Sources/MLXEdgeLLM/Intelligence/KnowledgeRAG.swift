// KnowledgeRAG.swift — Hybrid BM25 + MLX Vector Search with RRF Fusion
// ZeroDark Intel Tab v6.0

import Foundation
import SwiftUI

// MARK: - Models

struct KnowledgeChunk: Identifiable {
    let id: UUID
    let filename: String
    let title: String
    let category: KnowledgeCategory
    let content: String
    let keywords: [String]
    var bm25Score: Double = 0

    init(id: UUID = UUID(), filename: String, title: String,
         category: KnowledgeCategory, content: String, keywords: [String]) {
        self.id = id
        self.filename = filename
        self.title = title
        self.category = category
        self.content = content
        self.keywords = keywords
    }

    var summary: String {
        content.components(separatedBy: "\n")
            .first { !$0.hasPrefix("#") && !$0.isEmpty }
            .map { String($0.prefix(200)) } ?? String(content.prefix(200))
    }
}

// MARK: - Scored Chunk (hybrid search result)

struct ScoredChunk: Identifiable {
    let id: UUID
    let chunk: KnowledgeChunk
    let score: Double
    let matchType: MatchType

    enum MatchType: String {
        case keyword   // BM25 only
        case semantic  // Vector only
        case hybrid    // Both matched
    }

    init(chunk: KnowledgeChunk, score: Double, matchType: MatchType) {
        self.id = chunk.id
        self.chunk = chunk
        self.score = score
        self.matchType = matchType
    }
}

enum KnowledgeCategory: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case water       = "Water"
    case fire        = "Fire"
    case shelter     = "Shelter"
    case food        = "Food"
    case medical     = "Medical"
    case tactical    = "Tactical"
    case environment = "Environment"
    case intel       = "Intelligence"
    case navigation  = "Navigation"
    case comms       = "Communications"
    case defense     = "Defense"
    case sere        = "SERE"
    case urban       = "Urban"
    case vehicles    = "Vehicles"
    case leadership  = "Leadership"
    case logistics   = "Logistics"
    case tech        = "Technology"

    var icon: String {
        switch self {
        case .water:       return "drop.fill"
        case .fire:        return "flame.fill"
        case .shelter:     return "house.fill"
        case .food:        return "leaf.fill"
        case .medical:     return "cross.fill"
        case .tactical:    return "shield.fill"
        case .environment: return "cloud.sun.fill"
        case .intel:       return "eye.slash.fill"
        case .navigation:  return "location.north.line.fill"
        case .comms:       return "antenna.radiowaves.left.and.right"
        case .defense:     return "exclamationmark.shield.fill"
        case .sere:        return "figure.walk"
        case .urban:       return "building.2.fill"
        case .vehicles:    return "car.fill"
        case .leadership:  return "person.3.fill"
        case .logistics:   return "shippingbox.fill"
        case .tech:        return "cpu.fill"
        }
    }

    var zdColor: Color {
        switch self {
        case .water:       return ZDDesign.skyBlue
        case .fire:        return ZDDesign.sunsetOrange
        case .shelter:     return ZDDesign.earthBrown
        case .food:        return ZDDesign.forestGreen
        case .medical:     return ZDDesign.signalRed
        case .tactical:    return ZDDesign.safetyYellow
        case .environment: return ZDDesign.darkSage
        case .intel:       return ZDDesign.warmGray
        case .navigation:  return ZDDesign.successGreen
        case .comms:       return ZDDesign.cyanAccent
        case .defense:     return ZDDesign.signalRed
        case .sere:        return ZDDesign.darkSage
        case .urban:       return ZDDesign.mediumGray
        case .vehicles:    return ZDDesign.earthBrown
        case .leadership:  return ZDDesign.safetyYellow
        case .logistics:   return ZDDesign.warmGray
        case .tech:        return ZDDesign.skyBlue
        }
    }
}

// MARK: - Hybrid BM25 + Vector RAG Engine

@MainActor
final class KnowledgeRAG: ObservableObject {
    static let shared = KnowledgeRAG()

    @Published var isLoaded = false
    @Published var fileCount = 0
    @Published var chunkCount = 0
    @Published var isIndexed = false
    @Published var indexProgress: Double = 0.0

    private var chunks: [KnowledgeChunk] = []
    private let vectorStore = EmbeddedVectorStore.shared
    private let embeddingEngine = MLXEmbeddingEngine.shared

    // BM25 parameters
    private let k1: Double = 1.5
    private let b: Double = 0.75

    private let stopWords: Set<String> = [
        "the","and","for","with","this","that","from","are","was","will",
        "can","not","but","you","your","have","they","their","when","then",
        "into","over","each","only","also","both","been","more","very"
    ]

    private init() {
        Task { await loadKnowledgeBase() }
    }

    // MARK: - Loading

    func loadKnowledgeBase() async {
        let fm = FileManager.default

        let searchURL: URL
        if let knowledgeURL = Bundle.main.url(forResource: "Knowledge", withExtension: nil) {
            searchURL = knowledgeURL
        } else if let bundleURL = Bundle.main.resourceURL {
            searchURL = bundleURL
        } else {
            return
        }

        guard let enumerator = fm.enumerator(at: searchURL, includingPropertiesForKeys: nil) else { return }

        var loaded: [KnowledgeChunk] = []
        var files = 0
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "md" else { continue }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            files += 1
            let filename = fileURL.lastPathComponent
            let title = content.components(separatedBy: "\n")
                .first(where: { $0.hasPrefix("# ") })
                .map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) } ?? filename
            let category = inferCategory(from: fileURL.pathComponents)
            let keywords = topKeywords(in: content)
            for segment in chunkText(content, maxWords: 450) {
                loaded.append(KnowledgeChunk(
                    filename: filename, title: title,
                    category: category, content: segment, keywords: keywords
                ))
            }
        }

        chunks = loaded
        chunkCount = loaded.count
        fileCount = files
        isLoaded = true

        // Build vector index if MLX server is available
        await buildVectorIndex()
    }

    // MARK: - Vector Index Building

    func buildVectorIndex() async {
        guard !chunks.isEmpty else { return }

        // Check if already indexed
        let existingCount = vectorStore.count(for: .knowledgeBase)
        if existingCount == chunks.count {
            isIndexed = true
            indexProgress = 1.0
            return
        }

        // Clear old knowledge base vectors
        vectorStore.removeVectors(forSourceType: .knowledgeBase)

        let texts = chunks.map { $0.content }
        guard let embeddings = await embeddingEngine.batchEmbed(
            texts: texts,
            batchSize: 32,
            onProgress: { [weak self] progress in
                self?.indexProgress = progress
            }
        ) else {
            // MLX server unavailable — degrade to BM25-only
            isIndexed = false
            return
        }

        // Store embeddings linked to chunk IDs
        var newVectors: [EmbeddedVector] = []
        for (i, chunk) in chunks.enumerated() {
            newVectors.append(EmbeddedVector(
                data: embeddings[i],
                documentId: chunk.id.uuidString,
                sourceType: .knowledgeBase,
                metadata: [
                    "title": chunk.title,
                    "category": chunk.category.rawValue,
                    "filename": chunk.filename
                ]
            ))
        }
        vectorStore.addVectors(newVectors)
        vectorStore.save()

        isIndexed = true
        indexProgress = 1.0
    }

    // MARK: - BM25 Search

    func search(query: String, topK: Int = 5) -> [KnowledgeChunk] {
        let terms = tokenize(query)
        guard !terms.isEmpty, !chunks.isEmpty else { return [] }
        let avgLen = Double(chunks.map { tokenize($0.content).count }.reduce(0, +)) / Double(chunks.count)
        return chunks
            .map { c -> KnowledgeChunk in
                var mc = c
                mc.bm25Score = bm25Score(terms: terms, doc: c.content, avgLen: avgLen)
                return mc
            }
            .sorted { $0.bm25Score > $1.bm25Score }
            .filter { $0.bm25Score > 0 }
            .prefix(topK)
            .map { $0 }
    }

    private func bm25Score(terms: [String], doc: String, avgLen: Double) -> Double {
        let docTerms = tokenize(doc)
        let docLen = Double(docTerms.count)
        let freq = Dictionary(grouping: docTerms, by: { $0 }).mapValues { Double($0.count) }
        let N = Double(chunks.count)
        return terms.reduce(0.0) { acc, term in
            let tf = freq[term] ?? 0
            let df = Double(chunks.filter { tokenize($0.content).contains(term) }.count)
            guard df > 0 else { return acc }
            let idf = log((N - df + 0.5) / (df + 0.5) + 1.0)
            let tfNorm = tf * (k1 + 1.0) / (tf + k1 * (1.0 - b + b * docLen / max(avgLen, 1.0)))
            return acc + idf * tfNorm
        }
    }

    /// Synchronous context builder (BM25 only)
    func buildContext(for query: String) -> String {
        let results = search(query: query, topK: 5)
        guard !results.isEmpty else { return "" }
        var context = "RELEVANT KNOWLEDGE BASE CONTENT:\n\n"
        var words = 0
        for chunk in results {
            let w = chunk.content.split(separator: " ").count
            if words + w > 600 { break }
            context += "[\(chunk.title)]\n\(chunk.content)\n\n"
            words += w
        }
        return context
    }

    func chunks(for category: KnowledgeCategory) -> [KnowledgeChunk] {
        chunks.filter { $0.category == category }
    }

    /// Access all chunks (for multi-modal indexing)
    var allChunks: [KnowledgeChunk] { chunks }

    // MARK: - Helpers

    private func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }

    private func topKeywords(in text: String) -> [String] {
        Array(tokenize(text)
            .reduce(into: [:]) { $0[$1, default: 0] += 1 }
            .sorted { $0.value > $1.value }
            .prefix(15).map(\.key))
    }

    private func chunkText(_ text: String, maxWords: Int) -> [String] {
        let paragraphs = text.components(separatedBy: "\n\n")
        var result: [String] = []
        var current = ""
        var count = 0
        for para in paragraphs {
            let w = para.split(separator: " ").count
            if count + w > maxWords, !current.isEmpty {
                result.append(current)
                current = para
                count = w
            } else {
                current = current.isEmpty ? para : current + "\n\n" + para
                count += w
            }
        }
        if !current.isEmpty { result.append(current) }
        return result.isEmpty ? [text] : result
    }

    private func inferCategory(from pathComponents: [String]) -> KnowledgeCategory {
        let path = pathComponents.joined(separator: "/").lowercased()
        let filename = pathComponents.last?.lowercased() ?? ""
        let searchText = path + " " + filename
        if searchText.contains("water") || searchText.contains("hydrat") || searchText.contains("purif") { return .water }
        if searchText.contains("fire") || searchText.contains("ignit") { return .fire }
        if searchText.contains("shelter") || searchText.contains("bivouac") { return .shelter }
        if searchText.contains("food") || searchText.contains("forag") || searchText.contains("edible") { return .food }
        if searchText.contains("medical") || searchText.contains("first-aid") || searchText.contains("tourniquet") || searchText.contains("tccc") { return .medical }
        if searchText.contains("tactical") || searchText.contains("combat") || searchText.contains("patrol") { return .tactical }
        if searchText.contains("environment") || searchText.contains("desert") || searchText.contains("cold") || searchText.contains("weather") || searchText.contains("terrain") { return .environment }
        if searchText.contains("intel") || searchText.contains("opsec") || searchText.contains("sigint") { return .intel }
        if searchText.contains("navigation") || searchText.contains("land-nav") || searchText.contains("compass") || searchText.contains("mgrs") { return .navigation }
        if searchText.contains("comms") || searchText.contains("radio") || searchText.contains("signal") { return .comms }
        if searchText.contains("defense") || searchText.contains("perimeter") { return .defense }
        if searchText.contains("sere") || searchText.contains("evasion") || searchText.contains("escape") { return .sere }
        if searchText.contains("urban") || searchText.contains("mout") { return .urban }
        if searchText.contains("vehicles") || searchText.contains("convoy") { return .vehicles }
        if searchText.contains("leadership") || searchText.contains("command") { return .leadership }
        if searchText.contains("logistics") || searchText.contains("supply") { return .logistics }
        if searchText.contains("tech") || searchText.contains("cyber") { return .tech }
        return .tactical
    }
}

// MARK: - KnowledgeBaseView

struct KnowledgeBaseView: View {
    @ObservedObject private var rag = KnowledgeRAG.shared
    @State private var query = ""
    @State private var results: [KnowledgeChunk] = []
    @State private var selectedCategory: KnowledgeCategory? = nil
    @State private var selectedChunk: KnowledgeChunk? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    searchBar
                    categoryFilter
                    Divider().background(ZDDesign.mediumGray.opacity(0.3))
                    if !results.isEmpty {
                        resultsList
                    } else if !query.isEmpty {
                        noResultsView
                    } else {
                        loadingOrIdleView
                    }
                }
            }
            .navigationTitle("Knowledge Base")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    VStack(spacing: 0) {
                        Text("\(rag.chunkCount) chunks").font(.caption2).foregroundColor(.secondary)
                        Text("\(rag.fileCount) files").font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            .sheet(item: $selectedChunk) { chunk in
                KnowledgeChunkDetailView(chunk: chunk)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundColor(ZDDesign.mediumGray)
            TextField("Search tactical knowledge…", text: $query)
                .foregroundColor(ZDDesign.pureWhite)
                .submitLabel(.search)
                .onSubmit { runSearch() }
                .onChange(of: query) { _, _ in runSearch() }
            if !query.isEmpty {
                Button { query = ""; results = [] } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(ZDDesign.mediumGray)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(ZDDesign.darkCard)
    }

    // MARK: Category Filter

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(nil, label: "All")
                ForEach(KnowledgeCategory.allCases) { cat in
                    categoryChip(cat, label: cat.rawValue)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func categoryChip(_ cat: KnowledgeCategory?, label: String) -> some View {
        Button {
            selectedCategory = cat
            runSearch()
        } label: {
            HStack(spacing: 4) {
                if let cat = cat {
                    Image(systemName: cat.icon).font(.caption2)
                }
                Text(label).font(.caption.bold())
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(selectedCategory == cat ? ZDDesign.cyanAccent : ZDDesign.darkCard)
            .foregroundColor(selectedCategory == cat ? .black : ZDDesign.mediumGray)
            .cornerRadius(16)
        }
    }

    // MARK: Results

    private var resultsList: some View {
        List(results) { chunk in
            Button { selectedChunk = chunk } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: chunk.category.icon)
                            .font(.caption).foregroundColor(ZDDesign.cyanAccent)
                        Text(chunk.title).font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite)
                        Spacer()
                        Text(chunk.category.rawValue).font(.caption2).foregroundColor(.secondary)
                    }
                    Text(chunk.summary)
                        .font(.caption).foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .listRowBackground(ZDDesign.darkCard)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: Empty / Loading

    private var noResultsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.questionmark").font(.largeTitle).foregroundColor(.secondary)
            Text("No results for \"\(query)\"").font(.subheadline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingOrIdleView: some View {
        VStack(spacing: 12) {
            if !rag.isLoaded {
                ProgressView(value: rag.indexProgress)
                    .tint(ZDDesign.cyanAccent)
                    .padding(.horizontal, 40)
                Text("Loading knowledge base…").font(.subheadline).foregroundColor(.secondary)
            } else {
                Image(systemName: "text.book.closed").font(.largeTitle).foregroundColor(.secondary)
                Text("Search tactical knowledge").font(.subheadline).foregroundColor(.secondary)
                Text("\(rag.chunkCount) chunks from \(rag.fileCount) field manuals")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func runSearch() {
        if query.isEmpty {
            results = []
            return
        }
        var r = rag.search(query: query, topK: 20)
        if let cat = selectedCategory {
            r = r.filter { $0.category == cat }
        }
        results = r
    }
}

// MARK: - KnowledgeChunkDetailView

struct KnowledgeChunkDetailView: View {
    let chunk: KnowledgeChunk
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: chunk.category.icon).foregroundColor(ZDDesign.cyanAccent)
                            Text(chunk.category.rawValue).font(.caption.bold()).foregroundColor(.secondary)
                            Spacer()
                        }
                        Text(chunk.content)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(ZDDesign.pureWhite)
                            .textSelection(.enabled)
                        if !chunk.keywords.isEmpty {
                            Divider().background(ZDDesign.mediumGray.opacity(0.3))
                            Text("Keywords: " + chunk.keywords.joined(separator: ", "))
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(chunk.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}
