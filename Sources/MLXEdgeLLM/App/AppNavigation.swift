//
//  AppNavigation.swift
//  ZeroDark
//
//  Task-centric navigation. Users don't think in "memory" or "models" — 
//  they think in "what can I do?"
//

import SwiftUI

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: MAIN APP STRUCTURE
// MARK: ═══════════════════════════════════════════════════════════════════

@main
struct ZeroDarkApp: App {
    @StateObject private var appState = AppState.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var selectedTab: AppTab = .chat
    @Published var isOnboarded = false
    @Published var hasActiveConversation = false
    @Published var unreadRecallCount = 0
    
    // Quick access to engines
    let engine = ZeroDarkEngine.shared
    let memory = InfiniteMemorySystem.shared
}

// MARK: - Tab Definition

enum AppTab: String, CaseIterable {
    case home = "Home"
    case chat = "Chat"
    case recall = "Recall"
    case library = "Library"
    case more = "More"
    
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .recall: return "magnifyingglass"
        case .library: return "books.vertical.fill"
        case .more: return "ellipsis.circle.fill"
        }
    }
    
    var label: String {
        rawValue
    }
}

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: CONTENT VIEW (Main Container)
// MARK: ═══════════════════════════════════════════════════════════════════

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        TabView(selection: $appState.selectedTab) {
            HomeView()
                .tabItem {
                    Label(AppTab.home.label, systemImage: AppTab.home.icon)
                }
                .tag(AppTab.home)
            
            ChatView()
                .tabItem {
                    Label(AppTab.chat.label, systemImage: AppTab.chat.icon)
                }
                .tag(AppTab.chat)
            
            RecallView()
                .tabItem {
                    Label(AppTab.recall.label, systemImage: AppTab.recall.icon)
                }
                .tag(AppTab.recall)
            
            LibraryView()
                .tabItem {
                    Label(AppTab.library.label, systemImage: AppTab.library.icon)
                }
                .tag(AppTab.library)
            
            MoreView()
                .tabItem {
                    Label(AppTab.more.label, systemImage: AppTab.more.icon)
                }
                .tag(AppTab.more)
        }
        .tint(.cyan)
    }
}

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: 1. HOME TAB
// MARK: ═══════════════════════════════════════════════════════════════════

/// First thing you see. Quick actions, status, recent activity.
struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingQuickAction = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Hero: AI Status
                    AIStatusCard()
                    
                    // Quick Actions
                    QuickActionsGrid()
                    
                    // Recent Conversations
                    RecentConversationsSection()
                    
                    // Memory Insights
                    MemoryInsightsCard()
                    
                    // Learning Progress
                    LearningProgressCard()
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("ZeroDark")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        appState.selectedTab = .chat
                    } label: {
                        Image(systemName: "plus.bubble.fill")
                            .foregroundColor(.cyan)
                    }
                }
            }
        }
    }
}

struct AIStatusCard: View {
    @StateObject private var engine = ZeroDarkEngine.shared
    
    var body: some View {
        VStack(spacing: 16) {
            // Morphing blob placeholder
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.cyan.opacity(0.6), .cyan.opacity(0.1)],
                        center: .center,
                        startRadius: 20,
                        endRadius: 60
                    )
                )
                .frame(width: 120, height: 120)
                .overlay(
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                )
            
            Text(engine.isProcessing ? "Thinking..." : "Ready")
                .font(.headline)
                .foregroundColor(.white)
            
            HStack(spacing: 20) {
                StatusPill(label: "Mode", value: engine.currentMode.rawValue)
                StatusPill(label: "Power", value: engine.equivalentModelSize)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(20)
    }
}

struct StatusPill: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.cyan)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(12)
    }
}

struct QuickActionsGrid: View {
    @EnvironmentObject var appState: AppState
    
    let actions: [(icon: String, title: String, color: Color)] = [
        ("mic.fill", "Voice", .cyan),
        ("camera.fill", "Vision", .purple),
        ("doc.text.magnifyingglass", "Analyze", .orange),
        ("wand.and.stars", "Create", .pink)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .foregroundColor(.white)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(actions, id: \.title) { action in
                    QuickActionButton(
                        icon: action.icon,
                        title: action.title,
                        color: action.color
                    ) {
                        appState.selectedTab = .chat
                    }
                }
            }
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

struct RecentConversationsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button("See All") {}
                    .font(.caption)
                    .foregroundColor(.cyan)
            }
            
            VStack(spacing: 8) {
                RecentConversationRow(
                    title: "ZeroDark Architecture",
                    preview: "Let me explain the module structure...",
                    time: "2m ago"
                )
                RecentConversationRow(
                    title: "App Navigation",
                    preview: "Task-centric tabs are better...",
                    time: "15m ago"
                )
                RecentConversationRow(
                    title: "Infinite Memory",
                    preview: "95% token savings achieved...",
                    time: "1h ago"
                )
            }
        }
    }
}

