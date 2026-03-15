import Foundation
import Combine

// MARK: - Nuclear Mode Controller

/// Unified controller for all nuclear capabilities
@MainActor
public final class NuclearMode: ObservableObject {
    
    public static let shared = NuclearMode()
    
    // MARK: - Capabilities
    
    public struct Capabilities {
        public var agentTools: Bool = true
        public var codeSandbox: Bool = true
        public var voicePipeline: Bool = false
        public var screenUnderstanding: Bool = false
        public var healthIntegration: Bool = false
        public var smartHome: Bool = false
        public var liveTranslation: Bool = false
        
        public var summary: String {
            var active: [String] = []
            if agentTools { active.append("🔧 Agent Tools") }
            if codeSandbox { active.append("💻 Code Sandbox") }
            if voicePipeline { active.append("🎤 Voice Pipeline") }
            if screenUnderstanding { active.append("👁️ Screen Understanding") }
            if healthIntegration { active.append("❤️ Health Integration") }
            if smartHome { active.append("🏠 Smart Home") }
            if liveTranslation { active.append("🌐 Live Translation") }
            return active.isEmpty ? "No capabilities enabled" : active.joined(separator: "\n")
        }
    }
    
    // MARK: - State
    
    @Published public var capabilities = Capabilities()
    @Published public var isInitialized: Bool = false
    
    // MARK: - Components
    
    public let toolkit = AgentToolkit.shared
    public let sandbox = CodeSandbox.shared
    public let voice = VoicePipeline.shared
    #if os(macOS)
    public let screen = ScreenUnderstanding.shared
    #endif
    public let health = HealthIntegration.shared
    public let home = SmartHomeControl.shared
    public let translation = LiveTranslation.shared
    
    // MARK: - Init
    
    private init() {
        Task {
            await initialize()
        }
    }
    
    // MARK: - Initialize
    
    public func initialize() async {
        // Check each capability
        
        // Agent Tools - always available
        capabilities.agentTools = true
        
        // Code Sandbox - always available (uses JavaScriptCore)
        capabilities.codeSandbox = true
        
        // Voice Pipeline
        _ = voice.isAvailable
        capabilities.voicePipeline = voice.isAvailable
        
        // Screen Understanding (macOS only)
        #if os(macOS)
        capabilities.screenUnderstanding = screen.isAvailable
        #endif
        
        // Health Integration
        capabilities.healthIntegration = health.isAvailable
        
        // Smart Home
        capabilities.smartHome = home.isAvailable
        
        // Live Translation
        capabilities.liveTranslation = translation.isAvailable
        
        isInitialized = true
    }
    
    // MARK: - Request Permissions
    
    public func requestAllPermissions() async {
        // Voice
        if capabilities.voicePipeline {
            _ = voice.isAvailable
        }
        
        // Health
        if capabilities.healthIntegration {
            try? await health.requestAuthorization()
        }
    }
    
    // MARK: - System Prompt Enhancement
    
    public func generateSystemPromptAddition() async -> String {
        var lines: [String] = []
        
        lines.append("## Available Capabilities")
        lines.append("")
        
        // Agent Tools
        if capabilities.agentTools {
            lines.append("### 🔧 Agent Tools")
            lines.append("You can use the following tools by responding with tool_call XML:")
            let toolsPrompt = await toolkit.generateToolsPrompt()
            lines.append(toolsPrompt)
            lines.append("")
        }
        
        // Code Sandbox
        if capabilities.codeSandbox {
            lines.append("### 💻 Code Sandbox")
            lines.append("You can execute code on-device. Wrap code in ```javascript or ```python blocks.")
            lines.append("The code will be executed locally and the result returned.")
            lines.append("")
        }
        
        // Voice
        if capabilities.voicePipeline {
            lines.append("### 🎤 Voice Pipeline")
            lines.append("Voice input and output is available.")
            lines.append("The user may speak to you and you can respond with speech.")
            lines.append("")
        }
        
        // Screen Understanding
        #if os(macOS)
        if capabilities.screenUnderstanding {
            lines.append("### 👁️ Screen Understanding")
            lines.append("You can capture and analyze the user's screen to understand context.")
            lines.append("Use this to help with tasks visible on screen.")
            lines.append("")
        }
        #endif
        
        // Health
        if capabilities.healthIntegration && health.isAuthorized {
            lines.append("### ❤️ Health Integration")
            lines.append("You have access to the user's health data from Apple Health.")
            if let summary = health.lastSummary {
                lines.append("Latest health data:")
                lines.append(summary.asPromptContext)
            }
            lines.append("")
        }
        
        // Smart Home
        if capabilities.smartHome && home.isAvailable {
            lines.append("### 🏠 Smart Home Control")
            lines.append("You can control HomeKit devices.")
            lines.append("")
        }
        
        // Translation
        if capabilities.liveTranslation {
            lines.append("### 🌐 Live Translation")
            lines.append("You can translate text between languages on-device.")
            lines.append("Supported languages: English, Spanish, French, German, Italian, Portuguese, Chinese, Japanese, Korean, Arabic, Russian, Hindi")
            lines.append("")
        }
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Process Tool Calls
    
    public func processResponse(_ response: String) async -> (cleanedResponse: String, toolResults: [String]) {
        var cleaned = response
        var results: [String] = []
        
        // Process tool calls
        if capabilities.agentTools {
            let calls = await toolkit.parseToolCalls(from: response)
            
            for call in calls {
                let result = await toolkit.execute(call)
                results.append("[\(call.tool)] \(result.output)")
                
                // Remove tool_call from response
                if let range = cleaned.range(of: "<tool_call>[\\s\\S]*?</tool_call>", options: .regularExpression) {
                    cleaned.removeSubrange(range)
                }
            }
        }
        
        // Process code blocks
        if capabilities.codeSandbox {
            let codeBlocks = CodeBlockParser.parse(response)
            
            for block in codeBlocks {
                let result = await sandbox.execute(code: block.code, language: block.language)
                if result.success {
                    results.append("[Code Output] \(result.output)")
                } else if let error = result.error {
                    results.append("[Code Error] \(error)")
                }
            }
        }
        
        return (cleaned.trimmingCharacters(in: .whitespacesAndNewlines), results)
    }
    
    // MARK: - Agentic Loop
    
    /// Run a full agentic loop with tool execution
    public func runAgenticLoop(
        prompt: String,
        generateResponse: @escaping (String) async throws -> String,
        maxIterations: Int = 5
    ) async throws -> String {
        var currentPrompt = prompt
        var iteration = 0
        var finalResponse = ""
        
        while iteration < maxIterations {
            // Generate response
            let response = try await generateResponse(currentPrompt)
            
            // Process tool calls
            let (cleaned, toolResults) = await processResponse(response)
            
            if toolResults.isEmpty {
                // No tools called, we're done
                finalResponse = cleaned
                break
            }
            
            // Build continuation prompt with tool results
            var continuation = cleaned + "\n\n"
            continuation += "Tool Results:\n"
            for result in toolResults {
                continuation += "- \(result)\n"
            }
            continuation += "\nContinue your response based on these results."
            
            currentPrompt = continuation
            iteration += 1
        }
        
        return finalResponse
    }
}

// MARK: - Nuclear Mode UI Extension

public extension NuclearMode {
    
