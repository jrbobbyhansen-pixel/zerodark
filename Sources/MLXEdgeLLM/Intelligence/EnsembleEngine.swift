import Foundation

// MARK: - Ensemble Engine

/// Run multiple models and synthesize the best response
@MainActor
public final class EnsembleEngine: ObservableObject {
    
    // MARK: - Ensemble Mode
    
    public enum Mode: String, CaseIterable {
        case single = "Single Model"
        case cascade = "Cascade (Fallback)"
        case parallel = "Parallel (Best of N)"
        case consensus = "Consensus (Vote)"
        case speculative = "Speculative (Draft + Verify)"
    }
    
    // MARK: - Result
    
    public struct EnsembleResult {
        public let finalResponse: String
        public let selectedModel: Model
        public let allResponses: [(model: Model, response: String, score: Float)]
        public let mode: Mode
        public let totalTime: TimeInterval
        public let reasoning: String
    }
    
    // MARK: - State
    
    @Published public private(set) var isRunning = false
    @Published public private(set) var currentPhase = ""
    @Published public private(set) var progress: Float = 0
    
    private var engines: [Model: BeastEngine] = [:]
    private let router = ModelRouter.shared
    
    // MARK: - Single Model (Routed)
    
    public func runRouted(
        prompt: String,
        hasImages: Bool = false,
        images: [PlatformImage] = [],
        onToken: @escaping @MainActor (String) -> Void
    ) async throws -> EnsembleResult {
        let startTime = Date()
        
        // Get routing decision
        let decision = router.route(prompt: prompt, hasImages: hasImages)
        currentPhase = "Using \(decision.selectedModel.displayName)"
        
        // Run the selected model
        let engine = try await getEngine(for: decision.selectedModel)
        engine.setParams(decision.params)
        
        let response: String
        if hasImages && !images.isEmpty {
            response = try await engine.generateVision(
                prompt: prompt,
                images: images,
                onToken: onToken
            )
        } else {
            response = try await engine.generate(
                prompt: prompt,
                onToken: onToken
            )
        }
        
        router.recordSuccess(model: decision.selectedModel)
        
        return EnsembleResult(
            finalResponse: response,
            selectedModel: decision.selectedModel,
            allResponses: [(decision.selectedModel, response, 1.0)],
            mode: .single,
            totalTime: Date().timeIntervalSince(startTime),
            reasoning: decision.reasoning
        )
    }
    
    // MARK: - Cascade Mode
    
