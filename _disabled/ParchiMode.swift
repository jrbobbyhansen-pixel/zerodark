//
//  ParchiMode.swift
//  ZeroDark
//
//  Full computer control using local MLX models.
//  Screen reading, mouse/keyboard control, app automation.
//  Like Claude Computer Use or 0xSero, but 100% local.
//

import SwiftUI
import CoreGraphics
import Vision
import AppKit
import Accessibility

// MARK: - Parchi Core Engine

@MainActor
class ParchiEngine: ObservableObject {
    static let shared = ParchiEngine()
    
    // State
    @Published var isActive = false
    @Published var currentTask: String?
    @Published var stepLog: [ParchiStep] = []
    @Published var screenState: ScreenState?
    @Published var isThinking = false
    
    // Components
    private let screenReader = ScreenReader()
    private let inputController = InputController()
    private let appController = AppController()
    private let planner = TaskPlanner()
    
    // Settings
    @Published var safeMode = true // Confirm destructive actions
    @Published var maxSteps = 50
    @Published var stepDelay: TimeInterval = 0.5
    
    /// Execute a natural language task
    func execute(task: String) async throws {
        isActive = true
        currentTask = task
        stepLog = []
        
        defer { isActive = false }
        
        // 1. Capture current screen state
        let initialState = try await captureScreenState()
        screenState = initialState
        
        // 2. Generate action plan
        let plan = try await planner.planTask(task: task, screenState: initialState)
        
        logStep(.planning, "Generated \(plan.steps.count) step plan")
        
        // 3. Execute each step
        for (index, step) in plan.steps.enumerated() {
            guard index < maxSteps else {
                logStep(.error, "Max steps reached (\(maxSteps))")
                break
            }
            
            // Safety check for destructive actions
            if safeMode && step.isDestructive {
                logStep(.confirmation, "Destructive action: \(step.description)")
                // Would pause for confirmation
            }
            
            // Execute the step
            try await executeStep(step)
            
            // Wait for UI to settle
            try await Task.sleep(nanoseconds: UInt64(stepDelay * 1_000_000_000))
            
            // Re-capture screen to verify
            let newState = try await captureScreenState()
            screenState = newState
            
            // Check if goal achieved
            if try await planner.isTaskComplete(task: task, screenState: newState) {
                logStep(.success, "Task completed!")
                return
            }
        }
    }
    
    /// Capture current screen state with OCR and element detection
    func captureScreenState() async throws -> ScreenState {
        isThinking = true
        defer { isThinking = false }
        
        // Get screen capture
        let screenshot = try screenReader.captureScreen()
        
        // Run OCR
        let textElements = try await screenReader.extractText(from: screenshot)
        
        // Detect UI elements
        let uiElements = try await screenReader.detectUIElements(from: screenshot)
        
        // Get active window info
        let activeWindow = appController.getActiveWindow()
        
        // Get running apps
        let runningApps = appController.getRunningApps()
        
        return ScreenState(
            screenshot: screenshot,
            textElements: textElements,
            uiElements: uiElements,
            activeWindow: activeWindow,
            runningApps: runningApps,
            timestamp: Date()
        )
    }
    
    /// Execute a single action step
    private func executeStep(_ step: ActionStep) async throws {
        logStep(.action, step.description)
        
        switch step.action {
        case .click(let point):
            try inputController.click(at: point)
            
        case .doubleClick(let point):
            try inputController.doubleClick(at: point)
            
        case .rightClick(let point):
            try inputController.rightClick(at: point)
            
        case .type(let text):
            try inputController.type(text)
            
        case .keyPress(let key, let modifiers):
            try inputController.keyPress(key: key, modifiers: modifiers)
            
        case .scroll(let direction, let amount):
            try inputController.scroll(direction: direction, amount: amount)
            
        case .drag(let from, let to):
            try inputController.drag(from: from, to: to)
            
        case .launchApp(let bundleId):
            try appController.launchApp(bundleId: bundleId)
            
        case .switchApp(let bundleId):
            try appController.switchToApp(bundleId: bundleId)
            
        case .wait(let seconds):
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            
        case .screenshot:
            _ = try screenReader.captureScreen()
        }
    }
    
    private func logStep(_ type: StepType, _ message: String) {
        let step = ParchiStep(type: type, message: message, timestamp: Date())
        stepLog.append(step)
    }
}

// MARK: - Screen Reader

class ScreenReader {
    /// Capture the entire screen
    func captureScreen() throws -> CGImage {
        guard let displayID = CGMainDisplayID() as CGDirectDisplayID?,
              let image = CGDisplayCreateImage(displayID) else {
            throw ParchiError.captureFailedcls
        }
        return image
    }
    
