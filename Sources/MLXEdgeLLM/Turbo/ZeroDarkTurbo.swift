import Foundation

// MARK: - Zero Dark Turbo

/// The simplest possible API. One function. Maximum intelligence.
/// All complexity hidden. All optimizations automatic.

public struct ZeroDark {
    
    // MARK: - The One Function
    
    /// Ask Zero Dark anything. That's it.
    ///
    /// ```swift
    /// let answer = await ZeroDark.ask("What is the meaning of life?")
    /// ```
    ///
    /// Everything else is automatic:
    /// - Model selection based on task
    /// - Quality adjustment based on device state
    /// - Tool execution if needed
    /// - Memory integration
    /// - Response caching
    /// - Streaming to callback
    ///
    public static func ask(
        _ prompt: String,
        stream: ((String) -> Void)? = nil
    ) async throws -> String {
        
        // 1. Check response cache
        let router = await ModelRouter.shared
        let taskType = await router.detectTaskType(prompt)
        let optimalModel = await AdaptiveInference.shared.getOptimalModel(for: taskType)
        
        if let cached = await ResponseCache.shared.lookup(prompt: prompt, model: optimalModel) {
            stream?(cached)
            return cached
        }
        
        // 2. Get or preload engine
        let engine = try await ModelPreloader.shared.getEngine(optimalModel)
        
        // 3. Build context with memory
        let memory = await ConversationMemory.shared
        let context = await memory.buildContext(for: prompt)
        let fullPrompt = context.isEmpty ? prompt : "\(context)\n\nUser: \(prompt)"
        
        // 4. Adjust parameters adaptively
        var params = BeastParams.balanced
        await AdaptiveInference.shared.adjustParameters(&params)
        engine.setParams(params)
        
        // 5. Generate with streaming
        var response = ""
        response = try await engine.generate(prompt: fullPrompt) { token in
            response = token
            stream?(token)
        }
        
        // 6. Process tool calls if present
        let nuclear = await NuclearMode.shared
        let (cleaned, toolResults) = await nuclear.processResponse(response)
        
        if !toolResults.isEmpty {
            // Re-generate with tool results
            let toolContext = toolResults.joined(separator: "\n")
            let followUp = try await engine.generate(
                prompt: fullPrompt + "\n\nAssistant: " + cleaned + "\n\nTool Results:\n" + toolContext + "\n\nContinue:"
            ) { token in
                stream?(token)
            }
            response = followUp
        }
        
        // 7. Cache response
        await ResponseCache.shared.store(prompt: prompt, response: response, model: optimalModel)
        
        // 8. Learn from interaction
        await memory.extractAndLearn(from: "User: \(prompt)\nAssistant: \(response)")
        
        return response
    }
    
    // MARK: - Convenience Methods
    
    /// Quick question, no streaming
    public static func quick(_ prompt: String) async throws -> String {
        try await ask(prompt, stream: nil)
    }
    
    /// Code generation
    public static func code(_ description: String, language: String = "Swift") async throws -> String {
        try await ask("Write \(language) code: \(description)\n\nProvide only the code, no explanation.")
    }
    
    /// Translate text
    public static func translate(_ text: String, to language: String) async throws -> String {
        try await ask("Translate to \(language): \(text)")
    }
    
    /// Summarize content
    public static func summarize(_ text: String) async throws -> String {
        try await ask("Summarize in 2-3 sentences: \(text)")
    }
    
    /// Explain something
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
    
    // MARK: - Configuration
    
    /// Configure Zero Dark behavior
    public static func configure(_ config: Configuration) async {
        let adaptive = await AdaptiveInference.shared
        adaptive.isAutomatic = config.automaticQuality
        if let level = config.qualityLevel {
            adaptive.currentLevel = level
        }
        
        let preloader = await ModelPreloader.shared
        preloader.config.preloadOnLaunch = config.preloadOnLaunch
        preloader.config.predictivePreload = config.predictivePreload
    }
    
    public struct Configuration {
        public var automaticQuality: Bool = true
        public var qualityLevel: AdaptiveInference.QualityLevel?
        public var preloadOnLaunch: Bool = true
        public var predictivePreload: Bool = true
        public var enableTools: Bool = true
        public var enableMemory: Bool = true
        
        public static let `default` = Configuration()
        public static var performance: Configuration {
            var c = Configuration()
            c.qualityLevel = .fast
            return c
        }
        public static var quality: Configuration {
            var c = Configuration()
            c.qualityLevel = .maximum
            return c
        }
    }
    
    // MARK: - Lifecycle
    
    /// Call on app launch
    public static func warmup() async {
        await ModelPreloader.shared.warmup()
    }
    
    /// Call when entering background
    public static func prepareForBackground() async {
        await ModelPreloader.shared.prepareForBackground()
    }
}

// MARK: - SwiftUI Integration

import SwiftUI

/// Simple SwiftUI view modifier
public extension View {
    
    /// Add Zero Dark AI to any view
    func zeroDark(
        prompt: Binding<String>,
        response: Binding<String>,
        isLoading: Binding<Bool>
    ) -> some View {
        self.onChange(of: prompt.wrappedValue) { newPrompt in
            guard !newPrompt.isEmpty else { return }
            
            isLoading.wrappedValue = true
            
            Task {
                do {
                    let result = try await ZeroDark.ask(newPrompt) { partial in
                        Task { @MainActor in
                            response.wrappedValue = partial
                        }
                    }
                    await MainActor.run {
                        response.wrappedValue = result
                        isLoading.wrappedValue = false
                    }
                } catch {
                    await MainActor.run {
                        response.wrappedValue = "Error: \(error.localizedDescription)"
                        isLoading.wrappedValue = false
                    }
                }
            }
        }
    }
}

// MARK: - One-Line Examples

/*
 
 // Ask anything
 let answer = await ZeroDark.ask("What is the capital of France?")
 
 // Stream response
 let _ = await ZeroDark.ask("Write a poem") { partial in
     print(partial)
 }
 
 // Generate code
 let code = await ZeroDark.code("sort an array", language: "Python")
 
 // Translate
 let spanish = await ZeroDark.translate("Hello world", to: "Spanish")
 
 // Summarize
 let summary = await ZeroDark.summarize(longArticle)
 
 // Use tools
 let weather = await ZeroDark.tool("weather", args: ["location": "Austin"])
 
 // SwiftUI
 struct MyView: View {
     @State var prompt = ""
     @State var response = ""
     @State var loading = false
     
     var body: some View {
         TextField("Ask...", text: $prompt)
         Text(response)
     }
     .zeroDark(prompt: $prompt, response: $response, isLoading: $loading)
 }
 
 */
