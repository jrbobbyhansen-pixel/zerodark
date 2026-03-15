import Foundation

// MARK: - API Server

/// OpenAI-compatible REST API server
/// Run locally on device for integration with other tools

public actor APIServer {
    
    public static let shared = APIServer()
    
    public struct Config: Sendable {
        public var port: Int = 8080
        public var host: String = "127.0.0.1"
        public var enableCORS: Bool = true
        public var maxConcurrentRequests: Int = 4
        public var defaultModel: Model = .qwen3_8b
        
        public static let `default` = Config()
    }
    
    public var config = Config()
    public var isRunning: Bool = false
    
    // MARK: - Request/Response Types
    
    public struct ChatCompletionRequest: Codable, Sendable {
        public let model: String
        public let messages: [Message]
        public let temperature: Double?
        public let max_tokens: Int?
        public let stream: Bool?
        
        public struct Message: Codable, Sendable {
            public let role: String
            public let content: String
        }
    }
    
    public struct ChatCompletionResponse: Codable, Sendable {
        public let id: String
        public let object: String
        public let created: Int
        public let model: String
        public let choices: [Choice]
        public let usage: Usage
        
        public struct Choice: Codable, Sendable {
            public let index: Int
            public let message: Message
            public let finish_reason: String
            
            public struct Message: Codable, Sendable {
                public let role: String
                public let content: String
            }
        }
        
        public struct Usage: Codable, Sendable {
            public let prompt_tokens: Int
            public let completion_tokens: Int
            public let total_tokens: Int
        }
    }
    
    // MARK: - Server Control
    
    public func start() async throws {
        isRunning = true
        print("[APIServer] Started on \(config.host):\(config.port)")
        // Actual HTTP server implementation would go here
        // For now, this is a placeholder
    }
    
    public func stop() {
        isRunning = false
        print("[APIServer] Stopped")
    }
    
    // MARK: - Handle Request
    
    public func handleChatCompletion(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        // Build prompt from messages
        let prompt = request.messages.map { "\($0.role): \($0.content)" }.joined(separator: "\n")
        
        // Generate response
        let ai = await ZeroDarkAI.shared
        var response = ""
        response = try await ai.process(prompt: prompt, onToken: { token in
            response = token
        })
        
        return ChatCompletionResponse(
            id: "chatcmpl-\(UUID().uuidString.prefix(8))",
            object: "chat.completion",
            created: Int(Date().timeIntervalSince1970),
            model: request.model,
            choices: [
                .init(
                    index: 0,
                    message: .init(role: "assistant", content: response),
                    finish_reason: "stop"
                )
            ],
            usage: .init(
                prompt_tokens: prompt.split(separator: " ").count,
                completion_tokens: response.split(separator: " ").count,
                total_tokens: prompt.split(separator: " ").count + response.split(separator: " ").count
            )
        )
    }
}
