import Foundation

// MARK: - MCP Server

/// Model Context Protocol server for external tool integration
/// Enables Claude Desktop, Continue, etc. to use Zero Dark

public actor MCPServer {
    
    public static let shared = MCPServer()
    
    public struct Config: Sendable {
        public var name: String = "ZeroDark"
        public var version: String = "1.0.0"
        public var port: Int = 8081
        
        public static let `default` = Config()
    }
    
    public var config = Config()
    public var isRunning: Bool = false
    
    // MARK: - MCP Types
    
    public struct Tool: Codable, Sendable {
        public let name: String
        public let description: String
        public let inputSchema: InputSchema
        
        public struct InputSchema: Codable, Sendable {
            public let type: String
            public let properties: [String: Property]
            
            public struct Property: Codable, Sendable {
                public let type: String
                public let description: String
            }
        }
    }
    
    // MARK: - Server Control
    
    public func start() async throws {
        isRunning = true
        print("[MCPServer] Started on port \(config.port)")
    }
    
    public func stop() {
        isRunning = false
        print("[MCPServer] Stopped")
    }
    
    // MARK: - Tool Registration
    
    public func getAvailableTools() -> [Tool] {
        [
            Tool(
                name: "ask",
                description: "Ask Zero Dark AI a question",
                inputSchema: .init(
                    type: "object",
                    properties: [
                        "prompt": .init(type: "string", description: "The question or prompt")
                    ]
                )
            ),
            Tool(
                name: "generate_code",
                description: "Generate code in any language",
                inputSchema: .init(
                    type: "object",
                    properties: [
                        "description": .init(type: "string", description: "What the code should do"),
                        "language": .init(type: "string", description: "Programming language")
                    ]
                )
            ),
            Tool(
                name: "translate",
                description: "Translate text between languages",
                inputSchema: .init(
                    type: "object",
                    properties: [
                        "text": .init(type: "string", description: "Text to translate"),
                        "target_language": .init(type: "string", description: "Target language")
                    ]
                )
            )
        ]
    }
    
    // MARK: - Tool Execution
    
    public func executeTool(name: String, arguments: [String: String]) async throws -> String {
        switch name {
        case "ask":
            guard let prompt = arguments["prompt"] else {
                throw MCPError.missingArgument("prompt")
            }
            let ai = await ZeroDarkAI.shared
            var result = ""
            result = try await ai.process(prompt: prompt, onToken: { _ in })
            return result
            
        case "generate_code":
            guard let description = arguments["description"] else {
                throw MCPError.missingArgument("description")
            }
            let language = arguments["language"] ?? "Swift"
            let ai = await ZeroDarkAI.shared
            var result = ""
            result = try await ai.process(
                prompt: "Write \(language) code: \(description)\n\nProvide only the code.",
                onToken: { _ in }
            )
            return result
            
        case "translate":
            guard let text = arguments["text"], let target = arguments["target_language"] else {
                throw MCPError.missingArgument("text or target_language")
            }
            let translation = await LiveTranslation.shared
            let lang = LiveTranslation.Language.all.first { $0.name.lowercased() == target.lowercased() } ?? .spanish
            return try await translation.translate(text, to: lang)
            
        default:
            throw MCPError.unknownTool(name)
        }
    }
    
    public enum MCPError: Error {
        case missingArgument(String)
        case unknownTool(String)
        case executionFailed(String)
    }
}
