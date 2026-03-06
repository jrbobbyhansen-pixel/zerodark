import Foundation
import MLX
import MLXVLM
import MLXLMCommon
import UIKit
import os

/// Motor de inferencia para modelos Vision-Language usando MLXVLM.
@available(iOS 16.0, macOS 14.0, *)
actor VisionEngine {
    
    // MARK: - Properties
    
    private var container: ModelContainer?
    private let modelId: String
    private let logger = Logger(subsystem: "ai.mlxedgellm", category: "VisionEngine")
    
    // MARK: - Init
    
    init(modelId: String) {
        self.modelId = modelId
    }
    
    // MARK: - Load
    
    /// Carga el modelo desde HuggingFace (se cachea automáticamente en disco).
    func load(onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        logger.info("Loading VLM model: \(self.modelId)")
        MLX.GPU.set(cacheLimit: 64 * 1024 * 1024)
        
        let config = ModelConfiguration(id: modelId)
        container = try await VLMModelFactory.shared.loadContainer(
            configuration: config
        ) { progress in
            onProgress?(progress.fractionCompleted)
        }
        logger.info("VLM model loaded: \(self.modelId)")
    }
    
    // MARK: - Generate
    
    /// Genera una respuesta completa dado un prompt e imagen opcional.
    func generate(
        prompt: String,
        image: UIImage? = nil,
        maxTokens: Int = 512,
        temperature: Float = 0.1
    ) async throws -> String {
        guard let container else { throw MLXEdgeLLMError.modelNotLoaded }
        
        return try await container.perform { context in
            let messages: [Message] = image != nil
            ? [.user([.image(image!), .text(prompt)])]
            : [.user([.text(prompt)])]
            
            let input = try context.processor.prepare(
                input: UserInput(messages: messages)
            )
            let params = GenerateParameters(
                temperature: temperature,
                maxTokens: maxTokens
            )
            
            var result = ""
            for await token in context.model.generate(input: input, parameters: params) {
                result += token
            }
            return result
        }
    }
    
    // MARK: - Stream
    
    /// Genera tokens de forma progresiva.
    func stream(
        prompt: String,
        image: UIImage? = nil,
        maxTokens: Int = 512,
        temperature: Float = 0.3
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let container = self.container else {
                    continuation.finish(throwing: MLXEdgeLLMError.modelNotLoaded)
                    return
                }
                do {
                    try await container.perform { context in
                        let messages: [Message] = image != nil
                        ? [.user([.image(image!), .text(prompt)])]
                        : [.user([.text(prompt)])]
                        
                        let input = try context.processor.prepare(
                            input: UserInput(messages: messages)
                        )
                        let params = GenerateParameters(
                            temperature: temperature,
                            maxTokens: maxTokens
                        )
                        for await token in context.model.generate(input: input, parameters: params) {
                            continuation.yield(token)
                        }
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Unload
    
    func unload() {
        container = nil
        logger.info("VLM model unloaded")
    }
}
