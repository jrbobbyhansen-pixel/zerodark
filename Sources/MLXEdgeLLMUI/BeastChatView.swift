import SwiftUI
import MLXEdgeLLM

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Cross-Platform Colors
extension Color {
    #if os(iOS) || os(visionOS)
    static let systemBackground = Color(uiColor: .systemBackground)
    static let systemGray6 = Color(uiColor: .systemGray6)
    #else
    static let systemBackground = Color(nsColor: .windowBackgroundColor)
    static let systemGray6 = Color(nsColor: .controlBackgroundColor)
    #endif
}

// MARK: - Beast Chat View

/// Full-featured chat view with all Beast Mode capabilities
public struct BeastChatView: View {
    @StateObject private var viewModel = BeastChatViewModel()
    @State private var inputText = ""
    @State private var showModelPicker = false
    @State private var showParamControls = false
    @State private var showSystemPromptPicker = false
    @State private var showExportSheet = false
    @State private var showConversationList = false
    @FocusState private var inputFocused: Bool
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.systemBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Memory warning
                    MemoryWarningBanner()
                        .padding(.horizontal)
                    
                    // Chat messages
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(viewModel.messages) { message in
                                    MessageRow(message: message)
                                        .id(message.id)
                                }
                                
                                // Streaming response
                                if viewModel.isGenerating {
                                    StreamingMessageRow(
                                        text: viewModel.streamingText,
                                        thinking: viewModel.thinkingText
                                    )
                                    .id("streaming")
                                }
                                