struct RecentConversationRow: View {
    let title: String
    let preview: String
    let time: String
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.cyan.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "bubble.left.fill")
                        .foregroundColor(.cyan)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                Text(preview)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text(time)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

struct MemoryInsightsCard: View {
    @StateObject private var memory = InfiniteMemorySystem.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain")
                    .foregroundColor(.cyan)
                Text("Memory")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            HStack(spacing: 16) {
                MemoryStat(label: "Facts", value: "\(memory.semanticCount)")
                MemoryStat(label: "Episodes", value: "\(memory.episodicCount)")
                MemoryStat(label: "Rules", value: "\(memory.proceduralCount)")
            }
            
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.green)
                Text("\(memory.totalTokensSaved) tokens saved")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
    }
}

struct MemoryStat: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.cyan)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct LearningProgressCard: View {
    @StateObject private var learning = SelfRewardingEngine.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.green)
                Text("Learning")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quality Score")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(learning.avgScore, specifier: "%.1f")/1.0")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("LoRA Version")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("v\(learning.loraVersion)")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.cyan)
                }
            }
            
            ProgressView(value: learning.avgScore, total: 1.0)
                .tint(.green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
    }
}

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: 2. CHAT TAB
// MARK: ═══════════════════════════════════════════════════════════════════

/// Main conversation interface. Memory auto-injected.
struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                            
                            if viewModel.isGenerating {
                                ThinkingIndicator()
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        if let lastMessage = viewModel.messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Input
                ChatInputBar(
                    text: $viewModel.inputText,
                    isLoading: viewModel.isGenerating,
                    onSend: viewModel.send
                )
                .focused($isInputFocused)
            }
            .background(Color.black)
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ModeSelector(selectedMode: $viewModel.inferenceMode)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New Chat", systemImage: "plus") {
                            viewModel.newChat()
                        }
                        Button("Save Chat", systemImage: "square.and.arrow.down") {
                            viewModel.saveChat()
                        }
                        Divider()
                        Button("Voice Input", systemImage: "mic") {}
                        Button("Attach Image", systemImage: "photo") {}
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
}

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published var isGenerating = false
    @Published var inferenceMode: ZeroDarkEngine.InferenceMode = .standard
    
    private let engine = ZeroDarkEngine.shared
    
    func send() {
        guard !inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        let userMessage = ChatMessage(role: .user, content: inputText)
        messages.append(userMessage)
        
        let prompt = inputText
        inputText = ""
        isGenerating = true
        
        Task {
            let result = await engine.generateWithMemory(prompt: prompt, mode: inferenceMode)
            
            let assistantMessage = ChatMessage(
                role: .assistant,
                content: result.response,
                metadata: .init(
                    mode: result.mode,
                    techniques: result.techniquesUsed,
                    confidence: result.confidence
                )
            )
            messages.append(assistantMessage)
            isGenerating = false
        }
    }
    
    func newChat() {
        messages.removeAll()
    }
    
    func saveChat() {
        // Would save to library
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp = Date()
    var metadata: Metadata?
    
    enum Role {
        case user, assistant, system
    }
    
    struct Metadata {
        let mode: ZeroDarkEngine.InferenceMode
        let techniques: [String]
        let confidence: Double
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    .background(message.role == .user ? Color.cyan : Color.gray.opacity(0.2))
                    .foregroundColor(.white)
                    .cornerRadius(16)
                
                if let metadata = message.metadata {
                    HStack(spacing: 8) {
                        Text(metadata.mode.rawValue)
                        Text("•")
                        Text("\(Int(metadata.confidence * 100))%")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
            }
            
            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}

struct ThinkingIndicator: View {
    @State private var dotCount = 0
    
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 8, height: 8)
                        .opacity(dotCount > index ? 1 : 0.3)
                }
            }
            .padding(12)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(16)
            
            Spacer()
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
                dotCount = (dotCount + 1) % 4
            }
        }
    }
}

