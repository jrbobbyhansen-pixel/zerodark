//
//  NuclearDemo.swift
//  ZeroDark
//
//  AI + Tools. On-device.
//

import SwiftUI

// MARK: - Nuclear Demo View

public struct NuclearDemoTab: View {
    @StateObject private var viewModel = NuclearViewModel()
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.messages) { message in
                                NuclearMessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        if let last = viewModel.messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Power mode selector
                modeSelector
                
                // Tool executions
                if !viewModel.recentTools.isEmpty {
                    toolsBar
                }
                
                // Quick actions
                quickActionsBar
                
                // Input
                inputBar
            }
            .background(Color.black)
            .navigationTitle("☢️ Nuclear")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button("Clear Chat", systemImage: "trash") {
                            viewModel.clearChat()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.cyan)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Auto-load recommended model if none loaded
            let manager = MLXModelManager.shared
            if !manager.isReady && !manager.isLoading {
                Task {
                    if let recommended = manager.availableModels.first(where: { $0.recommended }) {
                        try? await manager.loadModel(recommended.id)
                    }
                }
            }
        }
    }
    
    // MARK: - Mode Selector
    
    private var modeSelector: some View {
        HStack(spacing: 8) {
            Text("Power:")
                .font(.caption)
                .foregroundColor(.gray)
            
            ForEach(ZeroDarkEngine.InferenceMode.allCases, id: \.self) { mode in
                Button {
                    viewModel.currentMode = mode
                } label: {
                    VStack(spacing: 2) {
                        Text(mode.rawValue)
                            .font(.caption2)
                            .fontWeight(viewModel.currentMode == mode ? .bold : .regular)
                        Text(modeSize(mode))
                            .font(.system(size: 8))
                    }
                    .foregroundColor(viewModel.currentMode == mode ? .cyan : .gray)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(viewModel.currentMode == mode ? Color.cyan.opacity(0.2) : Color.clear)
                    .cornerRadius(8)
                }
            }
            
            Spacer()
            
            Text("≈\(viewModel.equivalentSize)")
                .font(.caption)
                .foregroundColor(.cyan)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.cyan.opacity(0.1))
                .cornerRadius(8)
        }
        .padding(.horizontal)
        .frame(height: 36)
    }
    
    private func modeSize(_ mode: ZeroDarkEngine.InferenceMode) -> String {
        switch mode {
        case .quick: return "8B"
        case .standard: return "50B"
        case .deep: return "150B"
        case .maximum: return "300B+"
        case .adaptive: return "Auto"
        }
    }
    
    // MARK: - Tools Bar
    
    private var toolsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.recentTools) { tool in
                    HStack(spacing: 4) {
                        Image(systemName: tool.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(tool.success ? .green : .red)
                            .font(.caption)
                        Text(tool.tool)
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 36)
    }
    
    // MARK: - Quick Actions
    
    private var quickActionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                NuclearQuickAction(text: "Weather", icon: "cloud.sun.fill") {
                    viewModel.sendMessage("What's the weather in San Antonio?")
                }
                NuclearQuickAction(text: "Calendar", icon: "calendar") {
                    viewModel.sendMessage("What's on my calendar today?")
                }
                NuclearQuickAction(text: "Reminder", icon: "bell.fill") {
                    viewModel.sendMessage("Remind me to call the dentist")
                }
                NuclearQuickAction(text: "Calculate", icon: "function") {
                    viewModel.sendMessage("What's 15% of 847?")
                }
                NuclearQuickAction(text: "Time", icon: "clock.fill") {
                    viewModel.sendMessage("What time is it?")
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 44)
        .background(Color.white.opacity(0.03))
    }
    
    // MARK: - Input Bar
    
    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Ask anything...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color.white.opacity(0.1))
                .cornerRadius(20)
                .foregroundColor(.white)
                .focused($isInputFocused)
                .lineLimit(1...4)
                .onSubmit {
                    sendMessage()
                }
            
            Button {
                sendMessage()
            } label: {
                Image(systemName: viewModel.isProcessing ? "stop.fill" : "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundColor(.cyan)
            }
            .disabled(inputText.isEmpty && !viewModel.isProcessing)
        }
        .padding()
        .background(Color.black)
    }
    
    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        let text = inputText
        inputText = ""
        viewModel.sendMessage(text)
    }
}

// MARK: - Quick Action Button

struct NuclearQuickAction: View {
    let text: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(text)
                    .font(.caption)
            }
            .foregroundColor(.cyan)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.cyan.opacity(0.15))
            .cornerRadius(16)
        }
    }
}

// MARK: - Message Bubble

struct NuclearMessageBubble: View {
    let message: NuclearMessage
    
    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 60) }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(message.isUser ? Color.cyan.opacity(0.3) : Color.white.opacity(0.1))
                    .cornerRadius(16)
                
                if let tool = message.toolUsed {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.fill")
                            .font(.caption2)
                        Text(tool)
                            .font(.caption2)
                    }
                    .foregroundColor(.gray)
                }
            }
            
            if !message.isUser { Spacer(minLength: 60) }
        }
    }
}

// MARK: - View Model

