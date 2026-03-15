// SiriIntegration.swift
// "Hey Siri, ask Zero Dark..." → Your 14B answers instead of Apple's servers
// THE TAKEOVER

import Foundation

// MARK: - Siri Integration Protocol

/// Protocol for integrating with Siri Shortcuts
/// Actual AppIntents implementation should be in the app target to avoid duplicate declarations
public protocol SiriIntegrable {
    func processVoiceCommand(_ command: String) async throws -> String
    func processWithTools(_ command: String, useTools: Bool) async throws -> String
}

// MARK: - Siri Command Processor

/// Processes commands from Siri Shortcuts
public actor SiriCommandProcessor: SiriIntegrable {
    
    public static let shared = SiriCommandProcessor()
    
    private init() {}
    
    /// Process a voice command from Siri
    public func processVoiceCommand(_ command: String) async throws -> String {
        let ai = await ZeroDarkAI.shared
        return try await ai.process(prompt: command, onToken: { _ in })
    }
    
    /// Process a command with optional tool use
    public func processWithTools(_ command: String, useTools: Bool) async throws -> String {
        let ai = await ZeroDarkAI.shared
        
        if useTools {
            // Check for tool-worthy queries
            let toolkit = await AgentToolkit.shared
            let tools = await toolkit.tools
            
            // Let AI decide which tools to use
            let toolContext = tools.map { "\($0.name): \($0.description)" }.joined(separator: "\n")
            
            let planPrompt = """
            User request: \(command)
            
            Available tools:
            \(toolContext)
            
            If this request needs a tool, respond with TOOL: <tool_name>
            Otherwise, respond directly to the user.
            """
            
            let planResponse = try await ai.process(prompt: planPrompt, onToken: { _ in })
            
            if planResponse.hasPrefix("TOOL:") {
                // Execute tool and get result
                let toolResult = await executeToolFromPlan(planResponse, toolkit: toolkit)
                
                // Generate final response with tool context
                return try await ai.process(
                    prompt: "User asked: \(command)\nTool result: \(toolResult)\nProvide a helpful, conversational response.",
                    onToken: { _ in }
                )
            } else {
                return planResponse
            }
        } else {
            return try await ai.process(prompt: command, onToken: { _ in })
        }
    }
    
    private func executeToolFromPlan(_ plan: String, toolkit: AgentToolkit) async -> String {
        let parts = plan.replacingOccurrences(of: "TOOL:", with: "").trimmingCharacters(in: .whitespaces)
        let components = parts.components(separatedBy: " ")
        
        guard let toolName = components.first else {
            return "Could not parse tool"
        }
        
        let call = AgentToolkit.ToolCall(tool: toolName, arguments: [:])
        let result = await toolkit.execute(call)
        return result.output
    }
    
    /// Execute an autonomous task
    public func executeTask(_ task: String) async throws -> String {
        let agent = await AutonomousAgent.shared
        let result = try await agent.executeTask(task)
        return result.summary
    }
    
    /// Plan the user's day
    public func planDay() async throws -> String {
        let agent = await AutonomousAgent.shared
        let plan = try await agent.planDay()
        return plan.spokenSummary
    }
}

// MARK: - Siri Donation Helper

/// Donates intents to Siri for suggestions
public actor SiriDonationHelper {
    public static let shared = SiriDonationHelper()
    
    /// Record a command for Siri suggestions
    public func recordCommand(_ command: String) async {
        // In production: use INInteraction to donate
        // This helps Siri learn user patterns
    }
    
    /// Record a task execution for learning
    public func recordTask(_ task: String) async {
        // Siri learns your task patterns
    }
}

// MARK: - AppIntents Example (for reference)

/*
 Add this to your app target (not the framework) to enable Siri:
 
 import AppIntents
 import MLXEdgeLLM
 
 @available(iOS 16.0, macOS 13.0, *)
 struct AskZeroDarkIntent: AppIntent {
     static var title: LocalizedStringResource = "Ask Zero Dark"
     
     @Parameter(title: "Question")
     var question: String
     
     func perform() async throws -> some IntentResult & ReturnsValue<String> {
         let processor = await SiriCommandProcessor.shared
         let response = try await processor.processVoiceCommand(question)
         return .result(value: response)
     }
 }
 
 @available(iOS 16.0, macOS 13.0, *)
 struct ZeroDarkShortcutsProvider: AppShortcutsProvider {
     static var appShortcuts: [AppShortcut] {
         AppShortcut(
             intent: AskZeroDarkIntent(),
             phrases: ["Ask \(.applicationName)"],
             shortTitle: "Ask Zero Dark",
             systemImageName: "brain.head.profile"
         )
     }
 }
*/
