import Foundation
import NaturalLanguage

// MARK: - Model Router

/// Intelligent model selection based on task analysis, device capabilities, and user patterns
@MainActor
public final class ModelRouter: ObservableObject {
    
    public static let shared = ModelRouter()
    
    // MARK: - Task Types
    
    public enum TaskType: String, CaseIterable {
        case code = "Code Generation"
        case reasoning = "Complex Reasoning"
        case uncensored = "Uncensored/Unrestricted"
        case vision = "Image Analysis"
        case toolUse = "Tool/Function Calling"
        case creative = "Creative Writing"
        case roleplay = "Roleplay/Character"
        case translation = "Translation"
        case summarization = "Summarization"
        case math = "Mathematics"
        case general = "General Chat"
        
        public var icon: String {
            switch self {
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .reasoning: return "brain"
            case .uncensored: return "lock.open"
            case .vision: return "eye"
            case .toolUse: return "wrench.and.screwdriver"
            case .creative: return "paintbrush"
            case .roleplay: return "theatermasks"
            case .translation: return "globe"
            case .summarization: return "doc.text"
            case .math: return "function"
            case .general: return "bubble.left"
            }
        }
    }
    
    // MARK: - Device Tier
    
    public enum DeviceTier: Comparable {
        case constrained   // 4GB - iPad base, older devices
        case standard      // 8GB - iPhone 16 Pro Max, iPad Air
        case performance   // 16GB - iPad Pro M4, Macs
        case unlimited     // 32GB+ - High-end Macs
        
        public var maxModelSize: Int {
            switch self {
            case .constrained: return 3_000   // 3B max
            case .standard: return 5_000      // 8B max (4.5GB)
            case .performance: return 9_000   // 14B max (8GB)
            case .unlimited: return 20_000    // 32B+ possible
            }
        }
        
        public var displayName: String {
            switch self {
            case .constrained: return "Constrained (≤4GB)"
            case .standard: return "Standard (8GB)"
            case .performance: return "Performance (16GB)"
            case .unlimited: return "Unlimited (32GB+)"
            }
        }
    }
    
    // MARK: - Routing Decision
    
    public struct RoutingDecision {
        public let selectedModel: Model
        public let taskType: TaskType
        public let confidence: Float
        public let reasoning: String
        public let alternatives: [Model]
        public let params: BeastModeParams
    }
    
    // MARK: - State
    
    @Published public private(set) var deviceTier: DeviceTier = .standard
    @Published public private(set) var availableModels: [Model] = []
    @Published public var autoRouting: Bool = true
    @Published public var preferUncensored: Bool = false
    
    // Pattern learning
    private var taskHistory: [TaskType: Int] = [:]
    private var modelPerformance: [Model: (successes: Int, failures: Int)] = [:]
    
    // MARK: - Init
    
    private init() {
        detectDeviceTier()
        updateAvailableModels()
    }
    
    // MARK: - Device Detection
    
    public func detectDeviceTier() {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let memoryGB = Int(physicalMemory / 1024 / 1024 / 1024)
        
        switch memoryGB {
        case 0..<6:
            deviceTier = .constrained
        case 6..<12:
            deviceTier = .standard
        case 12..<24:
            deviceTier = .performance
        default:
            deviceTier = .unlimited
        }
        
        updateAvailableModels()
    }
    
    // MARK: - Available Models
    
    private func updateAvailableModels() {
        let maxSize = deviceTier.maxModelSize
        availableModels = Model.allCases.filter { $0.approximateSizeMB <= maxSize }
    }
    
    // MARK: - Task Classification
    
