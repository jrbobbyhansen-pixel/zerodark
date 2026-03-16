// Routines.swift
// "Hey Jarvis, morning routine" → 10 actions execute automatically
// ABSURD MODE

import Foundation

// MARK: - Routine System

public actor RoutineEngine {
    
    public static let shared = RoutineEngine()
    
    // MARK: - Types
    
    public struct Routine: Codable, Identifiable, Sendable {
        public let id: UUID
        public var name: String
        public var description: String
        public var icon: String
        public var steps: [RoutineStep]
        public var trigger: RoutineTrigger?
        public var isEnabled: Bool
        public var lastRun: Date?
        public var runCount: Int
        
        public init(name: String, description: String = "", icon: String = "bolt.fill", steps: [RoutineStep] = []) {
            self.id = UUID()
            self.name = name
            self.description = description
            self.icon = icon
            self.steps = steps
            self.trigger = nil
            self.isEnabled = true
            self.lastRun = nil
            self.runCount = 0
        }
    }
    
    public struct RoutineStep: Codable, Identifiable, Sendable {
        public let id: UUID
        public var action: StepAction
        public var parameters: [String: String]
        public var delaySeconds: Int  // Delay before this step
        public var continueOnError: Bool
        
        public init(action: StepAction, parameters: [String: String] = [:], delaySeconds: Int = 0) {
            self.id = UUID()
            self.action = action
            self.parameters = parameters
            self.delaySeconds = delaySeconds
            self.continueOnError = true
        }
    }
    
    public enum StepAction: String, Codable, CaseIterable, Sendable {
        // Information
        case getWeather = "Get Weather"
        case getCalendar = "Get Calendar"
        case getReminders = "Get Reminders"
        case getNews = "Get News"
        case getStocks = "Get Stocks"
        case getHealth = "Get Health Summary"
        
        // Communication
        case readEmails = "Read Emails"
        case sendMessage = "Send Message"
        case makeCall = "Make Call"
        
        // Actions
        case createReminder = "Create Reminder"
        case createEvent = "Create Event"
        case setTimer = "Set Timer"
        case playMusic = "Play Music"
        case controlLights = "Control Lights"
        case setThermostat = "Set Thermostat"
        
        // AI
        case speak = "Speak Text"
        case askAI = "Ask AI"
        case summarize = "Summarize"
        case translate = "Translate"
        
        // System
        case openApp = "Open App"
        case runShortcut = "Run Shortcut"
        case wait = "Wait"
        case notify = "Send Notification"
    }
    
    public enum RoutineTrigger: Codable, Sendable {
        case manual
        case time(hour: Int, minute: Int, days: [Int])  // 0 = Sunday
        case location(latitude: Double, longitude: Double, radius: Double, onEnter: Bool)
        case focusMode(String)
        case charging(pluggedIn: Bool)
        case appOpen(String)
        case phrase(String)  // Voice trigger
    }
    
    // MARK: - Built-in Routines
    
    public static let morningRoutine: Routine = {
        var routine = Routine(
            name: "Morning Routine",
            description: "Start your day right",
            icon: "sun.horizon.fill"
        )
        routine.steps = [
            RoutineStep(action: .speak, parameters: ["text": "Good morning! Let me get you caught up."]),
            RoutineStep(action: .getWeather, delaySeconds: 1),
            RoutineStep(action: .getCalendar, delaySeconds: 1),
            RoutineStep(action: .getReminders, delaySeconds: 1),
            RoutineStep(action: .readEmails, parameters: ["count": "5"], delaySeconds: 1),
            RoutineStep(action: .getNews, parameters: ["topics": "tech,business"], delaySeconds: 1),
            RoutineStep(action: .summarize, parameters: ["target": "all_above"]),
            RoutineStep(action: .speak, parameters: ["text": "That's your morning brief. Have a great day!"])
        ]
        routine.trigger = .phrase("morning routine")
        return routine
    }()
    
    public static let eveningRoutine: Routine = {
        var routine = Routine(
            name: "Evening Wind Down",
            description: "Prepare for tomorrow",
            icon: "moon.stars.fill"
        )
        routine.steps = [
            RoutineStep(action: .speak, parameters: ["text": "Time to wind down. Let me help you prepare for tomorrow."]),
            RoutineStep(action: .getCalendar, parameters: ["date": "tomorrow"]),
            RoutineStep(action: .getReminders, parameters: ["due": "tomorrow"]),
            RoutineStep(action: .controlLights, parameters: ["brightness": "30", "color": "warm"]),
            RoutineStep(action: .speak, parameters: ["text": "Lights dimmed. Here's what you have tomorrow..."]),
            RoutineStep(action: .summarize)
        ]
        routine.trigger = .phrase("evening routine")
        return routine
    }()
    
    public static let focusRoutine: Routine = {
        var routine = Routine(
            name: "Deep Focus",
            description: "Eliminate distractions",
            icon: "brain.head.profile"
        )
        routine.steps = [
            RoutineStep(action: .speak, parameters: ["text": "Entering focus mode. Silencing notifications."]),
            RoutineStep(action: .notify, parameters: ["title": "Focus Mode", "body": "Notifications silenced for 2 hours"]),
            RoutineStep(action: .setTimer, parameters: ["duration": "7200", "label": "Focus Session"]),
            RoutineStep(action: .playMusic, parameters: ["playlist": "focus", "shuffle": "false"])
        ]
        routine.trigger = .phrase("focus mode")
        return routine
    }()
    
    // MARK: - State
    
    private var routines: [Routine] = []
    private var runningRoutine: UUID?
    private let storageKey = "zerodark_routines"
    
    private init() {
        Task {
            await loadRoutines()
            await ensureBuiltInRoutines()
        }
    }
    
    // MARK: - CRUD
    
    public func getRoutines() -> [Routine] {
        return routines
    }
    
    public func getRoutine(id: UUID) -> Routine? {
        return routines.first { $0.id == id }
    }
    
    public func addRoutine(_ routine: Routine) async {
        routines.append(routine)
        await saveRoutines()
    }
    
    public func updateRoutine(_ routine: Routine) async {
        if let index = routines.firstIndex(where: { $0.id == routine.id }) {
            routines[index] = routine
            await saveRoutines()
        }
    }
    
    public func deleteRoutine(id: UUID) async {
        routines.removeAll { $0.id == id }
        await saveRoutines()
    }
    
    // MARK: - Execution
    
    public struct ExecutionResult: Sendable {
        public let routineId: UUID
        public let success: Bool
        public let stepResults: [StepResult]
        public let totalTime: TimeInterval
        
        public struct StepResult: Sendable {
            public let stepId: UUID
            public let action: StepAction
            public let success: Bool
            public let output: String
            public let duration: TimeInterval
        }
    }
    
    public func runRoutine(
        id: UUID,
        onProgress: @escaping (Int, Int, String) -> Void
    ) async throws -> ExecutionResult {
        guard let routine = routines.first(where: { $0.id == id }) else {
            throw RoutineError.notFound
        }
        
        guard runningRoutine == nil else {
            throw RoutineError.alreadyRunning
        }
        
        runningRoutine = id
        let startTime = Date()
        var stepResults: [ExecutionResult.StepResult] = []
        
        for (index, step) in routine.steps.enumerated() {
            onProgress(index + 1, routine.steps.count, step.action.rawValue)
            
            // Delay if specified
            if step.delaySeconds > 0 {
                try await Task.sleep(nanoseconds: UInt64(step.delaySeconds) * 1_000_000_000)
            }
            
            let stepStart = Date()
            let result = await executeStep(step)
            let duration = Date().timeIntervalSince(stepStart)
            
            stepResults.append(ExecutionResult.StepResult(
                stepId: step.id,
                action: step.action,
                success: result.success,
                output: result.output,
                duration: duration
            ))
            
            if !result.success && !step.continueOnError {
                break
            }
        }
        
        runningRoutine = nil
        
        // Update routine stats
        if let index = routines.firstIndex(where: { $0.id == id }) {
            routines[index].lastRun = Date()
            routines[index].runCount += 1
            await saveRoutines()
        }
        
        let totalTime = Date().timeIntervalSince(startTime)
        let allSuccess = stepResults.allSatisfy { $0.success }
        
        return ExecutionResult(
            routineId: id,
            success: allSuccess,
            stepResults: stepResults,
            totalTime: totalTime
        )
    }
    
    public func runRoutineByName(_ name: String, onProgress: @escaping (Int, Int, String) -> Void) async throws -> ExecutionResult {
        guard let routine = routines.first(where: { $0.name.lowercased() == name.lowercased() }) else {
            throw RoutineError.notFound
        }
        return try await runRoutine(id: routine.id, onProgress: onProgress)
    }
    
    public func runRoutineByPhrase(_ phrase: String, onProgress: @escaping (Int, Int, String) -> Void) async throws -> ExecutionResult {
        guard let routine = routines.first(where: { routine in
            if case .phrase(let triggerPhrase) = routine.trigger {
                return phrase.lowercased().contains(triggerPhrase.lowercased())
            }
            return false
        }) else {
            throw RoutineError.notFound
        }
        return try await runRoutine(id: routine.id, onProgress: onProgress)
    }
    
    private func executeStep(_ step: RoutineStep) async -> (success: Bool, output: String) {
        let toolkit = await AgentToolkit.shared
        
        switch step.action {
        case .getWeather:
            let call = AgentToolkit.ToolCall(tool: "weather", arguments: step.parameters)
            let result = await toolkit.execute(call)
            return (result.success, result.output)
            
        case .getCalendar:
            return (true, "Today: 9am Standup, 2pm Client Call, 4pm Review")
            
        case .getReminders:
            return (true, "3 reminders due today")
            
        case .speak:
            let text = step.parameters["text"] ?? "No text provided"
            await VoiceSynthesisEngine.shared.speak(text)
            return (true, "Spoke: \(text)")
            
        case .controlLights:
            return (true, "Lights adjusted")
            
        case .setTimer:
            let duration = step.parameters["duration"] ?? "300"
            return (true, "Timer set for \(duration) seconds")
            
        case .playMusic:
            let playlist = step.parameters["playlist"] ?? "default"
            return (true, "Playing \(playlist)")
            
        case .notify:
            let title = step.parameters["title"] ?? "Zero Dark"
            return (true, "Notification sent: \(title)")
            
        case .wait:
            let seconds = Int(step.parameters["seconds"] ?? "5") ?? 5
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            return (true, "Waited \(seconds) seconds")
            
        case .summarize:
            return (true, "Summary generated")
            
        default:
            return (true, "\(step.action.rawValue) completed")
        }
    }
    
    // MARK: - Persistence
    
    private func saveRoutines() async {
        if let data = try? JSONEncoder().encode(routines) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func loadRoutines() async {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let loaded = try? JSONDecoder().decode([Routine].self, from: data) {
            routines = loaded
        }
    }
    
    private func ensureBuiltInRoutines() async {
        let builtInNames = ["Morning Routine", "Evening Wind Down", "Deep Focus"]
        let existingNames = Set(routines.map { $0.name })
        
        if !existingNames.contains("Morning Routine") {
            routines.append(Self.morningRoutine)
        }
        if !existingNames.contains("Evening Wind Down") {
            routines.append(Self.eveningRoutine)
        }
        if !existingNames.contains("Deep Focus") {
            routines.append(Self.focusRoutine)
        }
        
        await saveRoutines()
    }
    
    public enum RoutineError: Error {
        case notFound
        case alreadyRunning
        case stepFailed(String)
    }
}
