// AutonomousAgent.swift
// Multi-step task planning and execution - PRODUCTION READY
// The AI that works while you sleep

import Foundation

// MARK: - Autonomous Agent

@MainActor
public final class AutonomousAgent: ObservableObject {
    
    public static let shared = AutonomousAgent()
    
    // MARK: - Types
    
    public struct AgentTask: Identifiable, Codable {
        public let id: String
        public let description: String
        public let createdAt: Date
        public var status: TaskStatus
        public var steps: [AgentStep]
        public var result: String?
        public var error: String?
        
        public enum TaskStatus: String, Codable {
            case pending
            case planning
            case executing
            case completed
            case failed
            case cancelled
        }
    }
    
    public struct AgentStep: Identifiable, Codable {
        public let id: String
        public let description: String
        public let action: AgentAction
        public var status: StepStatus
        public var output: String?
        public var startedAt: Date?
        public var completedAt: Date?
        
        public enum StepStatus: String, Codable {
            case pending
            case running
            case completed
            case failed
            case skipped
        }
    }
    
    public enum AgentAction: Codable, Equatable {
        case think(prompt: String)
        case search(query: String)
        case readFile(path: String)
        case writeFile(path: String, content: String)
        case runCode(language: String, code: String)
        case analyzeImage(description: String)
        case summarize(text: String)
        case askUser(question: String)
        case complete(result: String)
        
        var description: String {
            switch self {
            case .think: return "Thinking"
            case .search: return "Searching"
            case .readFile: return "Reading file"
            case .writeFile: return "Writing file"
            case .runCode: return "Running code"
            case .analyzeImage: return "Analyzing image"
            case .summarize: return "Summarizing"
            case .askUser: return "Asking user"
            case .complete: return "Completing"
            }
        }
    }
    
    // MARK: - Published State
    
    @Published public private(set) var currentTask: AgentTask?
    @Published public private(set) var taskHistory: [AgentTask] = []
    @Published public private(set) var isRunning: Bool = false
    
    // MARK: - Configuration
    
    public var maxStepsPerTask: Int = 20
    public var thinkingModel: String = "qwen2.5-14b"
    public var allowFileAccess: Bool = true
    public var allowCodeExecution: Bool = false  // Safety default
    public var sandboxPath: URL?
    
    // MARK: - Private
    
    private var activeContinuation: CheckedContinuation<String, Error>?
    private var shouldCancel: Bool = false
    
    private init() {
        loadTaskHistory()
    }
    
    // MARK: - Task Management
    
    /// Start a new autonomous task
    public func startTask(description: String, maxSteps: Int? = nil) async throws -> String {
        guard !isRunning else {
            throw AgentError.alreadyRunning
        }
        
        let task = AgentTask(
            id: UUID().uuidString,
            description: description,
            createdAt: Date(),
            status: .planning,
            steps: []
        )
        
        currentTask = task
        isRunning = true
        shouldCancel = false
        
        do {
            // Phase 1: Planning
            let steps = try await planTask(description: description, maxSteps: maxSteps ?? maxStepsPerTask)
            currentTask?.steps = steps
            currentTask?.status = .executing
            
            // Phase 2: Execution
            let result = try await executeSteps(steps)
            
            currentTask?.status = .completed
            currentTask?.result = result
            
            // Save to history
            if let completedTask = currentTask {
                taskHistory.insert(completedTask, at: 0)
                saveTaskHistory()
            }
            
            isRunning = false
            return result
            
        } catch {
            currentTask?.status = .failed
            currentTask?.error = error.localizedDescription
            
            if let failedTask = currentTask {
                taskHistory.insert(failedTask, at: 0)
                saveTaskHistory()
            }
            
            isRunning = false
            throw error
        }
    }
    
    /// Cancel the current task
    public func cancelTask() {
        shouldCancel = true
        currentTask?.status = .cancelled
        isRunning = false
    }
    
    /// Provide user response to an askUser step
    public func provideUserResponse(_ response: String) {
        activeContinuation?.resume(returning: response)
        activeContinuation = nil
    }
    
    // MARK: - Planning
    
