//
//  SiriIntents.swift
//  ZeroDark
//
//  Siri Integration via App Intents (iOS 16+)
//  "Hey Siri, ask ZeroDark..."
//

import AppIntents
import SwiftUI

// MARK: - Ask ZeroDark Intent

@available(iOS 16.0, *)
struct AskZeroDarkIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask ZeroDark"
    static var description = IntentDescription("Ask ZeroDark AI a question or give it a task")
    
    @Parameter(title: "Question or Task")
    var query: String
    
    static var parameterSummary: some ParameterSummary {
        Summary("Ask ZeroDark \(\.$query)")
    }
    
    static var openAppWhenRun: Bool = false
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let engine = UnifiedInferenceEngine.shared
        let response = await engine.generate(prompt: query, maxTokens: 200)
        return .result(dialog: IntentDialog(stringLiteral: response))
    }
}

// MARK: - Weather Intent

@available(iOS 16.0, *)
struct GetWeatherIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Weather"
    static var description = IntentDescription("Get current weather from ZeroDark")
    
    @Parameter(title: "Location", default: "San Antonio")
    var location: String
    
    static var parameterSummary: some ParameterSummary {
        Summary("Get weather in \(\.$location)")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let toolkit = AgentToolkit.shared
        let call = AgentToolkit.ToolCall(tool: "weather", arguments: ["location": location])
        let result = await toolkit.execute(call)
        return .result(dialog: IntentDialog(stringLiteral: result.output))
    }
}

// MARK: - Create Reminder Intent

@available(iOS 16.0, *)
struct CreateReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Reminder"
    static var description = IntentDescription("Create a reminder with ZeroDark")
    
    @Parameter(title: "Title")
    var title: String
    
    static var parameterSummary: some ParameterSummary {
        Summary("Remind me to \(\.$title)")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let toolkit = AgentToolkit.shared
        let call = AgentToolkit.ToolCall(tool: "reminder", arguments: ["title": title])
        let result = await toolkit.execute(call)
        return .result(dialog: IntentDialog(stringLiteral: result.output))
    }
}

// MARK: - Quick Calculate Intent

@available(iOS 16.0, *)
struct CalculateIntent: AppIntent {
    static var title: LocalizedStringResource = "Calculate"
    static var description = IntentDescription("Do math calculations with ZeroDark")
    
    @Parameter(title: "Expression")
    var expression: String
    
    static var parameterSummary: some ParameterSummary {
        Summary("Calculate \(\.$expression)")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let toolkit = AgentToolkit.shared
        let call = AgentToolkit.ToolCall(tool: "calculator", arguments: ["expression": expression])
        let result = await toolkit.execute(call)
        return .result(dialog: IntentDialog(stringLiteral: result.output))
    }
}

// MARK: - Health Check Intent

@available(iOS 16.0, *)
struct HealthCheckIntent: AppIntent {
    static var title: LocalizedStringResource = "Health Check"
    static var description = IntentDescription("Get health data from ZeroDark")
    
    @Parameter(title: "Metric", default: "steps")
    var metric: String
    
    static var parameterSummary: some ParameterSummary {
        Summary("Get my \(\.$metric)")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let toolkit = AgentToolkit.shared
        let call = AgentToolkit.ToolCall(tool: "health", arguments: ["metric": metric])
        let result = await toolkit.execute(call)
        return .result(dialog: IntentDialog(stringLiteral: result.output))
    }
}

// MARK: - Set Timer Intent

@available(iOS 16.0, *)
struct SetTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Timer"
    static var description = IntentDescription("Set a timer with ZeroDark")
    
    @Parameter(title: "Minutes", default: 5)
    var minutes: Int
    
    static var parameterSummary: some ParameterSummary {
        Summary("Set timer for \(\.$minutes) minutes")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let toolkit = AgentToolkit.shared
        let call = AgentToolkit.ToolCall(tool: "timer", arguments: ["duration": "\(minutes)"])
        let result = await toolkit.execute(call)
        return .result(dialog: IntentDialog(stringLiteral: result.output))
    }
}

// MARK: - Open App Intent

