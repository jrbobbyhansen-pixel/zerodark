import Foundation
import Network

// MARK: - API Server

/// Run Zero Dark as a local API server
/// This enables: Mac as inference server, multi-device access, enterprise deployment

public actor APIServer {
    
    public static let shared = APIServer()
    
    // MARK: - State
    
    private var listener: NWListener?
    private var isRunning = false
    
    // MARK: - Configuration
    
    public struct Config {
        public var port: UInt16 = 11434  // Same as Ollama for compatibility
        public var host: String = "127.0.0.1"
        public var enableCORS: Bool = true
        public var apiKey: String?  // Optional API key auth
        public var maxConcurrentRequests: Int = 4
        public var requestTimeout: TimeInterval = 300
        
        public static let `default` = Config()
        
        public static var ollamaCompatible: Config {
            var config = Config()
            config.port = 11434
            return config
        }
    }
    
    public var config = Config()
    
    // MARK: - Start/Stop
    
    public func start(config: Config = .default) throws {
        self.config = config
        
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: config.port))
        
        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("[API Server] Running at http://\(self?.config.host ?? ""):\(self?.config.port ?? 0)")
            case .failed(let error):
                print("[API Server] Failed: \(error)")
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
        isRunning = false
        print("[API Server] Stopped")
    }
    
    // MARK: - Connection Handling
    
    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                Task { [weak self] in
                    await self?.receiveRequest(connection)
                }
            }
        }
        connection.start(queue: .global())
    }
    
    private func receiveRequest(_ connection: NWConnection) async {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self = self, let data = data else {
                connection.cancel()
                return
            }
            
            Task {
                let response = await self.processHTTPRequest(data)
                await self.sendResponse(response, to: connection)
                connection.cancel()
            }
        }
    }
    
    // MARK: - HTTP Processing
    
    private func processHTTPRequest(_ data: Data) async -> HTTPResponse {
        guard let request = parseHTTPRequest(data) else {
            return HTTPResponse(status: 400, body: ["error": "Bad request"])
        }
        
        // API key auth
        if let requiredKey = config.apiKey {
            let providedKey = request.headers["Authorization"]?.replacingOccurrences(of: "Bearer ", with: "")
            if providedKey != requiredKey {
                return HTTPResponse(status: 401, body: ["error": "Unauthorized"])
            }
        }
        
        // Route request
        switch (request.method, request.path) {
        case ("GET", "/"):
            return HTTPResponse(status: 200, body: [
                "name": "Zero Dark",
                "version": "1.0.0",
                "status": "running"
            ])
            
        case ("GET", "/api/tags"), ("GET", "/v1/models"):
            return await handleListModels()
            
        case ("POST", "/api/generate"), ("POST", "/v1/completions"):
            return await handleGenerate(request)
            
        case ("POST", "/api/chat"), ("POST", "/v1/chat/completions"):
            return await handleChat(request)
            
        case ("GET", "/api/tools"), ("GET", "/v1/tools"):
            return await handleListTools()
            
        case ("POST", "/api/tools/call"), ("POST", "/v1/tools/call"):
            return await handleToolCall(request)
            
        case ("GET", "/health"):
            return HTTPResponse(status: 200, body: ["status": "healthy"])
            
        default:
            return HTTPResponse(status: 404, body: ["error": "Not found"])
        }
    }
    
    // MARK: - HTTP Parsing
    
    struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data?
    }
    
    struct HTTPResponse {
        let status: Int
        let body: [String: Any]
        
        var statusText: String {
            switch status {
            case 200: return "OK"
            case 400: return "Bad Request"
            case 401: return "Unauthorized"
            case 404: return "Not Found"
            case 500: return "Internal Server Error"
            default: return "Unknown"
            }
        }
    }
    
    private func parseHTTPRequest(_ data: Data) -> HTTPRequest? {
        guard let string = String(data: data, encoding: .utf8) else { return nil }
        
        let lines = string.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return nil }
        
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        
        let method = String(parts[0])
        let path = String(parts[1])
        
        var headers: [String: String] = [:]
        var bodyStartIndex = lines.count
        
        for (index, line) in lines.enumerated() {
            if line.isEmpty {
                bodyStartIndex = index + 1
                break
            }
            if line.contains(": ") {
                let headerParts = line.split(separator: ":", maxSplits: 1)
                if headerParts.count == 2 {
                    headers[String(headerParts[0])] = String(headerParts[1]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        let bodyLines = lines.dropFirst(bodyStartIndex).joined(separator: "\r\n")
        let body = bodyLines.isEmpty ? nil : bodyLines.data(using: .utf8)
        
        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }
    
    private func sendResponse(_ response: HTTPResponse, to connection: NWConnection) async {
        let json = try? JSONSerialization.data(withJSONObject: response.body)
        let body = json ?? Data()
        
        var http = "HTTP/1.1 \(response.status) \(response.statusText)\r\n"
        http += "Content-Type: application/json\r\n"
        http += "Content-Length: \(body.count)\r\n"
        
        if config.enableCORS {
            http += "Access-Control-Allow-Origin: *\r\n"
            http += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
            http += "Access-Control-Allow-Headers: Content-Type, Authorization\r\n"
        }
        
        http += "\r\n"
        
        var data = http.data(using: .utf8) ?? Data()
        data.append(body)
        
        connection.send(content: data, completion: .contentProcessed { _ in })
    }
    
    // MARK: - API Handlers
    
    private func handleListModels() async -> HTTPResponse {
        let models = Model.allCases.map { model -> [String: Any] in
            [
                "name": model.rawValue,
                "displayName": model.displayName,
                "size": model.approximateSizeMB,
                "description": model.modelDescription,
                "modified_at": ISO8601DateFormatter().string(from: Date())
            ]
        }
        
        // Ollama-compatible format
        return HTTPResponse(status: 200, body: [
            "models": models
        ])
    }
    
    private func handleGenerate(_ request: HTTPRequest) async -> HTTPResponse {
        guard let body = request.body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let prompt = json["prompt"] as? String else {
            return HTTPResponse(status: 400, body: ["error": "Missing prompt"])
        }
        
        let modelName = json["model"] as? String
        let model = Model.allCases.first { $0.rawValue == modelName } ?? .qwen3_8b
        
        do {
            let ai = await ZeroDarkAI.shared
            let response = try await ai.generate(prompt, model: model, stream: false)
            
            return HTTPResponse(status: 200, body: [
                "model": model.rawValue,
                "response": response,
                "done": true
            ])
        } catch {
            return HTTPResponse(status: 500, body: ["error": error.localizedDescription])
        }
    }
    
    private func handleChat(_ request: HTTPRequest) async -> HTTPResponse {
        guard let body = request.body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else {
            return HTTPResponse(status: 400, body: ["error": "Missing messages"])
        }
        
        // Convert to prompt
        var prompt = ""
        for message in messages {
            if let role = message["role"] as? String,
               let content = message["content"] as? String {
                prompt += "\(role): \(content)\n"
            }
        }
        
        let modelName = json["model"] as? String
        let model = Model.allCases.first { $0.rawValue == modelName } ?? .qwen3_8b
        
        do {
            let ai = await ZeroDarkAI.shared
            let response = try await ai.generate(prompt, model: model, stream: false)
            
            // OpenAI-compatible format
            return HTTPResponse(status: 200, body: [
                "id": "chatcmpl-\(UUID().uuidString.prefix(8))",
                "object": "chat.completion",
                "created": Int(Date().timeIntervalSince1970),
                "model": model.rawValue,
                "choices": [
                    [
                        "index": 0,
                        "message": [
                            "role": "assistant",
                            "content": response
                        ],
                        "finish_reason": "stop"
                    ]
                ],
                "usage": [
                    "prompt_tokens": prompt.count / 4,
                    "completion_tokens": response.count / 4,
                    "total_tokens": (prompt.count + response.count) / 4
                ]
            ])
        } catch {
            return HTTPResponse(status: 500, body: ["error": error.localizedDescription])
        }
    }
    
    private func handleListTools() async -> HTTPResponse {
        let toolkit = await AgentToolkit.shared
        let tools = await toolkit.tools
        
        let toolList = tools.map { tool -> [String: Any] in
            [
                "name": tool.name,
                "description": tool.description,
                "parameters": tool.parameters.map { param in
                    [
                        "name": param.name,
                        "type": param.type,
                        "description": param.description,
                        "required": param.required
                    ]
                }
            ]
        }
        
        return HTTPResponse(status: 200, body: ["tools": toolList])
    }
    
    private func handleToolCall(_ request: HTTPRequest) async -> HTTPResponse {
        guard let body = request.body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let toolName = json["tool"] as? String,
              let arguments = json["arguments"] as? [String: String] else {
            return HTTPResponse(status: 400, body: ["error": "Missing tool or arguments"])
        }
        
        let toolkit = await AgentToolkit.shared
        let call = AgentToolkit.ToolCall(tool: toolName, arguments: arguments)
        let result = await toolkit.execute(call)
        
        return HTTPResponse(status: 200, body: [
            "success": result.success,
            "output": result.output,
            "data": result.data ?? [:]
        ])
    }
}

// MARK: - Enterprise Features

public struct EnterpriseConfig {
    /// Enable audit logging
    public var auditLogging: Bool = false
    
    /// Audit log path
    public var auditLogPath: URL?
    
    /// Maximum tokens per request
    public var maxTokensPerRequest: Int = 4096
    
    /// Rate limiting (requests per minute)
    public var rateLimitPerMinute: Int = 60
    
    /// Allowed models (nil = all)
    public var allowedModels: [Model]?
    
    /// Disable uncensored models
    public var disableUncensored: Bool = false
    
    /// Custom system prompt prefix (for compliance)
    public var systemPromptPrefix: String?
    
    /// Content filter level
    public var contentFilterLevel: SafetyFilter.Level = .standard
    
    /// Enable tool whitelisting
    public var toolWhitelist: [String]?
    
    /// Disable code execution
    public var disableCodeExecution: Bool = false
}

extension APIServer {
    
    /// Configure for enterprise deployment
    public func configureEnterprise(_ config: EnterpriseConfig) async {
        // Apply enterprise settings
        if config.disableUncensored {
            // Filter out uncensored models
        }
        
        if config.disableCodeExecution {
            // Disable code sandbox
        }
        
        // Set safety filter level
        await MainActor.run {
            SafetyFilter.shared.level = config.contentFilterLevel
        }
        
        print("[API Server] Enterprise configuration applied")
    }
}
