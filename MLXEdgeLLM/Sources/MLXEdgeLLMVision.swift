import Foundation
import UIKit
import os

// MARK: - MLXEdgeLLMVision

/// API pública para análisis de imágenes on-device usando modelos VLM con MLX.
///
/// ```swift
/// // Análisis de ticket (one-liner)
/// let json = try await MLXEdgeLLMVision.extractReceipt(ticketImage)
///
/// // Instancia reutilizable (recomendado para múltiples llamadas)
/// let vision = try await MLXEdgeLLMVision(model: .qwen35_0_8b)
/// let json = try await vision.extractReceipt(ticketImage)
/// let desc = try await vision.analyze("¿Qué hay en esta imagen?", image: foto)
/// ```
@available(iOS 16.0, macOS 14.0, *)
public actor MLXEdgeLLMVision {

    // MARK: - Options

    public struct Options: Sendable {
        public var temperature: Float
        public var maxTokens: Int

        /// Opciones para OCR / extracción de datos — temperatura baja para resultados deterministas
        public static let extraction = Options(temperature: 0.1, maxTokens: 512)

        /// Opciones para chat visual conversacional
        public static let chat = Options(temperature: 0.3, maxTokens: 1024)

        public static let `default` = Options.extraction

        public init(temperature: Float = 0.1, maxTokens: Int = 512) {
            self.temperature = temperature
            self.maxTokens = maxTokens
        }
    }

    // MARK: - Properties

    private let engine: VisionEngine
    private let options: Options
    private let logger = Logger(subsystem: "ai.mlxedgellm", category: "MLXEdgeLLMVision")

    // MARK: - Init

    /// Inicializa y carga el modelo VLM.
    /// El modelo se descarga de HuggingFace en el primer uso y se cachea localmente (~1 GB para Qwen3.5 0.8B).
    /// - Parameters:
    ///   - model: Modelo VLM a usar (default: Qwen3.5 0.8B)
    ///   - options: Opciones de generación
    ///   - onProgress: Callback de progreso de descarga 0.0 → 1.0
    public init(
        model: VisionModel = .default,
        options: Options = .default,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        self.options = options
        self.engine = VisionEngine(modelId: model.rawValue)
        try await engine.load(onProgress: onProgress)
        logger.info("MLXEdgeLLMVision ready: \(model.displayName)")
    }

    // MARK: - Analyze Image

    /// Analiza una imagen con un prompt de texto.
    /// - Parameters:
    ///   - prompt: Instrucción o pregunta sobre la imagen
    ///   - image: Imagen a analizar
    /// - Returns: Respuesta completa del modelo
    public func analyze(_ prompt: String, image: UIImage) async throws -> String {
        try await engine.generate(
            prompt: prompt,
            image: image,
            maxTokens: options.maxTokens,
            temperature: options.temperature
        )
    }

    // MARK: - Text Chat (sin imagen)

    /// Chat de texto puro sin imagen.
    public func chat(_ prompt: String) async throws -> String {
        try await engine.generate(
            prompt: prompt,
            image: nil,
            maxTokens: options.maxTokens,
            temperature: options.temperature
        )
    }

    // MARK: - Streaming

    /// Analiza una imagen con streaming de tokens.
    public func stream(
        _ prompt: String,
        image: UIImage? = nil
    ) -> AsyncThrowingStream<String, Error> {
        engine.stream(
            prompt: prompt,
            image: image,
            maxTokens: options.maxTokens,
            temperature: options.temperature
        )
    }

    // MARK: - Receipt Extraction

    /// Extrae datos estructurados de un ticket de compra como JSON.
    /// - Parameter image: Foto del ticket
    /// - Returns: JSON con tienda, fecha, items y total
    public func extractReceipt(_ image: UIImage) async throws -> String {
        let prompt = """
        Analyze this receipt and extract the information as JSON with this exact structure:
        {
          "store": "store name",
          "date": "date in YYYY-MM-DD format",
          "items": [
            {"name": "product name", "quantity": 1, "price": 0.00}
          ],
          "subtotal": 0.00,
          "tax": 0.00,
          "total": 0.00,
          "currency": "currency code (USD, MXN, EUR, etc.)"
        }
        Respond ONLY with the JSON, no additional text.
        """
        return try await analyze(prompt, image: image)
    }

    // MARK: - Unload

    public func unload() async {
        await engine.unload()
    }
}

// MARK: - Static API (one-liners)

@available(iOS 16.0, macOS 14.0, *)
public extension MLXEdgeLLMVision {

    /// Analiza una imagen en una sola línea.
    static func analyze(
        _ prompt: String,
        image: UIImage,
        model: VisionModel = .default,
        options: Options = .default
    ) async throws -> String {
        let vision = try await MLXEdgeLLMVision(model: model, options: options)
        return try await vision.analyze(prompt, image: image)
    }

    /// Extrae datos de un ticket en una sola línea.
    static func extractReceipt(
        _ image: UIImage,
        model: VisionModel = .default
    ) async throws -> String {
        let vision = try await MLXEdgeLLMVision(model: model)
        return try await vision.extractReceipt(image)
    }
}
