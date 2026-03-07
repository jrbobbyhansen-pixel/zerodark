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

// MARK: - MLXEngine

/// Unified internal engine that dispatches to LLMModelFactory or VLMModelFactory
/// based on the model's purpose.
@MainActor
final class MLXEngine {
    
    // MARK: - State
    
    private var modelContainer: ModelContainer?
    private let model: Model
    private let generateParameters: GenerateParameters
    
    // MARK: - Init
    
    init(model: Model, temperature: Float? = nil) {
        self.model = model
        let defaultTemp: Float
        switch model.purpose {
            case .text:               defaultTemp = 0.7
            case .vision:             defaultTemp = 0.1
            case .visionSpecialized:  defaultTemp = 0.0   // deterministic OCR
        }
        self.generateParameters = GenerateParameters(temperature: temperature ?? defaultTemp)
    }
    
    // MARK: - Load
    
    func load(onProgress: @escaping (String) -> Void) async throws {
        guard modelContainer == nil else { return }
        
        let cacheLimitBytes: Int
        switch model.purpose {
            case .text:               cacheLimitBytes = 32 * 1024 * 1024
            case .vision:             cacheLimitBytes = 64 * 1024 * 1024
            case .visionSpecialized:  cacheLimitBytes = 48 * 1024 * 1024
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
                        onProgress("Downloading \(model.displayName): \(pct)%")
                    }
                }
                
            case .vision, .visionSpecialized:
                modelContainer = try await VLMModelFactory.shared.loadContainer(
                    configuration: config
                ) { [model] progress in
                    let pct = Int(progress.fractionCompleted * 100)
                    Task { @MainActor in
                        onProgress("Downloading \(model.displayName): \(pct)%")
                    }
                }
        }
        
        onProgress("\(model.displayName) ready ✓")
    }
    
    // MARK: - Generate (text-only)
    
    func generate(
        prompt: String,
        systemPrompt: String? = nil,
        maxTokens: Int = 1024,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        guard let container = modelContainer else {
            throw MLXEdgeLLMError.modelNotLoaded
        }
        
        var messages: [[String: String]] = []
        if let sys = systemPrompt {
            messages.append(["role": "system", "content": sys])
        }
        messages.append(["role": "user", "content": prompt])
        
        return try await container.perform { context in
            let input = try await context.processor.prepare(
                input: .init(messages: messages)
            )
            let result = try MLXLMCommon.generate(
                input: input,
                parameters: self.generateParameters,
                context: context
            ) { tokens in
                let partial = context.tokenizer.decode(tokens: tokens)
                Task { @MainActor in onToken(partial) }
                return tokens.count >= maxTokens ? .stop : .more
            }
            return context.tokenizer.decode(tokens: result.tokens)
        }
    }
    
    // MARK: - Generate (vision)
    
    func generate(
        prompt: String,
        image: PlatformImage?,
        maxTokens: Int = 800,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        guard let container = modelContainer else {
            throw MLXEdgeLLMError.modelNotLoaded
        }
        
        let userInput: UserInput
        if let img = image, let url = saveImageToTemp(img) {
            userInput = UserInput(prompt: prompt, images: [.url(url)])
        } else {
            userInput = UserInput(prompt: prompt)
        }
        
        return try await container.perform { context in
            let input = try await context.processor.prepare(input: userInput)
            let result = try MLXLMCommon.generate(
                input: input,
                parameters: self.generateParameters,
                context: context
            ) { tokens in
                let partial = context.tokenizer.decode(tokens: tokens)
                Task { @MainActor in onToken(partial) }
                return tokens.count >= maxTokens ? .stop : .more
            }
            return context.tokenizer.decode(tokens: result.tokens)
        }
    }
    
    // MARK: - Helpers
    
    private func saveImageToTemp(_ image: PlatformImage) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "mlxedge_\(UUID().uuidString).jpg")
#if canImport(UIKit)
        guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
#else
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = NSBitmapImageRep(cgImage: cgImage)
            .representation(using: .jpeg, properties: [:]) else { return nil }
#endif
        try? data.write(to: url)
        return url
    }
}