    public func classifyTask(_ prompt: String, hasImages: Bool = false) -> (TaskType, Float) {
        // Vision takes priority if images present
        if hasImages {
            return (.vision, 0.95)
        }
        
        let lowercased = prompt.lowercased()
        
        // Code detection
        let codeIndicators = [
            "code", "function", "implement", "debug", "fix this",
            "write a script", "programming", "algorithm", "```",
            "swift", "python", "javascript", "typescript", "rust",
            "class", "struct", "def ", "func ", "const ", "let ",
            "compile", "runtime", "syntax", "api", "sdk"
        ]
        let codeScore = codeIndicators.reduce(0.0) { score, word in
            lowercased.contains(word) ? score + 0.15 : score
        }
        if codeScore > 0.4 { return (.code, min(Float(codeScore), 0.95)) }
        
        // Uncensored detection
        let uncensoredIndicators = [
            "no restrictions", "uncensored", "without limits",
            "don't refuse", "bypass", "jailbreak", "unrestricted",
            "pretend you can", "ignore your", "act as if",
            "hypothetically", "for fiction", "roleplay as",
            "controversial", "offensive", "explicit"
        ]
        let uncensoredScore = uncensoredIndicators.reduce(0.0) { score, phrase in
            lowercased.contains(phrase) ? score + 0.2 : score
        }
        if uncensoredScore > 0.3 || preferUncensored { 
            return (.uncensored, min(Float(uncensoredScore) + 0.3, 0.95)) 
        }
        
        // Reasoning detection
        let reasoningIndicators = [
            "think step by step", "reason through", "analyze",
            "why does", "explain why", "logic", "prove",
            "consider", "evaluate", "compare and contrast",
            "what if", "implications", "deduce", "infer"
        ]
        let reasoningScore = reasoningIndicators.reduce(0.0) { score, phrase in
            lowercased.contains(phrase) ? score + 0.15 : score
        }
        if reasoningScore > 0.3 { return (.reasoning, min(Float(reasoningScore), 0.9)) }
        
        // Math detection
        let mathIndicators = [
            "calculate", "solve", "equation", "math",
            "derivative", "integral", "sum of", "probability",
            "statistics", "algebra", "geometry", "compute"
        ]
        let mathScore = mathIndicators.reduce(0.0) { score, word in
            lowercased.contains(word) ? score + 0.2 : score
        }
        if mathScore > 0.3 { return (.math, min(Float(mathScore), 0.9)) }
        
        // Creative/Roleplay detection
        let creativeIndicators = [
            "write a story", "poem", "creative", "imagine",
            "fiction", "narrative", "character", "dialogue"
        ]
        let roleplayIndicators = [
            "act as", "you are", "pretend to be", "roleplay",
            "in character", "respond as", "speak like"
        ]
        
        let creativeScore = creativeIndicators.reduce(0.0) { score, phrase in
            lowercased.contains(phrase) ? score + 0.2 : score
        }
        let roleplayScore = roleplayIndicators.reduce(0.0) { score, phrase in
            lowercased.contains(phrase) ? score + 0.2 : score
        }
        
        if roleplayScore > 0.3 { return (.roleplay, min(Float(roleplayScore), 0.9)) }
        if creativeScore > 0.3 { return (.creative, min(Float(creativeScore), 0.9)) }
        
        // Translation detection
        let translationIndicators = [
            "translate", "in spanish", "in french", "in german",
            "in chinese", "in japanese", "to english", "from english"
        ]
        let translationScore = translationIndicators.reduce(0.0) { score, phrase in
            lowercased.contains(phrase) ? score + 0.3 : score
        }
        if translationScore > 0.3 { return (.translation, min(Float(translationScore), 0.9)) }
        
        // Summarization detection
        let summarizeIndicators = [
            "summarize", "summary", "tldr", "brief", "key points",
            "main ideas", "condense", "shorten"
        ]
        let summarizeScore = summarizeIndicators.reduce(0.0) { score, phrase in
            lowercased.contains(phrase) ? score + 0.25 : score
        }
        if summarizeScore > 0.3 { return (.summarization, min(Float(summarizeScore), 0.9)) }
        
        // Tool use detection
        let toolIndicators = [
            "call function", "use tool", "execute", "run command",
            "api call", "json", "structured output"
        ]
        let toolScore = toolIndicators.reduce(0.0) { score, phrase in
            lowercased.contains(phrase) ? score + 0.2 : score
        }
        if toolScore > 0.3 { return (.toolUse, min(Float(toolScore), 0.85)) }
        
        // Default to general
        return (.general, 0.6)
    }
    
    // MARK: - Model Selection
    
