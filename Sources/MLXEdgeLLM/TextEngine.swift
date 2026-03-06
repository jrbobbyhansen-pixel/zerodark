import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import os

/// Motor de inferencia para modelos de texto usando MLXLLM.
@available(iOS 16.0, macOS 14.0, *)
actor TextEngine {
    
    // MARK: - Properties
    
    private var container: ModelContainer?
    private let modelId: String
    private let logger = Logger(subsystem: "ai.mlxedgellm", category: "TextEngine")
    
    // MARK: - Init
    
    init(modelId: String) {
        self.modelId = modelId
    }
    
    // MARK: - Load
    
    /// Carga el modelo desde HuggingFace (se cachea automáticamente en disco).
    func load(onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        logger.info("Loading text model: \(self.modelId)")
        MLX.GPU.set(cacheLimit: 32 * 1024 * 1024)
        
        let config = ModelConfiguration(id: modelId)
        container = try await LLMModelFactory.shared.loadContainer(
            configuration: config
        ) { progress in
            onProgress?(progress.fractionCompleted)
        }
        logger.info("Text model loaded: \(self.modelId)")
    }
    
    // MARK: - Generate
    
    /// Genera una respuesta completa.
    func generate(
        prompt: String,
        systemPrompt: String? = nil,
        maxTokens: Int = 1024,
        temperature: Float = 0.7
    ) async throws -> String {
        guard let container else { throw MLXEdgeLLMError.modelNotLoaded }
        
        return try await container.perform { context in
            var messages: [Message] = []
            if let system = systemPrompt {
                messages.append(.system(system))
            }
            messages.append(.user(prompt))
            
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
        systemPrompt: String? = nil,
        maxTokens: Int = 1024,
        temperature: Float = 0.7
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let container = self.container else {
                    continuation.finish(throwing: MLXEdgeLLMError.modelNotLoaded)
                    return
                }
                do {
                    try await container.perform { context in
                        var messages: [Message] = []
                        if let system = systemPrompt {
                            messages.append(.system(system))
                        }
                        messages.append(.user(prompt))
                        
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
        logger.info("Text model unloaded")
    }
}