    var capabilityIcons: [(name: String, icon: String, available: Bool)] {
        var icons: [(name: String, icon: String, available: Bool)] = [
            ("Agent Tools", "wrench.and.screwdriver", capabilities.agentTools),
            ("Code Sandbox", "terminal", capabilities.codeSandbox),
            ("Voice Pipeline", "mic.fill", capabilities.voicePipeline),
            ("Health Integration", "heart.fill", capabilities.healthIntegration),
            ("Smart Home", "house.fill", capabilities.smartHome),
            ("Live Translation", "globe", capabilities.liveTranslation)
        ]
        #if os(macOS)
        icons.append(("Screen Understanding", "eye", capabilities.screenUnderstanding))
        #endif
        return icons
    }
}

// MARK: - Use Case Descriptions

public struct NuclearUseCases {
    
    public static let cases: [(title: String, description: String, capability: String)] = [
        // Agent Tools
        ("Calculate anything", "Ask 'What's 15% of $847?' and get instant answers", "Agent Tools"),
        ("Create reminders", "'Remind me to call mom tomorrow at 3pm' → Apple Reminders", "Agent Tools"),
        ("Unit conversion", "'Convert 5 miles to kilometers' → instant conversion", "Agent Tools"),
        ("Date math", "'What date is 45 days from now?' → calculated", "Agent Tools"),
        ("Generate UUIDs", "Create random IDs, pick random items, roll dice", "Agent Tools"),
        
        // Code Sandbox
        ("Run JavaScript", "Execute JS code directly on device", "Code Sandbox"),
        ("Python-like syntax", "Write Python, runs as transpiled JS", "Code Sandbox"),
        ("Data processing", "Sort, filter, transform data with code", "Code Sandbox"),
        ("Regex testing", "Test regex patterns with multiple inputs", "Code Sandbox"),
        ("JSON validation", "Parse and pretty-print JSON", "Code Sandbox"),
        
        // Voice Pipeline
        ("Voice assistant", "Speak naturally, get spoken responses", "Voice Pipeline"),
        ("Hands-free mode", "Full conversation without touching screen", "Voice Pipeline"),
        ("Wake word", "Say 'Hey Zero' to activate", "Voice Pipeline"),
        ("Dictation", "Speak your messages and documents", "Voice Pipeline"),
        
        // Screen Understanding (macOS)
        ("Analyze screen", "Ask 'What's on my screen?' and get context", "Screen Understanding"),
        ("Help with UI", "Get guidance on visible applications", "Screen Understanding"),
        ("Extract text", "Pull text from any window", "Screen Understanding"),
        
        // Health Integration
        ("Daily health summary", "'How did I sleep?' → HealthKit data", "Health Integration"),
        ("Fitness tracking", "Steps, calories, exercise minutes", "Health Integration"),
        ("Health trends", "Analyze patterns over time", "Health Integration"),
        ("Workout history", "Review recent workouts", "Health Integration"),
        
        // Smart Home
        ("Control lights", "'Turn on living room lights' → HomeKit", "Smart Home"),
        ("Set temperature", "'Set thermostat to 72' → instant control", "Smart Home"),
        ("Run scenes", "'Activate movie night scene'", "Smart Home"),
        ("Room control", "'Turn off everything in bedroom'", "Smart Home"),
        
        // Translation
        ("Instant translation", "Translate text to any supported language", "Live Translation"),
        ("Conversation mode", "Real-time bilingual conversation", "Live Translation"),
        ("Language detection", "Auto-detect input language", "Live Translation"),
        ("Offline translation", "Works without internet (after download)", "Live Translation"),
    ]
}
