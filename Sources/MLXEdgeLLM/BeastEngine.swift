import Foundation
import MLX
import MLXLLM
import MLXVLM
import MLXLMCommon

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - BeastEngine

/// Beast Mode enhanced MLX engine with full parameter control and performance monitoring
@MainActor
public final class BeastEngine {
    
    // MARK: - State
    
    private var modelContainer: ModelContainer?
    public let model: Model
    private var params: BeastModeParams
    private var systemPrompt: String?
    
    // Generation tracking
    private var generationStartTime: Date?
    private var firstTokenTime: Date?
    private var tokenCount: Int = 0
    private var promptTokenCount: Int = 0
    
    // Cancellation support (nonisolated for closure access)
    private nonisolated(unsafe) var shouldStop = false
    private nonisolated(unsafe) var _firstTokenTime: Date?
    private nonisolated(unsafe) var _tokenCount: Int = 0
    
    // MARK: - Init
    
    public init(
        model: Model,
        params: BeastModeParams = .balanced,
        systemPrompt: String? = nil
    ) {
        self.model = model
        self.params = params
        self.systemPrompt = systemPrompt
    }
    
    // MARK: - Configuration
    
    public func setParams(_ newParams: BeastModeParams) {
        self.params = newParams
    }
    
    public func setSystemPrompt(_ prompt: String?) {
        self.systemPrompt = prompt
    }
    
    // MARK: - Load
    
    public func load(
        onProgress: @escaping (String) -> Void,
        onMemoryWarning: ((Int) -> Void)? = nil
    ) async throws {
        guard modelContainer == nil else { return }
        
        // Check memory before loading
        let monitor = SystemMonitor.shared
        if model.approximateSizeMB > 4000 && !monitor.canLoad8BModel {
            throw BeastError.insufficientMemory(
                required: model.approximateSizeMB,
                available: monitor.memoryAvailableMB
            )
        }
        
        // Configure GPU cache based on model size
        let cacheLimitBytes: Int
        switch model.approximateSizeMB {
        case 0..<1000:
            cacheLimitBytes = 32 * 1024 * 1024
        case 1000..<3000:
            cacheLimitBytes = 64 * 1024 * 1024
        case 3000..<5000:
            cacheLimitBytes = 96 * 1024 * 1024
        default:
            cacheLimitBytes = 128 * 1024 * 1024
        }
        MLX.GPU.set(cacheLimit: cacheLimitBytes)
        
        let config = ModelConfiguration(id: model.rawValue)
        
        switch model.purpose {
        case .text:
            modelContainer = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            ) { [model] progress in
                let pct = Int(progress.fractionCompleted * 100)
                Task { @MainActor in
                    onProgress("📥 \(model.displayName): \(pct)%")
                }
            }
            
        case .vision, .visionSpecialized:
            modelContainer = try await VLMModelFactory.shared.loadContainer(
                configuration: config
            ) { [model] progress in
                let pct = Int(progress.fractionCompleted * 100)
                Task { @MainActor in
                    onProgress("📥 \(model.displayName): \(pct)%")
                }
            }
        }
        
