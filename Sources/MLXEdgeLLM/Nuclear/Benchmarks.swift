import Foundation

// MARK: - Benchmarks

/// Performance benchmarking for Zero Dark models
public actor Benchmarks {
    
    public static let shared = Benchmarks()
    
    // MARK: - Results
    
    public struct BenchmarkResult: Sendable {
        public let model: Model
        public let promptTokens: Int
        public let outputTokens: Int
        public let timeToFirstTokenMs: Int
        public let totalTimeMs: Int
        public let tokensPerSecond: Float
        public let timestamp: Date
        
        public var summary: String {
            "\(model.displayName): \(Int(tokensPerSecond)) tok/s, TTFT: \(timeToFirstTokenMs)ms"
        }
    }
    
    private var results: [BenchmarkResult] = []
    
    // MARK: - Run Benchmark
    
    public func runBenchmark(
        model: Model,
        prompt: String = "The quick brown fox jumps over the lazy dog.",
        outputTokens: Int = 100
    ) async throws -> BenchmarkResult {
        
        let engine = try await BeastEngine(model: model)
        
        let startTime = Date()
        var firstTokenTime: Date?
        var tokenCount = 0
        
        let _ = try await engine.generate(prompt: prompt, onToken: { _ in
            if firstTokenTime == nil {
                firstTokenTime = Date()
            }
            tokenCount += 1
        })
        
        let endTime = Date()
        
        let ttft = firstTokenTime.map { Int($0.timeIntervalSince(startTime) * 1000) } ?? 0
        let totalTime = Int(endTime.timeIntervalSince(startTime) * 1000)
        let tps = totalTime > 0 ? Float(tokenCount) / Float(totalTime) * 1000 : 0
        
        let result = BenchmarkResult(
            model: model,
            promptTokens: prompt.split(separator: " ").count,
            outputTokens: tokenCount,
            timeToFirstTokenMs: ttft,
            totalTimeMs: totalTime,
            tokensPerSecond: tps,
            timestamp: Date()
        )
        
        results.append(result)
        return result
    }
    
    // MARK: - Results
    
    public func getResults() -> [BenchmarkResult] {
        results
    }
    
    public func clearResults() {
        results.removeAll()
    }
    
    public func getBestResult(for model: Model) -> BenchmarkResult? {
        results
            .filter { $0.model == model }
            .max { $0.tokensPerSecond < $1.tokensPerSecond }
    }
}

// MARK: - Leaderboard

public struct ModelLeaderboard {
    public var entries: [LeaderboardEntry] = []
    
    public struct LeaderboardEntry: Sendable {
        public let model: Model
        public let tokensPerSecond: Float
        public let deviceName: String
        public let timestamp: Date
    }
    
    public mutating func addEntry(model: Model, tps: Float, device: String) {
        entries.append(LeaderboardEntry(
            model: model,
            tokensPerSecond: tps,
            deviceName: device,
            timestamp: Date()
        ))
        entries.sort { $0.tokensPerSecond > $1.tokensPerSecond }
    }
    
    public var topModels: [LeaderboardEntry] {
        Array(entries.prefix(10))
    }
}
