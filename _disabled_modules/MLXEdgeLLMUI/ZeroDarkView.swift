import SwiftUI
import MLXEdgeLLM

// MARK: - Zero Dark Main View

/// The unified Zero Dark AI interface
public struct ZeroDarkView: View {
    @StateObject private var viewModel = ZeroDarkViewModel()
    @State private var selectedTab = 0
    
    public init() {}
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            // Chat Tab
            BeastChatView()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(0)
            
            // Vision Tab
            BeastVisionView()
                .tabItem {
                    Label("Vision", systemImage: "eye")
                }
                .tag(1)
            
            // Intelligence Tab
            IntelligenceView()
                .tabItem {
                    Label("Intelligence", systemImage: "brain")
                }
                .tag(2)
            
            // Settings Tab
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
        }
        .tint(.cyan)
    }
}

// MARK: - Intelligence View

struct IntelligenceView: View {
    @ObservedObject var router = ModelRouter.shared
    @ObservedObject var monitor = SystemMonitor.shared
    @ObservedObject var scorer = QualityScorer.shared
    
    var body: some View {
        NavigationStack {
            List {
                // Device Status
                Section {
                    HStack {
                        Label("Device Tier", systemImage: "cpu")
                        Spacer()
                        Text(router.deviceTier.displayName)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Label("Memory", systemImage: "memorychip")
                        Spacer()
                        Text("\(monitor.memoryAvailableMB) MB available")
                            .foregroundColor(memoryColor)
                    }
                    
                    HStack {
                        Label("Models Available", systemImage: "square.stack.3d.up")
                        Spacer()
                        Text("\(router.availableModels.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    #if os(iOS)
                    HStack {
                        Label("Thermal", systemImage: "thermometer")
                        Spacer()
                        Text("\(monitor.thermalState.emoji) \(monitor.thermalState.rawValue)")
                    }
                    #endif
                } header: {
                    Text("System Status")
                }
                
                // Auto-Routing
                Section {
                    Toggle("Auto-Routing", isOn: $router.autoRouting)
                    Toggle("Prefer Uncensored", isOn: $router.preferUncensored)
                } header: {
                    Text("Routing")
                } footer: {
                    Text("Auto-routing selects the best model for each task automatically.")
                }
                
                // Available Models
                Section {
                    ForEach(router.availableModels, id: \.rawValue) { model in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(model.displayName)
                                    .font(.subheadline)
                                Text(model.modelDescription)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text("\(model.approximateSizeMB / 1000).\((model.approximateSizeMB % 1000) / 100)GB")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Available Models")
                }
                
                // Quality Stats
                Section {
                    let stats = scorer.feedbackStats
                    
                    HStack {
                        Label("Total Ratings", systemImage: "star")
                        Spacer()
                        Text("\(stats.total)")
                            .foregroundColor(.secondary)
                    }
                    
                    if stats.total > 0 {
                        HStack {
                            Label("Average Rating", systemImage: "chart.bar")
                            Spacer()
                            Text(String(format: "%.1f / 5.0", stats.avgRating))
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Quality Feedback")
                }
            }
            .navigationTitle("Intelligence")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
    }
    
    private var memoryColor: Color {
        switch monitor.memoryPressure {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .orange
        case .terminal: return .red
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var safety = SafetyFilter.shared
    @State private var showingMemoryInfo = false
    
    var body: some View {
        NavigationStack {
            List {
                // Safety Level
                Section {
                    Picker("Safety Level", selection: $safety.level) {
                        ForEach(SafetyFilter.Level.allCases, id: \.rawValue) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                } header: {
                    Text("Content Filtering")
                } footer: {
                    Text(safety.level.description)
                }
                
                // Export/Import
                Section {
                    Button {
                        // Export conversations
                    } label: {
                        Label("Export All Conversations", systemImage: "square.and.arrow.up")
                    }
                    
                    Button {
                        // Clear memory
                    } label: {
                        Label("Clear Memory", systemImage: "trash")
                    }
                    .foregroundColor(.red)
                } header: {
                    Text("Data")
                }
                
                // About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://github.com/bobbyhansenjr/zerodark")!) {
                        HStack {
                            Text("GitHub")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("About Zero Dark")
                } footer: {
                    Text("Open-source on-device AI. Private. Uncensored. Intelligent.")
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
    }
}

// MARK: - ViewModel

@MainActor
class ZeroDarkViewModel: ObservableObject {
    let ai = ZeroDarkAI.shared
    
    init() {
        // Initialize on launch
    }
}

// MARK: - Preview

#Preview {
    ZeroDarkView()
}
