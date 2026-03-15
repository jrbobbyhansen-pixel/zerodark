import Foundation
#if os(iOS)
import UIKit
#endif

// MARK: - Adaptive Inference

/// Dynamically adjust inference parameters based on device state
/// Battery, thermal, memory pressure, user urgency

public actor AdaptiveInference {
    
    public static let shared = AdaptiveInference()
    
    // MARK: - Quality Levels
    
    public enum QualityLevel: Int, CaseIterable, Sendable {
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
        
        /// Recommended model size for this level (MB)
        public var maxModelSizeMB: Int {
            switch self {
            case .turbo: return 1000
            case .fast: return 2500
            case .balanced: return 4500
            case .quality: return 7500
            case .maximum: return 15000
            }
        }
    }
    
    // MARK: - State
    
    public var currentLevel: QualityLevel = .balanced
    public var isAutomatic: Bool = true
    
    private var lastAssessment: Date?
    private let assessmentInterval: TimeInterval = 30
    
    // MARK: - Assess Conditions
    
    public func assessAndAdjust() async -> QualityLevel {
        if let last = lastAssessment, Date().timeIntervalSince(last) < assessmentInterval {
            return currentLevel
        }
        lastAssessment = Date()
        
        guard isAutomatic else { return currentLevel }
        
        let battery = await getBatteryLevel()
        let thermal = getThermalState()
        
        var score = 2 // Start balanced
        
        // Battery adjustments
        if battery < 0.1 { score -= 2 }
        else if battery < 0.2 { score -= 1 }
        else if battery > 0.8 { score += 1 }
        
        // Thermal adjustments
        switch thermal {
        case .critical: score -= 2
        case .serious: score -= 1
        case .nominal: score += 1
        default: break
        }
        
        let clampedScore = max(0, min(4, score))
        currentLevel = QualityLevel(rawValue: clampedScore) ?? .balanced
        
        return currentLevel
    }
    
    // MARK: - Device State
    
    private func getBatteryLevel() async -> Float {
        #if os(iOS)
        return await MainActor.run {
            UIDevice.current.isBatteryMonitoringEnabled = true
            return UIDevice.current.batteryLevel
        }
        #else
        return 1.0
        #endif
    }
    
    private func getThermalState() -> ProcessInfo.ThermalState {
        ProcessInfo.processInfo.thermalState
    }
    
    // MARK: - Get Optimal Model
    
    public func getOptimalModel() async -> Model {
        let level = await assessAndAdjust()
        let maxSize = level.maxModelSizeMB
        
        let available = Model.allCases.filter { $0.approximateSizeMB <= maxSize }
        return available.max(by: { $0.approximateSizeMB < $1.approximateSizeMB }) ?? .qwen3_0_6b
    }
}

// MARK: - Batch Inference

public actor BatchInference {
    
    public static let shared = BatchInference()
    
    public struct BatchRequest: Sendable {
        public let id: String
        public let prompt: String
        public let priority: Int
        
        public init(id: String = UUID().uuidString, prompt: String, priority: Int = 0) {
            self.id = id
            self.prompt = prompt
            self.priority = priority
        }
    }
    
    public struct BatchResult: Sendable {
        public let id: String
        public let response: String
        public let error: String?
        public let latencyMs: Int
    }
    
    public func processBatch(_ requests: [BatchRequest]) async -> [BatchResult] {
        var results: [BatchResult] = []
        
        for request in requests.sorted(by: { $0.priority > $1.priority }) {
            let start = Date()
            var response = ""
            var errorMsg: String? = nil
            
            do {
                let ai = await ZeroDarkAI.shared
                response = try await ai.process(
                    prompt: request.prompt,
                    onToken: { _ in }
                )
            } catch {
                errorMsg = error.localizedDescription
            }
            
            let latency = Int(Date().timeIntervalSince(start) * 1000)
            results.append(BatchResult(
                id: request.id,
                response: response,
                error: errorMsg,
                latencyMs: latency
            ))
        }
        
        return results
    }
}