                                // Loading indicator
                                if !viewModel.progress.isEmpty {
                                    HStack {
                                        ProgressView()
                                        Text(viewModel.progress)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
                                }
                            }
                            .padding()
                        }
                        .onChange(of: viewModel.streamingText) { _, _ in
                            withAnimation {
                                proxy.scrollTo("streaming", anchor: .bottom)
                            }
                        }
                    }
                    
                    // Performance overlay (when generating)
                    if viewModel.isGenerating || viewModel.lastStats != nil {
                        PerformanceOverlay(
                            stats: viewModel.lastStats,
                            isGenerating: viewModel.isGenerating
                        )
                        .padding(.bottom, 8)
                    }
                    
                    // Input area
                    InputBar(
                        text: $inputText,
                        isGenerating: viewModel.isGenerating,
                        isFocused: $inputFocused,
                        onSend: sendMessage,
                        onStop: viewModel.stopGeneration
                    )
                }
            }
            .navigationTitle(viewModel.activeConversation?.title ?? "New Chat")
            .beastNavBarInline()
            .toolbar { chatToolbarContent }
            .sheet(isPresented: $showModelPicker) {
                BeastModelPicker(selectedModel: $viewModel.selectedModel)
            }
            .sheet(isPresented: $showParamControls) {
                ParameterControlsSheet(params: $viewModel.params)
            }
            .sheet(isPresented: $showSystemPromptPicker) {
                SystemPromptPicker(
                    selectedTemplate: $viewModel.selectedTemplate,
                    customPrompt: $viewModel.customSystemPrompt
                )
            }
            .sheet(isPresented: $showConversationList) {
                BeastConversationList(
                    conversations: viewModel.conversations,
                    activeConversation: viewModel.activeConversation,
                    onSelect: { conv in
                        Task { await viewModel.selectConversation(conv) }
                        showConversationList = false
                    },
                    onDelete: { conv in
                        Task { await viewModel.deleteConversation(conv) }
                    }
                )
            }
            .sheet(isPresented: $showExportSheet) {
                if let conv = viewModel.activeConversation {
                    ExportSheet(
                        conversation: conv,
                        turns: viewModel.turns
                    )
                }
            }
        }
    }
    
    @ToolbarContentBuilder
    private var chatToolbarContent: some ToolbarContent {
        #if os(iOS) || os(visionOS)
        ToolbarItem(placement: .topBarLeading) {
            chatMenuButton
        }
        ToolbarItem(placement: .topBarTrailing) {
            chatToolbarButtons
        }
        #else
        ToolbarItem(placement: .navigation) {
            chatMenuButton
        }
        ToolbarItem(placement: .primaryAction) {
            chatToolbarButtons
        }
        #endif
    }
    
    private var chatMenuButton: some View {
        Menu {
            Button {
                showConversationList = true
            } label: {
                Label("Conversations", systemImage: "list.bullet")
            }
            
            Button {
                Task { await viewModel.newConversation() }
            } label: {
                Label("New Chat", systemImage: "plus")
            }
            
            if viewModel.activeConversation != nil {
                Button {
                    showExportSheet = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
    
    private var chatToolbarButtons: some View {
        HStack(spacing: 12) {
            Button { showModelPicker = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                    Text(shortModelName).font(.caption)
                }
            }
            Button { showParamControls = true } label: {
                Image(systemName: "slider.horizontal.3")
            }
            Button { showSystemPromptPicker = true } label: {
                Image(systemName: "person.text.rectangle")
            }
        }
    }
    
    private var shortModelName: String {
        let name = viewModel.selectedModel.displayName
        // Extract just the model name without size indicators
        return name
            .replacingOccurrences(of: "⚡ ", with: "")
            .replacingOccurrences(of: "🔓 ", with: "")
            .replacingOccurrences(of: "🧠 ", with: "")
            .replacingOccurrences(of: "💻 ", with: "")
            .replacingOccurrences(of: "🔧 ", with: "")
            .components(separatedBy: " ").first ?? name
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        inputFocused = false
        Task {
            await viewModel.send(text)
        }
    }
}

// MARK: - Input Bar

struct InputBar: View {
    @Binding var text: String
    let isGenerating: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onStop: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Text field
            TextField("Message...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color.systemGray6)
                .cornerRadius(20)
                .lineLimit(1...6)
                .focused(isFocused)
                .submitLabel(.send)
                .onSubmit(onSend)
            
            // Send/Stop button
            if isGenerating {
                StopGenerationButton(action: onStop)
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(text.isEmpty ? .gray : .cyan)
                }
                .disabled(text.isEmpty)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Message Row

struct MessageRow: View {
    let message: BeastMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                // AI avatar
                Circle()
                    .fill(LinearGradient(
                        colors: [.cyan, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "cpu")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    )
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Thinking (for reasoning models)
                if let thinking = message.thinking, !thinking.isEmpty {
                    ThinkingView(thinking: thinking)
                }
                
                // Message content
                Text(message.content)
                    .padding(12)
                    .background(message.role == .user 
                                ? Color.cyan.opacity(0.2) 
                                : Color.systemGray6)
                    .cornerRadius(16)
                    .contextMenu {
                        Button {
                            #if os(iOS)
                            UIPasteboard.general.string = message.content
                            #else
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.content, forType: .string)
                            #endif
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                
                // Stats (if available)
                if let stats = message.stats {
                    Text(stats.summary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .user {
                // User avatar
                Circle()
                    .fill(Color.orange)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    )
            }
        }
    }
}

// MARK: - Streaming Message Row

struct StreamingMessageRow: View {
    let text: String
    let thinking: String?
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // AI avatar with pulse
            Circle()
                .fill(LinearGradient(
                    colors: [.cyan, .blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "cpu")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                )
                .modifier(PulseModifier())
            
            VStack(alignment: .leading, spacing: 4) {
                // Thinking
                if let thinking, !thinking.isEmpty {
                    ThinkingView(thinking: thinking)
                }
                
                // Streaming text
                HStack {
                    Text(text.isEmpty ? "..." : text)
                    Text("▋")
                        .foregroundColor(.cyan)
                        .modifier(BlinkModifier())
                }
                .padding(12)
                .background(Color.systemGray6)
                .cornerRadius(16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Animation Modifiers

struct PulseModifier: ViewModifier {
    @State private var isPulsing = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

struct BlinkModifier: ViewModifier {
    @State private var isVisible = true
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isVisible)
            .onAppear { isVisible = false }
    }
}

// MARK: - Beast Message Model

struct BeastMessage: Identifiable {
    let id: UUID
    let role: Turn.Role
    let content: String
    let thinking: String?
    let stats: GenerationStats?
    
    init(
        id: UUID = UUID(),
        role: Turn.Role,
        content: String,
        thinking: String? = nil,
        stats: GenerationStats? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thinking = thinking
        self.stats = stats
    }
}

// MARK: - Beast Chat ViewModel

@MainActor
final class BeastChatViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var activeConversation: Conversation?
    @Published var messages: [BeastMessage] = []
    @Published var turns: [Turn] = []
    @Published var streamingText = ""
    @Published var thinkingText: String?
    @Published var progress = ""
    @Published var isGenerating = false
    @Published var lastStats: GenerationStats?
    
    @Published var selectedModel: Model = .qwen3_8b
    @Published var params: BeastModeParams = .balanced
    @Published var selectedTemplate: SystemPromptTemplate = .assistant
    @Published var customSystemPrompt = ""
    
    private var engine: BeastEngine?
    private let store = ConversationStore.shared
    
    init() {
        Task { await loadConversations() }
    }
    
    // MARK: - Conversation Management
    
    func loadConversations() async {
        conversations = (try? await store.allConversations()) ?? []
    }
    
    func newConversation() async {
        activeConversation = nil
        messages = []
        turns = []
        streamingText = ""
        lastStats = nil
    }
    
    func selectConversation(_ conv: Conversation) async {
        activeConversation = conv
        turns = (try? await store.turns(for: conv.id)) ?? []
        messages = turns
            .filter { $0.role != .system }
            .map { BeastMessage(id: $0.id, role: $0.role, content: $0.content) }
    }
    
    func deleteConversation(_ conv: Conversation) async {
        try? await store.deleteConversation(id: conv.id)
        conversations.removeAll { $0.id == conv.id }
        if activeConversation?.id == conv.id {
            await newConversation()
        }
    }
    
    // MARK: - Generation
    
    func send(_ prompt: String) async {
        // Create conversation if needed
        if activeConversation == nil {
            guard let conv = try? await store.createConversation(model: selectedModel) else { return }
            activeConversation = conv
            conversations.insert(conv, at: 0)
        }
        
        guard let convID = activeConversation?.id else { return }
        
        // Add user message
        let userTurn = Turn(conversationID: convID, role: .user, content: prompt)
        try? await store.appendTurn(userTurn)
        messages.append(BeastMessage(role: .user, content: prompt))
        
        // Start generation
        isGenerating = true
        streamingText = ""
        thinkingText = nil
        
        do {
            // Load engine if needed or model changed
            if engine == nil || engine?.model != selectedModel {
                progress = "Loading \(selectedModel.displayName)..."
                engine = BeastEngine(
                    model: selectedModel,
                    params: params,
                    systemPrompt: currentSystemPrompt
                )
                try await engine?.load(onProgress: { [weak self] p in
                    self?.progress = p
                })
            }
            
            // Update params
            engine?.setParams(params)
            engine?.setSystemPrompt(currentSystemPrompt)
            
            progress = ""
            
            // Build history
            let history = turns.filter { $0.role != .system }.map { turn in
                ["role": turn.role.rawValue, "content": turn.content]
            }
            
            var fullResponse = ""
            
            _ = try await engine?.generate(
                prompt: prompt,
                history: history,
                onToken: { [weak self] partial in
                    // Parse thinking tags for reasoning models
                    let (thinking, answer) = ThinkingParser.parse(partial)
                    self?.thinkingText = thinking
                    self?.streamingText = answer
                    fullResponse = partial
                },
                onStats: { [weak self] stats in
                    self?.lastStats = stats
                }
            )
            
            // Parse final response
            let (thinking, answer) = ThinkingParser.parse(fullResponse)
            
            // Save assistant turn
            let assistantTurn = Turn(conversationID: convID, role: .assistant, content: answer)
            try? await store.appendTurn(assistantTurn)
            turns.append(assistantTurn)
            
            messages.append(BeastMessage(
                role: .assistant,
                content: answer,
                thinking: thinking,
                stats: lastStats
            ))
            
            streamingText = ""
            thinkingText = nil
            
            // Auto-title after first exchange
            if messages.count == 2 {
                await autoTitle(prompt: prompt)
            }
            
        } catch {
            messages.append(BeastMessage(
                role: .assistant,
                content: "❌ \(error.localizedDescription)"
            ))
        }
        
        isGenerating = false
        progress = ""
    }
    
    func stopGeneration() {
        engine?.stop()
    }
    
    // MARK: - Helpers
    
    private var currentSystemPrompt: String? {
        if selectedTemplate == .custom {
            return customSystemPrompt.isEmpty ? nil : customSystemPrompt
        }
        return selectedTemplate.prompt
    }
    
    private func autoTitle(prompt: String) async {
        guard let convID = activeConversation?.id else { return }
        
        // Generate a short title from the first prompt
        let title = String(prompt.prefix(50)).trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = title.count < prompt.count ? title + "..." : title
        
        try? await store.updateTitle(finalTitle, for: convID)
        activeConversation?.title = finalTitle
        await loadConversations()
    }
}

// MARK: - Beast Conversation List

struct BeastConversationList: View {
    let conversations: [Conversation]
    let activeConversation: Conversation?
    let onSelect: (Conversation) -> Void
    let onDelete: (Conversation) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                if conversations.isEmpty {
                    ContentUnavailableView(
                        "No conversations",
                        systemImage: "bubble.left",
                        description: Text("Start a new chat to begin.")
                    )
                } else {
                    ForEach(conversations) { conv in
                        Button {
                            onSelect(conv)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(conv.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    
                                    HStack(spacing: 4) {
                                        Text(conv.model.components(separatedBy: "/").last ?? conv.model)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text("·")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text("\(conv.turnCount) turns")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                if activeConversation?.id == conv.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.cyan)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                onDelete(conv)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Conversations")
            .beastNavBarInline()
            .beastToolbarDone(dismiss)
        }
    }
}

// MARK: - Preview

#Preview {
    BeastChatView()
}
