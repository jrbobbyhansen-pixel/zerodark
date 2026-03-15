import Foundation
import AppIntents
import Intents

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
            intent: TranslateIntent(),
            phrases: [
                "Translate with \(.applicationName)",
                "Translate \(\.$text) to \(\.$language)"
            ],
            shortTitle: "Translate",
            systemImageName: "globe"
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
    
    @Parameter(title: "Model", default: "auto")
    public var model: String
    
    public init() {}
    
    public init(prompt: String, model: String = "auto") {
        self.prompt = prompt
        self.model = model
    }
    
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let ai = await ZeroDarkAI.shared
        
        let selectedModel: Model
        if model == "auto" {
            selectedModel = .qwen3_8b
        } else {
            selectedModel = Model.allCases.first { $0.rawValue == model } ?? .qwen3_8b
        }
        
        let response = try await ai.generate(prompt, model: selectedModel, stream: false)
        
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
    
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let prompt = "Write \(language) code that: \(description_text)\n\nProvide only the code, no explanation."
        
        let ai = await ZeroDarkAI.shared
        let response = try await ai.generate(prompt, model: .qwen25_coder_7b, stream: false)
        
        return .result(value: response)
    }
}

// MARK: - Translate Intent

@available(iOS 16.0, macOS 13.0, *)
public struct TranslateIntent: AppIntent {
    public static var title: LocalizedStringResource = "Translate"
    public static var description = IntentDescription("Translate text with Zero Dark")
    
    @Parameter(title: "Text")
    public var text: String
    
    @Parameter(title: "Target Language", default: "Spanish")
    public var language: String
    
    public init() {}
    
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let translation = LiveTranslation.shared
        
        let targetLang = LiveTranslation.Language.all.first { 
            $0.name.lowercased() == language.lowercased() 
        } ?? .spanish
        
        if #available(iOS 17.4, macOS 14.4, *) {
            let translated = try await translation.translate(text, to: targetLang)
            return .result(value: translated)
        } else {
            // Fallback to LLM translation
            let prompt = "Translate to \(language): \(text)"
            let ai = await ZeroDarkAI.shared
            let response = try await ai.generate(prompt, stream: false)
            return .result(value: response)
        }
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
        
        let ai = await ZeroDarkAI.shared
        let response = try await ai.generate(prompt, stream: false)
        
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

// MARK: - Conversation Intent

@available(iOS 16.0, macOS 13.0, *)
public struct ContinueConversationIntent: AppIntent {
    public static var title: LocalizedStringResource = "Continue Conversation"
    public static var description = IntentDescription("Continue a Zero Dark conversation")
    public static var openAppWhenRun: Bool = true
    
    @Parameter(title: "Message")
    public var message: String
    
    @Parameter(title: "Conversation ID")
    public var conversationId: String?
    
    public init() {}
    
    public func perform() async throws -> some IntentResult {
        // Open app with conversation context
        return .result()
    }
}

// MARK: - Voice Shortcut

@available(iOS 16.0, macOS 13.0, *)
public struct VoiceConversationIntent: AppIntent {
    public static var title: LocalizedStringResource = "Voice Conversation"
    public static var description = IntentDescription("Start a voice conversation with Zero Dark")
    public static var openAppWhenRun: Bool = true
    
    public init() {}
    
    public func perform() async throws -> some IntentResult {
        // Start voice pipeline
        let voice = await VoicePipeline.shared
        try await voice.startListening()
        return .result()
    }
}
