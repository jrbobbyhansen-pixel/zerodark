import Foundation

// MARK: - GGUF Model Loader

/// Load ANY llama.cpp GGUF model
/// Thousands of models on Hugging Face, now on your device

public actor GGUFLoader {
    
    public static let shared = GGUFLoader()
    
    // MARK: - GGUF Format
    
    public struct GGUFHeader {
        public let magic: UInt32           // "GGUF"
        public let version: UInt32
        public let tensorCount: UInt64
        public let metadataKVCount: UInt64
    }
    
    public struct GGUFMetadata {
        public var architecture: String?
        public var quantizationType: String?
        public var contextLength: Int?
        public var embeddingLength: Int?
        public var blockCount: Int?
        public var attentionHeadCount: Int?
        public var vocabSize: Int?
        public var ropeFreqBase: Float?
        public var eos_token_id: Int?
        public var bos_token_id: Int?
    }
    
    public struct GGUFModel {
        public let path: URL
        public let header: GGUFHeader
        public let metadata: GGUFMetadata
        public let sizeMB: Int
        public let quantization: String
        
        public var displayName: String {
            path.deletingPathExtension().lastPathComponent
        }
    }
    
    // MARK: - Loading
    
    /// Load GGUF model from file
    public func load(from path: URL) async throws -> GGUFModel {
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw GGUFError.fileNotFound
        }
        
        let handle = try FileHandle(forReadingFrom: path)
        defer { try? handle.close() }
        
        // Read header
        guard let headerData = try handle.read(upToCount: 24) else {
            throw GGUFError.invalidFormat
        }
        
        let header = try parseHeader(headerData)
        
        // Verify magic
        guard header.magic == 0x46554747 else { // "GGUF" in little endian
            throw GGUFError.invalidMagic
        }
        
        // Parse metadata
        let metadata = try await parseMetadata(handle: handle, count: header.metadataKVCount)
        
        // Get file size
        let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
        let sizeMB = (attributes[.size] as? Int ?? 0) / (1024 * 1024)
        
        return GGUFModel(
            path: path,
            header: header,
            metadata: metadata,
            sizeMB: sizeMB,
            quantization: metadata.quantizationType ?? "unknown"
        )
    }
    
    private func parseHeader(_ data: Data) throws -> GGUFHeader {
        guard data.count >= 24 else {
            throw GGUFError.invalidFormat
        }
        
        return data.withUnsafeBytes { ptr in
            GGUFHeader(
                magic: ptr.load(fromByteOffset: 0, as: UInt32.self),
                version: ptr.load(fromByteOffset: 4, as: UInt32.self),
                tensorCount: ptr.load(fromByteOffset: 8, as: UInt64.self),
                metadataKVCount: ptr.load(fromByteOffset: 16, as: UInt64.self)
            )
        }
    }
    
    private func parseMetadata(handle: FileHandle, count: UInt64) async throws -> GGUFMetadata {
        var metadata = GGUFMetadata()
        
        // Simplified - real implementation would parse all KV pairs
        // For now, extract common fields
        
        metadata.architecture = "llama"
        metadata.contextLength = 4096
        
        return metadata
    }
    
    // MARK: - Model Discovery
    
    /// Find all GGUF files in documents
    public func discoverModels() async -> [GGUFModel] {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelsURL = documentsURL.appendingPathComponent("models")
        
        guard let enumerator = FileManager.default.enumerator(
            at: modelsURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        var models: [GGUFModel] = []
        
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "gguf" {
                if let model = try? await load(from: fileURL) {
                    models.append(model)
                }
            }
        }
        
        return models.sorted { $0.sizeMB < $1.sizeMB }
    }
    
    // MARK: - Download from Hugging Face
    
    /// Download model from Hugging Face
    public func download(
        repo: String,
        filename: String,
        onProgress: @escaping (Float) -> Void
    ) async throws -> URL {
        let url = URL(string: "https://huggingface.co/\(repo)/resolve/main/\(filename)")!
        
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelsURL = documentsURL.appendingPathComponent("models")
        try FileManager.default.createDirectory(at: modelsURL, withIntermediateDirectories: true)
        
        let destinationURL = modelsURL.appendingPathComponent(filename)
        
        // Check if already downloaded
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }
        
        // Download with progress
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)
        
        let expectedLength = response.expectedContentLength
        var downloadedLength: Int64 = 0
        
        let handle = try FileHandle(forWritingTo: destinationURL)
        
        for try await byte in asyncBytes {
            try handle.write(contentsOf: [byte])
            downloadedLength += 1
            
            if expectedLength > 0 {
                let progress = Float(downloadedLength) / Float(expectedLength)
                onProgress(progress)
            }
        }
        
        try handle.close()
        
        return destinationURL
    }
    
    // MARK: - Popular Models
    
    public static let popularModels: [(repo: String, file: String, description: String)] = [
        ("TheBloke/Llama-2-7B-GGUF", "llama-2-7b.Q4_K_M.gguf", "Llama 2 7B Q4"),
        ("TheBloke/Mistral-7B-v0.1-GGUF", "mistral-7b-v0.1.Q4_K_M.gguf", "Mistral 7B Q4"),
        ("TheBloke/CodeLlama-7B-GGUF", "codellama-7b.Q4_K_M.gguf", "CodeLlama 7B Q4"),
        ("TheBloke/Phi-2-GGUF", "phi-2.Q4_K_M.gguf", "Phi-2 Q4"),
        ("TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF", "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf", "TinyLlama 1.1B"),
    ]
    
    // MARK: - Errors
    
    public enum GGUFError: Error {
        case fileNotFound
        case invalidFormat
        case invalidMagic
        case unsupportedVersion
        case downloadFailed
    }
}
