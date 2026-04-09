import Foundation
import SwiftUI

// MARK: - DocumentIndexer

class DocumentIndexer: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var indexedDocuments: [String] = []
    
    private let vectorStore: DocumentVectorStore
    private let chunker: Chunker
    
    init(vectorStore: DocumentVectorStore, chunker: Chunker) {
        self.vectorStore = vectorStore
        self.chunker = chunker
    }
    
    func indexDocuments(at urls: [URL]) async {
        for (index, url) in urls.enumerated() {
            let chunks = await chunker.chunkDocument(at: url)
            for chunk in chunks {
                await vectorStore.store(chunk: chunk)
            }
            progress = Double(index + 1) / Double(urls.count)
            indexedDocuments.append(url.lastPathComponent)
        }
        progress = 1.0
    }
    
    func updateDocument(at url: URL) async {
        let chunks = await chunker.chunkDocument(at: url)
        for chunk in chunks {
            await vectorStore.update(chunk: chunk)
        }
    }
}

// MARK: - VectorStore

actor DocumentVectorStore {
    private var store: [String: [Chunk]] = [:]
    
    func store(chunk: Chunk) async {
        let key = chunk.documentID
        if store[key] == nil {
            store[key] = []
        }
        store[key]?.append(chunk)
    }
    
    func update(chunk: Chunk) async {
        let key = chunk.documentID
        if var chunks = store[key] {
            if let index = chunks.firstIndex(where: { $0.id == chunk.id }) {
                chunks[index] = chunk
            } else {
                chunks.append(chunk)
            }
            store[key] = chunks
        } else {
            store[key] = [chunk]
        }
    }
}

// MARK: - Chunker

actor Chunker {
    func chunkDocument(at url: URL) async -> [Chunk] {
        let text = try! String(contentsOf: url)
        let chunks = text.split(separator: "\n").map { Chunk(id: UUID().uuidString, documentID: url.lastPathComponent, content: String($0)) }
        return chunks
    }
}

// MARK: - Chunk

struct Chunk: Identifiable {
    let id: String
    let documentID: String
    let content: String
}