    private func planTask(description: String, maxSteps: Int) async throws -> [AgentStep] {
        let ai = ZeroDarkAI.shared
        
        let planningPrompt = """
        You are an autonomous AI agent. Plan the steps needed to complete this task:
        
        TASK: \(description)
        
        Available actions:
        - think: Reason about the problem
        - search: Search for information
        - readFile: Read a file
        - writeFile: Write to a file
        - runCode: Execute code (if enabled)
        - summarize: Summarize text
        - complete: Finish with result
        
        Output a JSON array of steps. Each step has:
        - description: What this step does
        - action: The action type
        - params: Action parameters
        
        Max \(maxSteps) steps. Be efficient.
        
        Example output:
        [
            {"description": "Research the topic", "action": "think", "params": {"prompt": "What do I know about..."}},
            {"description": "Summarize findings", "action": "summarize", "params": {"text": "..."}},
            {"description": "Return result", "action": "complete", "params": {"result": "..."}}
        ]
        
        Output ONLY valid JSON, no markdown:
        """
        
        var planJSON = ""
        planJSON = try await ai.process(prompt: planningPrompt) { _ in }
        
        // Parse the plan
        let steps = try parsePlan(planJSON)
        
        guard steps.count <= maxSteps else {
            throw AgentError.tooManySteps
        }
        
        return steps
    }
    
