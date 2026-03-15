import Foundation

// MARK: - Model Preloader

/// Predictively load models before user needs them
/// Zero perceived latency for common workflows

public actor ModelPreloader {
    
    public static let shared = ModelPreloader()
    
    // MARK: - State
    
    private var preloadedEngines: [Model: BeastEngine] = [:]
    private var loadingTasks: [Model: Task<BeastEngine, Error>] = [:]
    private var usageHistory: [Model: [Date]] = [:]
    
    // MARK: - Configuration
    
    public struct Config {
        /// Maximum models to keep preloaded
        public var maxPreloaded: Int = 2
        
        /// Preload on app launch
        public var preloadOnLaunch: Bool = true
        
        /// Models to always preload
        public var alwaysPreload: [Model] = [.qwen3_4b]
        
        /// Enable predictive preloading
        public var predictivePreload: Bool = true
        
        /// Unload after idle time (seconds)
        public var unloadAfterIdle: TimeInterval = 300
    }
    
    public var config = Config()
    
    // MARK: - Preload
    
    /// Preload a model in background
    public func preload(_ model: Model) async {
        // Already loaded?
        if preloadedEngines[model] != nil { return }
        
        // Already loading?
        if loadingTasks[model] != nil { return }
        
        // Check memory
        let monitor = await SystemMonitor.shared
        if await monitor.memoryPressure != .normal {
            return // Don't preload under memory pressure
        }
        
        // Start loading
        let task = Task<BeastEngine, Error> {
            let engine = try await BeastEngine(model: model)
            return engine
        }
        
        loadingTasks[model] = task
        
        do {
            let engine = try await task.value
            preloadedEngines[model] = engine
            loadingTasks.removeValue(forKey: model)
            
            // Evict if over limit
            await evictIfNeeded()
            
            print("[Preloader] Loaded: \(model.displayName)")
        } catch {
            loadingTasks.removeValue(forKey: model)
            print("[Preloader] Failed to load \(model.displayName): \(error)")
        }
    }
    
    /// Get preloaded engine or load on demand
    public func getEngine(_ model: Model) async throws -> BeastEngine {
        // Record usage
        usageHistory[model, default: []].append(Date())
        
        // Return preloaded
        if let engine = preloadedEngines[model] {
            return engine
        }
        
        // Wait for loading task
        if let task = loadingTasks[model] {
            return try await task.value
        }
        
        // Load now
        let engine = try await BeastEngine(model: model)
        preloadedEngines[model] = engine
        
        // Predictively preload related models
        if config.predictivePreload {
            Task {
                await predictivePreload(after: model)
            }
        }
        
        return engine
    }
    
    // MARK: - Predictive Loading
    
    private func predictivePreload(after model: Model) async {
        // Predict next model based on usage patterns
        let predicted = predictNextModel(after: model)
        
        for nextModel in predicted {
            if preloadedEngines[nextModel] == nil {
                await preload(nextModel)
            }
        }
    }
    
    private func predictNextModel(after model: Model) -> [Model] {
        // Simple heuristics for now
        // In production, use actual usage patterns
        
        switch model {
        case .qwen3_4b:
            // If user tries 4B, they might want 8B next
            return [.qwen3_8b]
            
        case .qwen3_8b:
            // Code task might follow general task
            return [.qwen25_coder_7b]
            
        case .qwen25_coder_7b:
            // Might want general model after coding
            return [.qwen3_8b]
            
        default:
            return []
        }
    }
    
    // MARK: - Eviction
    
    private func evictIfNeeded() async {
        while preloadedEngines.count > config.maxPreloaded {
            // Find least recently used
            let lru = preloadedEngines.keys.min { model1, model2 in
                let lastUse1 = usageHistory[model1]?.last ?? .distantPast
                let lastUse2 = usageHistory[model2]?.last ?? .distantPast
                return lastUse1 < lastUse2
            }
            
            if let model = lru, !config.alwaysPreload.contains(model) {
                preloadedEngines.removeValue(forKey: model)
                print("[Preloader] Evicted: \(model.displayName)")
            } else {
                break
            }
        }
    }
    
    /// Unload idle models
    public func unloadIdleModels() async {
        let now = Date()
        
        for (model, engine) in preloadedEngines {
            // Skip always-preload models
            if config.alwaysPreload.contains(model) { continue }
            
            // Check last usage
            let lastUse = usageHistory[model]?.last ?? .distantPast
            let idleTime = now.timeIntervalSince(lastUse)
            
            if idleTime > config.unloadAfterIdle {
                preloadedEngines.removeValue(forKey: model)
                print("[Preloader] Unloaded idle: \(model.displayName)")
            }
        }
    }
    
    // MARK: - Lifecycle
    
    /// Call on app launch
    public func warmup() async {
        guard config.preloadOnLaunch else { return }
        
        for model in config.alwaysPreload {
            await preload(model)
        }
    }
    
    /// Call when entering background
    public func prepareForBackground() async {
        // Keep only essential models
        for (model, _) in preloadedEngines {
            if !config.alwaysPreload.contains(model) {
                preloadedEngines.removeValue(forKey: model)
            }
        }
    }
    
    // MARK: - Stats
    
    public var stats: (loaded: Int, loading: Int, memoryMB: Int) {
        let loadedCount = preloadedEngines.count
        let loadingCount = loadingTasks.count
        let memory = preloadedEngines.values.reduce(0) { acc, engine in
            acc + engine.model.approximateSizeMB
        }
        return (loadedCount, loadingCount, memory)
    }
}

// MARK: - Instant Response Cache

/// Cache responses for identical prompts
public actor ResponseCache {
    
    public static let shared = ResponseCache()
    
    private struct CacheEntry {
        let response: String
        let model: Model
        let createdAt: Date
        var hitCount: Int
    }
    
    private var cache: [Int: CacheEntry] = [:]
    private let maxEntries = 100
    private let ttlSeconds: TimeInterval = 3600
    
    /// Check cache for exact prompt match
    public func lookup(prompt: String, model: Model) -> String? {
        let hash = prompt.hashValue
        
        guard var entry = cache[hash] else { return nil }
        guard entry.model == model else { return nil }
        
        // Check TTL
        if Date().timeIntervalSince(entry.createdAt) > ttlSeconds {
            cache.removeValue(forKey: hash)
            return nil
        }
        
        // Update hit count
        entry.hitCount += 1
        cache[hash] = entry
        
        return entry.response
    }
    
    /// Store response
    public func store(prompt: String, response: String, model: Model) {
        let hash = prompt.hashValue
        
        // Evict if needed
        if cache.count >= maxEntries {
            let lru = cache.min { $0.value.hitCount < $1.value.hitCount }
            if let key = lru?.key {
                cache.removeValue(forKey: key)
            }
        }
        
        cache[hash] = CacheEntry(
            response: response,
            model: model,
            createdAt: Date(),
            hitCount: 0
        )
    }
    
    public func clear() {
        cache.removeAll()
    }
}
