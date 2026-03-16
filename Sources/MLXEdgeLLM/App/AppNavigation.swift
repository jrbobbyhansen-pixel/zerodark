//
//  AppNavigation.swift
//  ZeroDark
//
//  Clean. Four tabs. Everything works.
//

import SwiftUI

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var selectedTab: AppTab = .chat
}

// MARK: - Tab Definition

enum AppTab: String, CaseIterable {
    case chat = "Chat"
    case zeta = "Zeta³"
    case memory = "Memory"
    case more = "More"
    
    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .zeta: return "sparkles"
        case .memory: return "brain.head.profile"
        case .more: return "gearshape.fill"
        }
    }
}

// MARK: - Main App Container

struct CoreContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        TabView(selection: $appState.selectedTab) {
            MainChatView()
                .tabItem {
                    Label(AppTab.chat.label, systemImage: AppTab.chat.icon)
                }
                .tag(AppTab.chat)
            
            TakeoverTab()
                .tabItem {
                    Label(AppTab.zeta.label, systemImage: AppTab.zeta.icon)
                }
                .tag(AppTab.zeta)
            
            MemoryView()
                .tabItem {
                    Label(AppTab.memory.label, systemImage: AppTab.memory.icon)
                }
                .tag(AppTab.memory)
            
            MoreView()
                .tabItem {
                    Label(AppTab.more.label, systemImage: AppTab.more.icon)
                }
                .tag(AppTab.more)
        }
        .tint(.cyan)
    }
}

extension AppTab {
    var label: String { rawValue }
}

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: 1. CHAT TAB (Main AI Interface)
// MARK: ═══════════════════════════════════════════════════════════════════

struct MainChatView: View {
    @StateObject private var viewModel = MainChatViewModel()
    @StateObject private var modelManager = MLXModelManager.shared
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Model status bar
                if !modelManager.isReady {
                    modelStatusBar
                }
                
