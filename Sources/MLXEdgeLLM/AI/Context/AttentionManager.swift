import Foundation
import SwiftUI
import CoreLocation

// MARK: - AttentionManager

final class AttentionManager: ObservableObject {
    @Published var priorities: [ContextPriority] = []
    
    func boostPriority(for context: Context) {
        if let index = priorities.firstIndex(where: { $0.context.id == context.id }) {
            priorities[index].importance += 1
        } else {
            priorities.append(ContextPriority(context: context, importance: 1))
        }
        priorities.sort { $0.importance > $1.importance }
    }
    
    func demotePriority(for context: Context) {
        if let index = priorities.firstIndex(where: { $0.context.id == context.id }) {
            priorities[index].importance -= 1
            priorities.sort { $0.importance > $1.importance }
        }
    }
    
    func resetPriority(for context: Context) {
        if let index = priorities.firstIndex(where: { $0.context.id == context.id }) {
            priorities[index].importance = 0
            priorities.sort { $0.importance > $1.importance }
        }
    }
}

// MARK: - ContextPriority

struct ContextPriority: Identifiable {
    let id = UUID()
    let context: Context
    var importance: Int
}

// MARK: - Context

struct Context: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let location: CLLocationCoordinate2D?
    let timestamp: Date
}

// MARK: - SwiftUI View

struct AttentionManagerView: View {
    @StateObject private var attentionManager = AttentionManager()
    
    var body: some View {
        List(attentionManager.priorities) { priority in
            VStack(alignment: .leading) {
                Text(priority.context.title)
                    .font(.headline)
                Text(priority.context.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Importance: \(priority.importance)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .contextMenu {
                Button(action: {
                    attentionManager.boostPriority(for: priority.context)
                }) {
                    Label("Boost Priority", systemImage: "arrow.up.circle")
                }
                Button(action: {
                    attentionManager.demotePriority(for: priority.context)
                }) {
                    Label("Demote Priority", systemImage: "arrow.down.circle")
                }
                Button(action: {
                    attentionManager.resetPriority(for: priority.context)
                }) {
                    Label("Reset Priority", systemImage: "xmark.circle")
                }
            }
        }
        .navigationTitle("Attention Manager")
    }
}

// MARK: - Preview

struct AttentionManagerView_Previews: PreviewProvider {
    static var previews: some View {
        AttentionManagerView()
    }
}