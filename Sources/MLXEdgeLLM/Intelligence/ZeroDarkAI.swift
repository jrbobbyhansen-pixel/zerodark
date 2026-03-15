import Foundation

// MARK: - Zero Dark AI

/// The unified intelligence interface for Zero Dark
/// Combines routing, ensemble, and adaptive capabilities
@MainActor
public final class ZeroDarkAI: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = ZeroDarkAI()
    
    // MARK: - Components
    
    public let router = ModelRouter.shared
    public let ensemble = EnsembleEngine()
    public let monitor = SystemMonitor.shared
    
    // MARK: - State
    
    @Published public var mode: EnsembleEngine.Mode = .single
    @Published public var isProcessing = false
    @Published public var currentModel: Model?
    @Published public var lastDecision: ModelRouter.RoutingDecision?
    @Published public var conversationContext: [String] = []
    
    // Adaptive settings
    @Published public var adaptiveMode = true
    @Published public var qualityPriority = true // false = speed priority
    @Published public var powerSaveMode = false
    
    // MARK: - Initialization
    
    private init() {
        // Start monitoring
        monitor.startMonitoring()
    }
    
    // MARK: - Main Interface
    
    /// Process any request with full intelligence
    public func process(
        prompt: String,
        images: [PlatformImage] = [],
        systemPrompt: String? = nil,
        forceModel: Model? = nil,
        onToken: @escaping @MainActor (String) -> Void,
        onStats: ((GenerationStats) -> Void)? = nil
    ) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }
        
        let hasImages = !images.isEmpty
        
        // Get routing decision
        let decision = router.route(
            prompt: prompt,
            hasImages: hasImages,
            forceModel: forceModel
        )
        lastDecision = decision
        currentModel = decision.selectedModel
        
        // Adapt mode based on conditions
        let effectiveMode = determineMode(for: decision)
        
        // Execute based on mode
        let result: EnsembleEngine.EnsembleResult
        
        switch effectiveMode {
        case .single:
            result = try await ensemble.runRouted(
                prompt: buildPrompt(prompt, systemPrompt: systemPrompt),
                hasImages: hasImages,
                images: images,
                onToken: onToken
            )
            
        case .cascade:
            let models = getCascadeModels(for: decision.taskType)
            result = try await ensemble.runCascade(
                prompt: buildPrompt(prompt, systemPrompt: systemPrompt),
                models: models,
                onToken: onToken
            )
            
        case .parallel:
            let models = getParallelModels(for: decision.taskType)
            result = try await ensemble.runParallel(
                prompt: buildPrompt(prompt, systemPrompt: systemPrompt),
                models: models
            ) { model, token in
                // Only send tokens from primary model to UI
                if model == decision.selectedModel {
                    onToken(token)
                }
            }
            
        case .speculative:
            let (draft, verify) = getSpeculativeModels()
            result = try await ensemble.runSpeculative(
                prompt: buildPrompt(prompt, systemPrompt: systemPrompt),
                draftModel: draft,
                verifyModel: verify,
                onToken: onToken
            )
            
        case .consensus:
            let models = getParallelModels(for: decision.taskType)
            result = try await ensemble.runConsensus(
                prompt: buildPrompt(prompt, systemPrompt: systemPrompt),
                models: models
            ) { model, token in
                if model == decision.selectedModel {
                    onToken(token)
                }
            }
        }
        
        // Update conversation context
        conversationContext.append("User: \(prompt)")
        conversationContext.append("AI: \(result.finalResponse)")
        
        // Keep context manageable
        if conversationContext.count > 20 {
            conversationContext.removeFirst(2)
        }
        
        return result.finalResponse
    }
    
    // MARK: - Mode Determination
    
    private func determineMode(for decision: ModelRouter.RoutingDecision) -> EnsembleEngine.Mode {
        // If user set a specific mode, respect it (unless power save)
        if !adaptiveMode {
            return powerSaveMode ? .single : mode
        }
        
        // Power save always uses single model
        if powerSaveMode {
            return .single
        }
        
        // Low confidence → use cascade
        if decision.confidence < 0.6 {
            return .cascade
        }
        
        // High-stakes tasks → parallel for quality
        if qualityPriority {
            switch decision.taskType {
            case .code, .reasoning, .math:
                return .parallel
            case .uncensored:
                return .single // Uncensored needs specific model
            default:
                break
            }
        }
        
        // Use speculative for long generations
        if decision.params.maxTokens > 2000 {
            return .speculative
        }
        
        return mode
    }
    
    // MARK: - Model Selection Helpers
    
    private func getCascadeModels(for taskType: ModelRouter.TaskType) -> [Model] {
        let available = router.availableModels
        
        // Start with best, fall back to smaller
        switch taskType {
        case .code:
            return [.qwen25_coder_14b, .qwen25_coder_7b, .qwen3_8b, .qwen3_4b]
                .filter { available.contains($0) }
        case .reasoning:
            return [.deepseek_r1_14b, .deepseek_r1_8b, .qwen3_8b, .qwen3_4b]
                .filter { available.contains($0) }
        case .uncensored:
            return [.qwen3_8b_abliterated, .hermes3_8b, .qwen3_8b]
                .filter { available.contains($0) }
        default:
            return [.qwen3_14b, .qwen3_8b, .qwen3_4b]
                .filter { available.contains($0) }
        }
    }
    
    private func getParallelModels(for taskType: ModelRouter.TaskType) -> [Model] {
        let available = router.availableModels
        
        // Run 2-3 diverse models
        switch taskType {
        case .code:
            return [.qwen25_coder_7b, .qwen3_8b, .deepseek_r1_8b]
                .filter { available.contains($0) }
                .prefix(3)
                .map { $0 }
        case .reasoning:
            return [.deepseek_r1_8b, .qwen3_8b, .llama3_1_8b]
                .filter { available.contains($0) }
                .prefix(3)
                .map { $0 }
        default:
            return [.qwen3_8b, .llama3_1_8b, .ministral_8b]
                .filter { available.contains($0) }
                .prefix(2)
                .map { $0 }
        }
    }
    
    private func getSpeculativeModels() -> (draft: Model, verify: Model) {
        let available = router.availableModels
        
        // Small model for draft, large for verify
        let draft = [Model.qwen3_4b, .llama3_2_3b, .qwen3_1_7b]
            .first { available.contains($0) } ?? .qwen3_4b
            
        let verify = [Model.qwen3_14b, .qwen3_8b, .llama3_1_8b]
            .first { available.contains($0) } ?? .qwen3_8b
            
        return (draft, verify)
    }
    
    // MARK: - Prompt Building
    
    private func buildPrompt(_ prompt: String, systemPrompt: String?) -> String {
        if let sys = systemPrompt {
            return "System: \(sys)\n\nUser: \(prompt)"
        }
        return prompt
    }
    
    // MARK: - Quick Actions
    
    /// Quick code generation
    public func code(
        _ task: String,
        language: String = "Swift",
        onToken: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        let prompt = PromptBuilder.codePrompt(task: task, language: language)
        return try await process(
            prompt: prompt,
            forceModel: router.availableModels.contains(.qwen25_coder_7b) ? .qwen25_coder_7b : nil,
            onToken: onToken
        )
    }
    
    /// Quick reasoning
    public func reason(
        _ question: String,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        let prompt = PromptBuilder.chainOfThought(question)
        return try await process(
            prompt: prompt,
            forceModel: router.availableModels.contains(.deepseek_r1_8b) ? .deepseek_r1_8b : nil,
            onToken: onToken
        )
    }
    
    /// Quick image analysis
    public func analyzeImage(
        _ images: [PlatformImage],
        question: String = "Describe what you see in detail.",
        onToken: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        return try await process(
            prompt: question,
            images: images,
            onToken: onToken
        )
    }
    
    /// Uncensored mode
    public func uncensored(
        _ prompt: String,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        router.preferUncensored = true
        defer { router.preferUncensored = false }
        
        return try await process(
            prompt: prompt,
            forceModel: .qwen3_8b_abliterated,
            onToken: onToken
        )
    }
    
    // MARK: - Cleanup
    
    public func unloadAll() {
        ensemble.unloadAll()
        currentModel = nil
    }
    
    public func clearContext() {
        conversationContext.removeAll()
    }
}

// MARK: - Convenience Extensions

public extension ZeroDarkAI {
    
    /// Get a human-readable status
    var statusDescription: String {
        var parts: [String] = []
        
        parts.append("Device: \(router.deviceTier.displayName)")
        parts.append("Models available: \(router.availableModels.count)")
        
        if let model = currentModel {
            parts.append("Active: \(model.displayName)")
        }
        
        parts.append("Mode: \(mode.rawValue)")
        
        if adaptiveMode {
            parts.append("Adaptive: ON")
        }
        
        if powerSaveMode {
            parts.append("Power Save: ON")
        }
        
        return parts.joined(separator: " | ")
    }
    
    /// Check if PRO models are available
    var hasProModels: Bool {
        router.deviceTier >= .performance
    }
    
    /// Get best available model for a task
    func bestModel(for task: ModelRouter.TaskType) -> Model {
        router.selectModel(for: task)
    }
}