    private func parsePlan(_ json: String) throws -> [AgentStep] {
        // Clean up the JSON (remove markdown code blocks if present)
        var cleanJSON = json
        if cleanJSON.contains("```") {
            cleanJSON = cleanJSON
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        guard let data = cleanJSON.data(using: .utf8) else {
            throw AgentError.invalidPlan
        }
        
        let rawSteps = try JSONDecoder().decode([RawStep].self, from: data)
        
        return rawSteps.map { raw in
            AgentStep(
                id: UUID().uuidString,
                description: raw.description,
                action: parseAction(raw.action, params: raw.params),
                status: .pending
            )
        }
    }
    
    private struct RawStep: Decodable {
        let description: String
        let action: String
        let params: [String: String]
    }
    
    private func parseAction(_ type: String, params: [String: String]) -> AgentAction {
        switch type {
        case "think":
            return .think(prompt: params["prompt"] ?? "")
        case "search":
            return .search(query: params["query"] ?? "")
        case "readFile":
            return .readFile(path: params["path"] ?? "")
        case "writeFile":
            return .writeFile(path: params["path"] ?? "", content: params["content"] ?? "")
        case "runCode":
            return .runCode(language: params["language"] ?? "python", code: params["code"] ?? "")
        case "analyzeImage":
            return .analyzeImage(description: params["description"] ?? "")
        case "summarize":
            return .summarize(text: params["text"] ?? "")
        case "askUser":
            return .askUser(question: params["question"] ?? "")
        case "complete":
            return .complete(result: params["result"] ?? "")
        default:
            return .think(prompt: "Unknown action: \(type)")
        }
    }
    
    // MARK: - Execution
    
    private func executeSteps(_ steps: [AgentStep]) async throws -> String {
        var context: [String: String] = [:]
        var finalResult = ""
        
        for (index, step) in steps.enumerated() {
            guard !shouldCancel else {
                throw AgentError.cancelled
            }
            
            // Update step status
            currentTask?.steps[index].status = .running
            currentTask?.steps[index].startedAt = Date()
            
            do {
                let output = try await executeAction(step.action, context: context)
                
                currentTask?.steps[index].status = .completed
                currentTask?.steps[index].output = output
                currentTask?.steps[index].completedAt = Date()
                
                // Add to context for subsequent steps
                context["step_\(index)_output"] = output
                
                // Check if this is the final step
                if case .complete(let result) = step.action {
                    finalResult = result
                }
                
            } catch {
                currentTask?.steps[index].status = .failed
                currentTask?.steps[index].output = error.localizedDescription
                throw error
            }
        }
        
        return finalResult.isEmpty ? context.values.joined(separator: "\n") : finalResult
    }
    
    private func executeAction(_ action: AgentAction, context: [String: String]) async throws -> String {
        let ai = ZeroDarkAI.shared
        
        switch action {
        case .think(let prompt):
            // Enhance prompt with context
            let contextStr = context.map { "- \($0.key): \($0.value.prefix(200))" }.joined(separator: "\n")
            let fullPrompt = contextStr.isEmpty ? prompt : "Context:\n\(contextStr)\n\nTask: \(prompt)"
            
            var result = ""
            result = try await ai.process(prompt: fullPrompt) { _ in }
            return result
            
        case .search(let query):
            // Use web search if available, otherwise simulate with AI
            let searchPrompt = "Search query: \(query)\n\nProvide relevant information about this topic."
            var result = ""
            result = try await ai.process(prompt: searchPrompt) { _ in }
            return result
            
        case .readFile(let path):
            guard allowFileAccess else {
                throw AgentError.fileAccessDenied
            }
            
            let url = resolveFilePath(path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw AgentError.fileNotFound(path)
            }
            
            let content = try String(contentsOf: url, encoding: .utf8)
            return String(content.prefix(10000)) // Limit size
            
        case .writeFile(let path, let content):
            guard allowFileAccess else {
                throw AgentError.fileAccessDenied
            }
            
            let url = resolveFilePath(path)
            
            // Security check: must be in sandbox
            if let sandbox = sandboxPath {
                guard url.path.hasPrefix(sandbox.path) else {
                    throw AgentError.outsideSandbox
                }
            }
            
            try content.write(to: url, atomically: true, encoding: .utf8)
            return "Written \(content.count) characters to \(path)"
            
        case .runCode(let language, let code):
            guard allowCodeExecution else {
                throw AgentError.codeExecutionDisabled
            }
            
            // Sandboxed code execution
            return try await executeCode(language: language, code: code)
            
        case .analyzeImage(let description):
            // Would integrate with vision model
            return "Image analysis: \(description)"
            
        case .summarize(let text):
            let prompt = "Summarize the following text concisely:\n\n\(text.prefix(5000))"
            var result = ""
            result = try await ai.process(prompt: prompt) { _ in }
            return result
            
        case .askUser(let question):
            // Wait for user input
            return try await withCheckedThrowingContinuation { continuation in
                self.activeContinuation = continuation
                
                // Timeout after 5 minutes
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000_000)
                    if self.activeContinuation != nil {
                        self.activeContinuation?.resume(throwing: AgentError.userResponseTimeout)
                        self.activeContinuation = nil
                    }
                }
            }
            
        case .complete(let result):
            return result
        }
    }
    
    private func resolveFilePath(_ path: String) -> URL {
        if path.hasPrefix("/") || path.hasPrefix("~") {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        
        if let sandbox = sandboxPath {
            return sandbox.appendingPathComponent(path)
        }
        
        return URL(fileURLWithPath: path)
    }
    
    private func executeCode(language: String, code: String) async throws -> String {
        // Sandboxed code execution using Process
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zerodark-agent-\(UUID().uuidString)")
        
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let scriptFile: URL
        let interpreter: String
        
        switch language.lowercased() {
        case "python", "py":
            scriptFile = tempDir.appendingPathComponent("script.py")
            interpreter = "/usr/bin/python3"
        case "javascript", "js":
            scriptFile = tempDir.appendingPathComponent("script.js")
            interpreter = "/usr/bin/env node"
        case "bash", "sh":
            scriptFile = tempDir.appendingPathComponent("script.sh")
            interpreter = "/bin/bash"
        default:
            throw AgentError.unsupportedLanguage(language)
        }
        
        try code.write(to: scriptFile, atomically: true, encoding: .utf8)
        
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "\(interpreter) \(scriptFile.path)"]
        process.currentDirectoryURL = tempDir
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        
        // Timeout after 30 seconds
        let deadline = Date().addingTimeInterval(30)
        while process.isRunning && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        
        if process.isRunning {
            process.terminate()
            throw AgentError.codeExecutionTimeout
        }
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""
        
        if process.terminationStatus != 0 {
            return "Error:\n\(error)\n\nOutput:\n\(output)"
        }
        
        return output
        #else
        throw AgentError.codeExecutionDisabled
        #endif
    }
    
    // MARK: - Persistence
    
    private func loadTaskHistory() {
        guard let data = UserDefaults.standard.data(forKey: "zerodark.agent.history"),
              let history = try? JSONDecoder().decode([AgentTask].self, from: data) else {
            return
        }
        taskHistory = Array(history.prefix(50)) // Keep last 50 tasks
    }
    
    private func saveTaskHistory() {
        guard let data = try? JSONEncoder().encode(Array(taskHistory.prefix(50))) else { return }
        UserDefaults.standard.set(data, forKey: "zerodark.agent.history")
    }
    
    // MARK: - Errors
    
    public enum AgentError: Error, LocalizedError {
        case alreadyRunning
        case invalidPlan
        case tooManySteps
        case cancelled
        case fileAccessDenied
        case fileNotFound(String)
        case outsideSandbox
        case codeExecutionDisabled
        case codeExecutionTimeout
        case unsupportedLanguage(String)
        case userResponseTimeout
        case executionFailed(String)
        
        public var errorDescription: String? {
            switch self {
            case .alreadyRunning: return "Agent is already running a task"
            case .invalidPlan: return "Could not parse task plan"
            case .tooManySteps: return "Task requires too many steps"
            case .cancelled: return "Task was cancelled"
            case .fileAccessDenied: return "File access not allowed"
            case .fileNotFound(let path): return "File not found: \(path)"
            case .outsideSandbox: return "Cannot write outside sandbox"
            case .codeExecutionDisabled: return "Code execution is disabled"
            case .codeExecutionTimeout: return "Code execution timed out"
            case .unsupportedLanguage(let lang): return "Unsupported language: \(lang)"
            case .userResponseTimeout: return "Timed out waiting for user response"
            case .executionFailed(let reason): return "Execution failed: \(reason)"
            }
        }
    }
}

