import Foundation
import Network

// MARK: - Model Context Protocol (MCP) Server

/// Zero Dark can act as an MCP server, allowing ANY MCP client to use its tools
/// This is what makes it interoperable with Claude Desktop, VS Code, etc.

public actor MCPServer {
    
    public static let shared = MCPServer()
    
    // MARK: - State
    
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var isRunning = false
    
    // MARK: - Configuration
    
    public struct Config {
        public var port: UInt16 = 8765
        public var host: String = "127.0.0.1"
        public var requireAuth: Bool = false
        public var authToken: String?
        
        public static let `default` = Config()
    }
    
    public var config = Config()
    
    // MARK: - MCP Protocol Types
    
    public struct MCPRequest: Codable {
        public let jsonrpc: String
        public let id: Int
        public let method: String
        public let params: [String: AnyCodable]?
    }
    
    public struct MCPResponse: Codable {
        public let jsonrpc: String
        public let id: Int
        public let result: AnyCodable?
        public let error: MCPError?
    }
    
    public struct MCPError: Codable {
        public let code: Int
        public let message: String
    }
    
    // MARK: - Start/Stop
    
    public func start() throws {
        guard !isRunning else { return }
        
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: config.port))
        
        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("[MCP Server] Listening on port \(self?.config.port ?? 0)")
            case .failed(let error):
                print("[MCP Server] Failed: \(error)")
            default:
                break
            }
        }
        
        listener?.newConnectionHandler = { [weak self] connection in
            Task {
                await self?.handleConnection(connection)
            }
        }
        
        listener?.start(queue: .global())
        isRunning = true
    }
    
    public func stop() {
        listener?.cancel()
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()
        isRunning = false
    }
    
    // MARK: - Handle Connection
    
    private func handleConnection(_ connection: NWConnection) {
        connections.append(connection)
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("[MCP Server] Client connected")
                Task {
                    await self?.receiveMessage(connection)
                }
            case .failed, .cancelled:
                Task {
                    await self?.removeConnection(connection)
                }
            default:
                break
            }
        }
        
        connection.start(queue: .global())
    }
    
    private func removeConnection(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
    }
    
    // MARK: - Message Handling
    
    private func receiveMessage(_ connection: NWConnection) async {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let data = data, !data.isEmpty {
                Task {
                    await self.processMessage(data, connection: connection)
                }
            }
            
            if !isComplete && error == nil {
                Task {
                    await self.receiveMessage(connection)
                }
            }
        }
    }
    
    private func processMessage(_ data: Data, connection: NWConnection) async {
        guard let request = try? JSONDecoder().decode(MCPRequest.self, from: data) else {
            return
        }
        
        let response = await handleRequest(request)
        
        if let responseData = try? JSONEncoder().encode(response) {
            connection.send(content: responseData, completion: .contentProcessed { _ in })
        }
    }
    
    // MARK: - MCP Methods
    
    private func handleRequest(_ request: MCPRequest) async -> MCPResponse {
        switch request.method {
        case "initialize":
            return initializeResponse(id: request.id)
            
        case "tools/list":
            return await toolsListResponse(id: request.id)
            
        case "tools/call":
            return await toolsCallResponse(id: request.id, params: request.params)
            
        case "resources/list":
            return resourcesListResponse(id: request.id)
            
        case "prompts/list":
            return promptsListResponse(id: request.id)
            
        default:
            return MCPResponse(
                jsonrpc: "2.0",
                id: request.id,
                result: nil,
                error: MCPError(code: -32601, message: "Method not found")
            )
        }
    }
    
    private func initializeResponse(id: Int) -> MCPResponse {
        let result: [String: Any] = [
            "protocolVersion": "2024-11-05",
            "capabilities": [
                "tools": [:],
                "resources": [:],
                "prompts": [:]
            ],
            "serverInfo": [
                "name": "Zero Dark",
                "version": "1.0.0"
            ]
        ]
        
        return MCPResponse(
            jsonrpc: "2.0",
            id: id,
            result: AnyCodable(result),
            error: nil
        )
    }
    
    private func toolsListResponse(id: Int) async -> MCPResponse {
        let toolkit = await AgentToolkit.shared
        let tools = await toolkit.tools
        
        let mcpTools = tools.map { tool -> [String: Any] in
            [
                "name": tool.name,
                "description": tool.description,
                "inputSchema": [
                    "type": "object",
                    "properties": Dictionary(uniqueKeysWithValues: tool.parameters.map { param in
                        (param.name, [
                            "type": param.type,
                            "description": param.description
                        ])
                    }),
                    "required": tool.parameters.filter { $0.required }.map { $0.name }
                ]
            ]
        }
        
        return MCPResponse(
            jsonrpc: "2.0",
            id: id,
            result: AnyCodable(["tools": mcpTools]),
            error: nil
        )
    }
    
    private func toolsCallResponse(id: Int, params: [String: AnyCodable]?) async -> MCPResponse {
        guard let params = params,
              let name = params["name"]?.value as? String,
              let arguments = params["arguments"]?.value as? [String: Any] else {
            return MCPResponse(
                jsonrpc: "2.0",
                id: id,
                result: nil,
                error: MCPError(code: -32602, message: "Invalid params")
            )
        }
        
        let stringArgs = arguments.mapValues { String(describing: $0) }
        let call = AgentToolkit.ToolCall(tool: name, arguments: stringArgs)
        
        let toolkit = await AgentToolkit.shared
        let result = await toolkit.execute(call)
        
        return MCPResponse(
            jsonrpc: "2.0",
            id: id,
            result: AnyCodable([
                "content": [
                    ["type": "text", "text": result.output]
                ],
                "isError": !result.success
            ]),
            error: nil
        )
    }
    
    private func resourcesListResponse(id: Int) -> MCPResponse {
        // Zero Dark can expose conversations, memories, etc. as MCP resources
        return MCPResponse(
            jsonrpc: "2.0",
            id: id,
            result: AnyCodable(["resources": []]),
            error: nil
        )
    }
    
    private func promptsListResponse(id: Int) -> MCPResponse {
        // Zero Dark can expose prompt templates as MCP prompts
        return MCPResponse(
            jsonrpc: "2.0",
            id: id,
            result: AnyCodable(["prompts": []]),
            error: nil
        )
    }
}

