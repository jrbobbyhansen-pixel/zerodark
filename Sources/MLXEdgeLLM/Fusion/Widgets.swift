// Widgets.swift — Home Screen & Lock Screen Widgets

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Widget Entry

struct ZeroDarkEntry: TimelineEntry {
    let date: Date
    let status: SystemStatus
    let lastQuery: String?
    let meshPeerCount: Int
    let memoryCount: Int
}

struct SystemStatus {
    var modelLoaded: Bool
    var modelName: String
    var isProcessing: Bool
    var batteryOptimized: Bool
    
    static var placeholder: SystemStatus {
        SystemStatus(
            modelLoaded: true,
            modelName: "Qwen3 8B",
            isProcessing: false,
            batteryOptimized: true
        )
    }
}

// MARK: - Timeline Provider

struct ZeroDarkTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> ZeroDarkEntry {
        ZeroDarkEntry(
            date: Date(),
            status: .placeholder,
            lastQuery: nil,
            meshPeerCount: 0,
            memoryCount: 0
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (ZeroDarkEntry) -> Void) {
        Task { @MainActor in
            let meshPeerCount = MeshService.shared.peers.count

            let entry = ZeroDarkEntry(
                date: Date(),
                status: .placeholder,
                lastQuery: "Tactical System Ready",
                meshPeerCount: meshPeerCount,
                memoryCount: 0
            )
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ZeroDarkEntry>) -> Void) {
        Task { @MainActor in
            // Fetch actual status with real data (LLM removed - tactical only)
            let meshPeerCount = MeshService.shared.peers.count

            let entry = ZeroDarkEntry(
                date: Date(),
                status: SystemStatus(
                    modelLoaded: true,
                    modelName: "ZeroDark Tactical",
                    isProcessing: false,
                    batteryOptimized: true
                ),
                lastQuery: nil,
                meshPeerCount: meshPeerCount,
                memoryCount: 0
            )

            // Update every 15 minutes
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }
}

// MARK: - Small Widget (Status)

struct ZeroDarkSmallWidget: View {
    var entry: ZeroDarkEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "brain")
                    .font(.title2)
                    .foregroundColor(ZDDesign.forestGreen)
                Spacer()
                Circle()
                    .fill(entry.status.modelLoaded ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
            }
            
            Text("ZeroDark")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(entry.status.modelName)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            if entry.meshPeerCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.caption2)
                    Text("\(entry.meshPeerCount)")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Medium Widget (Quick Actions)

struct ZeroDarkMediumWidget: View {
    var entry: ZeroDarkEntry
    
    var body: some View {
        HStack(spacing: 16) {
            // Status Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "brain")
                        .font(.title)
                        .foregroundColor(ZDDesign.forestGreen)
                    VStack(alignment: .leading) {
                        Text("ZeroDark")
                            .font(.headline)
                        Text(entry.status.modelName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    StatBadge(icon: "brain.head.profile", value: "\(entry.memoryCount)", label: "memories")
                    if entry.meshPeerCount > 0 {
                        StatBadge(icon: "person.2", value: "\(entry.meshPeerCount)", label: "peers")
                    }
                }
            }
            
            Divider()
            
            // Quick Actions (LLM removed - tactical only)
            VStack(spacing: 8) {
                Text("Tactical Mode")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct StatBadge: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(value)
                .font(.caption.bold())
        }
        .foregroundColor(.secondary)
    }
}

struct QuickActionButton<Intent: AppIntent>: View {
    let intent: Intent
    let icon: String
    let label: String
    
    var body: some View {
        Button(intent: intent) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(ZDDesign.forestGreen.opacity(0.2))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Large Widget (Full Dashboard)

struct ZeroDarkLargeWidget: View {
    var entry: ZeroDarkEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "brain")
                    .font(.title)
                    .foregroundColor(ZDDesign.forestGreen)
                VStack(alignment: .leading) {
                    Text("ZeroDark")
                        .font(.headline)
                    Text("100% On-Device AI")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Circle()
                    .fill(entry.status.modelLoaded ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
            }
            
            Divider()
            
            // Stats Row
            HStack(spacing: 16) {
                StatCard(icon: "cpu", title: entry.status.modelName, subtitle: "Active Model")
                StatCard(icon: "brain.head.profile", title: "\(entry.memoryCount)", subtitle: "Memories")
                StatCard(icon: "antenna.radiowaves.left.and.right", title: "\(entry.meshPeerCount)", subtitle: "Mesh Peers")
            }
            
            Divider()
            
            // Quick Actions Grid (LLM removed - tactical only)
            VStack {
                Text("Tactical System Active")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct StatCard: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(title)
                .font(.caption.bold())
                .lineLimit(1)
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct WidgetActionTile<Intent: AppIntent>: View {
    let intent: Intent
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        Button(intent: intent) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(0.15))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Lock Screen Widget (Accessory)

struct ZeroDarkAccessoryWidget: View {
    var entry: ZeroDarkEntry
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "brain")
            Text(entry.status.modelLoaded ? "Ready" : "Off")
                .font(.caption2)
        }
    }
}

// MARK: - Widget Configuration

struct ZeroDarkWidget: Widget {
    let kind: String = "ZeroDarkWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ZeroDarkTimelineProvider()) { entry in
            ZeroDarkWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("ZeroDark")
        .description("On-device AI assistant status and quick actions")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
    }
}

struct ZeroDarkWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: ZeroDarkEntry
    
    var body: some View {
        switch family {
        case .systemSmall:
            ZeroDarkSmallWidget(entry: entry)
        case .systemMedium:
            ZeroDarkMediumWidget(entry: entry)
        case .systemLarge:
            ZeroDarkLargeWidget(entry: entry)
        case .accessoryCircular, .accessoryRectangular:
            ZeroDarkAccessoryWidget(entry: entry)
        @unknown default:
            ZeroDarkSmallWidget(entry: entry)
        }
    }
}