@available(iOS 16.0, *)
struct OpenAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Open App"
    static var description = IntentDescription("Open an app with ZeroDark")
    
    @Parameter(title: "App Name")
    var appName: String
    
    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$appName)")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let toolkit = AgentToolkit.shared
        let call = AgentToolkit.ToolCall(tool: "open_app", arguments: ["app": appName])
        let result = await toolkit.execute(call)
        return .result(dialog: IntentDialog(stringLiteral: result.output))
    }
}

// MARK: - Convert Units Intent

@available(iOS 16.0, *)
struct ConvertIntent: AppIntent {
    static var title: LocalizedStringResource = "Convert Units"
    static var description = IntentDescription("Convert units with ZeroDark")
    
    @Parameter(title: "Value")
    var value: String
    
    @Parameter(title: "From Unit")
    var fromUnit: String
    
    @Parameter(title: "To Unit")
    var toUnit: String
    
    static var parameterSummary: some ParameterSummary {
        Summary("Convert \(\.$value) \(\.$fromUnit) to \(\.$toUnit)")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let toolkit = AgentToolkit.shared
        let call = AgentToolkit.ToolCall(tool: "convert", arguments: ["value": value, "from": fromUnit, "to": toUnit])
        let result = await toolkit.execute(call)
        return .result(dialog: IntentDialog(stringLiteral: result.output))
    }
}

// MARK: - Speak Text Intent

@available(iOS 16.0, *)
struct SpeakIntent: AppIntent {
    static var title: LocalizedStringResource = "Speak Text"
    static var description = IntentDescription("Have ZeroDark speak text aloud")
    
    @Parameter(title: "Text")
    var text: String
    
    static var parameterSummary: some ParameterSummary {
        Summary("Say \(\.$text)")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let toolkit = AgentToolkit.shared
        let call = AgentToolkit.ToolCall(tool: "speak", arguments: ["text": text])
        let result = await toolkit.execute(call)
        return .result(dialog: IntentDialog(stringLiteral: result.output))
    }
}

// MARK: - App Shortcuts Provider (Static Phrases Only)

@available(iOS 16.0, *)
struct ZeroDarkShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskZeroDarkIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Hey \(.applicationName)",
                "Talk to \(.applicationName)",
            ],
            shortTitle: "Ask ZeroDark",
            systemImageName: "brain"
        )
        
        AppShortcut(
            intent: GetWeatherIntent(),
            phrases: [
                "\(.applicationName) weather",
                "Get weather with \(.applicationName)",
            ],
            shortTitle: "Weather",
            systemImageName: "cloud.sun"
        )
        
        AppShortcut(
            intent: CreateReminderIntent(),
            phrases: [
                "\(.applicationName) reminder",
                "Create reminder with \(.applicationName)",
            ],
            shortTitle: "Create Reminder",
            systemImageName: "bell"
        )
        
        AppShortcut(
            intent: CalculateIntent(),
            phrases: [
                "\(.applicationName) calculate",
                "Math with \(.applicationName)",
            ],
            shortTitle: "Calculate",
            systemImageName: "function"
        )
        
        AppShortcut(
            intent: HealthCheckIntent(),
            phrases: [
                "\(.applicationName) health",
                "Health check \(.applicationName)",
            ],
            shortTitle: "Health Check",
            systemImageName: "heart"
        )
        
        AppShortcut(
            intent: SetTimerIntent(),
            phrases: [
                "\(.applicationName) timer",
                "Set timer with \(.applicationName)",
            ],
            shortTitle: "Set Timer",
            systemImageName: "timer"
        )
        
        AppShortcut(
            intent: OpenAppIntent(),
            phrases: [
                "Open app with \(.applicationName)",
                "\(.applicationName) open app",
            ],
            shortTitle: "Open App",
            systemImageName: "app"
        )
        
        AppShortcut(
            intent: ConvertIntent(),
            phrases: [
                "Convert with \(.applicationName)",
                "\(.applicationName) convert",
            ],
            shortTitle: "Convert",
            systemImageName: "arrow.left.arrow.right"
        )
        
        AppShortcut(
            intent: SpeakIntent(),
            phrases: [
                "\(.applicationName) say",
                "Speak with \(.applicationName)",
            ],
            shortTitle: "Speak",
            systemImageName: "speaker.wave.2"
        )
    }
}