                // Power mode selector
                powerModeBar
                
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if viewModel.messages.isEmpty {
                                emptyState
                            }
                            ForEach(viewModel.messages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        if let last = viewModel.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
                
                // Tools bar (when tools executed)
                if !viewModel.recentTools.isEmpty {
                    toolsBar
                }
                
                // Input bar
                inputBar
            }
            .background(Color.black)
            .navigationTitle("ZeroDark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(modelManager.isReady ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text("ZeroDark")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Clear Chat", systemImage: "trash") {
                            viewModel.clearChat()
                        }
                        Divider()
                        ForEach(ZeroDarkEngine.InferenceMode.allCases, id: \.self) { mode in
                            Button {
                                viewModel.currentMode = mode
                            } label: {
                                HStack {
                                    Text(mode.rawValue)
                                    if viewModel.currentMode == mode {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
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
            // Auto-load model
            if !modelManager.isReady && !modelManager.isLoading {
                Task {
                    if let recommended = modelManager.availableModels.first(where: { $0.recommended }) {
                        try? await modelManager.loadModel(recommended.id)
                    }
                }
            }
        }
    }
    
    // MARK: - Model Status
    
    private var modelStatusBar: some View {
        HStack {
            if modelManager.isLoading {
                ProgressView(value: modelManager.loadProgress)
                    .tint(.cyan)
                Text("\(Int(modelManager.loadProgress * 100))%")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("No model loaded")
                    .font(.caption)
                    .foregroundColor(.orange)
                Spacer()
                Button("Load") {
                    Task {
                        if let m = modelManager.availableModels.first(where: { $0.recommended }) {
                            try? await modelManager.loadModel(m.id)
                        }
                    }
                }
                .font(.caption)
                .foregroundColor(.cyan)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }
    
    // MARK: - Power Mode
    
    private var powerModeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ZeroDarkEngine.InferenceMode.allCases, id: \.self) { mode in
                    Button {
                        viewModel.currentMode = mode
                    } label: {
                        VStack(spacing: 2) {
                            Text(mode.rawValue)
                                .font(.caption2)
                                .fontWeight(viewModel.currentMode == mode ? .bold : .regular)
                            Text(modeDescription(mode))
                                .font(.system(size: 9))
                                .foregroundColor(.gray)
                        }
                        .foregroundColor(viewModel.currentMode == mode ? .cyan : .gray)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(viewModel.currentMode == mode ? Color.cyan.opacity(0.15) : Color.clear)
                        .cornerRadius(12)
                    }
                }
                
                Spacer()
                
                // Equivalent size indicator
                Text("≈\(viewModel.equivalentSize)")
                    .font(.caption2)
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.cyan.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding(.horizontal)
        }
        .frame(height: 44)
        .background(Color.white.opacity(0.02))
    }
    
    private func modeDescription(_ mode: ZeroDarkEngine.InferenceMode) -> String {
        switch mode {
        case .quick: return "~8B"
        case .standard: return "~50B"
        case .deep: return "~150B"
        case .maximum: return "~300B+"
        case .adaptive: return "Auto"
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 60)
            
            Image(systemName: "sparkles")
                .font(.system(size: 50))
                .foregroundColor(.cyan.opacity(0.5))
            
            Text("What can I help with?")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            Text("I can search the web, check weather, manage reminders, analyze images, and more.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            // Quick suggestions
            VStack(spacing: 8) {
                SuggestionButton(text: "What's the weather?") {
                    sendMessage("What's the weather in San Antonio?")
                }
                SuggestionButton(text: "Set a reminder") {
                    sendMessage("Remind me to check email at 5pm")
                }
                SuggestionButton(text: "What's on my calendar?") {
                    sendMessage("What's on my calendar today?")
                }
            }
            .padding(.top, 20)
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
                            .font(.caption2)
                        Text(tool.tool)
                            .font(.caption2)
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
    
    // MARK: - Input Bar
    
    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Message", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color.white.opacity(0.1))
                .cornerRadius(20)
                .foregroundColor(.white)
                .focused($isInputFocused)
                .lineLimit(1...4)
                .onSubmit { sendMessage(inputText) }
            
            Button {
                sendMessage(inputText)
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
    
    private func sendMessage(_ text: String) {
        guard !text.isEmpty else { return }
        inputText = ""
        viewModel.sendMessage(text)
    }
}

// MARK: - Chat View Model

@MainActor
class MainChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var recentTools: [ToolExecution] = []
    @Published var isProcessing = false
    @Published var currentMode: ZeroDarkEngine.InferenceMode = .standard
    @Published var equivalentSize: String = "8B"
    
    private let toolkit = AgentToolkit.shared
    private let engine = ZeroDarkEngine.shared
    
    func sendMessage(_ text: String) {
        let userMessage = ChatMessage(content: text, isUser: true)
        messages.append(userMessage)
        
        isProcessing = true
        
        Task {
            // Check if this needs a tool
            let toolResult = await executeToolIfNeeded(text)
            
            var response: String
            var toolUsed: String?
            
            if let result = toolResult {
                toolUsed = result.tool
                recentTools.insert(result, at: 0)
                if recentTools.count > 5 { recentTools.removeLast() }
                
                let prompt = """
                User asked: \(text)
                
                Tool "\(result.tool)" returned: \(result.result)
                
                Respond naturally, incorporating this information.
                """
                let zdResult = await engine.generate(prompt: prompt, mode: currentMode)
                response = zdResult.response
                equivalentSize = zdResult.equivalentSize
                
                if response.isEmpty { response = result.result }
            } else {
                let zdResult = await engine.generate(prompt: text, mode: currentMode)
                response = zdResult.response
                equivalentSize = zdResult.equivalentSize
            }
            
            let aiMessage = ChatMessage(content: response, isUser: false, toolUsed: toolUsed)
            messages.append(aiMessage)
            isProcessing = false
        }
    }
    
    private func executeToolIfNeeded(_ text: String) async -> ToolExecution? {
        let lower = text.lowercased()
        
        if lower.contains("weather") || lower.contains("temperature") || lower.contains("forecast") {
            let location = extractLocation(from: text) ?? "San Antonio"
            let call = AgentToolkit.ToolCall(tool: "weather", arguments: ["location": location])
            let result = await toolkit.execute(call)
            return ToolExecution(tool: "weather", input: text, result: result.output, success: result.success)
        }
        
        if lower.contains("calendar") || lower.contains("schedule") || lower.contains("events") || lower.contains("meeting") {
            let call = AgentToolkit.ToolCall(tool: "calendar", arguments: [:])
            let result = await toolkit.execute(call)
            return ToolExecution(tool: "calendar", input: text, result: result.output, success: result.success)
        }
        
        if lower.contains("remind") || lower.contains("reminder") {
            let title = extractReminderText(from: text)
            let call = AgentToolkit.ToolCall(tool: "reminder", arguments: ["title": title])
            let result = await toolkit.execute(call)
            return ToolExecution(tool: "reminder", input: text, result: result.output, success: result.success)
        }
        
        if lower.contains("time") || lower.contains("date") || lower.contains("today") || lower.contains("what day") {
            let call = AgentToolkit.ToolCall(tool: "time", arguments: [:])
            let result = await toolkit.execute(call)
            return ToolExecution(tool: "time", input: text, result: result.output, success: result.success)
        }
        
        return nil
    }
    
    private func extractLocation(from text: String) -> String? {
        let cities = ["san antonio", "austin", "houston", "dallas", "new york", "los angeles"]
        let lower = text.lowercased()
        for city in cities { if lower.contains(city) { return city.capitalized } }
        return nil
    }
    
    private func extractReminderText(from text: String) -> String {
        var cleaned = text.lowercased()
        for prefix in ["remind me to", "remind me", "set a reminder to", "set reminder"] {
            if cleaned.hasPrefix(prefix) { cleaned = String(cleaned.dropFirst(prefix.count)) }
        }
        return cleaned.trimmingCharacters(in: .whitespaces).capitalized
    }
    
    func clearChat() {
        messages.removeAll()
        recentTools.removeAll()
    }
}

// MARK: - Chat Message

struct ChatMessage: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
    var toolUsed: String?
    let timestamp = Date()
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 60) }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(14)
                    .background(
                        message.isUser
                            ? LinearGradient(colors: [.cyan.opacity(0.4), .cyan.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .cornerRadius(20)
                
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

// MARK: - Suggestion Button

struct SuggestionButton: View {
    let text: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline)
                .foregroundColor(.cyan)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.cyan.opacity(0.1))
                .cornerRadius(20)
        }
    }
}

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: 2. MEMORY TAB (What I Know About You)
// MARK: ═══════════════════════════════════════════════════════════════════

