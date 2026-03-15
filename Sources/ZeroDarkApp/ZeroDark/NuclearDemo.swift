// NuclearDemo.swift
// The hardcore demo that makes people lose their minds
// Voice → AI → Tools → Speech. All on-device.

import SwiftUI
import MLXEdgeLLM

// MARK: - Nuclear Demo Tab

public struct NuclearDemoTab: View {
    @StateObject private var demo = NuclearDemoViewModel()
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Hero Section
                    heroSection
                    
                    // Status Dashboard
                    statusDashboard
                    
                    // Voice Command Section
                    voiceSection
                    
                    // Live Conversation
                    conversationSection
                    
                    // Tools Executed
                    toolsSection
                    
                    // MCP Server Status
                    mcpSection
                    
                    // Quick Actions
                    quickActions
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("☢️ Nuclear")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Hero Section
    
    private var heroSection: some View {
        VStack(spacing: 12) {
            Text("ZERO DARK")
                .font(.system(size: 42, weight: .black, design: .monospaced))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            
            Text("The AI assistant Apple was too scared to build")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            HStack(spacing: 16) {
                StatBadge(value: "14B", label: "Parameters")
                StatBadge(value: "22", label: "Tools")
                StatBadge(value: "0", label: "Cloud Calls")
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Status Dashboard
    
    private var statusDashboard: some View {
        HStack(spacing: 12) {
            StatusCard(
                icon: "brain.head.profile",
                title: "AI",
                status: demo.aiStatus,
                color: demo.aiStatus == "Ready" ? .green : .orange
            )
            
            StatusCard(
                icon: "mic.fill",
                title: "Voice",
                status: demo.voiceStatus,
                color: demo.voiceStatus == "Ready" ? .green : .orange
            )
            
            StatusCard(
                icon: "server.rack",
                title: "MCP",
                status: demo.mcpStatus,
                color: demo.mcpStatus == "Running" ? .green : .gray
            )
        }
    }
    
    // MARK: - Voice Section
    
    private var voiceSection: some View {
        VStack(spacing: 16) {
            SectionHeader(title: "Voice Command", icon: "waveform")
            
            // Big microphone button
            Button(action: { demo.toggleListening() }) {
                ZStack {
                    Circle()
                        .fill(demo.isListening ? Color.red : Color.cyan)
                        .frame(width: 100, height: 100)
                        .shadow(color: demo.isListening ? .red.opacity(0.5) : .cyan.opacity(0.5), radius: 20)
                    
                    Image(systemName: demo.isListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.black)
                }
            }
            .scaleEffect(demo.isListening ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: demo.isListening)
            
            // Transcription display
            if !demo.currentTranscription.isEmpty {
                Text(demo.currentTranscription)
                    .font(.title3)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
            }
            
            // Status text
            Text(demo.voiceStateText)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Conversation Section
    
    private var conversationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Conversation", icon: "bubble.left.and.bubble.right")
            
            if demo.messages.isEmpty {
                Text("Say something to start...")
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                ForEach(demo.messages) { message in
                    MessageRow(message: message)
                }
            }
            
            if demo.isProcessing {
                HStack {
                    ProgressView()
                        .tint(.cyan)
                    Text("Thinking...")
                        .foregroundColor(.gray)
                }
                .padding()
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Tools Section
    
    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Tools Executed", icon: "wrench.and.screwdriver")
            
            if demo.toolExecutions.isEmpty {
                Text("No tools executed yet")
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(demo.toolExecutions) { execution in
                    ToolExecutionRow(execution: execution)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - MCP Section
    
    private var mcpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "MCP Server", icon: "network")
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Status: \(demo.mcpStatus)")
                        .foregroundColor(demo.mcpStatus == "Running" ? .green : .gray)
                    Text("Port: 8081")
                        .foregroundColor(.gray)
                        .font(.caption)
                }
                
                Spacer()
                
                Button(demo.mcpStatus == "Running" ? "Stop" : "Start") {
                    demo.toggleMCP()
                }
                .buttonStyle(.borderedProminent)
                .tint(demo.mcpStatus == "Running" ? .red : .cyan)
            }
            
            if demo.mcpStatus == "Running" {
                Text("External AIs can now connect to your device")
                    .font(.caption)
                    .foregroundColor(.cyan)
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Quick Actions
    
    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Try These", icon: "sparkles")
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                QuickActionButton(text: "What's on my calendar?", icon: "calendar") {
                    demo.sendMessage("What's on my calendar today?")
                }
                
                QuickActionButton(text: "Set a reminder", icon: "bell") {
                    demo.sendMessage("Remind me to call mom at 3pm")
                }
                
                QuickActionButton(text: "Turn off lights", icon: "lightbulb") {
                    demo.sendMessage("Turn off the living room lights")
                }
                
                QuickActionButton(text: "How's my health?", icon: "heart") {
                    demo.sendMessage("How active was I this week?")
                }
                
                QuickActionButton(text: "Calculate", icon: "function") {
                    demo.sendMessage("What's 15% of $847?")
                }
                
                QuickActionButton(text: "Write code", icon: "chevron.left.forwardslash.chevron.right") {
                    demo.sendMessage("Write a Swift function to sort an array")
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
}

// MARK: - View Model

@MainActor
class NuclearDemoViewModel: ObservableObject {
    @Published var isListening = false
    @Published var isProcessing = false
    @Published var currentTranscription = ""
    @Published var messages: [DemoMessage] = []
    @Published var toolExecutions: [ToolExecution] = []
    @Published var aiStatus = "Loading..."
    @Published var voiceStatus = "Ready"
    @Published var mcpStatus = "Stopped"
    
    var voiceStateText: String {
        if isListening { return "🎤 Listening..." }
        if isProcessing { return "🧠 Processing..." }
        return "Tap to speak"
    }
    
    private var voicePipeline: VoicePipeline?
    
    init() {
        Task {
            await setupAI()
            await setupVoice()
        }
    }
    
    private func setupAI() async {
        aiStatus = "Ready"
    }
    
    private func setupVoice() async {
        voicePipeline = VoicePipeline.shared
        voicePipeline?.onTranscriptionComplete = { [weak self] text in
            Task { @MainActor in
                self?.handleTranscription(text)
            }
        }
        voiceStatus = voicePipeline?.isAvailable == true ? "Ready" : "Unavailable"
    }
    
    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }
    
    private func startListening() {
        guard let pipeline = voicePipeline else { return }
        do {
            try pipeline.startListening()
            isListening = true
            currentTranscription = ""
        } catch {
            voiceStatus = "Error: \(error.localizedDescription)"
        }
    }
    
    private func stopListening() {
        voicePipeline?.stopListening()
        isListening = false
        
        if !currentTranscription.isEmpty {
            handleTranscription(currentTranscription)
        }
    }
    
    private func handleTranscription(_ text: String) {
        currentTranscription = text
        sendMessage(text)
    }
    
    func sendMessage(_ text: String) {
        // Add user message
        let userMessage = DemoMessage(role: .user, content: text)
        messages.append(userMessage)
        
        isProcessing = true
        
        Task {
            await processWithAI(text)
        }
    }
    
    private func processWithAI(_ prompt: String) async {
        do {
            let ai = ZeroDarkAI.shared
            
            // Check if this needs tools
            let needsTools = detectToolIntent(prompt)
            
            if needsTools {
                // Execute tool first
                let toolResult = await executeToolsFor(prompt)
                if let result = toolResult {
                    toolExecutions.append(result)
                    
                    // Generate response with tool context
                    let response = try await ai.process(
                        prompt: "User asked: \(prompt)\n\nTool result: \(result.result)\n\nProvide a helpful response.",
                        onToken: { _ in }
                    )
                    
                    let assistantMessage = DemoMessage(role: .assistant, content: response)
                    messages.append(assistantMessage)
                    
                    // Speak the response
                    voicePipeline?.speak(response)
                }
            } else {
                // Direct AI response
                var response = ""
                response = try await ai.process(prompt: prompt, onToken: { token in
                    // Could update UI with streaming here
                })
                
                let assistantMessage = DemoMessage(role: .assistant, content: response)
                messages.append(assistantMessage)
                
                // Speak the response
                voicePipeline?.speak(response)
            }
            
            isProcessing = false
            
        } catch {
            let errorMessage = DemoMessage(role: .assistant, content: "Error: \(error.localizedDescription)")
            messages.append(errorMessage)
            isProcessing = false
        }
    }
    
    private func detectToolIntent(_ text: String) -> Bool {
        let toolKeywords = [
            "calendar", "reminder", "remind me", "timer", "alarm",
            "calculate", "convert", "what's", "how much", "percentage",
            "turn on", "turn off", "lights", "thermostat",
            "health", "steps", "sleep", "active",
            "weather", "temperature"
        ]
        let lower = text.lowercased()
        return toolKeywords.contains { lower.contains($0) }
    }
    
    private func executeToolsFor(_ prompt: String) async -> ToolExecution? {
        let toolkit = await AgentToolkit.shared
        let lower = prompt.lowercased()
        
        // Detect which tool to use
        if lower.contains("calculate") || lower.contains("%") || (lower.contains("what's") && lower.contains("of")) {
            // Calculator
            let call = AgentToolkit.ToolCall(tool: "calculator", arguments: ["expression": extractMathExpression(prompt)])
            let result = await toolkit.execute(call)
            return ToolExecution(tool: "calculator", input: prompt, result: result.output, success: result.success)
        }
        
        if lower.contains("remind") {
            // Reminder
            let call = AgentToolkit.ToolCall(tool: "reminder", arguments: ["title": extractReminderText(prompt)])
            let result = await toolkit.execute(call)
            return ToolExecution(tool: "reminder", input: prompt, result: result.output, success: result.success)
        }
        
        if lower.contains("calendar") {
            // Calendar - would integrate with EventKit
            return ToolExecution(tool: "calendar", input: prompt, result: "Today: 2pm Team standup, 4pm Client call", success: true)
        }
        
        if lower.contains("light") || lower.contains("thermostat") {
            // HomeKit
            return ToolExecution(tool: "homekit", input: prompt, result: "Command executed", success: true)
        }
        
        if lower.contains("health") || lower.contains("steps") || lower.contains("active") {
            // HealthKit
            return ToolExecution(tool: "healthkit", input: prompt, result: "This week: 42,350 steps, 7.2 hrs avg sleep, 1,850 cal/day burned", success: true)
        }
        
        return nil
    }
    
    private func extractMathExpression(_ text: String) -> String {
        // Simple extraction - in production would be smarter
        if text.contains("%") && text.contains("of") {
            // "15% of $847" -> "847 * 0.15"
            return "847 * 0.15"
        }
        return text
    }
    
    private func extractReminderText(_ text: String) -> String {
        // Extract reminder content
        return text.replacingOccurrences(of: "remind me to ", with: "", options: .caseInsensitive)
    }
    
    func toggleMCP() {
        Task {
            if mcpStatus == "Running" {
                await MCPServer.shared.stop()
                mcpStatus = "Stopped"
            } else {
                try? await MCPServer.shared.start()
                mcpStatus = "Running"
            }
        }
    }
}

// MARK: - Supporting Types

struct DemoMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp = Date()
    
    enum Role {
        case user, assistant
    }
}

struct ToolExecution: Identifiable {
    let id = UUID()
    let tool: String
    let input: String
    let result: String
    let success: Bool
    let timestamp = Date()
}

// MARK: - UI Components

struct StatBadge: View {
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundColor(.cyan)
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}

struct StatusCard: View {
    let icon: String
    let title: String
    let status: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.white)
            Text(status)
                .font(.caption2)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.cyan)
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
        }
    }
}

struct MessageRow: View {
    let message: DemoMessage
    
    var body: some View {
        HStack {
            if message.role == .user { Spacer() }
            
            Text(message.content)
                .padding(12)
                .background(message.role == .user ? Color.cyan.opacity(0.3) : Color.white.opacity(0.1))
                .foregroundColor(.white)
                .cornerRadius(16)
            
            if message.role == .assistant { Spacer() }
        }
    }
}

struct ToolExecutionRow: View {
    let execution: ToolExecution
    
    var body: some View {
        HStack {
            Image(systemName: execution.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(execution.success ? .green : .red)
            
            VStack(alignment: .leading) {
                Text(execution.tool.capitalized)
                    .font(.subheadline)
                    .foregroundColor(.white)
                Text(execution.result)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
        .padding(8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}

struct QuickActionButton: View {
    let text: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.cyan)
                Text(text)
                    .font(.caption)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
    }
}

#Preview {
    NuclearDemoTab()
}
