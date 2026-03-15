// Widgets.swift
// Home screen widgets, lock screen, Dynamic Island
// ABSURD MODE

import Foundation
import SwiftUI

#if canImport(WidgetKit)
import WidgetKit

// MARK: - Widget Data Provider

public struct ZeroDarkWidgetData: Sendable {
    public let agentName: String
    public let agentEmoji: String
    public let lastInteraction: Date?
    public let pendingSuggestions: Int
    public let quickStats: QuickStats
    
    public struct QuickStats: Sendable {
        public let memoriesCount: Int
        public let routinesRun: Int
        public let tasksCompleted: Int
    }
    
    public static var placeholder: ZeroDarkWidgetData {
        ZeroDarkWidgetData(
            agentName: "Zero Dark",
            agentEmoji: "🤖",
            lastInteraction: Date(),
            pendingSuggestions: 3,
            quickStats: QuickStats(memoriesCount: 42, routinesRun: 7, tasksCompleted: 15)
        )
    }
}

// MARK: - Widget Provider

public actor WidgetDataProvider {
    
    public static let shared = WidgetDataProvider()
    
    private init() {}
    
    public func getCurrentData() async -> ZeroDarkWidgetData {
        let identity = await AgentIdentity.shared.getIdentity()
        let memoryStats = await PersistentMemory.shared.getStats()
        let suggestions = await ProactiveIntelligence.shared.generateSuggestions()
        
        return ZeroDarkWidgetData(
            agentName: identity.name,
            agentEmoji: identity.avatarEmoji,
            lastInteraction: Date(),
            pendingSuggestions: suggestions.count,
            quickStats: ZeroDarkWidgetData.QuickStats(
                memoriesCount: memoryStats.totalMemories,
                routinesRun: 0,  // Would track this
                tasksCompleted: 0
            )
        )
    }
    
    /// Trigger widget refresh
    public func refreshWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

#endif

// MARK: - Widget Views (for use in WidgetKit extension)

public struct SmallWidgetView: View {
    public let data: ZeroDarkWidgetData
    
    public init(data: ZeroDarkWidgetData) {
        self.data = data
    }
    
    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color.purple.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(data.agentEmoji)
                        .font(.title)
                    Text(data.agentName)
                        .font(.headline)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                if data.pendingSuggestions > 0 {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(.cyan)
                        Text("\(data.pendingSuggestions) suggestions")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                Text("Tap to chat")
                    .font(.caption2)
                    .foregroundColor(.cyan)
            }
            .padding()
        }
    }
}

public struct MediumWidgetView: View {
    public let data: ZeroDarkWidgetData
    
    public init(data: ZeroDarkWidgetData) {
        self.data = data
    }
    
    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color.purple.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            HStack {
                // Left side - Agent info
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(data.agentEmoji)
                            .font(.largeTitle)
                        VStack(alignment: .leading) {
                            Text(data.agentName)
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Ready to help")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                    
                    if data.pendingSuggestions > 0 {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(.cyan)
                            Text("\(data.pendingSuggestions) suggestions")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                    }
                }
                
                Spacer()
                
                // Right side - Quick stats
                VStack(alignment: .trailing, spacing: 12) {
                    StatRow(icon: "brain", value: "\(data.quickStats.memoriesCount)", label: "memories")
                    StatRow(icon: "bolt", value: "\(data.quickStats.routinesRun)", label: "routines")
                    StatRow(icon: "checkmark.circle", value: "\(data.quickStats.tasksCompleted)", label: "tasks")
                }
            }
            .padding()
        }
    }
}

public struct LargeWidgetView: View {
    public let data: ZeroDarkWidgetData
    public let recentActivity: [String]
    
    public init(data: ZeroDarkWidgetData, recentActivity: [String] = []) {
        self.data = data
        self.recentActivity = recentActivity
    }
    
    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color.purple.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Text(data.agentEmoji)
                        .font(.system(size: 50))
                    VStack(alignment: .leading) {
                        Text(data.agentName)
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Text("Your AI Assistant")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                }
                
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                // Quick actions
                HStack(spacing: 12) {
                    QuickActionButton(icon: "mic.fill", label: "Voice")
                    QuickActionButton(icon: "text.bubble", label: "Chat")
                    QuickActionButton(icon: "bolt.fill", label: "Routine")
                    QuickActionButton(icon: "sparkles", label: "Suggest")
                }
                
                // Stats
                HStack(spacing: 20) {
                    StatBox(value: "\(data.quickStats.memoriesCount)", label: "Memories", icon: "brain")
                    StatBox(value: "\(data.quickStats.routinesRun)", label: "Routines", icon: "bolt")
                    StatBox(value: "\(data.quickStats.tasksCompleted)", label: "Tasks", icon: "checkmark.circle")
                }
                
                Spacer()
                
                // Recent activity
                if !recentActivity.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent Activity")
                            .font(.caption)
                            .foregroundColor(.gray)
                        ForEach(recentActivity.prefix(3), id: \.self) { activity in
                            Text("• \(activity)")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Lock Screen Widgets

public struct LockScreenWidgetView: View {
    public let data: ZeroDarkWidgetData
    
    public init(data: ZeroDarkWidgetData) {
        self.data = data
    }
    
    public var body: some View {
        HStack {
            Text(data.agentEmoji)
            Text(data.pendingSuggestions > 0 ? "\(data.pendingSuggestions)" : "✓")
                .fontWeight(.bold)
        }
    }
}

// MARK: - Helper Views

struct StatRow: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.cyan)
            Text(value)
                .font(.caption.bold())
                .foregroundColor(.white)
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.cyan)
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.1))
        .cornerRadius(8)
    }
}

struct StatBox: View {
    let value: String
    let label: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(.cyan)
            Text(value)
                .font(.title3.bold())
                .foregroundColor(.white)
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Live Activities

#if os(iOS)
import ActivityKit

public struct ZeroDarkLiveActivity {
    
    public struct Attributes: ActivityAttributes {
        public struct ContentState: Codable, Hashable {
            public let status: String
            public let progress: Double
            public let currentStep: String
        }
        
        public let taskName: String
        public let startTime: Date
    }
    
    /// Start a live activity for a running task
    public static func start(taskName: String) async throws -> Activity<Attributes>? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return nil
        }
        
        let attributes = Attributes(taskName: taskName, startTime: Date())
        let state = Attributes.ContentState(status: "Running", progress: 0, currentStep: "Starting...")
        
        return try Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: nil)
        )
    }
    
    /// Update live activity progress
    public static func update(_ activity: Activity<Attributes>, progress: Double, step: String) async {
        let state = Attributes.ContentState(status: "Running", progress: progress, currentStep: step)
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }
    
    /// End the live activity
    public static func end(_ activity: Activity<Attributes>, success: Bool) async {
        let state = Attributes.ContentState(
            status: success ? "Complete" : "Failed",
            progress: 1.0,
            currentStep: success ? "Done!" : "Error"
        )
        await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(.now + 5))
    }
}
#endif
