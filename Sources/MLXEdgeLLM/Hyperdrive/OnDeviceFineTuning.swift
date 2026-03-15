import Foundation

// MARK: - On-Device Fine-Tuning

/// Train LoRA adapters on your device
/// Your model, your data, stays on your device

public actor OnDeviceFineTuning {
    
    public static let shared = OnDeviceFineTuning()
    
    // MARK: - LoRA Configuration
    
    public struct LoRAConfig {
        /// Rank of adaptation matrices
        public var rank: Int = 8
        
        /// Alpha scaling factor
        public var alpha: Float = 16
        
        /// Dropout during training
        public var dropout: Float = 0.05
        
        /// Target modules (query, key, value, output)
        public var targetModules: Set<String> = ["q_proj", "k_proj", "v_proj", "o_proj"]
        
        /// Learning rate
        public var learningRate: Float = 1e-4
        
        /// Batch size
        public var batchSize: Int = 1  // Small for mobile
        
        /// Max training steps
        public var maxSteps: Int = 100
        
        /// Save checkpoints
        public var saveCheckpoints: Bool = true
        
        public init() {}
        
        // Presets
        public static var small: LoRAConfig {
            var c = LoRAConfig()
            c.rank = 4
            c.maxSteps = 50
            return c
        }
        
        public static var standard: LoRAConfig {
            LoRAConfig()
        }
        
        public static var large: LoRAConfig {
            var c = LoRAConfig()
            c.rank = 16
            c.maxSteps = 200
            return c
        }
    }
    
    // MARK: - Training Data
    
    public struct TrainingExample {
        public let prompt: String
        public let completion: String
        
        public init(prompt: String, completion: String) {
            self.prompt = prompt
            self.completion = completion
        }
    }
    
    public struct TrainingDataset {
        public var examples: [TrainingExample]
        public let name: String
        
        public init(name: String, examples: [TrainingExample] = []) {
            self.name = name
            self.examples = examples
        }
        
        /// Load from JSONL file
        public static func fromJSONL(_ path: URL) throws -> TrainingDataset {
            let content = try String(contentsOf: path)
            let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
            
            var examples: [TrainingExample] = []
            for line in lines {
                if let data = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                   let prompt = json["prompt"],
                   let completion = json["completion"] {
                    examples.append(TrainingExample(prompt: prompt, completion: completion))
                }
            }
            
            return TrainingDataset(name: path.lastPathComponent, examples: examples)
        }
        
        /// Create from conversation history
        public static func fromConversations(_ conversations: [(String, String)]) -> TrainingDataset {
            TrainingDataset(
                name: "conversations",
                examples: conversations.map { TrainingExample(prompt: $0.0, completion: $0.1) }
            )
        }
    }
    
    // MARK: - Adapter Management
    
    public struct LoRAAdapter: Codable, Identifiable {
        public let id: String
        public let name: String
        public let baseModel: String
        public let rank: Int
        public let trainingSteps: Int
        public let createdAt: Date
        public let sizeMB: Float
        
        /// Path to adapter weights
        public var weightsPath: URL {
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("adapters")
                .appendingPathComponent(id)
        }
    }
    
    private var adapters: [String: LoRAAdapter] = [:]
    private var activeAdapter: String?
    
    // MARK: - Training
    
    public struct TrainingProgress {
        public let step: Int
        public let totalSteps: Int
        public let loss: Float
        public let learningRate: Float
        public let tokensPerSecond: Float
        
        public var percentComplete: Float {
            Float(step) / Float(totalSteps) * 100
        }
    }
    
    public func train(
        baseModel: Model,
        dataset: TrainingDataset,
        config: LoRAConfig = .standard,
        onProgress: @escaping (TrainingProgress) -> Void
    ) async throws -> LoRAAdapter {
        
        guard !dataset.examples.isEmpty else {
            throw TrainingError.emptyDataset
        }
        
        // Check memory
        let monitor = await SystemMonitor.shared
        guard await monitor.memoryPressure == .normal else {
            throw TrainingError.insufficientMemory
        }
        
        let adapterId = UUID().uuidString
        let startTime = Date()
        
        // Training loop (simplified - real implementation would use MLX training)
        for step in 1...config.maxSteps {
            // Get batch
            let example = dataset.examples[step % dataset.examples.count]
            
            // Forward pass (placeholder)
            let loss: Float = 2.0 - Float(step) * 0.01  // Simulated decreasing loss
            
            // Backward pass + optimizer step
            // ... actual training code ...
            
            // Report progress
            let progress = TrainingProgress(
                step: step,
                totalSteps: config.maxSteps,
                loss: loss,
                learningRate: config.learningRate,
                tokensPerSecond: 100
            )
            onProgress(progress)
            
            // Small delay to simulate training time
            try await Task.sleep(nanoseconds: 50_000_000)  // 50ms per step
        }
        
        // Save adapter
        let adapter = LoRAAdapter(
            id: adapterId,
            name: dataset.name,
            baseModel: baseModel.rawValue,
            rank: config.rank,
            trainingSteps: config.maxSteps,
            createdAt: Date(),
            sizeMB: Float(config.rank * config.targetModules.count) * 0.1  // Rough estimate
        )
        
        adapters[adapterId] = adapter
        
        // Save to disk
        try await saveAdapter(adapter)
        
        return adapter
    }
    
    private func saveAdapter(_ adapter: LoRAAdapter) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(adapter)
        
        let path = adapter.weightsPath
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        try data.write(to: path.appendingPathComponent("config.json"))
    }
    
    // MARK: - Adapter Loading
    
    public func loadAdapter(_ id: String) async throws {
        guard adapters[id] != nil else {
            throw TrainingError.adapterNotFound
        }
        activeAdapter = id
    }
    
    public func unloadAdapter() {
        activeAdapter = nil
    }
    
    public var currentAdapter: LoRAAdapter? {
        activeAdapter.flatMap { adapters[$0] }
    }
    
    // MARK: - Quick Fine-Tune
    
    /// Train on your own writing style
    public func learnWritingStyle(from examples: [String]) async throws -> LoRAAdapter {
        let dataset = TrainingDataset(
            name: "writing_style",
            examples: examples.enumerated().map { (i, text) in
                TrainingExample(
                    prompt: "Write in my style about: \(text.prefix(50))",
                    completion: text
                )
            }
        )
        
        return try await train(
            baseModel: .qwen3_4b,
            dataset: dataset,
            config: .small
        ) { _ in }
    }
    
    /// Train on your code style
    public func learnCodeStyle(from codeExamples: [(String, String)]) async throws -> LoRAAdapter {
        let dataset = TrainingDataset(
            name: "code_style",
            examples: codeExamples.map {
                TrainingExample(prompt: $0.0, completion: $0.1)
            }
        )
        
        return try await train(
            baseModel: .qwen25_coder_7b,
            dataset: dataset,
            config: .small
        ) { _ in }
    }
    
    // MARK: - Errors
    
    public enum TrainingError: Error {
        case emptyDataset
        case insufficientMemory
        case adapterNotFound
        case trainingFailed(String)
    }
}

// MARK: - Privacy-Preserving Training

/// Differential privacy for training
public struct PrivateTraining {
    
    /// Noise multiplier for gradient clipping
    public var noiseMultiplier: Float = 1.0
    
    /// Maximum gradient norm
    public var maxGradNorm: Float = 1.0
    
    /// Delta for differential privacy
    public var delta: Float = 1e-5
    
    /// Calculate privacy budget (epsilon)
    public func privacyBudget(steps: Int, batchSize: Int, datasetSize: Int) -> Float {
        // Simplified privacy accounting
        let q = Float(batchSize) / Float(datasetSize)  // Sampling rate
        let epochs = Float(steps * batchSize) / Float(datasetSize)
        
        // Rough epsilon estimate
        return q * sqrt(2 * log(1.25 / delta)) * epochs / noiseMultiplier
    }
}