    public func selectModel(for taskType: TaskType) -> Model {
        // Filter by device capability
        let candidates = availableModels
        
        // Task-specific preferences
        let preferred: [Model]
        
        switch taskType {
        case .code:
            preferred = [.qwen25_coder_7b, .deepcoder_8b, .qwen3_8b]
            
        case .reasoning:
            preferred = [.deepseek_r1_8b, .qwen3_8b, .llama3_1_8b]
            
        case .uncensored:
            preferred = [.qwen3_8b_abliterated, .hermes3_8b, .qwen3_8b]
            
        case .vision:
            preferred = [.qwen3_vl_8b, .qwen35_2b, .smolvlm_2b]
            
        case .toolUse:
            preferred = [.llama3_groq_8b, .qwen3_8b, .llama3_1_8b]
            
        case .creative, .roleplay:
            preferred = [.hermes3_8b, .qwen3_8b_abliterated, .qwen3_8b]
            
        case .translation:
            preferred = [.qwen3_8b, .llama3_1_8b, .ministral_8b]
            
        case .summarization:
            preferred = [.qwen3_8b, .ministral_8b, .llama3_1_8b]
            
        case .math:
            preferred = [.deepseek_r1_8b, .qwen3_8b, .qwen25_coder_7b]
            
        case .general:
            preferred = [.qwen3_8b, .llama3_1_8b, .ministral_8b]
        }
        
        // Find first available preferred model
        for model in preferred {
            if candidates.contains(model) {
                return model
            }
        }
        
        // Fallback to best available
        return candidates.first { $0.approximateSizeMB > 2000 } 
            ?? candidates.first 
            ?? .qwen3_4b
    }
    
    // MARK: - Full Routing
    
    public func route(
        prompt: String,
        hasImages: Bool = false,
        forceModel: Model? = nil
    ) -> RoutingDecision {
        // Allow manual override
        if let forced = forceModel {
            return RoutingDecision(
                selectedModel: forced,
                taskType: .general,
                confidence: 1.0,
                reasoning: "Model manually selected",
                alternatives: [],
                params: forced.recommendedParams
            )
        }
        
        // Classify task
        let (taskType, confidence) = classifyTask(prompt, hasImages: hasImages)
        
        // Select optimal model
        let selectedModel = selectModel(for: taskType)
        
        // Find alternatives
        let alternatives = availableModels
            .filter { $0 != selectedModel }
            .sorted { $0.approximateSizeMB > $1.approximateSizeMB }
            .prefix(3)
        
        // Get recommended params
        var params = selectedModel.recommendedParams
        
        // Task-specific param adjustments
        switch taskType {
        case .code:
            params.temperature = 0.2
            params.maxTokens = 4096
        case .reasoning:
            params.enableThinking = true
            params.thinkingBudget = 2048
        case .creative, .roleplay:
            params.temperature = 1.0
            params.topP = 0.98
        case .uncensored:
            params = .uncensored
        default:
            break
        }
        
        // Build reasoning explanation
        let reasoning = buildReasoning(taskType: taskType, model: selectedModel, confidence: confidence)
        
        // Track for learning
        taskHistory[taskType, default: 0] += 1
        
        return RoutingDecision(
            selectedModel: selectedModel,
            taskType: taskType,
            confidence: confidence,
            reasoning: reasoning,
            alternatives: Array(alternatives),
            params: params
        )
    }
    
    private func buildReasoning(taskType: TaskType, model: Model, confidence: Float) -> String {
        let confPercent = Int(confidence * 100)
        return "Detected \(taskType.rawValue) task (\(confPercent)% confidence). " +
               "Selected \(model.displayName) — optimized for this task type. " +
               "Device tier: \(deviceTier.displayName)."
    }
    
    // MARK: - Learning
    
    public func recordSuccess(model: Model) {
        var perf = modelPerformance[model, default: (0, 0)]
        perf.successes += 1
        modelPerformance[model] = perf
    }
    
    public func recordFailure(model: Model) {
        var perf = modelPerformance[model, default: (0, 0)]
        perf.failures += 1
        modelPerformance[model] = perf
    }
    
    public func successRate(for model: Model) -> Float? {
        guard let perf = modelPerformance[model] else { return nil }
        let total = perf.successes + perf.failures
        guard total > 0 else { return nil }
        return Float(perf.successes) / Float(total)
    }
}
