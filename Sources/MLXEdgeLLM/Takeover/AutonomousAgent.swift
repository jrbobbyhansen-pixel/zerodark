// AutonomousAgent.swift
// Multi-step planning and execution WITHOUT human in the loop
// "Plan my week" → 12 actions execute automatically
// ZETA³: THE TAKEOVER

import Foundation
import EventKit
import Contacts

// MARK: - Autonomous Agent

/// An AI agent that PLANS and EXECUTES multi-step tasks
/// Not just respond — THINK, PLAN, ACT
public actor AutonomousAgent {
    
    public static let shared = AutonomousAgent()
    
    // MARK: - Configuration
    
    public struct Config {
        /// Maximum steps in a single execution
        public var maxSteps: Int = 20
        
        /// Maximum time for full execution (seconds)
        public var maxExecutionTime: TimeInterval = 120
        
        /// Auto-approve low-risk actions
        public var autoApprove: Set<RiskLevel> = [.none, .low]
        
        /// Model to use for planning
        public var planningModel: Model = .qwen3_8b
        
        /// Model to use for execution
        public var executionModel: Model = .qwen3_4b
        
        public static let `default` = Config()
    }
    
    public enum RiskLevel: String, Sendable {
        case none = "none"        // Read-only operations
        case low = "low"          // Create reminders, events
        case medium = "medium"    // Send messages, modify data
        case high = "high"        // Delete data, financial actions
        case critical = "critical" // System changes, external APIs
    }
    
    public var config = Config.default
    private let toolkit = AgentToolkit.shared
    
    // MARK: - Task Execution
    
    public struct TaskResult: Sendable {
        public let success: Bool
        public let summary: String
        public let steps: [ExecutedStep]
        public let totalTime: TimeInterval
        
        public struct ExecutedStep: Sendable {
            public let index: Int
            public let action: String
            public let tool: String?
            public let result: String
            public let success: Bool
            public let riskLevel: RiskLevel
        }
    }
    
    /// Execute a complex task with autonomous planning
    public func executeTask(_ task: String) async throws -> TaskResult {
        let startTime = Date()
        var steps: [TaskResult.ExecutedStep] = []
        
        // 1. PLAN: Break down the task into steps
        let plan = try await createPlan(for: task)
        
        // 2. EXECUTE: Run each step
        for (index, step) in plan.steps.enumerated() {
            // Check time limit
            if Date().timeIntervalSince(startTime) > config.maxExecutionTime {
                break
            }
            
            // Check step limit
            if index >= config.maxSteps {
                break
            }
            
            // Assess risk
            let riskLevel = assessRisk(step)
            
            // Auto-approve or skip based on risk
            guard config.autoApprove.contains(riskLevel) else {
                steps.append(TaskResult.ExecutedStep(
                    index: index,
                    action: step.description,
                    tool: step.tool,
                    result: "Skipped: Requires approval (risk: \(riskLevel.rawValue))",
                    success: false,
                    riskLevel: riskLevel
                ))
                continue
            }
            
            // Execute the step
            let result = await executeStep(step)
            
            steps.append(TaskResult.ExecutedStep(
                index: index,
                action: step.description,
                tool: step.tool,
                result: result.output,
                success: result.success,
                riskLevel: riskLevel
            ))
            
            // If step failed, consider aborting
            if !result.success && step.critical {
                break
            }
        }
        
        // 3. SUMMARIZE: Generate summary of what was done
        let summary = try await generateSummary(task: task, steps: steps)
        
        let totalTime = Date().timeIntervalSince(startTime)
        let allSuccess = steps.allSatisfy { $0.success }
        
        return TaskResult(
            success: allSuccess,
            summary: summary,
            steps: steps,
            totalTime: totalTime
        )
    }
    
    // MARK: - Day Planning
    
    public struct DayPlan: Sendable {
        public let fullPlan: String
        public let spokenSummary: String
        public let priorities: [String]
        public let scheduledActions: [ScheduledAction]
        
        public struct ScheduledAction: Sendable {
            public let time: Date?
            public let action: String
            public let tool: String?
        }
    }
    
    /// Analyze calendar, tasks, and context to plan the day
    public func planDay() async throws -> DayPlan {
        // 1. Gather context
        let calendar = await gatherCalendarContext()
        let reminders = await gatherRemindersContext()
        let healthContext = await gatherHealthContext()
        
        // 2. Ask AI to create a plan
        let ai = await ZeroDarkAI.shared
        
        let planPrompt = """
        You are an autonomous AI assistant planning the user's day.
        
        TODAY'S CALENDAR:
        \(calendar)
        
        PENDING REMINDERS/TASKS:
        \(reminders)
        
        HEALTH/ENERGY CONTEXT:
        \(healthContext)
        
        Create a day plan that:
        1. Identifies top 3 priorities
        2. Suggests optimal time blocks for deep work
        3. Accounts for energy levels (morning vs afternoon)
        4. Schedules breaks and meals
        5. Flags any conflicts or concerns
        
        Format as:
        PRIORITIES:
        1. ...
        2. ...
        3. ...
        
        SCHEDULE:
        [time] - [activity] - [notes]
        ...
        
        SUMMARY: (2-3 sentences for speaking aloud)
        """
        
        let response = try await ai.process(prompt: planPrompt, onToken: { _ in })
        
        // Parse the response
        let priorities = extractPriorities(from: response)
        let spokenSummary = extractSummary(from: response)
        
        return DayPlan(
            fullPlan: response,
            spokenSummary: spokenSummary,
            priorities: priorities,
            scheduledActions: []
        )
    }
    
    // MARK: - Planning Engine
    
    private struct ExecutionPlan: Sendable {
        let steps: [PlanStep]
    }
    
    private struct PlanStep: Sendable {
        let description: String
        let tool: String?
        let arguments: [String: String]
        let critical: Bool  // If this fails, abort the plan
    }
    
    private func createPlan(for task: String) async throws -> ExecutionPlan {
        let ai = await ZeroDarkAI.shared
        let tools = await toolkit.tools
        
        let toolContext = tools.map { tool in
            "- \(tool.name): \(tool.description)"
        }.joined(separator: "\n")
        
        let planPrompt = """
        You are an autonomous AI agent that breaks down tasks into executable steps.
        
        AVAILABLE TOOLS:
        \(toolContext)
        
        USER TASK: \(task)
        
        Create an execution plan. For each step, specify:
        1. What to do (description)
        2. Which tool to use (or NONE if just thinking)
        3. Whether it's critical (if it fails, should we abort?)
        
        Format EXACTLY as:
        STEP 1: [description] | TOOL: [tool_name or NONE] | CRITICAL: [yes/no]
        STEP 2: ...
        
        Be thorough but efficient. Max 10 steps.
        """
        
        let response = try await ai.process(prompt: planPrompt, onToken: { _ in })
        
        // Parse steps from response
        let steps = parseSteps(from: response)
        
        return ExecutionPlan(steps: steps)
    }
    
    private func parseSteps(from response: String) -> [PlanStep] {
        var steps: [PlanStep] = []
        
        let lines = response.components(separatedBy: "\n")
        for line in lines {
            if line.contains("STEP") && line.contains("|") {
                let parts = line.components(separatedBy: "|")
                if parts.count >= 2 {
                    let description = parts[0]
                        .replacingOccurrences(of: "STEP \\d+:", with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespaces)
                    
                    var tool: String? = nil
                    if let toolPart = parts.first(where: { $0.contains("TOOL:") }) {
                        let toolName = toolPart
                            .replacingOccurrences(of: "TOOL:", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        if toolName.lowercased() != "none" {
                            tool = toolName
                        }
                    }
                    
                    let critical = parts.contains { $0.lowercased().contains("critical: yes") }
                    
                    steps.append(PlanStep(
                        description: description,
                        tool: tool,
                        arguments: [:],
                        critical: critical
                    ))
                }
            }
        }
        
        return steps
    }
    
    private func assessRisk(_ step: PlanStep) -> RiskLevel {
        guard let tool = step.tool else {
            return .none
        }
        
        // Categorize tools by risk
        let readOnlyTools = Set(["calculator", "datetime", "weather", "systeminfo"])
        let lowRiskTools = Set(["reminder", "timer", "random", "convert"])
        let mediumRiskTools = Set(["clipboard", "contacts"])
        let highRiskTools = Set(["homekit", "health"])
        
        let toolLower = tool.lowercased()
        
        if readOnlyTools.contains(toolLower) { return .none }
        if lowRiskTools.contains(toolLower) { return .low }
        if mediumRiskTools.contains(toolLower) { return .medium }
        if highRiskTools.contains(toolLower) { return .high }
        
        return .medium // Default
    }
    
    private func executeStep(_ step: PlanStep) async -> AgentToolkit.ToolResult {
        guard let toolName = step.tool else {
            return AgentToolkit.ToolResult(success: true, output: "No tool needed", data: nil)
        }
        
        let call = AgentToolkit.ToolCall(tool: toolName, arguments: step.arguments)
        return await toolkit.execute(call)
    }
    
    private func generateSummary(task: String, steps: [TaskResult.ExecutedStep]) async throws -> String {
        let ai = await ZeroDarkAI.shared
        
        let stepsSummary = steps.map { step in
            "\(step.success ? "✓" : "✗") \(step.action): \(step.result)"
        }.joined(separator: "\n")
        
        let prompt = """
        Summarize what was accomplished in 2-3 sentences for speaking aloud.
        
        Original task: \(task)
        
        Steps executed:
        \(stepsSummary)
        """
        
        return try await ai.process(prompt: prompt, onToken: { _ in })
    }
    
    // MARK: - Context Gathering
    
    private func gatherCalendarContext() async -> String {
        // Would integrate with EventKit
        return """
        - 9:00 AM: Team standup (30 min)
        - 11:00 AM: Client call with Acme Corp (1 hr)
        - 2:00 PM: Focus time (blocked)
        - 4:00 PM: 1:1 with manager (30 min)
        """
    }
    
    private func gatherRemindersContext() async -> String {
        // Would integrate with EventKit Reminders
        return """
        - [ ] Review Q1 report (due today)
        - [ ] Send invoice to client
        - [ ] Book dentist appointment
        - [x] Buy groceries (completed)
        """
    }
    
    private func gatherHealthContext() async -> String {
        // Would integrate with HealthKit
        return """
        - Sleep last night: 6.5 hours (below average)
        - Steps today: 2,340
        - Energy trend: May feel tired in afternoon
        """
    }
    
    // MARK: - Response Parsing
    
    private func extractPriorities(from response: String) -> [String] {
        var priorities: [String] = []
        
        let lines = response.components(separatedBy: "\n")
        var inPriorities = false
        
        for line in lines {
            if line.contains("PRIORITIES") {
                inPriorities = true
                continue
            }
            if line.contains("SCHEDULE") || line.contains("SUMMARY") {
                inPriorities = false
            }
            if inPriorities {
                let cleaned = line.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "^\\d+\\.\\s*", with: "", options: .regularExpression)
                if !cleaned.isEmpty {
                    priorities.append(cleaned)
                }
            }
        }
        
        return Array(priorities.prefix(3))
    }
    
    private func extractSummary(from response: String) -> String {
        if let summaryRange = response.range(of: "SUMMARY:") {
            let summary = response[summaryRange.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return String(summary.prefix(500))
        }
        return "Your day is planned. Check the full breakdown for details."
    }
}

// MARK: - Agent Loop (Continuous Execution)

public actor AgentLoop {
    public static let shared = AgentLoop()
    
    public enum LoopState {
        case idle
        case planning
        case executing(step: Int, total: Int)
        case complete
        case error(String)
    }
    
    @Published public private(set) var state: LoopState = .idle
    
    /// Run continuous agent loop until goal achieved
    public func runUntilComplete(
        goal: String,
        maxIterations: Int = 10,
        onProgress: @escaping (LoopState) -> Void
    ) async throws -> String {
        state = .planning
        onProgress(state)
        
        let agent = AutonomousAgent.shared
        var iterations = 0
        var fullResult = ""
        
        while iterations < maxIterations {
            iterations += 1
            state = .executing(step: iterations, total: maxIterations)
            onProgress(state)
            
            // Execute next iteration
            let result = try await agent.executeTask(goal)
            fullResult += "\n\nIteration \(iterations):\n\(result.summary)"
            
            // Check if goal is complete
            if await isGoalComplete(goal: goal, result: result) {
                break
            }
            
            // Update goal for next iteration based on what's remaining
            // (Would refine the prompt based on progress)
        }
        
        state = .complete
        onProgress(state)
        
        return fullResult
    }
    
    private func isGoalComplete(goal: String, result: AutonomousAgent.TaskResult) async -> Bool {
        // Simple heuristic: if all steps succeeded, consider complete
        // In production: ask AI to evaluate if goal is achieved
        return result.success
    }
}
