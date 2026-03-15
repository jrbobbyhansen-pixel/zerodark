import Foundation
import AppIntents

// MARK: - Shortcuts Integration

/// Expose Zero Dark to Siri Shortcuts
/// This lets users build automations with Zero Dark as the brain

// MARK: - App Shortcuts Provider

@available(iOS 16.0, macOS 13.0, *)
public struct ZeroDarkShortcuts: AppShortcutsProvider {
    
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskZeroDarkIntent(),
            phrases: [
                "Ask \(.applicationName) \(\.$prompt)",
                "Hey \(.applicationName) \(\.$prompt)",
                "\(.applicationName) \(\.$prompt)"
            ],
            shortTitle: "Ask Zero Dark",
            systemImageName: "brain"
        )
        
        AppShortcut(
            intent: GenerateCodeIntent(),
            phrases: [
                "Generate code with \(.applicationName)",
                "Write code in \(.applicationName)"
            ],
            shortTitle: "Generate Code",
            systemImageName: "chevron.left.forwardslash.chevron.right"
        )
        
        AppShortcut(
            intent: SummarizeIntent(),
            phrases: [
                "Summarize with \(.applicationName)",
                "Summarize \(\.$text)"
            ],
            shortTitle: "Summarize",
            systemImageName: "doc.text"
        )
        
        AppShortcut(
            intent: RunToolIntent(),
            phrases: [
                "Run \(.applicationName) tool",
                "Use \(\.$toolName) in \(.applicationName)"
            ],
            shortTitle: "Run Tool",
            systemImageName: "wrench"
        )
    }
}

// MARK: - Ask Zero Dark Intent

@available(iOS 16.0, macOS 13.0, *)
public struct AskZeroDarkIntent: AppIntent {
    public static var title: LocalizedStringResource = "Ask Zero Dark"
    public static var description = IntentDescription("Ask Zero Dark anything")
    public static var openAppWhenRun: Bool = false
    
    @Parameter(title: "Prompt")
    public var prompt: String
    
    public init() {}
    
    public init(prompt: String) {
        self.prompt = prompt
    }
    
    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        var response = ""
        let _ = try await ZeroDarkAI.shared.process(
            prompt: prompt,
            onToken: { token in response = token }
        )
        return .result(value: response)
    }
}

// MARK: - Generate Code Intent

@available(iOS 16.0, macOS 13.0, *)
public struct GenerateCodeIntent: AppIntent {
    public static var title: LocalizedStringResource = "Generate Code"
    public static var description = IntentDescription("Generate code with Zero Dark")
    
    @Parameter(title: "Description")
    public var description_text: String
    
    @Parameter(title: "Language", default: "Swift")
    public var language: String
    
    public init() {}
    
    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let prompt = "Write \(language) code that: \(description_text)\n\nProvide only the code, no explanation."
        
        var response = ""
        let _ = try await ZeroDarkAI.shared.process(
            prompt: prompt,
            forceModel: .qwen25_coder_7b,
            onToken: { token in response = token }
        )
        return .result(value: response)
    }
}

// MARK: - Summarize Intent

@available(iOS 16.0, macOS 13.0, *)
public struct SummarizeIntent: AppIntent {
    public static var title: LocalizedStringResource = "Summarize"
    public static var description = IntentDescription("Summarize text with Zero Dark")
    
    @Parameter(title: "Text")
    public var text: String
    
    @Parameter(title: "Style", default: "brief")
    public var style: String
    
    public init() {}
    
    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let prompt: String
        switch style.lowercased() {
        case "bullet":
            prompt = "Summarize in bullet points:\n\n\(text)"
        case "detailed":
            prompt = "Provide a detailed summary:\n\n\(text)"
        default:
            prompt = "Summarize in 2-3 sentences:\n\n\(text)"
        }
        
        var response = ""
        let _ = try await ZeroDarkAI.shared.process(
            prompt: prompt,
            onToken: { token in response = token }
        )
        return .result(value: response)
    }
}

// MARK: - Run Tool Intent

@available(iOS 16.0, macOS 13.0, *)
public struct RunToolIntent: AppIntent {
    public static var title: LocalizedStringResource = "Run Tool"
    public static var description = IntentDescription("Run a Zero Dark tool")
    
    @Parameter(title: "Tool Name")
    public var toolName: String
    
    @Parameter(title: "Arguments (JSON)")
    public var arguments: String?
    
    public init() {}
    
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        var args: [String: String] = [:]
        
        if let argsJson = arguments,
           let data = argsJson.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            args = parsed.mapValues { String(describing: $0) }
        }
        
        let toolkit = await AgentToolkit.shared
        let call = AgentToolkit.ToolCall(tool: toolName, arguments: args)
        let result = await toolkit.execute(call)
        
        return .result(value: result.output)
    }
}