@MainActor
class NuclearViewModel: ObservableObject {
    @Published var messages: [NuclearMessage] = []
    @Published var recentTools: [ToolExecution] = []
    @Published var isProcessing = false
    @Published var currentMode: ZeroDarkEngine.InferenceMode = .standard
    @Published var equivalentSize: String = "8B"
    
    private let toolkit = AgentToolkit.shared
    private let engine = ZeroDarkEngine.shared
    
    func sendMessage(_ text: String) {
        let userMessage = NuclearMessage(content: text, isUser: true)
        messages.append(userMessage)
        
        isProcessing = true
        
        Task {
            // Check if this needs a tool
            let toolResult = await executeToolIfNeeded(text)
            
            var response: String
            var toolUsed: String?
            
            if let result = toolResult {
                // Tool was executed - use its result
                toolUsed = result.tool
                recentTools.insert(result, at: 0)
                if recentTools.count > 5 { recentTools.removeLast() }
                
                // Generate response incorporating tool result
                let prompt = """
                User asked: \(text)
                
                Tool "\(result.tool)" returned: \(result.result)
                
                Respond naturally to the user, incorporating this information.
                """
                let zdResult = await engine.generate(prompt: prompt, mode: currentMode)
                response = zdResult.response
                equivalentSize = zdResult.equivalentSize
                
                // If generation failed, just use the tool result
                if response.isEmpty {
                    response = result.result
                }
            } else {
                // No tool needed - use ZeroDarkEngine with full power
                let zdResult = await engine.generate(prompt: text, mode: currentMode)
                response = zdResult.response
                equivalentSize = zdResult.equivalentSize
            }
            
            let aiMessage = NuclearMessage(content: response, isUser: false, toolUsed: toolUsed)
            messages.append(aiMessage)
            isProcessing = false
        }
    }
    
    private func executeToolIfNeeded(_ text: String) async -> ToolExecution? {
        let lower = text.lowercased()
        
        // Weather detection
        if lower.contains("weather") || lower.contains("temperature") || lower.contains("forecast") {
            let location = extractLocation(from: text) ?? "San Antonio"
            let call = AgentToolkit.ToolCall(tool: "weather", arguments: ["location": location])
            let result = await toolkit.execute(call)
            return ToolExecution(tool: "weather", input: text, result: result.output, success: result.success)
        }
        
        // Calendar detection
        if lower.contains("calendar") || lower.contains("schedule") || lower.contains("events") || lower.contains("meeting") {
            let call = AgentToolkit.ToolCall(tool: "calendar", arguments: [:])
            let result = await toolkit.execute(call)
            return ToolExecution(tool: "calendar", input: text, result: result.output, success: result.success)
        }
        
        // Reminder detection
        if lower.contains("remind") || lower.contains("reminder") {
            let title = extractReminderText(from: text)
            let call = AgentToolkit.ToolCall(tool: "reminder", arguments: ["title": title])
            let result = await toolkit.execute(call)
            return ToolExecution(tool: "reminder", input: text, result: result.output, success: result.success)
        }
        
        // Math detection
        if lower.contains("calculate") || lower.contains("what's") && (lower.contains("%") || lower.contains("+") || lower.contains("-") || lower.contains("*") || lower.contains("/")) {
            let expression = extractMathExpression(from: text)
            let call = AgentToolkit.ToolCall(tool: "calculator", arguments: ["expression": expression])
            let result = await toolkit.execute(call)
            return ToolExecution(tool: "calculator", input: text, result: result.output, success: result.success)
        }
        
        // Time detection
        if lower.contains("time") || lower.contains("date") || lower.contains("today") {
            let call = AgentToolkit.ToolCall(tool: "time", arguments: [:])
            let result = await toolkit.execute(call)
            return ToolExecution(tool: "time", input: text, result: result.output, success: result.success)
        }
        
        return nil
    }
    
    private func extractLocation(from text: String) -> String? {
        let cities = ["san antonio", "austin", "houston", "dallas", "new york", "los angeles"]
        let lower = text.lowercased()
        for city in cities {
            if lower.contains(city) {
                return city.capitalized
            }
        }
        return nil
    }
    
    private func extractReminderText(from text: String) -> String {
        var cleaned = text.lowercased()
        let prefixes = ["remind me to", "remind me", "set a reminder to", "set reminder"]
        for prefix in prefixes {
            if cleaned.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count))
            }
        }
        return cleaned.trimmingCharacters(in: .whitespaces).capitalized
    }
    
    private func extractMathExpression(from text: String) -> String {
        // Extract numbers and operators
        var expr = text.lowercased()
        expr = expr.replacingOccurrences(of: "what's", with: "")
        expr = expr.replacingOccurrences(of: "what is", with: "")
        expr = expr.replacingOccurrences(of: "calculate", with: "")
        expr = expr.replacingOccurrences(of: "of", with: "*0.01*")
        expr = expr.replacingOccurrences(of: "%", with: "")
        expr = expr.replacingOccurrences(of: "$", with: "")
        return expr.trimmingCharacters(in: .whitespaces)
    }
    
    func clearChat() {
        messages.removeAll()
        recentTools.removeAll()
    }
}

// MARK: - Message Model

struct NuclearMessage: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
    var toolUsed: String?
    let timestamp = Date()
}