// MARK: - AnyCodable Helper

public struct AnyCodable: Codable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encode(String(describing: value))
        }
    }
}

// MARK: - MCP Client

/// Zero Dark can also ACT as an MCP client to use external tools
public actor MCPClient {
    
    public static let shared = MCPClient()
    
    private var connections: [String: NWConnection] = [:]
    
    public func connect(to url: URL, identifier: String) async throws {
        guard let host = url.host, let port = url.port else {
            throw MCPClientError.invalidURL
        }
        
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(port)),
            using: .tcp
        )
        
        connection.start(queue: .global())
        connections[identifier] = connection
        
        // Initialize connection
        _ = try await sendRequest(
            to: identifier,
            method: "initialize",
            params: [
                "protocolVersion": "2024-11-05",
                "capabilities": [:],
                "clientInfo": [
                    "name": "Zero Dark",
                    "version": "1.0.0"
                ]
            ]
        )
    }
    
    public func listTools(from identifier: String) async throws -> [[String: Any]] {
        let response = try await sendRequest(to: identifier, method: "tools/list", params: nil)
        return (response["tools"] as? [[String: Any]]) ?? []
    }
    
    public func callTool(
        on identifier: String,
        name: String,
        arguments: [String: Any]
    ) async throws -> String {
        let response = try await sendRequest(
            to: identifier,
            method: "tools/call",
            params: ["name": name, "arguments": arguments]
        )
        
        if let content = response["content"] as? [[String: Any]],
           let first = content.first,
           let text = first["text"] as? String {
            return text
        }
        
        return String(describing: response)
    }
    
    private func sendRequest(
        to identifier: String,
        method: String,
        params: [String: Any]?
    ) async throws -> [String: Any] {
        guard let connection = connections[identifier] else {
            throw MCPClientError.notConnected
        }
        
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": Int.random(in: 1...999999),
            "method": method,
            "params": params ?? [:]
        ]
        
        let data = try JSONSerialization.data(withJSONObject: request)
        
        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    guard let data = data,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let result = json["result"] as? [String: Any] else {
                        continuation.resume(returning: [:])
                        return
                    }
                    
                    continuation.resume(returning: result)
                }
            })
        }
    }
    
    public func disconnect(_ identifier: String) {
        connections[identifier]?.cancel()
        connections.removeValue(forKey: identifier)
    }
    
    public enum MCPClientError: Error {
        case invalidURL
        case notConnected
        case requestFailed
    }
}
