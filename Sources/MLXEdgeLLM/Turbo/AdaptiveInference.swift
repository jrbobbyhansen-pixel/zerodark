import Foundation

// MARK: - Adaptive Inference

/// Dynamically adjust inference parameters based on device state
/// Battery, thermal, memory pressure, user urgency

public actor AdaptiveInference {
    
    public static let shared = AdaptiveInference()
    
    // MARK: - Quality Levels
    
    public enum QualityLevel: Int, CaseIterable {
        case turbo = 0      // Maximum speed, minimum quality
        case fast = 1       // Speed-optimized
        case balanced = 2   // Default
        case quality = 3    // Quality-optimized
        case maximum = 4    // Maximum quality, slower
        
        public var displayName: String {
            switch self {
            case .turbo: return "Turbo"
            case .fast: return "Fast"
            case .balanced: return "Balanced"
            case .quality: return "Quality"
            case .maximum: return "Maximum"
            }
        }
        
        /// Recommended model size for this level
        public var maxModelSizeGB: Double {
            switch self {
            case .turbo: return 1.0
            case .fast: return 2.5
            case .balanced: return 4.5
            case .quality: return 7.5
            case .maximum: return 15.0
            }
        }
        
        /// Temperature adjustment
        public var temperatureMultiplier: Float {
            switch self {
            case .turbo: return 0.8
            case .fast: return 0.9
            case .balanced: return 1.0
            case .quality: return 1.0
            case .maximum: return 1.0
            }
        }
        
        /// Max tokens multiplier
        public var maxTokensMultiplier: Float {
            switch self {
            case .turbo: return 0.5
            case .fast: return 0.75
            case .balanced: return 1.0
            case .quality: return 1.25
            case .maximum: return 1.5
            }
        }
    }
    
    // MARK: - State
    
    @Published public var currentLevel: QualityLevel = .balanced
    @Published public var isAutomatic: Bool = true
    
    private var lastAssessment: Date?
    private let assessmentInterval: TimeInterval = 30 // Reassess every 30 seconds
    
    // MARK: - Assess Conditions
    
    public func assessAndAdjust() async -> QualityLevel {
        // Rate limit assessments
        if let last = lastAssessment, Date().timeIntervalSince(last) < assessmentInterval {
            return currentLevel
        }
        lastAssessment = Date()
        
        guard isAutomatic else { return currentLevel }
        
        // Gather device state
        let battery = await getBatteryLevel()
        let thermal = await getThermalState()
        let memory = await getMemoryPressure()
        let power = await getPowerState()
        
        // Score-based assessment
        var score = 2 // Start at balanced
        
        // Battery adjustments
        switch battery {
        case ..<0.1:
            score -= 2  // Critical battery
        case 0.1..<0.2:
            score -= 1  // Low battery
        case 0.8...:
            score += 1  // High battery
        default:
            break
        }
        
        // Thermal adjustments
        switch thermal {
        case .critical:
            score -= 2
        case .serious:
            score -= 1
        case .nominal:
            score += 1
        default:
            break
        }
        
        // Memory adjustments
        switch memory {
        case .critical, .terminal:
            score -= 2
        case .warning:
            score -= 1
        case .normal:
            break
        }
        
        // Power state adjustments
        if power == .charging || power == .full {
            score += 1
        }
        
        // Clamp to valid range
        let clampedScore = max(0, min(4, score))
        currentLevel = QualityLevel(rawValue: clampedScore) ?? .balanced
        
        return currentLevel
    }
    
    // MARK: - Device State Queries
    
    private func getBatteryLevel() async -> Float {
        #if os(iOS)
        await MainActor.run {
            UIDevice.current.isBatteryMonitoringEnabled = true
            return UIDevice.current.batteryLevel
        }
        #else
        return 1.0 // Assume full on Mac
        #endif
    }
    
    private func getThermalState() async -> ProcessInfo.ThermalState {
        ProcessInfo.processInfo.thermalState
    }
    
    private func getMemoryPressure() async -> SystemMonitor.MemoryPressure {
        await SystemMonitor.shared.memoryPressure
    }
    
    private enum PowerState {
        case unplugged, charging, full, unknown
    }
    
    private func getPowerState() async -> PowerState {
        #if os(iOS)
        return await MainActor.run {
            UIDevice.current.isBatteryMonitoringEnabled = true
            switch UIDevice.current.batteryState {
            case .charging: return .charging
            case .full: return .full
            case .unplugged: return .unplugged
            default: return .unknown
            }
        }
        #else
        return .full // Assume plugged in on Mac
        #endif
    }
    
    // MARK: - Get Optimal Model
    
    public func getOptimalModel(for task: ModelRouter.TaskType) async -> Model {
        let level = await assessAndAdjust()
        let maxSize = level.maxModelSizeGB * 1000 // Convert to MB
        
        // Get available models within size budget
        let available = Model.allCases.filter { 
            Double($0.approximateSizeMB) <= maxSize 
        }
        
        // Route based on task
        let router = await ModelRouter.shared
        let decision = await router.route(prompt: "", taskType: task, forceModel: nil)
        
        // If recommended model is within budget, use it
        if available.contains(decision.selectedModel) {
            return decision.selectedModel
        }
        
        // Otherwise, use largest available
        return available.max(by: { $0.approximateSizeMB < $1.approximateSizeMB }) ?? .qwen3_0_6b
    }
    
    // MARK: - Adjust Parameters
    
    public func adjustParameters(_ params: inout BeastParams) async {
        let level = await assessAndAdjust()
        
        // Adjust temperature
        params.temperature *= level.temperatureMultiplier
        
        // Adjust max tokens
        params.maxTokens = Int(Float(params.maxTokens) * level.maxTokensMultiplier)
        
        // Adjust top-p for speed
        if level == .turbo || level == .fast {
            params.topP = min(params.topP, 0.8) // More deterministic = faster
        }
    }
}