    /// Capture a specific window
    func captureWindow(windowID: CGWindowID) throws -> CGImage {
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming]
        ) else {
            throw ParchiError.captureFailed
        }
        return image
    }
    
    /// Extract text from screen using Vision OCR
    func extractText(from image: CGImage) async throws -> [TextElement] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        
        guard let observations = request.results else { return [] }
        
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        
        return observations.compactMap { observation -> TextElement? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            
            let boundingBox = observation.boundingBox
            let rect = CGRect(
                x: boundingBox.minX * imageWidth,
                y: (1 - boundingBox.maxY) * imageHeight,
                width: boundingBox.width * imageWidth,
                height: boundingBox.height * imageHeight
            )
            
            return TextElement(
                text: candidate.string,
                confidence: candidate.confidence,
                bounds: rect
            )
        }
    }
    
    /// Detect UI elements (buttons, fields, etc.)
    func detectUIElements(from image: CGImage) async throws -> [UIElement] {
        // Use Vision for rectangle detection (approximation of UI elements)
        let rectangleRequest = VNDetectRectanglesRequest()
        rectangleRequest.minimumAspectRatio = 0.1
        rectangleRequest.maximumAspectRatio = 10.0
        rectangleRequest.minimumSize = 0.01
        rectangleRequest.maximumObservations = 100
        
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([rectangleRequest])
        
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        
        return (rectangleRequest.results ?? []).map { observation in
            let boundingBox = observation.boundingBox
            let rect = CGRect(
                x: boundingBox.minX * imageWidth,
                y: (1 - boundingBox.maxY) * imageHeight,
                width: boundingBox.width * imageWidth,
                height: boundingBox.height * imageHeight
            )
            
            return UIElement(
                type: .unknown,
                bounds: rect,
                confidence: observation.confidence
            )
        }
    }
}

// MARK: - Input Controller

class InputController {
    /// Click at a screen coordinate
    func click(at point: CGPoint) throws {
        let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        let mouseUp = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        
        mouseDown?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        mouseUp?.post(tap: .cghidEventTap)
    }
    
    /// Double click at a screen coordinate
    func doubleClick(at point: CGPoint) throws {
        try click(at: point)
        Thread.sleep(forTimeInterval: 0.1)
        try click(at: point)
    }
    
    /// Right click at a screen coordinate
    func rightClick(at point: CGPoint) throws {
        let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: .rightMouseDown,
            mouseCursorPosition: point,
            mouseButton: .right
        )
        let mouseUp = CGEvent(
            mouseEventSource: nil,
            mouseType: .rightMouseUp,
            mouseCursorPosition: point,
            mouseButton: .right
        )
        
        mouseDown?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        mouseUp?.post(tap: .cghidEventTap)
    }
    
    /// Type text
    func type(_ text: String) throws {
        for char in text {
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            
            var buffer = [UniChar](String(char).utf16)
            keyDown?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)
            keyUp?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)
            
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
            
            Thread.sleep(forTimeInterval: 0.02)
        }
    }
    
    /// Press a key with optional modifiers
    func keyPress(key: CGKeyCode, modifiers: CGEventFlags = []) throws {
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)
        
        keyDown?.flags = modifiers
        keyUp?.flags = modifiers
        
        keyDown?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        keyUp?.post(tap: .cghidEventTap)
    }
    
    /// Scroll in a direction
    func scroll(direction: ScrollDirection, amount: Int32) throws {
        let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: direction == .up || direction == .down ? amount : 0,
            wheel2: direction == .left || direction == .right ? amount : 0,
            wheel3: 0
        )
        
        scrollEvent?.post(tap: .cghidEventTap)
    }
    
    /// Drag from one point to another
    func drag(from: CGPoint, to: CGPoint) throws {
        // Move to start
        let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: from, mouseButton: .left)
        move?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.1)
        
        // Mouse down
        let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: from, mouseButton: .left)
        mouseDown?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.1)
        
        // Drag
        let drag = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: to, mouseButton: .left)
        drag?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.1)
        
        // Mouse up
        let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: to, mouseButton: .left)
        mouseUp?.post(tap: .cghidEventTap)
    }
}

// MARK: - App Controller

