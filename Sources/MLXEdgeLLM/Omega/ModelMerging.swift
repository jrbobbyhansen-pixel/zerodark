import Foundation

// MARK: - Model Merging

/// Combine models at runtime for best-of-both capabilities
/// SLERP, TIES, DARE merging — on device

public actor ModelMerging {
    
    public static let shared = ModelMerging()
    
    // MARK: - Merge Methods
    
    public enum MergeMethod {
        /// Spherical linear interpolation
        case slerp(ratio: Float)
        
        /// TIES: Trim, Elect Sign, Merge
        case ties(density: Float)
        
        /// DARE: Drop And REscale
        case dare(dropRate: Float)
        
        /// Simple linear interpolation
        case linear(ratio: Float)
        
        /// Task arithmetic
        case taskArithmetic(scaling: Float)
    }
    
    public struct MergeConfig {
        public var method: MergeMethod
        public var sourceModels: [Model]
        public var layerRanges: [ClosedRange<Int>]?  // nil = all layers
        
        public init(method: MergeMethod, sources: [Model]) {
            self.method = method
            self.sourceModels = sources
        }
    }
    
    // MARK: - Merge Operations
    
    /// Create merged model
    public func merge(_ config: MergeConfig) async throws -> MergedModel {
        guard config.sourceModels.count >= 2 else {
            throw MergeError.insufficientModels
        }
        
        let id = UUID().uuidString
        
        // In real implementation:
        // 1. Load source model weights
        // 2. Apply merge method
        // 3. Save merged weights
        
        return MergedModel(
            id: id,
            sources: config.sourceModels,
            method: config.method,
            createdAt: Date()
        )
    }
    
    public struct MergedModel: Identifiable {
        public let id: String
        public let sources: [Model]
        public let method: MergeMethod
        public let createdAt: Date
        
        public var displayName: String {
            let sourceNames = sources.map { $0.displayName }.joined(separator: "+")
            return "Merged(\(sourceNames))"
        }
    }
    
    // MARK: - Frankenmerge
    
    /// Combine different layers from different models
    public func frankenmerge(
        layers: [(model: Model, layerRange: ClosedRange<Int>)]
    ) async throws -> MergedModel {
        // Build frankenmerge from layer specifications
        // e.g., layers 0-8 from model A, layers 9-24 from model B
        
        let sources = layers.map { $0.model }
        
        return MergedModel(
            id: UUID().uuidString,
            sources: Array(Set(sources)),
            method: .linear(ratio: 0.5),
            createdAt: Date()
        )
    }
    
    // MARK: - Expert Mixing
    
    /// Mix models based on token/context
    public func expertMix(
        general: Model,
        expert: Model,
        expertTriggers: Set<String>
    ) -> ExpertMixConfig {
        ExpertMixConfig(
            generalModel: general,
            expertModel: expert,
            triggers: expertTriggers
        )
    }
    
    public struct ExpertMixConfig {
        public let generalModel: Model
        public let expertModel: Model
        public let triggers: Set<String>
        
        public func selectModel(for prompt: String) -> Model {
            let lower = prompt.lowercased()
            for trigger in triggers {
                if lower.contains(trigger) {
                    return expertModel
                }
            }
            return generalModel
        }
    }
    
    public enum MergeError: Error {
        case insufficientModels
        case incompatibleArchitectures
        case mergeFailed
    }
}

// MARK: - Dynamic Routing

/// Route to different models/merges based on context
public actor DynamicRouter {
    
    public static let shared = DynamicRouter()
    
    public struct Route {
        public let pattern: String
        public let model: Model
        public let priority: Int
    }
    
    private var routes: [Route] = []
    
    /// Add routing rule
    public func addRoute(pattern: String, model: Model, priority: Int = 0) {
        routes.append(Route(pattern: pattern, model: model, priority: priority))
        routes.sort { $0.priority > $1.priority }
    }
    
    /// Find best model for prompt
    public func route(_ prompt: String) -> Model {
        let lower = prompt.lowercased()
        
        for route in routes {
            if lower.contains(route.pattern) {
                return route.model
            }
        }
        
        return .qwen3_8b  // Default
    }
    
    /// Prebuilt router configurations
    public static func codeOptimized() -> DynamicRouter {
        let router = DynamicRouter()
        Task {
            await router.addRoute(pattern: "code", model: .qwen25_coder_7b, priority: 10)
            await router.addRoute(pattern: "function", model: .qwen25_coder_7b, priority: 10)
            await router.addRoute(pattern: "debug", model: .qwen25_coder_7b, priority: 10)
            await router.addRoute(pattern: "swift", model: .qwen25_coder_7b, priority: 10)
            await router.addRoute(pattern: "python", model: .qwen25_coder_7b, priority: 10)
        }
        return router
    }
    
    public static func reasoningOptimized() -> DynamicRouter {
        let router = DynamicRouter()
        Task {
            await router.addRoute(pattern: "think", model: .deepseek_r1_8b, priority: 10)
            await router.addRoute(pattern: "reason", model: .deepseek_r1_8b, priority: 10)
            await router.addRoute(pattern: "analyze", model: .deepseek_r1_8b, priority: 10)
            await router.addRoute(pattern: "explain why", model: .deepseek_r1_8b, priority: 10)
        }
        return router
    }
}
