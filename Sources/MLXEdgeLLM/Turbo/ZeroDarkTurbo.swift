import Foundation
import SwiftUI

// MARK: - Zero Dark Turbo

/// The simplest possible API. One function. Maximum intelligence.

public struct ZeroDark {
    
    /// Ask Zero Dark anything
    @MainActor
    public static func ask(
        _ prompt: String,
        stream: ((String) -> Void)? = nil
    ) async throws -> String {
        let ai = ZeroDarkAI.shared
        
        var response = ""
        response = try await ai.process(prompt: prompt, onToken: { token in
            response = token
            stream?(token)
        })
        
        return response
    }
    
    /// Quick question, no streaming
    @MainActor
    public static func quick(_ prompt: String) async throws -> String {
        try await ask(prompt, stream: nil)
    }
    
    /// Code generation
    @MainActor
    public static func code(_ description: String, language: String = "Swift") async throws -> String {
        try await ask("Write \(language) code: \(description)\n\nProvide only the code, no explanation.")
    }
    
    /// Translate text
    @MainActor
    public static func translate(_ text: String, to language: String) async throws -> String {
        try await ask("Translate to \(language): \(text)")
    }
    
    /// Summarize content
    @MainActor
    public static func summarize(_ text: String) async throws -> String {
        try await ask("Summarize in 2-3 sentences: \(text)")
    }
    
    /// Explain something
    @MainActor
    public static func explain(_ topic: String) async throws -> String {
        try await ask("Explain \(topic) in simple terms.")
    }
    
    /// Run a tool directly
    public static func tool(_ name: String, args: [String: String] = [:]) async -> String {
        let toolkit = await AgentToolkit.shared
        let call = AgentToolkit.ToolCall(tool: name, arguments: args)
        let result = await toolkit.execute(call)
        return result.output
    }
    
    /// Call on app launch
    @MainActor
    public static func warmup() async {
        _ = ZeroDarkAI.shared
    }
}

// MARK: - SwiftUI Integration

public extension View {
    
    @MainActor
    func zeroDark(
        prompt: Binding<String>,
        response: Binding<String>,
        isLoading: Binding<Bool>
    ) -> some View {
        self.onChange(of: prompt.wrappedValue) { _, newPrompt in
            guard !newPrompt.isEmpty else { return }
            
            isLoading.wrappedValue = true
            
            Task {
                do {
                    let result = try await ZeroDark.ask(newPrompt) { partial in
                        response.wrappedValue = partial
                    }
                    response.wrappedValue = result
                    isLoading.wrappedValue = false
                } catch {
                    response.wrappedValue = "Error: \(error.localizedDescription)"
                    isLoading.wrappedValue = false
                }
            }
        }
    }
}
