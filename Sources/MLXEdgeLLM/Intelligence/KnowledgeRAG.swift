import Foundation
import SwiftUI

// MARK: - Models

struct KnowledgeChunk: Identifiable {
    let id = UUID()
    let filename: String
    let title: String
    let category: KnowledgeCategory
    let content: String
    let keywords: [String]
    var bm25Score: Double = 0

    var summary: String {
        content.components(separatedBy: "\n")
            .first { !$0.hasPrefix("#") && !$0.isEmpty }
            .map { String($0.prefix(200)) } ?? String(content.prefix(200))
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

// MARK: - BM25 RAG Engine

@MainActor
final class KnowledgeRAG: ObservableObject {
    static let shared = KnowledgeRAG()

    @Published var isLoaded = false
    @Published var fileCount = 0
    @Published var chunkCount = 0

    private var chunks: [KnowledgeChunk] = []

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

    func loadKnowledgeBase() async {
        let fm = FileManager.default
        
        // Try Knowledge folder first, then fall back to bundle root
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

    /// Build context string for text LLM prompt
    func buildContext(for query: String, maxWords: Int = 600) -> String {
        let results = search(query: query, topK: 5)
        guard !results.isEmpty else { return "" }
        var context = "RELEVANT KNOWLEDGE BASE CONTENT:\n\n"
        var words = 0
        for chunk in results {
            let w = chunk.content.split(separator: " ").count
            if words + w > maxWords { break }
            context += "[\(chunk.title)]\n\(chunk.content)\n\n"
            words += w
        }
        return context
    }

    func chunks(for category: KnowledgeCategory) -> [KnowledgeChunk] {
        chunks.filter { $0.category == category }
    }

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
        // Check both path AND filename for category keywords (handles flattened bundles)
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
