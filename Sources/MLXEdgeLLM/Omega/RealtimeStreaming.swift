import Foundation
import Combine

// MARK: - Realtime Streaming

/// Ultra-low latency streaming for voice assistants

public actor RealtimeStreaming {
    
    public static let shared = RealtimeStreaming()
    
    public struct Config {
        public var targetTTFTMs: Int = 100
        public var maxTokensPerSecond: Int = 100
    }
    
    public var config = Config()
    
    // MARK: - Streaming Session
    
    public class StreamingSession: @unchecked Sendable {
        public let id: String
        public private(set) var isActive: Bool = true
        
        public let tokens = PassthroughSubject<String, Never>()
        public let complete = PassthroughSubject<String, Never>()
        
        private var fullText: String = ""
        
        init(id: String = UUID().uuidString) {
            self.id = id
        }
        
        func append(_ token: String) {
            fullText += token
            tokens.send(token)
        }
        
        func finish() {
            isActive = false
            complete.send(fullText)
        }
    }
    
    private var sessions: [String: StreamingSession] = [:]
    
    public func createSession() -> StreamingSession {
        let session = StreamingSession()
        sessions[session.id] = session
        return session
    }
    
    public func destroySession(_ id: String) {
        sessions.removeValue(forKey: id)
    }
    
    /// Stream generation
    public func stream(
        prompt: String,
        engine: BeastEngine,
        session: StreamingSession
    ) async throws {
        var result = ""
        result = try await engine.generate(prompt: prompt, onToken: { token in
            result = token
            session.append(token)
        })
        session.finish()
    }
}

// MARK: - Interrupt Handler

public actor InterruptHandler {
    
    public static let shared = InterruptHandler()
    
    private var currentGeneration: Task<Void, Error>?
    private var interruptRequested: Bool = false
    
    public func interrupt() {
        interruptRequested = true
        currentGeneration?.cancel()
    }
    
    public func reset() {
        interruptRequested = false
    }
}
