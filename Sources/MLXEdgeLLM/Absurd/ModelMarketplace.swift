// ModelMarketplace.swift
// Download community models, share your fine-tunes
// ABSURD MODE

import Foundation

// MARK: - Model Marketplace

public actor ModelMarketplace {
    
    public static let shared = ModelMarketplace()
    
    // MARK: - Types
    
    public struct MarketplaceModel: Codable, Identifiable, Sendable {
        public let id: String
        public let name: String
        public let description: String
        public let author: String
        public let category: ModelCategory
        public let baseModel: String
        public let sizeBytes: Int64
        public let downloads: Int
        public let rating: Float
        public let ratingCount: Int
        public let tags: [String]
        public let createdAt: Date
        public let updatedAt: Date
        public let downloadURL: URL?
        public let previewPrompt: String?
        
        public var sizeFormatted: String {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return formatter.string(fromByteCount: sizeBytes)
        }
    }
    
    public enum ModelCategory: String, Codable, CaseIterable, Sendable {
        case general = "General"
        case coding = "Coding"
        case creative = "Creative Writing"
        case roleplay = "Roleplay"
        case assistant = "Assistant"
        case medical = "Medical"
        case legal = "Legal"
        case science = "Science"
        case language = "Language"
        case uncensored = "Uncensored"
        case custom = "Custom"
    }
    
    public struct InstalledModel: Codable, Identifiable, Sendable {
        public let id: String
        public let marketplaceId: String
        public let name: String
        public let localPath: URL
        public let installedAt: Date
        public var lastUsed: Date?
        public var useCount: Int
    }
    
    // MARK: - Featured Models (Simulated Catalog)
    
    private let featuredModels: [MarketplaceModel] = [
        MarketplaceModel(
            id: "coder-supreme-8b",
            name: "Coder Supreme 8B",
            description: "Fine-tuned for Swift, Python, and TypeScript. Excellent at iOS development.",
            author: "ZeroDark Labs",
            category: .coding,
            baseModel: "Qwen2.5-Coder-8B",
            sizeBytes: 4_500_000_000,
            downloads: 12500,
            rating: 4.8,
            ratingCount: 342,
            tags: ["swift", "ios", "python", "coding"],
            createdAt: Date().addingTimeInterval(-86400 * 30),
            updatedAt: Date().addingTimeInterval(-86400 * 2),
            downloadURL: URL(string: "https://huggingface.co/zerodark/coder-supreme-8b"),
            previewPrompt: "Write a SwiftUI view for a login screen"
        ),
        MarketplaceModel(
            id: "storyteller-14b",
            name: "Storyteller 14B",
            description: "Creative writing powerhouse. Novels, scripts, poetry.",
            author: "Creative AI Co",
            category: .creative,
            baseModel: "Qwen2.5-14B",
            sizeBytes: 7_800_000_000,
            downloads: 8900,
            rating: 4.6,
            ratingCount: 215,
            tags: ["creative", "writing", "fiction", "poetry"],
            createdAt: Date().addingTimeInterval(-86400 * 45),
            updatedAt: Date().addingTimeInterval(-86400 * 5),
            downloadURL: URL(string: "https://huggingface.co/creative-ai/storyteller-14b"),
            previewPrompt: "Write the opening paragraph of a mystery novel"
        ),
        MarketplaceModel(
            id: "assistant-pro-8b",
            name: "Assistant Pro 8B",
            description: "The perfect personal assistant. Helpful, harmless, honest.",
            author: "ZeroDark Labs",
            category: .assistant,
            baseModel: "Llama-3.2-8B",
            sizeBytes: 4_200_000_000,
            downloads: 25000,
            rating: 4.9,
            ratingCount: 892,
            tags: ["assistant", "helpful", "productivity"],
            createdAt: Date().addingTimeInterval(-86400 * 60),
            updatedAt: Date().addingTimeInterval(-86400 * 1),
            downloadURL: URL(string: "https://huggingface.co/zerodark/assistant-pro-8b"),
            previewPrompt: "Help me plan a productive day"
        ),
        MarketplaceModel(
            id: "uncensored-llama-8b",
            name: "Uncensored Llama 8B",
            description: "No guardrails. Full creative freedom. Use responsibly.",
            author: "Open Models",
            category: .uncensored,
            baseModel: "Llama-3.2-8B-Abliterated",
            sizeBytes: 4_300_000_000,
            downloads: 45000,
            rating: 4.4,
            ratingCount: 1205,
            tags: ["uncensored", "abliterated", "freedom"],
            createdAt: Date().addingTimeInterval(-86400 * 90),
            updatedAt: Date().addingTimeInterval(-86400 * 10),
            downloadURL: URL(string: "https://huggingface.co/open-models/uncensored-llama-8b"),
            previewPrompt: nil
        ),
        MarketplaceModel(
            id: "medical-advisor-8b",
            name: "Medical Advisor 8B",
            description: "Medical knowledge assistant. NOT a replacement for professional care.",
            author: "HealthAI",
            category: .medical,
            baseModel: "Qwen2.5-8B",
            sizeBytes: 4_400_000_000,
            downloads: 5600,
            rating: 4.7,
            ratingCount: 156,
            tags: ["medical", "health", "symptoms", "educational"],
            createdAt: Date().addingTimeInterval(-86400 * 40),
            updatedAt: Date().addingTimeInterval(-86400 * 7),
            downloadURL: URL(string: "https://huggingface.co/health-ai/medical-advisor-8b"),
            previewPrompt: "Explain the symptoms of type 2 diabetes"
        ),
        MarketplaceModel(
            id: "polyglot-8b",
            name: "Polyglot 8B",
            description: "Fluent in 12 languages. Translation, conversation, teaching.",
            author: "Language Labs",
            category: .language,
            baseModel: "Qwen2.5-8B",
            sizeBytes: 4_600_000_000,
            downloads: 18000,
            rating: 4.5,
            ratingCount: 423,
            tags: ["multilingual", "translation", "spanish", "french", "german", "chinese"],
            createdAt: Date().addingTimeInterval(-86400 * 55),
            updatedAt: Date().addingTimeInterval(-86400 * 3),
            downloadURL: URL(string: "https://huggingface.co/language-labs/polyglot-8b"),
            previewPrompt: "Translate 'Hello, how are you?' into 5 languages"
        )
    ]
    
    // MARK: - State
    
    private var installedModels: [InstalledModel] = []
    private var downloadProgress: [String: Float] = [:]
    
    private init() {
        Task {
            await loadInstalledModels()
        }
    }
    
    // MARK: - Browse
    
    public func getFeaturedModels() -> [MarketplaceModel] {
        return featuredModels
    }
    
    public func getModelsByCategory(_ category: ModelCategory) -> [MarketplaceModel] {
        return featuredModels.filter { $0.category == category }
    }
    
    public func searchModels(query: String) -> [MarketplaceModel] {
        let queryLower = query.lowercased()
        return featuredModels.filter { model in
            model.name.lowercased().contains(queryLower) ||
            model.description.lowercased().contains(queryLower) ||
            model.tags.contains { $0.lowercased().contains(queryLower) }
        }
    }
    
    public func getTopDownloaded(limit: Int = 10) -> [MarketplaceModel] {
        return Array(featuredModels.sorted { $0.downloads > $1.downloads }.prefix(limit))
    }
    
    public func getTopRated(limit: Int = 10) -> [MarketplaceModel] {
        return Array(featuredModels.sorted { $0.rating > $1.rating }.prefix(limit))
    }
    
    // MARK: - Installation
    
    public func getInstalledModels() -> [InstalledModel] {
        return installedModels
    }
    
    public func isInstalled(_ modelId: String) -> Bool {
        return installedModels.contains { $0.marketplaceId == modelId }
    }
    
    public func installModel(
        _ model: MarketplaceModel,
        onProgress: @escaping (Float) -> Void
    ) async throws -> InstalledModel {
        guard let downloadURL = model.downloadURL else {
            throw MarketplaceError.downloadURLMissing
        }
        
        // Simulate download progress
        for i in 0...10 {
            try await Task.sleep(nanoseconds: 100_000_000)
            let progress = Float(i) / 10.0
            downloadProgress[model.id] = progress
            onProgress(progress)
        }
        
        // Create installed model record
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelPath = documentsPath.appendingPathComponent("models/\(model.id)")
        
        let installed = InstalledModel(
            id: UUID().uuidString,
            marketplaceId: model.id,
            name: model.name,
            localPath: modelPath,
            installedAt: Date(),
            lastUsed: nil,
            useCount: 0
        )
        
        installedModels.append(installed)
        await saveInstalledModels()
        
        downloadProgress.removeValue(forKey: model.id)
        
        return installed
    }
    
    public func uninstallModel(_ modelId: String) async throws {
        guard let index = installedModels.firstIndex(where: { $0.marketplaceId == modelId }) else {
            throw MarketplaceError.notInstalled
        }
        
        let model = installedModels[index]
        
        // Delete files
        try? FileManager.default.removeItem(at: model.localPath)
        
        installedModels.remove(at: index)
        await saveInstalledModels()
    }
    
    public func getDownloadProgress(_ modelId: String) -> Float? {
        return downloadProgress[modelId]
    }
    
    // MARK: - Publishing
    
    public struct PublishRequest {
        public let name: String
        public let description: String
        public let category: ModelCategory
        public let baseModel: String
        public let loraPath: URL
        public let tags: [String]
        public let previewPrompt: String?
        
        public init(name: String, description: String, category: ModelCategory, baseModel: String, loraPath: URL, tags: [String], previewPrompt: String?) {
            self.name = name
            self.description = description
            self.category = category
            self.baseModel = baseModel
            self.loraPath = loraPath
            self.tags = tags
            self.previewPrompt = previewPrompt
        }
    }
    
    public func publishModel(_ request: PublishRequest) async throws -> String {
        // In production: upload to server
        // Return model ID
        return "published-\(UUID().uuidString)"
    }
    
    // MARK: - Persistence
    
    private func loadInstalledModels() async {
        let key = "zerodark_installed_models"
        if let data = UserDefaults.standard.data(forKey: key),
           let models = try? JSONDecoder().decode([InstalledModel].self, from: data) {
            installedModels = models
        }
    }
    
    private func saveInstalledModels() async {
        let key = "zerodark_installed_models"
        if let data = try? JSONEncoder().encode(installedModels) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    public enum MarketplaceError: Error {
        case downloadURLMissing
        case downloadFailed
        case notInstalled
        case alreadyInstalled
        case insufficientStorage
        case publishFailed
    }
}