    /// Try models in sequence until one succeeds with good quality
    public func runCascade(
        prompt: String,
        models: [Model],
        qualityThreshold: Float = 0.7,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws -> EnsembleResult {
        let startTime = Date()
        var allResponses: [(Model, String, Float)] = []
        
        for (index, model) in models.enumerated() {
            currentPhase = "Trying \(model.displayName) (\(index + 1)/\(models.count))"
            progress = Float(index) / Float(models.count)
            
            do {
                let engine = try await getEngine(for: model)
                var fullResponse = ""
                
                let response = try await engine.generate(
                    prompt: prompt,
                    onToken: { token in
                        fullResponse = token
                        onToken(token)
                    }
                )
                
                // Score the response
                let score = scoreResponse(response, for: prompt)
                allResponses.append((model, response, score))
                
                if score >= qualityThreshold {
                    router.recordSuccess(model: model)
                    return EnsembleResult(
                        finalResponse: response,
                        selectedModel: model,
                        allResponses: allResponses,
                        mode: .cascade,
                        totalTime: Date().timeIntervalSince(startTime),
                        reasoning: "Cascade stopped at \(model.displayName) with score \(Int(score * 100))%"
                    )
                }
                
                router.recordFailure(model: model)
                
            } catch {
                allResponses.append((model, "Error: \(error.localizedDescription)", 0))
                continue
            }
        }
        
        // Return best response if none met threshold
        let best = allResponses.max(by: { $0.2 < $1.2 }) ?? allResponses.first!
        
        return EnsembleResult(
            finalResponse: best.1,
            selectedModel: best.0,
            allResponses: allResponses,
            mode: .cascade,
            totalTime: Date().timeIntervalSince(startTime),
            reasoning: "No model met quality threshold. Best: \(best.0.displayName) (\(Int(best.2 * 100))%)"
        )
    }
    
    // MARK: - Parallel Mode (Best of N)
    
    /// Run multiple models in parallel, select best response
    public func runParallel(
        prompt: String,
        models: [Model],
        onProgress: @escaping @MainActor (Model, String) -> Void
    ) async throws -> EnsembleResult {
        let startTime = Date()
        
        currentPhase = "Running \(models.count) models in parallel"
        
        // Run all models concurrently
        let results = await withTaskGroup(of: (Model, String, Float)?.self) { group in
            for model in models {
                group.addTask {
                    do {
                        let engine = try await self.getEngine(for: model)
                        var response = ""
                        
                        _ = try await engine.generate(
                            prompt: prompt,
                            onToken: { token in
                                response = token
                                Task { @MainActor in
                                    onProgress(model, token)
                                }
                            }
                        )
                        
                        let score = self.scoreResponse(response, for: prompt)
                        return (model, response, score)
                    } catch {
                        return nil
                    }
                }
            }
            
            var results: [(Model, String, Float)] = []
            for await result in group {
                if let r = result {
                    results.append(r)
                }
            }
            return results
        }
        
        guard let best = results.max(by: { $0.2 < $1.2 }) else {
            throw BeastError.generationCancelled
        }
        
        router.recordSuccess(model: best.0)
        
        return EnsembleResult(
            finalResponse: best.1,
            selectedModel: best.0,
            allResponses: results,
            mode: .parallel,
            totalTime: Date().timeIntervalSince(startTime),
            reasoning: "Selected \(best.0.displayName) with highest score (\(Int(best.2 * 100))%)"
        )
    }
    
    // MARK: - Consensus Mode
    
    /// Run multiple models, find consensus or vote
    public func runConsensus(
        prompt: String,
        models: [Model],
        onProgress: @escaping @MainActor (Model, String) -> Void
    ) async throws -> EnsembleResult {
        let startTime = Date()
        
        // Get all responses
        let parallelResult = try await runParallel(
            prompt: prompt,
            models: models,
            onProgress: onProgress
        )
        
        let responses = parallelResult.allResponses
        
        // Find semantic similarity and consensus
        let synthesized = synthesizeConsensus(responses: responses.map { $0.1 })
        
        return EnsembleResult(
            finalResponse: synthesized,
            selectedModel: parallelResult.selectedModel,
            allResponses: responses,
            mode: .consensus,
            totalTime: Date().timeIntervalSince(startTime),
            reasoning: "Synthesized consensus from \(responses.count) model responses"
        )
    }
    
    // MARK: - Speculative Mode
    
    /// Use small model to draft, large model to verify/refine
    public func runSpeculative(
        prompt: String,
        draftModel: Model = .qwen3_4b,
        verifyModel: Model = .qwen3_8b,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws -> EnsembleResult {
        let startTime = Date()
        
        // Phase 1: Draft with small fast model
        currentPhase = "Drafting with \(draftModel.displayName)"
        progress = 0.3
        
        let draftEngine = try await getEngine(for: draftModel)
        draftEngine.setParams(.precise) // Low temp for consistent draft
        
        let draft = try await draftEngine.generate(prompt: prompt, onToken: { _ in })
        
        // Phase 2: Verify/refine with large model
        currentPhase = "Refining with \(verifyModel.displayName)"
        progress = 0.6
        
        let verifyEngine = try await getEngine(for: verifyModel)
        
        let refinementPrompt = """
        Review and improve this response if needed. Keep it if it's already good.
        
        Original question: \(prompt)
        
        Draft response: \(draft)
        
        Provide the final response (improved or unchanged):
        """
        
        let refined = try await verifyEngine.generate(prompt: refinementPrompt, onToken: onToken)
        
        progress = 1.0
        
        return EnsembleResult(
            finalResponse: refined,
            selectedModel: verifyModel,
            allResponses: [
                (draftModel, draft, 0.7),
                (verifyModel, refined, 1.0)
            ],
            mode: .speculative,
            totalTime: Date().timeIntervalSince(startTime),
            reasoning: "Drafted with \(draftModel.displayName), refined with \(verifyModel.displayName)"
        )
    }
    
    // MARK: - Engine Management
    
    private func getEngine(for model: Model) async throws -> BeastEngine {
        if let existing = engines[model] {
            return existing
        }
        
        let engine = BeastEngine(model: model, params: model.recommendedParams)
        try await engine.load(onProgress: { [weak self] p in
            Task { @MainActor in
                self?.currentPhase = p
            }
        })
        engines[model] = engine
        return engine
    }
    
    public func unloadAll() {
        for (_, engine) in engines {
            engine.unload()
        }
        engines.removeAll()
    }
    
    public func unload(model: Model) {
        engines[model]?.unload()
        engines.removeValue(forKey: model)
    }
    
    // MARK: - Response Scoring
    
    nonisolated private func scoreResponse(_ response: String, for prompt: String) -> Float {
        var score: Float = 0.5
        
        // Length check (not too short, not too long)
        let wordCount = response.split(separator: " ").count
        if wordCount > 20 { score += 0.1 }
        if wordCount > 50 { score += 0.1 }
        if wordCount < 10 { score -= 0.2 }
        
        // Coherence check (ends properly)
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") {
            score += 0.1
        }
        
        // Relevance check (contains prompt keywords)
        let promptWords = Set(prompt.lowercased().split(separator: " ").map(String.init))
        let responseWords = Set(response.lowercased().split(separator: " ").map(String.init))
        let overlap = promptWords.intersection(responseWords).count
        let relevance = Float(overlap) / Float(max(promptWords.count, 1))
        score += relevance * 0.2
        
        // Refusal detection (penalize)
        let refusalPhrases = ["i cannot", "i can't", "i'm unable", "as an ai", "i don't have"]
        for phrase in refusalPhrases {
            if response.lowercased().contains(phrase) {
                score -= 0.3
                break
            }
        }
        
        return max(0, min(1, score))
    }
    
    // MARK: - Consensus Synthesis
    
    private func synthesizeConsensus(responses: [String]) -> String {
        // Simple approach: return longest non-refusing response
        // Could be enhanced with actual semantic comparison
        
        let nonRefusing = responses.filter { response in
            let lower = response.lowercased()
            return !lower.contains("i cannot") && 
                   !lower.contains("i can't") &&
                   !lower.contains("i'm unable")
        }
        
        if let best = nonRefusing.max(by: { $0.count < $1.count }) {
            return best
        }
        
        return responses.first ?? ""
    }
}
