import Foundation
import SwiftUI

// MARK: - Tool Metadata

struct ToolMetadata {
    let name: String
    let description: String
    let parameters: [String: Any]
    let examples: [String]
}

// MARK: - Tool Protocol

protocol Tool {
    var metadata: ToolMetadata { get }
    func execute(parameters: [String: Any]) async throws -> Any
}

// MARK: - Tool Registry

class ToolRegistry: ObservableObject {
    @Published private(set) var tools: [String: Tool] = [:]

    func register(tool: Tool) {
        tools[tool.metadata.name] = tool
    }

    func unregister(toolName: String) {
        tools.removeValue(forKey: toolName)
    }

    func discoverTools() -> [String] {
        return tools.keys.map { $0 }
    }

    func executeTool(name: String, parameters: [String: Any]) async throws -> Any {
        guard let tool = tools[name] else {
            throw NSError(domain: "ToolRegistry", code: 1, userInfo: [NSLocalizedDescriptionKey: "Tool not found"])
        }
        return try await tool.execute(parameters: parameters)
    }
}

// MARK: - Example Tool Implementations

struct ExampleTool: Tool {
    let metadata: ToolMetadata

    init(name: String, description: String, parameters: [String: Any], examples: [String]) {
        self.metadata = ToolMetadata(name: name, description: description, parameters: parameters, examples: examples)
    }

    func execute(parameters: [String: Any]) async throws -> Any {
        // Example execution logic
        return "Executed \(metadata.name) with parameters: \(parameters)"
    }
}

// MARK: - SwiftUI View for Tool Registry

struct ToolRegistryView: View {
    @StateObject private var viewModel = ToolRegistryViewModel()

    var body: some View {
        VStack {
            List(viewModel.toolNames, id: \.self) { toolName in
                Text(toolName)
            }
            Button("Discover Tools") {
                viewModel.discoverTools()
            }
        }
        .onAppear {
            viewModel.registerExampleTools()
        }
    }
}

// MARK: - ViewModel for Tool Registry View

class ToolRegistryViewModel: ObservableObject {
    @Published var toolNames: [String] = []

    private let toolRegistry = ToolRegistry()

    func registerExampleTools() {
        let exampleTool = ExampleTool(name: "ExampleTool", description: "An example tool", parameters: [:], examples: [])
        toolRegistry.register(tool: exampleTool)
        toolNames = toolRegistry.discoverTools()
    }

    func discoverTools() {
        toolNames = toolRegistry.discoverTools()
    }
}