struct ChatInputBar: View {
    @Binding var text: String
    let isLoading: Bool
    let onSend: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            TextField("Message", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(20)
                .lineLimit(1...5)
            
            Button(action: onSend) {
                Image(systemName: isLoading ? "stop.fill" : "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(text.isEmpty && !isLoading ? .gray : .cyan)
            }
            .disabled(text.isEmpty && !isLoading)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black)
    }
}

struct ModeSelector: View {
    @Binding var selectedMode: ZeroDarkEngine.InferenceMode
    
    var body: some View {
        Menu {
            ForEach(ZeroDarkEngine.InferenceMode.allCases, id: \.self) { mode in
                Button {
                    selectedMode = mode
                } label: {
                    HStack {
                        Text(mode.rawValue)
                        if selectedMode == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                Text(selectedMode.rawValue)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.cyan.opacity(0.2))
            .cornerRadius(12)
        }
    }
}

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: 3. RECALL TAB
// MARK: ═══════════════════════════════════════════════════════════════════

/// Search everything you've ever discussed. Your second brain.
struct RecallView: View {
    @State private var searchText = ""
    @State private var searchResults: [RecallResult] = []
    @State private var isSearching = false
    @State private var selectedFilter: RecallFilter = .all
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search your memory...", text: $searchText)
                        .textFieldStyle(.plain)
                        .onSubmit { search() }
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            searchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(12)
                .padding()
                
                // Filters
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(RecallFilter.allCases, id: \.self) { filter in
                            FilterChip(
                                title: filter.rawValue,
                                isSelected: selectedFilter == filter
                            ) {
                                selectedFilter = filter
                                if !searchText.isEmpty { search() }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Results
                if isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchResults.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("Try different keywords")
                    )
                } else if searchResults.isEmpty {
                    // Suggestions when empty
                    VStack(spacing: 24) {
                        Text("Try searching for...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 12) {
                            SuggestionRow(text: "What did we decide about...")
                            SuggestionRow(text: "Last week's conversation about...")
                            SuggestionRow(text: "The project where we...")
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    List(searchResults) { result in
                        RecallResultRow(result: result)
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color.black)
            .navigationTitle("Recall")
        }
    }
    
    func search() {
        guard !searchText.isEmpty else { return }
        isSearching = true
        
        Task {
            let memory = InfiniteMemorySystem.shared
            let context = await memory.retrieveContext(for: searchText, limit: 20)
            
            var results: [RecallResult] = []
            
            // Add facts
            for fact in context.facts {
                results.append(RecallResult(
                    type: .fact,
                    title: fact.category.capitalized,
                    content: fact.fact,
                    confidence: Double(fact.confidence),
                    date: fact.createdAt
                ))
            }
            
            // Add episodes
            for episode in context.episodes {
                results.append(RecallResult(
                    type: .episode,
                    title: episode.topics.first ?? "Conversation",
                    content: episode.summary,
                    confidence: Double(episode.importance),
                    date: episode.timestamp
                ))
            }
            
            // Add rules
            for rule in context.rules {
                results.append(RecallResult(
                    type: .rule,
                    title: "Rule",
                    content: "IF \(rule.trigger) THEN \(rule.action)",
                    confidence: Double(rule.successCount) / Double(max(1, rule.successCount + rule.failureCount)),
                    date: rule.createdAt
                ))
            }
            
            // Filter
            if selectedFilter != .all {
                results = results.filter { $0.type.rawValue == selectedFilter.rawValue }
            }
            
            searchResults = results.sorted { $0.confidence > $1.confidence }
            isSearching = false
        }
    }
}

enum RecallFilter: String, CaseIterable {
    case all = "All"
    case fact = "Facts"
    case episode = "Conversations"
    case rule = "Rules"
}

struct RecallResult: Identifiable {
    let id = UUID()
    let type: ResultType
    let title: String
    let content: String
    let confidence: Double
    let date: Date
    
    enum ResultType: String {
        case fact, episode, rule
        
        var icon: String {
            switch self {
            case .fact: return "lightbulb.fill"
            case .episode: return "bubble.left.and.bubble.right.fill"
            case .rule: return "arrow.triangle.branch"
            }
        }
        
        var color: Color {
            switch self {
            case .fact: return .yellow
            case .episode: return .cyan
            case .rule: return .purple
            }
        }
    }
}

struct RecallResultRow: View {
    let result: RecallResult
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: result.type.icon)
                .foregroundColor(result.type.color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(result.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text(result.date, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Text(result.content)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                
                HStack {
                    Text("\(Int(result.confidence * 100))% confidence")
                        .font(.caption2)
                        .foregroundColor(result.type.color)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.cyan : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .black : .white)
                .cornerRadius(16)
        }
    }
}

struct SuggestionRow: View {
    let text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            Text(text)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: 4. LIBRARY TAB
// MARK: ═══════════════════════════════════════════════════════════════════

/// Your stuff: saved chats, exports, documents, knowledge base.
struct LibraryView: View {
    @State private var selectedSection: LibrarySection = .chats
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Section picker
                Picker("Section", selection: $selectedSection) {
                    ForEach(LibrarySection.allCases, id: \.self) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content
                switch selectedSection {
                case .chats:
                    SavedChatsView()
                case .documents:
                    DocumentsView()
                case .knowledge:
                    KnowledgeBaseView()
                }
            }
            .background(Color.black)
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // Import document
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

enum LibrarySection: String, CaseIterable {
    case chats = "Chats"
    case documents = "Documents"
    case knowledge = "Knowledge"
}

struct SavedChatsView: View {
    var body: some View {
        List {
            ForEach(0..<5) { index in
                HStack {
                    VStack(alignment: .leading) {
                        Text("Chat \(index + 1)")
                            .font(.headline)
                        Text("Last message preview...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("Yesterday")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.plain)
    }
}

struct DocumentsView: View {
    var body: some View {
        List {
            ForEach(0..<3) { index in
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundColor(.cyan)
                    VStack(alignment: .leading) {
                        Text("Document \(index + 1).pdf")
                            .font(.subheadline)
                        Text("Added to knowledge base")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

struct KnowledgeBaseView: View {
    @StateObject private var rag = LocalRAGEngine.shared
    
    var body: some View {
        List {
            Section {
                HStack {
                    Text("Documents")
                    Spacer()
                    Text("\(rag.documentCount)")
                        .foregroundColor(.cyan)
                }
                HStack {
                    Text("Chunks")
                    Spacer()
                    Text("\(rag.chunkCount)")
                        .foregroundColor(.cyan)
                }
            }
            
            Section("Recent Queries") {
                ForEach(rag.lastQueryResults) { result in
                    VStack(alignment: .leading) {
                        Text(result.title)
                            .font(.subheadline)
                        Text(result.content)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: 5. MORE TAB
// MARK: ═══════════════════════════════════════════════════════════════════

/// Settings, models, tools, privacy — everything else.
struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ModelsSettingsView()
                    } label: {
                        SettingsRow(icon: "cpu", title: "Models", color: .cyan)
                    }
                    
                    NavigationLink {
                        ToolsSettingsView()
                    } label: {
                        SettingsRow(icon: "wrench.and.screwdriver", title: "Tools & Capabilities", color: .orange)
                    }
                    
                    NavigationLink {
                        ZeroDarkSettingsView()
                    } label: {
                        SettingsRow(icon: "bolt.fill", title: "Inference Engine", color: .yellow)
                    }
                }
                
                Section {
                    NavigationLink {
                        LearnFromEverythingView()
                    } label: {
                        SettingsRow(icon: "brain", title: "Learning Sources", color: .purple)
                    }
                    
                    NavigationLink {
                        MemoryDashboardView()
                    } label: {
                        SettingsRow(icon: "memorychip", title: "Memory", color: .green)
                    }
                }
                
                Section {
                    NavigationLink {
                        PrivacySettingsView()
                    } label: {
                        SettingsRow(icon: "lock.shield", title: "Privacy", color: .blue)
                    }
                    
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        SettingsRow(icon: "paintbrush", title: "Appearance", color: .pink)
                    }
                }
                
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        SettingsRow(icon: "info.circle", title: "About ZeroDark", color: .gray)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("More")
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(title)
        }
    }
}

// Placeholder views
struct ModelsSettingsView: View {
    var body: some View {
        Text("Models Settings")
            .navigationTitle("Models")
    }
}

struct ToolsSettingsView: View {
    var body: some View {
        Text("Tools Settings")
            .navigationTitle("Tools")
    }
}

struct PrivacySettingsView: View {
    var body: some View {
        Text("Privacy Settings")
            .navigationTitle("Privacy")
    }
}

struct AppearanceSettingsView: View {
    var body: some View {
        Text("Appearance Settings")
            .navigationTitle("Appearance")
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundColor(.cyan)
            
            Text("ZeroDark")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Version 1.0.0")
                .foregroundColor(.secondary)
            
            Text("Zero cloud. Zero tracking.\nDark mode by default.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text("MIT License • Open Source")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .navigationTitle("About")
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
        .preferredColorScheme(.dark)
}