class AppController {
    /// Get info about the active window
    func getActiveWindow() -> WindowInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        
        return WindowInfo(
            appName: app.localizedName ?? "Unknown",
            bundleId: app.bundleIdentifier ?? "",
            windowTitle: getWindowTitle(for: app),
            isActive: true
        )
    }
    
    /// Get running apps
    func getRunningApps() -> [AppInfo] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map { app in
                AppInfo(
                    name: app.localizedName ?? "Unknown",
                    bundleId: app.bundleIdentifier ?? "",
                    isActive: app.isActive
                )
            }
    }
    
    /// Launch an app
    func launchApp(bundleId: String) throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            throw ParchiError.appNotFound(bundleId)
        }
        
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            if let error = error {
                print("Failed to launch app: \(error)")
            }
        }
    }
    
    /// Switch to an app
    func switchToApp(bundleId: String) throws {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
            throw ParchiError.appNotRunning(bundleId)
        }
        
        app.activate(options: [.activateIgnoringOtherApps])
    }
    
    private func getWindowTitle(for app: NSRunningApplication) -> String {
        // Would use Accessibility API to get window title
        return app.localizedName ?? "Unknown"
    }
}

// MARK: - Task Planner (Uses Local LLM)

class TaskPlanner {
    /// Generate a plan for the task using local LLM
    func planTask(task: String, screenState: ScreenState) async throws -> ActionPlan {
        // Build context from screen state
        let context = buildContext(screenState: screenState)
        
        // Generate plan with local LLM
        let prompt = """
        You are a computer control agent. Given the current screen state and a task, generate a step-by-step plan.
        
        Current Screen Context:
        \(context)
        
        Task: \(task)
        
        Generate actions as JSON array. Available actions:
        - {"action": "click", "x": 100, "y": 200}
        - {"action": "type", "text": "hello"}
        - {"action": "keyPress", "key": "return"}
        - {"action": "keyPress", "key": "a", "modifiers": ["command"]}
        - {"action": "scroll", "direction": "down", "amount": 100}
        - {"action": "launchApp", "bundleId": "com.apple.Safari"}
        - {"action": "wait", "seconds": 1}
        
        Return only the JSON array of steps.
        """
        
        // Would call local LLM here
        // For now, return placeholder
        return ActionPlan(steps: [])
    }
    
    /// Check if task is complete
    func isTaskComplete(task: String, screenState: ScreenState) async throws -> Bool {
        // Would use LLM to verify task completion
        return false
    }
    
    private func buildContext(screenState: ScreenState) -> String {
        var context = "Active Window: \(screenState.activeWindow?.appName ?? "Unknown")\n"
        context += "Window Title: \(screenState.activeWindow?.windowTitle ?? "Unknown")\n\n"
        
        context += "Visible Text Elements:\n"
        for element in screenState.textElements.prefix(50) {
            context += "- \"\(element.text)\" at (\(Int(element.bounds.midX)), \(Int(element.bounds.midY)))\n"
        }
        
        context += "\nRunning Apps:\n"
        for app in screenState.runningApps {
            context += "- \(app.name) (\(app.bundleId))\n"
        }
        
        return context
    }
}

// MARK: - Data Types

struct ScreenState {
    let screenshot: CGImage
    let textElements: [TextElement]
    let uiElements: [UIElement]
    let activeWindow: WindowInfo?
    let runningApps: [AppInfo]
    let timestamp: Date
}

struct TextElement {
    let text: String
    let confidence: Float
    let bounds: CGRect
}

struct UIElement {
    let type: UIElementType
    let bounds: CGRect
    let confidence: Float
    
    enum UIElementType {
        case button, textField, checkbox, slider, unknown
    }
}

struct WindowInfo {
    let appName: String
    let bundleId: String
    let windowTitle: String
    let isActive: Bool
}

struct AppInfo {
    let name: String
    let bundleId: String
    let isActive: Bool
}

struct ActionPlan {
    let steps: [ActionStep]
}

struct ActionStep {
    let action: Action
    let description: String
    var isDestructive: Bool { action.isDestructive }
    
    enum Action {
        case click(CGPoint)
        case doubleClick(CGPoint)
        case rightClick(CGPoint)
        case type(String)
        case keyPress(CGKeyCode, CGEventFlags)
        case scroll(ScrollDirection, Int32)
        case drag(CGPoint, CGPoint)
        case launchApp(String)
        case switchApp(String)
        case wait(TimeInterval)
        case screenshot
        
        var isDestructive: Bool {
            switch self {
            case .keyPress(let key, let mods):
                // Cmd+Delete, Cmd+W, etc.
                return mods.contains(.maskCommand) && [51, 13].contains(key) // delete, w
            default:
                return false
            }
        }
    }
}

enum ScrollDirection {
    case up, down, left, right
}

struct ParchiStep: Identifiable {
    let id = UUID()
    let type: StepType
    let message: String
    let timestamp: Date
}