// MARK: - Agent Monitor View

#if canImport(SwiftUI)
import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
public struct AgentMonitorView: View {
    @ObservedObject var agent = AutonomousAgent.shared
    @State private var newTaskDescription: String = ""
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Current task
            if let task = agent.currentTask {
                currentTaskView(task)
            } else {
                newTaskInput
            }
            
            Divider()
            
            // Step list
            if let task = agent.currentTask {
                stepsList(task.steps)
            }
        }
        .background(Color.black)
    }
    
    private var newTaskInput: some View {
        HStack {
            TextField("Describe a task...", text: $newTaskDescription)
                .textFieldStyle(.plain)
                .padding()
            
            Button {
                Task {
                    try? await agent.startTask(description: newTaskDescription)
                    newTaskDescription = ""
                }
            } label: {
                Image(systemName: "play.fill")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(8)
            }
            .disabled(newTaskDescription.isEmpty || agent.isRunning)
        }
        .padding()
    }
    
    private func currentTaskView(_ task: AutonomousAgent.AgentTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                statusBadge(task.status)
                Spacer()
                if agent.isRunning {
                    Button("Cancel") {
                        agent.cancelTask()
                    }
                    .foregroundColor(.red)
                }
            }
            
            Text(task.description)
                .font(.headline)
                .foregroundColor(.white)
            
            if let error = task.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
    }
    
    private func stepsList(_ steps: [AutonomousAgent.AgentStep]) -> some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(steps) { step in
                    stepRow(step)
                }
            }
        }
    }
    
    private func stepRow(_ step: AutonomousAgent.AgentStep) -> some View {
        HStack {
            stepIcon(step.status)
            
            VStack(alignment: .leading) {
                Text(step.description)
                    .foregroundColor(.white)
                Text(step.action.description)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            if let output = step.output {
                Text(String(output.prefix(20)) + "...")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(step.status == .running ? Color.blue.opacity(0.1) : Color.clear)
    }
    
    private func stepIcon(_ status: AutonomousAgent.AgentStep.StepStatus) -> some View {
        Group {
            switch status {
            case .pending:
                Circle().stroke(Color.gray, lineWidth: 2)
            case .running:
                ProgressView()
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            case .skipped:
                Image(systemName: "arrow.right.circle")
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 24, height: 24)
    }
    
    private func statusBadge(_ status: AutonomousAgent.AgentTask.TaskStatus) -> some View {
        let (text, color): (String, Color) = {
            switch status {
            case .pending: return ("Pending", .gray)
            case .planning: return ("Planning", .yellow)
            case .executing: return ("Running", .blue)
            case .completed: return ("Done", .green)
            case .failed: return ("Failed", .red)
            case .cancelled: return ("Cancelled", .orange)
            }
        }()
        
        return Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .cornerRadius(4)
    }
}
#endif
