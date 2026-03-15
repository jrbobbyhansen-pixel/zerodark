import Foundation
import Combine

// MARK: - Realtime Streaming

/// Ultra-low latency streaming for voice assistants
/// First token in <100ms

public actor RealtimeStreaming {
    
    public static let shared = RealtimeStreaming()
    
    // MARK: - Configuration
    
    public struct Config {
        /// Target time to first token (ms)
        public var targetTTFTMs: Int = 100
        
        /// Maximum tokens per second
        public var maxTokensPerSecond: Int = 100
        
        /// Enable token batching for smoothness
        public var batchTokens: Bool = true
        
        /// Tokens per batch
        public var batchSize: Int = 3
        
        /// Enable prefetch (start generating before user finishes)
        public var enablePrefetch: Bool = true
        
        /// Confidence threshold for prefetch
        public var prefetchThreshold: Float = 0.8
    }
    
    public var config = Config()
    
    // MARK: - Streaming Session
    
    public class StreamingSession {
        public let id: String
        public private(set) var isActive: Bool = true
        
        // Publishers
        public let tokens = PassthroughSubject<String, Never>()
        public let words = PassthroughSubject<String, Never>()
        public let sentences = PassthroughSubject<String, Never>()
        public let complete = PassthroughSubject<String, Never>()
        public let error = PassthroughSubject<Error, Never>()
        
        // State
        private var fullText: String = ""
        private var wordBuffer: String = ""
        private var sentenceBuffer: String = ""
        
        init(id: String = UUID().uuidString) {
            self.id = id
        }
        
        func append(_ token: String) {
            fullText += token
            wordBuffer += token
            sentenceBuffer += token
            
            tokens.send(token)
            
            // Emit word
            if token.contains(" ") || token.contains("\n") {
                let word = wordBuffer.trimmingCharacters(in: .whitespaces)
                if !word.isEmpty {
                    words.send(word)
                }
                wordBuffer = ""
            }
            
            // Emit sentence
            if token.contains(".") || token.contains("!") || token.contains("?") {
                let sentence = sentenceBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty {
                    sentences.send(sentence)
                }
                sentenceBuffer = ""
            }
        }
        
        func finish() {
            isActive = false
            complete.send(fullText)
        }
        
        func fail(_ err: Error) {
            isActive = false
            error.send(err)
        }
    }
    
    // MARK: - Active Sessions
    
    private var sessions: [String: StreamingSession] = [:]
    
    // MARK: - Create Session
    
    public func createSession() -> StreamingSession {
        let session = StreamingSession()
        sessions[session.id] = session
        return session
    }
    
    public func destroySession(_ id: String) {
        sessions.removeValue(forKey: id)
    }
    
    // MARK: - Streaming Generation
    
    public func stream(
        prompt: String,
        engine: BeastEngine,
        session: StreamingSession
    ) async throws {
        let startTime = Date()
        var firstTokenTime: Date?
        var tokenCount = 0
        
        do {
            _ = try await engine.generate(prompt: prompt) { token in
                if firstTokenTime == nil {
                    firstTokenTime = Date()
                    let ttft = firstTokenTime!.timeIntervalSince(startTime) * 1000
                    print("[Realtime] TTFT: \(Int(ttft))ms")
                }
                
                session.append(token)
                tokenCount += 1
            }
            
            session.finish()
            
            // Log metrics
            let totalTime = Date().timeIntervalSince(startTime)
            let tokensPerSecond = Double(tokenCount) / totalTime
            print("[Realtime] \(tokenCount) tokens in \(Int(totalTime * 1000))ms (\(Int(tokensPerSecond)) tok/s)")
            
        } catch {
            session.fail(error)
            throw error
        }
    }
    
    // MARK: - Prefetch (Speculative Start)
    
    /// Start generating before user finishes typing
    public func prefetch(
        partialPrompt: String,
        engine: BeastEngine
    ) async -> String? {
        guard config.enablePrefetch else { return nil }
        
        // Predict completion
        let completion = predictCompletion(partialPrompt)
        
        guard let completion = completion else { return nil }
        
        // Start generating with predicted full prompt
        var prefetched = ""
        
        do {
            prefetched = try await engine.generate(
                prompt: partialPrompt + completion,
                maxTokens: 50
            ) { _ in }
        } catch {
            return nil
        }
        
        return prefetched
    }
    
    private func predictCompletion(_ partial: String) -> String? {
        // Simple heuristics for common patterns
        let lower = partial.lowercased()
        
        if lower.hasPrefix("what is") || lower.hasPrefix("what's") {
            return "?"
        }
        
        if lower.hasPrefix("how do") || lower.hasPrefix("how to") {
            return "?"
        }
        
        if lower.hasPrefix("can you") || lower.hasPrefix("could you") {
            return "?"
        }
        
        // Need more context
        return nil
    }
}

// MARK: - Interrupt Handling

public actor InterruptHandler {
    
    public static let shared = InterruptHandler()
    
    private var currentGeneration: Task<Void, Error>?
    private var interruptRequested: Bool = false
    
    /// Start interruptible generation
    public func generate(
        prompt: String,
        engine: BeastEngine,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        interruptRequested = false
        
        var result = ""
        
        currentGeneration = Task {
            result = try await engine.generate(prompt: prompt) { token in
                if self.interruptRequested {
                    throw CancellationError()
                }
                onToken(token)
            }
        }
        
        try await currentGeneration?.value
        return result
    }
    
    /// Interrupt current generation
    public func interrupt() {
        interruptRequested = true
        currentGeneration?.cancel()
    }
    
    /// Check if interrupted
    public func checkInterrupt() throws {
        if interruptRequested {
            throw CancellationError()
        }
    }
}

// MARK: - Voice Activity Detection

/// Detect when user starts/stops speaking
public actor VoiceActivityDetector {
    
    public static let shared = VoiceActivityDetector()
    
    public enum State {
        case silence
        case speaking
        case thinking  // User paused but might continue
    }
    
    @Published public var state: State = .silence
    
    /// Energy threshold for speech detection
    public var energyThreshold: Float = 0.02
    
    /// Silence duration to consider "finished speaking" (ms)
    public var silenceThresholdMs: Int = 500
    
    /// Process audio buffer
    public func processAudio(_ samples: [Float]) -> State {
        // Calculate RMS energy
        let energy = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
        
        if energy > energyThreshold {
            state = .speaking
        } else {
            // Could transition to thinking, then silence
            if state == .speaking {
                state = .thinking
            }
        }
        
        return state
    }
}

// MARK: - Turn-Taking

/// Natural conversation turn-taking
public actor TurnTaking {
    
    public static let shared = TurnTaking()
    
    public enum Turn {
        case user
        case assistant
        case overlap  // Both talking (should interrupt)
    }
    
    @Published public var currentTurn: Turn = .user
    
    /// Handle user starting to speak
    public func userStartedSpeaking() {
        if currentTurn == .assistant {
            currentTurn = .overlap
            // Should trigger interrupt
        } else {
            currentTurn = .user
        }
    }
    
    /// Handle user stopping speaking
    public func userStoppedSpeaking() {
        if currentTurn == .user {
            currentTurn = .assistant
        }
    }
    
    /// Handle assistant starting response
    public func assistantStartedSpeaking() {
        currentTurn = .assistant
    }
    
    /// Handle assistant finishing response
    public func assistantStoppedSpeaking() {
        currentTurn = .user
    }
}