struct MemoryView: View {
    @StateObject private var memory = InfiniteMemorySystem.shared
    @State private var searchText = ""
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Search
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Search memories...", text: $searchText)
                            .textFieldStyle(.plain)
                            .foregroundColor(.white)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Memory Stats
                    HStack(spacing: 16) {
                        MemoryStatCard(
                            icon: "lightbulb.fill",
                            title: "Facts",
                            value: memory.semanticCount,
                            color: .yellow
                        )
                        MemoryStatCard(
                            icon: "clock.fill",
                            title: "Episodes",
                            value: memory.episodicCount,
                            color: .blue
                        )
                        MemoryStatCard(
                            icon: "gearshape.fill",
                            title: "Rules",
                            value: memory.proceduralCount,
                            color: .green
                        )
                    }
                    
                    // Efficiency
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Efficiency")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(memory.totalTokensSaved)")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                                Text("tokens saved")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing) {
                                Text(String(format: "%.1fx", memory.compressionRatio))
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(.cyan)
                                Text("compression")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(16)
                    }
                    
                    // Viking Memory Tiers
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Memory Architecture")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        MemoryTierRow(tier: "L0 (Hot)", description: "Always loaded, ~100 tokens", color: .red)
                        MemoryTierRow(tier: "L1 (Warm)", description: "Loaded when relevant, ~500 tokens", color: .orange)
                        MemoryTierRow(tier: "L2 (Cold)", description: "Full content, loaded on demand", color: .blue)
                    }
                    
                    // How it works
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How It Works")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text("ZeroDark learns from your conversations. Facts, preferences, and patterns are stored locally on your device. Nothing ever leaves.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(16)
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("Memory")
        }
        .preferredColorScheme(.dark)
    }
}

struct MemoryStatCard: View {
    let icon: String
    let title: String
    let value: Int
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text("\(value)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
}

struct MemoryTierRow: View {
    let tier: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            Text(tier)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
            Spacer()
            Text(description)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: 3. MORE TAB (Settings)
// MARK: ═══════════════════════════════════════════════════════════════════

struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("AI Engine") {
                    NavigationLink {
                        ModelsSettingsView()
                    } label: {
                        SettingsRow(icon: "cpu", title: "Models", subtitle: "Download and manage", color: .cyan)
                    }
                    
                    NavigationLink {
                        EngineSettingsView()
                    } label: {
                        SettingsRow(icon: "bolt.fill", title: "Inference", subtitle: "Power modes & techniques", color: .yellow)
                    }
                }
                
                Section("Personalization") {
                    NavigationLink {
                        IdentitySettingsTab()
                    } label: {
                        SettingsRow(icon: "person.fill", title: "Identity", subtitle: "Name, personality, voice", color: .purple)
                    }
                }
                
