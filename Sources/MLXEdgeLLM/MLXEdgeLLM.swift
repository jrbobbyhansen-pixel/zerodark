import Foundation
import os

// MARK: - MLXEdgeLLM (Text)

/// API pública para inferencia de texto on-device usando MLX.
///
/// ```swift
/// // One-liner
/// let reply = try await MLXEdgeLLM.chat("¿Cuánto gasté esta semana?")
///
/// // Instancia reutilizable (recomendado para múltiples llamadas)
/// let llm = try await MLXEdgeLLM(model: .qwen3_1_7b)
/// let reply = try await llm.chat("Explica este gasto")
/// ```
@available(iOS 16.0, macOS 14.0, *)
public actor MLXEdgeLLM {
    
    // MARK: - Options
    
    public struct Options: Sendable {
        public var temperature: Float
        public var maxTokens: Int
        public var systemPrompt: String?
        
        public static let `default` = Options()
        
        public init(
            temperature: Float = 0.7,
            maxTokens: Int = 1024,
            systemPrompt: String? = nil
        ) {
            self.temperature = temperature
            self.maxTokens = maxTokens
            self.systemPrompt = systemPrompt
        }
    }
    
    // MARK: - Properties
    
    private let engine: TextEngine
    private let options: Options
    private let logger = Logger(subsystem: "ai.mlxedgellm", category: "MLXEdgeLLM")
    
    // MARK: - Init
    
    /// Inicializa y carga el modelo de texto.
    /// El modelo se descarga de HuggingFace en el primer uso y se cachea localmente.
    /// - Parameters:
    ///   - model: Modelo de texto a usar (default: Qwen3 1.7B)
    ///   - options: Opciones de generación
    ///   - onProgress: Callback de progreso de descarga 0.0 → 1.0
    public init(
        model: TextModel = .default,
        options: Options = .default,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        self.options = options
        self.engine = TextEngine(modelId: model.rawValue)
        try await engine.load(onProgress: onProgress)
        logger.info("MLXEdgeLLM ready: \(model.displayName)")
    }
    
    // MARK: - Chat
    
    /// Envía un mensaje y obtiene la respuesta completa.
    public func chat(
        _ prompt: String,
        systemPrompt: String? = nil
    ) async throws -> String {
        try await engine.generate(
            prompt: prompt,
            systemPrompt: systemPrompt ?? options.systemPrompt,
            maxTokens: options.maxTokens,
            temperature: options.temperature
        )
    }
    
    // MARK: - Stream
    
    /// Streaming de tokens en tiempo real.
    public func stream(
        _ prompt: String,
        systemPrompt: String? = nil
    ) -> AsyncThrowingStream<String, Error> {
        engine.stream(
            prompt: prompt,
            systemPrompt: systemPrompt ?? options.systemPrompt,
            maxTokens: options.maxTokens,
            temperature: options.temperature
        )
    }
    
    // MARK: - Unload
    
    public func unload() async {
        await engine.unload()
    }
}

// MARK: - Static API

@available(iOS 16.0, macOS 14.0, *)
public extension MLXEdgeLLM {
    
    /// Chat en una sola línea.
    static func chat(
        _ prompt: String,
        model: TextModel = .default,
        options: Options = .default
    ) async throws -> String {
        let llm = try await MLXEdgeLLM(model: model, options: options)
        return try await llm.chat(prompt)
    }
    
    /// Streaming en una sola línea.
    static func stream(
        _ prompt: String,
        model: TextModel = .default,
        options: Options = .default
    ) async throws -> AsyncThrowingStream<String, Error> {
        let llm = try await MLXEdgeLLM(model: model, options: options)
        return await llm.stream(prompt)
    }
}