// MARK: - Batch Inference

/// Process multiple prompts efficiently
public actor BatchInference {
    
    public static let shared = BatchInference()
    
    public struct BatchRequest {
        public let id: String
        public let prompt: String
        public let model: Model?
        public let priority: Int
        
        public init(id: String = UUID().uuidString, prompt: String, model: Model? = nil, priority: Int = 0) {
            self.id = id
            self.prompt = prompt
            self.model = model
            self.priority = priority
        }
    }
    
    public struct BatchResult {
        public let id: String
        public let response: String
        public let error: Error?
        public let latencyMs: Int
    }
    
    /// Process batch with automatic parallelization
    public func processBatch(
        _ requests: [BatchRequest],
        maxConcurrent: Int = 2
    ) async -> [BatchResult] {
        // Sort by priority
        let sorted = requests.sorted { $0.priority > $1.priority }
        
        var results: [BatchResult] = []
        
        // Process in chunks
        for chunk in sorted.chunked(into: maxConcurrent) {
            let chunkResults = await withTaskGroup(of: BatchResult.self) { group in
                for request in chunk {
                    group.addTask {
                        await self.processOne(request)
                    }
                }
                
                var collected: [BatchResult] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }
            
            results.append(contentsOf: chunkResults)
        }
        
        return results
    }
    
    private func processOne(_ request: BatchRequest) async -> BatchResult {
        let start = Date()
        
        do {
            let ai = await ZeroDarkAI.shared
            let response = try await ai.generate(
                request.prompt,
                model: request.model,
                stream: false
            )
            
            let latency = Int(Date().timeIntervalSince(start) * 1000)
            return BatchResult(id: request.id, response: response, error: nil, latencyMs: latency)
        } catch {
            let latency = Int(Date().timeIntervalSince(start) * 1000)
            return BatchResult(id: request.id, response: "", error: error, latencyMs: latency)
        }
    }
}

// MARK: - Array Extension

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