                Section("Labs") {
                    NavigationLink {
                        ScreenAgentTab()
                    } label: {
                        SettingsRow(icon: "rectangle.inset.filled.and.cursorarrow", title: "Parchi Mode", subtitle: "Computer use (macOS)", color: .mint)
                    }
                    
                    NavigationLink {
                        FineTuningTab()
                    } label: {
                        SettingsRow(icon: "brain.head.profile", title: "Fine-Tuning", subtitle: "On-device LoRA training", color: .indigo)
                    }
                }
                
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        SettingsRow(icon: "info.circle", title: "About", subtitle: "Version 1.0", color: .gray)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("More")
        }
        .preferredColorScheme(.dark)
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    var subtitle: String = ""
    let color: Color
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(.white)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
    }
}

// MARK: - Models Settings

struct ModelsSettingsView: View {
    @StateObject private var modelManager = MLXModelManager.shared
    
    var body: some View {
        List {
            Section("Current Model") {
                if modelManager.isReady, let current = modelManager.currentModelId {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(current.components(separatedBy: "/").last ?? current)
                        Spacer()
                        Text("Loaded")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                } else if modelManager.isLoading {
                    HStack {
                        ProgressView(value: modelManager.loadProgress)
                        Text("\(Int(modelManager.loadProgress * 100))%")
                            .font(.caption)
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("No model loaded")
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Section("Available Models") {
                ForEach(modelManager.availableModels) { model in
                    Button {
                        Task { try? await modelManager.loadModel(model.id) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(model.name)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    if model.recommended {
                                        Text("Recommended")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.cyan.opacity(0.3))
                                            .foregroundColor(.cyan)
                                            .cornerRadius(4)
                                    }
                                }
                                Text(model.size)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            if modelManager.currentModelId == model.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "arrow.down.circle")
                                    .foregroundColor(.cyan)
                            }
                        }
                    }
                    .disabled(modelManager.isLoading)
                }
            }
            
            Section {
                Text("Models are downloaded from Hugging Face. First load may take a few minutes depending on your connection.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .navigationTitle("Models")
    }
}

// MARK: - Inference Settings

struct EngineSettingsView: View {
    @StateObject private var engine = ZeroDarkEngine.shared
    
    var body: some View {
        List {
            Section("Power Mode") {
                ForEach(ZeroDarkEngine.InferenceMode.allCases, id: \.self) { mode in
                    Button {
                        engine.currentMode = mode
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(mode.rawValue)
                                    .foregroundColor(.white)
                                Text(modeDescription(mode))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            if engine.currentMode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.cyan)
                            }
                        }
                    }
                }
            }
            
            Section("Statistics") {
                LabeledContent("Total Queries", value: "\(engine.totalQueries)")
                LabeledContent("Avg Latency", value: String(format: "%.1fs", engine.avgLatency))
                LabeledContent("Equivalent Size", value: engine.equivalentModelSize)
            }
            
            Section("Active Techniques") {
                FeatureRow(name: "Speculative Decoding", enabled: true)
                FeatureRow(name: "Self-Rewarding", enabled: true)
                FeatureRow(name: "Tree of Thoughts", enabled: true)
                FeatureRow(name: "ZeroSwarm (12 agents)", enabled: true)
                FeatureRow(name: "RAG Engine", enabled: true)
            }
        }
        .navigationTitle("Inference")
    }
    
    private func modeDescription(_ mode: ZeroDarkEngine.InferenceMode) -> String {
        switch mode {
        case .quick: return "Fast responses, ~8B equivalent"
        case .standard: return "Balanced, ~50B equivalent"
        case .deep: return "Thorough reasoning, ~150B equivalent"
        case .maximum: return "Multi-agent, ~300B+ equivalent"
        case .adaptive: return "Auto-selects based on query"
        }
    }
}

struct FeatureRow: View {
    let name: String
    let enabled: Bool
    
    var body: some View {
        HStack {
            Text(name)
            Spacer()
            Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                .foregroundColor(enabled ? .green : .gray)
        }
    }
}

// MARK: - About

struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    Text("☢️")
                        .font(.system(size: 60))
                    Text("ZeroDark")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Zero cloud. Zero tracking.\nDark mode by default.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            }
            
            Section("Capabilities") {
                AboutRow(icon: "brain", text: "25+ LLM models")
                AboutRow(icon: "waveform", text: "On-device inference")
                AboutRow(icon: "network", text: "Device swarm")
                AboutRow(icon: "person.fill", text: "Voice cloning")
                AboutRow(icon: "memorychip", text: "Infinite memory")
                AboutRow(icon: "lock.shield", text: "100% private")
            }
            
            Section {
                Text("Built with MLX Swift. All processing happens on your device. Your data never leaves.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .navigationTitle("About")
    }
}

struct AboutRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.cyan)
                .frame(width: 30)
            Text(text)
        }
    }
}
