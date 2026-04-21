import Foundation
import Combine

// MARK: - ToolChainExecutor

class ToolChainExecutor {
    private let tools: [Tool]
    private var cancellables = Set<AnyCancellable>()
    
    init(tools: [Tool]) {
        self.tools = tools
    }
    
    func execute() async throws {
        var input: Any? = nil
        
        for tool in tools {
            do {
                input = try await tool.execute(input: input)
            } catch {
                throw ToolChainError.toolExecutionFailed(tool: tool, error: error)
            }
        }
    }
}

// MARK: - Tool

protocol Tool {
    func execute(input: Any?) async throws -> Any?
}

// MARK: - ToolChainError

enum ToolChainError: Error {
    case toolExecutionFailed(tool: Tool, error: Error)
}

// MARK: - Example Tools

struct ExampleTool1: Tool {
    func execute(input: Any?) async throws -> Any? {
        // Simulate some processing
        return "Processed by ExampleTool1"
    }
}

struct ExampleTool2: Tool {
    func execute(input: Any?) async throws -> Any? {
        // Simulate some processing
        return "Processed by ExampleTool2"
    }
}