        onProgress("⚡ \(model.displayName) loaded")
    }
    
    // MARK: - Unload
    
    public func unload() {
        modelContainer = nil
        MLX.GPU.clearCache()
    }
    
    // MARK: - Stop Generation
    
    public func stop() {
        shouldStop = true
    }
    
    private func resetTracking() {
        shouldStop = false
        _firstTokenTime = nil
        _tokenCount = 0
    }
    
    // MARK: - Generate (Text)
    
    public func generate(
        prompt: String,
        history: [[String: String]] = [],
        onToken: @escaping @MainActor (String) -> Void,
        onStats: ((GenerationStats) -> Void)? = nil
    ) async throws -> String {
        guard let container = modelContainer else {
            throw BeastError.modelNotLoaded
        }
        
        // Reset state
        resetTracking()
        let startTime = Date()
        generationStartTime = startTime
        
        // Build messages
        var messages: [[String: String]] = []
        
        if let sys = systemPrompt {
            messages.append(["role": "system", "content": sys])
        }
        
        // Add conversation history
        messages.append(contentsOf: history)
        
        // Add current prompt
        messages.append(["role": "user", "content": prompt])
        
        // Estimate prompt tokens
        let promptTokens = messages.reduce(0) { $0 + ($1["content"]?.count ?? 0) / 4 }
        promptTokenCount = promptTokens
        
        // Build generate parameters
        let genParams = GenerateParameters(
            temperature: params.temperature,
            topP: params.topP,
            repetitionPenalty: params.repetitionPenalty,
            repetitionContextSize: params.repetitionContextSize
        )
        
        // Capture values for closure
        let maxTokens = params.maxTokens
        let stopSeqs = params.stopSequences
        
        // Copy messages for closure
        let messagesCopy = messages
        
        return try await container.perform { [self] context in
            let input = try await context.processor.prepare(
                input: .init(messages: messagesCopy)
            )
            
            let result = try MLXLMCommon.generate(
                input: input,
                parameters: genParams,
                context: context
            ) { tokens in
                guard !self.shouldStop else {
                    return .stop
                }
                
                // Track first token time
                if self._firstTokenTime == nil {
                    self._firstTokenTime = Date()
                }
                
                self._tokenCount = tokens.count
                
                let partial = context.tokenizer.decode(tokens: tokens)
                Task { @MainActor in onToken(partial) }
                
                // Check stop sequences
                for stop in stopSeqs {
                    if partial.hasSuffix(stop) {
                        return .stop
                    }
                }
                
                return tokens.count >= maxTokens ? .stop : .more
            }
            
            // Calculate stats
            let endTime = Date()
            let totalTime = endTime.timeIntervalSince(startTime)
            let ttft = self._firstTokenTime?.timeIntervalSince(startTime) ?? 0
            
            let stats = GenerationStats(
                tokensGenerated: result.tokens.count,
                promptTokens: promptTokens,
                totalTokens: promptTokens + result.tokens.count,
                tokensPerSecond: totalTime > 0 ? Double(result.tokens.count) / totalTime : 0,
                timeToFirstToken: ttft,
                totalGenerationTime: totalTime,
                peakMemoryMB: 0,  // Will be updated on MainActor
                gpuMemoryMB: 0
            )
            onStats?(stats)
            
            return context.tokenizer.decode(tokens: result.tokens)
        }
    }
    
    // MARK: - Generate (Vision)
    
    public func generateVision(
        prompt: String,
        images: [PlatformImage],
        onToken: @escaping @MainActor (String) -> Void,
        onStats: ((GenerationStats) -> Void)? = nil
    ) async throws -> String {
        guard let container = modelContainer else {
            throw BeastError.modelNotLoaded
        }
        
        // Reset state
        resetTracking()
        let startTime = Date()
        generationStartTime = startTime
        
        // Save images to temp and create URLs
        let imageURLs: [UserInput.Image] = images.compactMap { image in
            guard let url = saveImageToTemp(image) else { return nil }
            return .url(url)
        }
        
        let userInput = UserInput(prompt: prompt, images: imageURLs)
        let promptTokens = prompt.count / 4 + (images.count * 500) // rough estimate for images
        promptTokenCount = promptTokens
        
        let genParams = GenerateParameters(
            temperature: params.temperature,
            topP: params.topP,
            repetitionPenalty: params.repetitionPenalty,
            repetitionContextSize: params.repetitionContextSize
        )
        
        let maxTokens = params.maxTokens
        
        return try await container.perform { [self] context in
            let input = try await context.processor.prepare(input: userInput)
            
            let result = try MLXLMCommon.generate(
                input: input,
                parameters: genParams,
                context: context
            ) { tokens in
                guard !self.shouldStop else {
                    return .stop
                }
                
                if self._firstTokenTime == nil {
                    self._firstTokenTime = Date()
                }
                
                self._tokenCount = tokens.count
                let partial = context.tokenizer.decode(tokens: tokens)
                Task { @MainActor in onToken(partial) }
                
                return tokens.count >= maxTokens ? .stop : .more
            }
            
            // Stats
            let endTime = Date()
            let totalTime = endTime.timeIntervalSince(startTime)
            let ttft = self._firstTokenTime?.timeIntervalSince(startTime) ?? 0
            
            let stats = GenerationStats(
                tokensGenerated: result.tokens.count,
                promptTokens: promptTokens,
                totalTokens: promptTokens + result.tokens.count,
                tokensPerSecond: totalTime > 0 ? Double(result.tokens.count) / totalTime : 0,
                timeToFirstToken: ttft,
                totalGenerationTime: totalTime,
                peakMemoryMB: 0,
                gpuMemoryMB: 0
            )
            onStats?(stats)
            
            return context.tokenizer.decode(tokens: result.tokens)
        }
    }
    
    // MARK: - Helpers
    
    private func saveImageToTemp(_ image: PlatformImage) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "beast_\(UUID().uuidString).jpg")
        
        #if canImport(UIKit)
        // Resize large images to save memory
        let maxDimension: CGFloat = 1024
        let resized = resizeImage(image, maxDimension: maxDimension)
        guard let data = resized.jpegData(compressionQuality: 0.85) else { return nil }
        #else
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = NSBitmapImageRep(cgImage: cgImage)
                .representation(using: .jpeg, properties: [:]) else { return nil }
        #endif
        
        try? data.write(to: url)
        return url
    }
    
    #if canImport(UIKit)
    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        
        if size.width <= maxDimension && size.height <= maxDimension {
            return image
        }
        
        let ratio = min(maxDimension / size.width, maxDimension / size.height)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        
        return resized
    }
    #endif
}

// MARK: - Beast Errors

public enum BeastError: LocalizedError {
    case modelNotLoaded
    case insufficientMemory(required: Int, available: Int)
    case generationCancelled
    case invalidModel(String)
    case thermalThrottling
    
    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Model not loaded. Call load() first."
        case .insufficientMemory(let required, let available):
            return "Not enough memory. Need \(required)MB, have \(available)MB. Close other apps and try again."
        case .generationCancelled:
            return "Generation was cancelled."
        case .invalidModel(let reason):
            return "Invalid model: \(reason)"
        case .thermalThrottling:
            return "Device is too hot. Let it cool down before continuing."
        }
    }
}

// MARK: - Stream Extension

public extension BeastEngine {
    
    /// Stream tokens with full stats
    func stream(
        prompt: String,
        history: [[String: String]] = []
    ) -> AsyncThrowingStream<(token: String, stats: GenerationStats?), Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                do {
                    var lastStats: GenerationStats?
                    
                    _ = try await self.generate(
                        prompt: prompt,
                        history: history,
                        onToken: { partial in
                            // Yield new tokens (delta)
                            continuation.yield((partial, lastStats))
                        },
                        onStats: { stats in
                            lastStats = stats
                        }
                    )
                    
                    // Final yield with stats
                    if let stats = lastStats {
                        continuation.yield(("", stats))
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
