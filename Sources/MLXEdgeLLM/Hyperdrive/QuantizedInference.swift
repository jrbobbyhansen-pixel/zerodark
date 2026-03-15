import Foundation
import MLX
import Accelerate

// MARK: - Quantized Inference

/// 2-bit, 3-bit, 4-bit quantization for maximum efficiency
/// Run 14B models in 4GB RAM

public actor QuantizedInference {
    
    public static let shared = QuantizedInference()
    
    // MARK: - Quantization Levels
    
    public enum QuantLevel: Int, CaseIterable {
        case q2 = 2   // 2-bit: Smallest, fastest, lower quality
        case q3 = 3   // 3-bit: Good balance for constrained devices
        case q4 = 4   // 4-bit: Standard, great quality
        case q5 = 5   // 5-bit: High quality
        case q6 = 6   // 6-bit: Near-lossless
        case q8 = 8   // 8-bit: Maximum quality
        case f16 = 16 // FP16: Full precision
        
        public var displayName: String {
            switch self {
            case .q2: return "Q2 (Ultra-Fast)"
            case .q3: return "Q3 (Fast)"
            case .q4: return "Q4 (Balanced)"
            case .q5: return "Q5 (Quality)"
            case .q6: return "Q6 (High)"
            case .q8: return "Q8 (Maximum)"
            case .f16: return "FP16 (Full)"
            }
        }
        
        /// Memory multiplier relative to FP16
        public var memoryMultiplier: Float {
            Float(rawValue) / 16.0
        }
        
        /// Speed multiplier relative to FP16
        public var speedMultiplier: Float {
            switch self {
            case .q2: return 4.0
            case .q3: return 3.2
            case .q4: return 2.5
            case .q5: return 2.0
            case .q6: return 1.6
            case .q8: return 1.3
            case .f16: return 1.0
            }
        }
        
        /// Quality score (0-1)
        public var qualityScore: Float {
            switch self {
            case .q2: return 0.70
            case .q3: return 0.80
            case .q4: return 0.90
            case .q5: return 0.94
            case .q6: return 0.97
            case .q8: return 0.99
            case .f16: return 1.00
            }
        }
    }
    
    // MARK: - Model Sizes at Different Quants
    
    public struct QuantizedSize {
        public let model: Model
        public let level: QuantLevel
        public let sizeMB: Int
        public let ramRequiredMB: Int
        
        public static func calculate(model: Model, level: QuantLevel) -> QuantizedSize {
            let baseSizeMB = model.approximateSizeMB
            let quantizedSize = Int(Float(baseSizeMB) * level.memoryMultiplier)
            let ramRequired = Int(Float(quantizedSize) * 1.2) // 20% overhead
            
            return QuantizedSize(
                model: model,
                level: level,
                sizeMB: quantizedSize,
                ramRequiredMB: ramRequired
            )
        }
    }
    
    /// What can run on this device?
    public func availableConfigs(ramMB: Int) -> [(Model, QuantLevel)] {
        var configs: [(Model, QuantLevel)] = []
        
        for model in Model.allCases {
            for level in QuantLevel.allCases {
                let size = QuantizedSize.calculate(model: model, level: level)
                if size.ramRequiredMB <= ramMB {
                    configs.append((model, level))
                }
            }
        }
        
        // Sort by quality (model size * quant quality)
        return configs.sorted { 
            Float($0.0.approximateSizeMB) * $0.1.qualityScore >
            Float($1.0.approximateSizeMB) * $1.1.qualityScore
        }
    }
    
    /// Best model for given RAM
    public func bestModel(ramMB: Int) -> (Model, QuantLevel)? {
        availableConfigs(ramMB: ramMB).first
    }
}

// MARK: - Constrained Device Configs

public extension QuantizedInference {
    
    /// iPhone SE / iPad mini (4GB)
    static var constrainedConfig: [(Model, QuantLevel)] {
        [
            (.qwen3_4b, .q4),      // 2.0GB - Best quality for 4GB
            (.qwen3_4b, .q3),      // 1.5GB - Faster
            (.qwen3_4b, .q2),      // 1.0GB - Fastest
            (.llama32_3b, .q4),    // 1.5GB - Alternative
            (.qwen3_1_7b, .q4),    // 0.9GB - Tiny but capable
        ]
    }
    
    /// iPhone 15/16 Pro (8GB)
    static var standardConfig: [(Model, QuantLevel)] {
        [
            (.qwen3_8b, .q4),      // 4.0GB - Best for 8GB
            (.qwen3_8b, .q3),      // 3.0GB - Faster
            (.deepseek_r1_8b, .q4),// 4.0GB - Reasoning
            (.qwen25_coder_7b, .q4),// 3.5GB - Code
        ]
    }
    
    /// iPad Pro M4 / Mac (16GB+)
    static var performanceConfig: [(Model, QuantLevel)] {
        [
            (.qwen25_14b, .q4),    // 7.0GB - Best 14B
            (.qwen25_14b, .q5),    // 8.8GB - Higher quality
            (.qwen3_14b, .q4),     // 7.0GB - Latest Qwen
            (.deepseek_r1_14b, .q4),// 7.0GB - Reasoning
            (.qwen3_8b, .q8),      // 8.0GB - Max quality 8B
        ]
    }
    
    /// Mac Studio / Pro (32GB+)
    static var unlimitedConfig: [(Model, QuantLevel)] {
        [
            (.qwen25_14b, .f16),   // 28GB - Full precision
            (.qwen25_14b, .q8),    // 14GB - Near-lossless
            (.qwen3_14b, .q8),     // 14GB
            // Could add 32B, 70B models here
        ]
    }
}
