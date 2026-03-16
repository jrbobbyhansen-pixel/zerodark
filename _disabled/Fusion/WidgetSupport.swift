import Foundation
import WidgetKit
import SwiftUI

// MARK: - Widget Support

/// Zero Dark widgets for Home Screen and Lock Screen
/// Quick AI access without opening the app

// MARK: - Widget Entry

public struct ZeroDarkEntry: TimelineEntry {
    public let date: Date
    public let prompt: String?
    public let response: String?
    public let quickActions: [QuickAction]
    
    public struct QuickAction: Identifiable {
        public let id = UUID()
        public let title: String
        public let icon: String
        public let prompt: String
    }
    
    public static var placeholder: ZeroDarkEntry {
        ZeroDarkEntry(
            date: Date(),
            prompt: nil,
            response: "Ask me anything...",
            quickActions: defaultActions
        )
    }
    
    public static var defaultActions: [QuickAction] {
        [
            QuickAction(title: "Daily Brief", icon: "sun.max", prompt: "Give me a brief summary of what I should know today"),
            QuickAction(title: "Quick Note", icon: "note.text", prompt: "Help me write a quick note"),
            QuickAction(title: "Translate", icon: "globe", prompt: "Translate: "),
            QuickAction(title: "Calculate", icon: "function", prompt: "Calculate: ")
        ]
    }
}

// MARK: - Widget Provider

public struct ZeroDarkProvider: TimelineProvider {
    
    public func placeholder(in context: Context) -> ZeroDarkEntry {
        .placeholder
    }
    
    public func getSnapshot(in context: Context, completion: @escaping (ZeroDarkEntry) -> Void) {
        completion(.placeholder)
    }
    
    public func getTimeline(in context: Context, completion: @escaping (Timeline<ZeroDarkEntry>) -> Void) {
        // Generate timeline with daily updates
        let currentDate = Date()
        
        // Get last conversation summary or greeting
        let greeting = getTimeBasedGreeting()
        
        let entry = ZeroDarkEntry(
            date: currentDate,
            prompt: nil,
            response: greeting,
            quickActions: ZeroDarkEntry.defaultActions
        )
        
        // Update every hour
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: currentDate)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        
        completion(timeline)
    }
    
    private func getTimeBasedGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        
        switch hour {
        case 5..<12:
            return "Good morning. What can I help with?"
        case 12..<17:
            return "Good afternoon. What's on your mind?"
        case 17..<21:
            return "Good evening. How can I assist?"
        default:
            return "Hello. I'm here when you need me."
        }
    }
}

// MARK: - Small Widget View

public struct ZeroDarkSmallWidget: View {
    let entry: ZeroDarkEntry
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "brain")
                    .font(.title2)
                    .foregroundColor(.cyan)
                Text("Zero Dark")
                    .font(.headline)
            }
            
            Text(entry.response ?? "Ask me anything")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(3)
            
            Spacer()
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Medium Widget View

public struct ZeroDarkMediumWidget: View {
    let entry: ZeroDarkEntry
    
    public var body: some View {
        HStack(spacing: 12) {
            // Left side - greeting
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "brain")
                        .font(.title2)
                        .foregroundColor(.cyan)
                    Text("Zero Dark")
                        .font(.headline)
                }
                
                Text(entry.response ?? "Ask me anything")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                
                Spacer()
            }
            
            Divider()
            
            // Right side - quick actions
            VStack(alignment: .leading, spacing: 8) {
                ForEach(entry.quickActions.prefix(4)) { action in
                    Link(destination: URL(string: "zerodark://ask?q=\(action.prompt.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!) {
                        HStack {
                            Image(systemName: action.icon)
                                .foregroundColor(.cyan)
                                .frame(width: 20)
                            Text(action.title)
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Large Widget View

public struct ZeroDarkLargeWidget: View {
    let entry: ZeroDarkEntry
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain")
                    .font(.title)
                    .foregroundColor(.cyan)
                
                VStack(alignment: .leading) {
                    Text("Zero Dark")
                        .font(.headline)
                    Text(entry.response ?? "Your AI assistant")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Divider()
            
            // Quick actions grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(entry.quickActions) { action in
                    Link(destination: URL(string: "zerodark://ask?q=\(action.prompt.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!) {
                        HStack {
                            Image(systemName: action.icon)
                                .foregroundColor(.cyan)
                            Text(action.title)
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
            
            Spacer()
            
            // Text input hint
            HStack {
                Image(systemName: "text.cursor")
                    .foregroundColor(.secondary)
                Text("Tap to ask anything...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Lock Screen Widget

public struct ZeroDarkLockScreenWidget: View {
    let entry: ZeroDarkEntry
    
    public var body: some View {
        HStack {
            Image(systemName: "brain")
                .foregroundColor(.cyan)
            Text("Zero Dark")
                .font(.caption)
        }
    }
}

// MARK: - Widget Bundle

/*
 To add widgets to your app:
 
 1. File → New → Target → Widget Extension
 2. Name it "ZeroDarkWidgets"
 3. Use this code:
 
 @main
 struct ZeroDarkWidgets: WidgetBundle {
     var body: some Widget {
         ZeroDarkMainWidget()
         ZeroDarkQuickWidget()
         ZeroDarkLockScreenWidget()
     }
 }
 
 struct ZeroDarkMainWidget: Widget {
     let kind: String = "ZeroDarkWidget"
     
     var body: some WidgetConfiguration {
         StaticConfiguration(kind: kind, provider: ZeroDarkProvider()) { entry in
             ZeroDarkWidgetView(entry: entry)
         }
         .configurationDisplayName("Zero Dark")
         .description("Quick AI access")
         .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
     }
 }
*/
