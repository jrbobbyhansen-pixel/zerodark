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
    }
}
