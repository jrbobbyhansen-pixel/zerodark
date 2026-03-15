import Foundation

// MARK: - Mixture of Experts

/// Route to specialized sub-models for specific tasks
/// Like having 8 specialized experts that activate on demand

public actor MixtureOfExperts {
    
    public static let shared = MixtureOfExperts()
    
    // MARK: - Expert Types
    
    public enum Expert: String, CaseIterable {
        case general = "general"
        case code = "code"
        case math = "math"
        case creative = "creative"
        case reasoning = "reasoning"
        case multilingual = "multilingual"
        case knowledge = "knowledge"
        case safety = "safety"
        
        public var displayName: String {
            rawValue.capitalized
        }
        
        /// Recommended model for this expert
        public var preferredModel: Model {
            switch self {
            case .general: return .qwen3_8b
            case .code: return .qwen25_coder_7b
            case .math: return .deepseek_r1_8b
            case .creative: return .qwen3_8b_abliterated
            case .reasoning: return .deepseek_r1_8b
            case .multilingual: return .qwen3_8b
            case .knowledge: return .qwen3_8b
            case .safety: return .qwen3_8b
            }
        }
        
        /// Keywords that activate this expert
        public var keywords: Set<String> {
            switch self {
            case .general:
                return []
            case .code:
                return ["code", "program", "function", "debug", "swift", "python", "javascript", "api", "implement", "algorithm", "compile", "syntax"]
            case .math:
                return ["calculate", "solve", "equation", "math", "number", "formula", "compute", "derivative", "integral", "statistics"]
            case .creative:
                return ["write", "story", "poem", "creative", "imagine", "fiction", "character", "narrative", "compose"]
            case .reasoning:
                return ["think", "reason", "analyze", "why", "explain", "logic", "deduce", "conclude", "argue", "proof"]
            case .multilingual:
                return ["translate", "spanish", "french", "german", "chinese", "japanese", "korean", "language", "foreign"]
            case .knowledge:
                return ["what is", "who is", "when did", "history", "fact", "define", "explain", "tell me about"]
            case .safety:
                return ["harmful", "dangerous", "illegal", "weapon", "drug", "hack", "exploit"]
            }
        }
    }
    
    // MARK: - Expert Selection
    
    private var loadedExperts: [Expert: BeastEngine] = [:]
    private var expertStats: [Expert: Int] = [:]  // Usage counts
    
    /// Select best expert for prompt
    public func selectExpert(_ prompt: String) -> Expert {
        let lowercased = prompt.lowercased()
        var scores: [Expert: Int] = [:]
        
        for expert in Expert.allCases {
            var score = 0
            for keyword in expert.keywords {
                if lowercased.contains(keyword) {
                    score += 1
                }
            }
            scores[expert] = score
        }
        
        // Get expert with highest score (default to general)
        let selected = scores.max(by: { $0.value < $1.value })?.key ?? .general
        
        // Update stats
        expertStats[selected, default: 0] += 1
        
        return selected
    }
    
    /// Get or load expert engine
    public func getExpert(_ expert: Expert) async throws -> BeastEngine {
        if let engine = loadedExperts[expert] {
            return engine
        }
        
        let engine = try await BeastEngine(model: expert.preferredModel)
        loadedExperts[expert] = engine
        
        return engine
    }
    
    /// Route and generate
    public func generate(
        _ prompt: String,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        // Select expert
        let expert = selectExpert(prompt)
        
        // Get engine
        let engine = try await getExpert(expert)
        
        // Add expert-specific system prompt
        let systemPrompt = expertSystemPrompt(expert)
        let fullPrompt = systemPrompt + "\n\nUser: " + prompt + "\n\nAssistant:"
        
        // Generate
        return try await engine.generate(prompt: fullPrompt, onToken: onToken)
    }
    
    private func expertSystemPrompt(_ expert: Expert) -> String {
        switch expert {
        case .general:
            return "You are a helpful, harmless, and honest AI assistant."
        case .code:
            return "You are an expert programmer. Write clean, efficient, well-documented code. Explain your approach."
        case .math:
            return "You are a mathematician. Show your work step by step. Use clear notation."
        case .creative:
            return "You are a creative writer. Be imaginative, evocative, and engaging. Take risks with language."
        case .reasoning:
            return "You are a logical thinker. Analyze step by step. Consider multiple perspectives. Show your reasoning."
        case .multilingual:
            return "You are a skilled translator and linguist. Preserve meaning and tone across languages."
        case .knowledge:
            return "You are a knowledgeable assistant. Provide accurate, well-sourced information. Cite when possible."
        case .safety:
            return "You are a safety-focused assistant. Refuse harmful requests politely. Suggest safe alternatives."
        }
    }
    
    // MARK: - Dynamic Expert Activation
    
    /// Top-K expert routing (like Mixtral)
    public func topKExperts(_ prompt: String, k: Int = 2) -> [Expert] {
        let lowercased = prompt.lowercased()
        var scores: [(Expert, Int)] = []
        
        for expert in Expert.allCases {
            var score = 0
            for keyword in expert.keywords {
                if lowercased.contains(keyword) {
                    score += 1
                }
            }
            scores.append((expert, score))
        }
        
        return scores
            .sorted { $0.1 > $1.1 }
            .prefix(k)
            .map { $0.0 }
    }
    
    /// Ensemble generation (combine multiple expert outputs)
    public func ensembleGenerate(
        _ prompt: String,
        experts: [Expert]
    ) async throws -> String {
        // Generate from each expert
        var outputs: [String] = []
        
        for expert in experts {
            let engine = try await getExpert(expert)
            let output = try await engine.generate(prompt: prompt) { _ in }
            outputs.append("[\(expert.displayName)]: \(output)")
        }
        
        // Combine (simple concatenation - could use voting/consensus)
        return outputs.joined(separator: "\n\n")
    }
    
    // MARK: - Stats
    
    public var stats: [(Expert, Int)] {
        expertStats.sorted { $0.value > $1.value }
    }
}