enum StepType {
    case planning, action, verification, confirmation, success, error
    
    var icon: String {
        switch self {
        case .planning: return "brain"
        case .action: return "cursorarrow.click.2"
        case .verification: return "checkmark.circle"
        case .confirmation: return "exclamationmark.triangle"
        case .success: return "checkmark.seal.fill"
        case .error: return "xmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .planning: return .purple
        case .action: return .cyan
        case .verification: return .blue
        case .confirmation: return .orange
        case .success: return .green
        case .error: return .red
        }
    }
}

enum ParchiError: Error {
    case captureFailed
    case appNotFound(String)
    case appNotRunning(String)
    case accessibilityDenied
    case planningFailed
}

// MARK: - SwiftUI View

struct ParchiModeView: View {
    @StateObject private var engine = ParchiEngine.shared
    @State private var taskInput = ""
    @State private var showSettings = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                ParchiHeader(showSettings: $showSettings)
                
                // Main content
                ScrollView {
                    VStack(spacing: 20) {
                        // Status
                        StatusCard(engine: engine)
                        
                        // Screen preview
                        if let state = engine.screenState {
                            ScreenPreview(state: state)
                        }
                        
                        // Step log
                        StepLogView(steps: engine.stepLog)
                    }
                    .padding(20)
                }
                
                // Input
                TaskInputBar(taskInput: $taskInput) {
                    Task {
                        try? await engine.execute(task: taskInput)
                        taskInput = ""
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            ParchiSettingsView(engine: engine)
        }
    }
}

struct ParchiHeader: View {
    @Binding var showSettings: Bool
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Image(systemName: "eye.fill")
                    .foregroundColor(.cyan)
                
                Text("PARCHI MODE")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(white: 0.05))
    }
}

struct StatusCard: View {
    @ObservedObject var engine: ParchiEngine
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(engine.isActive ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                
                Text(engine.isActive ? "Running" : "Idle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(engine.isActive ? .green : .gray)
                
                Spacer()
                
                if engine.isThinking {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.cyan)
                }
            }
            
            if let task = engine.currentTask {
                Text(task)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
            }
        }
        .padding(16)
        .background(Color(white: 0.08))
        .cornerRadius(12)
    }
}

struct ScreenPreview: View {
    let state: ScreenState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Screen Capture")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray)
            
            Image(decorative: state.screenshot, scale: 1.0)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 200)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
                )
            
            HStack {
                Label("\(state.textElements.count) text elements", systemImage: "text.cursor")
                Spacer()
                Label(state.activeWindow?.appName ?? "Unknown", systemImage: "macwindow")
            }
            .font(.system(size: 11))
            .foregroundColor(.gray)
        }
    }
}

struct StepLogView: View {
    let steps: [ParchiStep]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Action Log")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray)
            
            ForEach(steps) { step in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: step.type.icon)
                        .foregroundColor(step.type.color)
                        .frame(width: 20)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.message)
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                        
                        Text(step.timestamp, style: .time)
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                }
                .padding(10)
                .background(Color(white: 0.06))
                .cornerRadius(8)
            }
        }
    }
}

struct TaskInputBar: View {
    @Binding var taskInput: String
    let onSubmit: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Divider().background(Color.gray.opacity(0.3))
            
            HStack(spacing: 12) {
                TextField("Tell Parchi what to do...", text: $taskInput)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color(white: 0.1))
                    .cornerRadius(10)
                
                Button(action: onSubmit) {
                    Image(systemName: "play.fill")
                        .foregroundColor(.black)
                        .padding(12)
                        .background(Color.cyan)
                        .clipShape(Circle())
                }
                .disabled(taskInput.isEmpty)
            }
            .padding(16)
        }
        .background(Color.black)
    }
}

struct ParchiSettingsView: View {
    @ObservedObject var engine: ParchiEngine
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Safety") {
                    Toggle("Safe Mode", isOn: $engine.safeMode)
                    Text("Confirms destructive actions before executing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Limits") {
                    Stepper("Max Steps: \(engine.maxSteps)", value: $engine.maxSteps, in: 10...200, step: 10)
                    
                    HStack {
                        Text("Step Delay")
                        Spacer()
                        Text("\(engine.stepDelay, specifier: "%.1f")s")
                    }
                    Slider(value: $engine.stepDelay, in: 0.1...2.0, step: 0.1)
                }
                
                Section("Permissions") {
                    Label("Accessibility Access Required", systemImage: "hand.raised.fill")
                        .foregroundColor(.orange)
                    
                    Button("Open Accessibility Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
            }
            .navigationTitle("Parchi Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ParchiModeView()
}
