// ModelURLs.swift — CDN locations and local destinations for downloadable AI models
// Update CDN URLs before App Store submission

import Foundation

enum ModelURLs {
    // MARK: - CDN URLs
    // Replace these with your actual Cloudflare R2 / S3 bucket URLs before shipping.
    // Models must be hosted as publicly downloadable files.

    /// Embedding model — all-MiniLM-L6-v2 converted to CoreML (.mlpackage zipped)
    static let embeddingModelCDN = URL(string: "https://cdn.zerodark.app/models/v1/all-minilm-l6-v2.mlpackage.zip")!

    /// Vision model — moondream2 q4 converted to CoreML (.mlpackage zipped)
    static let visionModelCDN = URL(string: "https://cdn.zerodark.app/models/v1/moondream2-q4.mlpackage.zip")!

    // MARK: - Expected file sizes (for progress estimation)
    static let embeddingModelBytes: Int64 = 22_000_000       //  ~22 MB
    static let visionModelBytes: Int64    = 1_700_000_000    // ~1.7 GB

    // MARK: - SHA-256 checksums (set after hosting the actual files)
    static let embeddingModelSHA256 = ""   // fill in before shipping
    static let visionModelSHA256    = ""   // fill in before shipping

    // MARK: - Local destinations
    static var modelsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models", isDirectory: true)
    }

    static var embeddingModelDir: URL {
        modelsDirectory.appendingPathComponent("embeddings", isDirectory: true)
    }

    static var embeddingModelPath: URL {
        embeddingModelDir.appendingPathComponent("all-minilm-l6-v2.mlpackage")
    }

    static var visionModelDir: URL {
        modelsDirectory.appendingPathComponent("vision", isDirectory: true)
    }

    static var visionModelPath: URL {
        visionModelDir.appendingPathComponent("moondream2-q4.mlpackage")
    }

    // MARK: - Helpers
    static func createModelDirectories() {
        [modelsDirectory, embeddingModelDir, visionModelDir].forEach {
            try? FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        }
    }
}
